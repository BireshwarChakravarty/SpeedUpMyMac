import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum RemovalMethod: String, Codable, Sendable {
    /// Moved to the user's Trash.
    case trash
    /// Deleted as the user.
    case delete
    /// Deleted by the privileged script.
    case root
    /// Freed by running a tool (brew cleanup, simctl…).
    case command
}

public struct RemovedItem: Codable, Sendable {
    public var path: String
    public var bytes: Int64
    public var method: RemovalMethod
}

public struct RemovalFailure: Codable, Sendable {
    public var path: String
    public var reason: String
}

public struct CleanReport: Codable, Sendable {
    public var removed: [RemovedItem] = []
    public var failures: [RemovalFailure] = []
    /// Items that need root but sudo was off; reported so the UI can explain.
    public var needsSudo: [ScanItem] = []
    public var dryRun = false
    public var script: PrivilegedScript?

    public init() {}

    public var freedBytes: Int64 { removed.reduce(0) { $0 + $1.bytes } }

    public mutating func merge(_ other: CleanReport) {
        removed += other.removed
        failures += other.failures
        needsSudo += other.needsSudo
        if let s = other.script {
            var merged = script ?? PrivilegedScript()
            for line in s.lines { merged.addTrusted(line) }
            script = merged
        }
    }
}

extension PrivilegedScript: Codable {
    public init(from decoder: Decoder) throws {
        self.init()
        for line in try decoder.singleValueContainer().decode([String].self) { addTrusted(line) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(lines)
    }
}

/// A request to remove something: what, how big, who must do it, and whether Trash is preferred.
public struct RemovalRequest: Sendable {
    public var item: ScanItem
    public var scope: Scope
    public var preferTrash: Bool

    public init(item: ScanItem, scope: Scope, preferTrash: Bool) {
        self.item = item
        self.scope = scope
        self.preferTrash = preferTrash
    }
}

/// Executes removals. All paths are re-validated by `Safety` immediately before acting.
public struct Cleaner {
    public var settings: Settings
    public var sudo: Bool
    public var runner: PrivilegeRunner?
    public var dryRun: Bool

    public init(settings: Settings, sudo: Bool, runner: PrivilegeRunner?, dryRun: Bool = false) {
        self.settings = settings
        self.sudo = sudo
        self.runner = runner
        self.dryRun = dryRun
    }

    /// Cleans the given catalog results. Pass only the items the user selected.
    public func clean(_ selections: [TargetResult]) -> CleanReport {
        var report = CleanReport()
        report.dryRun = dryRun
        var requests: [RemovalRequest] = []
        for selection in selections {
            if case .command(let tool, let arguments, _) = selection.target.kind {
                report.merge(runCommand(selection, tool: tool, arguments: arguments))
                continue
            }
            for item in selection.items {
                requests.append(RemovalRequest(item: item, scope: selection.target.scope, preferTrash: selection.target.useTrash))
            }
        }
        report.merge(remove(requests, reason: "clean system caches and logs"))
        return report
    }

    /// The root script `remove` would run for these requests (for the receipt preview).
    public func privilegedPreview(_ requests: [RemovalRequest]) -> PrivilegedScript {
        var script = PrivilegedScript()
        for r in requests where r.scope == .system && Safety.isAllowed(r.item.path) { script.remove(r.item.path) }
        return script
    }

    /// Removes arbitrary items (used by cleanup, uninstall, purge and Space Lens).
    public func remove(_ requests: [RemovalRequest], reason: String) -> CleanReport {
        var report = CleanReport()
        report.dryRun = dryRun
        var escalate: [ScanItem] = []

        for request in requests {
            let item = request.item
            do {
                try Safety.validateForDeletion(item.path)
            } catch {
                report.failures.append(RemovalFailure(path: item.path, reason: error.localizedDescription))
                continue
            }
            guard Paths.lexists(item.path) else { continue }

            if request.scope == .system {
                if sudo { escalate.append(item) } else { report.needsSudo.append(item) }
                continue
            }
            let trash = request.preferTrash || settings.alwaysUseTrash
            if dryRun {
                report.removed.append(RemovedItem(path: item.path, bytes: item.bytes, method: trash ? .trash : .delete))
                continue
            }
            do {
                try removeAsUser(item.path, trash: trash)
                report.removed.append(RemovedItem(path: item.path, bytes: item.bytes, method: trash ? .trash : .delete))
            } catch {
                // Root-owned files inside user folders (e.g. from an old `sudo brew`) get escalated.
                if sudo && isPermissionError(error) { escalate.append(item) } else {
                    report.failures.append(RemovalFailure(path: item.path, reason: describe(error)))
                }
            }
        }

        guard !escalate.isEmpty else { return report }
        var script = PrivilegedScript()
        for item in escalate { script.remove(item.path) }
        report.script = script
        if dryRun {
            report.removed += escalate.map { RemovedItem(path: $0.path, bytes: $0.bytes, method: .root) }
            return report
        }
        guard let runner else {
            report.failures += escalate.map { RemovalFailure(path: $0.path, reason: "No privilege runner available") }
            return report
        }
        do {
            let result = try runner.run(script, reason: reason)
            for item in escalate {
                if Paths.lexists(item.path) {
                    let why = result.stderr.isEmpty ? "Still present after privileged removal (SIP-protected?)" : result.stderr
                    report.failures.append(RemovalFailure(path: item.path, reason: why.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    report.removed.append(RemovedItem(path: item.path, bytes: item.bytes, method: .root))
                }
            }
        } catch {
            report.failures += escalate.map { RemovalFailure(path: $0.path, reason: error.localizedDescription) }
        }
        return report
    }

    func removeAsUser(_ path: String, trash: Bool) throws {
        #if os(macOS)
        if trash {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
            return
        }
        #endif
        try FileManager.default.removeItem(atPath: path)
    }

    func runCommand(_ selection: TargetResult, tool: String, arguments: [String]) -> CleanReport {
        var report = CleanReport()
        report.dryRun = dryRun
        let before = selection.bytes
        if dryRun {
            report.removed.append(RemovedItem(path: "\(tool) \(arguments.joined(separator: " "))", bytes: before, method: .command))
            return report
        }
        guard let result = Shell.runTool(tool, arguments, timeout: 900) else {
            report.failures.append(RemovalFailure(path: tool, reason: "\(tool) is not installed"))
            return report
        }
        guard result.succeeded else {
            let message = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            report.failures.append(RemovalFailure(path: "\(tool) \(arguments.joined(separator: " "))",
                                                  reason: String(message.prefix(400))))
            return report
        }
        let after = FileSizer.total(selection.items.map(\.path))
        report.removed.append(RemovedItem(path: "\(tool) \(arguments.joined(separator: " "))",
                                          bytes: max(before - after, 0), method: .command))
        return report
    }

    func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(EACCES) || underlying.code == Int(EPERM)
        }
        return false
    }

    func describe(_ error: Error) -> String {
        let ns = error as NSError
        if isPermissionError(error) { return "Permission denied (grant Full Disk Access, or turn on Sudo mode)" }
        return ns.localizedDescription
    }
}
