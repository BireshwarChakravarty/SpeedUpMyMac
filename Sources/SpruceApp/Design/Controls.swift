import SwiftUI
import SpruceCore

// MARK: - Buttons

/// The primary call to action: a high-contrast pill (warm white on dark, warm ink on paper), or a
/// section's colour with `.tinted(_:)`. One per screen. `.controlSize(.large)` for hero actions.
struct PrimaryButtonStyle: ButtonStyle {
    /// nil: the high-contrast inverse pill.
    var fill: LinearGradient? = nil
    var glow: Color? = nil
    var text: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, fill: fill, glow: glow, text: text)
    }
}

private struct PrimaryButtonBody: View {
    var configuration: ButtonStyleConfiguration
    var fill: LinearGradient?
    var glow: Color?
    var text: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.pageModule) private var module
    @State private var hovering = false

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        let large = controlSize == .large || controlSize == .extraLarge
        let glowColor = glow ?? .black
        configuration.label
            .font(Theme.sans(large ? 15 : small ? 12 : 13, .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(text ?? (fill == nil ? Theme.onInverse : Theme.ink))
            .padding(.horizontal, large ? 28 : small ? 12 : 18)
            .frame(height: large ? 46 : small ? 26 : 32)
            .background {
                if let fill { Capsule().fill(fill) } else { Capsule().fill(Theme.inverse) }
            }
            .overlay(Capsule().fill(.white.opacity(hovering ? 0.12 : 0)))
            .overlay(Capsule().fill(.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .shadow(color: glowColor.opacity(isEnabled ? (fill == nil ? 0.25 : (hovering ? 0.5 : 0.35)) : 0),
                    radius: large ? 14 : 6, y: large ? 5 : 2)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed, sound: .tap))
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

/// Secondary buttons: a glass capsule that brightens on hover.
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
        let large = controlSize == .large || controlSize == .extraLarge
        configuration.label
            .font(Theme.sans(large ? 15 : small ? 12 : 13, .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, large ? 22 : small ? 10 : 14)
            .frame(height: large ? 46 : small ? 26 : 32)
            .background(Capsule().fill(configuration.isPressed ? Theme.cardHover : hovering ? Theme.cardHover : Theme.chipFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(PressFeedback(isPressed: configuration.isPressed, sound: .tap))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// The primary call to action: the high-contrast pill.
    static var brand: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var danger: PrimaryButtonStyle { PrimaryButtonStyle(fill: Theme.danger, glow: Color(hex: 0xF43F5E), text: .white) }
    /// The primary button in a specific section's colour.
    static func tinted(_ module: Module) -> PrimaryButtonStyle {
        PrimaryButtonStyle(fill: module.buttonGradient, glow: module.accent)
    }
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

/// Round checkmark in the section's colour with a dark tick when on, a hairline ring when off.
struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { CheckToggleBody(configuration: configuration) }
}

private struct CheckToggleBody: View {
    var configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pageModule) private var module

    var body: some View {
        Button {
            configuration.isOn.toggle()
            SoundFX.shared.play(configuration.isOn ? .check : .uncheck, haptic: .alignment)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(Theme.rim.opacity(configuration.isOn ? 0 : 0.3), lineWidth: 1.5)
                    Circle().fill(module.buttonGradient).scaleEffect(configuration.isOn ? 1 : 0.5).opacity(configuration.isOn ? 1 : 0)
                        .shadow(color: module.accent.opacity(configuration.isOn ? 0.45 : 0), radius: 4)
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

/// The system switch in the section's colour, label on the left like System Settings.
struct GlowSwitchStyle: ToggleStyle {
    /// Kept so call sites can name a section; the switch takes that section's colour.
    var tint: LinearGradient? = nil
    var module: Module? = nil

    func makeBody(configuration: Configuration) -> some View {
        GlowSwitchBody(configuration: configuration, module: module)
    }
}

private struct GlowSwitchBody: View {
    var configuration: ToggleStyleConfiguration
    var module: Module?
    @Environment(\.pageModule) private var page

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle("", isOn: configuration.$isOn).labelsHidden().toggleStyle(.switch).tint((module ?? page).accent)
        }
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
        .tint(Color(light: 0x8E8E93, dark: 0x636366)) // neutral selection: white text stays readable
    }
}

// MARK: - Admin switch

/// Includes system-level items when on. Shows a fingerprint when Touch ID replaces the password.
/// Amber while armed.
struct SudoSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.sudo
        HStack(spacing: 7) {
            Image(systemName: model.touchIDForAdmin ? "touchid" : (on ? "lock.open.fill" : "lock.fill"))
                .font(.system(size: model.touchIDForAdmin ? 13 : 11, weight: .semibold))
                .foregroundStyle(on ? Theme.sudo : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text("Admin").font(.system(size: 13, weight: .medium))
            Toggle("Admin", isOn: Binding(get: { on }, set: { _ in
                guard model.machine.isAdmin else { SoundFX.shared.play(.error); return }
                let binding = model.sudoBinding
                binding.wrappedValue.toggle()
                SoundFX.shared.play(model.sudo ? .unlock : .lock, haptic: .levelChange)
                if model.sudo { model.offerTouchIDIfUseful() }
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.sudo)
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(height: 32)
        .background(Capsule().fill(on ? Theme.sudo.opacity(0.16) : Theme.rim.opacity(0.06)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(Theme.sudo.opacity(0.45)) : AnyShapeStyle(Theme.rimGradient), lineWidth: 1))
        .shadow(color: Theme.sudo.opacity(on ? 0.35 : 0), radius: 10)
        .animation(Theme.snappy, value: on)
        .disabled(!model.machine.isAdmin)
        .help(model.machine.isAdmin
              ? (model.touchIDForAdmin
                 ? "Admin mode: include system-level items. Spruce asks for your fingerprint once, then not again for the next few minutes."
                 : "Admin mode: include system-level items. macOS asks for your password once, then not again for the next few minutes.")
              : "\(model.machine.userName) is a standard account on this Mac, so Spruce cleans everything you own but can't touch system folders.")
    }
}
