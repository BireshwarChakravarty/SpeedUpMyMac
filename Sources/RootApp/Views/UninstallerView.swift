import SwiftUI
import RootCore

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var query = ""
    @State private var sort = 0
    @State private var selectedApp: InstalledApp?
    @State private var leftovers: [Leftover] = []
    @State private var traces: [UninstallTrace] = []
    @State private var chosenLeftovers = Set<String>()
    @State private var chosenOrphans = Set<String>()
    @State private var loadingDetail = false

    private var filteredApps: [InstalledApp] {
        let list = model.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
        switch sort {
        case 1: return list.sorted { $0.bytes > $1.bytes }
        case 2: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        default: return list
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            PillPicker(selection: $mode, options: [(0, "Applications", "square.grid.2x2"), (1, "Orphaned files", "questionmark.folder")])
            if mode == 0 { appsPane.transition(.opacity) } else { orphansPane.transition(.opacity) }
        }
        .animation(Theme.spring, value: mode)
        .navigationTitle("Uninstaller")
        .task { if model.apps.isEmpty { await model.loadApps() } }
    }

    // MARK: Apps

    private var appsPane: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search apps", text: $query).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.rim.opacity(0.07)))
                    Menu {
                        Picker("Sort", selection: $sort) {
                            Text("Name").tag(0)
                            Text("Size").tag(1)
                            Text("Least used").tag(2)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28)
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredApps) { app in
                            AppRow(app: app, selected: selectedApp?.path == app.path) {
                                SoundFX.shared.play(.select)
                                withAnimation(Theme.spring) { selectedApp = app }
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
            .padding(12)
            .frame(width: 340)
            .glassCard()

            Group {
                if let app = selectedApp {
                    appDetail(app).id(app.path).transition(.moduleSwap)
                } else {
                    VStack {
                        EmptyState(symbol: "xmark.app", title: "Pick an app",
                                   message: "Root finds its caches, preferences, containers, launch agents, helpers, crash reports, package receipts and command-line links — then removes it completely, so nothing comes back. Drag an app to the Trash and Root will notice, too.")
                        if let verdict = model.verdict { VerdictCard(verdict: verdict) }
                    }
                    .card()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.spring, value: selectedApp?.path)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
        .onChange(of: selectedApp) { load() }
        .onChange(of: model.apps) {
            // After an uninstall the app disappears from the list; clear the detail pane.
            if let app = selectedApp, !model.apps.contains(where: { $0.path == app.path }) { selectedApp = nil }
        }
    }

    private func load() {
        guard let app = selectedApp else { return }
        loadingDetail = true
        Task {
            let found = await model.leftovers(for: app)
            leftovers = found
            chosenLeftovers = Set(found.filter { model.settings.uninstallCompletely || !$0.isUserData }.map(\.path))
            traces = model.settings.uninstallCompletely ? await model.traces(for: app, leftovers: found) : []
            loadingDetail = false
        }
    }

    private func appDetail(_ app: InstalledApp) -> some View {
        let complete = model.settings.uninstallCompletely
        let total = app.bytes + leftovers.filter { chosenLeftovers.contains($0.path) }.reduce(0) { $0 + $1.bytes }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Module.uninstaller.gradient).blur(radius: 26).opacity(0.5).frame(width: 80, height: 80)
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(Theme.title)
                        Text("\(app.version) · \(app.bundleID)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack(spacing: 6) {
                            if app.isAppStore { Chip(text: "App Store", color: Theme.leaf, symbol: "bag") }
                            if !app.userRemovable { SudoBadge() }
                            Text(app.lastUsed.map { "Used \(Format.relative($0))" } ?? "Never opened").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        CountingBytes(bytes: total, duration: 0.7).font(Theme.heroSmall)
                        Button {
                            model.confirmUninstall(app, leftovers: leftovers.filter { chosenLeftovers.contains($0.path) },
                                                   traces: complete ? traces : [])
                        } label: {
                            Label(complete ? "Remove Completely" : "Uninstall", systemImage: complete ? "flame.fill" : "trash")
                        }
                        .buttonStyle(.danger)
                        .disabled(!app.canUninstall || loadingDetail)
                    }
                }
                .card()

                if !app.canUninstall {
                    InfoNote(text: "\(app.name) is part of macOS and can't be removed.", symbol: "apple.logo")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(get: { model.settings.uninstallCompletely }, set: { on in
                        model.settings.uninstallCompletely = on
                        model.settings.save()
                        load()
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove completely — leave no trace").font(.system(.headline, design: .monospaced))
                            Text(complete
                                 ? "Deletes the app and every file it made, including its data and settings, and clears background jobs, privacy permissions, Login Items, the Dock tile and installer receipts. Then rescans to prove it's gone."
                                 : "Moves the app to the Trash and keeps its personal data (Application Support, containers) unless you tick it.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(GlowSwitchStyle(tint: Module.uninstaller.gradient))
                    PillPicker(selection: Binding(get: { model.settings.leftoverLevel }, set: { level in
                        model.settings.leftoverLevel = level
                        model.settings.save()
                        load()
                    }), options: [(MatchLevel.strict, "Strict", nil), (MatchLevel.enhanced, "Enhanced", nil), (MatchLevel.deep, "Deep", nil)])
                    .help("How hard to look. Deep also matches the vendor's name, team ID and ~/.dotfolders.")
                }
                .card()

                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: "Files outside the app", symbol: "doc.on.doc",
                                 trailing: loadingDetail ? nil : "\(leftovers.count)")
                    if loadingDetail {
                        HStack(spacing: 10) { GradientSpinner(); Text("Searching 60+ locations…").foregroundStyle(.secondary) }
                            .padding(.vertical, 8)
                    } else if leftovers.isEmpty {
                        Label("Nothing outside the bundle", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.safe)
                    }
                    ForEach(Array(leftovers.enumerated()), id: \.element.id) { index, l in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { chosenLeftovers.contains(l.path) },
                                                     set: { on in if on { chosenLeftovers.insert(l.path) } else { chosenLeftovers.remove(l.path) } }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(l.kind).fontWeight(.medium)
                                    if l.isUserData { Chip(text: "personal data", color: Theme.review, symbol: nil) }
                                    if l.system { SudoBadge() }
                                }
                                PathText(path: l.path)
                            }
                            Spacer()
                            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(l.path) }
                            SizeText(bytes: l.bytes).frame(width: 74, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                        .rowHover()
                        .reveal(index: index, step: 0.025)
                    }
                }
                .card()

                if complete && !traces.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Traces that aren't files", symbol: "wand.and.stars", trailing: "\(traces.count)")
                        ForEach(Array(traces.enumerated()), id: \.element.id) { index, t in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: t.symbol).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Module.uninstaller.gradient).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(t.title).fontWeight(.medium)
                                        if t.needsAdmin { SudoBadge() }
                                    }
                                    Text(t.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .rowHover()
                            .reveal(index: index, step: 0.03)
                        }
                    }
                    .card()
                }
            }
            .padding(.bottom, 80)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: Orphans

    private var orphansPane: some View {
        ModuleScroll {
            HeroHeader(title: "Orphaned files", value: Format.bytes(model.orphans.filter { chosenOrphans.contains($0.path) }.reduce(0) { $0 + $1.bytes }),
                       caption: "Leftovers from apps you deleted long ago", symbol: "questionmark.folder") {
                HStack {
                    Button("Find") { Task { await model.findOrphans() } }.disabled(model.busy != nil)
                    Button("Move to Trash") { model.confirmOrphans(model.orphans.filter { chosenOrphans.contains($0.path) }) }
                        .buttonStyle(.brand).disabled(chosenOrphans.isEmpty)
                }
            }
            InfoNote(text: "Only reverse-DNS names (com.vendor.app) that no installed app — or anything Spotlight can find — claims. Nothing is pre-selected; everything goes to the Trash.")
            if !model.orphans.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(model.orphans.enumerated()), id: \.element.id) { index, o in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { chosenOrphans.contains(o.path) },
                                                     set: { on in if on { chosenOrphans.insert(o.path) } else { chosenOrphans.remove(o.path) } }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.kind).fontWeight(.medium)
                                PathText(path: o.path)
                            }
                            Spacer()
                            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(o.path) }
                            SizeText(bytes: o.bytes)
                        }
                        .padding(.vertical, 3)
                        .rowHover()
                        .reveal(index: index)
                    }
                }
                .card()
            }
        }
    }
}

private struct AppRow: View {
    var app: InstalledApp
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 30, height: 30)
                    .scaleEffect(hovering ? 1.1 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).lineLimit(1).fontWeight(selected ? .semibold : .regular)
                    Text(app.lastUsed.map { "Used \(Format.relative($0))" } ?? "Never opened")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !app.userRemovable { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.sudo).help("Needs Sudo mode") }
                Text(Format.bytes(app.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? AnyShapeStyle(Module.uninstaller.wash(0.28)) : AnyShapeStyle(Theme.rim.opacity(hovering ? 0.06 : 0))))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.rimGradient, lineWidth: selected ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
    }
}

/// The result of the post-uninstall rescan.
struct VerdictCard: View {
    @Environment(AppModel.self) private var model
    var verdict: UninstallVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if verdict.remaining.isEmpty {
                Label("\(verdict.app) is gone — verified, no trace left", systemImage: "checkmark.seal.fill")
                    .font(.system(.headline, design: .monospaced)).foregroundStyle(Theme.safe)
            } else {
                Label("\(verdict.remaining.count) item(s) of \(verdict.app) remain", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.headline, design: .monospaced)).foregroundStyle(Theme.review)
                Text(model.sudo || !verdict.remaining.contains(where: \.system)
                     ? "These were in use or protected. Quit anything related and try again, or remove them from Finder."
                     : "These are system-level. Turn on Sudo mode and uninstall again to finish the job.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(verdict.remaining.prefix(8)) { l in PathText(path: l.path) }
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.rim.opacity(0.05)))
    }
}
