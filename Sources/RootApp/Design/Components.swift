import SwiftUI
import RootCore

/// A metric set the way Apple sets them: the number large, its unit smaller and grey ("392 MB").
struct MetricText: View {
    var value: String
    var size: CGFloat = 56

    var body: some View {
        let parts = MetricText.split(value)
        (Text(parts.0).font(.system(size: size, weight: .semibold))
            + Text(parts.1.isEmpty ? "" : " " + parts.1).font(.system(size: size * 0.46, weight: .medium)).foregroundColor(.secondary))
            .tracking(size > 40 ? -1 : 0)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// "392 MB" → ("392", "MB"); "3 busy" → ("3", "busy"); text without a leading number stays whole.
    static func split(_ value: String) -> (String, String) {
        guard let first = value.first, first.isNumber, let space = value.firstIndex(of: " ") else { return (value, "") }
        return (String(value[..<space]), String(value[value.index(after: space)...]))
    }
}

/// Bytes as a MetricText that counts to its new value.
struct BigBytes: View {
    var bytes: Int64
    var size: CGFloat = 56
    var duration: Double = 1.0
    @State private var shown: Double = 0
    @AppStorage(reduceEffectsKey) private var reduceEffects = false

    var body: some View {
        Color.clear
            .modifier(Tween(value: shown) { MetricText(value: Format.bytes(Int64($0)), size: size) })
            .onAppear { animate() }
            .onChange(of: bytes) { animate() }
            .accessibilityLabel(Format.bytes(bytes))
    }

    private func animate() {
        if reduceEffects { shown = Double(bytes); return }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { shown = Double(bytes) }
    }
}

/// Top of a module: the big metric with its caption, and the module's actions on the right.
struct HeroHeader<Actions: View>: View {
    var title: String
    var value: String
    var caption: String
    var symbol: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                MetricText(value: value)
                    .contentTransition(.numericText())
                    .animation(Theme.spring, value: value)
                Text(caption).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions() }
                .padding(.bottom, 4)
        }
        .padding(.vertical, 8)
        .reveal()
    }
}

/// Section heading above a grouped surface.
struct SectionTitle: View {
    var title: String
    var symbol: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 13).monospacedDigit()).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 4)
    }
}

/// A titled group of rows on one surface, rows separated by inset hairlines.
struct GroupedSection<Content: View>: View {
    var title: String?
    var trailing: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionTitle(title: title, symbol: nil, trailing: trailing) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
        }
        .reveal()
    }
}

/// Hairline between rows of a GroupedSection, inset past the leading control.
struct RowDivider: View {
    var inset: CGFloat = 48
    var body: some View { Rectangle().fill(Theme.separator).frame(height: 1).padding(.leading, inset) }
}

struct Chip: View {
    var text: String
    var color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
    }
}

/// Safe is the default and needs no label; only Review and Risky are called out.
struct RiskBadge: View {
    var risk: Risk
    var body: some View {
        if risk != .safe { Chip(text: risk.rawValue.capitalized, color: Theme.color(for: risk), symbol: nil) }
    }
}

struct SudoBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.sudo)
            .help("Needs Sudo mode")
            .accessibilityLabel("Needs Sudo mode")
    }
}

struct SizeText: View {
    var bytes: Int64
    var body: some View {
        Text(Format.bytes(bytes)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }
}

struct PathText: View {
    var path: String
    var body: some View {
        Text(Paths.abbreviate(path)).font(Theme.mono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            .textSelection(.enabled)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

struct BusyOverlay: View {
    var message: String
    var progress: Double?

    var body: some View {
        HStack(spacing: 10) {
            GradientSpinner(size: 14)
            Text(message).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if let progress {
                Text("\(Int(progress * 100))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassCard(cornerRadius: 20)
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

/// Standard module scaffold: a scrolling column with consistent margins.
struct ModuleScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content() }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 80)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

/// Toast for results and errors.
struct StatusBanner: View {
    var text: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isError ? Theme.risky : Theme.accentText)
            Text(text).font(.system(size: 13, weight: .medium)).lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassCard(cornerRadius: 20)
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

/// A short informational line.
struct InfoNote: View {
    var text: String
    var symbol: String = "info.circle"

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// The module's icon tile (kept for the menu bar and receipts).
struct ModuleGlyph: View {
    var module: Module
    var size: CGFloat = 24
    var bounce: Bool = false

    var body: some View {
        Image(systemName: module.symbol)
            .font(.system(size: size * 0.6, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
