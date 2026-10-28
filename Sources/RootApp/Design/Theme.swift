import SwiftUI
import RootCore

/// Design tokens from docs/DESIGN.md.
enum Theme {
    // Root: a lit terminal. Lime on near-black, with a little emerald for depth.
    static let lime = Color(hex: 0xBEF264)
    static let leaf = Color(hex: 0x84CC16)
    static let emerald = Color(hex: 0x10B981)

    static let brand = LinearGradient(colors: [lime, leaf, emerald], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brandAngular = AngularGradient(colors: [lime, leaf, emerald, Color(hex: 0x34D399), lime], center: .center)

    static let safe = Color(light: 0x16A34A, dark: 0x34D399)
    static let review = Color(light: 0xD97706, dark: 0xFBBF24)
    static let risky = Color(light: 0xDC2626, dark: 0xF87171)
    static let sudo = Color(light: 0xB45309, dark: 0xF59E0B)
    static let sudoGradient = LinearGradient(colors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let danger = LinearGradient(colors: [Color(hex: 0xFB7185), Color(hex: 0xE11D48)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The window's night sky, under the aurora.
    static let base = Color(light: 0xF1F5EE, dark: 0x060907)
    static let baseRaised = Color(light: 0xFAFCF8, dark: 0x0E140F)
    static let rim = Color(light: 0x000000, dark: 0xFFFFFF)
    /// Text on lime: the near-black of the terminal.
    static let ink = Color(hex: 0x0A0F0A)

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .safe: return safe
        case .review: return review
        case .risky: return risky
        }
    }

    static func scoreColor(_ score: Int) -> Color { score >= 80 ? safe : score >= 60 ? review : risky }

    static let hero = Font.system(size: 44, weight: .heavy, design: .monospaced)
    static let heroSmall = Font.system(size: 27, weight: .heavy, design: .monospaced)
    static let title = Font.system(size: 24, weight: .heavy, design: .monospaced)
    static let mono = Font.system(.caption, design: .monospaced)

    /// One spring for everything, so the whole app moves with the same weight.
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.75)
}

extension Module {
    /// Each module's two-colour accent: sidebar tile, aurora tint, hero glyph.
    var tint: (Color, Color) {
        switch self {
        case .smartScan: return (Color(hex: 0xBEF264), Color(hex: 0x10B981))
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

    /// Glyph colour on the module's tile: dark on the bright lime tile, white elsewhere.
    var ink: Color { self == .smartScan ? Theme.ink : .white }

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
