import SwiftUI
import RootCore

/// "Reduce visual effects" in Settings, on top of the system's Reduce Motion.
let reduceEffectsKey = "reduceEffects"

// MARK: - Entrance

/// Rises, sharpens and fades in the first time the view appears.
struct Reveal: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(reduceEffectsKey) private var reduceEffects = false

    func body(content: Content) -> some View {
        let still = reduceMotion || reduceEffects
        content
            .opacity(shown || still ? 1 : 0)
            .offset(y: shown || still ? 0 : 16)
            .scaleEffect(shown || still ? 1 : 0.985, anchor: .top)
            .blur(radius: shown || still ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func reveal(delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }

    /// Staggered entrance for the n-th item of a list.
    func reveal(index: Int, step: Double = 0.035) -> some View { modifier(Reveal(delay: min(Double(index) * step, 0.5))) }
}

/// Blur in/out, for module switches and overlays.
struct BlurTransition: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    static var moduleSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 18)).combined(with: .scale(scale: 0.985))
                .combined(with: .modifier(active: BlurTransition(radius: 14), identity: BlurTransition(radius: 0))),
            removal: .opacity.combined(with: .modifier(active: BlurTransition(radius: 10), identity: BlurTransition(radius: 0))))
    }

    static var toast: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - Hover

/// Lifts a tile toward the pointer: a little scale, a deeper shadow and a brighter rim.
struct HoverLift: ViewModifier {
    var scale: CGFloat
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .shadow(color: .black.opacity(hovering ? 0.28 : 0), radius: hovering ? 22 : 0, y: hovering ? 12 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.brand, lineWidth: 1)
                    .opacity(hovering ? 0.55 : 0)
                    .allowsHitTesting(false))
            .animation(Theme.snappy, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(scale: CGFloat = 1.015, cornerRadius: CGFloat = 20) -> some View {
        modifier(HoverLift(scale: scale, cornerRadius: cornerRadius))
    }

    /// A soft row highlight on hover, for list rows inside cards.
    func rowHover(cornerRadius: CGFloat = 10) -> some View { modifier(RowHover(cornerRadius: cornerRadius)) }
}

struct RowHover: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.rim.opacity(hovering ? 0.06 : 0)))
            .padding(.horizontal, -8)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Shimmer

/// A band of light that sweeps across the view every few seconds.
struct Shimmer: ViewModifier {
    var active: Bool
    var period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45)
                            .rotationEffect(.degrees(18))
                            .offset(x: -geo.size.width * 0.6 + CGFloat(min(t * 1.8, 1)) * geo.size.width * 1.7)
                            .blendMode(.plusLighter)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true, period: Double = 3.2) -> some View { modifier(Shimmer(active: active, period: period)) }
}

// MARK: - Tweening

/// Re-renders `build` with every intermediate value while `value` animates.
struct Tween<V: View>: ViewModifier, Animatable {
    var value: Double
    var build: (Double) -> V

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View { build(value) }
}

/// A number that counts up (or down) to its new value instead of jumping.
struct CountingText: View {
    var value: Double
    var duration: Double = 1.1
    var format: (Double) -> String
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .modifier(Tween(value: shown) { Text(format($0)).monospacedDigit() })
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, new in animate(to: new) }
            .accessibilityLabel(format(value))
    }

    private func animate(to target: Double) {
        if reduceMotion { shown = target; return }
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { shown = target }
    }
}

struct CountingBytes: View {
    var bytes: Int64
    var duration: Double = 1.1
    var body: some View { CountingText(value: Double(bytes), duration: duration) { Format.bytes(Int64($0)) } }
}

// MARK: - Press feedback

/// Squash on press, with a tap sound and a haptic.
struct PressFeedback: ViewModifier {
    var isPressed: Bool
    var sound: SoundFX.Effect?

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(Theme.snappy, value: isPressed)
            .onChange(of: isPressed) { _, pressed in
                if pressed, let sound { SoundFX.shared.play(sound, haptic: .generic) }
            }
    }
}
