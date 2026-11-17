import Foundation

/// Linear 2D affine calibration transform: `x' = scaleX * x + offsetX`, `y' = scaleY * y + offsetY`.
struct CalibrationTransform: Equatable {
    let scaleX: Double
    let offsetX: Double
    let scaleY: Double
    let offsetY: Double

    static let identity = CalibrationTransform(scaleX: 1.0, offsetX: 0.0, scaleY: 1.0, offsetY: 0.0)

    var isIdentity: Bool { self == .identity }

    var rawArray: [Double] { [scaleX, offsetX, scaleY, offsetY] }

    init(scaleX: Double, offsetX: Double, scaleY: Double, offsetY: Double) {
        self.scaleX = scaleX
        self.offsetX = offsetX
        self.scaleY = scaleY
        self.offsetY = offsetY
    }

    init(rawArray: [Double]) {
        guard rawArray.count == 4,
              rawArray.allSatisfy({ $0.isFinite }),
              abs(rawArray[0]) > 0.05,
              abs(rawArray[2]) > 0.05 else {
            self = .identity
            return
        }
        self.init(scaleX: rawArray[0], offsetX: rawArray[1], scaleY: rawArray[2], offsetY: rawArray[3])
    }

    @inline(__always)
    func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        let cx = min(max(scaleX * x + offsetX, 0.0), 1.0)
        let cy = min(max(scaleY * y + offsetY, 0.0), 1.0)
        return (cx, cy)
    }
}

/// Persistent driver configuration backed by `UserDefaults` with in-memory caching for hot-path access.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let displayName = "displayName"
        static let extraRotation = "extraRotation"
        static let autoRotate = "autoRotate"
        static let invertAutoRotate = "invertAutoRotate"
        static let palmRejection = "palmRejection"
        static let expandTrafficLights = "expandTrafficLights"
        static let touchKeyboard = "touchKeyboard"
        static let flipX = "flipX"
        static let flipY = "flipY"
        static let longPressRightClick = "longPressRightClick"
        static let twoFingerScroll = "twoFingerScroll"
        static let pinchZoom = "pinchZoom"
        static let threeFingerSwipe = "threeFingerSwipe"
        static let momentum = "momentum"
        static let invertScroll = "invertScroll"
        static let seizeDevice = "seizeDevice"
        static let calibration = "calibration"
        static let debugLog = "debugLog"
        static let showInDock = "showInDock"
    }

    // In-memory cached properties to avoid repeated UserDefaults dictionary lookups on the 240Hz HID path.
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    var displayName: String? { didSet { defaults.set(displayName, forKey: Key.displayName) } }
    var extraRotation: Int { didSet { defaults.set(extraRotation, forKey: Key.extraRotation) } }
    var autoRotate: Bool { didSet { defaults.set(autoRotate, forKey: Key.autoRotate) } }
    var invertAutoRotate: Bool { didSet { defaults.set(invertAutoRotate, forKey: Key.invertAutoRotate) } }
    var palmRejection: Bool { didSet { defaults.set(palmRejection, forKey: Key.palmRejection) } }
    var expandTrafficLights: Bool { didSet { defaults.set(expandTrafficLights, forKey: Key.expandTrafficLights) } }
    var touchKeyboard: Bool { didSet { defaults.set(touchKeyboard, forKey: Key.touchKeyboard) } }
    var flipX: Bool { didSet { defaults.set(flipX, forKey: Key.flipX) } }
    var flipY: Bool { didSet { defaults.set(flipY, forKey: Key.flipY) } }
    var longPressRightClick: Bool { didSet { defaults.set(longPressRightClick, forKey: Key.longPressRightClick) } }
    var twoFingerScroll: Bool { didSet { defaults.set(twoFingerScroll, forKey: Key.twoFingerScroll) } }
    var pinchZoom: Bool { didSet { defaults.set(pinchZoom, forKey: Key.pinchZoom) } }
    var threeFingerSwipe: Bool { didSet { defaults.set(threeFingerSwipe, forKey: Key.threeFingerSwipe) } }
    var momentum: Bool { didSet { defaults.set(momentum, forKey: Key.momentum) } }
    var invertScroll: Bool { didSet { defaults.set(invertScroll, forKey: Key.invertScroll) } }
    var seizeDevice: Bool { didSet { defaults.set(seizeDevice, forKey: Key.seizeDevice) } }
    var debugLog: Bool { didSet { defaults.set(debugLog, forKey: Key.debugLog) } }
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: Key.showInDock) } }

    var calibrationTransform: CalibrationTransform {
        didSet { defaults.set(calibrationTransform.rawArray, forKey: Key.calibration) }
    }

    var calibration: [Double] {
        get { calibrationTransform.rawArray }
        set { calibrationTransform = CalibrationTransform(rawArray: newValue) }
    }

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.extraRotation: 0,
            Key.autoRotate: true,
            Key.invertAutoRotate: false,
            Key.palmRejection: true,
            Key.expandTrafficLights: true,
            Key.touchKeyboard: true,
            Key.flipX: false,
            Key.flipY: false,
            Key.longPressRightClick: true,
            Key.twoFingerScroll: true,
            Key.pinchZoom: true,
            Key.threeFingerSwipe: true,
            Key.momentum: true,
            Key.invertScroll: false,
            Key.seizeDevice: false,
            Key.calibration: CalibrationTransform.identity.rawArray,
            Key.debugLog: false,
            Key.showInDock: true,
        ])

        enabled = defaults.bool(forKey: Key.enabled)
        displayName = defaults.string(forKey: Key.displayName)
        extraRotation = defaults.integer(forKey: Key.extraRotation)
        autoRotate = defaults.bool(forKey: Key.autoRotate)
        invertAutoRotate = defaults.bool(forKey: Key.invertAutoRotate)
        palmRejection = defaults.bool(forKey: Key.palmRejection)
        expandTrafficLights = defaults.bool(forKey: Key.expandTrafficLights)
        touchKeyboard = defaults.bool(forKey: Key.touchKeyboard)
        flipX = defaults.bool(forKey: Key.flipX)
        flipY = defaults.bool(forKey: Key.flipY)
        longPressRightClick = defaults.bool(forKey: Key.longPressRightClick)
        twoFingerScroll = defaults.bool(forKey: Key.twoFingerScroll)
        pinchZoom = defaults.bool(forKey: Key.pinchZoom)
        threeFingerSwipe = defaults.bool(forKey: Key.threeFingerSwipe)
        momentum = defaults.bool(forKey: Key.momentum)
        invertScroll = defaults.bool(forKey: Key.invertScroll)
        seizeDevice = defaults.bool(forKey: Key.seizeDevice)
        debugLog = defaults.bool(forKey: Key.debugLog)
        showInDock = defaults.bool(forKey: Key.showInDock)

        let rawCal = defaults.array(forKey: Key.calibration) as? [Double] ?? []
        calibrationTransform = CalibrationTransform(rawArray: rawCal)
    }
}

/// Asynchronous, low-overhead file logger (`/tmp/Touchy.log`).
enum Log {
    static let url = URL(fileURLWithPath: "/tmp/Touchy.log")
    private static let queue = DispatchQueue(label: "com.beratclxn.touchy.logger", qos: .utility)
    private static let formatter = ISO8601DateFormatter()

    static func write(_ message: @autoclosure () -> String, force: Bool = false) {
        guard force || Settings.shared.debugLog else { return }
        let text = message()
        let timestamp = Date()
        queue.async {
            let line = "[\(formatter.string(from: timestamp))] \(text)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
