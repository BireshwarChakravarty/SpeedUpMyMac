import AppKit
import AVFoundation

/// Burnish's sound effects, synthesized at launch: no audio files to ship, and every sound shares one
/// palette (glassy bells in C major, soft filtered-noise whooshes). Haptics ride along on Force Touch trackpads.
@MainActor
final class SoundFX {
    static let shared = SoundFX()

    enum Effect: CaseIterable {
        case tick, tap, select, toggleOn, toggleOff, check, uncheck, unlock, lock
        case whoosh, scanStart, scanDone, clean, success, error, vanish
    }

    static let enabledKey = "soundEffects"
    static let volumeKey = "soundVolume"

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var lastTick = Date.distantPast
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var prepared = false

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var volume: Float { Float(UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 0.55) }

    func play(_ effect: Effect, haptic: NSHapticFeedbackManager.FeedbackPattern? = nil) {
        if let haptic { NSHapticFeedbackManager.defaultPerformer.perform(haptic, performanceTime: .now) }
        guard enabled else { return }
        if effect == .tick {
            // Scan ticks arrive in bursts; keep them a soft patter, not a buzz.
            guard Date().timeIntervalSince(lastTick) > 0.07 else { return }
            lastTick = Date()
        }
        prepare()
        guard let buffer = buffers[effect], !players.isEmpty else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.volume = volume
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.9
        for effect in Effect.allCases { buffers[effect] = Synth.render(effect, format: format) }
        try? engine.start()
    }
}

/// Tiny additive/subtractive synth. Everything is rendered once into stereo buffers.
private enum Synth {
    static let rate = 44_100.0

    // C major, the Burnish key.
    static let c5 = 523.25, e5 = 659.25, g5 = 783.99, a5 = 880.0
    static let c6 = 1046.5, d6 = 1174.66, e6 = 1318.51, g6 = 1567.98, a6 = 1760.0, c7 = 2093.0, e7 = 2637.02

    struct Voice {
        var start: Double
        var render: (Double) -> Double   // local time → sample
        var length: Double
        var pan: Double = 0               // -1 left … 1 right
    }

    static func render(_ effect: SoundFX.Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (voices, gain) = design(effect)
        let duration = voices.map { $0.start + $0.length }.max() ?? 0.1
        let frames = AVAudioFrameCount(duration * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        let left = channels[0], right = channels[1]
        for i in 0..<Int(frames) { left[i] = 0; right[i] = 0 }
        for voice in voices {
            let first = Int(voice.start * rate), count = Int(voice.length * rate)
            let lg = Float(cos((voice.pan + 1) * .pi / 4)), rg = Float(sin((voice.pan + 1) * .pi / 4))
            for n in 0..<count where first + n < Int(frames) {
                let s = Float(voice.render(Double(n) / rate))
                left[first + n] += s * lg
                right[first + n] += s * rg
            }
        }
        // Soft clip and fade the last few ms so nothing clicks.
        let fade = min(Int(0.004 * rate), Int(frames))
        for i in 0..<Int(frames) {
            let tail = i >= Int(frames) - fade ? Float(Int(frames) - i) / Float(fade) : 1
            left[i] = tanhf(left[i] * gain) * tail
            right[i] = tanhf(right[i] * gain) * tail
        }
        return buffer
    }

    // MARK: Building blocks

    static func env(_ t: Double, attack: Double, decay: Double) -> Double {
        t < attack ? t / attack : exp(-(t - attack) / decay)
    }

    /// Glassy bell: inharmonic partials with faster-decaying overtones.
    static func bell(_ f: Double, at start: Double, decay: Double = 0.45, amp: Double = 0.3, pan: Double = 0) -> Voice {
        let partials: [(Double, Double, Double)] = [(1, 1, 1), (2.0, 0.42, 0.55), (2.76, 0.22, 0.35), (5.4, 0.08, 0.18)]
        return Voice(start: start, render: { t in
            var s = 0.0
            for (ratio, a, d) in partials { s += a * sin(2 * .pi * f * ratio * t) * env(t, attack: 0.002, decay: decay * d) }
            return amp * s
        }, length: decay * 5, pan: pan)
    }

    /// Short sine blip with an optional pitch glide.
    static func blip(_ f0: Double, to f1: Double? = nil, at start: Double, length: Double = 0.06, amp: Double = 0.3, pan: Double = 0) -> Voice {
        let f1 = f1 ?? f0
        return Voice(start: start, render: { t in
            let k = (f1 - f0) / length
            let phase = 2 * .pi * (f0 * t + 0.5 * k * t * t)
            return amp * sin(phase) * env(t, attack: 0.002, decay: length / 3)
        }, length: length * 2.5, pan: pan)
    }

    /// Filtered noise whoosh; the low-pass cutoff sweeps from `from` to `to` Hz.
    static func whoosh(at start: Double, length: Double, from: Double, to: Double, amp: Double = 0.25, pan: Double = 0, seed: UInt64 = 7) -> Voice {
        var rng = seed
        var low = 0.0, band = 0.0
        return Voice(start: start, render: { t in
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let white = Double(Int64(bitPattern: rng >> 11) % 1_000_000) / 500_000 - 1
            let x = min(t / length, 1)
            let cutoff = from + (to - from) * x
            let f = 2 * sin(.pi * min(cutoff, 8_000) / rate)
            // State-variable filter, band-pass output for an airy swish.
            low += f * band
            let high = white - low - 0.6 * band
            band += f * high
            let shape = sin(.pi * x)
            return amp * band * shape * shape
        }, length: length, pan: pan)
    }

    static func thud(_ f: Double, at start: Double, amp: Double = 0.45) -> Voice {
        Voice(start: start, render: { t in
            let glide = f * (1 + 0.6 * exp(-t / 0.015))
            return amp * tanh(2.2 * sin(2 * .pi * glide * t)) * env(t, attack: 0.002, decay: 0.07)
        }, length: 0.3)
    }

    static func click(at start: Double, amp: Double = 0.25) -> Voice {
        var rng: UInt64 = 99
        return Voice(start: start, render: { t in
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let white = Double(Int64(bitPattern: rng >> 11) % 1_000_000) / 500_000 - 1
            return amp * white * exp(-t / 0.003)
        }, length: 0.02)
    }

    // MARK: The palette

    static func design(_ effect: SoundFX.Effect) -> ([Voice], Float) {
        switch effect {
        case .tick:
            return ([blip(3_400, at: 0, length: 0.012, amp: 0.1, pan: Double.random(in: -0.5...0.5))], 1)
        case .tap:
            return ([blip(1_900, to: 1_500, at: 0, length: 0.03, amp: 0.22), click(at: 0, amp: 0.05)], 1)
        case .select:
            return ([blip(g5 * 2, to: e6, at: 0, length: 0.05, amp: 0.16), blip(c6, at: 0.004, length: 0.05, amp: 0.08)], 1)
        case .toggleOn:
            return ([blip(e6, at: 0, length: 0.045, amp: 0.2), blip(a6, at: 0.055, length: 0.06, amp: 0.2)], 1)
        case .toggleOff:
            return ([blip(a6, at: 0, length: 0.045, amp: 0.18), blip(e6, at: 0.055, length: 0.06, amp: 0.18)], 1)
        case .check:
            return ([blip(1_400, to: 2_100, at: 0, length: 0.04, amp: 0.2)], 1)
        case .uncheck:
            return ([blip(1_700, to: 1_100, at: 0, length: 0.04, amp: 0.15)], 1)
        case .unlock:
            return ([click(at: 0, amp: 0.3), click(at: 0.05, amp: 0.2), bell(g5, at: 0.06, decay: 0.35, amp: 0.18, pan: -0.2),
                     bell(c6, at: 0.13, decay: 0.45, amp: 0.2, pan: 0.2)], 1)
        case .lock:
            return ([bell(c6, at: 0, decay: 0.25, amp: 0.15), bell(g5, at: 0.07, decay: 0.3, amp: 0.15), click(at: 0.14, amp: 0.3)], 1)
        case .whoosh:
            return ([whoosh(at: 0, length: 0.32, from: 600, to: 3_200, amp: 0.5)], 1)
        case .scanStart:
            return ([whoosh(at: 0, length: 0.7, from: 300, to: 5_000, amp: 0.55),
                     blip(c5, to: c6, at: 0.02, length: 0.5, amp: 0.09),
                     bell(g6, at: 0.55, decay: 0.3, amp: 0.1, pan: 0.3)], 1)
        case .scanDone:
            let notes = [c6, e6, g6, c7]
            return (notes.enumerated().map { i, f in bell(f, at: Double(i) * 0.085, decay: 0.5, amp: 0.2, pan: -0.45 + Double(i) * 0.3) }, 1)
        case .clean:
            var voices = [whoosh(at: 0, length: 0.55, from: 5_000, to: 500, amp: 0.6, seed: 3)]
            voices += [c5, e5, g5].map { f in
                Voice(start: 0.12, render: { t in 0.07 * sin(2 * .pi * f * t) * env(t, attack: 0.12, decay: 0.5) }, length: 1.6)
            }
            let sparkle = [c7, e7, g6, a6, c7, d6 * 2, e7, g6 * 2]
            for (i, f) in sparkle.enumerated() {
                voices.append(bell(f, at: 0.18 + Double(i) * 0.07, decay: 0.28, amp: 0.1, pan: i.isMultiple(of: 2) ? -0.6 : 0.6))
            }
            voices.append(bell(c6, at: 0.7, decay: 0.8, amp: 0.2))
            return (voices, 1.1)
        case .success:
            return ([bell(g5, at: 0, decay: 0.35, amp: 0.2, pan: -0.2), bell(c6, at: 0.09, decay: 0.55, amp: 0.22, pan: 0.2)], 1)
        case .error:
            return ([thud(196, at: 0, amp: 0.3), thud(174.6, at: 0.13, amp: 0.3)], 1)
        case .vanish:
            return ([whoosh(at: 0, length: 0.45, from: 4_000, to: 200, amp: 0.55, seed: 11),
                     blip(e6, to: c5, at: 0.05, length: 0.35, amp: 0.08)], 1)
        }
    }
}
