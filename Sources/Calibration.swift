import AppKit

/// Full-screen 4-point affine calibration overlay presented on the target touch display.
final class CalibrationController {
    private var window: NSWindow?
    private var view: CalibrationView?
    private let targets: [CGPoint] = [
        CGPoint(x: 0.1, y: 0.1),
        CGPoint(x: 0.9, y: 0.1),
        CGPoint(x: 0.9, y: 0.9),
        CGPoint(x: 0.1, y: 0.9),
    ]
    private var samples: [CGPoint] = []
    private var lastTouch: CGPoint?
    private let mapper: DisplayMapper
    private let minimumAxisSpan: CGFloat = 0.2

    var isActive: Bool { window != nil }

    init(mapper: DisplayMapper) {
        self.mapper = mapper
    }

    func start() {
        guard let id = mapper.displayID, let screen = DisplayMapper.nsScreen(for: id) else {
            presentAlert(
                title: "Touch Display Not Found",
                message: "Please select the target display first."
            )
            return
        }

        samples.removeAll(keepingCapacity: true)
        lastTouch = nil

        let overlayWindow = KeyWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow.level = .screenSaver
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = NSColor.black.withAlphaComponent(0.88)
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayWindow.onEscape = { [weak self] in self?.cancel() }

        let overlayView = CalibrationView(frame: NSRect(origin: .zero, size: screen.frame.size))
        overlayView.target = targets[0]
        overlayView.step = 0

        overlayWindow.contentView = overlayView
        overlayWindow.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow.makeKeyAndOrderFront(nil)

        window = overlayWindow
        view = overlayView
    }

    /// Processes raw contacts while calibration is active (bypassing GestureEngine).
    func feed(_ contacts: [RawContact]) {
        guard isActive else { return }

        if let contact = contacts.first {
            let point = mapper.oriented(contact)
            lastTouch = point
            view?.touchPoint = point
            view?.touching = true
            return
        }

        // Record the sample when the finger lifts off the glass.
        guard let point = lastTouch else { return }
        lastTouch = nil
        view?.touchPoint = nil
        view?.touching = false
        samples.append(point)
        Log.write("Calibration sample \(samples.count): (\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y)))", force: true)

        if samples.count == targets.count {
            finish()
        } else {
            view?.target = targets[samples.count]
            view?.step = samples.count
        }
    }

    func cancel() {
        close()
    }

    private func finish() {
        let recorded = samples
        close()
        guard recorded.count == 4 else { return }

        let left = (recorded[0].x + recorded[3].x) * 0.5
        let right = (recorded[1].x + recorded[2].x) * 0.5
        let top = (recorded[0].y + recorded[1].y) * 0.5
        let bottom = (recorded[2].y + recorded[3].y) * 0.5

        guard abs(right - left) > minimumAxisSpan, abs(bottom - top) > minimumAxisSpan else {
            let formatted = recorded.map { String(format: "(%.2f, %.2f)", $0.x, $0.y) }.joined(separator: " ")
            Log.write("Calibration failed with points: \(formatted)", force: true)
            presentAlert(
                title: "Calibration Failed",
                message: "Recorded points: \(formatted)\nPlease check the display orientation or selected target display and try again."
            )
            return
        }

        let scaleX = 0.8 / Double(right - left)
        let offsetX = 0.1 - scaleX * Double(left)
        let scaleY = 0.8 / Double(bottom - top)
        let offsetY = 0.1 - scaleY * Double(top)

        let transform = CalibrationTransform(scaleX: scaleX, offsetX: offsetX, scaleY: scaleY, offsetY: offsetY)
        Settings.shared.calibrationTransform = transform
        Log.write("Calibration saved: \(transform.rawArray)", force: true)
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private final class KeyWindow: NSWindow {
    private static let escapeKeyCode: UInt16 = 53
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class CalibrationView: NSView {
    var target = CGPoint(x: 0.1, y: 0.1) { didSet { needsDisplay = true } }
    var step = 0 { didSet { needsDisplay = true } }
    var touching = false { didSet { needsDisplay = true } }
    var touchPoint: CGPoint? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        // Convert top-left normalized target to bottom-left NSView coordinates.
        let center = CGPoint(x: b.width * target.x, y: b.height * (1 - target.y))
        let strokeColor: NSColor = touching ? .systemGreen : .systemOrange
        strokeColor.setStroke()

        let crosshair = NSBezierPath()
        crosshair.lineWidth = 2
        crosshair.move(to: CGPoint(x: center.x - 30, y: center.y))
        crosshair.line(to: CGPoint(x: center.x + 30, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 30))
        crosshair.line(to: CGPoint(x: center.x, y: center.y + 30))
        crosshair.stroke()

        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
        ring.lineWidth = 3
        ring.stroke()

        if let tp = touchPoint {
            let touchCenter = CGPoint(x: b.width * tp.x, y: b.height * (1 - tp.y))
            NSColor.systemCyan.setFill()
            NSBezierPath(ovalIn: NSRect(x: touchCenter.x - 8, y: touchCenter.y - 8, width: 16, height: 16)).fill()
        }

        let prompt = "Calibration \(step + 1)/4 — Touch the center of the crosshair and lift your finger.\nPress Esc to cancel"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        let textRect = NSRect(x: 0, y: b.midY - 40, width: b.width, height: 80)
        (prompt as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
