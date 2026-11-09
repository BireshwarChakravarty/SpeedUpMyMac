import SwiftUI
import SpruceCore
import UniformTypeIdentifiers

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
                    Button("Refresh") {
                        SoundFX.shared.play(.whoosh)
                        Task { await model.refreshHealth() }
                    }
                }
                .card(padding: 22)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], spacing: 16) {
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
                        ("Full Disk Access for Spruce", h.security.fullDiskAccess ? "Granted" : "Missing"),
                    ], fraction: nil)
                    metric("CPU", "cpu", [
                        ("Load (1/5/15 min)", h.load.map { String(format: "%.2f", $0) }.joined(separator: " · ")),
                        ("Cores", "\(ProcessInfo.processInfo.activeProcessorCount)"),
                        ("Thermal state", h.thermal),
                    ], fraction: nil)
                }
                if !h.security.fullDiskAccess {
                    HStack {
                        Label("Without Full Disk Access, Mail, Safari, other apps' containers and the Trash can't be scanned.", systemImage: "hand.raised.fill")
                            .foregroundStyle(Theme.review)
                        Spacer()
                        Button("Open Settings") { model.openFullDiskAccessSettings() }.buttonStyle(.brand)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: title, symbol: symbol, trailing: nil)
                if let fraction {
                    Text("\(Int((min(max(fraction, 0), 1) * 100).rounded()))%")
                        .font(.system(.title3).weight(.bold).monospacedDigit())
                        .foregroundStyle(fraction > 0.9 ? AnyShapeStyle(Theme.risky) : AnyShapeStyle(Theme.accentText))
                }
            }
            if let fraction {
                GrowingBar(fraction: fraction, fill: fraction > 0.9 ? Theme.danger : Module.smartScan.barGradient, delay: 0.2, height: 7)
            }
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    if row.1 == "On" || row.1 == "Granted" {
                        Label(row.1, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.safe)
                    } else if row.1 == "Off" || row.1 == "Missing" {
                        Label(row.1, systemImage: "xmark.circle.fill").foregroundStyle(Theme.risky)
                    } else {
                        Text(row.1).monospacedDigit()
                    }
                }
                .font(.callout)
                .padding(.vertical, 1)
                .rowHover()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .hoverLift(scale: 1.01)
        .reveal(delay: 0.08)
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
                        .buttonStyle(.brand)
                }
            }
            if model.fleet.isEmpty {
                EmptyState(symbol: "macbook.and.iphone", title: "Add your other Macs",
                           message: "Install Spruce on each Mac and point it at the same synced folder (iCloud Drive by default). On a work Mac without your personal iCloud, pick any folder that syncs — Dropbox, Google Drive, OneDrive or a network share.").card()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(Array(model.fleet.enumerated()), id: \.element.id) { index, snap in
                    FleetCard(snap: snap, isThisMac: snap.machine.machineID == model.machine.machineID,
                              remove: { model.forgetFleetMachine(snap) })
                        .reveal(index: index, step: 0.08)
                }
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
    var remove: () -> Void = {}
    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        let used = snap.diskTotal > 0 ? 1 - Double(snap.diskAvailable) / Double(snap.diskTotal) : 0
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: snap.machine.model.lowercased().contains("book") ? "laptopcomputer" : "macmini")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Module.fleet.gradient))
                    .shadow(color: Module.fleet.tint.1.opacity(0.5), radius: 8, y: 4)
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(snap.machine.name).font(.headline)
                        if isThisMac { Chip(text: "This Mac", color: Theme.spruce, symbol: "location.fill") }
                    }
                    Text("\(snap.machine.chip) · macOS \(snap.machine.osVersion)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let score = snap.healthScore { ScoreRing(score: score, size: 54) }
            }
            .overlay(alignment: .topTrailing) {
                if !isThisMac && (hovering || confirming) {
                    Button { confirming = true } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.regularMaterial))
                            .overlay(Circle().strokeBorder(Theme.rimGradient, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 8, y: -8)
                    .help("Remove from Fleet")
                    .accessibilityLabel("Remove \(snap.machine.name) from the fleet")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            HStack(spacing: 6) {
                Chip(text: snap.machine.isAdmin ? "Admin" : "Standard", color: snap.machine.isAdmin ? Theme.safe : Theme.review,
                     symbol: snap.machine.isAdmin ? "person.badge.key.fill" : "person.fill")
                if snap.sudoEnabled { SudoBadge() }
                if snap.isStale { Chip(text: "stale", color: .secondary, symbol: "clock") }
            }
            GrowingBar(fraction: used, fill: used > 0.9 ? Theme.danger : Module.fleet.gradient, delay: 0.2, height: 7)
            HStack {
                Text("\(Format.bytes(snap.diskAvailable)) free of \(Format.bytes(snap.diskTotal))").font(.caption)
                Spacer()
                Text("\(snap.reclaimableBytes.map(Format.bytes) ?? "?") reclaimable").font(.caption).foregroundStyle(Theme.spruce)
            }
            Text("Updated \(Format.relative(snap.updatedAt))\(snap.lastClean.map { " · cleaned " + Format.relative($0) } ?? "") · freed \(Format.bytes(snap.totalFreed)) all-time")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .hoverLift()
        .onHover { on in withAnimation(Theme.snappy) { hovering = on } }
        .contextMenu {
            if isThisMac {
                Text("This Mac can't be removed while Spruce runs on it")
            } else {
                Button("Remove from Fleet", role: .destructive) { confirming = true }
            }
        }
        .confirmationDialog("Remove \(snap.machine.name) from the fleet?", isPresented: $confirming) {
            Button("Remove", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(snap.isStale
                 ? "Its card was last updated \(Format.relative(snap.updatedAt)). Nothing on that Mac changes; if it runs Spruce again, it adds itself back."
                 : "Nothing on that Mac changes. It adds itself back the next time it runs Spruce, so use this for Macs you no longer have and old duplicates.")
        }
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
            ForEach(Array(model.history.enumerated()), id: \.element.id) { index, entry in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(entry.paths.prefix(100), id: \.self) { PathText(path: $0) }
                        ForEach(entry.errors.prefix(20), id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.risky) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack {
                        Image(systemName: historySymbol(entry.action)).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary).frame(width: 18)
                        Text(entry.action.capitalized).fontWeight(.medium).frame(width: 90, alignment: .leading)
                        Text(entry.detail).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        if entry.trashed > 0 { Text("\(entry.trashed) in Trash").font(.caption).foregroundStyle(.secondary) }
                        if entry.bytes > 0 { SizeText(bytes: entry.bytes) }
                        Text(Format.relative(entry.date)).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
                .reveal(index: index, step: 0.03)
            }
        }
        .navigationTitle("History")
        .onAppear { model.loadHistory() }
    }

    private func historySymbol(_ action: String) -> String {
        switch action {
        case "uninstall": return "xmark.app"
        case "purge": return "hammer"
        case "orphans": return "questionmark.folder"
        case "optimize": return "wrench.and.screwdriver"
        case "smart": return "sparkles"
        case "autoclean": return "calendar.badge.clock"
        case "files": return "doc"
        default: return "trash.slash"
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newRoot = ""
    @State private var newIgnore = ""
    @AppStorage(SoundFX.enabledKey) private var soundOn = true
    @AppStorage(SoundFX.volumeKey) private var volume: Double = 0.55
    @AppStorage(reduceEffectsKey) private var reduceEffects = false
    @AppStorage(alwaysDarkKey) private var alwaysDark = true

    var body: some View {
        Form {
            if model.machine.isAdmin {
                Section("Admin access") {
                    Toggle("Use Touch ID instead of your password", isOn: Binding(
                        get: { model.touchIDForAdmin },
                        set: { on in model.setTouchIDForAdmin(on) }))
                        .disabled(!model.hasTouchID && !model.touchIDForAdmin)
                    Text(model.hasTouchID
                         ? "When Spruce needs admin rights, it asks for your fingerprint. If Touch ID isn't available (lid closed) or you cancel it, the password dialog appears instead. Also applies to sudo in Terminal."
                         : "No Touch ID sensor found. On a Mac mini or Mac Studio, connect a Magic Keyboard with Touch ID.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.touchIDSetupBlocked && !model.touchIDForAdmin {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("macOS blocked Spruce from writing /etc/pam.d/sudo_local, the file that turns on Touch ID for admin steps.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.review)
                            Text("Give Spruce Full Disk Access, quit and reopen it, then turn this on again. Or paste this in Terminal (it asks for your password once):")
                                .foregroundStyle(.secondary)
                            Text(Tweaks.touchIDTerminalCommand)
                                .font(Theme.code)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.rim.opacity(0.06)))
                            HStack {
                                Button("Open Full Disk Access") { model.openFullDiskAccessSettings() }
                                Button("Copy Command") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(Tweaks.touchIDTerminalCommand, forType: .string)
                                    model.report("Copied. Paste it in Terminal.")
                                }
                                Spacer()
                                Button("Check Again") { model.touchIDForAdmin = Tweaks.touchIDForSudoEnabled()
                                    if model.touchIDForAdmin { model.touchIDSetupBlocked = false; model.report("Touch ID is on") } }
                            }
                        }
                        .font(.caption)
                    }
                    if model.touchIDForAdmin {
                        HStack {
                            Button("Test Touch ID") { model.testTouchID() }.disabled(model.busy != nil)
                            Spacer()
                            Button("Show Log") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: Paths.expand("~/Library/Logs/Spruce/admin.log")))
                            }
                            .buttonStyle(.borderless)
                        }
                        if let result = model.touchIDTestResult {
                            Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(result.ok ? Theme.safe : Theme.review)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Look & Sound") {
                Toggle("Sound effects", isOn: $soundOn)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1, onEditingChanged: { editing in if !editing { SoundFX.shared.play(.success) } })
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .disabled(!soundOn)
                Toggle("Always use the dark theme", isOn: $alwaysDark)
                Toggle("Reduce visual effects (still orb, no particles)", isOn: $reduceEffects)
            }
            Section("Uninstaller") {
                Toggle("Remove apps completely — leave no trace", isOn: binding(\.uninstallCompletely))
                Text("Deletes the app, its data and settings outright, and clears its background jobs, privacy permissions, Login Items, Dock tile and installer receipts. Turn off to send apps to the Trash and keep their personal data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                    let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/spruce").path
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

    private func binding<T>(_ key: WritableKeyPath<SpruceCore.Settings, T>) -> Binding<T> {
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
                    Text(item).font(Theme.code)
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

// MARK: - Menu bar panel

/// The Uninstaller's drop target: a rose tile with a down arrow that bobs gently, and lifts when
/// an app hovers over it.
private struct DropTile: View {
    var targeted: Bool
    @State private var bob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Module.uninstaller.buttonGradient)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1))
            .overlay(Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink))
            .frame(width: 46, height: 46)
            .shadow(color: Module.uninstaller.accent.opacity(targeted ? 0.7 : 0.45), radius: targeted ? 16 : 10, y: 5)
            .scaleEffect(targeted ? 1.14 : 1)
            .offset(y: bob && !targeted ? -4 : 0)
            .animation(Theme.snappy, value: targeted)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { bob = true }
            }
    }
}

/// The round grey ✕ in the corner of the panel.
struct CloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.rim.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Close (Esc)")
        .accessibilityLabel("Close")
    }
}

/// Drag an app here (or onto the menu bar icon), see everything it left on this Mac, remove it.
struct QuickUninstallPanel: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconTile(module: .uninstaller, size: 22)
                Text("Uninstaller").font(.system(size: 14, weight: .semibold))
            }
            Group {
                if let name = model.quickScanning {
                    dropZone {
                        ProgressView().controlSize(.small)
                        Text("Scanning \(name)…").font(.callout).foregroundStyle(.secondary)
                    }
                } else if let quick = model.quickUninstall {
                    result(quick)
                } else {
                    dropZone {
                        DropTile(targeted: targeted)
                        Text(targeted ? "Drop to scan it" : "Drag an app here").font(.system(size: 15, weight: .semibold))
                            .contentTransition(.opacity)
                        Text("or drop it on the menu bar icon").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let app = urls.first(where: { $0.pathExtension == "app" }) else { return false }
                Task { await model.quickScan(app.path) }
                return true
            } isTargeted: { on in
                withAnimation(Theme.snappy) { targeted = on }
            }

            HStack {
                Spacer()
                Button(action: choose) { Label("Choose app…", systemImage: "plus.square") }
                    .disabled(model.quickScanning != nil)
                Spacer()
            }
            Text("Nothing is removed without your confirmation.")
                .font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.rim.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rimGradient, lineWidth: 1))
        .animation(Theme.spring, value: model.quickUninstall?.app.path)
        .animation(Theme.spring, value: model.quickScanning)
    }

    private func dropZone<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(RadialGradient(colors: [Module.uninstaller.accent.opacity(targeted ? 0.24 : 0.12), .clear],
                                     center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: 170)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Module.uninstaller.accent : Theme.rim.opacity(0.3),
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [8, 6])))
            .scaleEffect(targeted ? 1.02 : 1)
            .contentShape(Rectangle())
    }

    private func result(_ quick: AppModel.QuickUninstall) -> some View {
        let complete = model.settings.uninstallCompletely
        let systemApp = quick.app.isAppleApp && !InstalledApp.deletableAppleApps.contains(quick.app.bundleID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: quick.app.path))
                    .resizable().frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quick.app.name).font(.headline).lineLimit(1)
                    Text(quick.leftovers.isEmpty ? "No other files found"
                         : "\(quick.leftovers.count) related item\(quick.leftovers.count == 1 ? "" : "s") on this Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { model.quickUninstall = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Scan another app")
            }
            ForEach(kinds(quick).prefix(4), id: \.name) { row in
                HStack {
                    Text(row.name).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(Format.bytes(row.bytes)).font(.callout.monospacedDigit())
                }
            }
            HStack(alignment: .firstTextBaseline) {
                CountingBytes(bytes: quick.totalBytes, duration: 0.6).font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Button("Details") { close(); model.showInUninstaller(quick.app) }
                Button {
                    close()
                    model.removeQuickUninstall()
                } label: {
                    Label(complete ? "Remove…" : "Uninstall…", systemImage: complete ? "flame.fill" : "trash")
                }
                .buttonStyle(.brand)
                .disabled(systemApp)
            }
            if systemApp {
                Text("Part of macOS. The system volume is sealed, so it can't be removed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private struct KindTotal { var name: String; var bytes: Int64 }

    /// Sizes grouped by kind (Caches, Preferences, …), the app bundle first.
    private func kinds(_ quick: AppModel.QuickUninstall) -> [KindTotal] {
        var totals: [String: Int64] = [:]
        for item in quick.leftovers { totals[item.kind, default: 0] += item.bytes }
        return [KindTotal(name: "\(quick.app.name).app", bytes: quick.app.bytes)]
            + totals.sorted { $0.value > $1.value }.map { KindTotal(name: $0.key, bytes: $0.value) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Scan"
        panel.message = "Choose an app to see everything it keeps on this Mac."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        StatusItemController.shared?.show()
        Task { await model.quickScan(url.path) }
    }
}
