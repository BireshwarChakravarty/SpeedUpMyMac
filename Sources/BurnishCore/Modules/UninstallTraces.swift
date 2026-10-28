import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Something an app leaves behind that isn't a file you can delete: a running helper, a loaded launchd
/// job, cached preferences, a Launch Services registration, privacy grants, a Login Item, a Dock tile or
/// an installer receipt. A complete uninstall clears these before the files go, so nothing respawns.
public struct UninstallTrace: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case processes, launchJobs, preferences, launchServices, privacy, loginItem, dock, receipts
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    /// Kind-specific payload: pids, launchd service targets, preference domains, bundle IDs, package IDs…
    public var items: [String]
    public var needsAdmin: Bool

    public var id: String { kind.rawValue }

    public var symbol: String {
        switch kind {
        case .processes: return "bolt.horizontal.circle"
        case .launchJobs: return "power"
        case .preferences: return "gearshape"
        case .launchServices: return "square.stack.3d.down.right"
        case .privacy: return "hand.raised"
        case .loginItem: return "person.crop.circle.badge.xmark"
        case .dock: return "dock.rectangle"
        case .receipts: return "shippingbox"
        }
    }
}

public extension Uninstaller {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Everything besides files that a complete uninstall of `app` will clear.
    static func traces(for app: InstalledApp, leftovers: [Leftover], level: MatchLevel = .enhanced) -> [UninstallTrace] {
        var traces: [UninstallTrace] = []
        let ids = Array(Set([app.bundleID] + app.embeddedBundleIDs)).sorted()

        let procs = runningProcesses(inside: app.path)
        if !procs.isEmpty {
            traces.append(UninstallTrace(kind: .processes, title: "Quit \(procs.count) running process\(procs.count == 1 ? "" : "es")",
                                         detail: "The app and its helpers, so nothing recreates files mid-removal",
                                         items: procs.map { "\($0.pid):\($0.uid)" }, needsAdmin: procs.contains { $0.uid != getuid() }))
        }

        let jobs = launchJobs(for: app, ids: ids, leftovers: leftovers)
        if !jobs.isEmpty {
            traces.append(UninstallTrace(kind: .launchJobs, title: "Unload \(jobs.count) background job\(jobs.count == 1 ? "" : "s")",
                                         detail: jobs.map { $0.components(separatedBy: "/").last ?? $0 }.joined(separator: ", "),
                                         items: jobs, needsAdmin: jobs.contains { $0.hasPrefix("system/") }))
        }

        let domains = preferenceDomains(in: leftovers)
        if !domains.isEmpty {
            traces.append(UninstallTrace(kind: .preferences, title: "Flush \(domains.count) preference domain\(domains.count == 1 ? "" : "s")",
                                         detail: "Clears the preferences cache too, so macOS can't write the settings back",
                                         items: domains, needsAdmin: false))
        }

        traces.append(UninstallTrace(kind: .launchServices, title: "Unregister from Launch Services",
                                     detail: "Removes it from Open With menus and file-type defaults", items: [app.path], needsAdmin: false))
        traces.append(UninstallTrace(kind: .privacy, title: "Reset privacy permissions",
                                     detail: "Camera, microphone, screen recording, accessibility and other grants for \(ids.count) bundle ID\(ids.count == 1 ? "" : "s")",
                                     items: ids, needsAdmin: false))
        traces.append(UninstallTrace(kind: .loginItem, title: "Remove from Login Items",
                                     detail: "If it's listed in System Settings → General → Login Items", items: [app.name], needsAdmin: false))
        if dockContains(app.path) {
            traces.append(UninstallTrace(kind: .dock, title: "Remove from the Dock", detail: "Restarts the Dock", items: [app.path], needsAdmin: false))
        }
        let pkgs = packageIDs(for: app, level: level)
        if !pkgs.isEmpty {
            traces.append(UninstallTrace(kind: .receipts, title: "Forget \(pkgs.count) installer receipt\(pkgs.count == 1 ? "" : "s")",
                                         detail: pkgs.joined(separator: ", "), items: pkgs, needsAdmin: true))
        }
        return traces
    }

    /// Clears traces that need no admin rights right away and returns the root part as a script, to run
    /// in the same authorization as the file removal. Root parts are dropped when `sudo` is off.
    @discardableResult
    static func clearTraces(_ traces: [UninstallTrace], sudo: Bool) -> PrivilegedScript {
        var root = PrivilegedScript()
        let me = getuid()
        for trace in traces {
            switch trace.kind {
            case .processes:
                var mine: [pid_t] = []
                for item in trace.items {
                    let parts = item.split(separator: ":")
                    guard parts.count == 2, let pid = pid_t(parts[0]), let uid = uid_t(parts[1]) else { continue }
                    if uid == me { mine.append(pid) } else if sudo { root.add("/bin/kill", ["-9", String(pid)]) }
                }
                terminate(mine)
            case .launchJobs:
                for target in trace.items {
                    if target.hasPrefix("system/") {
                        if sudo { root.add("/bin/launchctl", ["bootout", target]) }
                    } else {
                        Shell.run("/bin/launchctl", ["bootout", target], timeout: 15)
                    }
                }
            case .preferences:
                for domain in trace.items {
                    if domain.hasPrefix("host:") {
                        Shell.run("/usr/bin/defaults", ["-currentHost", "delete", String(domain.dropFirst(5))], timeout: 10)
                    } else {
                        Shell.run("/usr/bin/defaults", ["delete", domain], timeout: 10)
                    }
                }
            case .launchServices:
                for path in trace.items { Shell.run(lsregister, ["-u", path], timeout: 30) }
            case .privacy:
                for id in trace.items {
                    Shell.run("/usr/bin/tccutil", ["reset", "All", id], timeout: 10)
                    if sudo { root.add("/usr/bin/tccutil", ["reset", "All", id]) }
                }
            case .loginItem:
                for name in trace.items {
                    Shell.run("/usr/bin/osascript", ["-e", "on run argv",
                                                     "-e", "tell application \"System Events\" to delete (every login item whose name is (item 1 of argv))",
                                                     "-e", "end run", name], timeout: 10)
                }
            case .dock:
                for path in trace.items where removeFromDock(path) { Shell.run("/usr/bin/killall", ["Dock"], timeout: 5) }
            case .receipts:
                if sudo { for pkg in trace.items { root.add("/usr/sbin/pkgutil", ["--forget", pkg]) } }
            }
        }
        return root
    }

    // MARK: Discovery

    struct RunningProcess: Equatable { var pid: pid_t; var uid: uid_t }

    /// Processes whose executable lives inside the bundle.
    static func runningProcesses(inside appPath: String) -> [RunningProcess] {
        #if os(macOS)
        guard let r = Shell.runTool("ps", ["-axww", "-o", "pid=,uid=,args="], timeout: 10), r.succeeded else { return [] }
        return parseProcesses(r.stdout, inside: appPath).filter { $0.pid != getpid() }
        #else
        return []
        #endif
    }

    static func parseProcesses(_ output: String, inside appPath: String) -> [RunningProcess] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]), let uid = uid_t(fields[1]) else { return nil }
            // `args` starts with the executable path; the arguments after it don't matter here.
            return String(fields[2]).hasPrefix(appPath + "/") ? RunningProcess(pid: pid, uid: uid) : nil
        }
    }

    /// launchd service targets (`gui/<uid>/<label>` or `system/<label>`) belonging to the app.
    static func launchJobs(for app: InstalledApp, ids: [String], leftovers: [Leftover]) -> [String] {
        var targets = Set<String>()
        let uid = getuid()
        func label(of plist: String) -> String? { readPlist(plist)?["Label"] as? String }
        // Plists the uninstall will delete, and ones registered from inside the bundle (SMAppService).
        for l in leftovers where l.path.hasSuffix(".plist") && (l.kind == "Launch Agent" || l.kind == "Launch Daemon") {
            if let name = label(of: l.path) { targets.insert(l.kind == "Launch Daemon" ? "system/\(name)" : "gui/\(uid)/\(name)") }
        }
        for (sub, daemon) in [("Contents/Library/LaunchAgents", false), ("Contents/Library/LaunchDaemons", true)] {
            let dir = (app.path as NSString).appendingPathComponent(sub)
            for file in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".plist") {
                if let name = label(of: (dir as NSString).appendingPathComponent(file)) {
                    targets.insert(daemon ? "system/\(name)" : "gui/\(uid)/\(name)")
                }
            }
        }
        // Loaded jobs in this user's domain whose label is one of the app's bundle IDs.
        #if os(macOS)
        if let r = Shell.runTool("launchctl", ["list"], timeout: 10), r.succeeded {
            for name in loadedLabels(r.stdout) where ownsLabel(name, ids: ids) { targets.insert("gui/\(uid)/\(name)") }
        }
        #endif
        return targets.sorted()
    }

    static func loadedLabels(_ output: String) -> [String] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: "\t")
            return fields.count == 3 ? String(fields[2]) : nil
        }
    }

    static func ownsLabel(_ label: String, ids: [String]) -> Bool {
        let lower = label.lowercased()
        return ids.map { $0.lowercased() }.contains { lower == $0 || lower.hasPrefix($0 + ".") }
    }

    /// Preference domains for plists in ~/Library/Preferences (`host:` marks ByHost domains).
    static func preferenceDomains(in leftovers: [Leftover]) -> [String] {
        let prefs = Paths.expand("~/Library/Preferences")
        let byHost = (prefs as NSString).appendingPathComponent("ByHost")
        var domains = Set<String>()
        for l in leftovers where l.path.hasSuffix(".plist") {
            let folder = (l.path as NSString).deletingLastPathComponent
            let name = String(((l.path as NSString).lastPathComponent).dropLast(".plist".count))
            if folder == prefs {
                domains.insert(name)
            } else if folder == byHost, let dot = name.lastIndex(of: ".") {
                // ByHost files are `<domain>.<hardware UUID>.plist`.
                domains.insert("host:" + name[..<dot])
            }
        }
        return domains.sorted()
    }

    // MARK: Actions

    /// SIGTERM, a short grace period, then SIGKILL for anything still alive.
    static func terminate(_ pids: [pid_t]) {
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, pids.contains(where: { kill($0, 0) == 0 }) { usleep(100_000) }
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    static func dockContains(_ appPath: String) -> Bool {
        #if os(macOS)
        return dockEntries().contains { entry in Self.dockEntry(entry, points: appPath) }
        #else
        return false
        #endif
    }

    #if os(macOS)
    static func dockEntries() -> [[String: Any]] {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        return (CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]]) ?? []
    }
    #endif

    static func dockEntry(_ entry: [String: Any], points appPath: String) -> Bool {
        guard let tile = entry["tile-data"] as? [String: Any], let file = tile["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return false }
        let path = URL(string: string)?.path ?? string
        return Paths.normalize(path) == Paths.normalize(appPath)
    }

    /// Drops the app's tile from the Dock. Returns true when something changed.
    static func removeFromDock(_ appPath: String) -> Bool {
        #if os(macOS)
        let entries = dockEntries()
        let kept = entries.filter { !dockEntry($0, points: appPath) }
        guard kept.count != entries.count else { return false }
        CFPreferencesSetAppValue("persistent-apps" as CFString, kept as CFArray, "com.apple.dock" as CFString)
        return CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        #else
        return false
        #endif
    }
}

public extension Uninstaller {
    /// The whole uninstall: quit the app, clear its traces, then remove the bundle and leftovers.
    /// Root steps (system daemons, receipts, root-owned files) share a single authorization.
    static func uninstall(_ app: InstalledApp, leftovers: [Leftover], traces: [UninstallTrace], complete: Bool,
                          settings: Settings, sudo: Bool, runner: PrivilegeRunner?, dryRun: Bool = false) -> CleanReport {
        var root = PrivilegedScript()
        if !dryRun {
            #if os(macOS)
            // Ask nicely first (unsaved documents); `clearTraces` terminates whatever is left.
            if !runningProcesses(inside: app.path).isEmpty {
                Shell.run("/usr/bin/osascript", ["-e", "on run argv", "-e", "tell application id (item 1 of argv) to quit", "-e", "end run",
                                                 app.bundleID], timeout: 10)
            }
            #endif
            root = clearTraces(traces, sudo: sudo)
        }
        let requests = self.requests(app: app, leftovers: leftovers, sudo: sudo, complete: complete)
        let base: PrivilegeRunner? = runner.map { root.isEmpty ? $0 : PrependingRunner(prefix: root, base: $0) }
        var report = Cleaner(settings: settings, sudo: sudo, runner: base, dryRun: dryRun).remove(requests, reason: "uninstall \(app.name)")
        // Nothing needed root for files, but traces did (system daemons, receipts): run those on their own.
        if !dryRun, sudo, !root.isEmpty, report.script == nil, let runner {
            do { _ = try runner.run(root, reason: "clear \(app.name) system traces") } catch {
                report.failures.append(RemovalFailure(path: "\(app.name) system traces", reason: error.localizedDescription))
            }
        }
        return report
    }
}
