import SwiftUI
import SpruceCore

// MARK: - Processes (App Tamer–style)

struct ProcessesView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [ProcessInfoRow] = []
    @State private var byMemory = false
    @State private var mineOnly = true

    private var maxMemory: Int64 { rows.map(\.memoryBytes).max() ?? 1 }

    private var shown: [ProcessInfoRow] {
        let list = rows.filter { !mineOnly || $0.isMine }
        return Array((byMemory ? list.sorted { $0.memoryBytes > $1.memoryBytes } : list.sorted { $0.cpu > $1.cpu }).prefix(40))
    }

    var body: some View {
        ModuleScroll {
            let busy = rows.filter { $0.cpu > 50 }.count
            HeroHeader(title: "Processes", value: busy > 0 ? "\(busy) busy" : "All calm",
                       caption: "Quit, pause (SIGSTOP) or push a hog onto the efficiency cores", symbol: "cpu") {
                VStack(alignment: .trailing, spacing: 10) {
                    PillPicker(selection: $byMemory, options: [(false, "CPU", "cpu"), (true, "Memory", "memorychip")])
                    Toggle("My processes only", isOn: $mineOnly)
                }
            }
            VStack(spacing: 2) {
                HStack(spacing: 10) {
                    Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 90, height: 1)
                    Text("CPU").frame(width: 64, alignment: .trailing)
                    Text("MEMORY").frame(width: 80, alignment: .trailing)
                    Color.clear.frame(width: 30, height: 1)
                }
                .font(Theme.mono(10, .semibold)).tracking(1.2).foregroundStyle(.tertiary)
                .padding(.bottom, 6)
                ForEach(shown) { p in
                    HStack(spacing: 10) {
                        Text(p.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if p.isPaused { Chip(text: "paused", color: Theme.review, symbol: "pause.fill") }
                        GrowingBar(fraction: byMemory ? Double(p.memoryBytes) / Double(max(maxMemory, 1)) : min(p.cpu / 100, 1),
                                   fill: Module.processes.gradient, height: 5)
                            .frame(width: 90)
                        Text(String(format: "%.1f%%", p.cpu)).monospacedDigit().frame(width: 64, alignment: .trailing)
                            .foregroundStyle(p.cpu > 80 ? Theme.risky : .primary)
                            .contentTransition(.numericText())
                        SizeText(bytes: p.memoryBytes).frame(width: 80, alignment: .trailing)
                        Menu {
                            Button("Quit") { act(.quit, p) }
                            Button(p.isPaused ? "Resume" : "Pause") { act(p.isPaused ? .resume : .pause, p) }
                            Button("Run on efficiency cores") { act(.efficiencyCores, p) }
                            Button("Normal priority") { act(.normalPriority, p) }
                            Divider()
                            Button("Force quit", role: .destructive) { act(.forceQuit, p) }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).frame(width: 30)
                            .disabled(!p.isMine)
                    }
                    .padding(.vertical, 3)
                    .rowHover()
                }
            }
            .animation(Theme.spring, value: shown.map(\.id))
            .card()
            Text("Pausing freezes a process until you resume it — handy for a runaway background app. Other users' and system processes are read-only.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Processes")
        .task {
            while !Task.isCancelled {
                rows = await Task.detached { Processes.list() }.value
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func act(_ action: Processes.Action, _ p: ProcessInfoRow) {
        let ok = Processes.perform(action, on: p)
        if ok { SoundFX.shared.play(action == .quit || action == .forceQuit ? .vanish : .success) }
        model.report(ok ? "\(p.name): done" : "Couldn't change \(p.name)", error: !ok)
        rows = Processes.list()
    }
}

// MARK: - Maintenance (OnyX / Mole optimize)

struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @State private var probes: [MaintenanceTask: ProbeResult] = [:]
    @State private var chosen = Set<MaintenanceTask>()
    @State private var outcomes: [MaintenanceOutcome] = []

    var body: some View {
        ModuleScroll {
            if probes.isEmpty {
                start
            } else {
                results
            }
        }
        .navigationTitle("Maintenance")
    }

    /// Before the first check: what Maintenance does, and one button.
    private var start: some View {
        VStack(spacing: 4) {
            ToolHero(module: .maintenance, title: "Maintenance",
                     subtitle: "Checks for real symptoms, then fixes only what needs it.") {
                Button("Check") { Task { await probe() } }
                    .buttonStyle(.brand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy != nil)
            }
            Text("\(MaintenanceTask.allCases.count) tasks: DNS, Spotlight, Launch Services, fonts, permissions and more. Nothing runs until you choose it.")
                .font(Theme.mono(11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var results: some View {
            HeroHeader(title: "Maintenance", value: "\(probes.values.filter(\.isRecommended).count) recommended",
                       caption: "Each task checks for a real symptom first — no ritual cache rebuilding", symbol: "wrench.and.screwdriver") {
                HStack {
                    Button("Re-check") { Task { await probe() } }
                    Button("Run \(chosen.count)") { Task { await runChosen() } }.buttonStyle(.tinted(.maintenance)).disabled(chosen.isEmpty || model.busy != nil)
                }
            }
            VStack(spacing: 4) {
                ForEach(MaintenanceTask.allCases) { task in
                    let probe = probes[task]
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(get: { chosen.contains(task) },
                                                 set: { on in if on { chosen.insert(task) } else { chosen.remove(task) } }))
                            .labelsHidden()
                            .disabled(!(probe?.isRunnable ?? false) || (task.needsAdmin && !model.sudo))
                        Image(systemName: task.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 22)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(task.title).fontWeight(.medium)
                                if task.needsAdmin { SudoBadge() }
                                if probe?.isRecommended == true { Chip(text: "Recommended", color: Theme.safe, symbol: "star.fill") }
                            }
                            Text(task.detail).font(.caption).foregroundStyle(.secondary)
                            if let probe { Text(probe.reason).font(.caption).foregroundStyle(probe.isRecommended ? Theme.safe : .secondary) }
                        }
                        Spacer()
                        if let outcome = outcomes.first(where: { $0.task == task }) {
                            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.title3)
                                .foregroundStyle(outcome.succeeded ? Theme.safe : Theme.risky).help(outcome.output)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 5)
                    .rowHover()
                }
            }
            .card()
    }

    private func probe() async {
        let machine = model.machine, sudo = model.sudo
        let results = await model.run("Probing…") { MaintenanceTask.allCases.map { ($0, $0.probe(machine: machine, sudo: sudo)) } }
        probes = Dictionary(uniqueKeysWithValues: results)
        chosen = Set(results.filter { $0.1.isRecommended && (!$0.0.needsAdmin || sudo) }.map(\.0))
    }

    private func runChosen() async {
        let tasks = MaintenanceTask.allCases.filter(chosen.contains)
        let sudo = model.sudo, runner = model.runner
        outcomes = await model.run("Running maintenance…") { Maintenance.run(tasks, sudo: sudo, runner: runner) }
        History.append(HistoryEntry(action: "optimize", detail: tasks.map(\.title).joined(separator: ", ")))
        model.report("Ran \(outcomes.filter(\.succeeded).count) of \(tasks.count) task(s)", error: outcomes.contains { !$0.succeeded })
        if !outcomes.contains(where: { !$0.succeeded }) {
            model.celebrate(Celebration(bytes: 0, title: "Maintenance done", detail: "\(tasks.count) task(s) ran cleanly", symbol: "wrench.and.screwdriver.fill"))
        }
        await probe()
    }
}

// MARK: - Startup items (KnockKnock / LaunchControl)

struct StartupView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [StartupItem] = []

    var body: some View {
        ModuleScroll {
            let review = items.filter(\.needsAttention).count
            HeroHeader(title: "Startup Items", value: review > 0 ? "\(review) to review" : "All good",
                       caption: "\(items.filter { !$0.disabled }.count) of \(items.count) running at login · disabling is reversible, nothing is deleted",
                       symbol: "power") {
                Button("Refresh") { Task { await load() } }
            }
            ForEach([StartupItem.Domain.userAgent, .globalAgent, .daemon], id: \.self) { domain in
                let list = items.filter { $0.domain == domain }
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTitle(title: domain.rawValue + "s", symbol: "power", trailing: "\(list.count)",
                                     admin: domain.needsAdmin)
                            .padding(.bottom, 6)
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider(inset: 62) }
                            row(item)
                        }
                    }
                    .card()
                }
            }
            Text("Login items added through System Settings → General → Login Items are managed there. In Admin mode, `spruce startup btm` lists every Background Task Management entry.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Startup Items")
        .task { await load() }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(get: { !item.disabled }, set: { on in toggle(item, on) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Module.startup.accent)
                .disabled(item.domain.needsAdmin && !model.sudo)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label).font(Theme.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                if let program = item.program { PathText(path: program) }
            }
            Spacer(minLength: 12)
            if item.quarantined && OSFeatures.launchdRejectsQuarantined {
                Chip(text: "Won't load", color: Theme.review, symbol: "exclamationmark.triangle.fill")
                    .help("macOS 27's launchd skips plists that still carry the download quarantine flag.")
                Button("Fix") { fixQuarantine(item) }
                    .controlSize(.small)
                    .disabled(item.domain != .userAgent && !model.sudo)
                    .help(item.domain == .userAgent ? "Clear the quarantine flag so launchd loads it" : "Needs Admin mode")
            }
            if item.signing.suspicious {
                Chip(text: item.signer ?? item.signing.rawValue, color: Theme.risky, symbol: "exclamationmark.triangle.fill")
            } else {
                Text(item.signer ?? item.signing.rawValue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(item.plistPath) }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .rowHover()
    }

    private func load() async {
        items = await model.run("Auditing launch agents…") { StartupItems.scan() }
    }

    private func fixQuarantine(_ item: StartupItem) {
        let sudo = model.sudo, runner = model.runner
        Task {
            do {
                try await Task.detached { try StartupItems.clearQuarantine(item, sudo: sudo, runner: runner) }.value
                model.report("\(item.label) will load again")
            } catch {
                model.report(error.localizedDescription, error: true)
            }
            await load()
        }
    }

    private func toggle(_ item: StartupItem, _ on: Bool) {
        let sudo = model.sudo, runner = model.runner
        Task {
            do {
                try await Task.detached { try StartupItems.setEnabled(item, enabled: on, sudo: sudo, runner: runner) }.value
                model.report("\(on ? "Enabled" : "Disabled") \(item.label)")
            } catch {
                model.report(error.localizedDescription, error: true)
            }
            await load()
        }
    }
}

// MARK: - Tweaks (RemoveMacAI / TinkerTool)

struct TweaksView: View {
    @Environment(AppModel.self) private var model
    private var applied: Set<String> { model.tweaksApplied ?? [] }
    private var hasFullDiskAccess: Bool { model.tweaksFullDiskAccess }
    private var loaded: Bool { model.tweaksApplied != nil }

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Tweaks", value: loaded ? "\(applied.count) of \(Tweaks.all.count) on" : "Checking…",
                       caption: "Every change remembers the previous value and can be reverted", symbol: "slider.horizontal.3") {
                HStack {
                    ForEach(Tweaks.presets, id: \.self) { preset in
                        Button(preset.capitalized) { confirmPreset(preset) }
                            .disabled(!loaded)
                    }
                    Button("Revert All") { confirmRevertAll() }
                        .disabled(applied.isEmpty)
                }
            }
            InfoNote(text: "Presets show exactly what they change before anything happens. System apps and Siri/Spotlight daemons sit on the sealed system volume, so Spruce only offers changes that are safe and reversible.")
            ForEach(TweakGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: group.rawValue, symbol: "slider.horizontal.3", trailing: nil)
                    ForEach(Tweaks.all.filter { $0.group == group }) { tweak in
                        let blockedByAccess = tweak.needsFullDiskAccess && !hasFullDiskAccess
                        Toggle(isOn: Binding(get: { applied.contains(tweak.id) }, set: { on in on ? apply([tweak]) : revert([tweak]) })) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(tweak.title)
                                    if tweak.needsAdmin { SudoBadge() }
                                    if blockedByAccess { Chip(text: "Needs Full Disk Access", color: Theme.review, symbol: "lock.shield") }
                                }
                                Text(tweak.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(GlowSwitchStyle(tint: Module.tweaks.gradient))
                        .disabled(!loaded || (tweak.needsAdmin && !model.sudo) || blockedByAccess)
                        .padding(.vertical, 2)
                        .rowHover()
                    }
                    if group == .privacy && !hasFullDiskAccess {
                        Button("Open Full Disk Access Settings") { model.openFullDiskAccessSettings() }
                            .controlSize(.small)
                    }
                    if group == .system {
                        Toggle(isOn: Binding(get: { model.touchIDForAdmin }, set: { on in model.setTouchIDForAdmin(on) })) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) { Text("Touch ID instead of your password"); SudoBadge() }
                                Text("Spruce's admin steps and sudo in Terminal ask for your fingerprint. Uses /etc/pam.d/sudo_local, which survives macOS updates.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(GlowSwitchStyle())
                        .disabled(!model.machine.isAdmin || (!model.hasTouchID && !model.touchIDForAdmin))
                    }
                }
                .card()
            }
        }
        .navigationTitle("Tweaks")
        .task { await refresh() }
        .onChange(of: model.tourSubpage) { _, page in
            if page == "tweaks-preset" { confirmPreset("balanced") }
        }
    }

    /// The apps a list of tweaks restarts, in plain words ("the Dock and Finder").
    private static func restartNote(_ tweaks: [Tweak]) -> String? {
        let apps = Set(tweaks.compactMap(\.restart)).sorted()
        guard !apps.isEmpty else { return nil }
        let names = apps.map { $0 == "Dock" ? "the Dock" : $0 }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "Restarts \(list) so the change shows up."
    }

    /// A preset changes several settings at once and restarts the Dock or Finder, so it goes through
    /// the usual receipt: every change listed, nothing done until confirmed.
    private func confirmPreset(_ preset: String) {
        let sudo = model.sudo
        let all = Tweaks.inPreset(preset).filter { !applied.contains($0.id) }
        let list = all.filter { (!$0.needsAdmin || sudo) && !($0.needsFullDiskAccess && !hasFullDiskAccess) }
        let skipped = all.count - list.count
        guard !list.isEmpty else {
            model.report(all.isEmpty ? "Everything in \(preset.capitalized) is already on" : "\(preset.capitalized) needs Admin mode or Full Disk Access for the rest")
            return
        }
        var note = Self.restartNote(list) ?? "Each change can be reverted from this page."
        if skipped > 0 { note += " \(skipped) more need Admin mode or Full Disk Access and are left as they are." }
        model.receipt = Receipt(title: "\(preset.capitalized) tweaks",
                                lines: list.map { ReceiptLine(path: "tweak:\($0.id)", title: $0.title, bytes: 0, destination: "Turn on") },
                                script: nil, confirmTitle: "Apply \(list.count)", note: note) { [self] in
            apply(list)
        }
    }

    private func confirmRevertAll() {
        let list = Tweaks.all.filter { applied.contains($0.id) && (!$0.needsAdmin || model.sudo) }
        guard !list.isEmpty else { return }
        model.receipt = Receipt(title: "Revert tweaks",
                                lines: list.map { ReceiptLine(path: "tweak:\($0.id)", title: $0.title, bytes: 0, destination: "Restore") },
                                script: nil, confirmTitle: "Revert \(list.count)",
                                note: Self.restartNote(list) ?? "Each setting goes back to the value it had before Spruce changed it.") { [self] in
            revert(list)
        }
    }

    private func refresh() async {
        let state = await Task.detached { () -> (Set<String>, Bool) in
            let access = Health.hasFullDiskAccess()
            return (Tweaks.appliedIDs(fullDiskAccess: access), access)
        }.value
        model.tweaksFullDiskAccess = state.1
        model.tweaksApplied = state.0
        model.touchIDForAdmin = Tweaks.touchIDForSudoEnabled()
    }

    private func apply(_ tweaks: [Tweak]) {
        let sudo = model.sudo, runner = model.runner
        let list = tweaks.filter { !$0.needsAdmin || sudo }
        Task {
            let errors = await model.run("Applying…") { Tweaks.apply(list, sudo: sudo, runner: runner) }
            model.report(errors.isEmpty ? "Applied \(list.count) tweak(s)" : "\(errors.count) tweak(s) failed: \(errors.values.first ?? "")", error: !errors.isEmpty)
            await refresh()
        }
    }

    private func revert(_ tweaks: [Tweak]) {
        let sudo = model.sudo, runner = model.runner
        Task {
            _ = await model.run("Reverting…") { Tweaks.revert(tweaks, sudo: sudo, runner: runner) }
            model.report("Restored previous settings")
            await refresh()
        }
    }
}
