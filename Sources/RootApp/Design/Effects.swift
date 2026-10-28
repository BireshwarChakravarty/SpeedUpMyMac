import SwiftUI
import RootCore

// MARK: - Scan ring

enum OrbPhase: Equatable { case idle, scanning, done }

/// The Smart Scan gauge: a thin ring that shows scan progress while working and the health score after.
struct ScanRing: View {
    var phase: OrbPhase
    var progress: Double
    var score: Int?
    var size: CGFloat = 196
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width = size * 0.062
        let target: Double = {
            switch phase {
            case .idle: return 0
            case .scanning: return max(0.02, progress)
            case .done: return Double(score ?? 0) / 100
            }
        }()
        ZStack {
            Circle().stroke(Theme.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: target)
                .stroke(LinearGradient(colors: [Color(hex: 0xD9F99D), Theme.lime, Theme.leaf], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: phase == .scanning ? 0.4 : 1.2), value: target)
            if phase == .scanning && !reduceMotion {
                // A short bright arc orbiting the track, so the ring reads as working between updates.
                Circle()
                    .trim(from: 0, to: 0.08)
                    .stroke(Theme.lime.opacity(0.9), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                    .onDisappear { spin = false }
            }
            VStack(spacing: 2) {
                switch phase {
                case .idle:
                    Image(systemName: "number").font(.system(size: size * 0.2, weight: .medium)).foregroundStyle(.secondary)
                case .scanning:
                    CountingText(value: progress * 100, duration: 0.3) { "\(Int($0))%" }
                        .font(.system(size: size * 0.24, weight: .semibold))
                case .done:
                    CountingText(value: Double(score ?? 0), duration: 1.2) { "\(Int($0.rounded()))" }
                        .font(.system(size: size * 0.28, weight: .semibold))
                    Text("Health").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .done ? "Health \(score ?? 0) out of 100" : phase == .scanning ? "Scanning, \(Int(progress * 100)) percent" : "Ready to scan")
    }
}

// MARK: - Celebration

/// A short burst of lime and white sparks from the centre.
struct ConfettiBurst: View {
    struct Bit {
        var angle, speed, spin, size, delay: Double
        var color: Color
        var shape: Int
    }

    @State private var start = Date()
    @State private var bits: [Bit]

    init(seed: Int) {
        var g = SeededRandom(seed: UInt64(bitPattern: Int64(seed)))
        let palette = [Theme.lime, Color(hex: 0xD9F99D), Theme.leaf, .white]
        _bits = State(initialValue: (0..<70).map { _ in
            Bit(angle: g.next(in: 0...(2 * .pi)), speed: g.next(in: 180...520), spin: g.next(in: -6...6),
                size: g.next(in: 4...8), delay: g.next(in: 0...0.08),
                color: palette[Int(g.next(in: 0...Double(palette.count - 1)).rounded())], shape: Int(g.next(in: 0...1.99)))
        })
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.45)
                for b in bits {
                    let t = elapsed - b.delay
                    guard t > 0 else { continue }
                    let travel = b.speed * (1 - exp(-t * 2.2)) / 2.2
                    let x = origin.x + cos(b.angle) * travel
                    let y = origin.y + sin(b.angle) * travel + 120 * t * t
                    let fade = max(0, 1 - t / 1.4)
                    guard fade > 0 else { continue }
                    ctx.opacity = fade
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(b.spin * t))
                    let s = b.size
                    if b.shape == 0 {
                        c.fill(Path(ellipseIn: CGRect(x: -s / 3, y: -s / 3, width: s / 1.5, height: s / 1.5)), with: .color(b.color))
                    } else {
                        c.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 6, width: s, height: s / 3), cornerRadius: 1), with: .color(b.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(state >> 11) / Double(UInt64(1) << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// The moment after a clean: a floating panel with the amount freed counting up, then it fades.
struct CelebrationOverlay: View {
    var celebration: Celebration
    var dismiss: () -> Void
    @State private var shown = false
    @AppStorage(reduceEffectsKey) private var reduceEffects = false

    var body: some View {
        ZStack {
            if !reduceEffects { ConfettiBurst(seed: celebration.id.hashValue) }
            VStack(spacing: 8) {
                Image(systemName: celebration.symbol == "sparkles" ? "checkmark.circle.fill" : celebration.symbol)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Theme.ink, Theme.lime)
                    .symbolRenderingMode(.palette)
                    .symbolEffect(.bounce, value: shown)
                if celebration.bytes > 0 {
                    CountingBytes(bytes: shown ? celebration.bytes : 0, duration: 1.1)
                        .font(.system(size: 44, weight: .semibold))
                }
                Text(celebration.title).font(.system(size: 15, weight: .medium))
                if let detail = celebration.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 28)
            .glassCard(cornerRadius: 24)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { dismiss() }
        }
    }
}

// MARK: - Spinner

struct GradientSpinner: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.85)
            .stroke(Theme.rim.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

// MARK: - Score ring

/// A compact health ring for tiles, the sidebar footer and the menu bar.
struct ScoreRing: View {
    var score: Int
    var size: CGFloat = 120
    var caption: String = "Health"
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(reduceEffectsKey) private var reduceEffects = false

    var body: some View {
        let width = max(3, size * 0.075)
        ZStack {
            Circle().stroke(Theme.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                CountingText(value: Double(score), duration: 1.0) { "\(Int($0.rounded()))" }
                    .font(.system(size: size * 0.3, weight: .semibold))
                if size >= 80 {
                    Text(caption).font(.system(size: size * 0.1)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .onChange(of: score) { animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(score) out of 100")
    }

    private func animate() {
        if reduceMotion || reduceEffects { shown = Double(score) / 100; return }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.1)) { shown = Double(score) / 100 }
    }
}

/// A thin horizontal bar that grows in from the left.
struct GrowingBar: View {
    var fraction: Double
    var fill: LinearGradient = Theme.brand
    var delay: Double = 0
    var height: CGFloat = 6
    @State private var shown: Double = 0
    @AppStorage(reduceEffectsKey) private var reduceEffects = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(fill)
                    .frame(width: max(height, geo.size.width * shown))
            }
        }
        .frame(height: height)
        .onAppear {
            let f = min(max(fraction, 0), 1)
            if reduceEffects { shown = f; return }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8).delay(delay)) { shown = f }
        }
        .onChange(of: fraction) { _, f in withAnimation(Theme.spring) { shown = min(max(f, 0), 1) } }
    }
}
