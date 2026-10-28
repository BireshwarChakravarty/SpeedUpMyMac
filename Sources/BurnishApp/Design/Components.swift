import SwiftUI
import BurnishCore

/// Top-of-module header: big rounded metric, caption, and the module's primary action.
struct HeroHeader<Actions: View>: View {
    var title: String
    var value: String
    var caption: String
    var symbol: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.polish)
                .frame(width: 56, height: 56)
                .glassCard(cornerRadius: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Text(value).font(Theme.hero).contentTransition(.numericText())
                Text(caption).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .card(padding: 22)
    }
}

/// Animated health ring.
struct ScoreRing: View {
    var score: Int
    var size: CGFloat = 120
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Theme.polishAngular, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                Text("health").font(.system(size: size * 0.1)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .onChange(of: score) { animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(score) out of 100")
    }

    private func animate() {
        if reduceMotion { shown = Double(score) / 100; return }
        shown = 0
        withAnimation(.easeOut(duration: 1.1)) { shown = Double(score) / 100 }
    }
}

struct RiskBadge: View {
    var risk: Risk
    var body: some View {
        Text(risk.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(Theme.color(for: risk))
            .background(Theme.color(for: risk).opacity(0.14), in: Capsule())
    }
}

struct SudoBadge: View {
    var body: some View {
        Label("sudo", systemImage: "lock.shield")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(Theme.sudo)
            .background(Theme.sudo.opacity(0.14), in: Capsule())
    }
}

struct SizeText: View {
    var bytes: Int64
    var body: some View {
        Text(Format.bytes(bytes)).font(.body.monospacedDigit()).foregroundStyle(.secondary)
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

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(Theme.polish)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

struct BusyOverlay: View {
    var message: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassCard(cornerRadius: 14)
    }
}

/// Standard module scaffold: scrolling column of cards with consistent spacing.
struct ModuleScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(22)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Small banner for results and errors.
struct StatusBanner: View {
    var text: String
    var isError: Bool = false

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "sparkles")
            .font(.callout)
            .foregroundStyle(isError ? Theme.risky : Theme.safe)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassCard(cornerRadius: 12)
    }
}
