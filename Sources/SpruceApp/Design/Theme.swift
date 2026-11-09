import SwiftUI
import SpruceCore

/// Design tokens (docs/DESIGN.md). A warm, calm ground (deep forest charcoal in dark mode, warm
/// paper in light) with a faint film grain, warm off-white text, and vivid section accents used
/// for labels, marks and active states. Spruce's own colour is mint on deep spruce green. The type
/// set is bundled: Geist for text and numbers, Geist Mono for labels, Cal Sans for titles.
/// The look follows Burrow's (github.com/caezium/Burrow, MIT); see NOTICE.md.
enum Theme {
    static let mint = Color(hex: 0x7DF5D0)
    static let spruce = Color(hex: 0x2DD4A0)
    static let deep = Color(hex: 0x0E9F7A)
    static let sky = Color(hex: 0x20A4F3)

    static let brand = LinearGradient(colors: [Color(hex: 0x8CF7D6), spruce], startPoint: .top, endPoint: .bottom)
    static let brandAngular = AngularGradient(colors: [mint, spruce, sky, mint], center: .center)

    static let safe = Color(light: 0x15803D, dark: 0x4ADE80)
    static let review = Color(light: 0xB45309, dark: 0xF0B24A)
    static let risky = Color(light: 0xDC2626, dark: 0xF0604E)
    static let sudo = Color(light: 0xB45309, dark: 0xF0B24A)
    static let danger = LinearGradient(colors: [Color(hex: 0xF57A68), Color(hex: 0xE0473A)], startPoint: .top, endPoint: .bottom)

    // Ground: deep forest charcoal (dark) / warm paper (light).
    static let base = Color(light: 0xF3F1EA, dark: 0x13140F)
    static let baseRaised = Color(light: 0xFBFAF6, dark: 0x1B1C16)
    /// Solid fallback for places that need an opaque surface (sheets, the menu bar panel).
    static let surface = Color(light: 0xFBFAF6, dark: 0x1D1E18)
    static let sidebar = Color(light: 0xE9E6DC, dark: 0x1A1B15)
    // Text: warm off-white (dark) / warm ink (light).
    static let text = Color(light: 0x1F1E16, dark: 0xECEAE0)
    // Lifted surfaces and lines: warm white over the ground.
    static let cardFill = Color(light: 0xFFFFFF, dark: 0xF2F0E4, lightAlpha: 0.7, darkAlpha: 0.065)
    static let cardHover = Color(light: 0xFFFFFF, dark: 0xF2F0E4, lightAlpha: 0.92, darkAlpha: 0.1)
    static let chipFill = Color(light: 0x2A2A1E, dark: 0xF2F0E4, lightAlpha: 0.07, darkAlpha: 0.08)
    static let hairline = Color(light: 0x2A2A1E, dark: 0xF2F0E4, lightAlpha: 0.12, darkAlpha: 0.1)
    static let separator = Color(light: 0x2A2A1E, dark: 0xF2F0E4, lightAlpha: 0.1, darkAlpha: 0.08)
    static let track = Color(light: 0x2A2A1E, dark: 0xF2F0E4, lightAlpha: 0.1, darkAlpha: 0.1)
    static let rim = Color(light: 0x000000, dark: 0xFFFFFF)
    /// The high-contrast call to action: warm white on dark, warm ink on paper.
    static let inverse = Color(light: 0x1F1E16, dark: 0xF6F4EA)
    static let onInverse = Color(light: 0xF6F4EA, dark: 0x13140F)
    /// Text on mint and on every section's colour.
    static let ink = Color(hex: 0x0B0D08)
    /// Spruce's colour as text: deep green in light mode, where mint would be unreadable.
    static let accentText = Color(light: 0x0B7A5E, dark: 0x7DF5D0)

    // Shape: rounded, the house signature.
    static let radiusSmall: CGFloat = 12
    static let radiusCard: CGFloat = 18
    static let radiusLarge: CGFloat = 26

    // Type: the bundled set. `.custom` falls back to the system font if a face isn't registered
    // (for example in `swift run`, outside the app bundle).
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face = weight == .semibold || weight == .bold || weight == .heavy ? "Geist-SemiBold"
            : weight == .medium ? "Geist-Medium" : "Geist-Regular"
        return .custom(face, size: size)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face = weight == .bold || weight == .heavy ? "GeistMono-Bold" : weight == .semibold ? "GeistMono-SemiBold"
            : weight == .medium ? "GeistMono-Medium" : "GeistMono-Regular"
        return .custom(face, size: size)
    }
    static func display(_ size: CGFloat) -> Font { .custom("CalSans-Regular", size: size) }

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .safe: return safe
        case .review: return review
        case .risky: return risky
        }
    }

    static func scoreColor(_ score: Int) -> Color { score >= 80 ? safe : score >= 60 ? review : risky }

    static let hero = sans(60, .semibold)
    static let heroUnit = mono(24, .medium)
    static let heroSmall = sans(28, .semibold)
    static let title = display(24)
    /// Paths and scripts.
    static let code = Font.custom("GeistMono-Regular", size: 11)

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
        case .status: return (0xA7E3A1, 0x6FB06A, 0x3E7D3A)
        case .cleanup: return (0x7DD3FC, 0x38BDF8, 0x0284C7)
        case .devPurge: return (0xA5B4FC, 0x818CF8, 0x4F46E5)
        case .installers: return (0xF2B48C, 0xD98C5F, 0xA65A30)
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
        case .status: return "Live vitals and their history"
        case .cleanup: return "Caches, logs, browser junk, installers and Trash"
        case .devPurge: return "Build artifacts from projects you're not touching"
        case .installers: return "Disk images and packages you've already used"
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

    /// A colour that adapts to light/dark appearance, each with its own opacity.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
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

    /// A content card: warm white lifted a little off the ground, with a hairline edge.
    func surface(cornerRadius: CGFloat = Theme.radiusCard) -> some View {
        modifier(Surface(cornerRadius: cornerRadius))
    }

    /// Standard padded card used by every module.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).surface().reveal()
    }
}

private struct Surface: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Theme.cardFill, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false))
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

/// The window's ground: the same calm, warm surface on every page (sections keep their colour in
/// labels and marks, not in the background), a faint light in the top corner, and film grain.
struct ModuleBackdrop: View {
    var module: Module
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.base
            LinearGradient(colors: [Color(light: 0xFBFAF4, dark: 0x1C1D16, lightAlpha: 0.5, darkAlpha: 0.55),
                                    Color(light: 0xEBE7DC, dark: 0x0C0D09, lightAlpha: 0.6, darkAlpha: 0.8)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.mint.opacity(scheme == .dark ? 0.06 : 0.08), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 620)
            Grain()
        }
        .ignoresSafeArea()
    }
}

/// Film grain: a tiled field of random light and dark specks at very low opacity.
struct Grain: View {
    var opacity: Double = 0.05

    /// Rendered once into a bitmap, then tiled.
    private static let tile: NSImage = {
        let size = 160
        var generator = SeededRandom(seed: 0x5EED)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 2, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .calibratedWhite, bytesPerRow: size * 2, bitsPerPixel: 16),
              let pixels = rep.bitmapData else { return NSImage(size: NSSize(width: 1, height: 1)) }
        for i in 0..<(size * size) {
            let speck = generator.next(in: 0...1) < 0.5
            pixels[i * 2] = generator.next(in: 0...1) < 0.5 ? 255 : 0
            pixels[i * 2 + 1] = speck ? UInt8(generator.next(in: 40...150)) : 0
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()

    var body: some View {
        Image(nsImage: Grain.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A soft sphere in a section's colour: the centrepiece of a page's empty and start states.
struct SectionSphere: View {
    var module: Module
    var size: CGFloat = 120

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: module.palette.hi), module.accent, Color(hex: module.palette.lo).opacity(0.85)],
                                 center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: size * 0.62))
            .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .frame(width: size, height: size)
            .background(Circle().fill(module.accent.opacity(0.22)).blur(radius: size * 0.3).frame(width: size * 1.5, height: size * 1.5))
            .accessibilityHidden(true)
    }
}
