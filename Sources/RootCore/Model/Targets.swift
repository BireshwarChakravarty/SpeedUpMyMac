import Foundation

/// How sure we are that removing something is harmless.
public enum Risk: String, Codable, Comparable, CaseIterable, Sendable {
    /// Regenerated automatically; pre-selected.
    case safe
    /// Probably junk, but look first; not pre-selected.
    case review
    /// Real data or hard to undo (backups, archives, snapshots); never pre-selected.
    case risky

    private var order: Int { [.safe: 0, .review: 1, .risky: 2][self]! }
    public static func < (a: Risk, b: Risk) -> Bool { a.order < b.order }
}

/// Who has to do the deleting.
public enum Scope: String, Codable, Sendable {
    case user
    /// Needs root: only offered when the Sudo toggle is on.
    case system
}

public enum TargetCategory: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case caches = "App Caches"
    case logs = "Logs & Reports"
    case browsers = "Browsers"
    case developer = "Developer"
    case communication = "Mail & Messages"
    case devices = "iPhone & iPad"
    case cloud = "Cloud & Sync"
    case installers = "Installers & Downloads"
    case trash = "Trash"
    case privacy = "Privacy Traces"

    public var symbol: String {
        switch self {
        case .system: return "gearshape.2"
        case .caches: return "square.stack.3d.up"
        case .logs: return "doc.text.magnifyingglass"
        case .browsers: return "safari"
        case .developer: return "hammer"
        case .communication: return "envelope"
        case .devices: return "iphone"
        case .cloud: return "icloud"
        case .installers: return "shippingbox"
        case .trash: return "trash"
        case .privacy: return "hand.raised"
        }
    }
}

/// What a target points at.
public enum TargetKind: Codable, Sendable, Equatable {
    /// Every child of each (globbed) directory becomes a removable item.
    case contents([String])
    /// Each (globbed) path is itself a removable item.
    case paths([String])
    /// Files under a directory whose names match any glob, optionally recursive (depth-limited).
    case files(root: String, patterns: [String], maxDepth: Int)
    /// A tool-driven cleanup (e.g. `brew cleanup`). `estimate` paths are measured for size.
    case command(tool: String, arguments: [String], estimate: [String])
}

/// A cleanup rule in the catalog.
public struct CleanupTarget: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var detail: String
    public var category: TargetCategory
    public var scope: Scope
    public var risk: Risk
    public var kind: TargetKind
    /// Only items not modified for this many days.
    public var minAgeDays: Int
    /// Skip while any of these processes run (exact process names).
    public var skipWhileRunning: [String]
    /// Child names to leave alone (glob patterns) — e.g. caches that log you out when removed.
    public var excludeNames: [String]
    /// Use the Trash rather than deleting outright (user scope only).
    public var useTrash: Bool

    public init(id: String, title: String, detail: String, category: TargetCategory, scope: Scope = .user,
                risk: Risk = .safe, kind: TargetKind, minAgeDays: Int = 0, skipWhileRunning: [String] = [],
                excludeNames: [String] = [], useTrash: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.scope = scope
        self.risk = risk
        self.kind = kind
        self.minAgeDays = minAgeDays
        self.skipWhileRunning = skipWhileRunning
        self.excludeNames = excludeNames
        self.useTrash = useTrash
    }
}

/// One concrete thing found on disk.
public struct ScanItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var bytes: Int64
    public var modified: Date?
    public var isDirectory: Bool

    public init(path: String, bytes: Int64, modified: Date? = nil, isDirectory: Bool = false) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
        self.isDirectory = isDirectory
    }
}

/// A target plus what was found for it.
public struct TargetResult: Codable, Identifiable, Sendable {
    public var id: String { target.id }
    public var target: CleanupTarget
    public var items: [ScanItem]
    /// Why the target was skipped (app running, needs sudo, tool missing…), if it was.
    public var skippedReason: String?

    public var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Output of a full cleanup scan.
public struct ScanReport: Codable, Sendable {
    public var date = Date()
    public var results: [TargetResult]
    public var sudo: Bool

    public var totalBytes: Int64 { results.reduce(0) { $0 + $1.bytes } }

    public func bytes(maxRisk: Risk) -> Int64 {
        results.filter { $0.target.risk <= maxRisk && $0.skippedReason == nil }.reduce(0) { $0 + $1.bytes }
    }

    public func byCategory() -> [(TargetCategory, Int64)] {
        TargetCategory.allCases.compactMap { cat in
            let total = results.filter { $0.target.category == cat && $0.skippedReason == nil }.reduce(0) { $0 + $1.bytes }
            return total > 0 ? (cat, total) : nil
        }
    }
}
