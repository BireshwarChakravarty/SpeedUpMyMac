import SwiftUI
import BurnishCore

/// The module's icon on a gradient tile, like System Settings but lit from within.
struct ModuleGlyph: View {
    var module: Module
    var size: CGFloat = 24
    var bounce: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(module.gradient)
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
            Image(systemName: module.symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: bounce)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: module.tint.1.opacity(0.45), radius: size * 0.18, y: size * 0.06)
    }
}

/// Top-of-module header: glyph, big metric, caption, and the module's primary action.
struct HeroHeader<Actions: View>: View {
    @Environment(AppModel.self) private var model
    var title: String
    var value: String
    var caption: String
    var symbol: String
    @ViewBuilder var actions: () -> Actions
    @State private var appeared = false

    var body: some View {
        let module = model.selection ?? .smartScan
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                Circle().fill(module.gradient).blur(radius: 22).opacity(0.55).frame(width: 70, height: 70)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(module.gradient))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: module.tint.1.opacity(0.5), radius: 12, y: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                Text(value)
                    .font(Theme.hero)
                    .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                    .animation(Theme.spring, value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            actions()
        }
        .card(padding: 22)
        .onAppear { appeared.toggle() }
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.polish)
            }
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            if let trailing { Text(trailing).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }
}

struct Chip: View {
    var text: String
    var color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

struct RiskBadge: View {
    var risk: Risk
    var body: some View { Chip(text: risk.rawValue.capitalized, color: Theme.color(for: risk), symbol: nil) }
}

struct SudoBadge: View {
    var body: some View { Chip(text: "sudo", color: Theme.sudo, symbol: "lock.fill") }
}

struct SizeText: View {
    var bytes: Int64
    var body: some View {
        Text(Format.bytes(bytes)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }
}

struct PathText: View {
    var path: String
    var body: some View {
        Text(Paths.abbreviate(path)).font(Theme.mono).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            .textSelection(.enabled)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    @State private var float = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.polish).blur(radius: 26).opacity(0.45).frame(width: 80, height: 80)
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Theme.polish)
                    .offset(y: float ? -4 : 4)
            }
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: float)
            Text(title).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .onAppear { float = true }
    }
}

struct BusyOverlay: View {
    var message: String
    var progress: Double?

    var body: some View {
        HStack(spacing: 12) {
            GradientSpinner(size: 18)
            Text(message).font(.callout.weight(.medium)).lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: message)
            if let progress {
                Text("\(Int(progress * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .glassCard(cornerRadius: 18)
        .shimmer(true, period: 2.4)
    }
}

/// Standard module scaffold: scrolling column of cards with consistent spacing.
struct ModuleScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(.horizontal, 26)
                .padding(.top, 6)
                .padding(.bottom, 90)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

/// Small toast for results and errors.
struct StatusBanner: View {
    var text: String
    var isError: Bool = false
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isError ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.polish)))
                .symbolEffect(.bounce, value: bounce)
            Text(text).font(.callout.weight(.medium)).lineLimit(2)
        }
        .padding(.leading, 8).padding(.trailing, 18).padding(.vertical, 8)
        .glassCard(cornerRadius: 22)
        .onAppear { bounce.toggle() }
    }
}

/// A short informational line with an icon.
struct InfoNote: View {
    var text: String
    var symbol: String = "info.circle"

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.polish)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .reveal()
    }
}
