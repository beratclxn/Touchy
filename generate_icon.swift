import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "/tmp/ProArtTouchIcon/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: outDir)
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func cgPath(_ bezier: NSBezierPath) -> CGPath {
    let path = CGMutablePath()
    var pts = [NSPoint](repeating: .zero, count: 3)
    for i in 0..<bezier.elementCount {
        switch bezier.element(at: i, associatedPoints: &pts) {
        case .moveTo: path.move(to: pts[0])
        case .lineTo: path.addLine(to: pts[0])
        case .curveTo, .cubicCurveTo: path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
        case .quadraticCurveTo: path.addQuadCurve(to: pts[1], control: pts[0])
        case .closePath: path.closeSubpath()
        @unknown default: break
        }
    }
    return path
}

/// Draws a glass panel: drop shadow, optional solid underlay, gradient fill and a gradient specular rim.
func glassPanel(
    _ ctx: CGContext, _ path: NSBezierPath, bounds: CGRect, s: CGFloat,
    underlay: NSColor?, fill: [CGColor], rimWidth: CGFloat, rimAlpha: CGFloat
) {
    let cs = CGColorSpaceCreateDeviceRGB()
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.016),
        blur: s * 0.034,
        color: CGColor(red: 0.0, green: 0.07, blue: 0.11, alpha: 0.6)
    )
    (underlay ?? NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.75, alpha: 0.4)).setFill()
    path.fill()
    ctx.restoreGState()

    ctx.saveGState()
    path.addClip()
    if let g = CGGradient(colorsSpace: cs, colors: fill as CFArray, locations: nil) {
        ctx.drawLinearGradient(
            g,
            start: CGPoint(x: bounds.minX, y: bounds.maxY),
            end: CGPoint(x: bounds.maxX, y: bounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(cgPath(path).copy(strokingWithWidth: rimWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    let rim = [
        CGColor(red: 1, green: 1, blue: 1, alpha: rimAlpha),
        CGColor(red: 0.7, green: 1, blue: 0.94, alpha: rimAlpha * 0.25),
        CGColor(red: 1, green: 1, blue: 1, alpha: rimAlpha * 0.6),
    ] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: rim, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(
            g,
            start: CGPoint(x: bounds.minX, y: bounds.maxY),
            end: CGPoint(x: bounds.maxX, y: bounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    ctx.restoreGState()
}

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    let cs = CGColorSpaceCreateDeviceRGB()
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // 1. macOS squircle
    let pad = s * 0.088
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let corner = rect.width * 0.228
    let squircle = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.042,
                  color: CGColor(red: 0, green: 0.06, blue: 0.10, alpha: 0.45))
    NSColor(calibratedRed: 0.03, green: 0.38, blue: 0.40, alpha: 1).setFill()
    squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()

    // 2. Turquoise background
    let bg = [
        CGColor(red: 0.13, green: 0.80, blue: 0.76, alpha: 1),
        CGColor(red: 0.05, green: 0.58, blue: 0.58, alpha: 1),
        CGColor(red: 0.02, green: 0.34, blue: 0.40, alpha: 1),
    ] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: bg, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    let bloom = [
        CGColor(red: 0.60, green: 1.00, blue: 0.92, alpha: 0.34),
        CGColor(red: 0.60, green: 1.00, blue: 0.92, alpha: 0),
    ] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: bloom, locations: [0, 1]) {
        let c = CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY - rect.height * 0.08)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s * 0.55, options: [])
    }

    // 3. Back rectangle: the Mac's built-in screen (dimmer glass)
    let macRect = CGRect(x: s * 0.165, y: s * 0.455, width: s * 0.54, height: s * 0.345)
    let macPath = NSBezierPath(roundedRect: macRect, xRadius: s * 0.045, yRadius: s * 0.045)
    glassPanel(ctx, macPath, bounds: macRect, s: s,
               underlay: NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.48, alpha: 1),
               fill: [
                   CGColor(red: 0.45, green: 0.88, blue: 0.84, alpha: 0.50),
                   CGColor(red: 0.14, green: 0.64, blue: 0.64, alpha: 0.38),
               ], rimWidth: s * 0.006, rimAlpha: 0.45)

    // 4. Front rectangle: the external monitor, overlapping on top (brighter, more opaque glass)
    let extRect = CGRect(x: s * 0.31, y: s * 0.215, width: s * 0.56, height: s * 0.375)
    let extPath = NSBezierPath(roundedRect: extRect, xRadius: s * 0.048, yRadius: s * 0.048)
    glassPanel(ctx, extPath, bounds: extRect, s: s,
               underlay: NSColor(calibratedRed: 0.08, green: 0.56, blue: 0.56, alpha: 1),
               fill: [
                   CGColor(red: 0.56, green: 0.98, blue: 0.90, alpha: 0.80),
                   CGColor(red: 0.18, green: 0.82, blue: 0.78, alpha: 0.66),
               ], rimWidth: s * 0.009, rimAlpha: 0.80)

    // 5. Bright white touch gesture line drawn on the external monitor
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    let squiggle = NSBezierPath()
    squiggle.move(to: P(0.385, 0.325))
    squiggle.curve(to: P(0.50, 0.50), controlPoint1: P(0.395, 0.41), controlPoint2: P(0.445, 0.54))
    squiggle.curve(to: P(0.595, 0.355), controlPoint1: P(0.545, 0.46), controlPoint2: P(0.545, 0.355))
    squiggle.curve(to: P(0.695, 0.48), controlPoint1: P(0.64, 0.355), controlPoint2: P(0.655, 0.48))
    squiggle.curve(to: P(0.80, 0.505), controlPoint1: P(0.735, 0.48), controlPoint2: P(0.77, 0.52))
    squiggle.lineWidth = s * 0.034
    squiggle.lineCapStyle = .round
    squiggle.lineJoinStyle = .round

    ctx.saveGState()
    extPath.addClip()
    ctx.setShadow(offset: .zero, blur: s * 0.040, color: CGColor(red: 0.75, green: 1, blue: 0.95, alpha: 0.95))
    NSColor.white.setStroke()
    squiggle.stroke()
    ctx.restoreGState()

    // Touch-down ring at the start of the gesture
    let start = P(0.385, 0.325)
    let nodeR = s * 0.030
    let ring = NSBezierPath(ovalIn: CGRect(x: start.x - nodeR * 1.8, y: start.y - nodeR * 1.8, width: nodeR * 3.6, height: nodeR * 3.6))
    NSColor(calibratedWhite: 1, alpha: 0.6).setStroke()
    ring.lineWidth = s * 0.006
    ring.stroke()

    ctx.restoreGState() // squircle clip

    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.004, dy: s * 0.004),
                           xRadius: corner - s * 0.003, yRadius: corner - s * 0.003)
    NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
    rim.lineWidth = s * 0.006
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    if let data = renderIcon(size: px) {
        try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
print("Iconset generated at \(outDir)")
