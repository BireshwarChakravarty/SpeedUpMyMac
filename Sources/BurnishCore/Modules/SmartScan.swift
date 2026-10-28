import Foundation

/// One-button overview (CleanMyMac Smart Care): junk, dev artifacts, health, maintenance and startup issues.
public struct SmartScanResult: Sendable {
    public var cleanup: ScanReport
    public var artifacts: [ProjectArtifact]
    public var health: HealthReport
    public var recommendedTasks: [MaintenanceTask]
    public var suspiciousStartupItems: [StartupItem]

    /// Bytes that a "Burnish now" would free: safe cleanup + idle project artifacts.
    public var quickWinBytes: Int64 {
        cleanup.results.filter { $0.target.risk == .safe && $0.skippedReason == nil }.reduce(0) { $0 + $1.bytes }
            + artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
    }

    /// Additional bytes available by turning on Sudo mode.
    public var sudoOnlyBytes: Int64 {
        cleanup.results.filter { $0.target.scope == .system && $0.skippedReason == "Needs Sudo mode" && $0.target.risk == .safe }
            .reduce(0) { $0 + $1.bytes }
    }
}

public enum SmartScan {
    public static func run(settings: Settings, sudo: Bool, progress: ((String) -> Void)? = nil) -> SmartScanResult {
        progress?("Looking for junk…")
        let cleanup = Scanner(settings: settings, sudo: sudo).scan { progress?("Scanning \($0.title)…") }
        progress?("Looking for build artifacts…")
        let artifacts = ProjectPurge(roots: settings.purgeRoots, minAgeDays: settings.purgeMinAgeDays).scan()
        progress?("Checking health…")
        let health = Health.report()
        progress?("Checking maintenance…")
        let machine = health.machine
        let tasks = MaintenanceTask.allCases.filter { $0.probe(machine: machine, sudo: sudo).isRecommended }
        progress?("Auditing startup items…")
        let startup = StartupItems.scan().filter { $0.signing.suspicious && !$0.disabled }
        return SmartScanResult(cleanup: cleanup, artifacts: artifacts, health: health, recommendedTasks: tasks,
                               suspiciousStartupItems: startup)
    }

    /// Unattended run used by the scheduled LaunchAgent: safe, user-scope items only, never sudo.
    public static func autoclean(settings: Settings) -> CleanReport {
        let scan = Scanner(settings: settings, sudo: false).scan()
        let selected = scan.results.filter {
            $0.target.risk == .safe && $0.target.scope == .user && $0.skippedReason == nil && !isCommand($0.target)
        }
        let report = Cleaner(settings: settings, sudo: false, runner: nil).clean(selected)
        History.append(HistoryEntry(action: "autoclean", detail: "Scheduled clean", report: report))
        let reclaimable = Scanner(settings: settings, sudo: false).scan().bytes(maxRisk: .safe)
        _ = try? Fleet.publish(settings: settings, reclaimable: reclaimable, health: Health.report(includeSecurity: false))
        return report
    }

    static func isCommand(_ target: CleanupTarget) -> Bool {
        if case .command = target.kind { return true }
        return false
    }
}
