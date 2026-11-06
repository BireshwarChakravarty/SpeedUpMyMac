import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// What a probe concluded about whether a maintenance task is worth running right now.
public enum ProbeResult: Codable, Sendable, Equatable {
    case recommended(String)
    case optional(String)
    case notNeeded(String)
    case unavailable(String)

    public var reason: String {
        switch self {
        case .recommended(let r), .optional(let r), .notNeeded(let r), .unavailable(let r): return r
        }
    }
    public var isRecommended: Bool { if case .recommended = self { return true } else { return false } }
    public var isRunnable: Bool { if case .unavailable = self { return false } else { return true } }
}

/// OnyX / Mole-optimize style maintenance. Tasks probe first and only "recommend" themselves when
/// a real symptom is present — no ritual cache rebuilding.
public enum MaintenanceTask: String, CaseIterable, Codable, Identifiable, Sendable {
    case flushDNS = "flush-dns"
    case spotlightReindex = "spotlight-reindex"
    case launchServices = "launch-services"
    case quickLook = "quicklook-reset"
    case iconCache = "icon-cache"
    case fontCaches = "font-caches"
    case brokenPreferences = "broken-preferences"
    case quarantineHistory = "quarantine-history"
    case vacuumDatabases = "vacuum-databases"
    case restartUI = "restart-ui"
    case thinSnapshots = "thin-snapshots"
    case homePermissions = "home-permissions"
    case updateXProtect = "update-xprotect"
    case periodicScripts = "periodic-scripts"
    case purgeMemory = "purge-memory"
    case gatekeeperPurge = "gatekeeper-purge"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flushDNS: return "Flush DNS cache"
        case .spotlightReindex: return "Rebuild Spotlight index"
        case .launchServices: return "Rebuild Launch Services"
        case .quickLook: return "Reset Quick Look"
        case .iconCache: return "Rebuild icon cache"
        case .fontCaches: return "Reset font caches"
        case .brokenPreferences: return "Remove corrupt preference files"
        case .quarantineHistory: return "Clear download history"
        case .vacuumDatabases: return "Compact Mail & Safari databases"
        case .restartUI: return "Restart Dock, Finder & menu bar"
        case .thinSnapshots: return "Thin local Time Machine snapshots"
        case .homePermissions: return "Repair home folder permissions"
        case .updateXProtect: return "Update XProtect now"
        case .periodicScripts: return "Run periodic maintenance scripts"
        case .purgeMemory: return "Purge disk cache from memory"
        case .gatekeeperPurge: return "Clean up Gatekeeper records"
        }
    }

    public var detail: String {
        switch self {
        case .flushDNS: return "Fixes sites that won't resolve after a network change. Skipped while a VPN is connected."
        case .spotlightReindex: return "Erases and rebuilds the index. Only worth it when search is slow or misses files; takes a while on AC power."
        case .launchServices: return "Fixes duplicate \"Open With\" entries and wrong default apps."
        case .quickLook: return "Fixes missing or stale previews and thumbnails."
        case .iconCache: return "Fixes generic or wrong app icons in Finder and the Dock."
        case .fontCaches: return "Fixes garbled text or fonts that won't activate. Restart afterwards."
        case .brokenPreferences: return "Finds .plist files that no longer parse (a common cause of apps crashing at launch) and moves them to the Trash."
        case .quarantineHistory: return "Erases the log of every file you ever downloaded (LSQuarantineEvent)."
        case .vacuumDatabases: return "Runs an integrity check and VACUUM on Mail's Envelope Index and Safari history when they're fragmented. Apps must be closed."
        case .restartUI: return "A quick fix for a stuck Dock, Finder or menu bar."
        case .thinSnapshots: return "Asks macOS to reclaim up to 50 GB from local snapshots. Snapshots are recovery points — only do this if you have a real backup."
        case .homePermissions: return "Resets ownership of your home folder. Only offered when ownership is actually wrong."
        case .updateXProtect: return "Fetches the latest malware definitions instead of waiting for the background check."
        case .periodicScripts: return "Legacy daily/weekly/monthly scripts. Removed by Apple in macOS 15."
        case .purgeMemory: return "Rarely helps on Apple silicon — macOS manages memory well. Useful only for benchmarking."
        case .gatekeeperPurge: return "macOS 27 and later: drops Gatekeeper's records for apps and tools that are no longer on this Mac (spctl purge)."
        }
    }

    public var symbol: String {
        switch self {
        case .flushDNS: return "network"
        case .spotlightReindex: return "magnifyingglass"
        case .launchServices: return "app.badge"
        case .quickLook: return "eye"
        case .iconCache: return "app.dashed"
        case .fontCaches: return "textformat"
        case .brokenPreferences: return "exclamationmark.triangle"
        case .quarantineHistory: return "clock.arrow.circlepath"
        case .vacuumDatabases: return "cylinder.split.1x2"
        case .restartUI: return "arrow.clockwise"
        case .thinSnapshots: return "camera.metering.unknown"
        case .homePermissions: return "lock.rotation"
        case .updateXProtect: return "shield.lefthalf.filled"
        case .periodicScripts: return "calendar.badge.clock"
        case .purgeMemory: return "memorychip"
        case .gatekeeperPurge: return "checkmark.shield"
        }
    }

    public var needsAdmin: Bool {
        switch self {
        case .flushDNS, .spotlightReindex, .thinSnapshots, .homePermissions, .updateXProtect, .periodicScripts, .purgeMemory,
             .gatekeeperPurge:
            return true
        default:
            return false
        }
    }

    /// Tasks whose effect is hard to undo get an extra confirmation.
    public var needsConfirmation: Bool { self == .thinSnapshots || self == .spotlightReindex || self == .quarantineHistory }

    // MARK: Probes

    public func probe(machine: MachineInfo, sudo: Bool) -> ProbeResult {
        if needsAdmin && !machine.isAdmin { return .unavailable("Needs an administrator account") }
        #if !os(macOS)
        return .unavailable("macOS only")
        #else
        switch self {
        case .flushDNS:
            return Maintenance.vpnConnected() ? .notNeeded("A VPN is connected — flushing could disrupt it")
                : .optional("Run if websites fail to load after switching networks")
        case .spotlightReindex:
            let status = Shell.run("/usr/bin/mdutil", ["-s", "/"]).stdout
            if status.contains("disabled") { return .notNeeded("Indexing is disabled on this volume") }
            let slow = Maintenance.spotlightProbeSeconds()
            if slow > 3 {
                return Maintenance.onACPower() ? .recommended(String(format: "A simple search took %.1f s", slow))
                    : .optional(String(format: "Search is slow (%.1f s) — plug in power before rebuilding", slow))
            }
            return .notNeeded(String(format: "Search responds in %.2f s", slow))
        case .brokenPreferences:
            let broken = Maintenance.corruptPreferences()
            return broken.isEmpty ? .notNeeded("All preference files parse")
                : .recommended("\(broken.count) corrupt file\(broken.count == 1 ? "" : "s") found")
        case .quarantineHistory:
            let n = Maintenance.quarantineEventCount()
            return n > 0 ? .optional("\(n) downloads recorded") : .notNeeded("History is empty")
        case .vacuumDatabases:
            if !Maintenance.running(["Mail", "Safari"]).isEmpty { return .unavailable("Quit Mail and Safari first") }
            return Maintenance.fragmentedDatabases().isEmpty ? .notNeeded("Databases are compact")
                : .recommended("Fragmented databases found")
        case .thinSnapshots:
            let n = Maintenance.localSnapshots().count
            return n > 0 ? .optional("\(n) local snapshot\(n == 1 ? "" : "s") on the startup disk") : .notNeeded("No local snapshots")
        case .homePermissions:
            return Maintenance.homePermissionsBroken() ? .recommended("Your home folder has the wrong owner or isn't writable")
                : .unavailable("Ownership is correct — nothing to repair")
        case .updateXProtect:
            return machine.osMajor >= 15 ? .optional("Fetch the latest definitions") : .unavailable("Needs macOS 15 or later")
        case .periodicScripts:
            return machine.osMajor >= 15 ? .unavailable("Removed in macOS 15 — macOS does this itself now")
                : .optional("Legacy maintenance")
        case .purgeMemory:
            return .optional("Diagnostic only")
        case .gatekeeperPurge:
            if OSFeatures.gatekeeperPurgeArguments != nil { return .optional("Removes records left by apps you've deleted") }
            return .unavailable(machine.osMajor >= 27 ? "This version of spctl has no purge command" : "Needs macOS 27 or later")
        case .launchServices, .quickLook, .iconCache, .fontCaches, .restartUI:
            return .optional("Run when you see the symptom described")
        }
        #endif
    }

    // MARK: Plans

    /// Commands to run as the user, and lines for the root script.
    public func plan(sudo: Bool) -> (user: [[String]], root: PrivilegedScript) {
        var user: [[String]] = []
        var root = PrivilegedScript()
        let uid = getuid()
        switch self {
        case .flushDNS:
            root.add("/usr/bin/dscacheutil", ["-flushcache"])
            root.add("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        case .spotlightReindex:
            root.add("/usr/bin/mdutil", ["-E", "/"])
        case .launchServices:
            user.append([Maintenance.lsregister, "-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
        case .quickLook:
            user.append(["/usr/bin/qlmanage", "-r", "cache"])
            user.append(["/usr/bin/qlmanage", "-r"])
        case .iconCache:
            for path in Paths.glob("~/Library/Caches/com.apple.iconservices*") { user.append(["/bin/rm", "-rf", "--", path]) }
            if sudo { root.remove("/Library/Caches/com.apple.iconservices.store") }
            user.append(["/usr/bin/killall", "Dock"])
            user.append(["/usr/bin/killall", "Finder"])
        case .fontCaches:
            user.append(["/usr/bin/atsutil", "databases", "-removeUser"])
            if sudo { root.add("/usr/bin/atsutil", ["databases", "-remove"]) }
            user.append(["/usr/bin/atsutil", "server", "-shutdown"])
            user.append(["/usr/bin/atsutil", "server", "-ping"])
        case .brokenPreferences:
            break // handled natively by Maintenance.run (moves files to Trash)
        case .quarantineHistory:
            user.append(["/usr/bin/sqlite3", Paths.expand("~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"),
                         "DELETE FROM LSQuarantineEvent; VACUUM;"])
        case .vacuumDatabases:
            for db in Maintenance.fragmentedDatabases() { user.append(["/usr/bin/sqlite3", db, "VACUUM;"]) }
        case .restartUI:
            user.append(["/usr/bin/killall", "Dock"])
            user.append(["/usr/bin/killall", "Finder"])
            user.append(["/usr/bin/killall", "SystemUIServer"])
        case .thinSnapshots:
            root.add("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "50000000000", "4"])
        case .homePermissions:
            root.add("/usr/sbin/diskutil", ["resetUserPermissions", "/", "\(uid)"])
        case .updateXProtect:
            root.add("/usr/bin/xprotect", ["update"])
        case .periodicScripts:
            root.add("/usr/sbin/periodic", ["daily", "weekly", "monthly"])
        case .purgeMemory:
            root.add("/usr/sbin/purge")
        case .gatekeeperPurge:
            if let args = OSFeatures.gatekeeperPurgeArguments { root.add("/usr/sbin/spctl", args) }
        }
        return (user, root)
    }
}

public struct MaintenanceOutcome: Sendable {
    public var task: MaintenanceTask
    public var succeeded: Bool
    public var output: String
}

public enum Maintenance {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Runs tasks: user commands first, then a single root script for every admin step.
    public static func run(_ tasks: [MaintenanceTask], sudo: Bool, runner: PrivilegeRunner?, dryRun: Bool = false) -> [MaintenanceOutcome] {
        var outcomes: [MaintenanceOutcome] = []
        var combined = PrivilegedScript()
        var rootTasks: [MaintenanceTask] = []
        for task in tasks {
            if task.needsAdmin && !sudo {
                outcomes.append(MaintenanceOutcome(task: task, succeeded: false, output: "Skipped: turn on Sudo mode"))
                continue
            }
            let plan = task.plan(sudo: sudo)
            var output = ""
            var ok = true
            if task == .brokenPreferences {
                let broken = corruptPreferences()
                let report = Cleaner(settings: Settings(), sudo: false, runner: nil, dryRun: dryRun)
                    .remove(broken.map { RemovalRequest(item: ScanItem(path: $0, bytes: 0), scope: .user, preferTrash: true) },
                            reason: "remove corrupt preferences")
                output = "Moved \(report.removed.count) corrupt file(s) to the Trash"
                ok = report.failures.isEmpty
            }
            for cmd in plan.user {
                if dryRun { output += "would run: \(cmd.joined(separator: " "))\n"; continue }
                let r = Shell.run(cmd[0], Array(cmd.dropFirst()), timeout: 600)
                output += r.stdout + r.stderr
                // killall exits 1 when the process wasn't running; that's fine.
                if !r.succeeded && !cmd[0].hasSuffix("killall") { ok = false }
            }
            if plan.root.isEmpty {
                outcomes.append(MaintenanceOutcome(task: task, succeeded: ok, output: output))
            } else {
                for line in plan.root.lines { combined.addTrusted(line) }
                rootTasks.append(task)
                outcomes.append(MaintenanceOutcome(task: task, succeeded: ok, output: output))
            }
        }
        guard !combined.isEmpty else { return outcomes }
        if dryRun {
            for i in outcomes.indices where rootTasks.contains(outcomes[i].task) {
                outcomes[i].output += "would run as root:\n" + combined.text
            }
            return outcomes
        }
        do {
            guard let runner else { throw PrivilegeError.failed("No privilege runner") }
            let r = try runner.run(combined, reason: "run maintenance tasks")
            for i in outcomes.indices where rootTasks.contains(outcomes[i].task) {
                outcomes[i].output += r.stdout + r.stderr
                outcomes[i].succeeded = outcomes[i].succeeded && r.succeeded
            }
        } catch {
            for i in outcomes.indices where rootTasks.contains(outcomes[i].task) {
                outcomes[i].succeeded = false
                outcomes[i].output += error.localizedDescription
            }
        }
        return outcomes
    }

    // MARK: Probe helpers

    static func vpnConnected() -> Bool {
        if Shell.run("/usr/sbin/scutil", ["--nc", "list"]).stdout.contains("(Connected)") { return true }
        let route = Shell.run("/sbin/route", ["-n", "get", "default"]).stdout
        return route.contains("interface: utun") || route.contains("interface: ipsec") || route.contains("interface: ppp")
    }

    static func onACPower() -> Bool {
        Shell.run("/usr/bin/pmset", ["-g", "batt"]).stdout.contains("AC Power")
    }

    /// Times a trivial Spotlight query twice and returns the faster run.
    static func spotlightProbeSeconds() -> Double {
        var best = Double.infinity
        for _ in 0..<2 {
            let start = Date()
            _ = Shell.run("/usr/bin/mdfind", ["-onlyin", "/Applications", "kMDItemFSName == 'Safari.app'"], timeout: 20)
            best = min(best, Date().timeIntervalSince(start))
        }
        return best
    }

    public static func corruptPreferences() -> [String] {
        let dir = Paths.expand("~/Library/Preferences")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".plist") }
        return files.compactMap { name in
            let path = (dir as NSString).appendingPathComponent(name)
            guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil ? path : nil
        }
    }

    static func quarantineEventCount() -> Int {
        let db = Paths.expand("~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
        guard FileManager.default.fileExists(atPath: db) else { return 0 }
        let r = Shell.run("/usr/bin/sqlite3", [db, "SELECT COUNT(*) FROM LSQuarantineEvent;"])
        return Int(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Mail/Safari SQLite files under 1 GB with ≥10% free pages that pass an integrity check.
    static func fragmentedDatabases() -> [String] {
        let candidates = Paths.glob("~/Library/Mail/V*/MailData/Envelope Index") + Paths.glob("~/Library/Safari/History.db")
        return candidates.filter { db in
            guard let size = (try? FileManager.default.attributesOfItem(atPath: db))?[.size] as? Int64,
                  size < 1_000_000_000 else { return false }
            let r = Shell.run("/usr/bin/sqlite3", [db, "PRAGMA page_count; PRAGMA freelist_count; PRAGMA quick_check;"], timeout: 30)
            let lines = r.stdout.split(separator: "\n").map(String.init)
            guard r.succeeded, lines.count >= 3, let pages = Double(lines[0]), let free = Double(lines[1]),
                  pages > 0, lines[2] == "ok" else { return false }
            return free / pages >= 0.10
        }
    }

    public static func localSnapshots() -> [String] {
        Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).stdout.split(separator: "\n")
            .map(String.init).filter { $0.contains("com.apple.TimeMachine") }
    }

    static func homePermissionsBroken() -> Bool {
        let home = Paths.home
        guard let owner = (try? FileManager.default.attributesOfItem(atPath: home))?[.ownerAccountID] as? NSNumber else { return false }
        if owner.uint32Value != getuid() { return true }
        let paths = [home, home + "/Library", home + "/Library/Preferences"]
        return paths.contains { (path: String) in access(path, W_OK) != 0 }
    }

    static func running(_ names: [String]) -> [String] {
        let all = ProcessList.runningNames()
        return names.filter(all.contains)
    }
}
