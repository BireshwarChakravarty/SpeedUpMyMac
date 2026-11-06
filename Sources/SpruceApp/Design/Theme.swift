import SwiftUI
import SpruceCore

/// Design tokens (docs/DESIGN.md). Spruce's own colour is mint on deep spruce green; every section
/// has a colour of its own (Module.palette) that tints its icon, its primary button and the light
/// behind its page. Glass is for chrome (sidebar, toolbar, menu bar panel); content sits on solid
/// surfaces with a hairline highlight along the top edge.
enum Theme {
    static let mint = Color(hex: 0x7DF5D0)
    static let spruce = Color(hex: 0x2DD4A0)
    static let deep = Color(hex: 0x0E9F7A)
    static let sky = Color(hex: 0x20A4F3)

    static let brand = LinearGradient(colors: [Color(hex: 0x8CF7D6), spruce], startPoint: .top, endPoint: .bottom)
    static let brandAngular = AngularGradient(colors: [mint, spruce, sky, mint], center: .center)

    static let safe = Color(light: 0x15803D, dark: 0x4ADE80)
    static let review = Color(light: 0xB45309, dark: 0xFBBF24)
    static let risky = Color(light: 0xDC2626, dark: 0xF87171)
    static let sudo = Color(light: 0xB45309, dark: 0xF5A524)
    static let danger = LinearGradient(colors: [Color(hex: 0xFB7185), Color(hex: 0xE11D48)], startPoint: .top, endPoint: .bottom)

    /// Window background and the solid surfaces that sit on it. Neutrals lean slightly green.
    static let base = Color(light: 0xF2F5F4, dark: 0x101615)
    static let baseRaised = Color(light: 0xFFFFFF, dark: 0x19201F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x19211F)
    static let sidebar = Color(light: 0xE8EDEB, dark: 0x1A2220)
    static let separator = Color(light: 0xE2E8E6, dark: 0x29322F)
    static let track = Color(light: 0xE2E8E6, dark: 0x2A3431)
    static let rim = Color(light: 0x000000, dark: 0xFFFFFF)
    /// Text on mint and on every section's button gradient.
    static let ink = Color(hex: 0x04140F)
    /// Spruce's colour as text: deep green in light mode, where mint would be unreadable.
    static let accentText = Color(light: 0x0B7A5E, dark: 0x7DF5D0)

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .safe: return safe
        case .review: return review
        case .risky: return risky
        }
    }

    static func scoreColor(_ score: Int) -> Color { score >= 80 ? safe : score >= 60 ? review : risky }

    /// Numbers use SF Pro Rounded: friendlier, and the digits stay tabular.
    static let hero = Font.system(size: 60, weight: .bold, design: .rounded)
    static let heroUnit = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let heroSmall = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title = Font.system(size: 22, weight: .semibold)
    static let mono = Font.system(.caption, design: .monospaced)

    /// One spring for everything, so the whole app moves with the same weight.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.8)
}

// MARK: - Section colours

extension Module {
    /// Light, middle and deep shades of the section's colour.
    var palette: (hi: UInt32, mid: UInt32, lo: UInt32) {
        switch self {
        case .smartScan: return (0x8CF7D6, 0x2DD4A0, 0x0E9F7A)
        case .cleanup: return (0x7DD3FC, 0x38BDF8, 0x0284C7)
        case .devPurge: return (0xA5B4FC, 0x818CF8, 0x4F46E5)
        case .uninstaller: return (0xF9A8D4, 0xF472B6, 0xDB2777)
        case .spaceLens: return (0xD8B4FE, 0xC084FC, 0x9333EA)
        case .processes: return (0xFCD34D, 0xFBBF24, 0xD97706)
        case .maintenance: return (0xFDBA74, 0xFB923C, 0xEA580C)
        case .startup: return (0xFDE68A, 0xFCD34D, 0xCA8A04)
        case .tweaks: return (0xCBD5E1, 0x94A3B8, 0x475569)
        case .health: return (0xFCA5A5, 0xF87171, 0xDC2626)
        case .fleet: return (0x93C5FD, 0x60A5FA, 0x2563EB)
        case .history: return (0xD4D4D4, 0xA3A3A3, 0x525252)
        }
    }

    var tint: (Color, Color) { (Color(hex: palette.mid), Color(hex: palette.lo)) }
    /// The section's colour for marks, charts and selected states.
    var accent: Color { Color(hex: palette.mid) }
    /// The section's colour as text: its deep shade in light mode, its light shade in dark.
    var accentText: Color { Color(light: palette.lo, dark: palette.hi) }
    /// Icon tiles: middle to deep, top to bottom, like System Settings.
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: palette.mid), Color(hex: palette.lo)], startPoint: .top, endPoint: .bottom)
    }
    /// Primary buttons and bars: light to middle, so dark text stays readable.
    var buttonGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: palette.hi), Color(hex: palette.mid)], startPoint: .top, endPoint: .bottom)
    }
    var barGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: palette.mid), Color(hex: palette.hi)], startPoint: .leading, endPoint: .trailing)
    }
    var ink: Color { Theme.ink }

    func wash(_ opacity: Double) -> LinearGradient {
        LinearGradient(colors: [accent.opacity(opacity), accent.opacity(opacity * 0.6)], startPoint: .leading, endPoint: .trailing)
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
        case .history: return "Everything Spruce has removed"
        }
    }
}

/// The section a view belongs to: buttons, checkmarks, switches and bars take its colour.
private struct PageModuleKey: EnvironmentKey {
    static let defaultValue: Module = .smartScan
}

extension EnvironmentValues {
    var pageModule: Module {
        get { self[PageModuleKey.self] }
        set { self[PageModuleKey.self] = newValue }
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

// MARK: - Surfaces

extension View {
    /// Liquid Glass is for the navigation layer (sidebar, floating overlays), per Apple's guidance;
    /// content sits on solid surfaces. On Sonoma/Sequoia this falls back to a material.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 1).allowsHitTesting(false))
        }
        #else
        self.background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 1).allowsHitTesting(false))
        #endif
    }

    /// A solid content surface: a hairline highlight along the top edge in dark mode, a soft
    /// shadow in light mode.
    func surface(cornerRadius: CGFloat = 16) -> some View {
        modifier(Surface(cornerRadius: cornerRadius))
    }

    /// Standard padded card used by every module.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).surface().reveal()
    }
}

private struct Surface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Theme.surface.opacity(scheme == .dark ? 0.86 : 1), in: shape)
            .overlay(shape.strokeBorder(Theme.rimGradient, lineWidth: 1).allowsHitTesting(false))
            .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.06), radius: scheme == .dark ? 10 : 8, y: 3)
    }
}

extension Theme {
    /// Lit from above: brighter along the top edge than the bottom.
    static let rimGradient = LinearGradient(colors: [rim.opacity(0.13), rim.opacity(0.04), rim.opacity(0.06)],
                                            startPoint: .top, endPoint: .bottom)
}

// MARK: - Section icon tile

/// A section's symbol, white on its colour, in a rounded tile with a glass top edge.
struct IconTile: View {
    var module: Module
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(module.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .center),
                                  lineWidth: max(0.5, size / 40)))
            .overlay(
                Image(systemName: module.symbol)
                    .font(.system(size: size * 0.54, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5))
            .frame(width: size, height: size)
            .shadow(color: module.accent.opacity(size > 30 ? 0.45 : 0.25), radius: size > 30 ? 12 : 3, y: size > 30 ? 6 : 1)
    }
}

/// The light behind each page, in its section's colour, cross-fading as you move between sections.
struct ModuleBackdrop: View {
    var module: Module
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 1.0 : 0.6
        ZStack {
            Theme.base
            ZStack {
                RadialGradient(colors: [module.accent.opacity(0.22 * strength), .clear],
                               center: UnitPoint(x: 0.45, y: 0.08), startRadius: 0, endRadius: 640)
                RadialGradient(colors: [Color(hex: module.palette.lo).opacity(0.12 * strength), .clear],
                               center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 560)
            }
            .id(module)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.45), value: module)
        .ignoresSafeArea()
    }
}
