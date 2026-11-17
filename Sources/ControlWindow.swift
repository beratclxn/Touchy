import AppKit
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var state: AppState

    private var isSearching: Bool {
        !state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            TouchyTheme.pageBg
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 240)

                Rectangle()
                    .fill(TouchyTheme.hairline)
                    .frame(width: 1)

                mainContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    // MARK: - Left Graphite Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Touchy")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TouchyTheme.textPrimary)
                    Text("USB-C HID touch driver")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(TouchyTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(TouchyTheme.textMuted)

                TextField("Search", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(TouchyTheme.textPrimary)

                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(TouchyTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TouchyTheme.raisedBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TouchyTheme.hairline, lineWidth: 1)
            )

            Text("Navigation")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(TouchyTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.top, 16)
                .padding(.bottom, 4)

            VStack(spacing: 4) {
                ForEach(SidebarTab.allCases) { tab in
                    sidebarRow(tab)
                }
            }

            Spacer()

            sidebarMasterToggleCard
        }
        .padding(.top, 28)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(TouchyTheme.sidebarBg)
    }

    private func sidebarRow(_ tab: SidebarTab) -> some View {
        let isSelected = (state.selectedTab == tab) && !isSearching
        return Button {
            state.searchQuery = ""
            state.selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isSelected ? TouchyTheme.textPrimary : TouchyTheme.textMuted)
                    .frame(width: 20, height: 20)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? TouchyTheme.textPrimary : TouchyTheme.textSecondary)

                Spacer()

                if tab == .system && !state.accessibilityOK {
                    TouchyStatusDot(color: TouchyTheme.warning)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TouchyTheme.raisedBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(TouchyTheme.hairline, lineWidth: 1)
                            )
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sidebarMasterToggleCard: some View {
        HStack(spacing: 8) {
            TouchyStatusDot(color: state.enabled ? TouchyTheme.positive : TouchyTheme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text("Touch synthesis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TouchyTheme.textPrimary)
                    .lineLimit(1)
                Text(state.enabled ? "Active" : "Paused")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TouchyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $state.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(TouchyTheme.turquoise)
                .labelsHidden()
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

    // MARK: - Right Main Content Area

    private var mainContentView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                touchyPageHeader

                if !state.accessibilityOK && state.selectedTab != .system && !isSearching {
                    permissionWarningBanner
                }

                if isSearching {
                    searchResultsView
                } else {
                    switch state.selectedTab {
                    case .overview: overviewTabContent
                    case .display:  displayTabContent
                    case .gestures: gesturesTabContent
                    case .system:   systemTabContent
                    case .about:    aboutTabContent
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Calm Page Header

    private var touchyPageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isSearching ? "Search results" : state.selectedTab.title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(TouchyTheme.textPrimary)

                Text(isSearching ? "Matching settings for \"\(state.searchQuery)\"" : state.selectedTab.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(TouchyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                TouchyMonoTag(text: contextMonoTag)

                Button {
                    state.onToggleKeyboardNow?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: state.isKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                            .font(.system(size: 14, weight: .regular))
                        Text(state.isKeyboardVisible ? "Hide keyboard" : "Touch keyboard")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(TouchyTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(state.isKeyboardVisible ? TouchyTheme.raisedBg : TouchyTheme.cardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                state.isKeyboardVisible ? TouchyTheme.turquoise.opacity(0.60) : TouchyTheme.hairline,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Show or hide touch keyboard on display")
            }
        }
        .padding(.bottom, 4)
    }

    private var contextMonoTag: String {
        if isSearching { return "FILTER" }
        switch state.selectedTab {
        case .overview:
            return state.isConnected ? "0x0D • \(state.slotCount)ch" : "0x0D • IDLE"
        case .display:
            return state.autoRotate ? "VCP 0xAA" : "\(state.extraRotation)°"
        case .gestures:
            return state.palmRejection ? "STYLUS" : "MULTI"
        case .system:
            return state.accessibilityOK ? "TCC OK" : "TCC REQ"
        case .about:
            return "v2.0 (4)"
        }
    }

    // MARK: - Permission Warning Banner

    private var permissionWarningBanner: some View {
        TouchyGlassCard(
            title: "Accessibility permission required",
            subtitle: "Touchy needs macOS Accessibility authorization to synthesize cursor, scroll, and gesture events",
            tag: "TCC"
        ) {
            HStack(spacing: 12) {
                TouchyStatusDot(color: TouchyTheme.warning)
                Text("Grant access in System Settings → Privacy & Security → Accessibility")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TouchyTheme.textSecondary)
                Spacer()
                Button("Open System & Permissions") {
                    state.selectedTab = .system
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Tab 1: Live Monitor (Digitizer Scope + Aligned Telemetry)

    private var overviewTabContent: some View {
        let isCustomCal = !Settings.shared.calibrationTransform.isIdentity
        return VStack(spacing: 16) {
            digitizerScopeCard

            HStack(alignment: .top, spacing: 16) {
                telemetryCard(
                    title: "HID digitizer",
                    primaryValue: state.isConnected ? state.systemDeviceName : "Disconnected",
                    row1Label: "Controller",
                    row1Value: state.isConnected ? state.deviceSummary : "Waiting for USB-C",
                    row2Label: "Channels",
                    row2Value: state.isConnected ? "\(state.slotCount) fingers" : "Usage 0x0D"
                )

                telemetryCard(
                    title: "Display & rotation",
                    primaryValue: state.activeDisplayName,
                    row1Label: "Orientation",
                    row1Value: state.autoRotate
                        ? "Auto (\(state.sensorOrientationAngle.map { "\($0)°" } ?? "Active"))"
                        : "Manual \(state.extraRotation)°",
                    row2Label: "Calibration",
                    row2Value: isCustomCal ? "4-point active" : "Factory default"
                )

                telemetryCard(
                    title: "Input engine",
                    primaryValue: state.palmRejection ? "Stylus priority" : "Multi-touch",
                    row1Label: "Scroll / Zoom",
                    row1Value: "\(state.twoFingerScroll ? "On" : "Off") / \(state.pinchZoom ? "On" : "Off")",
                    row2Label: "Accessibility",
                    row2Value: state.accessibilityOK ? "Granted" : "Required"
                )
            }
        }
    }

    private func telemetryCard(
        title: String,
        primaryValue: String,
        row1Label: String,
        row1Value: String,
        row2Label: String,
        row2Value: String
    ) -> some View {
        TouchyGlassCard(title: title) {
            VStack(alignment: .leading, spacing: 12) {
                Text(primaryValue)
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(TouchyTheme.textPrimary)
                    .lineLimit(1)

                Rectangle()
                    .fill(TouchyTheme.hairline)
                    .frame(height: 1)

                VStack(spacing: 8) {
                    HStack {
                        Text(row1Label)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(TouchyTheme.textMuted)
                        Spacer(minLength: 8)
                        Text(row1Value)
                            .font(.system(size: 12, weight: .regular))
                            .monospacedDigit()
                            .foregroundColor(TouchyTheme.textSecondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Text(row2Label)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(TouchyTheme.textMuted)
                        Spacer(minLength: 8)
                        Text(row2Value)
                            .font(.system(size: 12, weight: .regular))
                            .monospacedDigit()
                            .foregroundColor(TouchyTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Visual Moment: Live Digitizer Scope

    private var liveCoordinateReadout: String {
        guard let first = state.liveFingers.first else { return "IDLE" }
        if state.liveFingers.count == 1 {
            return String(format: "#%d  X %.3f  Y %.3f", first.id, first.normX, first.normY)
        }
        return String(format: "%dch  #%d  X %.3f  Y %.3f", state.liveFingers.count, first.id, first.normX, first.normY)
    }

    private var digitizerScopeCard: some View {
        TouchyGlassCard(
            title: "Digitizer scope",
            subtitle: state.isConnected
                ? "\(state.systemDeviceName) active — touch external display to inspect raw HID coordinates"
                : "Connect an external touch display to inspect real-time multi-touch coordinates",
            tag: liveCoordinateReadout
        ) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(TouchyTheme.scopeBg)

                    // Coordinate grid lines (rule of fifths)
                    Path { path in
                        for f: CGFloat in [0.2, 0.4, 0.6, 0.8] {
                            path.move(to: CGPoint(x: w * f, y: 0))
                            path.addLine(to: CGPoint(x: w * f, y: h))
                            path.move(to: CGPoint(x: 0, y: h * f))
                            path.addLine(to: CGPoint(x: w, y: h * f))
                        }
                    }
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)

                    // Center crosshair + 4 calibration corner L-reticles
                    Path { path in
                        let cx = w * 0.5
                        let cy = h * 0.5
                        path.move(to: CGPoint(x: cx - 8, y: cy))
                        path.addLine(to: CGPoint(x: cx + 8, y: cy))
                        path.move(to: CGPoint(x: cx, y: cy - 8))
                        path.addLine(to: CGPoint(x: cx, y: cy + 8))

                        let arm: CGFloat = 10
                        let lx = w * 0.12
                        let rx = w * 0.88
                        let ty = h * 0.12
                        let by = h * 0.88

                        // Top-left
                        path.move(to: CGPoint(x: lx, y: ty + arm))
                        path.addLine(to: CGPoint(x: lx, y: ty))
                        path.addLine(to: CGPoint(x: lx + arm, y: ty))

                        // Top-right
                        path.move(to: CGPoint(x: rx - arm, y: ty))
                        path.addLine(to: CGPoint(x: rx, y: ty))
                        path.addLine(to: CGPoint(x: rx, y: ty + arm))

                        // Bottom-left
                        path.move(to: CGPoint(x: lx, y: by - arm))
                        path.addLine(to: CGPoint(x: lx, y: by))
                        path.addLine(to: CGPoint(x: lx + arm, y: by))

                        // Bottom-right
                        path.move(to: CGPoint(x: rx - arm, y: by))
                        path.addLine(to: CGPoint(x: rx, y: by))
                        path.addLine(to: CGPoint(x: rx, y: by - arm))
                    }
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.2)

                    // Normalized axis origin labels
                    VStack {
                        HStack {
                            Text("0.0")
                            Spacer()
                            Text("1.0, 0.0")
                        }
                        Spacer()
                        HStack {
                            Text("0.0, 1.0")
                            Spacer()
                            Text("1.0")
                        }
                    }
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.28))
                    .padding(8)

                    if state.liveFingers.isEmpty {
                        Text("Touch external display to inspect raw HID coordinates")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.45))
                    }

                    // Live contact crosshairs and turquoise touch rings
                    ForEach(state.liveFingers) { finger in
                        let fx = CGFloat(finger.normX) * w
                        let fy = CGFloat(finger.normY) * h

                        Path { path in
                            path.move(to: CGPoint(x: fx, y: 0))
                            path.addLine(to: CGPoint(x: fx, y: h))
                            path.move(to: CGPoint(x: 0, y: fy))
                            path.addLine(to: CGPoint(x: w, y: fy))
                        }
                        .stroke(TouchyTheme.turquoise.opacity(0.25), lineWidth: 1)

                        ZStack {
                            Circle()
                                .stroke(TouchyTheme.turquoise, lineWidth: 1.5)
                                .frame(width: 32, height: 32)

                            Circle()
                                .fill(TouchyTheme.turquoise)
                                .frame(width: 8, height: 8)

                            Text(String(format: "#%d  %.2f, %.2f", finger.id, finger.normX, finger.normY))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(TouchyTheme.aquaLight)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(TouchyTheme.scopeBg.opacity(0.92))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(TouchyTheme.turquoise.opacity(0.45), lineWidth: 1)
                                        )
                                )
                                .offset(y: finger.normY < 0.22 ? 28 : -28)
                        }
                        .position(x: fx, y: fy)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .frame(height: 240)
        }
    }

    // MARK: - Tab 2: Display & Calibration

    private var displayTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "Target monitor & orientation",
                subtitle: "Choose which display receives touch input and configure rotation or axis mirroring"
            ) {
                VStack(spacing: 12) {
                    displayPickerRow(width: 220)
                    rowDivider
                    TouchyToggleRow(
                        icon: "crop.rotate",
                        title: "Auto-rotate display & touch",
                        subtitle: state.sensorOrientationAngle.map { "Active — DDC/CI accelerometer currently reports \($0)°" }
                            ?? "Reads hardware orientation via VESA DDC/CI (VCP 0xAA) and rotates macOS automatically",
                        isOn: $state.autoRotate
                    )
                    if state.autoRotate {
                        rowDivider
                        TouchyToggleRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Invert portrait direction (90° ↔ 270°)",
                            subtitle: "Swap 90° and 270° when portrait orientation appears inverted",
                            isOn: $state.invertAutoRotate
                        )
                    }
                    rowDivider
                    rotationPickerRow(width: 220)
                    rowDivider
                    TouchyToggleRow(
                        icon: "arrow.left.and.right",
                        title: "Flip horizontal axis",
                        subtitle: "Mirror left and right touch coordinates",
                        isOn: $state.flipX
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "arrow.up.and.down",
                        title: "Flip vertical axis",
                        subtitle: "Mirror top and bottom touch coordinates",
                        isOn: $state.flipY
                    )
                }
            }

            TouchyGlassCard(
                title: "4-point precision calibration",
                subtitle: "Touch four corner targets on your external display for sub-pixel alignment"
            ) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        let isDefaultCal = Settings.shared.calibrationTransform.isIdentity
                        Text(isDefaultCal ? "Default factory calibration" : "Custom 4-point calibration active")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isDefaultCal ? TouchyTheme.textSecondary : TouchyTheme.positive)
                        Text("Run calibration when pointer taps land offset from your finger or stylus tip")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(TouchyTheme.textSecondary)
                    }
                    Spacer()
                    Button("Reset to default") { state.onResetCalibration?() }
                        .buttonStyle(.bordered)
                    Button {
                        state.onCalibrate?()
                    } label: {
                        Label("Start 4-point calibration", systemImage: "scope")
                            .foregroundColor(TouchyTheme.accentInk)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TouchyTheme.turquoise)
                }
            }
        }
    }

    private func displayPickerRow(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(TouchyTheme.textMuted)
                .frame(width: 20, height: 20)
            Text("Target external display")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TouchyTheme.textPrimary)
            Spacer()
            Picker("", selection: $state.selectedDisplay) {
                Text(state.hasExternalDisplay ? "Auto (\(state.activeDisplayName))" : "Auto (External only)").tag("__AUTO__")
                if !state.screens.isEmpty {
                    Divider()
                    ForEach(state.screens, id: \.name) { sc in
                        Text(sc.name).tag(sc.name)
                    }
                }
            }
            .labelsHidden()
            .frame(width: width)
        }
        .padding(.vertical, 4)
    }

    private func rotationPickerRow(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rotate.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(TouchyTheme.textMuted)
                .frame(width: 20, height: 20)
            Text("Extra touch rotation")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TouchyTheme.textPrimary)
            Spacer()
            Picker("", selection: $state.extraRotation) {
                Text("0°").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: width)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tab 3: Touch & Stylus

    private var gesturesTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "Stylus & single-finger input",
                subtitle: "Palm rejection, tap behavior, window controls, and automatic keyboard triggers"
            ) {
                VStack(spacing: 12) {
                    TouchyToggleRow(
                        icon: "pencil.and.outline",
                        title: "Palm rejection (stylus priority)",
                        subtitle: "Locks onto active stylus strokes and ignores resting palm clusters",
                        isOn: $state.palmRejection
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "macwindow",
                        title: "Expand window traffic lights on tap",
                        subtitle: "Enlarges window close, minimize, and fullscreen controls into easier touch targets",
                        isOn: $state.expandTrafficLights
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "keyboard",
                        title: "Auto-open touch keyboard in text fields",
                        subtitle: "Shows the floating keyboard on text field focus and dismisses on hardware key input",
                        isOn: $state.touchKeyboard
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "cursorarrow.click",
                        title: "Long press for right-click",
                        subtitle: "Hold one finger stationary for 0.95s to open context menus",
                        isOn: $state.longPressRightClick
                    )
                }
            }

            TouchyGlassCard(
                title: "Multi-finger trackpad gestures",
                subtitle: "Pixel scrolling, inertia, magnification, and macOS Spaces switching"
            ) {
                VStack(spacing: 12) {
                    TouchyToggleRow(
                        icon: "scroll",
                        title: "Two-finger scroll",
                        subtitle: "Vertical and horizontal pixel scrolling across apps and documents",
                        isOn: $state.twoFingerScroll
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "wind",
                        title: "Scroll momentum",
                        subtitle: "Coasts scrolling to a smooth stop after fingers lift",
                        isOn: $state.momentum
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "arrow.up.arrow.down",
                        title: "Invert scroll direction",
                        subtitle: "Reverses natural content scrolling axis",
                        isOn: $state.invertScroll
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "plus.magnifyingglass",
                        title: "Two-finger pinch to zoom",
                        subtitle: "Native macOS magnification in Safari, Preview, Figma, and Maps",
                        isOn: $state.pinchZoom
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "rectangle.3.group",
                        title: "Three-finger swipe",
                        subtitle: "Left/right switches Spaces; up opens Mission Control; down opens App Exposé",
                        isOn: $state.threeFingerSwipe
                    )
                }
            }
        }
    }

    // MARK: - Tab 4: System & Permissions

    private var systemTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "macOS permissions & hardware",
                subtitle: "System authorizations and USB-C HID digitizer discovery"
            ) {
                VStack(spacing: 12) {
                    statusPermissionRow(
                        icon: "checkmark.shield",
                        title: "Accessibility permission",
                        subtitle: state.accessibilityOK
                            ? "Granted — Quartz CGEvent mouse, scroll, and gesture synthesis is active"
                            : "Missing — Enable Touchy in System Settings → Privacy & Security → Accessibility",
                        ok: state.accessibilityOK,
                        actionTitle: "Open Settings",
                        action: { state.onOpenAccessibility?() }
                    )

                    rowDivider

                    statusPermissionRow(
                        icon: "cable.connector",
                        title: state.isConnected ? "Connected: \(state.systemDeviceName)" : "USB HID digitizer",
                        subtitle: state.isConnected
                            ? "\(state.deviceSummary) mapped to \(state.activeDisplayName) (\(state.slotCount) contacts)"
                            : "Waiting for an external USB-C or USB touch display connection",
                        ok: state.isConnected,
                        actionTitle: "Rescan",
                        action: { state.onRescan?() }
                    )

                    rowDivider

                    HStack(spacing: 8) {
                        Button("Reset TCC cache") { state.onResetPermissions?() }
                            .buttonStyle(.bordered)
                        Button("Relaunch Touchy") { state.onRelaunch?() }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }

            TouchyGlassCard(
                title: "System integration",
                subtitle: "Login item, Dock visibility, and low-level IOHID seizure"
            ) {
                VStack(spacing: 12) {
                    TouchyToggleRow(
                        icon: "power",
                        title: "Launch at login",
                        subtitle: "Start Touchy automatically in the background when logging into macOS",
                        isOn: Binding(
                            get: { state.launchAtLogin },
                            set: { _ in state.onToggleLogin?() }
                        )
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "dock.rectangle",
                        title: "Show icon in Dock",
                        subtitle: "When disabled, Touchy runs exclusively from the menu bar",
                        isOn: $state.showInDock
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "lock.shield",
                        title: "Exclusive device access (IOHID seize)",
                        subtitle: "Prevents macOS from routing uncalibrated raw touches to the main screen",
                        isOn: $state.seizeDevice
                    )
                    rowDivider
                    TouchyToggleRow(
                        icon: "terminal",
                        title: "Verbose debug logging",
                        subtitle: "Write raw HID frames and gesture transitions to /tmp/Touchy.log",
                        isOn: $state.debugLog
                    )
                }
            }

            TouchyGlassCard(
                title: "Diagnostics & logs",
                subtitle: "Inspect runtime logs or copy a hardware diagnostics report",
                tag: "/tmp/Touchy.log"
            ) {
                HStack(spacing: 8) {
                    Button {
                        state.onShowLog?()
                    } label: {
                        Label("Open log file", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        state.onCopyDiagnostics?()
                        state.copiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            state.copiedToast = false
                        }
                    } label: {
                        Label(state.copiedToast ? "Copied" : "Copy diagnostics", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private func statusPermissionRow(
        icon: String,
        title: String,
        subtitle: String,
        ok: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(TouchyTheme.textMuted)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    TouchyStatusDot(color: ok ? TouchyTheme.positive : TouchyTheme.warning)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TouchyTheme.textPrimary)
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TouchyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tab 5: About, Compatibility & Legal Notice

    private var aboutTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "Application & driver architecture",
                subtitle: "Release metadata, runtime environment, and low-level system subsystems",
                tag: "Build 4"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    aboutMetadataRow(label: "Application name", value: "Touchy — Universal macOS Multi-Touch & Stylus Driver", ok: true)
                    aboutMetadataRow(label: "Version & build", value: "Version 2.0 (Build 4)", ok: true)
                    aboutMetadataRow(label: "Bundle identifier", value: Bundle.main.bundleIdentifier ?? "com.beratclxn.touchy", ok: true)
                    aboutMetadataRow(label: "Target platform", value: "macOS 13.0+ (Ventura / Sonoma / Sequoia) • Apple Silicon & Intel", ok: true)
                    aboutMetadataRow(
                        label: "Core subsystems",
                        value: "IOKit HID Digitizer (0x0D) • Quartz CGEvent Tap • VESA DDC/CI (IOAVService) • MonitorPanel",
                        ok: true
                    )
                    aboutMetadataRow(
                        label: "Detected hardware",
                        value: state.isConnected ? "\(state.systemDeviceName) (\(state.deviceSummary))" : "No external HID digitizer connected",
                        ok: state.isConnected
                    )
                }
            }

            TouchyGlassCard(
                title: "Hardware verification & compatibility",
                subtitle: "Reference hardware validation status and universal HID standard support"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Verified Reference Hardware — ASUS ProArt Display PA148CTV")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TouchyTheme.textPrimary)

                    Text(
                        "Touchy is engineered around universal industry specifications, including the USB Implementers Forum (USB-IF) HID Digitizer Usage Page (0x0D) for multi-touch and stylus input, and the VESA Monitor Control Command Set (MCCS / DDC/CI VCP 0xAA & 0xEA) for hardware accelerometer orientation sensing.\n\n" +
                        "Hardware notice: Physical hardware validation, multi-touch calibration, 10-finger gesture synthesis, stylus palm rejection, and G-Sensor auto-rotation have been tested and verified on the ASUS ProArt Display PA148CTV.\n\n" +
                        "Compatibility with other external USB-C or HDMI HID touchscreen monitors and pen displays is provided on a standards-compliant best-effort basis. Vendor-specific HID descriptors or non-standard coordinate ranges on untested monitors may require manual 4-point calibration or rotation adjustment."
                    )
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TouchyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            TouchyGlassCard(
                title: "Legal notice, trademarks & disclaimer",
                subtitle: "Intellectual property disclosures, local-only privacy statement, and limitation of liability"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        Text("1. Third-Party Trademarks & Non-Affiliation")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TouchyTheme.textPrimary)
                        Text(
                            "\"ASUS\" and \"ProArt\" are registered trademarks of ASUSTeK Computer Inc. \"Apple\", \"macOS\", \"Quartz\", and \"Retina\" are trademarks of Apple Inc., registered in the U.S. and other countries. Product and company names are used strictly for hardware identification and interoperability; their use does not imply affiliation or endorsement."
                        )
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(TouchyTheme.textSecondary)

                        rowDivider

                        Text("2. Privacy & System Permissions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TouchyTheme.textPrimary)
                        Text(
                            "Touchy operates 100% locally on your Mac with zero network connectivity, telemetry, or analytics. macOS Accessibility (TCC) and Input Monitoring permissions are used exclusively in real time to read raw USB HID Digitizer coordinates and synthesize Quartz cursor, scroll, and gesture events. Touchy never records, stores, or transmits keystrokes or personal user data."
                        )
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(TouchyTheme.textSecondary)

                        rowDivider

                        Text("3. Disclaimer of Warranty & Limitation of Liability")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(TouchyTheme.textPrimary)
                        Text(
                            "THIS SOFTWARE IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, HARDWARE COMPATIBILITY, AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, DISPLAY CONFIGURATION ALTERATIONS, OR OTHER LIABILITY ARISING FROM THE USE OF THIS SOFTWARE."
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TouchyTheme.textMuted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func aboutMetadataRow(label: String, value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TouchyStatusDot(color: ok ? TouchyTheme.positive : TouchyTheme.warning)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TouchyTheme.textPrimary)
                .frame(width: 172, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(TouchyTheme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(TouchyTheme.hairline)
            .frame(height: 1)
    }

    private var searchResultsView: some View {
        let q = state.searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let matchDisplay = "display calibration monitor orientation rotate g-sensor flip screen target".contains(q) || q.contains("display") || q.contains("rotate") || q.contains("calibr") || q.contains("flip")
        let matchGestures = "gestures touch stylus palm traffic lights window buttons red yellow green keyboard mini textbox input right click scroll momentum inertia zoom pinch spaces mission control".contains(q) || q.contains("palm") || q.contains("traffic") || q.contains("keyboard") || q.contains("scroll") || q.contains("zoom") || q.contains("gesture") || q.contains("stylus") || q.contains("click")
        let matchSystem = "system permissions accessibility privacy login dock iohid seize logs diagnostics tcc".contains(q) || q.contains("access") || q.contains("perm") || q.contains("login") || q.contains("dock") || q.contains("log") || q.contains("seize")
        let matchAbout = "about legal version proart asus license warranty disclaimer architecture".contains(q) || q.contains("about") || q.contains("asus") || q.contains("version") || q.contains("legal")
        let hasAny = matchDisplay || matchGestures || matchSystem || matchAbout

        return VStack(spacing: 16) {
            if matchDisplay { displayTabContent }
            if matchGestures { gesturesTabContent }
            if matchSystem { systemTabContent }
            if matchAbout { aboutTabContent }
            if !hasAny {
                TouchyGlassCard(
                    title: "No matching settings",
                    subtitle: "No controls found matching \"\(state.searchQuery)\""
                ) {
                    Text("Try searching for \"scroll\", \"palm\", \"display\", \"calibration\", \"permission\", or \"rotate\".")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(TouchyTheme.textSecondary)
                }
            }
        }
    }
}

final class ControlWindowController {
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        AppState.shared.syncFromSettings()
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: ControlPanelView(state: AppState.shared))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Touchy"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.toolbarStyle = .unified
        win.contentViewController = hosting
        win.isReleasedWhenClosed = false
        win.center()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win
    }
}
