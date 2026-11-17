import AppKit
import ApplicationServices
import SwiftUI

enum TrafficLightKind: Int, CaseIterable, Identifiable {
    case close = 0
    case minimize = 1
    case zoom = 2

    var id: Int { rawValue }

    func symbolName(isFullScreen: Bool) -> String {
        switch self {
        case .close:    return "xmark"
        case .minimize: return "minus"
        case .zoom:     return isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
    }

    var topColor: Color {
        switch self {
        case .close:    return Color(red: 1.00, green: 0.37, blue: 0.34) // #FF5F57
        case .minimize: return Color(red: 1.00, green: 0.74, blue: 0.18) // #FEBC2E
        case .zoom:     return Color(red: 0.16, green: 0.78, blue: 0.25) // #28C840
        }
    }

    var bottomColor: Color {
        switch self {
        case .close:    return Color(red: 0.88, green: 0.27, blue: 0.24)
        case .minimize: return Color(red: 0.87, green: 0.63, blue: 0.14)
        case .zoom:     return Color(red: 0.10, green: 0.67, blue: 0.16)
        }
    }

    var strokeColor: Color {
        switch self {
        case .close:    return Color(red: 0.78, green: 0.18, blue: 0.16)
        case .minimize: return Color(red: 0.76, green: 0.52, blue: 0.08)
        case .zoom:     return Color(red: 0.07, green: 0.55, blue: 0.12)
        }
    }

    var glyphColor: Color {
        switch self {
        case .close:    return Color(red: 0.30, green: 0.00, blue: 0.00)
        case .minimize: return Color(red: 0.36, green: 0.19, blue: 0.00)
        case .zoom:     return Color(red: 0.00, green: 0.24, blue: 0.00)
        }
    }
}

struct TrafficLightTarget {
    let kind: TrafficLightKind
    let axWindow: AXUIElement?
    let axElement: AXUIElement?
    let ownerPID: pid_t
    let originalCenter: CGPoint
    let isEnabled: Bool
    let isFullScreen: Bool
}

final class TrafficLightOverlayState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var hoveredKind: TrafficLightKind? = nil
    @Published var pressedKind: TrafficLightKind? = nil
    @Published var targets: [TrafficLightKind: TrafficLightTarget] = [:]

    var onSelect: ((TrafficLightKind) -> Void)?
}

private struct ExpandedTrafficLightsView: View {
    @ObservedObject var state: TrafficLightOverlayState

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                ForEach(TrafficLightKind.allCases) { kind in
                    trafficButton(for: kind)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.38))
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 6)
            .scaleEffect(state.isExpanded ? 1.0 : 0.34, anchor: UnitPoint(x: 0.18, y: 0.5))
            .opacity(state.isExpanded ? 1.0 : 0.0)
            .animation(.spring(response: 0.23, dampingFraction: 0.72), value: state.isExpanded)
        }
        .frame(width: TrafficLightOverlayController.windowWidth, height: TrafficLightOverlayController.windowHeight)
    }

    private func trafficButton(for kind: TrafficLightKind) -> some View {
        let target = state.targets[kind]
        let enabled = target?.isEnabled ?? true
        let isFullScreen = target?.isFullScreen ?? false
        let isHovered = (state.hoveredKind == kind) && enabled
        let isPressed = (state.pressedKind == kind) && enabled

        return Button {
            guard enabled else { return }
            state.onSelect?(kind)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        enabled
                            ? LinearGradient(colors: [kind.topColor, kind.bottomColor], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.gray.opacity(0.45), Color.gray.opacity(0.32)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .strokeBorder(enabled ? kind.strokeColor.opacity(0.85) : Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(isHovered ? 0.65 : 0.22), lineWidth: isHovered ? 2.0 : 0.8)
                    )
                    .shadow(
                        color: enabled ? kind.topColor.opacity(isHovered ? 0.65 : 0.28) : .clear,
                        radius: isHovered ? 8 : 3,
                        x: 0,
                        y: 2
                    )

                if enabled {
                    Image(systemName: kind.symbolName(isFullScreen: isFullScreen))
                        .font(.system(size: kind == .zoom ? 12.5 : 14, weight: .black))
                        .foregroundColor(kind.glyphColor.opacity(0.92))
                }
            }
            .scaleEffect(isPressed ? 0.90 : (isHovered ? 1.15 : 1.0))
            .animation(.spring(response: 0.18, dampingFraction: 0.68), value: isHovered)
            .animation(.spring(response: 0.14, dampingFraction: 0.75), value: isPressed)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private final class TrafficLightOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Detects taps on any macOS window's red/yellow/green traffic lights (including Full Screen Spaces)
/// and expands them into touch-friendly targets.
final class TrafficLightOverlayController {
    static let shared = TrafficLightOverlayController()

    static let windowWidth: CGFloat = 192
    static let windowHeight: CGFloat = 80

    private let state = TrafficLightOverlayState()
    private var panel: TrafficLightOverlayPanel?
    private var dismissTimer: Timer?
    private weak var activeInjector: EventInjector?

    /// Current overlay frame in global Quartz (top-left origin) screen coordinates.
    private(set) var overlayQuartzRect: CGRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true && state.isExpanded
    }

    private init() {
        state.onSelect = { [weak self] kind in
            self?.trigger(kind)
        }
    }

    // MARK: - Touch & Tap Interception

    /// Returns `true` if `point` (in Quartz coordinates) falls within the currently expanded traffic light pill.
    func contains(_ point: CGPoint) -> Bool {
        guard isVisible else { return false }
        let pillRect = overlayQuartzRect.insetBy(dx: 4, dy: 6)
        return pillRect.contains(point)
    }

    /// Updates hover highlight while a finger moves across the expanded traffic lights pill.
    func updateTouchPoint(_ point: CGPoint) {
        guard isVisible else { return }
        scheduleAutoDismiss()
        let hit = hitTestButton(at: point)
        if state.hoveredKind != hit {
            state.hoveredKind = hit
        }
    }

    /// Commits a touch release inside the expanded traffic lights pill.
    /// Returns `true` if the release was handled by the overlay.
    @discardableResult
    func commitTouchRelease(at point: CGPoint) -> Bool {
        guard isVisible else { return false }
        if let kind = hitTestButton(at: point) {
            trigger(kind)
            return true
        }
        if contains(point) {
            state.hoveredKind = nil
            scheduleAutoDismiss()
            return true
        }
        dismiss()
        return false
    }

    /// Inspects the window at `point` (Quartz coordinates). If `point` taps a window's traffic lights,
    /// expands the native traffic lights overlay and returns `true` (consuming the tap).
    func tryExpand(at point: CGPoint, injector: EventInjector) -> Bool {
        guard Settings.shared.expandTrafficLights else { return false }

        if isVisible {
            if commitTouchRelease(at: point) {
                return true
            }
        }

        guard let match = detectTrafficLights(near: point) else {
            return false
        }

        activeInjector = injector
        showOverlay(targets: match.targets, redCenter: match.redCenter, clusterCenterY: match.clusterCenterY, at: point)
        return true
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        state.hoveredKind = nil
        state.pressedKind = nil
        guard panel?.isVisible == true else { return }

        state.isExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.panel?.orderOut(nil)
        }
    }

    // MARK: - Executing Window Action (Windowed + Full Screen)

    private func trigger(_ kind: TrafficLightKind) {
        guard let target = state.targets[kind], target.isEnabled else { return }
        let injector = activeInjector

        state.pressedKind = kind
        dismissTimer?.invalidate()
        dismissTimer = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.state.isExpanded = false
            self.panel?.orderOut(nil)
            self.state.pressedKind = nil
            self.state.hoveredKind = nil

            Self.executeAction(for: target, injector: injector)
        }
    }

    private static func executeAction(for target: TrafficLightTarget, injector: EventInjector?) {
        switch target.kind {
        case .zoom:
            if target.isFullScreen {
                // 1. Direct AXFullScreen = false attribute write on the AXWindow (works even when the full-screen toolbar is hidden).
                if let axWin = target.axWindow,
                   AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanFalse) == .success {
                    Log.write("Traffic light 'zoom' exited Full Screen via AXFullScreen=false", force: true)
                    return
                }
                if let axWin = findFullScreenAXWindow(forPID: target.ownerPID),
                   AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanFalse) == .success {
                    Log.write("Traffic light 'zoom' exited Full Screen via PID AXWindow", force: true)
                    return
                }
                if let axButton = target.axElement,
                   AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success {
                    Log.write("Traffic light 'zoom' exited Full Screen via AXPressAction", force: true)
                    return
                }
                // Fallback: activate owning app and send standard macOS Exit Full Screen shortcut (Ctrl+Cmd+F).
                activateApp(pid: target.ownerPID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    injector?.pressKey(3, flags: [.maskCommand, .maskControl])
                    Log.write("Traffic light 'zoom' exited Full Screen via Ctrl+Cmd+F", force: true)
                }
                return
            } else {
                if let axButton = target.axElement,
                   AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success {
                    Log.write("Traffic light 'zoom' triggered via AXPressAction", force: true)
                    return
                }
                if let axWin = target.axWindow,
                   AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanTrue) == .success {
                    Log.write("Traffic light 'zoom' entered Full Screen via AXFullScreen=true", force: true)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    injector?.click(at: target.originalCenter)
                }
            }

        case .minimize:
            if target.isFullScreen {
                // macOS disables direct minimize in Full Screen; exit Full Screen first, then minimize automatically!
                let axWin = target.axWindow ?? findFullScreenAXWindow(forPID: target.ownerPID)
                if let axWin {
                    _ = AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanFalse)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        if AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue) != .success,
                           let minBtn = buttonElement(from: axWin, attribute: kAXMinimizeButtonAttribute as CFString) {
                            _ = AXUIElementPerformAction(minBtn, kAXPressAction as CFString)
                        }
                        Log.write("Traffic light 'minimize' exited Full Screen and minimized window", force: true)
                    }
                    return
                }
            }
            if let axButton = target.axElement,
               AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success {
                Log.write("Traffic light 'minimize' triggered via AXPressAction", force: true)
                return
            }
            if let axWin = target.axWindow,
               AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                Log.write("Traffic light 'minimize' triggered via AXMinimized=true", force: true)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                injector?.click(at: target.originalCenter)
            }

        case .close:
            if target.isFullScreen {
                // In Full Screen, the titlebar close button is often hidden/disabled by macOS.
                // Exit Full Screen first and then close the window reliably, or press close if enabled.
                if let axButton = target.axElement,
                   isEnabled(axButton),
                   AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success {
                    Log.write("Traffic light 'close' triggered in Full Screen via AXPressAction", force: true)
                    return
                }
                if let axWin = target.axWindow ?? findFullScreenAXWindow(forPID: target.ownerPID) {
                    _ = AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanFalse)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
                        if let closeBtn = buttonElement(from: axWin, attribute: kAXCloseButtonAttribute as CFString),
                           AXUIElementPerformAction(closeBtn, kAXPressAction as CFString) == .success {
                            Log.write("Traffic light 'close' exited Full Screen and closed window", force: true)
                        } else {
                            activateApp(pid: target.ownerPID)
                            injector?.pressKey(13, flags: .maskCommand) // Cmd+W
                            Log.write("Traffic light 'close' exited Full Screen and sent Cmd+W", force: true)
                        }
                    }
                    return
                }
                activateApp(pid: target.ownerPID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    injector?.pressKey(13, flags: .maskCommand) // Cmd+W
                }
                return
            }
            if let axButton = target.axElement,
               AXUIElementPerformAction(axButton, kAXPressAction as CFString) == .success {
                Log.write("Traffic light 'close' triggered via AXPressAction", force: true)
                return
            }
            if let axWin = target.axWindow,
               let closeBtn = buttonElement(from: axWin, attribute: kAXCloseButtonAttribute as CFString),
               AXUIElementPerformAction(closeBtn, kAXPressAction as CFString) == .success {
                Log.write("Traffic light 'close' triggered via window AXCloseButton", force: true)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                injector?.click(at: target.originalCenter)
            }
        }
    }

    private static func activateApp(pid: pid_t) {
        guard pid > 0 else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    private static func findFullScreenAXWindow(forPID pid: pid_t) -> AXUIElement? {
        guard pid > 0 else { return nil }
        let appAX = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            if let fsWin = axWindows.first(where: { isWindowFullScreen($0) }) {
                return fsWin
            }
            return axWindows.first
        }
        var mainRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appAX, kAXFocusedWindowAttribute as CFString, &mainRef) == .success,
           let mainWin = mainRef {
            return (mainWin as! AXUIElement)
        }
        return nil
    }

    private static func findCloseButtonInApp(forPID pid: pid_t) -> AXUIElement? {
        guard pid > 0 else { return nil }
        let appAX = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return nil
        }
        for axWin in axWindows {
            if let closeBtn = buttonElement(from: axWin, attribute: kAXCloseButtonAttribute as CFString) {
                return closeBtn
            }
        }
        return nil
    }

    // MARK: - Overlay Presentation & Geometry

    private func showOverlay(
        targets: [TrafficLightKind: TrafficLightTarget],
        redCenter: CGPoint,
        clusterCenterY: CGFloat,
        at touchPoint: CGPoint
    ) {
        ensurePanel()
        guard let panel else { return }

        state.targets = targets
        state.hoveredKind = nil
        state.pressedKind = nil

        var qx = redCenter.x - 42.0
        var qy = clusterCenterY - (Self.windowHeight * 0.5)

        let displayID = Self.displayContaining(quartzPoint: touchPoint)
        let bounds = CGDisplayBounds(displayID)
        if bounds.width > 0 && bounds.height > 0 {
            qx = min(max(qx, bounds.minX + 4), bounds.maxX - Self.windowWidth - 4)
            qy = min(max(qy, bounds.minY + 4), bounds.maxY - Self.windowHeight - 4)
        }

        overlayQuartzRect = CGRect(x: qx, y: qy, width: Self.windowWidth, height: Self.windowHeight)

        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let appKitOriginY = primaryHeight - qy - Self.windowHeight
        let appKitFrame = NSRect(x: qx, y: appKitOriginY, width: Self.windowWidth, height: Self.windowHeight)

        panel.setFrame(appKitFrame, display: true)
        state.isExpanded = false
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            self?.state.isExpanded = true
        }
        scheduleAutoDismiss()
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let p = TrafficLightOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: ExpandedTrafficLightsView(state: state))
        panel = p
    }

    private func scheduleAutoDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Hit-tests which of the 3 enlarged buttons (if any) contains `point` in Quartz screen coordinates.
    private func hitTestButton(at point: CGPoint) -> TrafficLightKind? {
        guard isVisible else { return nil }
        let centerY = overlayQuartzRect.minY + (Self.windowHeight * 0.5)
        let centersX: [(TrafficLightKind, CGFloat)] = [
            (.close, overlayQuartzRect.minX + 46.0),
            (.minimize, overlayQuartzRect.minX + 96.0),
            (.zoom, overlayQuartzRect.minX + 146.0),
        ]

        var bestKind: TrafficLightKind?
        var bestDist: CGFloat = 26.0
        for (kind, cx) in centersX {
            let d = hypot(point.x - cx, point.y - centerY)
            if d <= bestDist, state.targets[kind]?.isEnabled ?? true {
                bestDist = d
                bestKind = kind
            }
        }
        return bestKind
    }

    private static func displayContaining(quartzPoint: CGPoint) -> CGDirectDisplayID {
        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(quartzPoint, 1, &displayID, &count)
        return displayID
    }

    // MARK: - Accessibility Traffic Light Detection (Windowed + Full Screen)

    private struct DetectionMatch {
        let targets: [TrafficLightKind: TrafficLightTarget]
        let redCenter: CGPoint
        let clusterCenterY: CGFloat
    }

    private func detectTrafficLights(near point: CGPoint) -> DetectionMatch? {
        let systemWide = AXUIElementCreateSystemWide()
        let probeOffsets: [CGPoint] = [
            .zero,
            CGPoint(x: 12, y: 10),
            CGPoint(x: -10, y: 10),
            CGPoint(x: 16, y: 0),
            CGPoint(x: 0, y: 14),
            CGPoint(x: -12, y: 0),
            CGPoint(x: 20, y: 14),
        ]

        var visitedWindows: [AXUIElement] = []

        for offset in probeOffsets {
            let probe = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            var hitRef: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(probe.x), Float(probe.y), &hitRef) == .success,
                  let hit = hitRef,
                  let win = Self.enclosingWindow(of: hit) else {
                continue
            }

            if visitedWindows.contains(where: { CFEqual($0, win) }) {
                continue
            }
            visitedWindows.append(win)

            if let match = Self.extractTrafficLights(from: win, touchPoint: point) {
                return match
            }
        }

        return detectViaWindowList(near: point)
    }

    private func detectViaWindowList(near point: CGPoint) -> DetectionMatch? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let displayID = Self.displayContaining(quartzPoint: point)
        let displayBounds = CGDisplayBounds(displayID)

        for info in infoList {
            let layer = (info[kCGWindowLayer as String] as? Int) ?? -1
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            let pid = (info[kCGWindowOwnerPID as String] as? pid_t) ?? 0
            guard layer == 0, alpha > 0.05 else { continue }
            if pid == ownPID && panel?.isVisible == true {
                let winName = (info[kCGWindowName as String] as? String) ?? ""
                if winName.isEmpty { continue }
            }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 140, bounds.height >= 80 else {
                continue
            }

            guard bounds.insetBy(dx: -18, dy: -18).contains(point) else { continue }

            // Check if `point` is near the top-left traffic light corner of this topmost window.
            let cornerRect = CGRect(x: bounds.minX - 16, y: bounds.minY - 16, width: 118, height: 68)
            guard cornerRect.contains(point) else {
                return nil
            }

            let appAX = AXUIElementCreateApplication(pid)
            var matchedAXWindow: AXUIElement?
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let axWindows = windowsRef as? [AXUIElement] {
                for axWin in axWindows {
                    if let match = Self.extractTrafficLights(from: axWin, touchPoint: point) {
                        return match
                    }
                    if matchedAXWindow == nil {
                        if let winFrame = Self.frame(of: axWin),
                           hypot(winFrame.minX - bounds.minX, winFrame.minY - bounds.minY) < 40 {
                            matchedAXWindow = axWin
                        } else if Self.isWindowFullScreen(axWin) {
                            matchedAXWindow = axWin
                        }
                    }
                }
                if matchedAXWindow == nil {
                    matchedAXWindow = axWindows.first
                }
            }

            let looksFullScreen = (matchedAXWindow.map { Self.isWindowFullScreen($0) } ?? false)
                || (abs(bounds.width - displayBounds.width) <= 4 && abs(bounds.height - displayBounds.height) <= 40)

            let redCenter = CGPoint(x: bounds.minX + 20, y: bounds.minY + 20)
            let yellowCenter = CGPoint(x: bounds.minX + 40, y: bounds.minY + 20)
            let greenCenter = CGPoint(x: bounds.minX + 60, y: bounds.minY + 20)
            let fallbackCluster = CGRect(x: bounds.minX + 12, y: bounds.minY + 12, width: 56, height: 16)

            if fallbackCluster.insetBy(dx: -28, dy: -26).contains(point) {
                let closeEl = matchedAXWindow.flatMap { Self.buttonElement(from: $0, attribute: kAXCloseButtonAttribute as CFString) }
                let minEl = matchedAXWindow.flatMap { Self.buttonElement(from: $0, attribute: kAXMinimizeButtonAttribute as CFString) }
                let zoomEl = matchedAXWindow.flatMap {
                    Self.buttonElement(from: $0, attribute: kAXFullScreenButtonAttribute as CFString)
                        ?? Self.buttonElement(from: $0, attribute: kAXZoomButtonAttribute as CFString)
                }

                let targets: [TrafficLightKind: TrafficLightTarget] = [
                    .close: TrafficLightTarget(
                        kind: .close,
                        axWindow: matchedAXWindow,
                        axElement: closeEl,
                        ownerPID: pid,
                        originalCenter: redCenter,
                        isEnabled: true,
                        isFullScreen: looksFullScreen
                    ),
                    .minimize: TrafficLightTarget(
                        kind: .minimize,
                        axWindow: matchedAXWindow,
                        axElement: minEl,
                        ownerPID: pid,
                        originalCenter: yellowCenter,
                        isEnabled: true,
                        isFullScreen: looksFullScreen
                    ),
                    .zoom: TrafficLightTarget(
                        kind: .zoom,
                        axWindow: matchedAXWindow,
                        axElement: zoomEl,
                        ownerPID: pid,
                        originalCenter: greenCenter,
                        isEnabled: true,
                        isFullScreen: looksFullScreen
                    ),
                ]
                return DetectionMatch(targets: targets, redCenter: redCenter, clusterCenterY: redCenter.y)
            }

            return nil
        }

        return nil
    }

    private static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        if role(of: element) == (kAXWindowRole as String) {
            return element
        }
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
           let win = winRef {
            return (win as! AXUIElement)
        }
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let el = current else { break }
            if role(of: el) == (kAXWindowRole as String) {
                return el
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }
        return nil
    }

    private static func extractTrafficLights(from window: AXUIElement, touchPoint: CGPoint) -> DetectionMatch? {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)

        let fullScreen = isWindowFullScreen(window)
        let closeEl = buttonElement(from: window, attribute: kAXCloseButtonAttribute as CFString)
        let minimizeEl = buttonElement(from: window, attribute: kAXMinimizeButtonAttribute as CFString)
        let zoomEl = buttonElement(from: window, attribute: kAXFullScreenButtonAttribute as CFString)
            ?? buttonElement(from: window, attribute: kAXZoomButtonAttribute as CFString)

        let closeRect = closeEl.flatMap { frame(of: $0) }
        let minimizeRect = minimizeEl.flatMap { frame(of: $0) }
        let zoomRect = zoomEl.flatMap { frame(of: $0) }

        let availableRects = [closeRect, minimizeRect, zoomRect].compactMap { $0 }

        if !availableRects.isEmpty {
            var clusterRect = availableRects[0]
            for r in availableRects.dropFirst() {
                clusterRect = clusterRect.union(r)
            }

            let hitZone = clusterRect.insetBy(dx: -24, dy: -22)
            if hitZone.contains(touchPoint) {
                let baseCenterY = clusterRect.midY
                let redCenter = closeRect.map { CGPoint(x: $0.midX, y: $0.midY) }
                    ?? minimizeRect.map { CGPoint(x: $0.midX - 20, y: $0.midY) }
                    ?? CGPoint(x: clusterRect.minX + 7, y: baseCenterY)

                let yellowCenter = minimizeRect.map { CGPoint(x: $0.midX, y: $0.midY) }
                    ?? CGPoint(x: redCenter.x + 20, y: baseCenterY)

                let greenCenter = zoomRect.map { CGPoint(x: $0.midX, y: $0.midY) }
                    ?? CGPoint(x: yellowCenter.x + 20, y: baseCenterY)

                let closeEnabled = fullScreen ? true : (closeEl.map { isEnabled($0) } ?? true)
                let minimizeEnabled = fullScreen ? true : (minimizeEl.map { isEnabled($0) } ?? false)
                let zoomEnabled = fullScreen ? true : (zoomEl.map { isEnabled($0) } ?? true)

                let targets: [TrafficLightKind: TrafficLightTarget] = [
                    .close: TrafficLightTarget(kind: .close, axWindow: window, axElement: closeEl, ownerPID: pid, originalCenter: redCenter, isEnabled: closeEnabled, isFullScreen: fullScreen),
                    .minimize: TrafficLightTarget(kind: .minimize, axWindow: window, axElement: minimizeEl, ownerPID: pid, originalCenter: yellowCenter, isEnabled: minimizeEnabled, isFullScreen: fullScreen),
                    .zoom: TrafficLightTarget(kind: .zoom, axWindow: window, axElement: zoomEl, ownerPID: pid, originalCenter: greenCenter, isEnabled: zoomEnabled, isFullScreen: fullScreen),
                ]

                return DetectionMatch(targets: targets, redCenter: redCenter, clusterCenterY: baseCenterY)
            }
        }

        // Full Screen fallback when the auto-hidden titlebar hides the traffic light button frames:
        if fullScreen, let winFrame = frame(of: window) {
            let cornerZone = CGRect(x: winFrame.minX - 16, y: winFrame.minY - 16, width: 118, height: 68)
            if cornerZone.contains(touchPoint) {
                let redCenter = CGPoint(x: winFrame.minX + 20, y: winFrame.minY + 20)
                let yellowCenter = CGPoint(x: winFrame.minX + 40, y: winFrame.minY + 20)
                let greenCenter = CGPoint(x: winFrame.minX + 60, y: winFrame.minY + 20)

                let targets: [TrafficLightKind: TrafficLightTarget] = [
                    .close: TrafficLightTarget(kind: .close, axWindow: window, axElement: closeEl, ownerPID: pid, originalCenter: redCenter, isEnabled: true, isFullScreen: true),
                    .minimize: TrafficLightTarget(kind: .minimize, axWindow: window, axElement: minimizeEl, ownerPID: pid, originalCenter: yellowCenter, isEnabled: true, isFullScreen: true),
                    .zoom: TrafficLightTarget(kind: .zoom, axWindow: window, axElement: zoomEl, ownerPID: pid, originalCenter: greenCenter, isEnabled: true, isFullScreen: true),
                ]
                return DetectionMatch(targets: targets, redCenter: redCenter, clusterCenterY: redCenter.y)
            }
        }

        return nil
    }

    private static func isWindowFullScreen(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref) == .success,
           let num = ref as? NSNumber,
           num.boolValue {
            return true
        }
        if let subrole = stringAttr(window, kAXSubroleAttribute as CFString),
           subrole == "AXFullScreenWindow" {
            return true
        }
        if let f = frame(of: window) {
            let displayID = displayContaining(quartzPoint: CGPoint(x: f.midX, y: f.midY))
            let db = CGDisplayBounds(displayID)
            if db.width > 0 && abs(f.width - db.width) <= 4 && abs(f.height - db.height) <= 42 && abs(f.minY - db.minY) <= 42 {
                return true
            }
        }
        return false
    }

    private static func stringAttr(_ element: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func buttonElement(from window: AXUIElement, attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute, &ref) == .success, let val = ref else {
            return nil
        }
        return (val as! AXUIElement)
    }

    private static func role(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &ref) == .success,
              let num = ref as? NSNumber else {
            return true
        }
        return num.boolValue
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }
}
