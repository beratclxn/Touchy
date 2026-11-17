import AppKit
import SwiftUI

enum TouchyTheme {
    // Primary single accent (#21CCC2 turquoise) & compatibility constants
    static let aquaLight = Color(red: 0.45, green: 0.92, blue: 0.88)  // #73EBE0
    static let turquoise = Color(red: 0.13, green: 0.80, blue: 0.76)  // #21CCC2
    static let tealDeep = Color(red: 0.02, green: 0.50, blue: 0.54)   // #058089
    static let cyanGlow = Color(red: 0.40, green: 0.95, blue: 0.95)
    static let emerald = Color(red: 0.30, green: 0.76, blue: 0.54)    // #4CC38A
    static let amber = Color(red: 0.90, green: 0.60, blue: 0.20)      // #E59934
    static let accentInk = Color(red: 0.03, green: 0.08, blue: 0.08)  // #081414 (>4.5:1 on #21CCC2)

    // Graphite / Ink neutral ramp (adaptive Dark / Light)
    static let sidebarBg     = adaptive(dark: 0x0F1012, light: 0xF3F4F6)
    static let pageBg        = adaptive(dark: 0x141518, light: 0xFAFAFA)
    static let cardBg        = adaptive(dark: 0x1A1C20, light: 0xFFFFFF)
    static let raisedBg      = adaptive(dark: 0x23262B, light: 0xF1F2F4)
    static let hairline      = adaptiveAlpha(darkWhite: 1.0, darkAlpha: 0.08, lightWhite: 0.0, lightAlpha: 0.08)

    static let textPrimary   = adaptive(dark: 0xEDEDEF, light: 0x171717)
    static let textSecondary = adaptive(dark: 0xA1A4AB, light: 0x525252)
    static let textMuted     = adaptive(dark: 0x7E828C, light: 0x737373)

    static let positive      = adaptive(dark: 0x4CC38A, light: 0x16A34A)
    static let warning       = adaptive(dark: 0xE59934, light: 0xD97706)
    static let danger        = adaptive(dark: 0xE5484D, light: 0xDC2626)

    // Studio canvas surface for the live XY digitizer scope
    static let scopeBg       = Color(red: 0.043, green: 0.055, blue: 0.067) // #0B0E11

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [aquaLight, turquoise, tealDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        })
    }

    private static func adaptiveAlpha(
        darkWhite: CGFloat, darkAlpha: CGFloat,
        lightWhite: CGFloat, lightAlpha: CGFloat
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: darkWhite, alpha: darkAlpha)
                : NSColor(calibratedWhite: lightWhite, alpha: lightAlpha)
        })
    }
}

/// Signature monospaced hardware register / coordinate pill tag (`6pt` radius, `1px` hairline).
struct TouchyMonoTag: View {
    let text: String
    var color: Color = TouchyTheme.textSecondary
    var background: Color = TouchyTheme.raisedBg

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(TouchyTheme.hairline, lineWidth: 1)
            )
            .lineLimit(1)
    }
}

/// Crisp `6×6` status indicator dot without glow or blur.
struct TouchyStatusDot: View {
    var color: Color = TouchyTheme.positive

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

/// Monochrome `20×20` aligned line icon column.
struct TouchySquircleIcon: View {
    let systemName: String
    var colors: [Color] = []
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(TouchyTheme.textSecondary)
            .frame(width: max(size, 20), height: max(size, 20))
    }
}

/// Flat graphite card container with `20pt` padding, `12pt` radius, and a `1px` hairline border.
struct TouchyGlassCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var tag: String? = nil
    var icon: String? = nil
    var iconColors: [Color] = []
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || subtitle != nil || tag != nil {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title {
                            Text(title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(TouchyTheme.textPrimary)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(TouchyTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    if let tag {
                        TouchyMonoTag(text: tag)
                    }
                }
            }

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TouchyTheme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TouchyTheme.hairline, lineWidth: 1)
        )
    }
}

/// Aligned settings row with a `20×20` monochrome line icon, label + caption, and system switch.
struct TouchyToggleRow: View {
    let icon: String
    var colors: [Color] = []
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(TouchyTheme.textMuted)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TouchyTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(TouchyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(TouchyTheme.turquoise)
                .labelsHidden()
        }
        .padding(.vertical, 4)
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
