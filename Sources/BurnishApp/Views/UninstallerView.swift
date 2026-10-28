import SwiftUI
import BurnishCore

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var query = ""
    @State private var sort = 0
    @State private var selectedApp: InstalledApp?
    @State private var leftovers: [Leftover] = []
    @State private var chosenLeftovers = Set<String>()
    @State private var chosenOrphans = Set<String>()

    private var filteredApps: [InstalledApp] {
        let list = model.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
        switch sort {
        case 1: return list.sorted { $0.bytes > $1.bytes }
        case 2: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        default: return list
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Applications").tag(0)
                Text("Orphaned files").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.vertical, 12)
            if mode == 0 { appsPane } else { orphansPane }
        }
        .navigationTitle("Uninstaller")
        .task { if model.apps.isEmpty { await model.loadApps() } }
    }

    // MARK: Apps

    private var appsPane: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
                    Picker("", selection: $sort) {
                        Text("Name").tag(0)
                        Text("Size").tag(1)
                        Text("Least used").tag(2)
                    }
                    .labelsHidden().frame(width: 110)
                }
                List(filteredApps, selection: Binding(get: { selectedApp?.path }, set: { path in
                    selectedApp = model.apps.first { $0.path == path }
                })) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text(app.lastUsed.map { "Used \(Format.relative($0))" } ?? "Never opened")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !app.userRemovable { Image(systemName: "lock.shield").foregroundStyle(Theme.sudo).help("Needs Sudo mode") }
                        SizeText(bytes: app.bytes)
                    }
                    .tag(app.path)
                }
            }
            .padding(.leading, 12)
            .frame(minWidth: 320, idealWidth: 380)

            Group {
                if let app = selectedApp { appDetail(app) } else {
                    EmptyState(symbol: "xmark.app", title: "Pick an app",
                               message: "Burnish finds its caches, preferences, containers, launch agents and helpers — the way Pearcleaner does — and shows you each one before anything moves. You can also drag an app to the Trash; Burnish will notice and offer to clean up after it.")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedApp) {
            guard let app = selectedApp else { return }
            Task {
                leftovers = await model.leftovers(for: app)
                chosenLeftovers = Set(leftovers.filter { !$0.isUserData }.map(\.path))
            }
        }
    }

    private func appDetail(_ app: InstalledApp) -> some View {
        let total = app.bytes + leftovers.filter { chosenLeftovers.contains($0.path) }.reduce(0) { $0 + $1.bytes }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text(app.name).font(.title2.weight(.bold))
                        Text("\(app.version) · \(app.bundleID)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if app.isAppStore { Text("Mac App Store").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(Format.bytes(total)).font(Theme.heroSmall)
                        Button("Uninstall") {
                            model.confirmUninstall(app, leftovers: leftovers.filter { chosenLeftovers.contains($0.path) })
                        }
                        .buttonStyle(.polish)
                        .disabled(!app.canUninstall)
                    }
                }
                .card()
                if !app.canUninstall {
                    Label("\(app.name) is part of macOS and can't be removed.", systemImage: "apple.logo").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files outside the app (\(leftovers.count))").font(.headline)
                    Text("Personal data (Application Support, containers) is unticked by default.").font(.caption).foregroundStyle(.secondary)
                    ForEach(leftovers) { l in
                        HStack {
                            Toggle("", isOn: Binding(get: { chosenLeftovers.contains(l.path) },
                                                     set: { on in if on { chosenLeftovers.insert(l.path) } else { chosenLeftovers.remove(l.path) } }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(l.kind).fontWeight(.medium)
                                    if l.isUserData { RiskBadge(risk: .review) }
                                    if l.system { SudoBadge() }
                                }
                                PathText(path: l.path)
                            }
                            Spacer()
                            Button { model.reveal(l.path) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                            SizeText(bytes: l.bytes)
                        }
                    }
                }
                .card()
                Picker("Matching", selection: Binding(get: { model.settings.leftoverLevel }, set: { level in
                    model.settings.leftoverLevel = level
                    model.settings.save()
                    Task { leftovers = await model.leftovers(for: app) }
                })) {
                    Text("Strict").tag(MatchLevel.strict)
                    Text("Enhanced").tag(MatchLevel.enhanced)
                    Text("Deep").tag(MatchLevel.deep)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
            .padding(18)
        }
    }

    // MARK: Orphans

    private var orphansPane: some View {
        ModuleScroll {
            HeroHeader(title: "Orphaned files", value: Format.bytes(model.orphans.filter { chosenOrphans.contains($0.path) }.reduce(0) { $0 + $1.bytes }),
                       caption: "Leftovers from apps you deleted long ago", symbol: "questionmark.folder") {
                HStack {
                    Button("Find") { Task { await model.findOrphans() } }.disabled(model.busy != nil)
                    Button("Move to Trash") { model.confirmOrphans(model.orphans.filter { chosenOrphans.contains($0.path) }) }
                        .buttonStyle(.polish).disabled(chosenOrphans.isEmpty)
                }
            }
            Label("Only reverse-DNS names (com.vendor.app) that no installed app — or anything Spotlight can find — claims. Nothing is pre-selected; everything goes to the Trash.",
                  systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            if !model.orphans.isEmpty {
                VStack(spacing: 2) {
                    ForEach(model.orphans) { o in
                        HStack {
                            Toggle("", isOn: Binding(get: { chosenOrphans.contains(o.path) },
                                                     set: { on in if on { chosenOrphans.insert(o.path) } else { chosenOrphans.remove(o.path) } }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.kind).fontWeight(.medium)
                                PathText(path: o.path)
                            }
                            Spacer()
                            Button { model.reveal(o.path) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                            SizeText(bytes: o.bytes)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .card()
            }
        }
    }
}
