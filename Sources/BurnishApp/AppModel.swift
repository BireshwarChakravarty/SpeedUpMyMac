import SwiftUI
import BurnishCore
import Observation

enum Module: String, CaseIterable, Identifiable, Hashable {
    case smartScan, cleanup, devPurge, uninstaller, spaceLens
    case processes, maintenance, startup, tweaks
    case health, fleet, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: return "Smart Scan"
        case .cleanup: return "Cleanup"
        case .devPurge: return "Dev Purge"
        case .uninstaller: return "Uninstaller"
        case .spaceLens: return "Space Lens"
        case .processes: return "Processes"
        case .maintenance: return "Maintenance"
        case .startup: return "Startup Items"
        case .tweaks: return "Tweaks"
        case .health: return "Health"
        case .fleet: return "Fleet"
        case .history: return "History"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: return "sparkles"
        case .cleanup: return "trash.slash"
        case .devPurge: return "hammer"
        case .uninstaller: return "xmark.app"
        case .spaceLens: return "circle.circle"
        case .processes: return "cpu"
        case .maintenance: return "wrench.and.screwdriver"
        case .startup: return "power"
        case .tweaks: return "slider.horizontal.3"
        case .health: return "heart.text.square"
        case .fleet: return "macbook.and.iphone"
        case .history: return "clock.arrow.circlepath"
        }
    }

    static let groups: [(String?, [Module])] = [
        (nil, [.smartScan]),
        ("Clean", [.cleanup, .devPurge, .uninstaller, .spaceLens]),
        ("Speed", [.processes, .maintenance, .startup, .tweaks]),
        ("Protect", [.health]),
        ("Fleet", [.fleet, .history]),
    ]
}

/// One line on the receipt shown before anything is removed.
struct ReceiptLine: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var title: String
    var bytes: Int64
    var destination: String
}

/// The full-window moment after a clean or uninstall.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    var bytes: Int64
    var title: String
    var detail: String?
    var symbol: String = "sparkles"
}

/// What a post-uninstall rescan found.
struct UninstallVerdict: Equatable {
    var app: String
    var remaining: [Leftover]
}

/// The confirmation sheet: exactly what goes, where it goes, and the root script if any.
struct Receipt: Identifiable {
    let id = UUID()
    var title: String
    var lines: [ReceiptLine]
    var script: PrivilegedScript?
    var confirmTitle: String
    var note: String?
    var perform: @MainActor () async -> Void

    var total: Int64 { lines.reduce(0) { $0 + $1.bytes } }
}

@MainActor
@Observable
final class AppModel {
    var settings = BurnishCore.Settings.load()
    var machine = MachineInfo.current()
    var selection: Module? = .smartScan

    // Shared busy/status state.
    var busy: String?
    var status: String?
    var statusIsError = false
    var receipt: Receipt?
    var celebration: Celebration?
    var scanProgress: Double?
    var scanStage = ""

    // Module data.
    var smart: SmartScanResult?
    var scan: ScanReport?
    var selectedTargets = Set<String>()
    var excludedItems = Set<String>()
    var artifacts: [ProjectArtifact] = []
    var selectedArtifacts = Set<String>()
    var apps: [InstalledApp] = []
    var orphans: [Leftover] = []
    var health: HealthReport?
    var fleet: [FleetSnapshot] = []
    var history: [HistoryEntry] = []
    var sentinelOffer: (app: InstalledApp, leftovers: [Leftover])?
    var verdict: UninstallVerdict?

    let sentinel = TrashSentinel()

    init() {
        sentinel.onAppTrashed = { [weak self] path in
            Task { @MainActor in self?.offerLeftoverCleanup(forTrashed: path) }
        }
        if settings.trashSentinel { sentinel.start() }
    }

    // MARK: Sudo toggle

    var sudo: Bool { settings.sudoEnabled(machine: machine) }

    var sudoBinding: Binding<Bool> {
        Binding(get: { self.sudo }, set: { newValue in
            guard self.machine.isAdmin else { return }
            self.settings.adminMode = newValue
            self.settings.save()
        })
    }

    var runner: PrivilegeRunner { Privilege.appleScriptRunner() }

    // MARK: Helpers

    func run<T: Sendable>(_ message: String, _ work: @escaping @Sendable () -> T) async -> T {
        busy = message
        defer { busy = nil }
        return await Task.detached(priority: .userInitiated) { work() }.value
    }

    func report(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
        if error { SoundFX.shared.play(.error, haptic: .generic) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if self.status == text { self.status = nil }
        }
    }

    func summarize(_ r: CleanReport, verb: String = "Freed", celebrate title: String? = nil) {
        var text = "\(verb) \(Format.bytes(r.freedBytes)) · \(r.removed.count) item(s)"
        if !r.needsSudo.isEmpty { text += " · \(r.needsSudo.count) need Sudo mode" }
        if !r.failures.isEmpty { text += " · \(r.failures.count) failed" }
        let failed = r.removed.isEmpty && !r.failures.isEmpty
        report(text, error: failed)
        if !failed && !r.removed.isEmpty { celebrate(Celebration(bytes: r.freedBytes, title: title ?? "\(verb) and polished")) }
    }

    func celebrate(_ c: Celebration) {
        celebration = c
        SoundFX.shared.play(.clean, haptic: .levelChange)
    }

    func destination(scope: Scope, trash: Bool) -> String {
        scope == .system ? "Delete as admin" : (trash || settings.alwaysUseTrash ? "Move to Trash" : "Delete")
    }

    // MARK: Smart Scan

    func runSmartScan() async {
        let settings = self.settings, sudo = self.sudo
        let steps = Double(CleanupCatalog.all.count + 5)
        scanProgress = 0
        scanStage = "Warming up…"
        SoundFX.shared.play(.scanStart, haptic: .generic)
        let relay = ScanRelay()
        let pump = Task { @MainActor in
            while !Task.isCancelled {
                if let next = relay.take() {
                    self.scanStage = next.0
                    self.scanProgress = min(Double(next.1) / steps, 0.99)
                    self.busy = next.0
                    SoundFX.shared.play(.tick)
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        let result = await run("Scanning your Mac…") { SmartScan.run(settings: settings, sudo: sudo) { relay.post($0) } }
        pump.cancel()
        withAnimation(Theme.spring) {
            scanProgress = nil
            smart = result
        }
        scan = result.cleanup
        artifacts = result.artifacts
        health = result.health
        resetCleanupSelection()
        selectedArtifacts = Set(result.artifacts.filter { !$0.recentlyActive }.map(\.path))
        SoundFX.shared.play(.scanDone, haptic: .levelChange)
        await publishFleet()
    }

    /// "Burnish now": safe cleanup + idle artifacts, after a receipt.
    func burnishNow() {
        guard let smart else { return }
        let targets = smart.cleanup.results.filter { $0.target.risk == .safe && $0.skippedReason == nil }
        let idle = smart.artifacts.filter { !$0.recentlyActive }
        var lines = targets.map { ReceiptLine(path: $0.target.id, title: $0.target.title, bytes: $0.bytes,
                                              destination: destination(scope: $0.target.scope, trash: $0.target.useTrash)) }
        lines += idle.map { ReceiptLine(path: $0.path, title: "\($0.kind) · \(Paths.abbreviate($0.project))", bytes: $0.bytes, destination: "Delete") }
        let script = Cleaner(settings: settings, sudo: sudo, runner: nil).privilegedPreview(
            targets.filter { $0.target.scope == .system }.flatMap { r in r.items.map { RemovalRequest(item: $0, scope: .system, preferTrash: false) } })
        receipt = Receipt(title: "Burnish now", lines: lines, script: script.isEmpty ? nil : script, confirmTitle: "Clean",
                          note: "Only items marked safe and idle build folders. Everything else stays until you review it.") { [self] in
            let settings = self.settings, sudo = self.sudo, runner = self.runner
            let result = await run("Cleaning…") { () -> CleanReport in
                var r = Cleaner(settings: settings, sudo: sudo, runner: runner).clean(targets)
                r.merge(Cleaner(settings: settings, sudo: false, runner: nil).remove(
                    idle.map { RemovalRequest(item: ScanItem(path: $0.path, bytes: $0.bytes, isDirectory: true), scope: .user, preferTrash: false) },
                    reason: "purge"))
                History.append(HistoryEntry(action: "smart", detail: "Burnish now", report: r))
                return r
            }
            summarize(result, celebrate: "Burnished")
            await runSmartScan()
        }
    }

    // MARK: Cleanup

    func runCleanupScan() async {
        let settings = self.settings, sudo = self.sudo
        scan = await run("Measuring junk…") { Scanner(settings: settings, sudo: sudo).scan() }
        resetCleanupSelection()
    }

    func resetCleanupSelection() {
        selectedTargets = Set(scan?.results.filter { $0.target.risk == .safe && $0.skippedReason == nil }.map(\.target.id) ?? [])
        excludedItems = []
    }

    var selectedCleanupResults: [TargetResult] {
        (scan?.results ?? []).filter { selectedTargets.contains($0.target.id) && $0.skippedReason == nil }.map { r in
            var r = r
            r.items.removeAll { excludedItems.contains($0.path) }
            return r
        }
    }

    func confirmCleanup() {
        let chosen = selectedCleanupResults
        guard !chosen.isEmpty else { return }
        let lines = chosen.map { ReceiptLine(path: $0.target.id, title: $0.target.title, bytes: $0.bytes,
                                             destination: destination(scope: $0.target.scope, trash: $0.target.useTrash)) }
        let script = Cleaner(settings: settings, sudo: sudo, runner: nil).privilegedPreview(
            chosen.filter { $0.target.scope == .system }.flatMap { r in r.items.map { RemovalRequest(item: $0, scope: .system, preferTrash: false) } })
        receipt = Receipt(title: "Clean \(chosen.count) categor\(chosen.count == 1 ? "y" : "ies")", lines: lines,
                          script: script.isEmpty ? nil : script, confirmTitle: "Clean", note: nil) { [self] in
            let settings = self.settings, sudo = self.sudo, runner = self.runner
            let result = await run("Cleaning…") { () -> CleanReport in
                let r = Cleaner(settings: settings, sudo: sudo, runner: runner).clean(chosen)
                History.append(HistoryEntry(action: "clean", detail: chosen.map(\.target.title).joined(separator: ", "), report: r))
                return r
            }
            summarize(result)
            await runCleanupScan()
        }
    }

    // MARK: Dev purge

    func runPurgeScan() async {
        let roots = settings.purgeRoots, age = settings.purgeMinAgeDays
        artifacts = await run("Looking for build artifacts…") { ProjectPurge(roots: roots, minAgeDays: age).scan() }
        selectedArtifacts = Set(artifacts.filter { !$0.recentlyActive }.map(\.path))
    }

    func confirmPurge() {
        let chosen = artifacts.filter { selectedArtifacts.contains($0.path) }
        guard !chosen.isEmpty else { return }
        receipt = Receipt(title: "Purge build artifacts",
                          lines: chosen.map { ReceiptLine(path: $0.path, title: "\($0.kind) · \(Paths.abbreviate($0.project))", bytes: $0.bytes, destination: "Delete") },
                          script: nil, confirmTitle: "Purge", note: "Your build tools recreate these on the next install or build.") { [self] in
            let settings = self.settings
            let result = await run("Purging…") { () -> CleanReport in
                let r = Cleaner(settings: settings, sudo: false, runner: nil).remove(
                    chosen.map { RemovalRequest(item: ScanItem(path: $0.path, bytes: $0.bytes, isDirectory: true), scope: .user, preferTrash: false) },
                    reason: "purge")
                History.append(HistoryEntry(action: "purge", detail: "\(chosen.count) artifact folder(s)", report: r))
                return r
            }
            summarize(result)
            await runPurgeScan()
        }
    }

    // MARK: Uninstaller

    func loadApps() async {
        apps = await run("Reading installed apps…") { Uninstaller.installedApps() }
    }

    func leftovers(for app: InstalledApp) async -> [Leftover] {
        let level = settings.leftoverLevel, others = apps
        return await run("Finding \(app.name)'s files…") { Uninstaller.leftovers(for: app, level: level, otherApps: others) }
    }

    func traces(for app: InstalledApp, leftovers: [Leftover]) async -> [UninstallTrace] {
        let level = settings.leftoverLevel
        return await Task.detached { Uninstaller.traces(for: app, leftovers: leftovers, level: level) }.value
    }

    func confirmUninstall(_ app: InstalledApp, leftovers: [Leftover], traces: [UninstallTrace]) {
        let complete = settings.uninstallCompletely
        let gone = complete ? "Delete" : "Move to Trash"
        var lines = [ReceiptLine(path: app.path, title: "\(app.name).app", bytes: app.bytes,
                                 destination: app.userRemovable ? gone : "Delete as admin")]
        lines += leftovers.map { ReceiptLine(path: $0.path, title: $0.kind, bytes: $0.bytes,
                                             destination: $0.system ? "Delete as admin" : (complete || $0.kind.contains("Cache") ? "Delete" : "Move to Trash")) }
        lines += traces.map { ReceiptLine(path: "trace:\($0.kind.rawValue)", title: $0.title, bytes: 0,
                                          destination: $0.needsAdmin ? "Clear as admin" : "Clear") }
        let requests = Uninstaller.requests(app: app, leftovers: leftovers, sudo: sudo, complete: complete)
        var preview = Cleaner(settings: settings, sudo: sudo, runner: nil).privilegedPreview(requests)
        if sudo {
            // Show the trace commands too: they run in the same prompt.
            var tracesPreview = PrivilegedScript()
            for t in traces where t.needsAdmin {
                for item in t.items {
                    switch t.kind {
                    case .launchJobs where item.hasPrefix("system/"): tracesPreview.add("/bin/launchctl", ["bootout", item])
                    case .receipts: tracesPreview.add("/usr/sbin/pkgutil", ["--forget", item])
                    case .processes: tracesPreview.add("/bin/kill", ["-9", String(item.split(separator: ":").first ?? "")])
                    default: break
                    }
                }
            }
            for line in preview.lines { tracesPreview.addTrusted(line) }
            preview = tracesPreview
        }
        let needsAdmin = requests.contains { $0.scope == .system } || traces.contains(where: \.needsAdmin)
        var note: String? = complete
            ? "Complete removal: everything below is deleted permanently, including \(app.name)'s data and settings."
            : nil
        if needsAdmin && !sudo {
            let skip = machine.isAdmin ? "Some items need Sudo mode and will be skipped." : "Some items are system-level; this account can't remove them."
            note = [note, skip].compactMap { $0 }.joined(separator: " ")
        }
        receipt = Receipt(title: complete ? "Remove \(app.name) completely" : "Uninstall \(app.name)", lines: lines,
                          script: preview.isEmpty ? nil : preview,
                          confirmTitle: complete ? "Remove Completely" : "Uninstall", note: note) { [self] in
            let settings = self.settings, sudo = self.sudo, runner = self.runner, others = self.apps
            let level = settings.leftoverLevel
            let (result, left) = await run("Removing \(app.name)…") { () -> (CleanReport, [Leftover]) in
                let r = Uninstaller.uninstall(app, leftovers: leftovers, traces: traces, complete: complete,
                                              settings: settings, sudo: sudo, runner: runner)
                History.append(HistoryEntry(action: "uninstall", detail: app.name, report: r))
                let left = Uninstaller.remaining(after: app, level: level, otherApps: others).filter { complete || !$0.isUserData }
                return (r, left)
            }
            verdict = UninstallVerdict(app: app.name, remaining: left)
            if left.isEmpty && !result.removed.isEmpty {
                status = nil
                SoundFX.shared.play(.vanish)
                celebrate(Celebration(bytes: result.freedBytes, title: "\(app.name) is gone", detail: "Verified — no trace left on this Mac",
                                      symbol: "checkmark.seal.fill"))
            } else {
                summarize(result, verb: "Removed")
            }
            await loadApps()
        }
    }

    func findOrphans() async {
        let installed = apps.isEmpty ? Uninstaller.installedApps(measureSizes: false) : apps
        orphans = await run("Looking for leftovers of deleted apps…") { Orphans.find(installed: installed, minBytes: 1) }
    }

    func confirmOrphans(_ chosen: [Leftover]) {
        guard !chosen.isEmpty else { return }
        receipt = Receipt(title: "Remove orphaned files", lines: chosen.map { ReceiptLine(path: $0.path, title: $0.kind, bytes: $0.bytes, destination: "Move to Trash") },
                          script: nil, confirmTitle: "Move to Trash", note: "These belong to apps that are no longer installed. They go to the Trash so you can restore anything.") { [self] in
            let settings = self.settings
            let result = await run("Removing…") { () -> CleanReport in
                let r = Cleaner(settings: settings, sudo: false, runner: nil).remove(
                    chosen.map { RemovalRequest(item: ScanItem(path: $0.path, bytes: $0.bytes), scope: .user, preferTrash: true) }, reason: "orphans")
                History.append(HistoryEntry(action: "orphans", detail: "\(chosen.count) item(s)", report: r))
                return r
            }
            summarize(result, verb: "Moved")
            await findOrphans()
        }
    }

    func offerLeftoverCleanup(forTrashed path: String) {
        guard let app = Uninstaller.describe(path, measureSize: false) else { return }
        let level = settings.leftoverLevel
        Task {
            let found = await Task.detached { Uninstaller.leftovers(for: app, level: level).filter { !$0.system } }.value
            if !found.isEmpty { self.sentinelOffer = (app, found) }
        }
    }

    // MARK: Generic removal (Space Lens, large files, duplicates)

    func confirmRemoval(title: String, items: [(path: String, bytes: Int64)]) {
        guard !items.isEmpty else { return }
        receipt = Receipt(title: title, lines: items.map { ReceiptLine(path: $0.path, title: ($0.path as NSString).lastPathComponent, bytes: $0.bytes, destination: "Move to Trash") },
                          script: nil, confirmTitle: "Move to Trash", note: nil) { [self] in
            let settings = self.settings
            let result = await run("Moving to Trash…") { () -> CleanReport in
                let r = Cleaner(settings: settings, sudo: false, runner: nil).remove(
                    items.map { RemovalRequest(item: ScanItem(path: $0.path, bytes: $0.bytes), scope: .user, preferTrash: true) }, reason: title)
                History.append(HistoryEntry(action: "files", detail: title, report: r))
                return r
            }
            summarize(result, verb: "Moved")
        }
    }

    // MARK: Health & fleet

    func refreshHealth() async {
        health = await run("Checking health…") { Health.report() }
    }

    func publishFleet() async {
        let settings = self.settings
        let reclaimable = scan?.bytes(maxRisk: .safe)
        let health = self.health
        fleet = await Task.detached {
            _ = try? Fleet.publish(settings: settings, reclaimable: reclaimable, health: health)
            return Fleet.load(settings: settings)
        }.value
    }

    func loadHistory() { history = History.load() }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Hands scan progress from the worker thread to the UI without flooding the main actor.
final class ScanRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var stage: String?
    private var count = 0

    func post(_ s: String) {
        lock.lock(); stage = s; count += 1; lock.unlock()
    }

    func take() -> (String, Int)? {
        lock.lock(); defer { lock.unlock() }
        guard let s = stage else { return nil }
        stage = nil
        return (s, count)
    }
}
