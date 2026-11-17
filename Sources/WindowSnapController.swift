import AppKit
import ApplicationServices
import SwiftUI

enum WindowSnapZone: Equatable {
    case leftHalf
    case rightHalf
    case maximize
}

final class WindowSnapPreviewState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var zone: WindowSnapZone = .leftHalf
}

private struct WindowSnapPreviewView: View {
    @ObservedObject var state: WindowSnapPreviewState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.72)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TouchyTheme.aquaLight.opacity(0.28),
                            TouchyTheme.tealDeep.opacity(0.18),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            TouchyTheme.aquaLight.opacity(0.85),
                            Color.white.opacity(0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.0
                )
        }
        .padding(8)
        .scaleEffect(state.isVisible ? 1.0 : 0.94)
        .opacity(state.isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: state.isVisible)
    }
}

private final class WindowSnapPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Provides native-style Left / Right / Top-Maximize Window Snapping when dragging windows by touch.
final class WindowSnapController {
    static let shared = WindowSnapController()

    private static let edgeThreshold: CGFloat = 34.0
    private static let minWindowMoveConfirmation: CGFloat = 10.0

    private let previewState = WindowSnapPreviewState()
    private var previewPanel: WindowSnapPreviewPanel?

    private var trackedWindow: AXUIElement?
    private var initialWindowOrigin: CGPoint = .zero
    private var confirmedWindowDrag: Bool = false
    private var dragCheckRejected: Bool = false
    private var activeZone: WindowSnapZone?
    private var activeSnapQuartzRect: CGRect = .zero

    private init() {}

    // MARK: - Drag Lifecycle

    /// Called when a single-finger drag starts at `startPoint` (in Quartz screen coordinates).
    func beginDrag(at startPoint: CGPoint) {
        resetState()

        // Ignore drags starting inside our own floating overlays.
        if TouchKeyboardController.shared.contains(startPoint) || TrafficLightOverlayController.shared.contains(startPoint) {
            dragCheckRejected = true
            return
        }

        let systemWide = AXUIElementCreateSystemWide()
        var hitRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(startPoint.x), Float(startPoint.y), &hitRef) == .success,
              let hit = hitRef,
              let win = Self.enclosingWindow(of: hit),
              let initialOrigin = Self.position(of: win) else {
            dragCheckRejected = true
            return
        }

        // Only track standard movable/resizable windows (not Full Screen windows).
        var posSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(win, kAXPositionAttribute as CFString, &posSettable) == .success,
              posSettable.boolValue,
              AXUIElementIsAttributeSettable(win, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              sizeSettable.boolValue,
              !Self.isFullScreen(win) else {
            dragCheckRejected = true
            return
        }

        trackedWindow = win
        initialWindowOrigin = initialOrigin
    }

    /// Called during `handleDragging` with the current finger position in Quartz coordinates.
    func updateDrag(at currentPoint: CGPoint) {
        guard !dragCheckRejected, let win = trackedWindow else { return }

        let displayID = Self.displayContaining(quartzPoint: currentPoint)
        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else { return }

        // Check if the finger is near the Left, Right, or Top snap edges of this display.
        let nearLeft = (currentPoint.x - displayBounds.minX) <= Self.edgeThreshold
        let nearRight = (displayBounds.maxX - currentPoint.x) <= Self.edgeThreshold
        let nearTop = (currentPoint.y - displayBounds.minY) <= Self.edgeThreshold
            && (currentPoint.x - displayBounds.minX) > 100.0
            && (displayBounds.maxX - currentPoint.x) > 100.0

        guard nearLeft || nearRight || nearTop else {
            if activeZone != nil {
                hidePreview()
            }
            return
        }

        // Confirm that the window's AXPosition actually moved during this drag (distinguishing window-dragging
        // from selecting text or drawing inside a canvas that touches the screen edge).
        if !confirmedWindowDrag {
            guard let currentOrigin = Self.position(of: win) else {
                dragCheckRejected = true
                return
            }
            let windowMoved = hypot(currentOrigin.x - initialWindowOrigin.x, currentOrigin.y - initialWindowOrigin.y)
            if windowMoved >= Self.minWindowMoveConfirmation {
                confirmedWindowDrag = true
            } else {
                return
            }
        }

        let visibleRect = Self.visibleQuartzRect(forDisplay: displayID)
        let zone: WindowSnapZone
        let targetRect: CGRect

        if nearLeft {
            zone = .leftHalf
            targetRect = CGRect(
                x: visibleRect.minX,
                y: visibleRect.minY,
                width: floor(visibleRect.width * 0.5),
                height: visibleRect.height
            )
        } else if nearRight {
            zone = .rightHalf
            let halfWidth = floor(visibleRect.width * 0.5)
            targetRect = CGRect(
                x: visibleRect.maxX - halfWidth,
                y: visibleRect.minY,
                width: halfWidth,
                height: visibleRect.height
            )
        } else {
            zone = .maximize
            targetRect = visibleRect
        }

        if activeZone != zone || activeSnapQuartzRect != targetRect {
            activeZone = zone
            activeSnapQuartzRect = targetRect
            showPreview(quartzRect: targetRect, zone: zone)
        }
    }

    /// Called when the single-finger drag ends at `endPoint`. If a snap zone is active, snaps the dragged window.
    func endDrag(at endPoint: CGPoint) {
        defer { resetState() }
        guard confirmedWindowDrag,
              let win = trackedWindow,
              let zone = activeZone,
              activeSnapQuartzRect.width > 0,
              activeSnapQuartzRect.height > 0 else {
            hidePreview()
            return
        }

        let targetRect = activeSnapQuartzRect
        hidePreview()

        // Apply Size -> Position -> Size on the next runloop tick (after mouseUp finishes moving the window).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            Self.setWindowFrame(win, to: targetRect)
            Log.write("Window snapped to \(zone) -> (\(Int(targetRect.minX)), \(Int(targetRect.minY)), \(Int(targetRect.width))x\(Int(targetRect.height)))", force: true)
        }
    }

    func cancelDrag() {
        hidePreview()
        resetState()
    }

    private func resetState() {
        trackedWindow = nil
        initialWindowOrigin = .zero
        confirmedWindowDrag = false
        dragCheckRejected = false
        activeZone = nil
        activeSnapQuartzRect = .zero
    }

    // MARK: - Preview Panel

    private func showPreview(quartzRect: CGRect, zone: WindowSnapZone) {
        ensurePreviewPanel()
        guard let panel = previewPanel else { return }

        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let appKitY = primaryHeight - quartzRect.minY - quartzRect.height
        let appKitFrame = NSRect(x: quartzRect.minX, y: appKitY, width: quartzRect.width, height: quartzRect.height)

        previewState.zone = zone
        panel.setFrame(appKitFrame, display: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            self?.previewState.isVisible = true
        }
    }

    private func hidePreview() {
        activeZone = nil
        activeSnapQuartzRect = .zero
        guard previewPanel?.isVisible == true else { return }
        previewState.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, !self.previewState.isVisible else { return }
            self.previewPanel?.orderOut(nil)
        }
    }

    private func ensurePreviewPanel() {
        guard previewPanel == nil else { return }
        let p = WindowSnapPreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: WindowSnapPreviewView(state: previewState))
        previewPanel = p
    }

    // MARK: - Accessibility & Display Helpers

    private static func setWindowFrame(_ window: AXUIElement, to rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    private static func displayContaining(quartzPoint: CGPoint) -> CGDirectDisplayID {
        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(quartzPoint, 1, &displayID, &count)
        return displayID
    }

    /// Returns the usable desktop rect (excluding Menu Bar and Dock) in global Quartz coordinates.
    private static func visibleQuartzRect(forDisplay displayID: CGDirectDisplayID) -> CGRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == displayID {
                let vf = screen.visibleFrame
                let qy = primaryHeight - vf.origin.y - vf.height
                return CGRect(x: vf.origin.x, y: qy, width: vf.width, height: vf.height)
            }
        }
        return CGDisplayBounds(displayID)
    }

    private static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           (roleRef as? String) == (kAXWindowRole as String) {
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
            var rRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &rRef) == .success,
               (rRef as? String) == (kAXWindowRole as String) {
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

    private static func position(of element: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              let posVal = posRef else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func isFullScreen(_ window: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref) == .success,
           let num = ref as? NSNumber {
            return num.boolValue
        }
        return false
    }
}
