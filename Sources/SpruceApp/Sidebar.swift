import SwiftUI
import SpruceCore

/// The floating sidebar: modules in groups, each with its coloured icon tile and a live count, and
/// this Mac at the bottom.
/// Liquid Glass on macOS 26 (it's the navigation layer), a plain raised panel before that.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 30) // the traffic lights live here
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Module.groups.indices, id: \.self) { index in
                        let group = Module.groups[index]
                        if let title = group.0 {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 14)
                                .padding(.bottom, 3)
                        }
                        ForEach(group.1) { module in
                            SidebarRow(module: module, selected: model.selection == module, badge: badge(for: module),
                                       namespace: namespace) {
                                guard model.selection != module else { return }
                                SoundFX.shared.play(.select, haptic: .alignment)
                                withAnimation(Theme.spring) { model.selection = module }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
            MachineFooter().padding(8)
        }
        .modifier(SidebarSurface())
    }

    private func badge(for module: Module) -> String? {
        switch module {
        case .cleanup:
            guard let scan = model.scan else { return nil }
            let bytes = scan.bytes(maxRisk: .safe)
            return bytes > 0 ? Format.bytes(bytes) : nil
        case .devPurge:
            let bytes = model.artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
            return bytes > 0 ? Format.bytes(bytes) : nil
        case .maintenance:
            let n = model.smart?.recommendedTasks.count ?? 0
            return n > 0 ? "\(n)" : nil
        case .startup:
            let n = model.smart?.suspiciousStartupItems.count ?? 0
            return n > 0 ? "\(n)" : nil
        case .health:
            return model.health.map { "\($0.score)" }
        case .fleet:
            return model.fleet.count > 1 ? "\(model.fleet.count)" : nil
        default:
            return nil
        }
    }
}

private struct SidebarSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(Theme.sidebar, in: shape)
                .overlay(shape.strokeBorder(Theme.rim.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
        #else
        content.background(Theme.sidebar, in: shape)
            .overlay(shape.strokeBorder(Theme.rim.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        #endif
    }
}

private struct SidebarRow: View {
    var module: Module
    var selected: Bool
    var badge: String?
    var namespace: Namespace.ID
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(module: module, size: 22)
                    .scaleEffect(selected ? 1.06 : 1)
                    .animation(Theme.snappy, value: selected)
                Text(module.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(selected ? AnyShapeStyle(module.accentText) : AnyShapeStyle(.secondary))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.rim.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.rimGradient, lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.rim.opacity(0.05))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(Theme.spring, value: badge)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The app icon in miniature: three glass chevrons and a glint on deep spruce green.
struct SpruceMark: View {
    var glint = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1A6B58), Color(hex: 0x0D3F35), Color(hex: 0x05201B)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(RadialGradient(colors: [Theme.mint.opacity(0.5), .clear], center: UnitPoint(x: 0.5, y: 0.12),
                                         startRadius: 0, endRadius: s * 0.7))
                ForEach(0..<3, id: \.self) { i in
                    SpruceChevrons(only: i)
                        .stroke(SpruceMark.chevronFills[i],
                                style: StrokeStyle(lineWidth: s * 70 / 824, lineCap: .round, lineJoin: .round))
                }
                .shadow(color: .black.opacity(0.35), radius: s * 0.02, y: s * 0.012)
                if glint {
                    Circle().fill(.white).frame(width: s * 0.045, height: s * 0.045)
                        .shadow(color: Theme.mint, radius: s * 0.05)
                        .position(x: s * 0.5, y: s * (196 - 100) / 824)
                }
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .strokeBorder(Theme.rimGradient, lineWidth: max(0.5, s * 0.008))
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static let chevronFills: [LinearGradient] = [
        LinearGradient(colors: [Color(hex: 0xF2FFFA), Color(hex: 0xA7F7DD)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0xB4F8E2), Color(hex: 0x4FE0B2)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(hex: 0x6FEBC4), Color(hex: 0x1FB98C)], startPoint: .top, endPoint: .bottom),
    ]
}

/// The icon's three chevrons (top to bottom), on its 1024-unit grid with the 824-unit body filling
/// the rect. `only` draws a single chevron.
struct SpruceChevrons: Shape {
    var only: Int? = nil

    static let chevrons: [[(CGFloat, CGFloat)]] = [
        [(362, 418), (512, 292), (662, 418)],
        [(307, 604), (512, 432), (717, 604)],
        [(254, 790), (512, 574), (770, 790)],
    ]

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 824
        func p(_ point: (CGFloat, CGFloat)) -> CGPoint {
            CGPoint(x: rect.minX + (point.0 - 100) * k, y: rect.minY + (point.1 - 100) * k)
        }
        var path = Path()
        for (index, chevron) in SpruceChevrons.chevrons.enumerated() where only == nil || only == index {
            path.move(to: p(chevron[0]))
            path.addLine(to: p(chevron[1]))
            path.addLine(to: p(chevron[2]))
        }
        return path
    }
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
