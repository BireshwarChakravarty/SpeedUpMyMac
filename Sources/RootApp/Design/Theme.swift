import SwiftUI
import RootCore

/// Design tokens (docs/DESIGN.md): native macOS surfaces, SF Pro, and one accent, lime, kept for
/// the thing you should press and the numbers that matter.
enum Theme {
    static let lime = Color(hex: 0xBEF264)
    static let leaf = Color(hex: 0x84CC16)
    static let emerald = Color(hex: 0x10B981)

    static let brand = LinearGradient(colors: [lime, Color(hex: 0xA3E635)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brandAngular = AngularGradient(colors: [Color(hex: 0xD9F99D), lime, leaf, Color(hex: 0xD9F99D)], center: .center)

    static let safe = Color(light: 0x15803D, dark: 0x4ADE80)
    static let review = Color(light: 0xB45309, dark: 0xFBBF24)
    static let risky = Color(light: 0xDC2626, dark: 0xF87171)
    static let sudo = Color(light: 0xB45309, dark: 0xF59E0B)
    static let danger = LinearGradient(colors: [Color(hex: 0xF43F5E), Color(hex: 0xE11D48)], startPoint: .top, endPoint: .bottom)

    /// Window background and the grouped surfaces that sit on it.
    static let base = Color(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let baseRaised = Color(light: 0xFFFFFF, dark: 0x262628)
    static let surface = Color(light: 0xFFFFFF, dark: 0x262628)
    static let sidebar = Color(light: 0xEDEDF0, dark: 0x2A2A2D)
    static let separator = Color(light: 0xE5E5EA, dark: 0x343437)
    static let track = Color(light: 0xE5E5EA, dark: 0x343437)
    static let rim = Color(light: 0x000000, dark: 0xFFFFFF)
    /// Text on lime.
    static let ink = Color(hex: 0x0A0F0A)
    /// Text on the accent wash in light mode, where pure lime is unreadable.
    static let accentText = Color(light: 0x4D7C0F, dark: 0xBEF264)

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .safe: return safe
        case .review: return review
        case .risky: return risky
        }
    }

    static func scoreColor(_ score: Int) -> Color { score >= 80 ? safe : score >= 60 ? review : risky }

    static let hero = Font.system(size: 56, weight: .semibold)
    static let heroUnit = Font.system(size: 26, weight: .medium)
    static let heroSmall = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let mono = Font.system(.caption, design: .monospaced)

    /// One spring for everything, so the whole app moves with the same weight.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.8)
}

extension Module {
    /// One accent for every module: the brand stays coherent instead of changing colour per page.
    var tint: (Color, Color) { (Theme.lime, Color(hex: 0xA3E635)) }
    var ink: Color { Theme.ink }
    var gradient: LinearGradient { Theme.brand }

    func wash(_ opacity: Double) -> LinearGradient {
        LinearGradient(colors: [Theme.lime.opacity(opacity), Theme.lime.opacity(opacity)], startPoint: .leading, endPoint: .trailing)
    }

    var subtitle: String {
        switch self {
        case .smartScan: return "One scan, every corner of this Mac"
        case .cleanup: return "Caches, logs, browser junk, installers and Trash"
        case .devPurge: return "Build artifacts from projects you're not touching"
        case .uninstaller: return "Remove apps completely — no traces left"
        case .spaceLens: return "See what's using your disk"
        case .processes: return "Tame CPU and memory hogs"
        case .maintenance: return "Fix what's actually broken"
        case .startup: return "What launches with your Mac"
        case .tweaks: return "Reversible tune-ups for macOS"
        case .health: return "Disk, memory, battery and security"
        case .fleet: return "Every Mac you own, at a glance"
        case .history: return "Everything Root has removed"
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// A colour that adapts to light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension View {
    /// Liquid Glass is for the navigation layer (sidebar, floating overlays), per Apple's guidance;
    /// content sits on plain grouped surfaces. On Sonoma/Sequoia this falls back to a material.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.rim.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
        }
        #else
        self.background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Theme.rim.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
        #endif
    }

    /// A grouped content surface, like a System Settings section: no border, no shadow.
    func surface(cornerRadius: CGFloat = 12) -> some View {
        self.background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Standard padded card used by every module.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).surface().reveal()
    }
}

extension Theme {
    static let rimGradient = LinearGradient(colors: [rim.opacity(0.12), rim.opacity(0.06)], startPoint: .top, endPoint: .bottom)
}
