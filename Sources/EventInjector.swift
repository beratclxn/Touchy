import AppKit
import ApplicationServices
import CoreGraphics

/// Synthesizes low-level Quartz mouse, continuous pixel scroll, trackpad magnification, keyboard, and space-switch events.
final class EventInjector {
    static let syntheticEventTag: Int64 = 0x544F5543
    private(set) static var lastSyntheticKeyTime: TimeInterval = 0
    private(set) static var lastSyntheticMouseTime: TimeInterval = 0

    private var eventSource: CGEventSource? = {
        let src = CGEventSource(stateID: .hidSystemState)
        src?.localEventsSuppressionInterval = 0.0
        return src
    }()

    func refreshEventSource() {
        let src = CGEventSource(stateID: .hidSystemState)
        src?.localEventsSuppressionInterval = 0.0
        eventSource = src
    }

    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint(x: -10_000, y: -10_000)
    private var lastCursorPoint: CGPoint?
    private var clickCount: Int64 = 1
    private(set) var leftDown = false
    private var dockRevealTimer: Timer?

    private var scrollRemainderX = 0.0
    private var scrollRemainderY = 0.0

    private static let doubleClickRadius: CGFloat = 24.0

    /// Undocumented Quartz `CGEventField` identifiers required for native trackpad gesture synthesis.
    private enum HIDEventField {
        private static func field(_ raw: UInt32) -> CGEventField { unsafeBitCast(raw, to: CGEventField.self) }
        static let eventType = field(55)
        static let scrollPhase = field(99)
        static let gestureHIDType = field(110)
        static let gestureZoomValue = field(113)
        static let gestureRotateValue = field(114)
        static let gestureSwipeMotion = field(115)
        static let momentumPhase = field(123)
        static let gesturePhase = field(132)
        static let isDirectionInvertedFromDevice = field(137)
    }

    enum Phase: Int64 {
        case began = 1, changed = 2, ended = 4, cancelled = 8, mayBegin = 128
    }

    enum Momentum: Int64 {
        case none = 0, begin = 1, `continue` = 2, end = 3
    }

    enum SwipeDirection: Int64 {
        case up = 1     // deltaY = +1.0
        case down = 2   // deltaY = -1.0
        case left = 4   // deltaX = +1.0 (previous)
        case right = 8  // deltaX = -1.0 (next)
    }

    enum Arrow: CGKeyCode {
        case left = 123, right = 124, down = 125, up = 126
    }

    // MARK: - Mouse Synthesis

    private func postMouse(
        _ type: CGEventType,
        at point: CGPoint,
        button: CGMouseButton,
        clicks: Int64 = 1,
        overrideDelta: CGVector? = nil
    ) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }

        let dx: Double
        let dy: Double
        if let overrideDelta {
            dx = Double(overrideDelta.dx)
            dy = Double(overrideDelta.dy)
        } else if let prev = lastCursorPoint {
            dx = Double(point.x - prev.x)
            dy = Double(point.y - prev.y)
        } else {
            dx = 0
            dy = 0
        }
        lastCursorPoint = point

        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event.setDoubleValueField(.mouseEventDeltaX, value: dx)
        event.setDoubleValueField(.mouseEventDeltaY, value: dy)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        switch type {
        case .leftMouseDown, .leftMouseDragged, .rightMouseDown:
            event.setDoubleValueField(.mouseEventPressure, value: 1.0)
        case .leftMouseUp, .rightMouseUp:
            event.setDoubleValueField(.mouseEventPressure, value: 0.0)
        default:
            break
        }
        Self.lastSyntheticMouseTime = ProcessInfo.processInfo.systemUptime
        event.post(tap: .cghidEventTap)
    }

    @inline(__always)
    private func isWithinDoubleClickWindow(at point: CGPoint, now: TimeInterval) -> Bool {
        (now - lastClickTime) < NSEvent.doubleClickInterval &&
        hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < Self.doubleClickRadius
    }

    func move(to point: CGPoint) {
        postMouse(.mouseMoved, at: point, button: .left)
    }

    func cancelDockReveal() {
        dockRevealTimer?.invalidate()
        dockRevealTimer = nil
    }

    /// Summons and reveals the macOS Dock at the bottom of `displayBounds` by synthesizing downward edge-push
    /// `.mouseMoved` events (`mouseEventDeltaY > 0`) at `y = displayBounds.maxY - 1.0`, then parking the cursor inside the Dock.
    func revealDock(at point: CGPoint, displayBounds: CGRect) {
        cancelDockReveal()
        guard displayBounds.width > 0, displayBounds.height > 0 else { return }

        let safeX = min(max(point.x, displayBounds.minX + 95.0), displayBounds.maxX - 95.0)
        let bottomY = displayBounds.maxY - 1.0
        let bottomPoint = CGPoint(x: safeX, y: bottomY)

        // Do NOT call CGWarpMouseCursorPosition here, because CGWarpMouseCursorPosition activates a 250ms
        // WindowServer event suppression interval that blocks Dock edge detection.
        // Instead, smoothly step into the bottom edge using native .mouseMoved CGEvents:
        postMouse(.mouseMoved, at: CGPoint(x: safeX, y: bottomY - 14.0), button: .left, overrideDelta: CGVector(dx: 0, dy: 14))
        postMouse(.mouseMoved, at: CGPoint(x: safeX, y: bottomY - 5.0), button: .left, overrideDelta: CGVector(dx: 0, dy: 9))
        postMouse(.mouseMoved, at: bottomPoint, button: .left, overrideDelta: CGVector(dx: 0, dy: 38))

        var tick = 0
        let maxTicks = 56
        let timer = Timer(timeInterval: 0.015, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            tick += 1

            // Once the Dock has migrated and slid up onto `displayBounds`, park the cursor slightly inside the Dock bar.
            if tick >= 5, tick % 2 == 0, Self.isDockVisible(on: displayBounds) {
                let hoverPoint = CGPoint(x: safeX, y: max(displayBounds.minY + 40, displayBounds.maxY - 34.0))
                self.postMouse(.mouseMoved, at: hoverPoint, button: .left, overrideDelta: CGVector(dx: 0, dy: -8))
                self.dockRevealTimer = nil
                timer.invalidate()
                Log.write("Dock revealed on display at (\(Int(safeX)), \(Int(bottomY))) after \(tick) ticks", force: true)
                return
            }

            if tick == 30 {
                // After 450ms of uninterrupted edge-push (for Full Screen two-stage Dock reveal),
                // re-enter the bottom edge from 8pt above before the second downward push wave.
                self.postMouse(.mouseMoved, at: CGPoint(x: safeX, y: bottomY - 8.0), button: .left, overrideDelta: CGVector(dx: 0, dy: -8))
                self.postMouse(.mouseMoved, at: CGPoint(x: safeX, y: bottomY - 2.0), button: .left, overrideDelta: CGVector(dx: 0, dy: 6))
            } else {
                self.postMouse(.mouseMoved, at: bottomPoint, button: .left, overrideDelta: CGVector(dx: 0, dy: 42))
            }

            if tick >= maxTicks {
                self.dockRevealTimer = nil
                timer.invalidate()
                Log.write("Dock reveal sequence completed at (\(Int(safeX)), \(Int(bottomY)))", force: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dockRevealTimer = timer
    }

    /// Checks via Accessibility (`com.apple.dock`) whether the Dock's `AXList` bar is currently visible inside `displayBounds`.
    private static func isDockVisible(on displayBounds: CGRect) -> Bool {
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return false
        }
        let dockApp = AXUIElementCreateApplication(dockPID)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockApp, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }
        for child in children {
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String,
                  role == (kAXListRole as String) else {
                continue
            }
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let posVal = posRef, let sizeVal = sizeRef else {
                continue
            }
            var pos = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
                  AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
                  size.width > 40, size.height > 20 else {
                continue
            }
            let dockRect = CGRect(origin: pos, size: size)
            let onThisScreenHorizontally = dockRect.midX >= displayBounds.minX && dockRect.midX <= displayBounds.maxX
            let visibleVertically = dockRect.minY < (displayBounds.maxY - 18.0) && dockRect.maxY <= (displayBounds.maxY + 12.0)
            if onThisScreenHorizontally && visibleVertically {
                return true
            }
        }
        return false
    }

    func mouseDown(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        clickCount = isWithinDoubleClickWindow(at: point, now: now) ? (clickCount + 1) : 1
        lastClickTime = now
        lastClickPoint = point

        move(to: point)
        postMouse(.leftMouseDown, at: point, button: .left, clicks: clickCount)
        leftDown = true
    }

    func drag(to point: CGPoint) {
        postMouse(.leftMouseDragged, at: point, button: .left, clicks: clickCount)
    }

    func mouseUp(at point: CGPoint) {
        guard leftDown else { return }
        postMouse(.leftMouseUp, at: point, button: .left, clicks: clickCount)
        leftDown = false
    }

    func click(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let target = isWithinDoubleClickWindow(at: point, now: now) ? lastClickPoint : point
        mouseDown(at: target)
        mouseUp(at: target)
    }

    func rightClick(at point: CGPoint) {
        move(to: point)
        postMouse(.rightMouseDown, at: point, button: .right)
        postMouse(.rightMouseUp, at: point, button: .right)
    }

    // MARK: - Continuous Pixel Scroll & Horizontal Swipe Navigation

    func scroll(dx: Double, dy: Double, at point: CGPoint? = nil, phase: Phase?, momentum: Momentum = .none) {
        let direction = Settings.shared.invertScroll ? -1.0 : 1.0
        scrollRemainderX += dx * direction
        scrollRemainderY += dy * direction

        let integralX = scrollRemainderX.rounded(.towardZero)
        let integralY = scrollRemainderY.rounded(.towardZero)
        scrollRemainderX -= integralX
        scrollRemainderY -= integralY

        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: Int(integralY)),
            wheel2: Int32(clamping: Int(integralX)),
            wheel3: 0
        ) else { return }

        if let point {
            event.location = point
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(HIDEventField.scrollPhase, value: phase?.rawValue ?? 0)
        event.setIntegerValueField(HIDEventField.momentumPhase, value: momentum.rawValue)
        event.setIntegerValueField(HIDEventField.isDirectionInvertedFromDevice, value: Settings.shared.invertScroll ? 0 : 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        event.post(tap: .cghidEventTap)

        if phase == .ended || phase == .cancelled || momentum == .end {
            scrollRemainderX = 0
            scrollRemainderY = 0
        }
    }

    // MARK: - Native Trackpad Magnification, Rotation & Fluid Swipe

    func magnify(_ amount: Double, at point: CGPoint? = nil, phase: Phase) {
        guard let event = CGEvent(source: nil) else { return }
        if let point {
            event.location = point
        }
        event.setIntegerValueField(HIDEventField.eventType, value: 29)      // NSEventTypeGesture
        event.setIntegerValueField(HIDEventField.gestureHIDType, value: 8)  // kIOHIDEventTypeZoom
        event.setIntegerValueField(HIDEventField.gesturePhase, value: phase.rawValue)
        event.setDoubleValueField(HIDEventField.gestureZoomValue, value: amount)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        event.post(tap: .cghidEventTap)
    }

    func rotate(_ degrees: Double, at point: CGPoint? = nil, phase: Phase) {
        guard let event = CGEvent(source: nil) else { return }
        if let point {
            event.location = point
        }
        event.setIntegerValueField(HIDEventField.eventType, value: 29)      // NSEventTypeGesture
        event.setIntegerValueField(HIDEventField.gestureHIDType, value: 5)  // kIOHIDEventTypeRotation
        event.setIntegerValueField(HIDEventField.gesturePhase, value: phase.rawValue)
        event.setDoubleValueField(HIDEventField.gestureZoomValue, value: degrees)
        event.setDoubleValueField(HIDEventField.gestureRotateValue, value: degrees)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        event.post(tap: .cghidEventTap)
    }

    func swipe(_ direction: SwipeDirection, at point: CGPoint? = nil) {
        for phase in [Phase.began, Phase.changed, Phase.ended] {
            guard let event = CGEvent(source: nil) else { continue }
            if let point {
                event.location = point
            }
            event.setIntegerValueField(HIDEventField.eventType, value: 29)       // NSEventTypeGesture
            event.setIntegerValueField(HIDEventField.gestureHIDType, value: 16)  // kIOHIDEventTypeNavigationSwipe
            event.setIntegerValueField(HIDEventField.gesturePhase, value: phase.rawValue)
            event.setIntegerValueField(HIDEventField.gestureSwipeMotion, value: direction.rawValue)
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - System Workspace Shortcuts & Virtual Keyboard Synthesis

    func controlArrow(_ arrow: Arrow) {
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        pressKey(arrow.rawValue, flags: flags)
    }

    func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        Self.lastSyntheticKeyTime = ProcessInfo.processInfo.systemUptime
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func typeUnicode(_ text: String) {
        guard !text.isEmpty else { return }
        var utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else { return }
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
        Self.lastSyntheticKeyTime = ProcessInfo.processInfo.systemUptime
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
