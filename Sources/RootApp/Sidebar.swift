import SwiftUI
import RootCore

/// Glass sidebar: logo, grouped modules with a sliding selection pill, live badges, and this Mac.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandMark()
                .padding(.top, 30)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Module.groups.indices, id: \.self) { index in
                        let group = Module.groups[index]
                        if let title = group.0 {
                            Text(title.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
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
            MachineFooter().padding(10)
        }
        .glassCard(cornerRadius: 24)
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
                ModuleGlyph(module: module, size: 26, bounce: selected)
                Text(module.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(selected ? module.ink : .secondary)
                        .background(Capsule().fill(selected ? AnyShapeStyle(module.gradient) : AnyShapeStyle(Theme.rim.opacity(0.1))))
                        .contentTransition(.numericText())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.rim.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rimGradient, lineWidth: 1))
                        .overlay(alignment: .leading) {
                            Capsule().fill(module.gradient).frame(width: 3, height: 18).offset(x: -5)
                                .shadow(color: module.tint.0, radius: 4)
                        }
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.rim.opacity(0.05))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(Theme.spring, value: badge)
    }
}

/// The Root mark (the root shell's `#` and a cursor, as in Assets/AppIcon.svg) plus the wordmark.
struct BrandMark: View {
    @State private var blink = false

    var body: some View {
        HStack(spacing: 10) {
            RootMark(cursorOn: blink).frame(width: 34, height: 34)
                .shadow(color: Theme.leaf.opacity(0.45), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("root").font(.system(size: 20, weight: .heavy, design: .monospaced))
                    Text("_").font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.lime)
                        .opacity(blink ? 1 : 0.15)
                }
                Text("clean to the root").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { blink = true }
        }
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
                RoundedRectangle(cornerRadius: s * 0.23, style: .continuous)
                    .fill(RadialGradient(colors: [Theme.leaf.opacity(0.35), .clear], center: UnitPoint(x: 0.42, y: 0.5),
                                         startRadius: 0, endRadius: s * 0.5))
                HashGlyph()
                    .stroke(LinearGradient(colors: [Color(hex: 0xECFCCB), Theme.lime, Color(hex: 0x4D7C0F)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round))
                RoundedRectangle(cornerRadius: s * 0.014, style: .continuous)
                    .fill(Theme.lime)
                    .frame(width: s * 0.12, height: s * 0.055)
                    .position(x: s * 0.775, y: s * 0.715)
                    .opacity(cursorOn ? 1 : 0.2)
                RoundedRectangle(cornerRadius: s * 0.23, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
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
            ZStack {
                if let score = model.health?.score {
                    ScoreRing(score: score, size: 34)
                } else {
                    Image(systemName: "macmini").font(.system(size: 16)).foregroundStyle(Theme.brand)
                }
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.machine.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text("\(model.machine.chip) · \(model.machine.isAdmin ? "Admin" : "Standard")")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let disk = model.health?.disk {
                    GrowingBar(fraction: disk.usedFraction, height: 4)
                    Text("\(Format.bytes(disk.availableBytes)) free").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.rim.opacity(0.05)))
        .task { if model.health == nil { await model.refreshHealth() } }
    }
}
