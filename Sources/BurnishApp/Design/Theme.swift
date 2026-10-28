import SwiftUI
import BurnishCore

/// Design tokens from docs/DESIGN.md.
enum Theme {
    static let mint = Color(hex: 0x2FD4B5)
    static let azure = Color(hex: 0x2F8CFF)
    static let violet = Color(hex: 0x6A5CFF)

    static let polish = LinearGradient(colors: [mint, azure, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let polishAngular = AngularGradient(colors: [mint, azure, violet, mint], center: .center)

    static let safe = Color(light: 0x16A34A, dark: 0x34D399)
    static let review = Color(light: 0xD97706, dark: 0xFBBF24)
    static let risky = Color(light: 0xDC2626, dark: 0xF87171)
    static let sudo = Color(light: 0xB45309, dark: 0xF59E0B)
    static let sudoGradient = LinearGradient(colors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let danger = LinearGradient(colors: [Color(hex: 0xFB7185), Color(hex: 0xE11D48)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The window's night sky, under the aurora.
    static let base = Color(light: 0xEEF2FA, dark: 0x070A14)
    static let baseRaised = Color(light: 0xF8FAFF, dark: 0x0E1326)
    static let rim = Color(light: 0x000000, dark: 0xFFFFFF)

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .safe: return safe
        case .review: return review
        case .risky: return risky
        }
    }

    static func scoreColor(_ score: Int) -> Color { score >= 80 ? safe : score >= 60 ? review : risky }

    static let hero = Font.system(size: 46, weight: .bold, design: .rounded)
    static let heroSmall = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title = Font.system(size: 26, weight: .bold, design: .rounded)
    static let mono = Font.system(.caption, design: .monospaced)

    /// One spring for everything, so the whole app moves with the same weight.
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.75)
}

extension Module {
    /// Each module's two-colour accent: sidebar tile, aurora tint, hero glyph.
    var tint: (Color, Color) {
        switch self {
        case .smartScan: return (Color(hex: 0x2FD4B5), Color(hex: 0x6A5CFF))
        case .cleanup: return (Color(hex: 0x22D3EE), Color(hex: 0x2F8CFF))
        case .devPurge: return (Color(hex: 0xF472B6), Color(hex: 0xA855F7))
        case .uninstaller: return (Color(hex: 0xFB7185), Color(hex: 0xF97316))
        case .spaceLens: return (Color(hex: 0x818CF8), Color(hex: 0xC084FC))
        case .processes: return (Color(hex: 0x34D399), Color(hex: 0x22D3EE))
        case .maintenance: return (Color(hex: 0x2DD4BF), Color(hex: 0x3B82F6))
        case .startup: return (Color(hex: 0xFBBF24), Color(hex: 0xF97316))
        case .tweaks: return (Color(hex: 0xA78BFA), Color(hex: 0xEC4899))
        case .health: return (Color(hex: 0x4ADE80), Color(hex: 0x2FD4B5))
        case .fleet: return (Color(hex: 0x60A5FA), Color(hex: 0x6A5CFF))
        case .history: return (Color(hex: 0x94A3B8), Color(hex: 0x818CF8))
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint.0, tint.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The accent at low strength, for selected-row fills.
    func wash(_ opacity: Double) -> LinearGradient {
        LinearGradient(colors: [tint.0.opacity(opacity), tint.1.opacity(opacity)], startPoint: .leading, endPoint: .trailing)
    }

    var subtitle: String {
        switch self {
        case .smartScan: return "One scan, every corner of this Mac"
        case .cleanup: return "Caches, logs, browser junk, installers and Trash"
        case .devPurge: return "Build artifacts from projects you're not touching"
        case .uninstaller: return "Remove apps completely — no traces left"
        case .spaceLens: return "See what's eating your disk"
        case .processes: return "Tame CPU and memory hogs"
        case .maintenance: return "Fix what's actually broken"
        case .startup: return "What launches with your Mac"
        case .tweaks: return "Reversible tune-ups for macOS"
        case .health: return "Disk, memory, battery and security"
        case .fleet: return "Every Mac you own, at a glance"
        case .history: return "Everything Burnish has removed"
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
    /// Liquid Glass on macOS 26 Tahoe; a frosted material with a lit rim on Sonoma/Sequoia.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
                .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 0.75).allowsHitTesting(false))
        } else {
            self.frostedCard(shape)
        }
        #else
        self.frostedCard(shape)
        #endif
    }

    fileprivate func frostedCard(_ shape: RoundedRectangle) -> some View {
        self.background(.ultraThinMaterial, in: shape)
            .background(Theme.baseRaised.opacity(0.35), in: shape)
            .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 1).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    /// Standard padded card used by every module. Cards rise into place the first time they appear.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).glassCard().reveal()
    }
}

extension Theme {
    /// Light catching the top edge of a pane of glass.
    static let rimGradient = LinearGradient(colors: [rim.opacity(0.28), rim.opacity(0.06), rim.opacity(0.02), rim.opacity(0.12)],
                                            startPoint: .top, endPoint: .bottom)
}
