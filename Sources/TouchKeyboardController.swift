import AppKit
import ApplicationServices
import SwiftUI

final class TouchKeyboardState: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var isShifted: Bool = false
    @Published var isCapsLocked: Bool = false
    @Published var isSymbols: Bool = false
    @Published var isMoreSymbols: Bool = false
    @Published var layout: KeyboardLayoutSpec = KeyboardLayouts.spec(forLanguage: "en")
    @Published var layoutTitle: String = "English"
    @Published var lastTypedPreview: String = ""

    var onTypeText: ((String) -> Void)?
    var onSpecialKey: ((TouchKeyboardController.SpecialKey) -> Void)?
    var onShortcut: ((TouchKeyboardController.ShortcutAction) -> Void)?
    var onCycleLayout: (() -> Void)?
    var onDismiss: (() -> Void)?
}

/// Top strip of the keyboard that drags the whole panel (native window drag, works with touch-synthesized mouse events).
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragHandleNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        TouchKeyboardController.shared.rememberUserPosition()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

/// Authentic Apple iPadOS Keyboard UI for macOS Touchscreen Input
private struct MiniTouchKeyboardView: View {
    @ObservedObject var state: TouchKeyboardState

    // MARK: - iPadOS Color Palette

    private let platterTop = Color(red: 0.84, green: 0.85, blue: 0.88)
    private let platterBottom = Color(red: 0.78, green: 0.80, blue: 0.84)
    private let letterKeyBg = Color.white
    private let modifierKeyBg = Color(red: 0.68, green: 0.71, blue: 0.76)
    private let activeModifierKeyBg = Color.white
    private let returnKeyBg = Color(red: 0.00, green: 0.48, blue: 1.00) // iPadOS #007AFF Blue
    private let keyShadowColor = Color.black.opacity(0.30)
    private let keyPrimaryText = Color.black.opacity(0.88)
    private let keySecondaryText = Color.black.opacity(0.38)

    // MARK: - Key Layouts (follows the keyboard layout selected in macOS)

    private var row1Letters: [String] { state.layout.row1 }
    private var row1TopHints: [String] { state.layout.hints1 }
    private var row2Letters: [String] { state.layout.row2 }
    private var row2TopHints: [String] { state.layout.hints2 }
    private var row3Letters: [String] { state.layout.row3 }
    private var row3TopHints: [String] { state.layout.hints3 }

    // Symbol Pages (.?123 and #+=)
    private let symRow1Page1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private var symRow2Page1: [String] { ["-", "/", ":", ";", "(", ")", state.layout.currency, "&", "@", "\""] }
    private let symRow3Page1 = [".", ",", "?", "!", "'", "+", "=", "_"]

    private let symRow1Page2 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
    private let symRow2Page2 = ["_", "\\", "|", "~", "<", ">", "€", "$", "£", "•"]
    private let symRow3Page2 = [".", ",", "?", "!", "'", "`", "\"", "/"]

    private var uppercaseActive: Bool {
        state.isShifted || state.isCapsLocked
    }

    var body: some View {
        VStack(spacing: 6) {
            iPadQuickTypeBar
            if state.isSymbols {
                iPadSymbolRows
            } else {
                iPadLetterRows
            }
            iPadBottomRow
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(
            width: TouchKeyboardController.panelWidth,
            height: TouchKeyboardController.panelHeight
        )
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [platterTop, platterBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.0)
            }
        )
        .shadow(color: Color.black.opacity(0.32), radius: 20, x: 0, y: 10)
        .scaleEffect(state.isPresented ? 1.0 : 0.90)
        .opacity(state.isPresented ? 1.0 : 0.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: state.isPresented)
    }

    // MARK: - iPadOS Top Grabber & QuickType Bar

    private var iPadQuickTypeBar: some View {
        VStack(spacing: 3) {
            // Floating iPadOS grabber handle at top center
            Capsule()
                .fill(Color.black.opacity(0.22))
                .frame(width: 36, height: 4.5)
                .padding(.top, 1)

            HStack(spacing: 0) {
                // Left Quick Action Icons (Undo, Redo, Copy, Paste)
                HStack(spacing: 12) {
                    quickTypeIconButton("arrow.uturn.backward", help: "Undo") {
                        state.onShortcut?(.undo)
                    }
                    quickTypeIconButton("arrow.uturn.forward", help: "Redo") {
                        state.onShortcut?(.redo)
                    }
                    quickTypeIconButton("doc.on.doc", help: "Copy") {
                        state.onShortcut?(.copy)
                    }
                    quickTypeIconButton("doc.on.clipboard", help: "Paste") {
                        state.onShortcut?(.paste)
                    }
                }
                .padding(.leading, 8)

                Spacer(minLength: 10)

                // Right Controls (Select All + Keyboard Dismiss)
                HStack(spacing: 10) {
                    quickTypeIconButton("selection.pin.in.out", help: "Select All") {
                        state.onShortcut?(.selectAll)
                    }
                    Button {
                        state.onDismiss?()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(keyPrimaryText.opacity(0.75))
                            .frame(width: 28, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 8)
            }
            .frame(height: 30)
        }
        .background(WindowDragHandle())
    }

    private func quickTypeIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundColor(keyPrimaryText.opacity(0.78))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - iPadOS Letter Rows (Rows 1, 2, 3)

    private var iPadLetterRows: some View {
        VStack(spacing: 6) {
            // Row 1: tab + Q W E R T Y U I O P (Ğ Ü) + delete
            HStack(spacing: 5.5) {
                iPadModifierKey(
                    label: "tab",
                    icon: nil,
                    alignment: .bottomLeading,
                    width: 50
                ) {
                    state.onSpecialKey?(.tab)
                }

                ForEach(Array(row1Letters.enumerated()), id: \.offset) { idx, baseKey in
                    let hint = idx < row1TopHints.count ? row1TopHints[idx] : nil
                    iPadLetterKey(
                        main: displayChar(for: baseKey),
                        secondary: hint
                    )
                }

                iPadModifierKey(
                    label: nil,
                    icon: "delete.left",
                    alignment: .center,
                    width: 52
                ) {
                    state.onSpecialKey?(.backspace)
                }
            }

            // Row 2: caps lock + A S D F G H J K L (Ş İ) + return
            HStack(spacing: 5.5) {
                iPadCapsLockKey(width: 62)

                ForEach(Array(row2Letters.enumerated()), id: \.offset) { idx, baseKey in
                    let hint = idx < row2TopHints.count ? row2TopHints[idx] : nil
                    iPadLetterKey(
                        main: displayChar(for: baseKey),
                        secondary: hint
                    )
                }

                iPadReturnKey(width: 68)
            }

            // Row 3: left shift + Z X C V B N M (Ö Ç) , . + right shift
            HStack(spacing: 5.5) {
                iPadShiftKey(width: 66)

                ForEach(Array(row3Letters.enumerated()), id: \.offset) { idx, baseKey in
                    let hint = idx < row3TopHints.count ? row3TopHints[idx] : nil
                    iPadLetterKey(
                        main: displayChar(for: baseKey),
                        secondary: hint
                    )
                }

                iPadShiftKey(width: 66)
            }
        }
    }

    // MARK: - iPadOS Symbol Rows (.?123 and #+=)

    private var iPadSymbolRows: some View {
        let r1 = state.isMoreSymbols ? symRow1Page2 : symRow1Page1
        let r2 = state.isMoreSymbols ? symRow2Page2 : symRow2Page1
        let r3 = state.isMoreSymbols ? symRow3Page2 : symRow3Page1

        return VStack(spacing: 6) {
            // Row 1: tab + 1 2 3 4 5 6 7 8 9 0 + delete
            HStack(spacing: 5.5) {
                iPadModifierKey(
                    label: "tab",
                    icon: nil,
                    alignment: .bottomLeading,
                    width: 50
                ) {
                    state.onSpecialKey?(.tab)
                }

                ForEach(r1, id: \.self) { sym in
                    iPadLetterKey(main: sym, secondary: nil)
                }

                iPadModifierKey(
                    label: nil,
                    icon: "delete.left",
                    alignment: .center,
                    width: 52
                ) {
                    state.onSpecialKey?(.backspace)
                }
            }

            // Row 2: caps/blank + symbols + return
            HStack(spacing: 5.5) {
                iPadModifierKey(
                    label: state.isMoreSymbols ? "123" : "#+=",
                    icon: nil,
                    alignment: .center,
                    width: 62
                ) {
                    state.isMoreSymbols.toggle()
                }

                ForEach(r2, id: \.self) { sym in
                    iPadLetterKey(main: sym, secondary: nil)
                }

                iPadReturnKey(width: 68)
            }

            // Row 3: #+= toggle + punctuation + #+= toggle
            HStack(spacing: 5.5) {
                iPadModifierKey(
                    label: state.isMoreSymbols ? "123" : "#+=",
                    icon: nil,
                    alignment: .center,
                    width: 66
                ) {
                    state.isMoreSymbols.toggle()
                }

                ForEach(r3, id: \.self) { sym in
                    iPadLetterKey(main: sym, secondary: nil)
                }

                iPadModifierKey(
                    label: state.isMoreSymbols ? "123" : "#+=",
                    icon: nil,
                    alignment: .center,
                    width: 66
                ) {
                    state.isMoreSymbols.toggle()
                }
            }
        }
    }

    // MARK: - iPadOS Bottom Row (.?123, Globe, Space, Arrows, Dismiss Keyboard)

    private var iPadBottomRow: some View {
        HStack(spacing: 5.5) {
            // .?123 / ABC key
            iPadModifierKey(
                label: state.isSymbols ? "ABC" : ".?123",
                icon: nil,
                alignment: .bottomLeading,
                width: 58
            ) {
                state.isSymbols.toggle()
                if !state.isSymbols {
                    state.isMoreSymbols = false
                }
            }

            // Globe: cycles through the keyboard layouts enabled in macOS
            Button {
                state.onCycleLayout?()
            } label: {
                ZStack(alignment: .bottomLeading) {
                    iPadKeycapBackground(color: modifierKeyBg)
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(keyPrimaryText)
                        .padding(.leading, 8)
                        .padding(.bottom, 7)
                }
                .frame(width: 44, height: 39)
            }
            .buttonStyle(.plain)
            .help("Switch Keyboard Layout")

            // Space bar
            Button {
                state.onSpecialKey?(.space)
            } label: {
                ZStack {
                    iPadKeycapBackground(color: letterKeyBg)
                    Text(state.layoutTitle)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(keyPrimaryText.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 39)
            }
            .buttonStyle(.plain)

            // Right .?123 key
            iPadModifierKey(
                label: state.isSymbols ? "ABC" : ".?123",
                icon: nil,
                alignment: .bottomTrailing,
                width: 54
            ) {
                state.isSymbols.toggle()
                if !state.isSymbols {
                    state.isMoreSymbols = false
                }
            }

            // Compact Arrow Cluster (Left, Up/Down, Right)
            HStack(spacing: 3) {
                iPadArrowKey("chevron.left", key: .leftArrow)
                VStack(spacing: 2) {
                    iPadHalfArrowKey("chevron.up", key: .upArrow)
                    iPadHalfArrowKey("chevron.down", key: .downArrow)
                }
                iPadArrowKey("chevron.right", key: .rightArrow)
            }

            // Signature iPadOS Bottom-Right Dismiss Keyboard Key
            iPadModifierKey(
                label: nil,
                icon: "keyboard.chevron.compact.down",
                alignment: .center,
                width: 48
            ) {
                state.onDismiss?()
            }
        }
    }

    // MARK: - Authentic iPadOS Keycap Builders

    private func iPadKeycapBackground(color: Color) -> some View {
        ZStack {
            // 3D Bottom Shadow Edge (iPadOS key elevation)
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(keyShadowColor)
                .offset(y: 1.4)

            // Keycap Surface
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(color)
        }
    }

    private func iPadLetterKey(main: String, secondary: String?) -> some View {
        Button {
            state.onTypeText?(main)
            if state.isShifted && !state.isCapsLocked {
                state.isShifted = false
            }
        } label: {
            ZStack {
                iPadKeycapBackground(color: letterKeyBg)

                if let secondary {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Text(secondary)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(keySecondaryText)
                                .padding(.trailing, 4.5)
                                .padding(.top, 2.5)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text(main)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(keyPrimaryText)
                    .offset(y: secondary != nil ? 3 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 39)
        }
        .buttonStyle(.plain)
    }

    private func iPadModifierKey(
        label: String?,
        icon: String?,
        alignment: Alignment,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: alignment) {
                iPadKeycapBackground(color: modifierKeyBg)

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundColor(keyPrimaryText)
                        .padding(alignment == .center ? 0 : 7)
                } else if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(keyPrimaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                }
            }
            .frame(width: width, height: 39)
        }
        .buttonStyle(.plain)
    }

    private func iPadCapsLockKey(width: CGFloat) -> some View {
        Button {
            state.isCapsLocked.toggle()
            if state.isCapsLocked {
                state.isShifted = false
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                iPadKeycapBackground(color: state.isCapsLocked ? activeModifierKeyBg : modifierKeyBg)

                // iPadOS green LED indicator in top-left corner
                VStack {
                    HStack {
                        Circle()
                            .fill(state.isCapsLocked ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.black.opacity(0.18))
                            .frame(width: 4.5, height: 4.5)
                            .padding(.leading, 7)
                            .padding(.top, 6)
                        Spacer()
                    }
                    Spacer()
                }

                Text("caps lock")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(keyPrimaryText)
                    .padding(.leading, 7)
                    .padding(.bottom, 6)
            }
            .frame(width: width, height: 39)
        }
        .buttonStyle(.plain)
    }

    private func iPadShiftKey(width: CGFloat) -> some View {
        Button {
            if state.isShifted {
                state.isShifted = false
            } else {
                state.isShifted = true
            }
        } label: {
            let isLit = state.isShifted || state.isCapsLocked
            ZStack(alignment: .center) {
                iPadKeycapBackground(color: isLit ? activeModifierKeyBg : modifierKeyBg)
                Image(systemName: state.isCapsLocked ? "capslock.fill" : (state.isShifted ? "shift.fill" : "shift"))
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundColor(keyPrimaryText)
            }
            .frame(width: width, height: 39)
        }
        .buttonStyle(.plain)
    }

    private func iPadReturnKey(width: CGFloat) -> some View {
        Button {
            state.onSpecialKey?(.returnKey)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                iPadKeycapBackground(color: returnKeyBg)
                Text("return")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
            }
            .frame(width: width, height: 39)
        }
        .buttonStyle(.plain)
    }

    private func iPadArrowKey(_ icon: String, key: TouchKeyboardController.SpecialKey) -> some View {
        Button {
            state.onSpecialKey?(key)
        } label: {
            ZStack {
                iPadKeycapBackground(color: modifierKeyBg)
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(keyPrimaryText)
            }
            .frame(width: 26, height: 39)
        }
        .buttonStyle(.plain)
    }

    private func iPadHalfArrowKey(_ icon: String, key: TouchKeyboardController.SpecialKey) -> some View {
        Button {
            state.onSpecialKey?(key)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(keyShadowColor)
                    .offset(y: 1.0)
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(modifierKeyBg)
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(keyPrimaryText)
            }
            .frame(width: 26, height: 18.5)
        }
        .buttonStyle(.plain)
    }

    private func displayChar(for base: String) -> String {
        guard uppercaseActive else { return base }
        return base.uppercased(with: state.layout.locale)
    }
}

private final class TouchKeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages the floating Accessibility-style Mini Touch Keyboard that appears when tapping any text input,
/// and automatically dismisses on physical keyboard input or touching outside the keyboard.
final class TouchKeyboardController {
    static let shared = TouchKeyboardController()

    static let panelWidth: CGFloat = 620
    static let panelHeight: CGFloat = 236

    enum SpecialKey {
        case backspace
        case returnKey
        case tab
        case space
        case escape
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
    }

    enum ShortcutAction {
        case undo
        case redo
        case copy
        case paste
        case selectAll
    }

    private let state = TouchKeyboardState()
    private var panel: TouchKeyboardPanel?
    private weak var activeInjector: EventInjector?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var focusCheckWorkItem: DispatchWorkItem?
    private(set) var lastPresentTime: TimeInterval = 0
    private var lastDismissTime: TimeInterval = 0

    var onVisibilityChanged: ((Bool) -> Void)?

    var isVisible: Bool {
        panel?.isVisible == true && state.isPresented
    }

    /// Current Mini Keyboard frame in global Quartz (top-left origin) screen coordinates.
    var keyboardQuartzRect: CGRect {
        guard let panel, panel.isVisible else { return .zero }
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let f = panel.frame
        return CGRect(
            x: f.origin.x,
            y: primaryHeight - f.origin.y - f.height,
            width: f.width,
            height: f.height
        )
    }

    private init() {
        state.onTypeText = { [weak self] text in
            self?.activeInjector?.typeUnicode(text)
        }
        state.onSpecialKey = { [weak self] special in
            self?.sendSpecialKey(special)
        }
        state.onShortcut = { [weak self] shortcut in
            self?.sendShortcut(shortcut)
        }
        state.onDismiss = { [weak self] in
            self?.dismiss()
        }
        state.onCycleLayout = { [weak self] in
            self?.cycleLayout()
        }
        refreshLayout()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLayout()
        }
        setupHardwareDismissMonitors()
    }

    // MARK: - Keyboard Layout (follows macOS) & Remembered Position

    /// Re-reads the keyboard layout currently selected in macOS and applies it to the on-screen keyboard.
    func refreshLayout() {
        let current = KeyboardLayouts.current()
        state.layout = current.spec
        state.layoutTitle = current.title
    }

    /// Globe key: steps through the keyboard layouts enabled in macOS without changing the system input source.
    private func cycleLayout() {
        let options = KeyboardLayouts.enabled()
        guard options.count > 1 else { return }
        let index = options.firstIndex(where: { $0.spec.code == state.layout.code }) ?? -1
        let next = options[(index + 1) % options.count]
        state.layout = next.spec
        state.layoutTitle = next.title
    }

    private var rememberedOrigin: NSPoint?

    /// Called after the user finishes dragging the keyboard so it reopens where they left it.
    func rememberUserPosition() {
        if let frame = panel?.frame {
            rememberedOrigin = frame.origin
        }
    }

    private func rememberedFrame(avoiding tapQuartzPoint: CGPoint?) -> NSRect? {
        guard let origin = rememberedOrigin else { return nil }
        let frame = NSRect(origin: origin, size: NSSize(width: Self.panelWidth, height: Self.panelHeight))
        guard NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }) else {
            return nil
        }
        if let tap = tapQuartzPoint {
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            let quartz = CGRect(
                x: frame.origin.x,
                y: primaryHeight - frame.origin.y - frame.height,
                width: frame.width,
                height: frame.height
            )
            if quartz.insetBy(dx: -16, dy: -16).contains(tap) { return nil }
        }
        return frame
    }

    // MARK: - Hit-Testing & Visibility

    /// Returns `true` if `quartzPoint` is inside the visible Mini Touch Keyboard.
    func contains(_ quartzPoint: CGPoint) -> Bool {
        guard isVisible else { return false }
        return keyboardQuartzRect.insetBy(dx: -8, dy: -8).contains(quartzPoint)
    }

    /// Called when the user touches down at `quartzPoint`.
    /// Does not immediately dismiss on first frame so resting palms or top-menubar keyboard toggle taps never kill the keyboard prematurely.
    func handleTouchDown(at quartzPoint: CGPoint) {
        focusCheckWorkItem?.cancel()
        focusCheckWorkItem = nil
    }

    /// Called when a confirmed drag or scroll gesture begins outside the keyboard.
    func handleOutsideGestureBegan(at quartzPoint: CGPoint) {
        guard isVisible, !contains(quartzPoint) else { return }
        if (ProcessInfo.processInfo.systemUptime - lastPresentTime) < 0.35 { return }
        dismiss()
    }

    /// Called after a single-finger tap completes at `quartzPoint`.
    /// Checks whether the tapped UI element (or newly focused element) is an editable text field;
    /// if the keyboard is already open and the user tapped outside on a non-text element, dismisses it.
    func handleScreenTap(at quartzPoint: CGPoint, injector: EventInjector) {
        if isVisible && contains(quartzPoint) { return }

        // Ignore taps in the top 34pt macOS Menu Bar strip so clicking the Top Bar Keyboard button never fights with auto-dismiss.
        var tapDisplayID: CGDirectDisplayID = CGMainDisplayID()
        var tapDisplayCount: UInt32 = 0
        CGGetDisplaysWithPoint(quartzPoint, 1, &tapDisplayID, &tapDisplayCount)
        let tapDisplayBounds = CGDisplayBounds(tapDisplayID)
        if tapDisplayBounds.height > 0 && quartzPoint.y <= (tapDisplayBounds.minY + 34.0) {
            return
        }

        activeInjector = injector
        focusCheckWorkItem?.cancel()

        // 1. Immediate check at the tapped coordinates.
        if Settings.shared.touchKeyboard && Self.isEditableTextInput(near: quartzPoint) {
            present(near: quartzPoint)
            return
        }

        // 2. Deferred check (+65ms) after the target application processes the synthesized mouse click
        // and updates `kAXFocusedUIElementAttribute` (essential for Safari, Chrome, Electron, and SwiftUI fields).
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if Settings.shared.touchKeyboard &&
               (Self.isEditableTextInput(near: quartzPoint) || Self.isFocusedElementEditable(near: quartzPoint)) {
                self.present(near: quartzPoint)
            } else if self.isVisible && !self.contains(quartzPoint) && (ProcessInfo.processInfo.systemUptime - self.lastPresentTime) > 0.35 {
                self.dismiss()
            }
        }
        focusCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.065, execute: work)
    }

    /// Toggles the iPadOS Touch Keyboard manually from the Top Bar button or menu.
    func toggleManual(onDisplay displayID: CGDirectDisplayID?, injector: EventInjector) {
        let now = ProcessInfo.processInfo.systemUptime
        if isVisible || (now - lastDismissTime) < 0.25 {
            dismiss()
        } else {
            presentManual(onDisplay: displayID, injector: injector)
        }
    }

    /// Opens the iPadOS Touch Keyboard centered near the bottom of `displayID` (even if no text box was auto-detected).
    func presentManual(onDisplay displayID: CGDirectDisplayID?, injector: EventInjector) {
        activeInjector = injector
        focusCheckWorkItem?.cancel()
        focusCheckWorkItem = nil

        if eventTap == nil {
            installPassiveKeyTapIfNeeded()
        }
        ensurePanel()
        guard let panel else { return }

        let targetID = displayID ?? CGMainDisplayID()
        let bounds = CGDisplayBounds(targetID)

        var qx = bounds.midX - (Self.panelWidth * 0.5)
        var qy = bounds.maxY - Self.panelHeight - 36.0

        if bounds.width > 0 && bounds.height > 0 {
            qx = min(max(qx, bounds.minX + 12), bounds.maxX - Self.panelWidth - 12)
            qy = min(max(qy, bounds.minY + 34), bounds.maxY - Self.panelHeight - 16)
        }

        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let appKitOriginY = primaryHeight - qy - Self.panelHeight
        let frame = rememberedFrame(avoiding: nil)
            ?? NSRect(x: qx, y: appKitOriginY, width: Self.panelWidth, height: Self.panelHeight)

        refreshLayout()
        lastPresentTime = ProcessInfo.processInfo.systemUptime
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.isPresented = true
            self.onVisibilityChanged?(true)
        }
        Log.write("Mini Touch Keyboard opened manually on display \(targetID) at (\(Int(qx)), \(Int(qy)))", force: true)
    }

    func present(near tapQuartzPoint: CGPoint) {
        if eventTap == nil {
            installPassiveKeyTapIfNeeded()
        }
        ensurePanel()
        guard let panel else { return }

        // If already visible on the same screen, keep its current user-positioned location unless it would cover the tap point.
        let currentRect = keyboardQuartzRect
        if isVisible && !currentRect.insetBy(dx: -16, dy: -16).contains(tapQuartzPoint) {
            return
        }

        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(tapQuartzPoint, 1, &displayID, &count)
        let bounds = CGDisplayBounds(displayID)

        var qx = tapQuartzPoint.x - (Self.panelWidth * 0.5)
        // Prefer placing the keyboard 44pt below the tapped text box; if near the bottom of the screen, place it above.
        var qy = tapQuartzPoint.y + 44.0
        if bounds.height > 0 && (qy + Self.panelHeight > bounds.maxY - 16) {
            qy = tapQuartzPoint.y - Self.panelHeight - 38.0
        }

        if bounds.width > 0 && bounds.height > 0 {
            qx = min(max(qx, bounds.minX + 12), bounds.maxX - Self.panelWidth - 12)
            qy = min(max(qy, bounds.minY + 28), bounds.maxY - Self.panelHeight - 12)
        }

        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let appKitOriginY = primaryHeight - qy - Self.panelHeight
        let frame = rememberedFrame(avoiding: tapQuartzPoint)
            ?? NSRect(x: qx, y: appKitOriginY, width: Self.panelWidth, height: Self.panelHeight)

        refreshLayout()
        lastPresentTime = ProcessInfo.processInfo.systemUptime
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.isPresented = true
            self.onVisibilityChanged?(true)
        }
        Log.write("Mini Touch Keyboard opened at (\(Int(qx)), \(Int(qy)))", force: true)
    }

    func dismiss() {
        focusCheckWorkItem?.cancel()
        focusCheckWorkItem = nil
        guard panel?.isVisible == true else { return }
        lastDismissTime = ProcessInfo.processInfo.systemUptime
        state.isPresented = false
        onVisibilityChanged?(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, !self.state.isPresented else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let p = TouchKeyboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.worksWhenModal = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: MiniTouchKeyboardView(state: state))
        panel = p
    }

    // MARK: - Key Synthesis

    private func sendSpecialKey(_ key: SpecialKey) {
        guard let injector = activeInjector else { return }
        switch key {
        case .backspace:  injector.pressKey(51)
        case .returnKey:  injector.pressKey(36)
        case .tab:        injector.pressKey(48)
        case .space:      injector.pressKey(49)
        case .escape:     injector.pressKey(53)
        case .leftArrow:  injector.pressKey(123, flags: [.maskSecondaryFn, .maskNumericPad])
        case .rightArrow: injector.pressKey(124, flags: [.maskSecondaryFn, .maskNumericPad])
        case .downArrow:  injector.pressKey(125, flags: [.maskSecondaryFn, .maskNumericPad])
        case .upArrow:    injector.pressKey(126, flags: [.maskSecondaryFn, .maskNumericPad])
        }
    }

    private func sendShortcut(_ action: ShortcutAction) {
        guard let injector = activeInjector else { return }
        switch action {
        case .undo:      injector.pressKey(6, flags: .maskCommand)                    // Cmd+Z
        case .redo:      injector.pressKey(6, flags: [.maskCommand, .maskShift])      // Cmd+Shift+Z
        case .copy:      injector.pressKey(8, flags: .maskCommand)                    // Cmd+C
        case .paste:     injector.pressKey(9, flags: .maskCommand)                    // Cmd+V
        case .selectAll: injector.pressKey(0, flags: .maskCommand)                    // Cmd+A
        }
    }

    // MARK: - Physical Keyboard & Outside-Click Auto-Dismiss Monitors

    private func setupHardwareDismissMonitors() {
        // 1. AppKit global & local keyDown monitors: dismiss whenever the user types on the physical keyboard.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handlePotentialPhysicalKeyEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handlePotentialPhysicalKeyEvent(event)
            return event
        }

        // 2. Global physical mouse click outside the keyboard panel also dismisses it unless clicking the top menu bar or a text field.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if (now - self.lastPresentTime) < 0.30 { return }
            if (now - EventInjector.lastSyntheticMouseTime) < 0.12 { return }
            if let cg = event.cgEvent, cg.getIntegerValueField(.eventSourceUserData) == EventInjector.syntheticEventTag {
                return
            }
            let mouseLoc = NSEvent.mouseLocation
            // Ignore clicks in the top 34pt macOS Menu Bar strip so clicking the Top Bar Keyboard button toggles cleanly.
            for screen in NSScreen.screens {
                if screen.frame.contains(mouseLoc) && mouseLoc.y >= (screen.frame.maxY - 34.0) {
                    return
                }
            }
            if let panel = self.panel, !panel.frame.insetBy(dx: -8, dy: -8).contains(mouseLoc) {
                self.dismiss()
            }
        }

        // 3. Passive listen-only Quartz CGEventTap to guarantee physical key press detection across all apps.
        installPassiveKeyTapIfNeeded()
    }

    private func installPassiveKeyTapIfNeeded() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<TouchKeyboardController>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = controller.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                let tag = event.getIntegerValueField(.eventSourceUserData)
                let now = ProcessInfo.processInfo.systemUptime
                if tag != EventInjector.syntheticEventTag && (now - EventInjector.lastSyntheticKeyTime) > 0.08 {
                    DispatchQueue.main.async {
                        if controller.isVisible {
                            controller.dismiss()
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handlePotentialPhysicalKeyEvent(_ event: NSEvent) {
        guard isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if (now - EventInjector.lastSyntheticKeyTime) < 0.08 { return }
        if let cg = event.cgEvent, cg.getIntegerValueField(.eventSourceUserData) == EventInjector.syntheticEventTag {
            return
        }
        dismiss()
    }

    // MARK: - Accessibility Text Input Detection

    private static let textInputRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField",
        kAXComboBoxRole as String,
    ]

    private static let textInputSubroles: Set<String> = [
        "AXSearchField",
        "AXSecureTextField",
        "AXTextInput",
    ]

    private static let nonTextControlRoles: Set<String> = [
        kAXWindowRole as String,
        kAXApplicationRole as String,
        kAXScrollAreaRole as String,
        kAXToolbarRole as String,
        kAXButtonRole as String,
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXSliderRole as String,
        kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String,
        kAXImageRole as String,
        kAXMenuBarRole as String,
        kAXMenuItemRole as String,
    ]

    /// Checks whether the UI element at `point` (or its immediate ancestors) is an editable text input.
    private static func isEditableTextInput(near point: CGPoint) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var hitRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hitRef) == .success,
              let hit = hitRef else {
            return false
        }

        // Never treat our own TouchKeyboardPanel or TrafficLightOverlayPanel as a text input.
        var pid: pid_t = 0
        if AXUIElementGetPid(hit, &pid) == .success, pid == ProcessInfo.processInfo.processIdentifier {
            if TouchKeyboardController.shared.contains(point) || TrafficLightOverlayController.shared.contains(point) {
                return false
            }
        }

        var current: AXUIElement? = hit
        for _ in 0..<4 {
            guard let el = current else { break }
            if isElementEditableText(el) {
                return true
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }
        return false
    }

    /// Checks whether the frontmost application's currently focused UI element is an editable text field covering `point`.
    private static func isFocusedElementEditable(near point: CGPoint) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        var focusedElement: AXUIElement?

        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let ref = focusedRef {
            focusedElement = (ref as! AXUIElement)
        } else if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appAX = AXUIElementCreateApplication(frontPID)
            if AXUIElementCopyAttributeValue(appAX, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
               let ref = focusedRef {
                focusedElement = (ref as! AXUIElement)
            }
        }

        guard let focused = focusedElement, isElementEditableText(focused) else {
            return false
        }

        // Ensure the tap point actually landed on or near the focused text input.
        if let rect = frame(of: focused) {
            return rect.insetBy(dx: -28, dy: -24).contains(point)
        }
        return true
    }

    private static func isElementEditableText(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
        if textInputRoles.contains(role) {
            return true
        }

        if let subrole = stringAttribute(element, kAXSubroleAttribute as CFString),
           textInputSubroles.contains(subrole) {
            return true
        }

        var editableRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef) == .success,
           let num = editableRef as? NSNumber, num.boolValue {
            return true
        }

        guard !nonTextControlRoles.contains(role) else { return false }

        var rangeSettable = DarwinBoolean(false)
        var valueSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &rangeSettable) == .success,
           rangeSettable.boolValue,
           AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable) == .success,
           valueSettable.boolValue {
            return true
        }

        return false
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
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
