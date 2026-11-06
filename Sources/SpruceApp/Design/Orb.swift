import SwiftUI
import SpruceCore

/// Smart Scan's hero: a glass orb inside a progress ring. While scanning, specks of junk drift into
/// the orb as each place is checked; afterwards the orb holds as many specks as there's junk to
/// clean, and the ring shows the Mac's health. A clean Mac's orb is clear and bright.
struct GlassOrb: View {
    var phase: OrbPhase
    var progress: Double
    var score: Int?
    var junkBytes: Int64
    var size: CGFloat = 280
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(reduceEffectsKey) private var reduceEffects = false
    @State private var spin = false

    private var ringTarget: Double {
        switch phase {
        case .idle: return 0
        case .scanning: return max(0.02, progress)
        case .done: return Double(score ?? 0) / 100
        }
    }

    /// Specks inside the orb: a handful at rest, more as a scan finds junk, and roughly one per
    /// doubling of the junk after it.
    private var speckCount: Int {
        switch phase {
        case .idle: return 7
        case .scanning: return 8 + Int(progress * 26)
        case .done:
            guard junkBytes > 0 else { return 3 }
            let megabytes = max(1, Double(junkBytes) / 1_000_000)
            return min(40, 6 + Int(log2(megabytes) * 2.6))
        }
    }

    var body: some View {
        let ring = size * 0.026
        let still = reduceMotion || reduceEffects
        let clean = phase == .done && junkBytes == 0
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.spruce.opacity(clean ? 0.45 : 0.32), .clear],
                                     center: .center, startRadius: size * 0.3, endRadius: size * 0.66))
                .frame(width: size * 1.3, height: size * 1.3)
                .allowsHitTesting(false)
            Circle().stroke(Theme.rim.opacity(0.08), lineWidth: ring)
            Circle()
                .trim(from: 0, to: ringTarget)
                .stroke(Theme.brandAngular, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.spruce.opacity(0.6), radius: size * 0.04)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: phase == .scanning ? 0.4 : 1.2), value: ringTarget)
            if phase == .scanning && !still {
                Circle()
                    .trim(from: 0, to: 0.07)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: ring, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                    .onDisappear { spin = false }
            }
            ball(clean: clean, still: still)
                .frame(width: size * 0.8, height: size * 0.8)
            label
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .done ? "Health \(score ?? 0) out of 100" : phase == .scanning ? "Scanning, \(Int(progress * 100)) percent" : "Ready to scan")
    }

    private func ball(clean: Bool, still: Bool) -> some View {
        let count = speckCount
        let scanning = phase == .scanning
        return ZStack {
            Circle().fill(RadialGradient(
                colors: clean
                    ? [Color(hex: 0x8CF7D6).opacity(0.75), Color(hex: 0x14806A).opacity(0.6), Color(hex: 0x06261F).opacity(0.92)]
                    : [Color(hex: 0x2DD4A0).opacity(0.55), Color(hex: 0x115E59).opacity(0.5), Color(hex: 0x071C18).opacity(0.94)],
                center: UnitPoint(x: 0.5, y: 0.64), startRadius: 0, endRadius: size * 0.42))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { timeline in
                Canvas { context, canvas in
                    let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                    let radius = min(canvas.width, canvas.height) / 2
                    var glow = context
                    glow.addFilter(.blur(radius: radius * 0.035))
                    for i in 0..<count {
                        let seed = Double(i) * 12.9898
                        let base = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                        let angle = Double(i) * 2.399963 + t * (0.18 + abs(base) * 0.25) * (i.isMultiple(of: 2) ? 1 : -1)
                        var distance = 0.18 + abs(base) * 0.62
                        if scanning {
                            // Drift inwards from the rim, over and over: junk being gathered.
                            let cycle = (t * 0.22 + abs(base) * 3).truncatingRemainder(dividingBy: 1)
                            distance = 0.85 - cycle * 0.7
                        }
                        let bob = sin(t * 1.3 + seed) * 0.03
                        let point = CGPoint(x: center.x + cos(angle) * radius * distance,
                                            y: center.y + sin(angle) * radius * (distance * 0.86 + bob))
                        let r = radius * (0.018 + abs(base) * 0.018)
                        let speck = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                        let halo = Path(ellipseIn: CGRect(x: point.x - r * 2.6, y: point.y - r * 2.6, width: r * 5.2, height: r * 5.2))
                        glow.fill(halo, with: .color(Color(hex: 0x5EF0C4).opacity(0.55)))
                        context.fill(speck, with: .color(Color(hex: 0xE6FFF6).opacity(0.92)))
                    }
                }
            }
            .allowsHitTesting(false)
            // The specular highlight and the glass rim.
            Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                         center: UnitPoint(x: 0.34, y: 0.26), startRadius: 0, endRadius: size * 0.17))
            Circle().fill(RadialGradient(colors: [.clear, Theme.sky.opacity(0.22)], center: UnitPoint(x: 0.5, y: 0.35),
                                         startRadius: size * 0.2, endRadius: size * 0.42))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04), .white.opacity(0.18)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        }
        .clipShape(Circle())
        .shadow(color: Theme.spruce.opacity(0.32), radius: size * 0.1, y: size * 0.06)
    }

    @ViewBuilder private var label: some View {
        VStack(spacing: 2) {
            switch phase {
            case .idle:
                SpruceChevrons()
                    .stroke(SpruceMark.chevronFills[0], style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .shadow(color: Theme.mint.opacity(0.6), radius: 8)
            case .scanning:
                CountingText(value: progress * 100, duration: 0.3) { "\(Int($0))%" }
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
            case .done:
                CountingText(value: Double(score ?? 0), duration: 1.2) { "\(Int($0.rounded()))" }
                    .font(.system(size: size * 0.23, weight: .bold, design: .rounded))
                Text("Mac health").font(.system(size: 13, weight: .medium)).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }
}
