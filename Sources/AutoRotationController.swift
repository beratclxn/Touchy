import AppKit
import CoreGraphics
import Foundation
import IOKit

private typealias IOAVServiceRef = CFTypeRef

@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer,
    _ outputBufferSize: UInt32
) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn

/// Polls external display hardware G-sensor via VESA DDC/CI (`VCP 0xAA` Screen Orientation)
/// and rotates the macOS display + touch coordinate space via `MonitorPanel.framework`.
final class AutoRotationController {
    private let mapper: DisplayMapper
    private let queue = DispatchQueue(label: "com.beratclxn.touchy.autorotate", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var avService: IOAVServiceRef?
    private var pendingAngle: Int?
    private var lastAppliedAngle: Int?
    private var lastRotationTimestamp: TimeInterval = 0

    var onOrientationDetected: ((Int?) -> Void)?

    private enum DDC {
        static let chipAddress: UInt32 = 0x37
        static let dataAddress: UInt32 = 0x51
        static let vcpScreenOrientation: UInt8 = 0xAA
        static let vcpAutoRotationEnable: UInt8 = 0xEA
    }

    init(mapper: DisplayMapper) {
        self.mapper = mapper
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW)
    }

    func start() {
        stop()
        DispatchQueue.main.async {
            Self.restoreBuiltInDisplayIfRotated()
        }
        guard Settings.shared.autoRotate else {
            DispatchQueue.main.async { [weak self] in self?.onOrientationDetected?(nil) }
            return
        }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 0.5, repeating: 1.5)
        source.setEventHandler { [weak self] in
            self?.pollSensor()
        }
        timer = source
        source.resume()
        Log.write("Auto-Rotate DDC monitor started", force: true)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.avService = nil
            self?.pendingAngle = nil
        }
    }

    func refreshNow() {
        queue.async { [weak self] in
            self?.lastAppliedAngle = nil
            self?.pollSensor()
        }
    }

    // MARK: - DDC/CI Polling

    private func pollSensor() {
        guard Settings.shared.autoRotate else { return }

        let now = ProcessInfo.processInfo.systemUptime
        // Allow WindowServer time to settle after a mode/orientation switch.
        guard now - lastRotationTimestamp >= 2.5 else { return }

        if avService == nil {
            avService = Self.findExternalAVService()
            if let service = avService {
                // Ensure the display OSD "Auto Rotation" toggle (VCP 0xEA) is enabled when supported.
                Self.writeVCP(avService: service, vcp: DDC.vcpAutoRotationEnable, value: 1)
            }
        }

        guard let service = avService else {
            DispatchQueue.main.async { [weak self] in self?.onOrientationDetected?(nil) }
            return
        }

        guard let rawCode = Self.readVCP(avService: service, vcp: DDC.vcpScreenOrientation) else {
            // Re-acquire IOAVService on next tick if the display link was reset.
            avService = nil
            return
        }

        guard let targetAngle = Self.angle(forVCPValue: UInt8(rawCode & 0xFF), invertPortrait: Settings.shared.invertAutoRotate) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onOrientationDetected?(targetAngle)
        }

        // Require 2 consecutive matching samples to debounce brief physical bumps.
        guard pendingAngle == targetAngle else {
            pendingAngle = targetAngle
            return
        }

        guard lastAppliedAngle != targetAngle else { return }
        lastAppliedAngle = targetAngle

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Self.restoreBuiltInDisplayIfRotated()

            if self.mapper.displayID == nil {
                self.mapper.refresh()
            }
            guard let displayID = self.mapper.displayID,
                  CGDisplayIsBuiltin(displayID) == 0 else { return }
            let currentHW = Int(CGDisplayRotation(displayID).rounded())
            guard currentHW != targetAngle else { return }

            if Self.setMacOSDisplayOrientation(displayID: displayID, degrees: targetAngle) {
                self.lastRotationTimestamp = ProcessInfo.processInfo.systemUptime
                Log.write("Auto-Rotate applied external display (\(displayID)) orientation: \(targetAngle)° (from VCP 0xAA=\(rawCode))", force: true)
            }
        }
    }

    private static func angle(forVCPValue code: UInt8, invertPortrait: Bool) -> Int? {
        switch code {
        case 0x01: return 0
        case 0x02: return invertPortrait ? 270 : 90
        case 0x03: return 180
        case 0x04: return invertPortrait ? 90 : 270
        default:   return nil
        }
    }

    // MARK: - IOAVService DDC/CI Helpers

    private static func findExternalAVService() -> IOAVServiceRef? {
        let matching = IOServiceMatching("DCPAVServiceProxy")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            let location = IORegistryEntryCreateCFProperty(
                service,
                "Location" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String
            if location == "External",
               let av = IOAVServiceCreateWithService(kCFAllocatorDefault, service)?.takeRetainedValue() {
                return av
            }
        }
        return nil
    }

    private static func readVCP(avService: IOAVServiceRef, vcp: UInt8) -> UInt16? {
        for _ in 0..<2 {
            var packet: [UInt8] = [0x82, 0x01, vcp, 0x00]
            packet[3] = 0x6E ^ UInt8(DDC.dataAddress) ^ packet[0] ^ packet[1] ^ packet[2]

            guard IOAVServiceWriteI2C(avService, DDC.chipAddress, DDC.dataAddress, &packet, UInt32(packet.count)) == kIOReturnSuccess else {
                usleep(30_000)
                continue
            }
            usleep(45_000)

            var reply = [UInt8](repeating: 0, count: 11)
            guard IOAVServiceReadI2C(avService, DDC.chipAddress, DDC.dataAddress, &reply, UInt32(reply.count)) == kIOReturnSuccess else {
                usleep(30_000)
                continue
            }

            // Valid VCP Get Feature Reply: [0x51/0x6E, 0x88, 0x02, resultCode(0=OK), vcpCode, type, mh, ml, sh, sl, chk]
            if reply[2] == 0x02 && reply[3] == 0x00 && reply[4] == vcp {
                return (UInt16(reply[8]) << 8) | UInt16(reply[9])
            }
            usleep(25_000)
        }
        return nil
    }

    private static func writeVCP(avService: IOAVServiceRef, vcp: UInt8, value: UInt16) {
        let hi = UInt8((value >> 8) & 0xFF)
        let lo = UInt8(value & 0xFF)
        var packet: [UInt8] = [0x84, 0x03, vcp, hi, lo, 0x00]
        packet[5] = 0x6E ^ UInt8(DDC.dataAddress) ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        _ = IOAVServiceWriteI2C(avService, DDC.chipAddress, DDC.dataAddress, &packet, UInt32(packet.count))
        usleep(50_000)
    }

    // MARK: - MonitorPanel Framework Display Rotation

    /// Safety guard: ensures the MacBook's built-in screen is never left rotated by an external sensor event.
    static func restoreBuiltInDisplayIfRotated() {
        for screen in DisplayMapper.screens() where screen.builtIn {
            let rot = Int(CGDisplayRotation(screen.id).rounded())
            if rot != 0 {
                guard let mgrClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return }
                let manager = mgrClass.init()
                guard let displays = manager.value(forKey: "displays") as? [NSObject] else { return }
                for display in displays {
                    guard let idNum = display.value(forKey: "displayID") as? NSNumber,
                          CGDirectDisplayID(idNum.uint32Value) == screen.id else { continue }
                    display.setValue(NSNumber(value: 0), forKey: "orientation")
                    Log.write("Restored Built-in Display (\(screen.id)) orientation to 0°", force: true)
                }
            }
        }
    }

    @discardableResult
    static func setMacOSDisplayOrientation(displayID: CGDirectDisplayID, degrees: Int) -> Bool {
        // Strictly refuse to rotate built-in displays; orientation only applies to external displays.
        guard CGDisplayIsBuiltin(displayID) == 0 else {
            Log.write("Refused to rotate built-in display \(displayID)", force: true)
            return false
        }
        guard let mgrClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return false }
        let manager = mgrClass.init()
        guard let displays = manager.value(forKey: "displays") as? [NSObject] else { return false }

        for display in displays {
            guard let idNum = display.value(forKey: "displayID") as? NSNumber,
                  CGDirectDisplayID(idNum.uint32Value) == displayID else { continue }
            let isBuiltIn = (display.value(forKey: "isBuiltIn") as? NSNumber)?.boolValue ?? false
            guard !isBuiltIn else {
                Log.write("Refused MPDisplay orientation change on built-in display \(displayID)", force: true)
                return false
            }
            let canChange = (display.value(forKey: "canChangeOrientation") as? NSNumber)?.boolValue ?? false
            guard canChange else { return false }
            display.setValue(NSNumber(value: degrees), forKey: "orientation")
            return true
        }
        return false
    }
}
