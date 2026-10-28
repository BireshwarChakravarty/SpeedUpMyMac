import SwiftUI
import BurnishCore

/// Design tokens from docs/DESIGN.md.
enum Theme {
    static let mint = Color(red: 0.184, green: 0.831, blue: 0.710)     // #2FD4B5
    static let azure = Color(red: 0.184, green: 0.549, blue: 1.0)      // #2F8CFF
    static let violet = Color(red: 0.416, green: 0.361, blue: 1.0)     // #6A5CFF

    static let polish = LinearGradient(colors: [mint, azure, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let polishAngular = AngularGradient(colors: [mint, azure, violet, mint], center: .center)

    static let safe = Color(light: 0x16A34A, dark: 0x34D399)
    static let review = Color(light: 0xD97706, dark: 0xFBBF24)
    static let risky = Color(light: 0xDC2626, dark: 0xF87171)
    static let sudo = Color(light: 0xB45309, dark: 0xF59E0B)

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .safe: return safe
        case .review: return review
        case .risky: return risky
        }
    }

    static func scoreColor(_ score: Int) -> Color { score >= 80 ? safe : score >= 60 ? review : risky }

    static let hero = Font.system(size: 44, weight: .bold, design: .rounded)
    static let heroSmall = Font.system(size: 28, weight: .bold, design: .rounded)
    static let mono = Font.system(.caption, design: .monospaced)
}

extension Color {
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
    /// Liquid Glass on macOS 26 Tahoe; a regular material card on Sonoma/Sequoia.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Standard padded card used by every module.
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

/// The primary call to action: a capsule filled with the polish gradient.
struct PolishButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Theme.polish.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.azure.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PolishButtonStyle {
    static var polish: PolishButtonStyle { PolishButtonStyle() }
}
