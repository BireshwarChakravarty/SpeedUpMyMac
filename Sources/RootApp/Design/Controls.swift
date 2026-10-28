import SwiftUI
import RootCore

// MARK: - Buttons

/// The primary call to action: a solid lime capsule with dark text. One per screen.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: LinearGradient = Theme.brand
    var glow: Color = Theme.leaf
    var text: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, fill: fill, text: text)
    }
}

private struct PrimaryButtonBody: View {
    var configuration: ButtonStyleConfiguration
    var fill: LinearGradient
    var text: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, small ? 12 : 18)
            .frame(height: small ? 26 : 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().fill(.white.opacity(hovering ? 0.12 : 0)))
            .overlay(Capsule().fill(.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed, sound: .tap))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

/// Secondary buttons: an outlined capsule that fills slightly on hover.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { QuietButtonBody(configuration: configuration) }
}

private struct QuietButtonBody: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .medium))
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? 26 : 32)
            .background(Capsule().fill(Theme.rim.opacity(configuration.isPressed ? 0.12 : hovering ? 0.08 : 0.04)))
            .overlay(Capsule().strokeBorder(Theme.rim.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(PressFeedback(isPressed: configuration.isPressed, sound: .tap))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var brand: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var danger: PrimaryButtonStyle { PrimaryButtonStyle(fill: Theme.danger, glow: Color(hex: 0xF43F5E), text: .white) }
    /// Kept for call sites written per module; every module now shares the one accent.
    static func tinted(_ module: Module) -> PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
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
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.rim.opacity(hovering ? 0.1 : 0.0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? .primary : .secondary)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Toggles

/// Round checkmark: lime with a dark tick when on, a hairline ring when off.
struct CheckToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
            SoundFX.shared.play(configuration.isOn ? .check : .uncheck, haptic: .alignment)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(Theme.rim.opacity(configuration.isOn ? 0 : 0.3), lineWidth: 1.5)
                    Circle().fill(Theme.lime).scaleEffect(configuration.isOn ? 1 : 0.5).opacity(configuration.isOn ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .scaleEffect(configuration.isOn ? 1 : 0.5)
                        .opacity(configuration.isOn ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// The system switch, tinted with the accent. Kept as a style so call sites stay unchanged.
struct GlowSwitchStyle: ToggleStyle {
    var tint: LinearGradient = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(Theme.leaf)
    }
}

extension ToggleStyle where Self == CheckToggleStyle {
    static var check: CheckToggleStyle { CheckToggleStyle() }
}

extension ToggleStyle where Self == GlowSwitchStyle {
    static var glow: GlowSwitchStyle { GlowSwitchStyle() }
}

// MARK: - Segmented picker

/// The system segmented control (Liquid Glass on macOS 26), with a click.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String, symbol: String?)]

    var body: some View {
        Picker("", selection: Binding(get: { selection }, set: { new in
            guard new != selection else { return }
            SoundFX.shared.play(.select)
            withAnimation(Theme.spring) { selection = new }
        })) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i].title).tag(options[i].value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - Sudo switch

/// Lock, "Sudo", and a small system switch. Amber when armed.
struct SudoSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.sudo
        HStack(spacing: 7) {
            Image(systemName: on ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Theme.sudo : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text("Sudo").font(.system(size: 13, weight: .medium))
            Toggle("Sudo", isOn: Binding(get: { on }, set: { _ in
                guard model.machine.isAdmin else { SoundFX.shared.play(.error); return }
                let binding = model.sudoBinding
                binding.wrappedValue.toggle()
                SoundFX.shared.play(model.sudo ? .unlock : .lock, haptic: .levelChange)
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.sudo)
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(height: 30)
        .background(Capsule().fill(on ? Theme.sudo.opacity(0.14) : Theme.rim.opacity(0.05)))
        .overlay(Capsule().strokeBorder(on ? Theme.sudo.opacity(0.4) : Theme.rim.opacity(0.12), lineWidth: 1))
        .animation(Theme.snappy, value: on)
        .disabled(!model.machine.isAdmin)
        .help(model.machine.isAdmin
              ? "Sudo mode: include system-level items. macOS asks for your password once per batch, after you've seen the exact script."
              : "\(model.machine.userName) is a standard account on this Mac, so Root cleans everything you own but can't touch system folders.")
    }
}
