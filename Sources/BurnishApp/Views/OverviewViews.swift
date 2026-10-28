import SwiftUI
import BurnishCore

// MARK: - Health (Sensei / Stats)

struct HealthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleScroll {
            if let h = model.health {
                HStack(spacing: 22) {
                    ScoreRing(score: h.score, size: 120)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.machine.name).font(.title2.weight(.bold))
                        Text("\(h.machine.chip) · \(h.machine.model) · macOS \(h.machine.osVersion) · \(Format.bytes(h.machine.memoryBytes)) memory")
                            .foregroundStyle(.secondary)
                        Text("Up \(Int(h.uptimeSeconds / 86_400)) days · thermal \(h.thermal)").foregroundStyle(.secondary)
                        ForEach(h.notes, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(Theme.review) }
                    }
                    Spacer()
                    Button("Refresh") { Task { await model.refreshHealth() } }
                }
                .card(padding: 22)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    metric("Storage", "internaldrive", [
                        ("Available", Format.bytes(h.disk.availableBytes)),
                        ("Of which purgeable", Format.bytes(h.disk.purgeableBytes)),
                        ("Capacity", Format.bytes(h.disk.totalBytes)),
                        ("Local snapshots", "\(h.disk.localSnapshots)"),
                        ("SSD SMART", h.disk.smartStatus ?? "n/a"),
                    ], fraction: h.disk.usedFraction)
                    metric("Memory", "memorychip", [
                        ("Pressure", h.memory.pressure),
                        ("Kernel free level", h.memory.freePercent.map { "\($0)%" } ?? "?"),
                        ("Swap used", Format.bytes(h.memory.swapUsedBytes)),
                        ("Installed", Format.bytes(h.memory.totalBytes)),
                    ], fraction: h.memory.freePercent.map { 1 - Double($0) / 100 })
                    if let b = h.battery {
                        metric("Battery", "battery.100percent", [
                            ("Health", b.healthPercent.map { "\($0)%" } ?? "?"),
                            ("Cycles", "\(b.cycleCount)"),
                            ("Condition", b.condition ?? "?"),
                            ("Charging", b.charging ? "Yes" : "No"),
                        ], fraction: b.healthPercent.map { Double($0) / 100 })
                    }
                    metric("Security", "lock.shield", [
                        ("System Integrity Protection", onOff(h.security.sip)),
                        ("Gatekeeper", onOff(h.security.gatekeeper)),
                        ("FileVault", onOff(h.security.fileVault)),
                        ("Firewall", onOff(h.security.firewall)),
                        ("XProtect", h.security.xprotectVersion ?? "?"),
                        ("Full Disk Access for Burnish", h.security.fullDiskAccess ? "Granted" : "Missing"),
                    ], fraction: nil)
                    metric("CPU", "cpu", [
                        ("Load (1/5/15 min)", h.load.map { String(format: "%.2f", $0) }.joined(separator: " · ")),
                        ("Cores", "\(ProcessInfo.processInfo.activeProcessorCount)"),
                        ("Thermal state", h.thermal),
                    ], fraction: nil)
                }
                if !h.security.fullDiskAccess {
                    HStack {
                        Label("Without Full Disk Access, Mail, Safari, other apps' containers and the Trash can't be scanned.", systemImage: "hand.raised")
                        Spacer()
                        Button("Open Settings") { model.openFullDiskAccessSettings() }.buttonStyle(.polish)
                    }
                    .card()
                }
            } else {
                EmptyState(symbol: "heart.text.square", title: "Checking…", message: "Disk, memory, battery, thermals and security posture.").card()
            }
        }
        .navigationTitle("Health")
        .task { if model.health == nil { await model.refreshHealth() } }
    }

    private func onOff(_ v: Bool?) -> String { v.map { $0 ? "On" : "Off" } ?? "Unknown" }

    private func metric(_ title: String, _ symbol: String, _ rows: [(String, String)], fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1)).tint(fraction > 0.9 ? Theme.risky : Theme.azure)
            }
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).monospacedDigit()
                        .foregroundStyle(row.1 == "Off" || row.1 == "Missing" ? Theme.risky : .primary)
                }
                .font(.callout)
            }
        }
        .card()
    }
}

// MARK: - Fleet

struct FleetView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Fleet", value: "\(model.fleet.count) Mac\(model.fleet.count == 1 ? "" : "s")",
                       caption: "Synced through \(Paths.abbreviate(model.settings.resolvedFleetFolder))", symbol: "macbook.and.iphone") {
                HStack {
                    Button("Change folder…") { chooseFolder() }
                    Button("Publish this Mac") { Task { await model.publishFleet(); model.report("Published \(model.machine.name)") } }
                        .buttonStyle(.polish)
                }
            }
            if model.fleet.isEmpty {
                EmptyState(symbol: "macbook.and.iphone", title: "Add your other Macs",
                           message: "Install Burnish on each Mac and point it at the same synced folder (iCloud Drive by default). On a work Mac without your personal iCloud, pick any folder that syncs — Dropbox, Google Drive, OneDrive or a network share.").card()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                ForEach(model.fleet) { snap in FleetCard(snap: snap, isThisMac: snap.machine.machineID == model.machine.machineID) }
            }
        }
        .navigationTitle("Fleet")
        .task { await model.publishFleet() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.fleetFolder = url.path
            model.settings.save()
            Task { await model.publishFleet() }
        }
    }
}

struct FleetCard: View {
    var snap: FleetSnapshot
    var isThisMac: Bool

    var body: some View {
        let used = snap.diskTotal > 0 ? 1 - Double(snap.diskAvailable) / Double(snap.diskTotal) : 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "laptopcomputer").font(.title).foregroundStyle(Theme.polish)
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(snap.machine.name).font(.headline)
                        if isThisMac { Text("This Mac").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1).background(.quaternary, in: Capsule()) }
                    }
                    Text("\(snap.machine.chip) · macOS \(snap.machine.osVersion)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let score = snap.healthScore { ScoreRing(score: score, size: 54) }
            }
            HStack(spacing: 6) {
                Text(snap.machine.isAdmin ? "Admin" : "Standard")
                    .font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
                    .foregroundStyle(snap.machine.isAdmin ? Theme.safe : Theme.review)
                    .background((snap.machine.isAdmin ? Theme.safe : Theme.review).opacity(0.14), in: Capsule())
                if snap.sudoEnabled { SudoBadge() }
                if snap.isStale { Text("stale").font(.caption2).foregroundStyle(.secondary) }
            }
            ProgressView(value: used).tint(used > 0.9 ? Theme.risky : Theme.azure)
            HStack {
                Text("\(Format.bytes(snap.diskAvailable)) free of \(Format.bytes(snap.diskTotal))").font(.caption)
                Spacer()
                Text("\(snap.reclaimableBytes.map(Format.bytes) ?? "?") reclaimable").font(.caption).foregroundStyle(Theme.azure)
            }
            Text("Updated \(Format.relative(snap.updatedAt))\(snap.lastClean.map { " · cleaned " + Format.relative($0) } ?? "") · freed \(Format.bytes(snap.totalFreed)) all-time")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "History", value: Format.bytes(model.history.reduce(0) { $0 + $1.bytes }),
                       caption: "freed on this Mac · every removal is logged with its paths", symbol: "clock.arrow.circlepath") {
                Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.expand("~/.Trash"))) }
            }
            if model.history.isEmpty {
                EmptyState(symbol: "clock", title: "Nothing yet", message: "Cleanups, uninstalls, purges and tweaks appear here.").card()
            }
            ForEach(model.history) { entry in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entry.paths.prefix(100), id: \.self) { PathText(path: $0) }
                        ForEach(entry.errors.prefix(20), id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.risky) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack {
                        Text(entry.action.capitalized).fontWeight(.medium).frame(width: 90, alignment: .leading)
                        Text(entry.detail).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        if entry.trashed > 0 { Text("\(entry.trashed) in Trash").font(.caption).foregroundStyle(.secondary) }
                        if entry.bytes > 0 { SizeText(bytes: entry.bytes) }
                        Text(Format.relative(entry.date)).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    }
                }
                .card(padding: 12)
            }
        }
        .navigationTitle("History")
        .onAppear { model.loadHistory() }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newRoot = ""
    @State private var newIgnore = ""

    var body: some View {
        Form {
            Section("Safety") {
                Toggle("Always use the Trash (even for caches)", isOn: binding(\.alwaysUseTrash))
                Toggle("Watch the Trash for uninstalled apps", isOn: Binding(get: { model.settings.trashSentinel }, set: { on in
                    model.settings.trashSentinel = on
                    model.settings.save()
                    if on { model.sentinel.start() } else { model.sentinel.stop() }
                }))
                Picker("Leftover matching", selection: binding(\.leftoverLevel)) {
                    Text("Strict").tag(MatchLevel.strict)
                    Text("Enhanced").tag(MatchLevel.enhanced)
                    Text("Deep").tag(MatchLevel.deep)
                }
                listEditor("Never touch", items: model.settings.ignorePaths, text: $newIgnore) { model.settings.ignorePaths = $0 }
            }
            Section("Dev Purge") {
                Stepper("Skip projects active in the last \(model.settings.purgeMinAgeDays) days", value: binding(\.purgeMinAgeDays), in: 0...90)
                listEditor("Project roots", items: model.settings.purgeRoots, text: $newRoot) { model.settings.purgeRoots = $0 }
            }
            Section("Space Lens") {
                Stepper("Large file threshold: \(model.settings.largeFileMinMB) MB", value: binding(\.largeFileMinMB), in: 50...10_000, step: 50)
                Stepper("Old = not opened in \(model.settings.oldFileDays) days", value: binding(\.oldFileDays), in: 30...1_000, step: 30)
            }
            Section("Schedule") {
                Picker("Automatic safe clean", selection: Binding(get: { model.settings.schedule }, set: { schedule in
                    model.settings.schedule = schedule
                    model.settings.save()
                    let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/burnish").path
                    do { try Scheduler.install(schedule, cliPath: cli) } catch { model.report(error.localizedDescription, error: true) }
                })) {
                    Text("Off").tag(Schedule.off)
                    Text("Daily").tag(Schedule.daily)
                    Text("Weekly").tag(Schedule.weekly)
                }
                Text("Runs as you via a LaunchAgent — no admin needed, never uses sudo, only items marked safe.").font(.caption).foregroundStyle(.secondary)
            }
            Section("This Mac") {
                LabeledContent("Account", value: "\(model.machine.userName) · \(model.machine.isAdmin ? "Administrator" : "Standard")")
                LabeledContent("Fleet folder", value: Paths.abbreviate(model.settings.resolvedFleetFolder))
                Button("Grant Full Disk Access…") { model.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<T>(_ key: WritableKeyPath<BurnishCore.Settings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: key] }, set: { value in
            model.settings[keyPath: key] = value
            model.settings.save()
        })
    }

    private func listEditor(_ title: String, items: [String], text: Binding<String>, update: @escaping ([String]) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item).font(Theme.mono)
                    Spacer()
                    Button { update(items.filter { $0 != item }); model.settings.save() } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("~/path", text: text)
                Button("Add") {
                    let value = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { return }
                    update(items + [value])
                    model.settings.save()
                    text.wrappedValue = ""
                }
            }
        }
    }
}

// MARK: - Menu bar extra

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ScoreRing(score: model.health?.score ?? 0, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.machine.name).font(.headline)
                    if let d = model.health?.disk {
                        Text("\(Format.bytes(d.availableBytes)) free").font(.callout)
                    }
                    if let m = model.health?.memory {
                        Text("Memory: \(m.pressure)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let smart = model.smart {
                Text("\(Format.bytes(smart.quickWinBytes)) ready to clean").foregroundStyle(Theme.azure)
            }
            HStack {
                Button("Smart Scan") { Task { await model.runSmartScan() } }.disabled(model.busy != nil)
                Button("Burnish now") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    model.selection = .smartScan
                    model.burnishNow()
                }
                .buttonStyle(.polish)
                .disabled(model.smart == nil || model.busy != nil)
            }
            if let busy = model.busy { Text(busy).font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button("Open Burnish") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .task { if model.health == nil { await model.refreshHealth() } }
    }
}
