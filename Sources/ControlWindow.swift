import AppKit
import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var state: AppState

    private var isSearching: Bool {
        !state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            backgroundAtmosphere

            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 238)

                Divider()
                    .opacity(0.25)

                mainContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    // MARK: - Ambient Background

    private var backgroundAtmosphere: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            Circle()
                .fill(TouchyTheme.aquaLight.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -260, y: -190)

            Circle()
                .fill(TouchyTheme.tealDeep.opacity(0.14))
                .frame(width: 460, height: 460)
                .blur(radius: 110)
                .offset(x: 260, y: 200)
        }
        .ignoresSafeArea()
    }

    // MARK: - Left Liquid Glass Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer().frame(height: 22)

            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .shadow(color: TouchyTheme.tealDeep.opacity(0.35), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Touchy")
                            .font(.system(size: 14, weight: .bold))
                        Text("2.0")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(TouchyTheme.accentGradient)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    Text("Universal macOS Touch Driver")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 2)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Search settings…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))

                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 12)

            Text("CATEGORIES")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.75))
                .padding(.horizontal, 18)
                .padding(.top, 4)

            VStack(spacing: 4) {
                ForEach(SidebarTab.allCases) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            sidebarMasterToggleCard
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .background(.ultraThinMaterial)
    }

    private func sidebarRow(_ tab: SidebarTab) -> some View {
        let isSelected = (state.selectedTab == tab) && !isSearching
        return Button {
            state.searchQuery = ""
            state.selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                TouchySquircleIcon(systemName: tab.icon, colors: tab.gradientColors, size: 26)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.82))

                Spacer()

                if tab == .system && !state.accessibilityOK {
                    Circle().fill(TouchyTheme.amber).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [TouchyTheme.aquaLight.opacity(0.24), TouchyTheme.turquoise.opacity(0.16)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(TouchyTheme.aquaLight.opacity(0.38), lineWidth: 1)
                            )
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sidebarMasterToggleCard: some View {
        let activeColor = state.enabled ? TouchyTheme.emerald : Color.secondary
        return HStack(spacing: 8) {
            ZStack {
                Circle().fill(activeColor.opacity(0.25)).frame(width: 16, height: 16)
                Circle().fill(activeColor).frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Touch Synthesis")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(state.enabled ? "Master Driver Active" : "Touch Input Paused")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $state.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(TouchyTheme.turquoise)
                .labelsHidden()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Right Main Content Area

    private var mainContentView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                touchyHeroHeader

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
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Touchy Liquid Glass Hero Header

    private var touchyHeroHeader: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TouchyTheme.aquaLight.opacity(0.22),
                            TouchyTheme.turquoise.opacity(0.16),
                            TouchyTheme.tealDeep.opacity(0.20),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    TouchyTheme.aquaLight.opacity(0.25),
                                    Color.white.opacity(0.10),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )

            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(TouchyTheme.aquaLight.opacity(0.30)).frame(width: 60, height: 60).blur(radius: 12)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                        .shadow(color: TouchyTheme.tealDeep.opacity(0.45), radius: 8, x: 0, y: 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isSearching ? "Search Results" : state.selectedTab.title)
                        .font(.system(size: 20, weight: .bold))

                    Text(isSearching ? "Matching settings for \"\(state.searchQuery)\"" : state.selectedTab.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button {
                    state.onToggleKeyboardNow?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.isKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(state.isKeyboardVisible ? "Hide Keyboard" : "Keyboard")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        state.isKeyboardVisible
                            ? AnyShapeStyle(TouchyTheme.accentGradient)
                            : AnyShapeStyle(Color.primary.opacity(0.08))
                    )
                    .foregroundColor(state.isKeyboardVisible ? .white : .primary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Show or Hide Touch Keyboard on Display")

                heroHeaderRightBadge
            }
            .padding(18)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 6)
    }

    // MARK: - Context-Aware Hero Header Status Badge

    @ViewBuilder
    private var heroHeaderRightBadge: some View {
        switch state.selectedTab {
        case .about:
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(TouchyTheme.emerald)
                    Text("Touchy v2.0")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))

                Text("Build 4 • Release Channel")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

        case .gestures:
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.palmRejection ? TouchyTheme.emerald : TouchyTheme.aquaLight)
                        .frame(width: 7, height: 7)
                    Text(state.palmRejection ? "Palm Rejection Active" : "Multi-Touch Gestures")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))

                Text("Stylus, Scroll, Zoom & Spaces")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

        case .system:
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.accessibilityOK ? TouchyTheme.emerald : TouchyTheme.amber)
                        .frame(width: 7, height: 7)
                    Text(state.accessibilityOK ? "Accessibility Granted" : "Permission Needed")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    state.accessibilityOK
                        ? Capsule().fill(Color.primary.opacity(0.08))
                        : Capsule().fill(TouchyTheme.amber.opacity(0.25))
                )
                .overlay(
                    Capsule().stroke(
                        state.accessibilityOK ? Color.white.opacity(0.20) : TouchyTheme.amber.opacity(0.40),
                        lineWidth: 1
                    )
                )

                Text(state.accessibilityOK ? "Quartz CGEvent Synthesis Active" : "Grant in macOS Settings")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
            }

        case .overview, .display:
            if state.isConnected {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(TouchyTheme.emerald)
                            .frame(width: 7, height: 7)
                        Text("\(state.systemDeviceName) • Connected")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(AnyShapeStyle(TouchyTheme.accentGradient))
                    .foregroundColor(.white)
                    .clipShape(Capsule())

                    Text("Target: \(state.activeDisplayName) • \(state.slotCount)-Finger HID")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(TouchyTheme.cyanGlow)
                            .frame(width: 7, height: 7)
                        Text(state.selectedTab == .display ? "Display Mapping" : "Live Visualizer")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))

                    Text(state.selectedTab == .display ? "Target: \(state.activeDisplayName)" : "Ready for Multi-Touch Input")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Permission Warning Banner

    private var permissionWarningBanner: some View {
        TouchyGlassCard(
            title: "Accessibility Permission Required",
            subtitle: "Touchy needs macOS Accessibility authorization to synthesize mouse clicks, scrolling, and multi-touch gestures.",
            icon: "exclamationmark.shield.fill",
            iconColors: [TouchyTheme.amber, Color.orange]
        ) {
            HStack(spacing: 10) {
                Button {
                    state.selectedTab = .system
                } label: {
                    Label("Manage in System & Permissions →", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TouchyTheme.amber)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    // MARK: - Tab 1: Live Monitor (Real-Time Visualizer & Read-Only Telemetry)

    private var overviewTabContent: some View {
        let isCustomCal = !Settings.shared.calibrationTransform.isIdentity
        return VStack(spacing: 16) {
            liveTouchIslandCard

            HStack(alignment: .top, spacing: 14) {
                telemetryCard(
                    icon: "hand.point.up.braille.fill",
                    colors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep],
                    title: "HID Touch Digitizer",
                    primaryValue: state.isConnected ? state.systemDeviceName : "Disconnected",
                    secondaryLine1: state.isConnected ? "Controller: \(state.deviceSummary)" : "Waiting for USB-C / USB HID input",
                    secondaryLine2: state.isConnected ? "Capacity: \(state.slotCount) simultaneous contacts" : "Usage Page: 0x0D (Digitizer)"
                )

                telemetryCard(
                    icon: "display",
                    colors: SidebarTab.display.gradientColors,
                    title: "Display & Orientation",
                    primaryValue: state.activeDisplayName,
                    secondaryLine1: state.autoRotate
                        ? "G-Sensor Auto-Rotate: \(state.sensorOrientationAngle.map { "\($0)°" } ?? "Active")"
                        : "Manual Extra Rotation: \(state.extraRotation)°",
                    secondaryLine2: isCustomCal ? "Calibration: Custom 4-Point ✓" : "Calibration: Factory Default"
                )

                telemetryCard(
                    icon: "pencil.and.outline",
                    colors: [TouchyTheme.emerald, Color.teal],
                    title: "Stylus & Gesture Engine",
                    primaryValue: state.palmRejection ? "Palm Rejection Active" : "Standard Multi-Touch",
                    secondaryLine1: "Scroll: \(state.twoFingerScroll ? "On" : "Off") • Zoom: \(state.pinchZoom ? "On" : "Off")",
                    secondaryLine2: "3-Finger Spaces: \(state.threeFingerSwipe ? "On" : "Off") • Access: \(state.accessibilityOK ? "OK" : "Missing")"
                )
            }
        }
    }

    private func telemetryCard(
        icon: String,
        colors: [Color],
        title: String,
        primaryValue: String,
        secondaryLine1: String,
        secondaryLine2: String
    ) -> some View {
        TouchyGlassCard(
            title: title,
            subtitle: nil,
            icon: icon,
            iconColors: colors
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(primaryValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Divider().opacity(0.25)
                Text(secondaryLine1)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(secondaryLine2)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Live Touch Island Surface

    private var liveTouchIslandCard: some View {
        TouchyGlassCard(
            title: "Live Touch Island",
            subtitle: state.isConnected
                ? "Device Connected (\(state.systemDeviceName)) — touch your screen with fingers or a stylus to inspect real-time coordinates"
                : "Connect an external touch display to preview real-time multi-touch coordinates",
            icon: "sparkles.tv.fill",
            iconColors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep]
        ) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.02, green: 0.13, blue: 0.16),
                                    Color(red: 0.03, green: 0.19, blue: 0.23),
                                    Color(red: 0.02, green: 0.11, blue: 0.14),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Path { path in
                        let w = geo.size.width, h = geo.size.height
                        for f in [0.2, 0.4, 0.6, 0.8] {
                            path.move(to: CGPoint(x: w * f, y: 0))
                            path.addLine(to: CGPoint(x: w * f, y: h))
                            path.move(to: CGPoint(x: 0, y: h * f))
                            path.addLine(to: CGPoint(x: w, y: h * f))
                        }
                    }
                    .stroke(TouchyTheme.aquaLight.opacity(0.10), lineWidth: 1)

                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Capsule().fill(Color.white).frame(width: 4.5, height: state.liveFingers.isEmpty ? 8 : 11)
                            Capsule().fill(Color.white).frame(width: 4.5, height: state.liveFingers.isEmpty ? 8 : 11)
                        }
                        .shadow(color: TouchyTheme.aquaLight, radius: 4)

                        Text(
                            state.liveFingers.isEmpty
                                ? (state.isConnected ? "Touchy Island • \(state.systemDeviceName) Ready" : "Touchy Island • Waiting for Touch Display")
                                : "\(state.liveFingers.count) Active Contact(s) • " + state.liveFingers.map { String(format: "#%d (%.0f%%, %.0f%%)", $0.id, $0.normX * 100, $0.normY * 100) }.joined(separator: "  ")
                        )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.78))
                            .overlay(
                                Capsule().stroke(
                                    state.liveFingers.isEmpty ? Color.white.opacity(0.18) : TouchyTheme.aquaLight.opacity(0.85),
                                    lineWidth: 1.2
                                )
                            )
                            .shadow(color: state.liveFingers.isEmpty ? .clear : TouchyTheme.turquoise.opacity(0.55), radius: 10)
                    )
                    .padding(.top, 8)

                    if state.liveFingers.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            ZStack {
                                Circle().stroke(TouchyTheme.aquaLight.opacity(0.25), lineWidth: 1.5).frame(width: 54, height: 54)
                                Image(systemName: "hand.point.up.left.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(LinearGradient(colors: [TouchyTheme.aquaLight, TouchyTheme.cyanGlow], startPoint: .top, endPoint: .bottom))
                            }
                            Text("Touch your external display with one or more fingers")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    ForEach(state.liveFingers) { finger in
                        ZStack {
                            Circle().fill(TouchyTheme.aquaLight.opacity(0.22)).frame(width: 56, height: 56)
                            Circle().stroke(TouchyTheme.cyanGlow.opacity(0.85), lineWidth: 2).frame(width: 38, height: 38)
                            Circle()
                                .fill(LinearGradient(colors: [.white, TouchyTheme.aquaLight], startPoint: .top, endPoint: .bottom))
                                .frame(width: 16, height: 16)
                                .shadow(color: TouchyTheme.aquaLight, radius: 6)

                            Text("#\(finger.id)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(TouchyTheme.tealDeep.opacity(0.9)))
                                .foregroundColor(.white)
                                .offset(y: -28)
                        }
                        .position(
                            x: CGFloat(finger.normX) * geo.size.width,
                            y: CGFloat(finger.normY) * geo.size.height
                        )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [TouchyTheme.aquaLight.opacity(0.45), TouchyTheme.tealDeep.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
            }
            .frame(height: 215)
        }
    }

    // MARK: - Tab 2: Display & Calibration

    private var displayTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "Target Monitor & Orientation",
                subtitle: "Choose which display receives touch input and configure rotation or axis mirroring",
                icon: "display",
                iconColors: SidebarTab.display.gradientColors
            ) {
                VStack(spacing: 12) {
                    displayPickerRow(width: 220)
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "crop.rotate",
                        colors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep],
                        title: "Auto-Rotate Display & Touch (G-Sensor)",
                        subtitle: state.sensorOrientationAngle.map { "Active — Display G-Sensor currently reports \($0)° via DDC/CI" }
                            ?? "Reads the connected display's hardware accelerometer via DDC/CI (VCP 0xAA) and rotates macOS automatically",
                        isOn: $state.autoRotate
                    )
                    if state.autoRotate {
                        Divider().opacity(0.25)
                        TouchyToggleRow(
                            icon: "arrow.triangle.2.circlepath",
                            colors: [TouchyTheme.cyanGlow, Color.blue],
                            title: "Invert Portrait Direction (90° ↔ 270°)",
                            subtitle: "Swap 90° and 270° if Portrait orientation appears upside-down when standing the monitor",
                            isOn: $state.invertAutoRotate
                        )
                    }
                    Divider().opacity(0.25)
                    rotationPickerRow(width: 220)
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                        colors: [TouchyTheme.cyanGlow, Color.blue],
                        title: "Flip Horizontal Axis (Flip X)",
                        subtitle: "Mirror left and right touch coordinates",
                        isOn: $state.flipX
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "arrow.up.and.down.righttriangle.up.righttriangle.down.fill",
                        colors: [TouchyTheme.cyanGlow, Color.blue],
                        title: "Flip Vertical Axis (Flip Y)",
                        subtitle: "Mirror top and bottom touch coordinates",
                        isOn: $state.flipY
                    )
                }
            }

            TouchyGlassCard(
                title: "4-Point Precision Calibration",
                subtitle: "Touch 4 corner targets on your external touch display for sub-pixel alignment",
                icon: "scope",
                iconColors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep]
            ) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        let isDefaultCal = Settings.shared.calibrationTransform.isIdentity
                        Text(isDefaultCal ? "Status: Default Factory Calibration" : "Status: Custom 4-Point Calibration Active ✓")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(isDefaultCal ? .secondary : TouchyTheme.emerald)
                        Text("Run calibration if the cursor clicks slightly offset from your finger or stylus tip.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Reset to Default") { state.onResetCalibration?() }.buttonStyle(.bordered)
                    Button {
                        state.onCalibrate?()
                    } label: {
                        Label("Start 4-Point Calibration…", systemImage: "scope")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TouchyTheme.turquoise)
                }
            }
        }
    }

    private func displayPickerRow(width: CGFloat) -> some View {
        HStack {
            Text("Target External Display").font(.system(size: 12.5, weight: .medium))
            Spacer()
            Picker("", selection: $state.selectedDisplay) {
                Text(state.hasExternalDisplay ? "Auto (\(state.activeDisplayName))" : "Auto (External Only)").tag("__AUTO__")
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
    }

    private func rotationPickerRow(width: CGFloat) -> some View {
        HStack {
            Text("Extra Touch Rotation").font(.system(size: 12.5, weight: .medium))
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
    }

    // MARK: - Tab 3: Touch & Stylus

    private var gesturesTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "Stylus & Single-Finger Input",
                subtitle: "Universal stylus palm rejection, tap, drag, and context menu behavior",
                icon: "pencil.and.outline",
                iconColors: [TouchyTheme.emerald, Color.teal]
            ) {
                VStack(spacing: 10) {
                    TouchyToggleRow(
                        icon: "pencil.and.outline",
                        colors: [TouchyTheme.emerald, Color.teal],
                        title: "Palm Rejection (Universal Stylus Mode)",
                        subtitle: "Locks onto your active stylus stroke and filters out resting palm clusters, contact area spikes, and lower-hand touches",
                        isOn: $state.palmRejection
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "ellipsis.rectangle.fill",
                        colors: [Color(red: 1.0, green: 0.37, blue: 0.34), Color(red: 1.0, green: 0.74, blue: 0.18)],
                        title: "Expand Window Traffic Lights on Tap",
                        subtitle: "The red, yellow, and green macOS window buttons grow into large touch targets when you tap them",
                        isOn: $state.expandTrafficLights
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "keyboard.fill",
                        colors: [TouchyTheme.aquaLight, TouchyTheme.turquoise],
                        title: "Auto-Popup Mini Touch Keyboard on Text Fields",
                        subtitle: "Pops up a floating mini keyboard when tapping any text box; disappears on physical keyboard press or outside touch",
                        isOn: $state.touchKeyboard
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "cursorarrow.click.badge.clock",
                        colors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep],
                        title: "Long Press for Right Click",
                        subtitle: "Hold one finger stationary for 0.95s to open the context menu without affecting single taps",
                        isOn: $state.longPressRightClick
                    )
                }
            }

            TouchyGlassCard(
                title: "Two-Finger & Multi-Finger Trackpad Gestures",
                subtitle: "Smooth scrolling, momentum inertia, pinch-to-zoom, and macOS Spaces switching",
                icon: "hand.draw.fill",
                iconColors: SidebarTab.gestures.gradientColors
            ) {
                VStack(spacing: 10) {
                    TouchyToggleRow(
                        icon: "scroll.fill",
                        colors: [TouchyTheme.cyanGlow, Color.blue],
                        title: "Two-Finger Scroll",
                        subtitle: "Smooth vertical and horizontal scrolling across webpages, documents, and timelines",
                        isOn: $state.twoFingerScroll
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "wind",
                        colors: [TouchyTheme.emerald, Color.teal],
                        title: "Scroll Momentum (Inertia)",
                        subtitle: "Scrolling coasts smoothly to a stop after lifting your fingers, just like a Magic Trackpad",
                        isOn: $state.momentum
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "arrow.up.arrow.down.circle.fill",
                        colors: [TouchyTheme.amber, Color.orange],
                        title: "Invert Scroll Direction",
                        subtitle: "Reverses natural content scrolling direction",
                        isOn: $state.invertScroll
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "plus.magnifyingglass",
                        colors: SidebarTab.gestures.gradientColors,
                        title: "Two-Finger Pinch to Zoom",
                        subtitle: "Native macOS magnification gesture in Safari, Preview, Figma, Maps, and Photos",
                        isOn: $state.pinchZoom
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "rectangle.3.group.fill",
                        colors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep],
                        title: "Three-Finger Swipe (Mission Control & Spaces)",
                        subtitle: "Swipe Left/Right: Switch Spaces • Swipe Up: Mission Control • Swipe Down: App Exposé",
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
                title: "macOS Permissions & Hardware Connection",
                subtitle: "System authorizations and USB-C HID digitizer discovery",
                icon: "checkmark.shield.fill",
                iconColors: SidebarTab.system.gradientColors
            ) {
                VStack(spacing: 12) {
                    statusPermissionRow(
                        title: "Accessibility Permission",
                        subtitle: state.accessibilityOK
                            ? "Granted — Quartz CGEvent mouse, scroll, and gesture synthesis is fully active."
                            : "Missing — Enable Touchy in System Settings → Privacy & Security → Accessibility.",
                        ok: state.accessibilityOK,
                        actionTitle: "Open Accessibility Settings…",
                        action: { state.onOpenAccessibility?() }
                    )

                    Divider().opacity(0.25)

                    statusPermissionRow(
                        title: state.isConnected ? "Device Connected: \(state.systemDeviceName)" : "USB-C HID Digitizer Connection",
                        subtitle: state.isConnected
                            ? "Connected — \(state.deviceSummary) mapped to \(state.activeDisplayName) (\(state.slotCount) simultaneous fingers)"
                            : "Waiting — Connect your external touch display via USB-C or USB data cable to your Mac.",
                        ok: state.isConnected,
                        actionTitle: "Rescan Hardware",
                        action: { state.onRescan?() }
                    )

                    Divider().opacity(0.25)

                    HStack(spacing: 10) {
                        Button("Reset TCC Permission Cache") { state.onResetPermissions?() }.buttonStyle(.bordered)
                        Button("Relaunch Touchy") { state.onRelaunch?() }.buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }

            TouchyGlassCard(
                title: "System Integration & Driver Behavior",
                subtitle: "Login item, Dock visibility, and low-level IOHID seizure options",
                icon: "gearshape.2.fill",
                iconColors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep]
            ) {
                VStack(spacing: 10) {
                    TouchyToggleRow(
                        icon: "power.circle.fill",
                        colors: [TouchyTheme.emerald, Color.teal],
                        title: "Launch at Login",
                        subtitle: "Automatically start Touchy in the background when you log in to macOS",
                        isOn: Binding(
                            get: { state.launchAtLogin },
                            set: { _ in state.onToggleLogin?() }
                        )
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "dock.rectangle",
                        colors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep],
                        title: "Show App Icon in Dock",
                        subtitle: "When disabled, Touchy runs exclusively in the top macOS Menu Bar",
                        isOn: $state.showInDock
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "lock.shield.fill",
                        colors: [TouchyTheme.amber, Color.orange],
                        title: "Exclusive Device Access (IOHID Seize)",
                        subtitle: "Prevents macOS from routing raw uncalibrated touches to the primary screen",
                        isOn: $state.seizeDevice
                    )
                    Divider().opacity(0.25)
                    TouchyToggleRow(
                        icon: "terminal.fill",
                        colors: [Color.gray, Color.secondary],
                        title: "Verbose Debug Logging",
                        subtitle: "Writes raw HID packets and state transitions to /tmp/Touchy.log",
                        isOn: $state.debugLog
                    )
                }
            }

            TouchyGlassCard(
                title: "Diagnostics & Driver Logs",
                subtitle: "Inspect runtime logs or copy a hardware diagnostics report",
                icon: "waveform.path.ecg.rectangle.fill",
                iconColors: [TouchyTheme.cyanGlow, TouchyTheme.tealDeep]
            ) {
                HStack(spacing: 10) {
                    Button {
                        state.onShowLog?()
                    } label: {
                        Label("Open Log File (/tmp/Touchy.log)", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        state.onCopyDiagnostics?()
                        state.copiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            state.copiedToast = false
                        }
                    } label: {
                        Label(state.copiedToast ? "✓ Copied to Clipboard" : "Copy Diagnostics Report", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private func statusPermissionRow(
        title: String,
        subtitle: String,
        ok: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            TouchySquircleIcon(
                systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                colors: ok ? [TouchyTheme.emerald, Color.green] : [TouchyTheme.amber, Color.orange],
                size: 28
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundColor(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.bordered)
        }
    }

    // MARK: - Tab 5: About, Compatibility & Legal Notice

    private var aboutTabContent: some View {
        VStack(spacing: 16) {
            TouchyGlassCard(
                title: "Application & Driver Architecture",
                subtitle: "Release metadata, runtime environment, and low-level system subsystems",
                icon: "cpu.fill",
                iconColors: [TouchyTheme.aquaLight, TouchyTheme.tealDeep]
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    aboutMetadataRow(label: "Application Name", value: "Touchy — Universal macOS Multi-Touch & Stylus Driver", ok: true)
                    aboutMetadataRow(label: "Version & Build", value: "Version 2.0 (Build 4) • Release Channel", ok: true)
                    aboutMetadataRow(label: "Bundle Identifier", value: Bundle.main.bundleIdentifier ?? "com.beratclxn.touchy", ok: true)
                    aboutMetadataRow(label: "Target Platform", value: "macOS 13.0+ (Ventura / Sonoma / Sequoia) • Apple Silicon & Intel", ok: true)
                    aboutMetadataRow(
                        label: "Core Subsystems",
                        value: "IOKit HID Digitizer (0x0D) • Quartz CGEvent Tap • VESA DDC/CI (IOAVService) • MonitorPanel",
                        ok: true
                    )
                    aboutMetadataRow(
                        label: "Currently Detected Hardware",
                        value: state.isConnected ? "\(state.systemDeviceName) (\(state.deviceSummary))" : "No External HID Digitizer Connected",
                        ok: state.isConnected
                    )
                }
            }

            TouchyGlassCard(
                title: "Hardware Verification & Compatibility Disclosure",
                subtitle: "Reference hardware validation status and universal HID standard support",
                icon: "checkmark.seal.fill",
                iconColors: [TouchyTheme.emerald, Color.teal]
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Verified Reference Hardware — ASUS ProArt Display PA148CTV")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    Text(
                        "Touchy is engineered around universal industry specifications, including the USB Implementers Forum (USB-IF) HID Digitizer Usage Page (0x0D) for multi-touch and stylus input, and the VESA Monitor Control Command Set (MCCS / DDC/CI VCP 0xAA & 0xEA) for hardware accelerometer orientation sensing.\n\n" +
                        "IMPORTANT HARDWARE NOTICE: As of Version 2.0 (Build 4), physical hardware validation, multi-touch calibration, 10-finger gesture synthesis, Universal Stylus Palm Rejection, and G-Sensor Auto-Rotation have been exclusively tested and verified on the ASUS ProArt Display PA148CTV, where all subsystems operate seamlessly without known issues.\n\n" +
                        "Compatibility with other third-party external USB-C or HDMI HID touchscreen monitors and pen displays is provided on a universal, standards-compliant best-effort basis. Variations in vendor-specific HID report descriptors, non-standard coordinate ranges, or proprietary DDC/CI firmware implementations on untested monitors may require manual 4-Point Calibration or Extra Rotation adjustment."
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            TouchyGlassCard(
                title: "Legal Notice, Trademarks, Privacy & Disclaimer of Warranty",
                subtitle: "Intellectual property disclosures, local-only data policy, and limitation of liability",
                icon: "building.columns.fill",
                iconColors: [TouchyTheme.amber, Color.orange]
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        Text("1. Third-Party Trademarks & Non-Affiliation")
                            .font(.system(size: 12.5, weight: .bold))
                        Text(
                            "\"ASUS\" and \"ProArt\" are registered trademarks of ASUSTeK Computer Inc. \"Apple\", \"macOS\", \"Quartz\", and \"Retina\" are trademarks of Apple Inc., registered in the U.S. and other countries. All product, monitor, and company names mentioned within this software are used strictly for hardware identification and interoperability purposes; their use does not imply any affiliation with or endorsement by their respective rights holders."
                        )
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                        Divider().opacity(0.25)

                        Text("2. Privacy & System Permissions Statement")
                            .font(.system(size: 12.5, weight: .bold))
                        Text(
                            "Touchy operates 100% locally on your Mac with zero network connectivity, zero telemetry, and zero analytics. macOS Accessibility (TCC) and Input Monitoring permissions are utilized exclusively in real time to read raw USB HID Digitizer touch coordinates and synthesize corresponding Quartz cursor, scroll, and gesture events. Touchy never records, stores, or transmits keystrokes, screen contents, or personal user data."
                        )
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                        Divider().opacity(0.25)

                        Text("3. Disclaimer of Warranty & Limitation of Liability")
                            .font(.system(size: 12.5, weight: .bold))
                        Text(
                            "THIS SOFTWARE IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, HARDWARE COMPATIBILITY, AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, DISPLAY CONFIGURATION ALTERATIONS, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func aboutMetadataRow(label: String, value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(ok ? TouchyTheme.emerald : TouchyTheme.amber)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 185, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
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
                    title: "No Matching Settings",
                    subtitle: "No controls or preferences found matching \"\(state.searchQuery)\"",
                    icon: "magnifyingglass",
                    iconColors: [TouchyTheme.amber, Color.orange]
                ) {
                    Text("Try searching for terms like \"scroll\", \"palm\", \"display\", \"calibrate\", \"permission\", or \"rotate\".")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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
