import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, TouchReaderDelegate {
    private var statusItem: NSStatusItem!
    private var keyboardStatusItem: NSStatusItem!
    private let reader = HIDTouchReader()
    private let mapper = DisplayMapper()
    private let injector = EventInjector()
    private lazy var engine = GestureEngine(injector: injector)
    private lazy var calibration = CalibrationController(mapper: mapper)
    private lazy var autoRotation = AutoRotationController(mapper: mapper)
    private let windowController = ControlWindowController()
    private let popoverController = MenuBarPopoverController()
    private let contextMenu = NSMenu()
    private var permissionPoll: Timer?
    private var wasTrusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("=== Touchy launched: \(Bundle.main.bundlePath) ===", force: true)

        applyDockPolicy()
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        contextMenu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Touchy Control Center"
        }

        keyboardStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let kbButton = keyboardStatusItem.button {
            kbButton.target = self
            kbButton.action = #selector(toggleKeyboardNow)
            kbButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            kbButton.toolTip = "Show / Hide Touch Keyboard (Touchy)"
        }
        TouchKeyboardController.shared.onVisibilityChanged = { [weak self] visible in
            AppState.shared.isKeyboardVisible = visible
            self?.updateKeyboardStatusIcon()
        }

        wireStateCallbacks()

        mapper.refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.engine.reset()
            self?.mapper.refresh()
            self?.syncAppState()
        }

        autoRotation.onOrientationDetected = { angle in
            if AppState.shared.sensorOrientationAngle != angle {
                AppState.shared.sensorOrientationAngle = angle
            }
        }
        autoRotation.start()

        reader.delegate = self
        reader.start(seize: Settings.shared.seizeDevice)

        setupPermissions()
        syncAppState()
        updateIcon()
        logStatus()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.popoverController.show(relativeTo: button)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPoll?.invalidate()
        autoRotation.stop()
        engine.reset()
        reader.stop()
    }

    // MARK: - App Menu & Dock Policy

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(Settings.shared.showInDock ? .regular : .accessory)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open Control Panel", action: #selector(openControlWindow), keyEquivalent: "1")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Touchy", action: #selector(quit), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func wireStateCallbacks() {
        let state = AppState.shared
        state.onSettingsChanged = { [weak self] in
            guard let self else { return }
            if !Settings.shared.enabled { self.engine.reset() }
            self.updateIcon()
        }
        state.onDisplayChanged = { [weak self] in
            self?.mapper.refresh()
            self?.autoRotation.refreshNow()
            self?.syncAppState()
        }
        state.onAutoRotateChanged = { [weak self] in
            guard let self else { return }
            if Settings.shared.autoRotate {
                self.autoRotation.start()
                self.autoRotation.refreshNow()
            } else {
                self.autoRotation.stop()
            }
        }
        state.onSeizeChanged = { [weak self] in
            self?.rescan()
        }
        state.onDockPolicyChanged = { [weak self] in
            self?.applyDockPolicy()
            if Settings.shared.showInDock {
                self?.windowController.show()
            }
        }
        state.onCalibrate = { [weak self] in self?.startCalibration() }
        state.onResetCalibration = { [weak self] in self?.resetCalibration() }
        state.onRescan = { [weak self] in self?.rescan() }
        state.onOpenAccessibility = { [weak self] in self?.openAccessibility() }
        state.onResetPermissions = { [weak self] in self?.resetPermissionsAndRelaunch() }
        state.onRelaunch = { [weak self] in self?.relaunchApp() }
        state.onShowLog = { [weak self] in self?.showLog() }
        state.onCopyDiagnostics = { [weak self] in self?.copyDiagnostics() }
        state.onToggleLogin = { [weak self] in
            self?.toggleLogin()
            self?.syncAppState()
        }
        state.onToggleKeyboardNow = { [weak self] in self?.toggleKeyboardNow() }
        state.onOpenControlPanel = { [weak self] in self?.openControlWindow() }
        state.onQuit = { [weak self] in self?.quit() }
    }

    private func syncAppState() {
        let state = AppState.shared
        state.isConnected = !reader.handlers.isEmpty
        if let first = reader.handlers.values.first {
            state.deviceSummary = first.name
            state.slotCount = first.slotCount
        } else {
            state.deviceSummary = "No Device Connected"
            state.slotCount = 0
        }
        state.activeDisplayName = mapper.displayName
        state.hasExternalDisplay = mapper.hasExternalDisplay
        state.screens = DisplayMapper.externalScreens()
        state.accessibilityOK = accessibilityOK
        state.hidOpenOK = hidOpenOK
        state.syncFromSettings()
    }

    // MARK: - Permissions

    private var accessibilityOK: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    private var hidOpenOK: Bool {
        reader.lastOpenResult == kIOReturnSuccess
    }

    private func setupPermissions() {
        wasTrusted = accessibilityOK
        if !wasTrusted {
            promptAccessibility()
        }
        if !hidOpenOK && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let nowTrusted = self.accessibilityOK
            guard nowTrusted != self.wasTrusted else { return }
            self.wasTrusted = nowTrusted
            Log.write("Accessibility status changed: \(nowTrusted) (PostEvent=\(CGPreflightPostEventAccess()))", force: true)
            self.injector.refreshEventSource()
            self.updateIcon()
            self.syncAppState()
            if nowTrusted {
                if !CGPreflightPostEventAccess() {
                    Log.write("Relaunching Touchy to activate WindowServer PostEvent access", force: true)
                    self.relaunchApp()
                    return
                }
                self.reader.start(seize: Settings.shared.seizeDevice)
            }
        }
    }

    private func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func runTCCReset() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "All", bundleID]
        try? process.run()
        process.waitUntilExit()
        Log.write("tccutil reset All \(bundleID) exit code: \(process.terminationStatus)", force: true)
    }

    private func logStatus() {
        Log.write("Status -> AX=\(AXIsProcessTrusted()) PostEvent=\(CGPreflightPostEventAccess()) ListenEvent=\(CGPreflightListenEventAccess()) HIDOpen=\(reader.lastOpenResult) Devices=\(reader.handlers.count) Display=\(mapper.displayName)", force: true)
    }

    // MARK: - TouchReaderDelegate

    func touchReader(_ reader: HIDTouchReader, didReceive contacts: [RawContact]) {
        // Only publish live finger coordinates when a UI surface is visible or needs clearing,
        // avoiding 240Hz SwiftUI view invalidations during normal background touch operation.
        let isUIVisible = windowController.isVisible || popoverController.isShown
        if isUIVisible || !AppState.shared.liveFingers.isEmpty {
            if isUIVisible && !contacts.isEmpty {
                AppState.shared.liveFingers = contacts.map { contact in
                    let point = mapper.calibrated(mapper.oriented(contact))
                    return LiveFinger(id: contact.id, normX: Double(point.x), normY: Double(point.y))
                }
            } else if !AppState.shared.liveFingers.isEmpty {
                AppState.shared.liveFingers = []
            }
        }

        if calibration.isActive {
            calibration.feed(contacts)
            return
        }
        guard Settings.shared.enabled else { return }
        guard accessibilityOK else {
            if !contacts.isEmpty {
                Log.write("Touch detected (\(contacts.count) fingers) waiting for Accessibility permission", force: true)
            }
            return
        }

        var touchPoints: [TouchPoint] = []
        touchPoints.reserveCapacity(contacts.count)
        for contact in contacts {
            if let mapped = mapper.map(contact) {
                touchPoints.append(TouchPoint(id: contact.id, p: mapped, size: contact.size, isStylus: contact.isStylus))
            }
        }
        engine.process(touchPoints)
    }

    func touchReaderDevicesChanged(_ reader: HIDTouchReader) {
        mapper.refresh()
        autoRotation.refreshNow()
        updateIcon()
        syncAppState()
        logStatus()
    }

    // MARK: - Menu Bar UI & Context Menu

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        updateIcon()
        syncAppState()
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            popoverController.close()
            statusItem.menu = contextMenu
            sender.performClick(nil)
            statusItem.menu = nil
            return
        }
        popoverController.toggle(relativeTo: sender)
    }

    @objc private func toggleKeyboardNow() {
        popoverController.close()
        TouchKeyboardController.shared.toggleManual(onDisplay: mapper.displayID, injector: injector)
        updateKeyboardStatusIcon()
    }

    private func updateKeyboardStatusIcon() {
        let isOpen = TouchKeyboardController.shared.isVisible
        let symbolName = isOpen ? "keyboard.chevron.compact.down.fill" : "keyboard.fill"
        if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Touch Keyboard") {
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
            let configured = base.withSymbolConfiguration(config) ?? base
            configured.isTemplate = true
            keyboardStatusItem?.button?.image = configured
        }
    }

    private func updateIcon() {
        let connected = !reader.handlers.isEmpty
        let warning = !accessibilityOK || !hidOpenOK
        statusItem.button?.image = MenuBarIconRenderer.makeIcon(
            enabled: Settings.shared.enabled,
            connected: connected,
            warning: warning
        )
        updateKeyboardStatusIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()
        syncAppState()
        menu.removeAllItems()
        let s = Settings.shared

        // 1. Settings Window & Quick Touch Keyboard Toggle
        menu.addItem(makeItem("Touchy Settings…", #selector(openControlWindow), key: ","))
        let kbTitle = TouchKeyboardController.shared.isVisible ? "Hide Touch Keyboard" : "Show Touch Keyboard"
        menu.addItem(makeItem(kbTitle, #selector(toggleKeyboardNow), key: "k"))
        menu.addItem(.separator())

        // 2. Hardware Status Header
        if reader.handlers.isEmpty {
            menu.addItem(makeDisabledItem("No Touch Display Connected"))
            if !hidOpenOK {
                menu.addItem(makeDisabledItem("HID failed to open (code \(reader.lastOpenResult))"))
            }
        } else {
            for handler in reader.handlers.values {
                menu.addItem(makeDisabledItem("● \(AppState.shared.systemDeviceName) (\(handler.slotCount) fingers)"))
            }
        }
        menu.addItem(makeDisabledItem("Target: \(mapper.displayName)"))

        // 3. Permission Notice (if needed)
        if !accessibilityOK {
            menu.addItem(.separator())
            menu.addItem(makeItem("⚠️ Grant Accessibility Permission…", #selector(openAccessibility)))
        }
        if !hidOpenOK {
            menu.addItem(makeItem("⚠️ Grant Input Monitoring Permission…", #selector(openInputMonitoring)))
        }

        menu.addItem(.separator())

        // 4. Primary Toggles
        menu.addItem(makeToggleItem("Touch Synthesis Enabled", s.enabled, #selector(toggleEnabled)))
        menu.addItem(makeToggleItem("Palm Rejection (Stylus Mode)", s.palmRejection, #selector(togglePalmRejection)))
        menu.addItem(makeToggleItem("Expand Traffic Lights on Tap", s.expandTrafficLights, #selector(toggleExpandTrafficLights)))
        menu.addItem(makeToggleItem("Mini Touch Keyboard on Text Fields", s.touchKeyboard, #selector(toggleTouchKeyboard)))

        // 5. Display & Orientation Submenus
        let displayMenu = NSMenu()
        displayMenu.addItem(makeToggleItem("Auto-Detect External Display", s.displayName == nil, #selector(selectDisplay(_:)), represented: nil))
        let externalScreens = DisplayMapper.externalScreens()
        if !externalScreens.isEmpty {
            displayMenu.addItem(.separator())
            for screen in externalScreens {
                displayMenu.addItem(makeToggleItem(screen.name, s.displayName == screen.name, #selector(selectDisplay(_:)), represented: screen.name))
            }
        }
        menu.addItem(makeSubmenuItem("Target Display", submenu: displayMenu))

        let orientationMenu = NSMenu()
        orientationMenu.addItem(makeToggleItem("Auto-Rotate (G-Sensor)", s.autoRotate, #selector(toggleAutoRotate)))
        if s.autoRotate {
            orientationMenu.addItem(makeToggleItem("Invert Portrait Direction", s.invertAutoRotate, #selector(toggleInvertAutoRotate)))
        }
        orientationMenu.addItem(.separator())
        for angle in [0, 90, 180, 270] {
            orientationMenu.addItem(makeToggleItem("Extra Rotate \(angle)°", s.extraRotation == angle, #selector(selectRotation(_:)), represented: angle))
        }
        orientationMenu.addItem(.separator())
        orientationMenu.addItem(makeToggleItem("Flip Horizontal (X)", s.flipX, #selector(toggleFlipX)))
        orientationMenu.addItem(makeToggleItem("Flip Vertical (Y)", s.flipY, #selector(toggleFlipY)))
        menu.addItem(makeSubmenuItem("Orientation", submenu: orientationMenu))

        // 6. Calibration
        menu.addItem(makeItem("Start 4-Point Calibration…", #selector(startCalibration)))
        if !Settings.shared.calibrationTransform.isIdentity {
            menu.addItem(makeItem("Reset Calibration to Default", #selector(resetCalibration)))
        }

        menu.addItem(.separator())

        // 7. Gestures Submenu
        let gesturesMenu = NSMenu()
        gesturesMenu.addItem(makeToggleItem("Long Press → Right Click", s.longPressRightClick, #selector(toggleLongPress)))
        gesturesMenu.addItem(makeToggleItem("Two-Finger Scroll", s.twoFingerScroll, #selector(toggleScroll)))
        gesturesMenu.addItem(makeToggleItem("Scroll Momentum (Inertia)", s.momentum, #selector(toggleMomentum)))
        gesturesMenu.addItem(makeToggleItem("Invert Scroll Direction", s.invertScroll, #selector(toggleInvert)))
        gesturesMenu.addItem(makeToggleItem("Two-Finger Pinch to Zoom", s.pinchZoom, #selector(togglePinch)))
        gesturesMenu.addItem(makeToggleItem("Three-Finger Swipe (Spaces)", s.threeFingerSwipe, #selector(toggleSwipe)))
        menu.addItem(makeSubmenuItem("Gestures", submenu: gesturesMenu))

        // 8. Advanced & Diagnostics Submenu (No duplicated top-level items)
        let advancedMenu = NSMenu()
        advancedMenu.addItem(makeToggleItem("Exclusive Device Access (Seize)", s.seizeDevice, #selector(toggleSeize)))
        advancedMenu.addItem(makeToggleItem("Show Icon in Dock", s.showInDock, #selector(toggleShowInDock)))
        advancedMenu.addItem(makeToggleItem("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        advancedMenu.addItem(.separator())
        advancedMenu.addItem(makeItem("Rescan Hardware Devices", #selector(rescan)))
        advancedMenu.addItem(makeItem("Open Log File (/tmp/Touchy.log)", #selector(showLog)))
        advancedMenu.addItem(makeItem("Copy Diagnostics Report", #selector(copyDiagnostics)))
        advancedMenu.addItem(makeToggleItem("Verbose Debug Log", s.debugLog, #selector(toggleDebug)))
        advancedMenu.addItem(.separator())
        advancedMenu.addItem(makeItem("Reset Permissions (tccutil) & Relaunch", #selector(resetPermissionsAndRelaunch)))
        advancedMenu.addItem(makeItem("Relaunch Touchy", #selector(relaunchApp)))
        menu.addItem(makeSubmenuItem("Advanced & Tools", submenu: advancedMenu))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Touchy", #selector(quit), key: "q"))
    }

    private func makeDisabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeToggleItem(_ title: String, _ isOn: Bool, _ selector: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = makeItem(title, selector)
        item.state = isOn ? .on : .off
        item.representedObject = represented
        return item
    }

    private func makeSubmenuItem(_ title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func openControlWindow() {
        windowController.show()
    }

    @objc private func toggleEnabled() {
        Settings.shared.enabled.toggle()
        if !Settings.shared.enabled { engine.reset() }
        updateIcon()
        syncAppState()
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        Settings.shared.displayName = sender.representedObject as? String
        mapper.refresh()
        autoRotation.refreshNow()
        syncAppState()
    }

    @objc private func selectRotation(_ sender: NSMenuItem) {
        Settings.shared.extraRotation = sender.representedObject as? Int ?? 0
        syncAppState()
    }

    @objc private func toggleAutoRotate() {
        Settings.shared.autoRotate.toggle()
        if Settings.shared.autoRotate {
            autoRotation.start()
            autoRotation.refreshNow()
        } else {
            autoRotation.stop()
        }
        syncAppState()
    }

    @objc private func toggleInvertAutoRotate() {
        Settings.shared.invertAutoRotate.toggle()
        autoRotation.refreshNow()
        syncAppState()
    }

    @objc private func toggleFlipX() { Settings.shared.flipX.toggle(); syncAppState() }
    @objc private func toggleFlipY() { Settings.shared.flipY.toggle(); syncAppState() }
    @objc private func togglePalmRejection() { Settings.shared.palmRejection.toggle(); syncAppState() }
    @objc private func toggleExpandTrafficLights() { Settings.shared.expandTrafficLights.toggle(); syncAppState() }
    @objc private func toggleTouchKeyboard() {
        Settings.shared.touchKeyboard.toggle()
        if !Settings.shared.touchKeyboard { TouchKeyboardController.shared.dismiss() }
        syncAppState()
    }
    @objc private func toggleLongPress() { Settings.shared.longPressRightClick.toggle(); syncAppState() }
    @objc private func toggleScroll() { Settings.shared.twoFingerScroll.toggle(); syncAppState() }
    @objc private func toggleMomentum() { Settings.shared.momentum.toggle(); syncAppState() }
    @objc private func toggleInvert() { Settings.shared.invertScroll.toggle(); syncAppState() }
    @objc private func togglePinch() { Settings.shared.pinchZoom.toggle(); syncAppState() }
    @objc private func toggleSwipe() { Settings.shared.threeFingerSwipe.toggle(); syncAppState() }
    @objc private func toggleDebug() { Settings.shared.debugLog.toggle(); syncAppState() }

    @objc private func toggleShowInDock() {
        Settings.shared.showInDock.toggle()
        applyDockPolicy()
        syncAppState()
    }

    @objc private func toggleSeize() {
        Settings.shared.seizeDevice.toggle()
        rescan()
    }

    @objc private func rescan() {
        engine.reset()
        reader.start(seize: Settings.shared.seizeDevice)
        autoRotation.refreshNow()
        updateIcon()
        syncAppState()
        logStatus()
    }

    @objc private func startCalibration() {
        engine.reset()
        calibration.start()
    }

    @objc private func resetCalibration() {
        Settings.shared.calibrationTransform = .identity
    }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: Log.url.path) {
            Log.write("Log started", force: true)
        }
        NSWorkspace.shared.open(Log.url)
    }

    @objc private func copyDiagnostics() {
        var text = "Touchy Diagnostics\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        text += "Bundle: \(Bundle.main.bundlePath)\n"
        text += "Accessibility: \(accessibilityOK), PostEvent: \(CGPreflightPostEventAccess()), HID open: \(reader.lastOpenResult)\n"
        text += "Display: \(mapper.displayName)\n"
        if reader.handlers.isEmpty {
            text += "No touch device found\n"
        }
        for handler in reader.handlers.values {
            text += handler.diagnostics
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Update Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove the app to /Applications and try again."
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        promptAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func resetPermissionsAndRelaunch() {
        runTCCReset()
        relaunchApp()
    }

    @objc private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.4; open \"\(bundleURL.path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
