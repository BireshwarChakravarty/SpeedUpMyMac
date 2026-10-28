import SwiftUI
import BurnishCore

// MARK: - Buttons

/// The primary call to action: a capsule of polish gradient with a travelling glint.
struct PolishButtonStyle: ButtonStyle {
    var fill: LinearGradient = Theme.polish
    var glow: Color = Theme.azure

    func makeBody(configuration: Configuration) -> some View {
        PolishButtonBody(configuration: configuration, fill: fill, glow: glow)
    }
}

private struct PolishButtonBody: View {
    var configuration: ButtonStyleConfiguration
    var fill: LinearGradient
    var glow: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(fill)
                    .overlay(Capsule().fill(.white.opacity(hovering ? 0.12 : 0)))
                    .shimmer(isEnabled, period: 3.6)
                    .opacity(isEnabled ? 1 : 0.35)
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: glow.opacity(isEnabled ? (hovering ? 0.65 : 0.4) : 0), radius: hovering ? 18 : 10, y: 5)
            .modifier(PressFeedback(isPressed: configuration.isPressed, sound: .tap))
            .animation(Theme.snappy, value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

/// Secondary buttons: a pane of glass that brightens on hover.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GlassButtonBody(configuration: configuration) }
}

private struct GlassButtonBody: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font(small ? .callout.weight(.medium) : .body.weight(.medium))
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 4 : 7)
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(Theme.rim.opacity(hovering ? 0.14 : 0.06)))
            .overlay(Capsule().strokeBorder(Theme.rimGradient, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(PressFeedback(isPressed: configuration.isPressed, sound: .tap))
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == PolishButtonStyle {
    static var polish: PolishButtonStyle { PolishButtonStyle() }
    static var danger: PolishButtonStyle { PolishButtonStyle(fill: Theme.danger, glow: Color(hex: 0xFB7185)) }
    static func tinted(_ module: Module) -> PolishButtonStyle { PolishButtonStyle(fill: module.gradient, glow: module.tint.1) }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}

/// Round icon button (reveal in Finder, add to collector…).
struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.rim.opacity(hovering ? 0.14 : 0.0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? .primary : .secondary)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
    }
}

// MARK: - Toggles

/// Round checkmark that fills with the polish gradient, with a pop and a sound.
struct CheckToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            SoundFX.shared.play(configuration.isOn ? .check : .uncheck, haptic: .alignment)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(Theme.rim.opacity(configuration.isOn ? 0 : 0.35), lineWidth: 1.5)
                    Circle().fill(Theme.polish).scaleEffect(configuration.isOn ? 1 : 0.2).opacity(configuration.isOn ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .scaleEffect(configuration.isOn ? 1 : 0.4)
                        .opacity(configuration.isOn ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .shadow(color: Theme.azure.opacity(configuration.isOn ? 0.5 : 0), radius: 5)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// A switch with a gradient track and a springy knob.
struct GlowSwitchStyle: ToggleStyle {
    var tint: LinearGradient = Theme.polish
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(Theme.rim.opacity(0.14))
                Capsule().fill(tint).opacity(configuration.isOn ? 1 : 0)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .overlay(Capsule().strokeBorder(Theme.rim.opacity(0.12), lineWidth: 0.5))
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: configuration.isOn)
            .onTapGesture {
                guard isEnabled else { return }
                configuration.isOn.toggle()
                SoundFX.shared.play(configuration.isOn ? .toggleOn : .toggleOff, haptic: .levelChange)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ToggleStyle where Self == CheckToggleStyle {
    static var check: CheckToggleStyle { CheckToggleStyle() }
}

extension ToggleStyle where Self == GlowSwitchStyle {
    static var glow: GlowSwitchStyle { GlowSwitchStyle() }
}

// MARK: - Pill picker

/// A segmented control whose selection is a glass pill that slides between options.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String, symbol: String?)]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    withAnimation(Theme.spring) { selection = option.value }
                    SoundFX.shared.play(.select, haptic: .alignment)
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                        Text(option.title).font(.callout.weight(selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .background {
                        if selected {
                            Capsule().fill(Theme.rim.opacity(0.14))
                                .overlay(Capsule().strokeBorder(Theme.rimGradient, lineWidth: 1))
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Theme.rim.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Sudo switch

/// The Sudo capsule: amber and glowing when on, a lock that springs open, a click and a chime.
struct SudoSwitch: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let on = model.sudo
        Button {
            guard model.machine.isAdmin else { SoundFX.shared.play(.error); return }
            let sudo = model.sudoBinding
            sudo.wrappedValue.toggle()
            SoundFX.shared.play(model.sudo ? .unlock : .lock, haptic: .levelChange)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: on)
                Text("Sudo").font(.system(.callout, design: .rounded).weight(.semibold))
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? AnyShapeStyle(Color.white.opacity(0.3)) : AnyShapeStyle(Theme.rim.opacity(0.15)))
                    Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }
                .frame(width: 30, height: 18)
            }
            .foregroundStyle(on ? .white : .primary)
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .background {
                Capsule().fill(on ? AnyShapeStyle(Theme.sudoGradient) : AnyShapeStyle(.ultraThinMaterial))
                    .shimmer(on, period: 4)
            }
            .overlay(Capsule().strokeBorder(on ? .white.opacity(0.35) : Theme.rim.opacity(0.12), lineWidth: 1))
            .shadow(color: Color(hex: 0xF59E0B).opacity(on ? 0.55 : 0), radius: hovering ? 16 : 10)
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(model.machine.isAdmin ? 1 : 0.45)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: on)
        .animation(Theme.snappy, value: hovering)
        .onHover { hovering = $0 }
        .help(model.machine.isAdmin
              ? "Sudo mode: include system-level items. macOS asks for your password once per batch, after you've seen the exact script."
              : "\(model.machine.userName) is a standard account on this Mac, so Burnish cleans everything you own but can't touch system folders.")
        .accessibilityLabel("Sudo mode")
        .accessibilityValue(on ? "On" : "Off")
    }
}
