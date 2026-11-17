import Foundation
import SwiftUI
import ServiceManagement

struct LiveFinger: Identifiable, Equatable {
    let id: Int
    let normX: Double
    let normY: Double
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case overview
    case display
    case gestures
    case system
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Live Monitor"
        case .display:  return "Display & Calibration"
        case .gestures: return "Touch & Stylus"
        case .system:   return "System & Permissions"
        case .about:    return "About & Legal"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Real-time digitizer coordinate scope and hardware status"
        case .display:  return "Target display assignment, DDC/CI orientation, and 4-point calibration"
        case .gestures: return "Stylus palm rejection, tap behavior, scrolling, zoom, and Spaces"
        case .system:   return "Accessibility authorization, IOHID connection, login item, and logs"
        case .about:    return "Build metadata, verified reference hardware, and legal disclosures"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "viewfinder.rectangular"
        case .display:  return "display"
        case .gestures: return "hand.draw"
        case .system:   return "checkmark.shield"
        case .about:    return "info.circle"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .overview:
            return [Color(red: 0.40, green: 0.92, blue: 0.86), Color(red: 0.05, green: 0.62, blue: 0.62)]
        case .display:
            return [Color(red: 0.30, green: 0.85, blue: 0.95), Color(red: 0.08, green: 0.52, blue: 0.72)]
        case .gestures:
            return [Color(red: 0.36, green: 0.90, blue: 0.78), Color(red: 0.06, green: 0.58, blue: 0.52)]
        case .system:
            return [Color(red: 0.20, green: 0.84, blue: 0.60), Color(red: 0.05, green: 0.58, blue: 0.42)]
        case .about:
            return [Color(red: 0.42, green: 0.84, blue: 0.90), Color(red: 0.10, green: 0.46, blue: 0.56)]
        }
    }
}

enum BentoTab: String {
    case home
    case system
}

/// Centralized reactive state store decoupling SwiftUI views from hardware services.
final class AppState: ObservableObject {
    static let shared = AppState()

    // Navigation & transient UI state
    @Published var selectedTab: SidebarTab = .overview
    @Published var searchQuery: String = ""
    @Published var copiedToast: Bool = false
    @Published var bentoTab: BentoTab = .home
    @Published var bentoStatusHint: String? = nil

    // Live hardware & permission state
    @Published var isConnected: Bool = false
    @Published var deviceSummary: String = "No Device Connected"
    @Published var slotCount: Int = 0
    @Published var activeDisplayName: String = "—"
    @Published var hasExternalDisplay: Bool = false
    @Published var screens: [DisplayMapper.ScreenInfo] = []
    @Published var accessibilityOK: Bool = false
    @Published var hidOpenOK: Bool = true
    @Published var sensorOrientationAngle: Int? = nil
    @Published var liveFingers: [LiveFinger] = []
    @Published var isKeyboardVisible: Bool = false

    /// Dynamically resolves the connected 2nd display / touch hardware name reported by macOS.
    var systemDeviceName: String {
        if hasExternalDisplay && activeDisplayName != "—" {
            return activeDisplayName
        }
        if isConnected && !deviceSummary.isEmpty {
            return deviceSummary
        }
        return activeDisplayName != "—" ? activeDisplayName : "Touch Display"
    }

    // Persisted driver settings
    @Published var enabled: Bool = Settings.shared.enabled {
        didSet { Settings.shared.enabled = enabled; onSettingsChanged?() }
    }
    @Published var selectedDisplay: String = Settings.shared.displayName ?? "__AUTO__" {
        didSet {
            Settings.shared.displayName = (selectedDisplay == "__AUTO__") ? nil : selectedDisplay
            onDisplayChanged?()
        }
    }
    @Published var extraRotation: Int = Settings.shared.extraRotation {
        didSet { Settings.shared.extraRotation = extraRotation }
    }
    @Published var autoRotate: Bool = Settings.shared.autoRotate {
        didSet { Settings.shared.autoRotate = autoRotate; onAutoRotateChanged?() }
    }
    @Published var invertAutoRotate: Bool = Settings.shared.invertAutoRotate {
        didSet { Settings.shared.invertAutoRotate = invertAutoRotate; onAutoRotateChanged?() }
    }
    @Published var palmRejection: Bool = Settings.shared.palmRejection {
        didSet { Settings.shared.palmRejection = palmRejection }
    }
    @Published var expandTrafficLights: Bool = Settings.shared.expandTrafficLights {
        didSet { Settings.shared.expandTrafficLights = expandTrafficLights }
    }
    @Published var touchKeyboard: Bool = Settings.shared.touchKeyboard {
        didSet {
            Settings.shared.touchKeyboard = touchKeyboard
            if !touchKeyboard { TouchKeyboardController.shared.dismiss() }
        }
    }
    @Published var flipX: Bool = Settings.shared.flipX {
        didSet { Settings.shared.flipX = flipX }
    }
    @Published var flipY: Bool = Settings.shared.flipY {
        didSet { Settings.shared.flipY = flipY }
    }
    @Published var longPressRightClick: Bool = Settings.shared.longPressRightClick {
        didSet { Settings.shared.longPressRightClick = longPressRightClick }
    }
    @Published var twoFingerScroll: Bool = Settings.shared.twoFingerScroll {
        didSet { Settings.shared.twoFingerScroll = twoFingerScroll }
    }
    @Published var momentum: Bool = Settings.shared.momentum {
        didSet { Settings.shared.momentum = momentum }
    }
    @Published var invertScroll: Bool = Settings.shared.invertScroll {
        didSet { Settings.shared.invertScroll = invertScroll }
    }
    @Published var pinchZoom: Bool = Settings.shared.pinchZoom {
        didSet { Settings.shared.pinchZoom = pinchZoom }
    }
    @Published var threeFingerSwipe: Bool = Settings.shared.threeFingerSwipe {
        didSet { Settings.shared.threeFingerSwipe = threeFingerSwipe }
    }
    @Published var seizeDevice: Bool = Settings.shared.seizeDevice {
        didSet { Settings.shared.seizeDevice = seizeDevice; onSeizeChanged?() }
    }
    @Published var debugLog: Bool = Settings.shared.debugLog {
        didSet { Settings.shared.debugLog = debugLog }
    }
    @Published var showInDock: Bool = Settings.shared.showInDock {
        didSet { Settings.shared.showInDock = showInDock; onDockPolicyChanged?() }
    }
    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    // Action callbacks wired by AppDelegate
    var onSettingsChanged: (() -> Void)?
    var onDisplayChanged: (() -> Void)?
    var onAutoRotateChanged: (() -> Void)?
    var onSeizeChanged: (() -> Void)?
    var onDockPolicyChanged: (() -> Void)?
    var onCalibrate: (() -> Void)?
    var onResetCalibration: (() -> Void)?
    var onRescan: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onResetPermissions: (() -> Void)?
    var onRelaunch: (() -> Void)?
    var onShowLog: (() -> Void)?
    var onCopyDiagnostics: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onToggleKeyboardNow: (() -> Void)?
    var onOpenControlPanel: (() -> Void)?
    var onQuit: (() -> Void)?

    func flashBentoHint(_ text: String) {
        bentoStatusHint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.bentoStatusHint == text {
                self?.bentoStatusHint = nil
            }
        }
    }

    func cycleDisplay() {
        guard !screens.isEmpty else {
            selectedDisplay = "__AUTO__"
            flashBentoHint("No External Display")
            return
        }
        if screens.count == 1 {
            selectedDisplay = "__AUTO__"
            flashBentoHint("External: \(screens[0].name)")
            return
        }
        let all = ["__AUTO__"] + screens.map { $0.name }
        let idx = all.firstIndex(of: selectedDisplay) ?? 0
        let next = all[(idx + 1) % all.count]
        selectedDisplay = next
        flashBentoHint(next == "__AUTO__" ? "Display: Auto (\(activeDisplayName))" : "Display: \(next)")
    }

    func cycleRotation() {
        if autoRotate {
            autoRotate = false
        }
        let next = (extraRotation + 90) % 360
        extraRotation = next
        flashBentoHint("Manual Rotation: \(next)°")
    }

    func syncFromSettings() {
        let s = Settings.shared
        if enabled != s.enabled { enabled = s.enabled }
        let disp = s.displayName ?? "__AUTO__"
        if selectedDisplay != disp { selectedDisplay = disp }
        if extraRotation != s.extraRotation { extraRotation = s.extraRotation }
        if autoRotate != s.autoRotate { autoRotate = s.autoRotate }
        if invertAutoRotate != s.invertAutoRotate { invertAutoRotate = s.invertAutoRotate }
        if palmRejection != s.palmRejection { palmRejection = s.palmRejection }
        if expandTrafficLights != s.expandTrafficLights { expandTrafficLights = s.expandTrafficLights }
        if touchKeyboard != s.touchKeyboard { touchKeyboard = s.touchKeyboard }
        if flipX != s.flipX { flipX = s.flipX }
        if flipY != s.flipY { flipY = s.flipY }
        if longPressRightClick != s.longPressRightClick { longPressRightClick = s.longPressRightClick }
        if twoFingerScroll != s.twoFingerScroll { twoFingerScroll = s.twoFingerScroll }
        if momentum != s.momentum { momentum = s.momentum }
        if invertScroll != s.invertScroll { invertScroll = s.invertScroll }
        if pinchZoom != s.pinchZoom { pinchZoom = s.pinchZoom }
        if threeFingerSwipe != s.threeFingerSwipe { threeFingerSwipe = s.threeFingerSwipe }
        if seizeDevice != s.seizeDevice { seizeDevice = s.seizeDevice }
        if debugLog != s.debugLog { debugLog = s.debugLog }
        if showInDock != s.showInDock { showInDock = s.showInDock }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }
}
