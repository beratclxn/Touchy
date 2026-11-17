import AppKit
import SwiftUI

enum TouchyTheme {
    static let aquaLight = Color(red: 0.45, green: 0.92, blue: 0.88)  // #73EBE0
    static let turquoise = Color(red: 0.13, green: 0.80, blue: 0.76)  // #21CCC2
    static let tealDeep = Color(red: 0.02, green: 0.50, blue: 0.54)   // #058089
    static let cyanGlow = Color(red: 0.40, green: 0.95, blue: 0.95)
    static let emerald = Color(red: 0.20, green: 0.86, blue: 0.58)
    static let amber = Color(red: 0.99, green: 0.72, blue: 0.22)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [aquaLight, turquoise, tealDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct TouchySquircleIcon: View {
    let systemName: String
    let colors: [Color]
    var size: CGFloat = 28

    var body: some View {
        let radius = size * 0.28
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: (colors.last ?? .blue).opacity(0.35), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            Image(systemName: systemName)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 1)
        }
    }
}

struct TouchyGlassCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColors: [Color] = [TouchyTheme.aquaLight, TouchyTheme.tealDeep]
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 10) {
                    if let icon {
                        TouchySquircleIcon(systemName: icon, colors: iconColors, size: 26)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 2)
            }

            content()
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.07),
                                TouchyTheme.aquaLight.opacity(0.03),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.07),
                            TouchyTheme.aquaLight.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 6)
    }
}

struct TouchyToggleRow: View {
    let icon: String
    let colors: [Color]
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TouchySquircleIcon(systemName: icon, colors: colors, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(TouchyTheme.turquoise)
                .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}

/// Renders the custom Touchy display template icon for the macOS Menu Bar.
enum MenuBarIconRenderer {
    static func makeIcon(enabled: Bool, connected: Bool, warning: Bool) -> NSImage {
        let size = NSSize(width: 19, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let alpha: CGFloat = enabled ? 1.0 : 0.45
            NSColor(calibratedWhite: 0.0, alpha: alpha).setFill()
            NSColor(calibratedWhite: 0.0, alpha: alpha).setStroke()

            // Back rectangle = Mac screen, front rectangle = external touch monitor with a gesture line on it.
            let macRect = NSRect(x: 1.5, y: 8.4, width: 11.6, height: 7.6)
            let mac = NSBezierPath(roundedRect: macRect, xRadius: 1.8, yRadius: 1.8)
            mac.lineWidth = 1.2
            mac.stroke()

            let extRect = NSRect(x: 5.4, y: 2.0, width: 12.2, height: 8.2)
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            NSBezierPath(roundedRect: extRect.insetBy(dx: -1.3, dy: -1.3), xRadius: 2.8, yRadius: 2.8).fill()
            ctx.restoreGState()
            let ext = NSBezierPath(roundedRect: extRect, xRadius: 1.9, yRadius: 1.9)
            ext.lineWidth = 1.5
            ext.stroke()

            let squiggle = NSBezierPath()
            squiggle.move(to: NSPoint(x: 7.2, y: 4.2))
            squiggle.curve(to: NSPoint(x: 9.8, y: 8.0), controlPoint1: NSPoint(x: 7.5, y: 6.2), controlPoint2: NSPoint(x: 8.6, y: 8.6))
            squiggle.curve(to: NSPoint(x: 12.0, y: 4.9), controlPoint1: NSPoint(x: 10.9, y: 7.2), controlPoint2: NSPoint(x: 10.9, y: 4.9))
            squiggle.curve(to: NSPoint(x: 15.6, y: 7.2), controlPoint1: NSPoint(x: 13.2, y: 4.9), controlPoint2: NSPoint(x: 14.2, y: 7.4))
            squiggle.lineWidth = 1.6
            squiggle.lineCapStyle = .round
            squiggle.lineJoinStyle = .round
            squiggle.stroke()

            if !enabled {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                let clearSlash = NSBezierPath()
                clearSlash.move(to: NSPoint(x: 2.0, y: 16.0))
                clearSlash.line(to: NSPoint(x: 17.0, y: 2.0))
                clearSlash.lineWidth = 3.2
                clearSlash.lineCapStyle = .round
                clearSlash.stroke()
                ctx.restoreGState()

                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2.0, y: 16.0))
                slash.line(to: NSPoint(x: 17.0, y: 2.0))
                slash.lineWidth = 1.6
                slash.lineCapStyle = .round
                slash.stroke()
            } else if warning {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                NSBezierPath(ovalIn: NSRect(x: 13.0, y: 12.2, width: 5.6, height: 5.6)).fill()
                ctx.restoreGState()
                NSBezierPath(ovalIn: NSRect(x: 14.0, y: 13.2, width: 3.8, height: 3.8)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
