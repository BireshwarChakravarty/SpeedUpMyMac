import SwiftUI
import BurnishCore

// MARK: - Processes (App Tamer–style)

struct ProcessesView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [ProcessInfoRow] = []
    @State private var byMemory = false
    @State private var mineOnly = true

    private var shown: [ProcessInfoRow] {
        let list = rows.filter { !mineOnly || $0.isMine }
        return Array((byMemory ? list.sorted { $0.memoryBytes > $1.memoryBytes } : list.sorted { $0.cpu > $1.cpu }).prefix(40))
    }

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Processes", value: "\(rows.filter { $0.cpu > 50 }.count) busy",
                       caption: "Quit, pause (SIGSTOP) or push a hog onto the efficiency cores", symbol: "cpu") {
                VStack(alignment: .trailing) {
                    Picker("", selection: $byMemory) {
                        Text("CPU").tag(false)
                        Text("Memory").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                    Toggle("My processes only", isOn: $mineOnly)
                }
            }
            VStack(spacing: 2) {
                ForEach(shown) { p in
                    HStack(spacing: 10) {
                        Text(p.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if p.isPaused { Text("paused").font(.caption).foregroundStyle(Theme.review) }
                        Text(String(format: "%.1f%%", p.cpu)).monospacedDigit().frame(width: 64, alignment: .trailing)
                            .foregroundStyle(p.cpu > 80 ? Theme.risky : .primary)
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
                }
            }
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
            HeroHeader(title: "Maintenance", value: "\(probes.values.filter(\.isRecommended).count) recommended",
                       caption: "Each task checks for a real symptom first — no ritual cache rebuilding", symbol: "wrench.and.screwdriver") {
                HStack {
                    Button("Re-check") { Task { await probe() } }
                    Button("Run \(chosen.count)") { Task { await runChosen() } }.buttonStyle(.polish).disabled(chosen.isEmpty || model.busy != nil)
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
                        Image(systemName: task.symbol).frame(width: 22).foregroundStyle(Theme.azure)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(task.title).fontWeight(.medium)
                                if task.needsAdmin { SudoBadge() }
                                if probe?.isRecommended == true {
                                    Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(Theme.safe)
                                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.safe.opacity(0.14), in: Capsule())
                                }
                            }
                            Text(task.detail).font(.caption).foregroundStyle(.secondary)
                            if let probe { Text(probe.reason).font(.caption).foregroundStyle(probe.isRecommended ? Theme.safe : .secondary) }
                        }
                        Spacer()
                        if let outcome = outcomes.first(where: { $0.task == task }) {
                            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(outcome.succeeded ? Theme.safe : Theme.risky).help(outcome.output)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .card()
        }
        .navigationTitle("Maintenance")
        .task { await probe() }
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
        await probe()
    }
}

// MARK: - Startup items (KnockKnock / LaunchControl)

struct StartupView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [StartupItem] = []

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Startup Items", value: "\(items.filter { !$0.disabled }.count) active",
                       caption: "\(items.filter { $0.signing.suspicious }.count) unsigned, ad-hoc or broken · disabling is reversible, nothing is deleted",
                       symbol: "power") {
                Button("Refresh") { Task { await load() } }
            }
            ForEach([StartupItem.Domain.userAgent, .globalAgent, .daemon], id: \.self) { domain in
                let list = items.filter { $0.domain == domain }
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(domain.rawValue + "s").font(.headline)
                            if domain.needsAdmin { SudoBadge() }
                        }
                        ForEach(list) { item in row(item) }
                    }
                    .card()
                }
            }
            Text("Login items added through System Settings → General → Login Items are managed there. With Sudo mode on, `burnish startup btm` lists every Background Task Management entry.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Startup Items")
        .task { await load() }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { !item.disabled }, set: { on in toggle(item, on) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(item.domain.needsAdmin && !model.sudo)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label).fontWeight(.medium).lineLimit(1)
                if let program = item.program { PathText(path: program) }
            }
            Spacer()
            Text(item.signer ?? item.signing.rawValue).font(.caption)
                .foregroundStyle(item.signing.suspicious ? Theme.risky : .secondary)
            Button { model.reveal(item.plistPath) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }

    private func load() async {
        items = await model.run("Auditing launch agents…") { StartupItems.scan() }
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
    @State private var applied = Set<String>()
    @State private var touchID = false

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Tweaks", value: "\(applied.count) of \(Tweaks.all.count) on",
                       caption: "Every change remembers the previous value and can be reverted", symbol: "slider.horizontal.3") {
                HStack {
                    ForEach(Tweaks.presets, id: \.self) { preset in
                        Button(preset.capitalized) { apply(Tweaks.inPreset(preset)) }
                    }
                    Button("Revert all") { revert(Tweaks.all) }
                }
            }
            Label("macOS 26 seals the system volume, so system apps and Siri/Spotlight daemons can't be deleted without disabling SIP. Burnish won't ask you to. These are the changes that are safe and reversible.",
                  systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            ForEach(TweakGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.rawValue).font(.headline)
                    ForEach(Tweaks.all.filter { $0.group == group }) { tweak in
                        Toggle(isOn: Binding(get: { applied.contains(tweak.id) }, set: { on in on ? apply([tweak]) : revert([tweak]) })) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(tweak.title)
                                    if tweak.needsAdmin { SudoBadge() }
                                }
                                Text(tweak.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(tweak.needsAdmin && !model.sudo)
                    }
                    if group == .system {
                        Toggle(isOn: Binding(get: { touchID }, set: { on in setTouchID(on) })) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) { Text("Touch ID for sudo"); SudoBadge() }
                                Text("Authorize sudo in Terminal with your fingerprint. Uses /etc/pam.d/sudo_local, which survives macOS updates.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!model.sudo)
                    }
                }
                .card()
            }
        }
        .navigationTitle("Tweaks")
        .task { await refresh() }
    }

    private func refresh() async {
        applied = await Task.detached { Set(Tweaks.all.filter(Tweaks.isApplied).map(\.id)) }.value
        touchID = Tweaks.touchIDForSudoEnabled()
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

    private func setTouchID(_ on: Bool) {
        let runner = model.runner
        Task {
            let ok = await model.run("Configuring Touch ID…") { (try? runner.run(Tweaks.touchIDScript(enable: on), reason: "configure Touch ID for sudo"))?.succeeded ?? false }
            model.report(ok ? "Touch ID for sudo \(on ? "on" : "off")" : "Couldn't change Touch ID for sudo", error: !ok)
            await refresh()
        }
    }
}
