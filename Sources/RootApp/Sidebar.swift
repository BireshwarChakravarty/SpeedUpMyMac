import SwiftUI
import RootCore

/// The floating sidebar: modules in groups with quiet icons and live counts, and this Mac at the bottom.
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
            HStack(spacing: 9) {
                Image(systemName: module.symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(selected ? Theme.accentText : .secondary)
                    .frame(width: 18)
                    .symbolEffect(.bounce, value: selected)
                Text(module.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.lime.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.rim.opacity(0.05))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(Theme.spring, value: badge)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The app icon in miniature: a lime `#` and cursor on a near-black tile.
struct RootMark: View {
    var cursorOn = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.23, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x18221A), Color(hex: 0x070A08)], startPoint: .top, endPoint: .bottom))
                HashGlyph()
                    .stroke(LinearGradient(colors: [Color(hex: 0xECFCCB), Color(hex: 0xA3E635), Color(hex: 0x4D7C0F)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round))
                RoundedRectangle(cornerRadius: s * 0.014, style: .continuous)
                    .fill(Color(hex: 0xA3E635))
                    .frame(width: s * 0.12, height: s * 0.055)
                    .position(x: s * 0.775, y: s * 0.715)
                    .opacity(cursorOn ? 1 : 0.2)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The `#` from the icon, in a 1024-unit square.
struct HashGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        for (a, b) in [((400, 250), (340, 770)), ((600, 250), (540, 770)), ((236, 420), (704, 420)), ((212, 610), (680, 610))] {
            path.move(to: p(CGFloat(a.0), CGFloat(a.1)))
            path.addLine(to: p(CGFloat(b.0), CGFloat(b.1)))
        }
        return path
    }
}

struct MachineFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            RootMark().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.machine.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(footerLine).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.rim.opacity(0.04)))
        .task { if model.health == nil { await model.refreshHealth() } }
    }

    private var footerLine: String {
        var parts = [model.machine.chip, model.machine.isAdmin ? "Admin" : "Standard"]
        if let disk = model.health?.disk { parts.append("\(Format.bytes(disk.availableBytes)) free") }
        return parts.joined(separator: " · ")
    }
}
