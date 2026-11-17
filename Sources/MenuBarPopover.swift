import AppKit
import SwiftUI

/// Compact Menu Bar Control Center popover using the Touchy graphite ramp and nested radii.
struct MenuBarBentoView: View {
    @ObservedObject var state: AppState
    var onClosePopover: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            topDeviceBannerCard

            if state.bentoTab == .home {
                bentoTileGrid
                middleDisplayTouchCard
            } else {
                bentoSystemCard
            }

            Spacer(minLength: 0)

            bottomNavigationBar
        }
        .padding(12)
        .frame(width: 340, height: 348)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TouchyTheme.pageBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TouchyTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 1. Top Device Bar

    private var topDeviceBannerCard: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Touchy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TouchyTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    TouchyStatusDot(color: statusDotColor)
                    Text(bannerSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(TouchyTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                topActionButton(
                    icon: "keyboard",
                    isActive: state.isKeyboardVisible,
                    help: "Show or hide touch keyboard"
                ) {
                    onClosePopover?()
                    state.onToggleKeyboardNow?()
                }

                topActionButton(
                    icon: "arrow.clockwise",
                    isActive: false,
                    help: "Rescan USB-C touch and displays"
                ) {
                    state.onRescan?()
                    state.flashBentoHint("Devices rescanned")
                }

                topActionButton(
                    icon: "power",
                    isActive: state.enabled,
                    help: state.enabled ? "Disable touch input" : "Enable touch input"
                ) {
                    state.enabled.toggle()
                    state.flashBentoHint(state.enabled ? "Touch enabled" : "Touch paused")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TouchyTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TouchyTheme.hairline, lineWidth: 1)
        )
    }

    private var statusDotColor: Color {
        if !state.enabled { return TouchyTheme.textMuted }
        if !state.accessibilityOK { return TouchyTheme.warning }
        return state.isConnected ? TouchyTheme.positive : TouchyTheme.textMuted
    }

    private var bannerSubtitle: String {
        if let hint = state.bentoStatusHint { return hint }
        if !state.enabled { return "Touch paused" }
        if !state.accessibilityOK { return "Accessibility needed" }
        return state.isConnected
            ? state.systemDeviceName
            : "Waiting for display"
    }

    private func topActionButton(
        icon: String,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isActive ? TouchyTheme.accentInk : TouchyTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? TouchyTheme.turquoise : TouchyTheme.raisedBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? Color.clear : TouchyTheme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 2. 2×4 Quick-Toggle Grid

    private var bentoTileGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                bentoTile(icon: "pencil.and.outline", title: "Palm reject", isOn: state.palmRejection, help: "Stylus palm rejection") {
                    state.palmRejection.toggle()
                    state.flashBentoHint("Palm rejection: \(state.palmRejection ? "On" : "Off")")
                }
                bentoTile(icon: "cursorarrow.click", title: "Right click", isOn: state.longPressRightClick, help: "Long press for right-click") {
                    state.longPressRightClick.toggle()
                    state.flashBentoHint("Long press right-click: \(state.longPressRightClick ? "On" : "Off")")
                }
                bentoTile(icon: "scroll", title: "Scroll", isOn: state.twoFingerScroll, help: "Two-finger smooth scrolling") {
                    state.twoFingerScroll.toggle()
                    state.flashBentoHint("Two-finger scroll: \(state.twoFingerScroll ? "On" : "Off")")
                }
                bentoTile(icon: "wind", title: "Momentum", isOn: state.momentum, help: "Scroll inertia after lifting fingers") {
                    state.momentum.toggle()
                    state.flashBentoHint("Scroll momentum: \(state.momentum ? "On" : "Off")")
                }
            }

            HStack(spacing: 8) {
                bentoTile(icon: "plus.magnifyingglass", title: "Pinch zoom", isOn: state.pinchZoom, help: "Two-finger pinch to zoom") {
                    state.pinchZoom.toggle()
                    state.flashBentoHint("Pinch to zoom: \(state.pinchZoom ? "On" : "Off")")
                }
                bentoTile(icon: "rectangle.3.group", title: "3-finger", isOn: state.threeFingerSwipe, help: "Three-finger Spaces & Mission Control") {
                    state.threeFingerSwipe.toggle()
                    state.flashBentoHint("3-finger gestures: \(state.threeFingerSwipe ? "On" : "Off")")
                }
                bentoTile(icon: "arrow.up.arrow.down", title: "Invert scroll", isOn: state.invertScroll, help: "Reverse natural scroll direction") {
                    state.invertScroll.toggle()
                    state.flashBentoHint("Invert scroll: \(state.invertScroll ? "On" : "Off")")
                }
                bentoTile(icon: "dock.rectangle", title: "Dock icon", isOn: state.showInDock, help: "Show Touchy in macOS Dock") {
                    state.showInDock.toggle()
                    state.flashBentoHint("Dock icon: \(state.showInDock ? "Visible" : "Hidden")")
                }
            }
        }
    }

    private func bentoTile(icon: String, title: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isOn ? TouchyTheme.textPrimary : TouchyTheme.textMuted)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn ? TouchyTheme.textPrimary : TouchyTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? TouchyTheme.raisedBg : TouchyTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOn ? TouchyTheme.turquoise.opacity(0.45) : TouchyTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 3. Display & Rotation Bar

    private var middleDisplayTouchCard: some View {
        HStack(spacing: 8) {
            Button {
                state.cycleDisplay()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(TouchyTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(TouchyTheme.raisedBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(TouchyTheme.hairline, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.hasExternalDisplay ? state.activeDisplayName : "No external display")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(TouchyTheme.textPrimary)
                            .lineLimit(1)
                        Text(state.screens.count > 1 ? "Switch display" : "External touch")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(TouchyTheme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)

            Button {
                state.autoRotate.toggle()
                state.flashBentoHint("Auto-rotate: \(state.autoRotate ? "On" : "Off")")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "crop.rotate")
                        .font(.system(size: 11, weight: .regular))
                    Text(state.autoRotate ? "Auto" : "Manual")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(state.autoRotate ? TouchyTheme.accentInk : TouchyTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(state.autoRotate ? TouchyTheme.turquoise : TouchyTheme.raisedBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(state.autoRotate ? Color.clear : TouchyTheme.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Toggle DDC/CI auto-rotate")

            Button {
                state.cycleRotation()
            } label: {
                Text("\(state.extraRotation)°")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(TouchyTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(TouchyTheme.raisedBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(TouchyTheme.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Rotate touch coordinates (0° / 90° / 180° / 270°)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TouchyTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TouchyTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - System Tab Content

    private var bentoSystemCard: some View {
        let isCustomCal = !Settings.shared.calibrationTransform.isIdentity
        return VStack(spacing: 4) {
            bentoSystemRow(
                icon: state.accessibilityOK ? "checkmark.shield" : "exclamationmark.triangle",
                title: "Accessibility access",
                value: state.accessibilityOK ? "Granted" : "Grant",
                valueColor: state.accessibilityOK ? TouchyTheme.positive : TouchyTheme.warning
            ) {
                onClosePopover?()
                state.onOpenAccessibility?()
            }

            bentoSystemRow(
                icon: isCustomCal ? "arrow.counterclockwise" : "scope",
                title: isCustomCal ? "Reset calibration" : "4-point calibration",
                value: isCustomCal ? "Reset" : "Start"
            ) {
                if isCustomCal {
                    state.onResetCalibration?()
                    state.flashBentoHint("Calibration reset")
                } else {
                    onClosePopover?()
                    state.onCalibrate?()
                }
            }

            bentoSystemRow(
                icon: "lock.shield",
                title: "Exclusive access (seize)",
                value: state.seizeDevice ? "On" : "Off"
            ) {
                state.seizeDevice.toggle()
            }

            bentoSystemRow(
                icon: "power",
                title: "Launch at login",
                value: state.launchAtLogin ? "On" : "Off"
            ) {
                state.onToggleLogin?()
            }

            bentoSystemRow(
                icon: "doc.on.clipboard",
                title: "Diagnostics report",
                value: state.copiedToast ? "Copied" : "Copy",
                valueColor: state.copiedToast ? TouchyTheme.positive : TouchyTheme.textSecondary
            ) {
                state.onCopyDiagnostics?()
                state.flashBentoHint("Diagnostics copied")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TouchyTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TouchyTheme.hairline, lineWidth: 1)
        )
    }

    private func bentoSystemRow(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = TouchyTheme.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(TouchyTheme.textMuted)
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(TouchyTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(valueColor)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TouchyTheme.raisedBg.opacity(0.65))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Bottom Navigation Bar

    private var bottomNavigationBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                bentoNavTab(tab: .home, icon: "square.grid.2x2", title: "Home")
                bentoNavTab(tab: .system, icon: "cpu", title: "System")
            }
            .padding(3)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TouchyTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TouchyTheme.hairline, lineWidth: 1)
            )

            Spacer(minLength: 4)

            Button {
                onClosePopover?()
                state.onOpenControlPanel?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .regular))
                    Text("Settings…")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(TouchyTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TouchyTheme.cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TouchyTheme.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Open Touchy settings window (⌘,)")

            Button {
                state.onQuit?()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TouchyTheme.danger)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TouchyTheme.cardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TouchyTheme.hairline, lineWidth: 1)
                    )
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
                    .font(.system(size: 11.5, weight: .regular))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(isSelected ? TouchyTheme.textPrimary : TouchyTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? TouchyTheme.raisedBg : Color.clear)
            )
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
            let panelWidth: CGFloat = 340
            let panelHeight: CGFloat = 348
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
