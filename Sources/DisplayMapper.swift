import AppKit
import CoreGraphics

/// Maps normalized panel coordinates (`0...1`) onto the target monitor's global Quartz coordinate space.
final class DisplayMapper {
    private(set) var displayID: CGDirectDisplayID?
    private(set) var displayName: String = "—"
    private(set) var hasExternalDisplay: Bool = false
    private var displayBounds: CGRect = .zero
    private var hardwareRotation: Int = 0

    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    struct ScreenInfo {
        let id: CGDirectDisplayID
        let name: String
        let builtIn: Bool
    }

    static func screens() -> [ScreenInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            return ScreenInfo(id: id, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// Returns only external (non-built-in) displays so touch mapping and orientation never target the MacBook's internal screen.
    static func externalScreens() -> [ScreenInfo] {
        screens().filter { !$0.builtIn }
    }

    static func nsScreen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value == id
        }
    }

    /// Re-evaluates which active external display corresponds to the touch monitor and caches its geometry.
    func refresh() {
        let externals = Self.externalScreens()
        var selected: ScreenInfo?

        if let preferredName = Settings.shared.displayName {
            selected = externals.first { $0.name == preferredName }
            // Clear stale preference if it pointed to the built-in display.
            if selected == nil, Self.screens().contains(where: { $0.name == preferredName && $0.builtIn }) {
                Settings.shared.displayName = nil
            }
        }
        if selected == nil {
            selected = externals.first
        }

        displayID = selected?.id
        displayName = selected?.name ?? "—"
        hasExternalDisplay = (selected != nil)

        if let id = displayID {
            displayBounds = CGDisplayBounds(id)
            hardwareRotation = Int(CGDisplayRotation(id).rounded())
        } else {
            displayBounds = .zero
            hardwareRotation = 0
        }

        Log.write("Touch display -> \(displayName) (\(displayID.map(String.init) ?? "none"))", force: true)
    }

    /// Applies rotation and axis flipping in normalized `0...1` coordinates (prior to 4-point calibration).
    @inline(__always)
    func oriented(_ contact: RawContact) -> CGPoint {
        var x = contact.x
        var y = contact.y
        let settings = Settings.shared

        let totalRotation = ((settings.extraRotation + hardwareRotation) % 360 + 360) % 360
        switch totalRotation {
        case 90:  (x, y) = (1.0 - y, x)
        case 180: (x, y) = (1.0 - x, 1.0 - y)
        case 270: (x, y) = (y, 1.0 - x)
        default:  break
        }

        if settings.flipX { x = 1.0 - x }
        if settings.flipY { y = 1.0 - y }
        return CGPoint(x: x, y: y)
    }

    /// Applies the 4-point linear calibration transform to oriented normalized coordinates.
    @inline(__always)
    func calibrated(_ point: CGPoint) -> CGPoint {
        let (cx, cy) = Settings.shared.calibrationTransform.apply(x: Double(point.x), y: Double(point.y))
        return CGPoint(x: cx, y: cy)
    }

    /// Projects normalized `0...1` coordinates onto global Quartz screen coordinates.
    @inline(__always)
    func screenPoint(fromNormalized point: CGPoint) -> CGPoint? {
        guard displayID != nil, displayBounds.width > 0, displayBounds.height > 0 else { return nil }
        let x = displayBounds.minX + min(Double(point.x) * displayBounds.width, displayBounds.width - 1.0)
        let y = displayBounds.minY + min(Double(point.y) * displayBounds.height, displayBounds.height - 1.0)
        return CGPoint(x: x, y: y)
    }

    @inline(__always)
    func map(_ contact: RawContact) -> CGPoint? {
        screenPoint(fromNormalized: calibrated(oriented(contact)))
    }
}
