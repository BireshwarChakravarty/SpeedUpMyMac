import SwiftUI
import SpruceCore

/// The sections, grouped the way the rail shows them. Each group's pages appear as tabs at the top.
enum RailGroup: String, CaseIterable, Identifiable {
    case home, clean, apps, speed, protect, fleet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Overview"
        case .clean: return "Clean"
        case .apps: return "Apps"
        case .speed: return "Speed"
        case .protect: return "Protect"
        case .fleet: return "Fleet"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "sparkles"
        case .clean: return "wand.and.rays"
        case .apps: return "square.grid.2x2"
        case .speed: return "gauge.with.dots.needle.67percent"
        case .protect: return "checkmark.shield"
        case .fleet: return "macbook.and.iphone"
        }
    }

    var modules: [Module] {
        switch self {
        case .home: return [.smartScan, .status]
        case .clean: return [.cleanup, .devPurge, .installers, .spaceLens]
        case .apps: return [.uninstaller]
        case .speed: return [.processes, .maintenance, .startup, .tweaks]
        case .protect: return [.health]
        case .fleet: return [.fleet, .history]
        }
    }

    /// The colour the rail item lights up in.
    var module: Module { modules[0] }

    static func of(_ module: Module) -> RailGroup {
        allCases.first { $0.modules.contains(module) } ?? .home
    }
}

/// The slim rail on the left: Spruce's mark, one icon per group, Settings at the bottom.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        let current = RailGroup.of(model.selection ?? .smartScan)
        VStack(spacing: 10) {
            Color.clear.frame(height: 22) // the traffic lights live here
            SpruceMark().frame(width: 40, height: 40)
                .help("Spruce")
            Capsule().fill(Theme.hairline).frame(width: 28, height: 1).padding(.vertical, 4)
            ForEach(RailGroup.allCases) { group in
                RailButton(group: group, selected: group == current, badge: badge(for: group), namespace: namespace) {
                    guard group != current else { return }
                    SoundFX.shared.play(.select, haptic: .alignment)
                    withAnimation(Theme.spring) { model.selection = group.module }
                }
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings (⌘,)")
            .padding(.bottom, 10)
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// A dot when something in the group needs a look.
    private func badge(for group: RailGroup) -> Bool {
        switch group {
        case .speed: return !(model.smart?.recommendedTasks.isEmpty ?? true) || !(model.smart?.suspiciousStartupItems.isEmpty ?? true)
        case .protect: return (model.health?.score ?? 100) < 70
        default: return false
        }
    }
}

private struct RailButton: View {
    var group: RailGroup
    var selected: Bool
    var badge: Bool
    var namespace: Namespace.ID
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(group.module.accent)
                        .matchedGeometryEffect(id: "rail", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.chipFill)
                }
                Image(systemName: group.symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(.secondary))
                    .symbolEffect(.bounce, value: selected)
            }
            .frame(width: 48, height: 48)
            .overlay(alignment: .topTrailing) {
                if badge && !selected {
                    Circle().fill(Theme.review).frame(width: 7, height: 7).offset(x: -8, y: 8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(group.title)
        .accessibilityLabel(group.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The app icon in miniature: four rounded bars stacked into a spruce, on deep forest green.
struct SpruceMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 824
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x17463A), Color(hex: 0x06170F)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(RadialGradient(colors: [Color(hex: 0x5FF0C4).opacity(0.4), .clear], center: UnitPoint(x: 0.5, y: 0.28),
                                         startRadius: 0, endRadius: s * 0.6))
                ForEach(SpruceMark.bars.indices, id: \.self) { i in
                    let bar = SpruceMark.bars[i]
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: bar.top), Color(hex: bar.bottom)], startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(0.35))
                                .frame(height: 16 * k).padding(.horizontal, 26 * k).padding(.top, 12 * k)
                        }
                        .frame(width: bar.width * k, height: 100 * k)
                        .offset(x: (412 - bar.width / 2) * k, y: (162 + CGFloat(i) * 124) * k)
                        .shadow(color: .black.opacity(0.35), radius: s * 0.02, y: s * 0.012)
                }
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .strokeBorder(Theme.rimGradient, lineWidth: max(0.5, s * 0.008))
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The icon's bars, top to bottom, on its 824-unit body: width and gradient.
    static let bars: [(width: CGFloat, top: UInt32, bottom: UInt32)] = [
        (196, 0xF2FFFA, 0xBDF6E2),
        (344, 0x9BF2D5, 0x5FE0B6),
        (492, 0x49D9AB, 0x22B98C),
        (640, 0x1DAE85, 0x0E7F62),
    ]
}

struct MachineFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            SpruceMark().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.machine.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(footerLine).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.rim.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rimGradient, lineWidth: 1))
        .task { if model.health == nil { await model.refreshHealth() } }
    }

    private var footerLine: String {
        var parts = [model.machine.chip, model.machine.isAdmin ? "Admin" : "Standard"]
        if let disk = model.health?.disk { parts.append("\(Format.bytes(disk.availableBytes)) free") }
        return parts.joined(separator: " · ")
    }
}
