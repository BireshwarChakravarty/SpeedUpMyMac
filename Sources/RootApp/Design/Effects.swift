import SwiftUI
import RootCore

// MARK: - Aurora background

/// The window's backdrop: a slowly drifting aurora tinted by the current module, over a night sky
/// with a little star dust. Mesh gradient on macOS 15+, soft drifting blobs on Sonoma.
struct AuroraBackground: View {
    var module: Module
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(reduceEffectsKey) private var reduceEffects = false

    var body: some View {
        ZStack {
            Theme.base
            ZStack {
                ForEach([module], id: \.self) { m in
                    AuroraLayer(tint: m.tint, animated: !(reduceMotion || reduceEffects))
                        .transition(.opacity)
                }
            }
            .opacity((colorScheme == .dark ? 0.85 : 0.45) * intensity)
            .animation(.easeInOut(duration: 1.1), value: module)
            if !(reduceMotion || reduceEffects) && colorScheme == .dark {
                StarDust().opacity(0.55)
            }
            // Vignette: keeps the edges calm so the content sits in the light.
            RadialGradient(colors: [.clear, Theme.base.opacity(0.65)], center: .center, startRadius: 200, endRadius: 1100)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct AuroraLayer: View {
    var tint: (Color, Color)
    var animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                content(t: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            content(t: 0)
        }
    }

    @ViewBuilder
    private func content(t: Double) -> some View {
        if #available(macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: meshPoints(t), colors: meshColors)
                .blur(radius: 30)
        } else {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    blob(tint.0, size: w * 0.7).offset(x: -w * 0.25 + sin(t * 0.11) * w * 0.08, y: -h * 0.3 + cos(t * 0.13) * h * 0.06)
                    blob(tint.1, size: w * 0.6).offset(x: w * 0.3 + cos(t * 0.09) * w * 0.07, y: h * 0.25 + sin(t * 0.12) * h * 0.08)
                    blob(Theme.emerald, size: w * 0.45).offset(x: w * 0.05 + sin(t * 0.07) * w * 0.1, y: -h * 0.05).opacity(0.6)
                }
                .frame(width: w, height: h)
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color.opacity(0.55)).frame(width: size, height: size).blur(radius: size * 0.22)
    }

    private var meshColors: [Color] {
        let night = Color(hex: 0x060907, opacity: 0)
        return [
            tint.0.opacity(0.75), night, tint.1.opacity(0.45),
            night, tint.1.opacity(0.35), night,
            Theme.emerald.opacity(0.4), tint.0.opacity(0.3), night,
        ]
    }

    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func wobble(_ base: Double, _ speed: Double, _ amp: Double) -> Float { Float(base + sin(t * speed) * amp) }
        return [
            [0, 0], [wobble(0.5, 0.21, 0.12), 0], [1, 0],
            [0, wobble(0.5, 0.17, 0.12)], [wobble(0.5, 0.13, 0.18), wobble(0.5, 0.19, 0.16)], [1, wobble(0.5, 0.23, 0.12)],
            [0, 1], [wobble(0.5, 0.15, 0.14), 1], [1, 1],
        ]
    }
}

/// Faint twinkling points of light.
private struct StarDust: View {
    private struct Star { var x, y, size, phase, speed: Double }
    private let stars: [Star] = {
        var rng = SystemRandomNumberGenerator()
        return (0..<70).map { _ in
            Star(x: .random(in: 0...1, using: &rng), y: .random(in: 0...1, using: &rng), size: .random(in: 0.6...1.8, using: &rng),
                 phase: .random(in: 0...(2 * .pi), using: &rng), speed: .random(in: 0.4...1.4, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for s in stars {
                    let twinkle = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * s.speed + s.phase))
                    let rect = CGRect(x: s.x * size.width, y: (s.y + t * 0.002 * s.speed).truncatingRemainder(dividingBy: 1) * size.height,
                                      width: s.size, height: s.size)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle * 0.6)))
                }
            }
        }
    }
}

// MARK: - Scan orb

enum OrbPhase: Equatable { case idle, scanning, done }

/// The Smart Scan centrepiece: a glossy sphere in a spinning gradient ring, with orbiting sparks,
/// ripples while it works and a breathing glow when it's ready.
struct ScanOrb<Center: View>: View {
    var phase: OrbPhase
    var progress: Double
    var size: CGFloat = 230
    var action: () -> Void
    @ViewBuilder var label: () -> Center
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                glow(t)
                if phase == .scanning { ripples(t) }
                ring(t)
                if phase == .scanning { progressArc }
                sphere
                sparks(t)
                label()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size * 1.45, height: size * 1.45)
        .scaleEffect(pressed ? 0.95 : (hovering && phase != .scanning ? 1.035 : 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        .contentShape(Circle().inset(by: size * 0.2))
        .onHover { hovering = $0 }
        .onTapGesture {
            guard phase != .scanning else { return }
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var spin: Double { phase == .scanning ? 1.6 : 0.25 }

    private func glow(_ t: Double) -> some View {
        let breathe = 0.5 + 0.5 * sin(t * (phase == .scanning ? 4 : 1.4))
        return Circle()
            .fill(Theme.brandAngular)
            .rotationEffect(.radians(t * spin))
            .frame(width: size * 1.05, height: size * 1.05)
            .blur(radius: size * 0.2)
            .opacity((hovering ? 0.75 : 0.5) + 0.2 * breathe)
            .scaleEffect(1 + 0.04 * breathe)
    }

    private func ripples(_ t: Double) -> some View {
        ZStack {
            ForEach(0..<3) { i in
                let p = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle()
                    .strokeBorder(Theme.brand, lineWidth: 2)
                    .frame(width: size, height: size)
                    .scaleEffect(1 + p * 0.45)
                    .opacity((1 - p) * 0.6)
            }
        }
    }

    private func ring(_ t: Double) -> some View {
        Circle()
            .strokeBorder(AngularGradient(colors: [Theme.lime, Theme.leaf, Theme.emerald, Theme.lime.opacity(0.2), Theme.lime],
                                          center: .center), lineWidth: size * 0.035)
            .rotationEffect(.radians(t * spin * 1.4))
            .frame(width: size, height: size)
            .shadow(color: Theme.leaf.opacity(0.6), radius: 10)
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: max(0.02, progress))
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.012, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: size * 1.1, height: size * 1.1)
            .shadow(color: .white.opacity(0.8), radius: 4)
            .animation(.easeOut(duration: 0.3), value: progress)
    }

    private var sphere: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x4D7C0F), Color(hex: 0x16260F), Color(hex: 0x050805)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.55))
            Circle().fill(RadialGradient(colors: [Theme.lime.opacity(0.55), .clear], center: UnitPoint(x: 0.7, y: 0.85),
                                         startRadius: 0, endRadius: size * 0.45))
            // Specular highlight.
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.55, height: size * 0.3)
                .offset(y: -size * 0.24)
                .blur(radius: 2)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .frame(width: size * 0.9, height: size * 0.9)
        .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
    }

    private func sparks(_ t: Double) -> some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let count = phase == .scanning ? 14 : 8
            ctx.addFilter(.blur(radius: 0.6))
            for i in 0..<count {
                let k = Double(i)
                let radius = size * (0.56 + 0.07 * sin(k * 1.7))
                let speed = (phase == .scanning ? 1.4 : 0.35) * (0.6 + 0.4 * sin(k * 2.3))
                let angle = t * speed + k * (2 * .pi / Double(count))
                let tilt = 0.38 + 0.1 * sin(k)
                let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius * tilt)
                let front = sin(angle) > 0
                let r = (front ? 2.6 : 1.6) * (0.7 + 0.3 * sin(t * 3 + k))
                ctx.opacity = front ? 0.95 : 0.4
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(i.isMultiple(of: 2) ? Theme.lime : .white))
            }
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .allowsHitTesting(false)
    }
}

// MARK: - Celebration

/// A burst of gradient confetti and sparkles from the centre, with gravity and spin.
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
        let palette = [Theme.lime, Theme.leaf, Theme.emerald, Color(hex: 0x22D3EE), Color(hex: 0xFBBF24), .white]
        _bits = State(initialValue: (0..<140).map { _ in
            Bit(angle: g.next(in: 0...(2 * .pi)), speed: g.next(in: 260...820), spin: g.next(in: -9...9),
                size: g.next(in: 5...12), delay: g.next(in: 0...0.12),
                color: palette[Int(g.next(in: 0...Double(palette.count - 1)).rounded())], shape: Int(g.next(in: 0...2.99)))
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
                    let drag = exp(-t * 1.6)
                    let travel = b.speed * (1 - drag) / 1.6
                    let x = origin.x + cos(b.angle) * travel
                    let y = origin.y + sin(b.angle) * travel + 260 * t * t
                    let fade = max(0, 1 - t / 2.4)
                    guard fade > 0 else { continue }
                    ctx.opacity = fade
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(b.spin * t))
                    let s = b.size
                    switch b.shape {
                    case 0: c.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2), cornerRadius: 1.5), with: .color(b.color))
                    case 1: c.fill(Path(ellipseIn: CGRect(x: -s / 3, y: -s / 3, width: s / 1.5, height: s / 1.5)), with: .color(b.color))
                    default: c.fill(sparkle(s), with: .color(b.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func sparkle(_ s: Double) -> Path {
        var p = Path()
        let r = s * 0.75, w = s * 0.16
        p.move(to: CGPoint(x: 0, y: -r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: w, y: -w))
        p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: w, y: w))
        p.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -w, y: w))
        p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -w, y: -w))
        return p
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

/// Full-window moment after a clean: confetti, the amount freed counting up, then it fades away.
struct CelebrationOverlay: View {
    var celebration: Celebration
    var dismiss: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.25 : 0).ignoresSafeArea()
            ConfettiBurst(seed: celebration.id.hashValue)
            VStack(spacing: 10) {
                Image(systemName: celebration.symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .symbolEffect(.bounce, value: shown)
                    .shadow(color: Theme.leaf.opacity(0.7), radius: 18)
                if celebration.bytes > 0 {
                    CountingBytes(bytes: shown ? celebration.bytes : 0, duration: 1.4)
                        .font(.system(size: 64, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: Theme.emerald.opacity(0.8), radius: 24)
                }
                Text(celebration.title).font(.system(.title2, design: .monospaced).weight(.semibold)).foregroundStyle(.white)
                if let detail = celebration.detail {
                    Text(detail).font(.callout).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 44).padding(.vertical, 30)
            .glassCard(cornerRadius: 32)
            .scaleEffect(shown ? 1 : 0.7)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { dismiss() }
        }
    }
}

// MARK: - Spinner

/// A gradient comet chasing its tail.
struct GradientSpinner: View {
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2.5
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 1)
            .stroke(AngularGradient(colors: [Theme.lime.opacity(0), Theme.lime, Theme.leaf, Theme.emerald], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

// MARK: - Score ring

/// Health ring: gradient arc with a glowing head, and the score counting up.
struct ScoreRing: View {
    var score: Int
    var size: CGFloat = 120
    var caption: String = "health"
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width = size * 0.085
        ZStack {
            Circle().stroke(Theme.rim.opacity(0.08), lineWidth: width)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [Theme.lime, Theme.leaf, Theme.emerald, Theme.lime], center: .center),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.leaf.opacity(0.6), radius: size * 0.06)
            Color.clear.modifier(Tween(value: shown) { p in
                Circle()
                    .fill(.white)
                    .frame(width: width * 0.7, height: width * 0.7)
                    .shadow(color: .white, radius: 4)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * p))
                    .opacity(p > 0.01 ? 1 : 0)
            })
            VStack(spacing: 0) {
                CountingText(value: Double(score), duration: 1.2) { "\(Int($0.rounded()))" }
                    .font(.system(size: size * 0.3, weight: .bold, design: .monospaced))
                if size >= 80 {
                    Text(caption).font(.system(size: size * 0.095, weight: .medium)).foregroundStyle(.secondary)
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
        if reduceMotion { shown = Double(score) / 100; return }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.3)) { shown = Double(score) / 100 }
    }
}

/// A horizontal bar that grows in from the left.
struct GrowingBar: View {
    var fraction: Double
    var fill: LinearGradient = Theme.brand
    var delay: Double = 0
    var height: CGFloat = 8
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rim.opacity(0.07))
                Capsule().fill(fill)
                    .frame(width: max(height, geo.size.width * shown))
                    .shadow(color: Theme.leaf.opacity(0.45), radius: 4)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(delay)) { shown = min(max(fraction, 0), 1) } }
        .onChange(of: fraction) { _, f in withAnimation(Theme.spring) { shown = min(max(f, 0), 1) } }
    }
}
