import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct ProcessInfoRow: Codable, Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var uid: UInt32
    public var cpu: Double
    public var memoryBytes: Int64
    public var name: String
    public var state: String

    public var isMine: Bool { uid == getuid() }
    /// Stopped via SIGSTOP (by Root or anything else).
    public var isPaused: Bool { state.hasPrefix("T") }
}

/// App Tamer–style process control. Works on your own processes without admin.
public enum Processes {
    public static func list() -> [ProcessInfoRow] {
        // -c: executable name only; rss is KB.
        #if os(macOS)
        let r = Shell.run("/bin/ps", ["-axco", "pid=,uid=,%cpu=,rss=,state=,comm="])
        #else
        let r = Shell.run("/bin/ps", ["-axo", "pid=,uid=,%cpu=,rss=,state=,comm="])
        #endif
        return r.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count == 6, let pid = Int32(parts[0]), let uid = UInt32(parts[1]),
                  let cpu = Double(parts[2]), let rss = Int64(parts[3]) else { return nil }
            return ProcessInfoRow(pid: pid, uid: uid, cpu: cpu, memoryBytes: rss * 1024, name: String(parts[5]),
                                  state: String(parts[4]))
        }
    }

    public static func top(by key: KeyPath<ProcessInfoRow, Double>, limit: Int = 15) -> [ProcessInfoRow] {
        Array(list().sorted { $0[keyPath: key] > $1[keyPath: key] }.prefix(limit))
    }

    public static func topMemory(limit: Int = 15) -> [ProcessInfoRow] {
        Array(list().sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
    }

    public enum Action: String, CaseIterable, Sendable {
        case quit, forceQuit, pause, resume, efficiencyCores, normalPriority
    }

    /// Never act on these, even for the user's own copies.
    static let protectedNames: Set<String> = ["WindowServer", "loginwindow", "launchd", "kernel_task", "Finder", "Dock",
                                              "SystemUIServer", "ControlCenter", "Root", "RootApp", "root"]

    @discardableResult
    public static func perform(_ action: Action, on process: ProcessInfoRow) -> Bool {
        guard process.isMine || Privilege.isRoot, !protectedNames.contains(process.name) else { return false }
        switch action {
        case .quit: return kill(process.pid, SIGTERM) == 0
        case .forceQuit: return kill(process.pid, SIGKILL) == 0
        case .pause: return kill(process.pid, SIGSTOP) == 0
        case .resume: return kill(process.pid, SIGCONT) == 0
        case .efficiencyCores:
            // Background QoS: the scheduler keeps the process on efficiency cores (App Tamer's E-core mode).
            return Shell.run("/usr/sbin/taskpolicy", ["-b", "-p", "\(process.pid)"]).succeeded
        case .normalPriority:
            return Shell.run("/usr/sbin/taskpolicy", ["-B", "-p", "\(process.pid)"]).succeeded
        }
    }
}
