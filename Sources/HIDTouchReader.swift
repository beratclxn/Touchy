import Foundation
import IOKit
import IOKit.hid

/// Single touch or stylus contact normalized to `0...1` in the panel's native coordinate space.
struct RawContact {
    let id: Int
    let x: Double
    let y: Double
    let size: Double
    let isStylus: Bool
}

protocol TouchReaderDelegate: AnyObject {
    func touchReader(_ reader: HIDTouchReader, didReceive contacts: [RawContact])
    func touchReaderDevicesChanged(_ reader: HIDTouchReader)
}

private enum HIDUsage {
    static let pageGenericDesktop = 0x01
    static let pageDigitizer = 0x0D

    static let x = 0x30
    static let y = 0x31

    static let pen = 0x02
    static let touchScreen = 0x04
    static let stylus = 0x20
    static let inRange = 0x32
    static let tipSwitch = 0x42
    static let confidence = 0x47
    static let width = 0x48
    static let height = 0x49
    static let contactID = 0x51
    static let deviceMode = 0x52
    static let contactCount = 0x54
    static let contactCountMax = 0x55

    static let appleVendorID = 0x05AC
}

/// Logical finger or stylus collection inside a multi-touch HID report descriptor.
private final class TouchSlot {
    enum Field { case tip, inRange, confidence, contactID, x, y, width, height }

    let index: Int
    var reportID: UInt32 = 0
    var isStylus = false
    var hasTip = false, hasInRange = false, hasConfidence = false, hasContactID = false
    var hasX = false, hasY = false, hasWidth = false, hasHeight = false
    var xMin = 0, xMax = 1, yMin = 0, yMax = 1
    var widthMin = 0, widthMax = 1, heightMin = 0, heightMax = 1

    var tip = 0, inRange = 0, confidence = 1, contactID = 0, x = 0, y = 0, width = 0, height = 0
    var lastUpdatedTimestamp: UInt64 = 0
    var tipElement: IOHIDElement?
    var inRangeElement: IOHIDElement?

    init(index: Int) { self.index = index }

    var isValid: Bool { hasX && hasY && (hasTip || hasInRange) }

    var normalizedSize: Double {
        let nw = hasWidth ? Double(width - widthMin) / Double(max(1, widthMax - widthMin)) : 0.0
        let nh = hasHeight ? Double(height - heightMin) / Double(max(1, heightMax - heightMin)) : 0.0
        return min(max(max(nw, nh), 0.0), 1.0)
    }

    var isTouching: Bool {
        let down = hasTip ? (tip != 0) : (inRange != 0)
        let confident = hasConfidence ? (confidence != 0) : true
        return down && confident
    }

    @inline(__always)
    func set(_ field: Field, _ value: Int) {
        switch field {
        case .tip: tip = value
        case .inRange: inRange = value
        case .confidence: confidence = value
        case .contactID: contactID = value
        case .x: x = value
        case .y: y = value
        case .width: width = value
        case .height: height = value
        }
    }

    var contact: RawContact {
        let nx = Double(x - xMin) / Double(max(1, xMax - xMin))
        let ny = Double(y - yMin) / Double(max(1, yMax - yMin))
        return RawContact(
            id: hasContactID ? contactID : (isStylus ? 900 + index : index),
            x: min(max(nx, 0.0), 1.0),
            y: min(max(ny, 0.0), 1.0),
            size: normalizedSize,
            isStylus: isStylus
        )
    }
}

/// Parses HID digitizer reports for a single physical touch screen.
final class TouchDeviceHandler {
    let device: IOHIDDevice
    let name: String
    let vendorID: Int
    let productID: Int

    private var slots: [TouchSlot] = []
    private var slotsByReportID: [UInt32: [TouchSlot]] = [:]
    private var cookieMap: [IOHIDElementCookie: (TouchSlot, TouchSlot.Field)] = [:]
    private var contactCountCookie: IOHIDElementCookie?
    private var contactCountElement: IOHIDElement?
    private var contactCountReportID: UInt32 = 0
    private var contactCount = 0
    private var maxContactsLogical = 0

    // Packet assembly state
    private var pendingTimestamp: UInt64?
    private var pendingReportID: UInt32 = 0
    private var flushScheduled = false
    private var hybridFrame: [Int: RawContact] = [:]
    private var hybridRemaining = 0
    private var activeStrokeReports = 0
    private var liftWatchdogWorkItem: DispatchWorkItem?

    var onFrame: (([RawContact]) -> Void)?

    init(device: IOHIDDevice) {
        self.device = device
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let manufacturer = (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !manufacturer.isEmpty && !product.isEmpty && !product.localizedCaseInsensitiveContains(manufacturer) {
            self.name = "\(manufacturer) \(product)"
        } else if !product.isEmpty {
            self.name = product
        } else if !manufacturer.isEmpty {
            self.name = "\(manufacturer) Touch Display"
        } else {
            self.name = "USB Touch Display"
        }
        self.vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        self.productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        buildSlots()
    }

    var slotCount: Int { slots.count }
    var hasContactCount: Bool { contactCountCookie != nil }

    // MARK: - Descriptor Parsing

    private static func applicationCollection(of element: IOHIDElement) -> IOHIDElement? {
        var current: IOHIDElement? = IOHIDElementGetParent(element)
        while let collection = current {
            if IOHIDElementGetCollectionType(collection) == kIOHIDElementCollectionTypeApplication {
                return collection
            }
            current = IOHIDElementGetParent(collection)
        }
        return nil
    }

    private func configureFeatureElement(_ element: IOHIDElement, usage: Int) {
        if usage == HIDUsage.deviceMode {
            let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, mach_absolute_time(), 2)
            let status = IOHIDDeviceSetValue(device, element, value)
            Log.write("Device Mode=2 feature set result: \(status)")
        } else if usage == HIDUsage.contactCountMax {
            // Querying Contact Count Maximum (0x55) activates multi-touch reporting on HID-MT controllers.
            maxContactsLogical = IOHIDElementGetLogicalMax(element)
            let reportID = CFIndex(IOHIDElementGetReportID(element))
            var buffer = [UInt8](repeating: 0, count: 16)
            var length: CFIndex = buffer.count
            if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, &buffer, &length) == kIOReturnSuccess,
               length >= 2, buffer[1] > 0 {
                maxContactsLogical = Int(buffer[1])
            }
        }
    }

    private func buildSlots() {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return
        }

        var slotByParent: [IOHIDElementCookie: TouchSlot] = [:]
        var parentOrder: [IOHIDElementCookie] = []
        let inputTypes: Set<UInt32> = [
            kIOHIDElementTypeInput_Misc.rawValue,
            kIOHIDElementTypeInput_Button.rawValue,
            kIOHIDElementTypeInput_Axis.rawValue,
            kIOHIDElementTypeInput_ScanCodes.rawValue,
        ]

        for element in elements {
            let type = IOHIDElementGetType(element).rawValue
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))

            if type == kIOHIDElementTypeFeature.rawValue && page == HIDUsage.pageDigitizer {
                configureFeatureElement(element, usage: usage)
                continue
            }
            guard inputTypes.contains(type),
                  let app = Self.applicationCollection(of: element),
                  Int(IOHIDElementGetUsagePage(app)) == HIDUsage.pageDigitizer else { continue }

            let appUsage = Int(IOHIDElementGetUsage(app))
            guard appUsage == HIDUsage.touchScreen || appUsage == HIDUsage.pen else { continue }

            if page == HIDUsage.pageDigitizer && usage == HIDUsage.contactCount {
                if contactCountCookie == nil {
                    contactCountCookie = IOHIDElementGetCookie(element)
                    contactCountElement = element
                    contactCountReportID = IOHIDElementGetReportID(element)
                }
                continue
            }

            guard let field = Self.resolveField(page: page, usage: usage),
                  let parent = IOHIDElementGetParent(element) else { continue }

            let parentCookie = IOHIDElementGetCookie(parent)
            let parentUsage = Int(IOHIDElementGetUsage(parent))
            let slot: TouchSlot
            if let existing = slotByParent[parentCookie] {
                slot = existing
            } else {
                slot = TouchSlot(index: parentOrder.count)
                slot.reportID = IOHIDElementGetReportID(element)
                slot.isStylus = (appUsage == HIDUsage.pen || parentUsage == HIDUsage.stylus || parentUsage == HIDUsage.pen)
                slotByParent[parentCookie] = slot
                parentOrder.append(parentCookie)
            }

            guard registerField(field, element: element, into: slot) else { continue }
            cookieMap[IOHIDElementGetCookie(element)] = (slot, field)
        }

        slots = parentOrder.compactMap { slotByParent[$0] }.filter { $0.isValid }
        slotsByReportID = Dictionary(grouping: slots, by: { $0.reportID })
        let validIDs = Set(slots.map { ObjectIdentifier($0) })
        cookieMap = cookieMap.filter { validIDs.contains(ObjectIdentifier($0.value.0)) }

        Log.write("Device \(name) slots=\(slots.count) contactCount=\(contactCountCookie != nil) maxContacts=\(maxContactsLogical)", force: true)
    }

    private static func resolveField(page: Int, usage: Int) -> TouchSlot.Field? {
        switch (page, usage) {
        case (HIDUsage.pageGenericDesktop, HIDUsage.x): return .x
        case (HIDUsage.pageGenericDesktop, HIDUsage.y): return .y
        case (HIDUsage.pageDigitizer, HIDUsage.tipSwitch): return .tip
        case (HIDUsage.pageDigitizer, HIDUsage.inRange): return .inRange
        case (HIDUsage.pageDigitizer, HIDUsage.confidence): return .confidence
        case (HIDUsage.pageDigitizer, HIDUsage.contactID): return .contactID
        case (HIDUsage.pageDigitizer, HIDUsage.width): return .width
        case (HIDUsage.pageDigitizer, HIDUsage.height): return .height
        default: return nil
        }
    }

    private func registerField(_ field: TouchSlot.Field, element: IOHIDElement, into slot: TouchSlot) -> Bool {
        switch field {
        case .x:
            guard !slot.hasX else { return false }
            slot.hasX = true
            slot.xMin = IOHIDElementGetLogicalMin(element)
            slot.xMax = IOHIDElementGetLogicalMax(element)
        case .y:
            guard !slot.hasY else { return false }
            slot.hasY = true
            slot.yMin = IOHIDElementGetLogicalMin(element)
            slot.yMax = IOHIDElementGetLogicalMax(element)
        case .width:
            guard !slot.hasWidth else { return false }
            slot.hasWidth = true
            slot.widthMin = IOHIDElementGetLogicalMin(element)
            slot.widthMax = IOHIDElementGetLogicalMax(element)
        case .height:
            guard !slot.hasHeight else { return false }
            slot.hasHeight = true
            slot.heightMin = IOHIDElementGetLogicalMin(element)
            slot.heightMax = IOHIDElementGetLogicalMax(element)
        case .tip:
            guard !slot.hasTip else { return false }
            slot.hasTip = true
            slot.tipElement = element
        case .inRange:
            guard !slot.hasInRange else { return false }
            slot.hasInRange = true
            slot.inRangeElement = element
        case .confidence:
            guard !slot.hasConfidence else { return false }
            slot.hasConfidence = true
        case .contactID:
            guard !slot.hasContactID else { return false }
            slot.hasContactID = true
        }

        // Seed initial state from the kernel's cached element value so delta-only IOHIDValue callbacks
        // never miss unchanged coordinates or contact IDs on the first touch.
        let dummy = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
        var valRef = Unmanaged<IOHIDValue>.passUnretained(dummy)
        if IOHIDDeviceGetValue(device, element, &valRef) == kIOReturnSuccess {
            let value = valRef.takeUnretainedValue()
            switch field {
            case .x:
                slot.x = extractAxisValue(value, element: element, maxLogical: slot.xMax)
            case .y:
                slot.y = extractAxisValue(value, element: element, maxLogical: slot.yMax)
            case .contactID:
                slot.contactID = IOHIDValueGetIntegerValue(value)
            case .confidence:
                slot.confidence = IOHIDValueGetIntegerValue(value)
            default:
                break
            }
        }
        return true
    }

    var diagnostics: String {
        var out = "Device: \(name)\nVID: 0x\(String(vendorID, radix: 16)) PID: 0x\(String(productID, radix: 16))\n"
        out += "Finger slots: \(slots.count), Contact Count: \(hasContactCount ? "yes" : "no"), Max contacts: \(maxContactsLogical)\n"
        for slot in slots {
            out += "  slot \(slot.index): rid=\(slot.reportID) stylus=\(slot.isStylus) X[\(slot.xMin)…\(slot.xMax)] Y[\(slot.yMin)…\(slot.yMax)] tip=\(slot.hasTip) inRange=\(slot.hasInRange) conf=\(slot.hasConfidence) size=\(slot.hasWidth || slot.hasHeight) id=\(slot.hasContactID)\n"
        }
        return out
    }

    // MARK: - Input Value Decoding

    /// Extracts axis coordinates safely when a digitizer descriptor groups multiple 16-bit words (`ReportCount > 1` or 4-byte value)
    /// into a single element (`ReportSize=16, ReportCount=2`).
    @inline(__always)
    private func extractAxisValue(_ value: IOHIDValue, element: IOHIDElement, maxLogical: Int) -> Int {
        let count = IOHIDElementGetReportCount(element)
        let length = IOHIDValueGetLength(value)
        if (count > 1 || length >= 4) && length >= 2 {
            let ptr = IOHIDValueGetBytePtr(value)
            if length >= 4 {
                let w0 = Int(ptr[0]) | (Int(ptr[1]) << 8)
                if w0 > 0 && w0 <= maxLogical { return w0 }
                let w1 = Int(ptr[2]) | (Int(ptr[3]) << 8)
                if w1 > 0 && w1 <= maxLogical { return w1 }
                return w0 & 0xFFFF
            } else if length == 2 {
                return Int(ptr[0]) | (Int(ptr[1]) << 8)
            } else if length == 1 {
                return Int(ptr[0])
            }
        }
        return IOHIDValueGetIntegerValue(value)
    }

    func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let timestamp = IOHIDValueGetTimeStamp(value)
        let reportID = IOHIDElementGetReportID(element)

        if let pending = pendingTimestamp, pending != timestamp || reportID != pendingReportID {
            processReport()
        }
        pendingTimestamp = timestamp
        pendingReportID = reportID

        let cookie = IOHIDElementGetCookie(element)
        if cookie == contactCountCookie {
            contactCount = IOHIDValueGetIntegerValue(value)
            if contactCount == 0, let reportSlots = slotsByReportID[reportID] {
                for slot in reportSlots {
                    slot.tip = 0
                    slot.inRange = 0
                }
            }
        } else if let (slot, field) = cookieMap[cookie] {
            let decoded: Int
            switch field {
            case .x:
                decoded = extractAxisValue(value, element: element, maxLogical: slot.xMax)
            case .y:
                decoded = extractAxisValue(value, element: element, maxLogical: slot.yMax)
            default:
                decoded = IOHIDValueGetIntegerValue(value)
            }
            slot.set(field, decoded)
            slot.lastUpdatedTimestamp = timestamp
        }

        if !flushScheduled {
            flushScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.flushScheduled = false
                if self.pendingTimestamp != nil { self.processReport() }
            }
        }
    }

    @inline(__always)
    private func refreshTipState(for slot: TouchSlot) {
        if let tipElem = slot.tipElement {
            let dummy = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, tipElem, 0, 0)
            var valRef = Unmanaged<IOHIDValue>.passUnretained(dummy)
            if IOHIDDeviceGetValue(device, tipElem, &valRef) == kIOReturnSuccess {
                slot.tip = IOHIDValueGetIntegerValue(valRef.takeUnretainedValue())
            }
        }
        if let inRangeElem = slot.inRangeElement {
            let dummy = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, inRangeElem, 0, 0)
            var valRef = Unmanaged<IOHIDValue>.passUnretained(dummy)
            if IOHIDDeviceGetValue(device, inRangeElem, &valRef) == kIOReturnSuccess {
                slot.inRange = IOHIDValueGetIntegerValue(valRef.takeUnretainedValue())
            }
        }
    }

    private func processReport() {
        let reportID = pendingReportID
        let reportTimestamp = pendingTimestamp ?? 0
        pendingTimestamp = nil

        guard let reportSlots = slotsByReportID[reportID], !reportSlots.isEmpty else { return }

        // Refresh tip/inRange state from the kernel for any slot that did not emit a delta value callback
        // in this report timestamp, preventing missed TipSwitch=0 transitions from leaving a finger stuck down.
        for slot in reportSlots where slot.isTouching && slot.lastUpdatedTimestamp != reportTimestamp {
            refreshTipState(for: slot)
        }

        // Hybrid multi-packet mode (used only when hardware splits contacts across multiple packets).
        if contactCountCookie != nil && contactCountReportID == reportID && maxContactsLogical > reportSlots.count {
            if contactCount > 0 {
                hybridFrame.removeAll(keepingCapacity: true)
                hybridRemaining = contactCount
            }
            if hybridRemaining > 0 {
                for slot in reportSlots where slot.isTouching {
                    let contact = slot.contact
                    hybridFrame[contact.id] = contact
                }
                hybridRemaining -= reportSlots.count
                if hybridRemaining <= 0 {
                    emit(hybridFrame.values.sorted { $0.id < $1.id })
                }
                return
            }
        }

        // Parallel mode (all 10 finger slots fit in a single report):
        // Do not gate on `contactCount` because macOS IOHIDManager only fires value callbacks when an element changes,
        // and ELAN controllers keep Contact Count (0x54) == 1 across both touch-down and lift-off reports.
        // Instead, each slot's individual Tip Switch (0x42) accurately tracks whether that finger is touching.
        var contacts: [RawContact] = []
        contacts.reserveCapacity(reportSlots.count)
        for slot in reportSlots where slot.isTouching {
            let contact = slot.contact
            if let existingIndex = contacts.firstIndex(where: { $0.id == contact.id }) {
                contacts[existingIndex] = contact
            } else {
                contacts.append(contact)
            }
        }
        emit(contacts)
    }

    private func emit(_ contacts: [RawContact]) {
        liftWatchdogWorkItem?.cancel()
        liftWatchdogWorkItem = nil

        if contacts.isEmpty {
            activeStrokeReports = 0
        } else {
            activeStrokeReports += 1
            let watchdog = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let countElem = self.contactCountElement {
                    let dummy = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, countElem, 0, 0)
                    var valRef = Unmanaged<IOHIDValue>.passUnretained(dummy)
                    if IOHIDDeviceGetValue(self.device, countElem, &valRef) == kIOReturnSuccess {
                        self.contactCount = IOHIDValueGetIntegerValue(valRef.takeUnretainedValue())
                    }
                }
                for slot in self.slots where slot.isTouching {
                    self.refreshTipState(for: slot)
                    if self.contactCount == 0 || self.activeStrokeReports <= 6 {
                        slot.tip = 0
                        slot.inRange = 0
                    }
                }
                let remaining = self.slots.filter { $0.isTouching }.map { $0.contact }
                if remaining.isEmpty {
                    self.activeStrokeReports = 0
                    self.onFrame?([])
                }
            }
            liftWatchdogWorkItem = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.095, execute: watchdog)
        }

        if Settings.shared.debugLog {
            Log.write("frame: " + contacts.map { "#\($0.id)(\(String(format: "%.3f", $0.x)),\(String(format: "%.3f", $0.y)),sz=\(String(format: "%.2f", $0.size)))" }.joined(separator: " "))
        }
        onFrame?(contacts)
    }
}

/// Discovers USB-C HID digitizer devices and streams normalized contact frames.
final class HIDTouchReader {
    weak var delegate: TouchReaderDelegate?
    private var manager: IOHIDManager?
    private(set) var handlers: [IOHIDDevice: TouchDeviceHandler] = [:]
    private(set) var lastOpenResult: IOReturn = kIOReturnSuccess

    func start(seize: Bool) {
        stop()
        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: HIDUsage.pageDigitizer, kIOHIDDeviceUsageKey: HIDUsage.touchScreen],
            [kIOHIDDeviceUsagePageKey: HIDUsage.pageDigitizer, kIOHIDDeviceUsageKey: HIDUsage.pen],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDTouchReader>.fromOpaque(ctx).takeUnretainedValue().deviceAdded(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDTouchReader>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(hidManager, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<HIDTouchReader>.fromOpaque(ctx).takeUnretainedValue().valueReceived(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let options = seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        lastOpenResult = IOHIDManagerOpen(hidManager, options)
        Log.write("IOHIDManagerOpen seize=\(seize) result=\(lastOpenResult)", force: true)
        manager = hidManager
    }

    func stop() {
        guard let hidManager = manager else { return }
        for handler in handlers.values { handler.onFrame?([]) }
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        handlers.removeAll()
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
        guard vendorID != HIDUsage.appleVendorID else { return }

        let handler = TouchDeviceHandler(device: device)
        guard handler.slotCount > 0 else {
            Log.write("Ignoring \(handler.name): no usable touch slots", force: true)
            return
        }
        handler.onFrame = { [weak self, weak handler] contacts in
            guard let self, handler != nil else { return }
            self.delegate?.touchReader(self, didReceive: contacts)
        }
        handlers[device] = handler
        delegate?.touchReaderDevicesChanged(self)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let removed = handlers.removeValue(forKey: device) {
            removed.onFrame?([])
            delegate?.touchReader(self, didReceive: [])
        }
        delegate?.touchReaderDevicesChanged(self)
    }

    private func valueReceived(_ value: IOHIDValue) {
        let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
        handlers[device]?.handle(value)
    }
}
