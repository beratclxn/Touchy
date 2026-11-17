import AppKit
import SwiftUI

/// Menu Bar Bento Control Center popover matching the frosted-glass Bento layout.
struct MenuBarBentoView: View {
    @ObservedObject var state: AppState
    var onClosePopover: (() -> Void)?

    private let shellBg = Color(white: 0.92, opacity: 0.95)
    private let cardBg = Color(white: 0.97, opacity: 0.86)
    private let pillBg = Color(white: 0.85, opacity: 0.90)
    private let circleOffBg = Color(white: 0.82, opacity: 0.95)
    private let circleOnBg = Color(white: 0.14, opacity: 1.0)
    private let textPrimary = Color(white: 0.12)
    private let textSecondary = Color(white: 0.46)

    var body: some View {
        VStack(spacing: 12) {
            topDeviceBannerCard

            if state.bentoTab == .home {
                bentoTileGrid
                middleDisplayTouchCard
            } else {
                bentoSystemCard
            }

            bottomNavigationBar
        }
        .padding(14)
        .frame(width: 358)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(shellBg)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    // MARK: - 1. Top Banner Card

    private var topDeviceBannerCard: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.14), radius: 3, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Touchy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(textPrimary)
                    .lineLimit(1)

                Text(bannerSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    onClosePopover?()
                    state.onToggleKeyboardNow?()
                } label: {
                    ZStack {
                        Circle()
                            .fill(state.isKeyboardVisible ? circleOnBg : circleOffBg)
                            .frame(width: 36, height: 36)
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(state.isKeyboardVisible ? .white : Color(white: 0.25))
                    }
                }
                .buttonStyle(.plain)
                .help("Show / Hide Touch Keyboard")

                topCircleButton(icon: "arrow.clockwise", help: "Rescan USB-C Touch & Displays") {
                    state.onRescan?()
                    state.flashBentoHint("Devices Rescanned")
                }

                Button {
                    state.enabled.toggle()
                    state.flashBentoHint(state.enabled ? "Touch Enabled" : "Touch Disabled")
                } label: {
                    ZStack {
                        Circle()
                            .fill(state.enabled ? circleOnBg : circleOffBg)
                            .frame(width: 36, height: 36)
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(state.enabled ? .white : Color(white: 0.30))
                    }
                }
                .buttonStyle(.plain)
                .help(state.enabled ? "Disable Touch Input" : "Enable Touch Input")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(cardBg))
    }

    private var bannerSubtitle: String {
        if let hint = state.bentoStatusHint { return hint }
        if !state.enabled { return "Touch Disabled" }
        if !state.accessibilityOK { return "Accessibility Required" }
        return state.isConnected
            ? "\(state.systemDeviceName) • Connected"
            : "Waiting for Touch Display"
    }

    private func topCircleButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(circleOffBg).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(white: 0.25))
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 2. 2×4 Bento Quick-Toggle Grid (8 Unique Feature Toggles)

    private var bentoTileGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                bentoTile(icon: "pencil.and.outline", title: "Palm Reject", isOn: state.palmRejection, help: "Universal Stylus Palm Rejection") {
                    state.palmRejection.toggle()
                    state.flashBentoHint("Stylus Palm Rejection: \(state.palmRejection ? "On" : "Off")")
                }
                bentoTile(icon: "hand.tap.fill", title: "Right Click", isOn: state.longPressRightClick, help: "Long press with one finger for right-click") {
                    state.longPressRightClick.toggle()
                    state.flashBentoHint("Long Press Right Click: \(state.longPressRightClick ? "On" : "Off")")
                }
                bentoTile(icon: "arrow.up.and.down", title: "Scroll", isOn: state.twoFingerScroll, help: "Two-finger smooth scrolling") {
                    state.twoFingerScroll.toggle()
                    state.flashBentoHint("Two-Finger Scroll: \(state.twoFingerScroll ? "On" : "Off")")
                }
                bentoTile(icon: "wind", title: "Momentum", isOn: state.momentum, help: "Smooth scrolling inertia after lifting fingers") {
                    state.momentum.toggle()
                    state.flashBentoHint("Scroll Momentum: \(state.momentum ? "On" : "Off")")
                }
            }

            HStack(spacing: 10) {
                bentoTile(icon: "arrow.up.left.and.arrow.down.right", title: "Pinch Zoom", isOn: state.pinchZoom, help: "Two-finger pinch to zoom") {
                    state.pinchZoom.toggle()
                    state.flashBentoHint("Pinch to Zoom: \(state.pinchZoom ? "On" : "Off")")
                }
                bentoTile(icon: "rectangle.3.group.fill", title: "3-Finger", isOn: state.threeFingerSwipe, help: "Three-finger swipe for Spaces & Mission Control") {
                    state.threeFingerSwipe.toggle()
                    state.flashBentoHint("3-Finger Spaces: \(state.threeFingerSwipe ? "On" : "Off")")
                }
                bentoTile(icon: "arrow.up.arrow.down.circle.fill", title: "Invert Scroll", isOn: state.invertScroll, help: "Invert natural scroll direction") {
                    state.invertScroll.toggle()
                    state.flashBentoHint("Invert Scroll: \(state.invertScroll ? "On" : "Off")")
                }
                bentoTile(icon: "dock.rectangle", title: "Dock Icon", isOn: state.showInDock, help: "Show or hide Touchy in macOS Dock") {
                    state.showInDock.toggle()
                    state.flashBentoHint("Dock Icon: \(state.showInDock ? "Visible" : "Hidden")")
                }
            }
        }
    }

    private func bentoTile(icon: String, title: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(isOn ? circleOnBg : circleOffBg).frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(isOn ? .white : Color(white: 0.34))
                }
                Text(title)
                    .font(.system(size: 10.5, weight: isOn ? .bold : .semibold))
                    .foregroundColor(isOn ? textPrimary : textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(cardBg))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 3. Middle Display, Rotation & Live Touch Card

    // MARK: - 3. Display & Rotation Card

    private var middleDisplayTouchCard: some View {
        HStack(spacing: 8) {
            Button {
                state.cycleDisplay()
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(white: 0.16))
                            .frame(width: 28, height: 28)
                        Image(systemName: "display")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.hasExternalDisplay ? state.activeDisplayName : "No External Display")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(textPrimary)
                            .lineLimit(1)
                        Text(state.screens.count > 1 ? "External Display • Switch" : "External Display Only")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)

            Button {
                state.autoRotate.toggle()
                state.flashBentoHint("Auto-Rotate (G-Sensor): \(state.autoRotate ? "On" : "Off")")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "crop.rotate")
                        .font(.system(size: 11, weight: .bold))
                    Text(state.autoRotate ? "Auto" : "Manual")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .foregroundColor(state.autoRotate ? .white : Color(white: 0.22))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(state.autoRotate ? circleOnBg : Color.white.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .help("Toggle G-Sensor Auto-Rotate")

            Button {
                state.cycleRotation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(state.extraRotation)°")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(white: 0.22))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .help("Rotate touch orientation (0° / 90° / 180° / 270°)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(cardBg))
    }

    // MARK: - System Tab Content

    private var bentoSystemCard: some View {
        let isCustomCal = !Settings.shared.calibrationTransform.isIdentity
        return VStack(spacing: 9) {
            bentoSystemRow(
                icon: state.accessibilityOK ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                title: "Accessibility Access",
                value: state.accessibilityOK ? "Active ✓" : "Grant…"
            ) {
                onClosePopover?()
                state.onOpenAccessibility?()
            }

            bentoSystemRow(
                icon: isCustomCal ? "arrow.counterclockwise.circle.fill" : "scope",
                title: isCustomCal ? "Reset Calibration" : "Start 4-Point Calibration",
                value: isCustomCal ? "Reset to Default" : "Run…"
            ) {
                if isCustomCal {
                    state.onResetCalibration?()
                    state.flashBentoHint("Reset to Factory Default")
                } else {
                    onClosePopover?()
                    state.onCalibrate?()
                }
            }

            bentoSystemRow(
                icon: "lock.shield.fill",
                title: "Exclusive Access (Seize)",
                value: state.seizeDevice ? "On" : "Off"
            ) {
                state.seizeDevice.toggle()
            }

            bentoSystemRow(
                icon: "power.circle.fill",
                title: "Launch at Login",
                value: state.launchAtLogin ? "On" : "Off"
            ) {
                state.onToggleLogin?()
            }

            bentoSystemRow(
                icon: "doc.on.clipboard",
                title: "Diagnostics Report",
                value: state.copiedToast ? "Copied! ✓" : "Copy"
            ) {
                state.onCopyDiagnostics?()
                state.flashBentoHint("Diagnostics Copied to Clipboard")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(cardBg))
    }

    private func bentoSystemRow(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(circleOffBg).frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(white: 0.24))
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(textPrimary)
                Spacer()
                Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.045)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Bottom Navigation Bar

    private var bottomNavigationBar: some View {
        HStack(spacing: 8) {
            // Segmented Tab Switcher (Home / System)
            HStack(spacing: 2) {
                bentoNavTab(tab: .home, icon: "square.grid.2x2.fill", title: "Home")
                bentoNavTab(tab: .system, icon: "cpu", title: "System")
            }
            .padding(3)
            .background(Capsule().fill(cardBg).shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1))

            Spacer(minLength: 6)

            // Settings Window Launcher Button
            Button {
                onClosePopover?()
                state.onOpenControlPanel?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5, weight: .bold))
                    Text("Settings…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6.5)
                .background(Capsule().fill(cardBg).shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1))
            }
            .buttonStyle(.plain)
            .help("Open Full Touchy Settings Window (⌘,)")

            // Quit App Button
            Button {
                state.onQuit?()
            } label: {
                ZStack {
                    Circle()
                        .fill(cardBg)
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                    Image(systemName: "power")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color.red.opacity(0.75))
                }
            }
            .buttonStyle(.plain)
            .help("Quit Touchy (⌘Q)")
        }
    }

    private func bentoNavTab(tab: BentoTab, icon: String, title: String) -> some View {
        let isSelected = (state.bentoTab == tab)
        return Button {
            state.bentoTab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(isSelected ? textPrimary : textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Capsule().fill(isSelected ? pillBg : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

final class BentoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class MenuBarPopoverController {
    private var panel: BentoPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        isShown ? close() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        AppState.shared.syncFromSettings()
        if panel == nil {
            let rootView = MenuBarBentoView(state: AppState.shared) { [weak self] in
                self?.close()
            }
            let hosting = NSHostingView(rootView: rootView)
            let panelWidth: CGFloat = 358
            let panelHeight: CGFloat = 384
            hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

            let p = BentoPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.contentView = hosting
            panel = p
        }

        guard let panel, let btnWindow = button.window else { return }
        let btnRectInWindow = button.convert(button.bounds, to: nil)
        let btnRectOnScreen = btnWindow.convertToScreen(btnRectInWindow)

        let pSize = panel.frame.size
        var x = btnRectOnScreen.midX - pSize.width / 2
        let y = btnRectOnScreen.minY - pSize.height - 6

        if let screen = btnWindow.screen ?? NSScreen.main {
            let sFrame = screen.visibleFrame
            x = max(sFrame.minX + 8, min(x, sFrame.maxX - pSize.width - 8))
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }
}
