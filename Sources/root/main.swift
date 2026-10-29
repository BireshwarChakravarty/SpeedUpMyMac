import RootCore
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - Terminal helpers

let isTTY = isatty(STDOUT_FILENO) == 1
func paint(_ s: String, _ code: String) -> String { isTTY ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
func bold(_ s: String) -> String { paint(s, "1") }
func dim(_ s: String) -> String { paint(s, "2") }
func green(_ s: String) -> String { paint(s, "32") }
func amber(_ s: String) -> String { paint(s, "33") }
func red(_ s: String) -> String { paint(s, "31") }
func cyan(_ s: String) -> String { paint(s, "36") }

func pad(_ s: String, _ width: Int) -> String { s.count >= width ? s : s + String(repeating: " ", count: width - s.count) }
func lpad(_ s: String, _ width: Int) -> String { s.count >= width ? s : String(repeating: " ", count: width - s.count) + s }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("root: \(message)\n".utf8))
    exit(1)
}

func riskLabel(_ risk: Risk) -> String {
    switch risk {
    case .safe: return green("safe")
    case .review: return amber("review")
    case .risky: return red("risky")
    }
}

func printJSON<T: Encodable>(_ value: T) {
    guard let data = try? JSONEncoder.stable.encode(value) else { fail("could not encode JSON") }
    print(String(decoding: data, as: UTF8.self))
}

/// Asks before destructive work. Non-interactive runs must pass --yes.
func confirm(_ question: String, yes: Bool) -> Bool {
    if yes { return true }
    guard isatty(STDIN_FILENO) == 1 else {
        FileHandle.standardError.write(Data("root: not a terminal; pass --yes to proceed unattended\n".utf8))
        return false
    }
    print("\(question) [y/N] ", terminator: "")
    return (readLine() ?? "").lowercased().hasPrefix("y")
}

// MARK: - Arguments

struct Args {
    var command: String
    var positional: [String] = []
    var flags = Set<String>()
    var options: [String: [String]] = [:]

    init(_ argv: [String]) {
        command = argv.first ?? "help"
        var i = 1
        let valued: Set<String> = ["--only", "--min-age", "--root", "--level", "--min-mb", "--older-days", "--top", "--depth",
                                   "--folder", "--task", "--path"]
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                if let eq = a.firstIndex(of: "=") {
                    options[String(a[..<eq]), default: []].append(String(a[a.index(after: eq)...]))
                } else if valued.contains(a), i + 1 < argv.count {
                    options[a, default: []].append(argv[i + 1])
                    i += 1
                } else {
                    flags.insert(a)
                }
            } else if a.hasPrefix("-") && a.count == 2 {
                switch a {
                case "-y": flags.insert("--yes")
                case "-n": flags.insert("--dry-run")
                case "-s": flags.insert("--sudo")
                case "-j": flags.insert("--json")
                default: flags.insert(a)
                }
            } else {
                positional.append(a)
            }
            i += 1
        }
    }

    func has(_ flag: String) -> Bool { flags.contains(flag) }
    func value(_ key: String) -> String? { options[key]?.last }
    func values(_ key: String) -> [String] { options[key] ?? [] }
    func int(_ key: String) -> Int? { value(key).flatMap(Int.init) }
}

let args = Args(Array(CommandLine.arguments.dropFirst()))
var settings = Settings.load()
Scheduler.migrateLegacy(settings.schedule, cliPath: URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path)
let machine = MachineInfo.current()

/// Sudo is on when requested by flag or by the saved toggle — and only if this account is an admin.
var sudo: Bool {
    let wanted = args.has("--sudo") || settings.adminMode
    if wanted && !machine.isAdmin {
        FileHandle.standardError.write(Data(amber("root: \(machine.userName) is a standard account on this Mac — running user-level only.\n").utf8))
        return false
    }
    return wanted && !args.has("--no-sudo")
}

let runner: PrivilegeRunner = Privilege.sudoRunner()

if Privilege.isRoot && ProcessInfo.processInfo.environment["ROOTAPP_ALLOW_ROOT"] != "1" && !["help", "--help", "-h", "version", "--version"].contains(args.command) {
    fail("run root as yourself, not with sudo — it asks for admin rights only for the steps that need them")
}

// MARK: - Commands

func cmdHelp() {
    print("""
    \(bold("root")) — clean every Mac down to the root

    \(bold("USAGE"))  root <command> [options]

    \(bold("CLEAN"))
      scan                    Show what can be cleaned (no changes)
      clean                   Clean safe items; --include-review / --include-risky to widen, --only id,id
      purge                   Remove idle build artifacts (node_modules, target, .build, Pods, venv…)
      apps                    List installed apps with size and last use
      uninstall <app>         Remove an app completely, no traces (--level strict|enhanced|deep, --keep-data)
      orphans                 Find leftovers of apps that are no longer installed
      large [path]            Large files (--min-mb 500, --older-days 180)
      dupes [path]            Duplicate files (--min-mb 1)
      lens [path]             Disk usage tree (--depth 2, --top 15)

    \(bold("SPEED"))
      top                     Top CPU and memory processes
      optimize                Probe and run maintenance (--list, --task id, --all-optional)
      startup                 Audit launch agents & daemons (disable|enable|fix <label>)
      tweaks                  List tweaks; apply <id|preset> / revert <id|all>; presets: balanced, privacy, snappy
      touchid on|off          Use Touch ID for sudo (admin)

    \(bold("PROTECT / FLEET"))
      status                  Health score, disk, memory, battery, security posture
      doctor                  Check permissions and tools
      fleet                   Show every Mac in your fleet; fleet publish; fleet folder <path>
      schedule daily|weekly|off   Unattended safe clean via a user LaunchAgent (no admin needed)
      sudo on|off             Persist the Sudo toggle
      history                 What Root removed, and when

    \(bold("OPTIONS"))
      -s, --sudo    include system-level items (admin accounts only)    -n, --dry-run   preview only
      -y, --yes     don't ask                                           -j, --json      machine-readable output
    """)
}

func printScan(_ report: ScanReport, showItems: Bool) {
    var lastCategory: TargetCategory?
    for result in report.results.sorted(by: { ($0.target.category.rawValue, -$0.bytes) < ($1.target.category.rawValue, -$1.bytes) }) {
        if result.target.category != lastCategory {
            print("\n" + bold(result.target.category.rawValue))
            lastCategory = result.target.category
        }
        let size = result.items.isEmpty ? dim("   —    ") : lpad(Format.bytes(result.bytes), 8)
        var line = "  \(size)  \(pad(result.target.title, 38)) \(riskLabel(result.target.risk))"
        if result.target.scope == .system { line += " " + amber("[sudo]") }
        if let skipped = result.skippedReason { line += "  " + dim("(\(skipped))") }
        line += dim("  \(result.target.id)")
        print(line)
        if showItems {
            for item in result.items.prefix(8) { print(dim("            \(lpad(Format.bytes(item.bytes), 8))  \(Paths.abbreviate(item.path))")) }
            if result.items.count > 8 { print(dim("            … \(result.items.count - 8) more")) }
        }
    }
    let safe = report.results.filter { $0.target.risk == .safe && $0.skippedReason == nil }.reduce(0) { $0 + $1.bytes }
    let sudoMore = report.results.filter { $0.skippedReason == "Needs Sudo mode" }.reduce(0) { $0 + $1.bytes }
    print("\n\(bold("Safe to clean now:")) \(green(Format.bytes(safe)))   \(dim("total found \(Format.bytes(report.totalBytes))"))")
    if sudoMore > 0 && !report.sudo {
        print(dim(machine.isAdmin ? "Another \(Format.bytes(sudoMore)) needs --sudo." : "Another \(Format.bytes(sudoMore)) is system-level (needs an admin account)."))
    }
}

func cmdScan() {
    let report = Scanner(settings: settings, sudo: sudo).scan()
    if args.has("--json") { printJSON(report); return }
    printScan(report, showItems: args.has("--verbose") || args.has("-v"))
}

func printReport(_ report: CleanReport, action: String) {
    let verb = report.dryRun ? "Would free" : "Freed"
    let trashed = report.removed.filter { $0.method == .trash }.count
    print("\n\(bold(verb)) \(green(Format.bytes(report.freedBytes))) — \(report.removed.count) item(s)"
          + (trashed > 0 ? ", \(trashed) moved to Trash" : ""))
    if !report.needsSudo.isEmpty {
        print(amber("\(report.needsSudo.count) system item(s) skipped — rerun with --sudo"))
    }
    for f in report.failures.prefix(10) { print(red("  ✗ ") + Paths.abbreviate(f.path) + dim("  \(f.reason)")) }
    if report.failures.count > 10 { print(dim("  … \(report.failures.count - 10) more failures")) }
    if !report.dryRun && (report.freedBytes > 0 || !report.failures.isEmpty) {
        History.append(HistoryEntry(action: action, detail: "CLI \(action)", report: report))
    }
}

func cmdClean() {
    let dry = args.has("--dry-run")
    let useSudo = sudo
    let scan = Scanner(settings: settings, sudo: useSudo).scan()
    var maxRisk: Risk = .safe
    if args.has("--include-review") { maxRisk = .review }
    if args.has("--include-risky") { maxRisk = .risky }
    let only = Set(args.values("--only").flatMap { $0.split(separator: ",").map(String.init) })
    let selected = scan.results.filter { r in
        if !only.isEmpty { return only.contains(r.target.id) && r.skippedReason == nil }
        return r.target.risk <= maxRisk && r.skippedReason == nil
    }
    guard !selected.isEmpty else { print("Nothing to clean."); return }
    print(bold("Receipt") + dim(dry ? "  (dry run)" : ""))
    for r in selected {
        let how = r.target.scope == .system ? amber("root") : (r.target.useTrash || settings.alwaysUseTrash ? "Trash" : "delete")
        print("  \(lpad(Format.bytes(r.bytes), 8))  \(pad(r.target.title, 38)) \(dim(how))")
    }
    let total = selected.reduce(0) { $0 + $1.bytes }
    print("  \(lpad(Format.bytes(total), 8))  \(bold("total"))")
    let cleaner = Cleaner(settings: settings, sudo: useSudo, runner: runner, dryRun: dry)
    let systemRequests = selected.filter { $0.target.scope == .system }.flatMap { r in
        r.items.map { RemovalRequest(item: $0, scope: .system, preferTrash: false) }
    }
    let preview = cleaner.privilegedPreview(systemRequests)
    if !preview.isEmpty && (args.has("--show-script") || dry) {
        print(dim("\nScript that will run as root:\n" + preview.text))
    }
    guard dry || confirm("\nClean these items?", yes: args.has("--yes")) else { print("Cancelled."); return }
    let report = cleaner.clean(selected)
    printReport(report, action: "clean")
}

func cmdPurge() {
    let roots = args.values("--root").isEmpty ? settings.purgeRoots : args.values("--root")
    let minAge = args.int("--min-age") ?? settings.purgeMinAgeDays
    print(dim("Scanning \(roots.map(Paths.abbreviate).filter { Paths.isDirectory(Paths.expand($0)) }.joined(separator: ", "))…"))
    let artifacts = ProjectPurge(roots: roots, minAgeDays: minAge).scan()
    if args.has("--json") { printJSON(artifacts); return }
    guard !artifacts.isEmpty else { print("No build artifacts found."); return }
    for a in artifacts.prefix(60) {
        let mark = a.recentlyActive ? amber("active") : green("idle  ")
        print("  \(lpad(Format.bytes(a.bytes), 8))  \(mark)  \(pad(a.kind, 16)) \(Paths.abbreviate(a.path))")
    }
    let idle = artifacts.filter { !$0.recentlyActive || args.has("--include-active") }
    print("\n\(bold("Idle artifacts:")) \(green(Format.bytes(idle.reduce(0) { $0 + $1.bytes }))) in \(idle.count) folder(s)"
          + dim("  (active = touched in the last \(minAge) days; --include-active to add them)"))
    guard !idle.isEmpty else { return }
    let dry = args.has("--dry-run")
    guard dry || confirm("Delete these build artifacts? They are rebuilt by your tools.", yes: args.has("--yes")) else { return }
    let requests = idle.map { RemovalRequest(item: ScanItem(path: $0.path, bytes: $0.bytes, isDirectory: true), scope: .user, preferTrash: false) }
    printReport(Cleaner(settings: settings, sudo: false, runner: nil, dryRun: dry).remove(requests, reason: "purge"), action: "purge")
}

func cmdApps() {
    let apps = Uninstaller.installedApps()
    if args.has("--json") { printJSON(apps); return }
    for app in apps.sorted(by: { $0.bytes > $1.bytes }) {
        let used = app.lastUsed.map { Format.relative($0) } ?? "never/unknown"
        let tag = app.userRemovable ? "" : amber(" [admin]")
        print("  \(lpad(Format.bytes(app.bytes), 8))  \(pad(app.name, 32)) \(dim(pad(used, 14))) \(dim(app.bundleID))\(tag)")
    }
}

func findApp(_ query: String, in apps: [InstalledApp]) -> InstalledApp? {
    let q = query.lowercased()
    if query.hasSuffix(".app") || query.hasPrefix("/") { return Uninstaller.describe(Paths.expand(query)) }
    return apps.first { $0.bundleID.lowercased() == q } ?? apps.first { $0.name.lowercased() == q }
        ?? apps.first { $0.name.lowercased().contains(q) }
}

func cmdUninstall() {
    guard let query = args.positional.first else { fail("usage: root uninstall <app name | bundle id | path>") }
    let apps = Uninstaller.installedApps(measureSizes: false)
    guard var app = findApp(query, in: apps) else { fail("no app matching \"\(query)\"") }
    app.bytes = FileSizer.measure(app.path).bytes
    guard app.canUninstall else { fail("\(app.name) is part of macOS and can't be removed") }
    let level = args.value("--level").flatMap(MatchLevel.init(rawValue:)) ?? settings.leftoverLevel
    let leftovers = Uninstaller.leftovers(for: app, level: level, otherApps: apps)
    // Complete removal is the default: personal data included, deleted outright, traces cleared.
    let complete = !args.has("--keep-data") && (settings.uninstallCompletely || args.has("--with-data"))
    let chosen = leftovers.filter { complete || !$0.isUserData }
    let traces = complete ? Uninstaller.traces(for: app, leftovers: chosen, level: level) : []
    print(bold("\(app.name) \(app.version)") + dim("  \(app.bundleID)  \(Paths.abbreviate(app.path))"))
    print("  \(lpad(Format.bytes(app.bytes), 8))  app bundle \(dim(complete ? "→ deleted" : "→ Trash"))")
    for l in leftovers {
        let selected = chosen.contains(l)
        let mark = selected ? green("✓") : dim("·")
        let note = l.isUserData && !complete ? dim("  personal data — kept (--keep-data)") : ""
        print("  \(mark) \(lpad(Format.bytes(l.bytes), 8))  \(pad(l.kind, 20)) \(Paths.abbreviate(l.path))\(l.system ? amber(" [sudo]") : "")\(note)")
    }
    for t in traces {
        print("  \(green("✓")) \(lpad("", 8))  \(pad("Trace", 20)) \(t.title)\(t.needsAdmin ? amber(" [sudo]") : "")  \(dim(t.detail))")
    }
    let useSudo = sudo
    let requests = Uninstaller.requests(app: app, leftovers: chosen, sudo: useSudo, complete: complete)
    if (requests.contains(where: { $0.scope == .system }) || traces.contains(where: \.needsAdmin)) && !useSudo {
        print(amber(machine.isAdmin ? "Some items need --sudo; they will be skipped." : "Some items are system-level and need an admin account."))
    }
    let dry = args.has("--dry-run")
    let question = complete ? "Remove \(app.name) completely? This deletes it and its data permanently." : "Uninstall \(app.name)?"
    guard dry || confirm(question, yes: args.has("--yes")) else { print("Cancelled."); return }
    let report = Uninstaller.uninstall(app, leftovers: chosen, traces: traces, complete: complete, settings: settings,
                                       sudo: useSudo, runner: runner, dryRun: dry)
    printReport(report, action: "uninstall")
    if !dry {
        let left = Uninstaller.remaining(after: app, level: level, otherApps: apps).filter { complete || !$0.isUserData }
        if left.isEmpty {
            print(green("Verified: no trace of \(app.name) left."))
        } else {
            print(amber("\(left.count) item(s) remain:"))
            for l in left.prefix(10) { print("    \(Paths.abbreviate(l.path))\(l.system && !useSudo ? amber(" [needs --sudo]") : "")") }
        }
    }
}

func cmdOrphans() {
    print(dim("Looking for files from apps that are no longer installed…"))
    let orphans = Orphans.find(installed: Uninstaller.installedApps(measureSizes: false), minBytes: 1)
    if args.has("--json") { printJSON(orphans); return }
    guard !orphans.isEmpty else { print("No orphaned files found."); return }
    for o in orphans { print("  \(lpad(Format.bytes(o.bytes), 8))  \(pad(o.kind, 20)) \(Paths.abbreviate(o.path))") }
    let total = orphans.reduce(0) { $0 + $1.bytes }
    print("\n\(bold("Orphaned:")) \(amber(Format.bytes(total))) — review before removing; everything goes to the Trash.")
    let dry = args.has("--dry-run")
    guard dry || confirm("Move all of these to the Trash?", yes: args.has("--yes")) else { return }
    let requests = orphans.map { RemovalRequest(item: ScanItem(path: $0.path, bytes: $0.bytes), scope: .user, preferTrash: true) }
    printReport(Cleaner(settings: settings, sudo: false, runner: nil, dryRun: dry).remove(requests, reason: "orphans"), action: "orphans")
}

func cmdLarge() {
    let root = args.positional.first ?? "~"
    let minMB = Int64(args.int("--min-mb") ?? settings.largeFileMinMB)
    let files = SpaceLens.largeFiles(in: root, minBytes: minMB * 1_000_000, olderThanDays: args.int("--older-days"))
    if args.has("--json") { printJSON(files); return }
    for f in files.prefix(args.int("--top") ?? 50) {
        let age = f.accessed.map { Format.relative($0) } ?? ""
        print("  \(lpad(Format.bytes(f.bytes), 8))  \(dim(pad(age, 10)))  \(Paths.abbreviate(f.path))")
    }
    print(dim("\n\(files.count) file(s) ≥ \(minMB) MB. Remove from Finder or the Root app (items go to the Trash)."))
}

func cmdDupes() {
    let root = args.positional.first ?? "~"
    let minMB = Int64(args.int("--min-mb") ?? 1)
    print(dim("Hashing files ≥ \(minMB) MB under \(root)…"))
    let groups = Duplicates.find(in: root, minBytes: minMB * 1_000_000)
    if args.has("--json") { printJSON(groups); return }
    for g in groups.prefix(args.int("--top") ?? 30) {
        print("\(bold(Format.bytes(g.reclaimable))) reclaimable · \(g.paths.count) × \(Format.bytes(g.bytesEach))")
        for p in g.paths { print(dim("    \(Paths.abbreviate(p))")) }
    }
    print("\n\(bold("Total reclaimable:")) \(Format.bytes(groups.reduce(0) { $0 + $1.reclaimable }))")
}

func cmdLens() {
    let root = args.positional.first ?? "~"
    let depth = args.int("--depth") ?? 2
    let top = args.int("--top") ?? 15
    let tree = SpaceLens.scan(Paths.expand(root), depth: depth)
    func show(_ node: DiskNode, indent: Int, level: Int) {
        let pct = tree.bytes > 0 ? Double(node.bytes) / Double(tree.bytes) : 0
        let bar = String(repeating: "█", count: Int(pct * 20)) + String(repeating: "░", count: 20 - Int(pct * 20))
        print("\(String(repeating: "  ", count: indent))\(lpad(Format.bytes(node.bytes), 8))  \(cyan(bar))  \(node.name)")
        guard level < depth else { return }
        for child in node.children.prefix(top) where child.isDirectory { show(child, indent: indent + 1, level: level + 1) }
    }
    show(tree, indent: 0, level: 0)
}

func cmdTop() {
    let rows = Processes.list()
    print(bold("CPU"))
    for p in rows.sorted(by: { $0.cpu > $1.cpu }).prefix(10) {
        print("  \(lpad(String(format: "%.1f%%", p.cpu), 7))  \(lpad(Format.bytes(p.memoryBytes), 8))  \(pad(p.name, 30)) \(dim("pid \(p.pid)"))\(p.isPaused ? amber(" paused") : "")")
    }
    print(bold("\nMemory"))
    for p in rows.sorted(by: { $0.memoryBytes > $1.memoryBytes }).prefix(10) {
        print("  \(lpad(Format.bytes(p.memoryBytes), 8))  \(lpad(String(format: "%.1f%%", p.cpu), 7))  \(pad(p.name, 30)) \(dim("pid \(p.pid)"))")
    }
    print(dim("\nPause a hog: kill -STOP <pid> · resume: kill -CONT <pid> · E-cores: taskpolicy -b -p <pid> (or use the app)"))
}

func cmdOptimize() {
    let useSudo = sudo
    let probes = MaintenanceTask.allCases.map { ($0, $0.probe(machine: machine, sudo: useSudo)) }
    if args.has("--list") || (args.values("--task").isEmpty && !args.has("--all-optional") && !args.has("--yes") && !args.has("--dry-run")) {
        for (task, probe) in probes {
            let state: String
            switch probe {
            case .recommended: state = green("recommended")
            case .optional: state = dim("optional   ")
            case .notNeeded: state = dim("not needed ")
            case .unavailable: state = dim("unavailable")
            }
            print("  \(state)  \(pad(task.title, 38)) \(task.needsAdmin ? amber("[sudo] ") : "       ")\(dim(probe.reason))  \(dim(task.rawValue))")
        }
        print(dim("\nRun recommended tasks: root optimize --yes   ·   specific: --task id   ·   everything optional: --all-optional"))
        if args.has("--list") { return }
    }
    var tasks: [MaintenanceTask]
    if !args.values("--task").isEmpty {
        let ids = Set(args.values("--task").flatMap { $0.split(separator: ",").map(String.init) })
        tasks = MaintenanceTask.allCases.filter { ids.contains($0.rawValue) }
    } else {
        tasks = probes.filter { $0.1.isRecommended || (args.has("--all-optional") && $0.1.isRunnable) }.map(\.0)
    }
    tasks = tasks.filter { t in probes.first { $0.0 == t }?.1.isRunnable ?? false }
    guard !tasks.isEmpty else { print("Nothing needs doing — your Mac looks healthy."); return }
    print(bold("Will run: ") + tasks.map(\.title).joined(separator: ", "))
    let dry = args.has("--dry-run")
    guard dry || confirm("Proceed?", yes: args.has("--yes") && !tasks.contains(where: \.needsConfirmation)) else { return }
    for outcome in Maintenance.run(tasks, sudo: useSudo, runner: runner, dryRun: dry) {
        print("\(outcome.succeeded ? green("✓") : red("✗")) \(outcome.task.title)")
        let out = outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { print(dim(out.split(separator: "\n").prefix(6).map { "    " + $0 }.joined(separator: "\n"))) }
    }
    if !dry { History.append(HistoryEntry(action: "optimize", detail: tasks.map(\.title).joined(separator: ", "))) }
}

func cmdStartup() {
    let sub = args.positional.first
    if sub == "disable" || sub == "enable" {
        guard let label = args.positional.dropFirst().first else { fail("usage: root startup \(sub!) <label>") }
        guard let item = StartupItems.scan(checkSignatures: false).first(where: { $0.label == label }) else { fail("no job labelled \(label)") }
        do {
            try StartupItems.setEnabled(item, enabled: sub == "enable", sudo: sudo, runner: runner)
            print(green("✓ ") + "\(sub == "enable" ? "Enabled" : "Disabled") \(label)")
        } catch { fail(error.localizedDescription) }
        return
    }
    if sub == "fix" {
        guard let label = args.positional.dropFirst().first else { fail("usage: root startup fix <label>") }
        guard let item = StartupItems.scan(checkSignatures: false).first(where: { $0.label == label }) else { fail("no job labelled \(label)") }
        guard item.quarantined else { print("\(label) isn't quarantined; nothing to fix."); return }
        do {
            try StartupItems.clearQuarantine(item, sudo: sudo, runner: runner)
            print(green("✓ ") + "Cleared the quarantine flag on \(label); launchd will load it again")
        } catch { fail(error.localizedDescription) }
        return
    }
    if sub == "btm" {
        guard sudo else { fail("needs --sudo") }
        do { print(try StartupItems.backgroundTaskDump(runner: runner)) } catch { fail(error.localizedDescription) }
        return
    }
    let items = StartupItems.scan()
    if args.has("--json") { printJSON(items); return }
    for item in items {
        let sig = item.signing.suspicious ? red(pad(item.signing.rawValue, 14)) : dim(pad(item.signing.rawValue, 14))
        let state = item.disabled ? dim("off") : green("on ")
        let blocked = item.quarantined && OSFeatures.launchdRejectsQuarantined ? red("  quarantined: launchd won't load it (root startup fix \(item.label))") : ""
        print("  \(state)  \(sig) \(pad(item.domain.rawValue, 14)) \(item.label)\(item.signer.map { dim("  " + $0) } ?? "")\(blocked)")
    }
    print(dim("\nDisable: root startup disable <label>   (reversible; nothing is deleted)   ·   full BTM list: root startup btm --sudo"))
}

func cmdTweaks() {
    let sub = args.positional.first
    let useSudo = sudo
    switch sub {
    case "apply", "revert":
        guard let what = args.positional.dropFirst().first else { fail("usage: root tweaks \(sub!) <id|preset|all>") }
        var chosen: [Tweak]
        if Tweaks.presets.contains(what) { chosen = Tweaks.inPreset(what) }
        else if what == "all" { chosen = Tweaks.all }
        else if let t = Tweaks.tweak(what) { chosen = [t] }
        else { fail("unknown tweak or preset \(what)") }
        if !useSudo { chosen = chosen.filter { !$0.needsAdmin } }
        let errors = sub == "apply" ? Tweaks.apply(chosen, sudo: useSudo, runner: runner) : Tweaks.revert(chosen, sudo: useSudo, runner: runner)
        for t in chosen {
            if let e = errors[t.id] { print(red("✗ ") + t.title + dim("  \(e)")) } else { print(green("✓ ") + t.title) }
        }
    default:
        for group in TweakGroup.allCases {
            print("\n" + bold(group.rawValue))
            for t in Tweaks.all where t.group == group {
                let on = Tweaks.isApplied(t) ? green("on ") : dim("off")
                print("  \(on)  \(pad(t.title, 44)) \(dim(t.id))\(t.needsAdmin ? amber(" [sudo]") : "")")
            }
        }
        print(dim("\nroot tweaks apply balanced|privacy|snappy|<id>   ·   root tweaks revert all"))
    }
}

func cmdTouchID() {
    guard machine.isAdmin else { fail("Touch ID for sudo needs an administrator account") }
    let on = args.positional.first != "off"
    do {
        let r = try runner.run(Tweaks.touchIDScript(enable: on), reason: "configure Touch ID for sudo")
        print(r.succeeded ? green("✓ Touch ID for sudo \(on ? "enabled" : "disabled")") : red(r.stderr))
    } catch { fail(error.localizedDescription) }
}

func cmdStatus() {
    let health = Health.report()
    if args.has("--json") { printJSON(health); return }
    let scoreColor = health.score >= 80 ? green : health.score >= 60 ? amber : red
    print("\(bold(health.machine.name))  \(dim("\(health.machine.chip) · macOS \(health.machine.osVersion) · \(Format.bytes(health.machine.memoryBytes)) RAM"))")
    print("Account   \(health.machine.userName) \(health.machine.isAdmin ? green("admin") : amber("standard (user-level cleaning only)"))  ·  Sudo mode \(settings.sudoEnabled(machine: machine) ? amber("on") : dim("off"))")
    print("Health    \(scoreColor(bold("\(health.score)")))/100")
    let d = health.disk
    print("Disk      \(Format.bytes(d.availableBytes)) available of \(Format.bytes(d.totalBytes))  \(dim("(\(Format.bytes(d.purgeableBytes)) purgeable · \(d.localSnapshots) snapshots · SMART \(d.smartStatus ?? "n/a"))"))")
    print("Memory    \(health.memory.pressure) pressure  \(dim("free \(health.memory.freePercent.map { "\($0)%" } ?? "?") · swap \(Format.bytes(health.memory.swapUsedBytes))"))")
    print("CPU       load \(health.load.map { String(format: "%.2f", $0) }.joined(separator: " "))  \(dim("thermal \(health.thermal) · up \(Int(health.uptimeSeconds / 86_400)) d"))")
    if let b = health.battery {
        print("Battery   \(b.healthPercent.map { "\($0)% health" } ?? "?") · \(b.cycleCount) cycles\(b.condition.map { " · \($0)" } ?? "")")
    }
    let s = health.security
    func yn(_ v: Bool?) -> String { v == nil ? dim("?") : (v! ? green("on") : red("off")) }
    print("Security  SIP \(yn(s.sip)) · Gatekeeper \(yn(s.gatekeeper)) · FileVault \(yn(s.fileVault)) · Firewall \(yn(s.firewall)) · XProtect \(s.xprotectVersion ?? "?")")
    print("Access    Full Disk Access \(s.fullDiskAccess ? green("granted") : amber("missing — grant it to your terminal for a complete clean"))")
    if !health.notes.isEmpty { print("\n" + health.notes.map { "  • " + $0 }.joined(separator: "\n")) }
}

func cmdDoctor() {
    print(bold("Root doctor") + dim("  \(machine.name) · \(machine.chip) · macOS \(machine.osVersion)"))
    func row(_ ok: Bool, _ label: String, _ hint: String) { print("  \(ok ? green("✓") : amber("!")) \(pad(label, 30)) \(dim(hint))") }
    row(machine.isAdmin, "Administrator account", machine.isAdmin ? "Sudo mode available" : "standard account: user-level cleaning only (still most of the junk)")
    row(Health.hasFullDiskAccess(), "Full Disk Access",
        OSFeatures.containersProtected
            ? "needed on macOS 27 to clean inside other apps' containers; add your terminal app in Privacy & Security"
            : "System Settings → Privacy & Security → Full Disk Access")
    row(Tweaks.touchIDForSudoEnabled(), "Touch ID for sudo", "root touchid on")
    row(Scheduler.isInstalled, "Scheduled clean", "root schedule weekly")
    if OSFeatures.major >= 27 {
        let stuck = StartupItems.scan(checkSignatures: false).filter { $0.quarantined && !$0.disabled }
        row(stuck.isEmpty, "Launch jobs launchd will load", stuck.isEmpty ? "none are quarantined"
            : "\(stuck.count) quarantined (macOS 27 skips them): root startup fix <label>")
        row(OSFeatures.gatekeeperPurgeArguments != nil, "Gatekeeper purge (spctl)",
            OSFeatures.gatekeeperPurgeArguments != nil ? "root optimize --task gatekeeper-purge --sudo" : "not offered by this spctl")
    }
    for tool in ["brew", "xcrun", "docker", "git", "sqlite3"] {
        row(Shell.which(tool) != nil, "\(tool)", Shell.which(tool) ?? "not installed (related targets are skipped)")
    }
    row(true, "Fleet folder", Paths.abbreviate(settings.resolvedFleetFolder))
}

func cmdFleet() {
    switch args.positional.first {
    case "publish":
        let reclaimable = Scanner(settings: settings, sudo: false).scan().bytes(maxRisk: .safe)
        do {
            let snap = try Fleet.publish(settings: settings, reclaimable: reclaimable, health: Health.report())
            print(green("✓ ") + "Published \(snap.machine.name) to \(Paths.abbreviate(Fleet.folder(settings)))")
        } catch { fail(error.localizedDescription) }
    case "folder":
        guard let path = args.positional.dropFirst().first else { print(settings.resolvedFleetFolder); return }
        settings.fleetFolder = path
        settings.save()
        print(green("✓ ") + "Fleet folder set to \(Paths.abbreviate(settings.resolvedFleetFolder))")
    case "forget":
        guard let id = args.positional.dropFirst().first else { fail("usage: root fleet forget <machine-id>") }
        Fleet.forget(id, settings: settings)
    default:
        let fleet = Fleet.load(settings: settings)
        if args.has("--json") { printJSON(fleet); return }
        guard !fleet.isEmpty else { print("No Macs yet. Run `root fleet publish` on each Mac."); return }
        for s in fleet {
            let me = s.machine.machineID == machine.machineID ? cyan(" (this Mac)") : ""
            let acct = s.machine.isAdmin ? green("admin") : amber("standard")
            print("\(bold(s.machine.name))\(me)  \(dim("\(s.machine.chip) · macOS \(s.machine.osVersion)")) · \(acct)")
            print("    health \(s.healthScore.map(String.init) ?? "?")  ·  \(Format.bytes(s.diskAvailable)) free of \(Format.bytes(s.diskTotal))  ·  reclaimable \(s.reclaimableBytes.map(Format.bytes) ?? "?")  ·  freed all-time \(Format.bytes(s.totalFreed))")
            print(dim("    updated \(Format.relative(s.updatedAt))\(s.lastClean.map { " · last clean " + Format.relative($0) } ?? "")\(s.isStale ? " · stale" : "")  id \(s.machine.machineID)"))
        }
    }
}

func cmdSchedule() {
    guard let value = args.positional.first, let schedule = Schedule(rawValue: value) else { fail("usage: root schedule daily|weekly|off") }
    let cli = Shell.which("root") ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    do {
        try Scheduler.install(schedule, cliPath: cli)
        settings.schedule = schedule
        settings.save()
        print(green("✓ ") + (schedule == .off ? "Scheduled cleaning turned off" : "Root will clean safe items \(schedule.rawValue) (no admin needed)"))
    } catch { fail(error.localizedDescription) }
}

func cmdSudo() {
    guard let v = args.positional.first, v == "on" || v == "off" else {
        print("Sudo mode is \(settings.sudoEnabled(machine: machine) ? "on" : "off")\(machine.isAdmin ? "" : " (unavailable: standard account)")")
        return
    }
    guard machine.isAdmin || v == "off" else { fail("\(machine.userName) is not an administrator on this Mac") }
    settings.adminMode = v == "on"
    settings.save()
    print(green("✓ ") + "Sudo mode \(v)")
}

func cmdHistory() {
    let entries = History.load()
    if args.has("--json") { printJSON(entries); return }
    guard !entries.isEmpty else { print("Nothing yet."); return }
    for e in entries.prefix(args.int("--top") ?? 30) {
        print("  \(dim(pad(Format.relative(e.date), 10)))  \(pad(e.action, 10))  \(lpad(e.bytes > 0 ? Format.bytes(e.bytes) : "", 8))  \(e.detail)\(e.errors.isEmpty ? "" : red("  \(e.errors.count) errors"))")
    }
    print("\n\(bold("Freed all-time:")) \(green(Format.bytes(History.totalFreed)))")
}

func cmdAutoclean() {
    let report = SmartScan.autoclean(settings: settings)
    print("[\(Format.isoFormatter.string(from: Date()))] autoclean freed \(Format.bytes(report.freedBytes)), \(report.failures.count) failures")
}

// MARK: - Dispatch

switch args.command {
case "help", "--help", "-h": cmdHelp()
case "version", "--version": print("root \(Fleet.version)")
case "scan": cmdScan()
case "clean": cmdClean()
case "purge": cmdPurge()
case "apps": cmdApps()
case "uninstall": cmdUninstall()
case "orphans": cmdOrphans()
case "large": cmdLarge()
case "dupes": cmdDupes()
case "lens": cmdLens()
case "top": cmdTop()
case "optimize": cmdOptimize()
case "startup": cmdStartup()
case "tweaks": cmdTweaks()
case "touchid": cmdTouchID()
case "status": cmdStatus()
case "doctor": cmdDoctor()
case "fleet": cmdFleet()
case "schedule": cmdSchedule()
case "sudo": cmdSudo()
case "history": cmdHistory()
case "autoclean": cmdAutoclean()
default:
    FileHandle.standardError.write(Data("root: unknown command \(args.command)\n\n".utf8))
    cmdHelp()
    exit(2)
}
