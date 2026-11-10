import SwiftUI
import SpruceCore

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = 0
    @State private var query = ""
    @State private var sort = 0
    /// The app whose row is open, showing its files.
    @State private var selectedApp: InstalledApp?
    @State private var leftovers: [Leftover] = []
    @State private var traces: [UninstallTrace] = []
    @State private var chosenLeftovers = Set<String>()
    @State private var chosenOrphans = Set<String>()
    @State private var loadingDetail = false
    /// Apps ticked for removal, by path.
    @State private var picked = Set<String>()
    @State private var preparing = false

    private var filteredApps: [InstalledApp] {
        let list = model.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
        switch sort {
        case 1: return list.sorted { $0.bytes > $1.bytes }
        case 2: return list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        default: return list
        }
    }

    private var pickedApps: [InstalledApp] { model.apps.filter { picked.contains($0.path) } }

    var body: some View {
        VStack(spacing: 12) {
            PillPicker(selection: $mode, options: [(0, "Applications", "square.grid.2x2"), (1, "Orphaned files", "questionmark.folder")])
            if mode == 0 { appsPane.transition(.opacity) } else { orphansPane.transition(.opacity) }
        }
        .animation(Theme.spring, value: mode)
        .navigationTitle("Uninstaller")
        .task {
            if model.apps.isEmpty { await model.loadApps() }
            takeFocus()
        }
        .onChange(of: model.uninstallFocus) { takeFocus() }
        .onChange(of: model.tourSubpage) { _, page in
            if page == "orphans" {
                mode = 1
                Task { await model.findOrphans() }
            }
        }
    }

    /// An app picked in the menu bar panel opens here, expanded.
    private func takeFocus() {
        guard let app = model.uninstallFocus else { return }
        model.uninstallFocus = nil
        mode = 0
        query = ""
        selectedApp = model.apps.first { $0.path == app.path } ?? app
    }

    // MARK: Apps

    private var appsPane: some View {
        VStack(spacing: 10) {
            appsToolbar
            if let verdict = model.verdict {
                VerdictCard(verdict: verdict)
                    .overlay(alignment: .topTrailing) {
                        IconButton(symbol: "xmark", help: "Dismiss") { withAnimation(Theme.snappy) { model.verdict = nil } }
                            .padding(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.apps.isEmpty {
                            HStack(spacing: 10) { GradientSpinner(); Text("Reading your Applications folders…").foregroundStyle(.secondary) }
                                .padding(.vertical, 40)
                        } else if filteredApps.isEmpty {
                            Text("No app matches \u{201C}\(query)\u{201D}").foregroundStyle(.secondary).padding(.vertical, 40)
                        }
                        ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { RowDivider(inset: 50) }
                            appRow(app).id(app.path)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .surface()
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: selectedApp?.path) { _, path in
                    guard let path else { return }
                    withAnimation(Theme.spring) { proxy.scrollTo(path, anchor: .top) }
                }
            }
            removalBar
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 18)
        .onChange(of: selectedApp) { load() }
        .onChange(of: model.apps) {
            // After an uninstall the app disappears from the list; close its row and untick it.
            let paths = Set(model.apps.map(\.path))
            picked = picked.intersection(paths)
            if let app = selectedApp, !paths.contains(app.path) { selectedApp = nil }
        }
    }

    private var appsToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.chipFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .frame(maxWidth: 360)
            PillPicker(selection: $sort, options: [(0, "Name", nil), (1, "Size", nil), (2, "Least used", nil)])
                .fixedSize()
            Spacer()
            Text("\(model.apps.count) apps · \(Format.bytes(model.apps.reduce(0) { $0 + $1.bytes }))")
                .font(Theme.mono(11)).foregroundStyle(.secondary)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let open = selectedApp?.path == app.path
        let ticked = picked.contains(app.path)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(Theme.snappy) {
                        if ticked { picked.remove(app.path) } else { picked.insert(app.path) }
                    }
                } label: {
                    Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ticked ? AnyShapeStyle(Module.uninstaller.accent) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!app.canUninstall)
                .help(app.canUninstall ? (ticked ? "Don't remove \(app.name)" : "Select \(app.name) for removal") : "Part of macOS")

                Button {
                    SoundFX.shared.play(.select)
                    withAnimation(Theme.spring) { selectedApp = open ? nil : app }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .frame(width: 12)
                        Image(nsImage: FileIcon.image(app.path)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(app.name).font(Theme.sans(13, .medium)).lineLimit(1)
                                if app.isAppStore { Chip(text: "App Store", color: Theme.spruce, symbol: "bag") }
                                if !app.userRemovable { SudoBadge() }
                            }
                            Text("v\(app.version) · \(app.lastUsed.map { "used \(Format.relative($0))" } ?? "never opened")")
                                .font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        SizeText(bytes: app.bytes).frame(minWidth: 70, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 7)
            .rowHover()

            if open {
                appDetail(app)
                    .padding(.leading, 46).padding(.bottom, 12).padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Ticked apps, their total, and one Remove for all of them.
    private var removalBar: some View {
        let apps = pickedApps
        let total = apps.reduce(Int64(0)) { sum, app in
            sum + app.bytes + (app.path == selectedApp?.path
                ? leftovers.filter { chosenLeftovers.contains($0.path) }.reduce(0) { $0 + $1.bytes } : 0)
        }
        let complete = model.settings.uninstallCompletely
        return HStack(spacing: 12) {
            Image(systemName: apps.isEmpty ? "hand.tap" : "checkmark.circle.fill")
                .foregroundStyle(apps.isEmpty ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(Module.uninstaller.accent))
            Text(apps.isEmpty ? "Tick apps to remove several at once, or open one to see its files"
                 : "\(apps.count) selected · \(Format.bytes(total))\(apps.count == 1 ? "" : " plus their files")")
                .font(Theme.mono(11)).foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            if !apps.isEmpty {
                Button("Clear") { withAnimation(Theme.snappy) { picked = [] } }
            }
            Button {
                Task { await removePicked() }
            } label: {
                if preparing { ProgressView().controlSize(.small) }
                else { Label(complete ? "Remove Completely" : "Remove", systemImage: complete ? "flame.fill" : "trash") }
            }
            .buttonStyle(.danger)
            .disabled(apps.isEmpty || preparing || model.busy != nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .surface()
    }

    /// Builds one receipt for every ticked app. The open app keeps the files chosen in its row;
    /// the others get the usual selection.
    private func removePicked() async {
        let apps = pickedApps.filter(\.canUninstall)
        guard !apps.isEmpty else { return }
        preparing = true
        defer { preparing = false }
        let complete = model.settings.uninstallCompletely
        var plans: [UninstallPlan] = []
        for app in apps {
            if app.path == selectedApp?.path && !loadingDetail {
                plans.append(UninstallPlan(app: app, leftovers: leftovers.filter { chosenLeftovers.contains($0.path) },
                                           traces: complete ? traces : []))
            } else {
                let found = await model.leftovers(for: app).filter { complete || !$0.isUserData }
                let appTraces = complete ? await model.traces(for: app, leftovers: found) : []
                plans.append(UninstallPlan(app: app, leftovers: found, traces: appTraces))
            }
        }
        model.confirmUninstall(plans)
    }

    private func load() {
        guard let app = selectedApp else { return }
        loadingDetail = true
        leftovers = []
        traces = []
        Task {
            let found = await model.leftovers(for: app)
            guard selectedApp?.path == app.path else { return }
            leftovers = found
            chosenLeftovers = Set(found.filter { model.settings.uninstallCompletely || !$0.isUserData }.map(\.path))
            traces = model.settings.uninstallCompletely ? await model.traces(for: app, leftovers: found) : []
            loadingDetail = false
        }
    }

    /// The open row: the app's files outside its bundle, what else gets cleared, and how hard to look.
    private func appDetail(_ app: InstalledApp) -> some View {
        let complete = model.settings.uninstallCompletely
        let total = app.bytes + leftovers.filter { chosenLeftovers.contains($0.path) }.reduce(0) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(app.bundleID).font(Theme.mono(11)).foregroundStyle(.tertiary).textSelection(.enabled).lineLimit(1)
                Spacer()
                IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(app.path) }
                Button {
                    model.confirmUninstall(app, leftovers: leftovers.filter { chosenLeftovers.contains($0.path) },
                                           traces: complete ? traces : [])
                } label: {
                    Text(complete ? "Remove \(Format.bytes(total)) Completely" : "Uninstall \(Format.bytes(total))")
                }
                .buttonStyle(.danger)
                .controlSize(.small)
                .disabled(!app.canUninstall || loadingDetail || model.busy != nil)
            }

            if !app.canUninstall {
                InfoNote(text: "\(app.name) is part of macOS and can't be removed.", symbol: "apple.logo")
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(title: "Files outside the app", symbol: "doc.on.doc",
                             trailing: loadingDetail ? nil : "\(leftovers.count)")
                if loadingDetail {
                    HStack(spacing: 10) { GradientSpinner(); Text("Searching 60+ locations…").foregroundStyle(.secondary) }
                        .padding(.vertical, 8)
                } else if leftovers.isEmpty {
                    Label("Nothing outside the bundle", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.safe)
                        .padding(.vertical, 4)
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

            if complete && !traces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: "Traces that aren't files", symbol: "wand.and.stars", trailing: "\(traces.count)")
                    ForEach(Array(traces.enumerated()), id: \.element.id) { index, t in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: t.symbol).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary).frame(width: 20)
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
            }

            HStack(alignment: .top, spacing: 16) {
                Toggle(isOn: Binding(get: { model.settings.uninstallCompletely }, set: { on in
                    model.settings.uninstallCompletely = on
                    model.settings.save()
                    load()
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove completely").fontWeight(.medium)
                        Text(complete
                             ? "Deletes the app and every file it made, and clears background jobs, privacy permissions, Login Items, the Dock tile and installer receipts. Then rescans to prove it's gone."
                             : "Moves the app to the Trash and keeps its personal data unless you tick it.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(GlowSwitchStyle(tint: Module.uninstaller.gradient))
                Spacer(minLength: 8)
                PillPicker(selection: Binding(get: { model.settings.leftoverLevel }, set: { level in
                    model.settings.leftoverLevel = level
                    model.settings.save()
                    load()
                }), options: [(MatchLevel.strict, "Strict", nil), (MatchLevel.enhanced, "Enhanced", nil), (MatchLevel.deep, "Deep", nil)])
                .fixedSize()
                .help("How hard to look. Deep also matches the vendor's name, team ID and ~/.dotfolders.")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
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
                        .buttonStyle(.brand).disabled(chosenOrphans.isEmpty)
                }
            }
            InfoNote(text: "Only reverse-DNS names (com.vendor.app) that no installed app — or anything Spotlight can find — claims. Nothing is pre-selected; everything goes to the Trash.")
            if !model.orphans.isEmpty {
                VStack(spacing: 2) {
                    orphanSelectionBar
                    RowDivider(inset: 0).padding(.vertical, 4)
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

extension UninstallerView {
    /// "Select All" above the orphaned files: a checkbox that selects or clears every row, with a
    /// count of what's chosen.
    fileprivate var orphanSelectionBar: some View {
        let all = Set(model.orphans.map(\.path))
        let allChosen = !all.isEmpty && all.isSubset(of: chosenOrphans)
        let chosen = model.orphans.filter { chosenOrphans.contains($0.path) }
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { allChosen }, set: { on in
                withAnimation(Theme.snappy) { chosenOrphans = on ? all : [] }
            })) {
                Text(allChosen ? "Deselect All" : "Select All").fontWeight(.medium)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help(allChosen ? "Clear every row (⇧⌘A)" : "Select every orphaned file (⇧⌘A)")
            Spacer()
            Text(chosen.isEmpty ? "\(model.orphans.count) found"
                 : "\(chosen.count) of \(model.orphans.count) selected · \(Format.bytes(chosen.reduce(0) { $0 + $1.bytes }))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 2)
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
                    .font(.system(.headline)).foregroundStyle(Theme.safe)
            } else {
                Label("\(verdict.remaining.count) item(s) of \(verdict.app) remain", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.headline)).foregroundStyle(Theme.review)
                Text(model.sudo || !verdict.remaining.contains(where: \.system)
                     ? "These were in use or protected. Quit anything related and try again, or remove them from Finder."
                     : "These are system-level. Turn on Admin mode and uninstall again to finish the job.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(verdict.remaining.prefix(8)) { l in PathText(path: l.path) }
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.rim.opacity(0.05)))
    }
}
