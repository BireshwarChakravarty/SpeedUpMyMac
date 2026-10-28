import SwiftUI
import BurnishCore

struct SpaceLensView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var root = Paths.home
    @State private var tree: DiskNode?
    @State private var focus: DiskNode?
    @State private var trail: [DiskNode] = []
    @State private var hovered: DiskNode?
    @State private var collector: [String: Int64] = [:]
    @State private var large: [LargeFile] = []
    @State private var olderOnly = false
    @State private var dupes: [DuplicateGroup] = []
    @State private var dupeKeep: [String: String] = [:]
    @State private var sweep: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PillPicker(selection: $mode, options: [(0, "Disk map", "circle.circle"), (1, "Large & old", "doc.badge.clock"),
                                                       (2, "Duplicates", "doc.on.doc")])
                Spacer()
                Text(Paths.abbreviate(root)).font(Theme.mono).foregroundStyle(.secondary)
                Button("Choose folder…") { chooseRoot() }
            }
            .padding(.horizontal, 26).padding(.bottom, 12)
            Group {
                switch mode {
                case 0: mapPane
                case 1: largePane
                default: dupesPane
                }
            }
            .id(mode)
            .transition(.moduleSwap)
            .animation(Theme.spring, value: mode)
        }
        .navigationTitle("Space Lens")
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: root)
        if panel.runModal() == .OK, let url = panel.url {
            root = url.path
            tree = nil; focus = nil; trail = []; large = []; dupes = []
        }
    }

    // MARK: Disk map

    private var mapPane: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack {
                if let node = focus ?? tree {
                    Color.clear.modifier(Tween(value: sweep) { progress in
                        Sunburst(root: node, hovered: $hovered, progress: progress) { tapped in
                            if tapped.isDirectory && !tapped.children.isEmpty {
                                SoundFX.shared.play(.whoosh)
                                trail.append(focus ?? tree!)
                                focus = tapped
                            }
                        }
                    })
                    .frame(minWidth: 380, minHeight: 380)
                    .onAppear { sweepIn() }
                    .onChange(of: ObjectIdentifier(node)) { sweepIn() }
                    .overlay {
                        VStack(spacing: 2) {
                            Text((hovered ?? node).name).font(.headline).lineLimit(1).frame(maxWidth: 150)
                            Text(Format.bytes((hovered ?? node).bytes)).font(Theme.heroSmall)
                            if !trail.isEmpty && hovered == nil {
                                Button("Back") { SoundFX.shared.play(.whoosh); focus = trail.popLast() }.controlSize(.small)
                            }
                        }
                        .allowsHitTesting(hovered == nil)
                    }
                } else {
                    EmptyState(symbol: "circle.circle", title: "Map your disk",
                               message: "A DaisyDisk-style sunburst of what's using space. Click a ring to drill in; drop items into the collector to remove them together.")
                    Button("Scan \(Paths.abbreviate(root))") { scanTree() }.buttonStyle(.polish).disabled(model.busy != nil)
                }
            }
            .frame(maxWidth: .infinity)
            .card()

            VStack(alignment: .leading, spacing: 6) {
                if let node = focus ?? tree {
                    Text(Paths.abbreviate(node.path)).font(.headline).lineLimit(1).truncationMode(.middle)
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(node.children) { child in
                                HStack {
                                    Image(systemName: child.isDirectory ? "folder.fill" : "doc").foregroundStyle(Theme.azure)
                                    Text(child.name).lineLimit(1)
                                    Spacer()
                                    SizeText(bytes: child.bytes)
                                    if !child.isAggregate {
                                        IconButton(symbol: collector[child.path] == nil ? "plus.circle" : "checkmark.circle.fill",
                                                   help: "Add to collector") {
                                            SoundFX.shared.play(.check)
                                            withAnimation(Theme.snappy) { collector[child.path] = child.bytes }
                                        }
                                        .disabled(!Safety.isAllowed(child.path))
                                    }
                                }
                                .padding(.vertical, 3)
                                .rowHover()
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    if child.isDirectory && !child.children.isEmpty { trail.append(node); focus = child }
                                }
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Label("Collector: \(collector.count) · \(Format.bytes(collector.values.reduce(0, +)))", systemImage: "tray.full")
                        Spacer()
                        Button("Clear") { collector = [:] }.disabled(collector.isEmpty)
                        Button("Remove…") {
                            model.confirmRemoval(title: "Remove collected items", items: collector.map { (path: $0.key, bytes: $0.value) })
                            collector = [:]
                        }
                        .buttonStyle(.polish).disabled(collector.isEmpty)
                    }
                    Button("Rescan") { scanTree() }.disabled(model.busy != nil)
                }
            }
            .frame(width: 380)
            .card()
        }
        .padding(.horizontal, 22).padding(.bottom, 22)
    }

    private func sweepIn() {
        sweep = 0
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.9)) { sweep = 1 }
    }

    private func scanTree() {
        let path = root
        Task {
            tree = await model.run("Mapping \(Paths.abbreviate(path))…") { SpaceLens.scan(path, depth: 4) }
            focus = nil
            trail = []
        }
    }

    // MARK: Large files

    private var largePane: some View {
        ModuleScroll {
            HStack {
                Text("Files over \(model.settings.largeFileMinMB) MB").font(.headline)
                Toggle("Only not opened in \(model.settings.oldFileDays) days", isOn: $olderOnly)
                Spacer()
                Button("Find") {
                    let path = root, min = Int64(model.settings.largeFileMinMB) * 1_000_000
                    let days: Int? = olderOnly ? model.settings.oldFileDays : nil
                    Task { large = await model.run("Looking for large files…") { SpaceLens.largeFiles(in: path, minBytes: min, olderThanDays: days) } }
                }
                .buttonStyle(.polish)
            }
            if !large.isEmpty {
                VStack(spacing: 2) {
                    ForEach(large) { f in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable().frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((f.path as NSString).lastPathComponent).lineLimit(1)
                                PathText(path: (f.path as NSString).deletingLastPathComponent)
                            }
                            Spacer()
                            if let a = f.accessed { Text("opened \(Format.relative(a))").font(.caption).foregroundStyle(.secondary) }
                            SizeText(bytes: f.bytes).frame(width: 80, alignment: .trailing)
                            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(f.path) }
                            IconButton(symbol: "trash", help: "Move to Trash") {
                                model.confirmRemoval(title: "Move \((f.path as NSString).lastPathComponent) to Trash", items: [(path: f.path, bytes: f.bytes)])
                            }
                        }
                        .padding(.vertical, 3)
                        .rowHover()
                    }
                }
                .card()
            }
        }
    }

    // MARK: Duplicates

    private var dupesPane: some View {
        ModuleScroll {
            HStack {
                Text("Identical files (SHA-256) over 1 MB").font(.headline)
                Spacer()
                if !dupes.isEmpty {
                    Text("\(Format.bytes(dupes.reduce(0) { $0 + $1.reclaimable })) reclaimable").foregroundStyle(.secondary)
                    Button("Remove extra copies…") {
                        let items = dupes.flatMap { g in g.paths.filter { $0 != (dupeKeep[g.hash] ?? g.paths[0]) }.map { (path: $0, bytes: g.bytesEach) } }
                        model.confirmRemoval(title: "Remove duplicate copies", items: items)
                    }
                }
                Button("Find") {
                    let path = root
                    Task { dupes = await model.run("Hashing files…") { Duplicates.find(in: path) } }
                }
                .buttonStyle(.polish)
            }
            Text("Burnish keeps one copy of each set — click a path to choose which.").font(.caption).foregroundStyle(.secondary)
            ForEach(dupes) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.paths.count) × \(Format.bytes(group.bytesEach))").fontWeight(.medium)
                    ForEach(group.paths, id: \.self) { path in
                        let keep = (dupeKeep[group.hash] ?? group.paths[0]) == path
                        Button { dupeKeep[group.hash] = path } label: {
                            HStack {
                                Image(systemName: keep ? "checkmark.circle.fill" : "circle").foregroundStyle(keep ? Theme.safe : .secondary)
                                PathText(path: path)
                                Spacer()
                                Text(keep ? "keep" : "remove").font(.caption).foregroundStyle(keep ? Theme.safe : Theme.review)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 12)
            }
        }
    }
}

/// Sunburst chart: each ring is one directory level; angle is proportional to size.
struct Sunburst: View {
    var root: DiskNode
    @Binding var hovered: DiskNode?
    /// 0…1 while the rings sweep in.
    var progress: Double = 1
    var onTap: (DiskNode) -> Void

    struct Segment {
        var node: DiskNode
        var depth: Int
        var start: Double
        var end: Double
    }

    private var segments: [Segment] {
        var out: [Segment] = []
        func walk(_ node: DiskNode, depth: Int, start: Double, span: Double) {
            guard depth <= 3, node.bytes > 0 else { return }
            var angle = start
            for child in node.children {
                let childSpan = span * Double(child.bytes) / Double(node.bytes)
                if childSpan > 0.004 {
                    out.append(Segment(node: child, depth: depth, start: angle, end: angle + childSpan))
                    walk(child, depth: depth + 1, start: angle, span: childSpan)
                }
                angle += childSpan
            }
        }
        walk(root, depth: 1, start: 0, span: 2 * .pi)
        return out
    }

    private func ringRadii(_ depth: Int, in size: CGFloat) -> (CGFloat, CGFloat) {
        let hole = size * 0.18
        let ring = (size / 2 - hole) / 3
        return (hole + ring * CGFloat(depth - 1), hole + ring * CGFloat(depth) - 2)
    }

    private func color(_ s: Segment) -> Color {
        let hue = 0.47 + 0.25 * ((s.start + s.end) / 2) / (2 * .pi)
        return Color(hue: hue, saturation: 0.75 - 0.12 * Double(s.depth), brightness: 0.95 - 0.08 * Double(s.depth))
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let segs = segments
            Canvas { context, _ in
                for s in segs {
                    // Outer rings start a little later, so the chart unfolds from the centre.
                    let local = min(max((progress - Double(s.depth - 1) * 0.12) / 0.76, 0), 1)
                    guard local > 0 else { continue }
                    var (inner, outer) = ringRadii(s.depth, in: size)
                    let isHovered = hovered.map { $0 === s.node } ?? false
                    if isHovered { outer += 6; inner -= 1 }
                    let start = s.start * local, end = s.end * local
                    var path = Path()
                    path.addArc(center: center, radius: outer, startAngle: .radians(start - .pi / 2),
                                endAngle: .radians(end - .pi / 2), clockwise: false)
                    path.addArc(center: center, radius: inner, startAngle: .radians(end - .pi / 2),
                                endAngle: .radians(start - .pi / 2), clockwise: true)
                    path.closeSubpath()
                    if isHovered {
                        var glow = context
                        glow.addFilter(.shadow(color: color(s).opacity(0.9), radius: 10))
                        glow.fill(path, with: .color(color(s)))
                    } else {
                        context.fill(path, with: .color(color(s).opacity((s.node.isAggregate ? 0.35 : 0.85) * local)))
                    }
                    context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.75)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = hit(p, center: center, size: size, segs: segs)
                case .ended: hovered = nil
                }
            }
            .onTapGesture { p in
                if let node = hit(p, center: center, size: size, segs: segs) { onTap(node) }
            }
        }
    }

    private func hit(_ p: CGPoint, center: CGPoint, size: CGFloat, segs: [Segment]) -> DiskNode? {
        let dx = p.x - center.x, dy = p.y - center.y
        let r = sqrt(dx * dx + dy * dy)
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return segs.first { s in
            let (inner, outer) = ringRadii(s.depth, in: size)
            return r >= inner && r <= outer && Double(angle) >= s.start && Double(angle) < s.end
        }?.node
    }
}
