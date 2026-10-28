import Foundation

public enum MatchLevel: String, Codable, CaseIterable, Sendable {
    /// Exact bundle ID or app name only (AppCleaner-style).
    case strict
    /// Adds contains-matches, joined bundle components and version-stripped names (default).
    case enhanced
    /// Adds company/team-identifier matches; more hits, more false positives.
    case deep
}

public enum Schedule: String, Codable, CaseIterable, Sendable {
    case off, daily, weekly
}

/// User preferences, stored at ~/Library/Application Support/Root/settings.json.
/// Every field has a default so older/newer files decode cleanly.
public struct Settings: Codable, Equatable, Sendable {
    /// The Sudo toggle. Ignored (treated as off) on accounts that aren't administrators.
    public var adminMode = false
    /// Send everything to the Trash, even caches (slower to reclaim, maximally reversible).
    public var alwaysUseTrash = false
    public var ignorePaths: [String] = []
    public var purgeRoots: [String] = Settings.defaultPurgeRoots
    public var purgeMinAgeDays = 7
    public var largeFileMinMB = 500
    public var oldFileDays = 180
    public var leftoverLevel: MatchLevel = .enhanced
    /// Uninstall leaves nothing behind: personal data included, deleted outright rather than trashed,
    /// plus running helpers, launchd jobs, cached preferences, privacy grants, Dock tile and receipts.
    public var uninstallCompletely = true
    /// Folder that holds fleet snapshots and shared settings. nil = iCloud Drive/Root, else local.
    public var fleetFolder: String?
    public var schedule: Schedule = .off
    public var trashSentinel = true
    /// Targets the user turned off permanently (by catalog id).
    public var disabledTargets: [String] = []

    public static let defaultPurgeRoots = ["~/Developer", "~/Projects", "~/Code", "~/code", "~/dev", "~/src",
                                           "~/GitHub", "~/repos", "~/work", "~/Documents/GitHub", "~/Sites"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        adminMode = try c.decodeIfPresent(Bool.self, forKey: .adminMode) ?? d.adminMode
        alwaysUseTrash = try c.decodeIfPresent(Bool.self, forKey: .alwaysUseTrash) ?? d.alwaysUseTrash
        ignorePaths = try c.decodeIfPresent([String].self, forKey: .ignorePaths) ?? d.ignorePaths
        purgeRoots = try c.decodeIfPresent([String].self, forKey: .purgeRoots) ?? d.purgeRoots
        purgeMinAgeDays = try c.decodeIfPresent(Int.self, forKey: .purgeMinAgeDays) ?? d.purgeMinAgeDays
        largeFileMinMB = try c.decodeIfPresent(Int.self, forKey: .largeFileMinMB) ?? d.largeFileMinMB
        oldFileDays = try c.decodeIfPresent(Int.self, forKey: .oldFileDays) ?? d.oldFileDays
        leftoverLevel = try c.decodeIfPresent(MatchLevel.self, forKey: .leftoverLevel) ?? d.leftoverLevel
        uninstallCompletely = try c.decodeIfPresent(Bool.self, forKey: .uninstallCompletely) ?? d.uninstallCompletely
        fleetFolder = try c.decodeIfPresent(String.self, forKey: .fleetFolder)
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? d.schedule
        trashSentinel = try c.decodeIfPresent(Bool.self, forKey: .trashSentinel) ?? d.trashSentinel
        disabledTargets = try c.decodeIfPresent([String].self, forKey: .disabledTargets) ?? d.disabledTargets
    }

    public static var fileURL: URL { URL(fileURLWithPath: Paths.support).appendingPathComponent("settings.json") }

    /// Loads local settings and merges the fleet-wide shared settings (ignore list, purge roots).
    public static func load() -> Settings {
        var settings = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder.stable.decode(Settings.self, from: $0) }
            ?? Settings()
        if let shared = SharedSettings.load(from: settings.resolvedFleetFolder) {
            settings.ignorePaths = Array(Set(settings.ignorePaths + shared.ignorePaths)).sorted()
            settings.purgeRoots = Array(Set(settings.purgeRoots + shared.purgeRoots)).sorted()
        }
        Safety.userIgnored = settings.ignorePaths.map(Paths.expand)
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder.stable.encode(self) else { return }
        try? data.write(to: Settings.fileURL, options: .atomic)
        Safety.userIgnored = ignorePaths.map(Paths.expand)
    }

    /// Sudo is only effective when the toggle is on *and* the account can actually authorize.
    public func sudoEnabled(machine: MachineInfo) -> Bool { adminMode && machine.isAdmin }

    public var resolvedFleetFolder: String {
        _ = Legacy.movedFleetFolder
        if let fleetFolder, !fleetFolder.isEmpty { return Paths.expand(fleetFolder) }
        if let icloud = Paths.iCloudDrive { return (icloud as NSString).appendingPathComponent("Root") }
        return (Paths.support as NSString).appendingPathComponent("Fleet")
    }
}

/// Settings shared by every Mac in the fleet folder (`shared-settings.json`).
public struct SharedSettings: Codable, Sendable {
    public var ignorePaths: [String] = []
    public var purgeRoots: [String] = []

    public init(ignorePaths: [String] = [], purgeRoots: [String] = []) {
        self.ignorePaths = ignorePaths
        self.purgeRoots = purgeRoots
    }

    public static func load(from folder: String) -> SharedSettings? {
        let url = URL(fileURLWithPath: folder).appendingPathComponent("shared-settings.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.stable.decode(SharedSettings.self, from: data)
    }

    public func save(to folder: String) throws {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: folder).appendingPathComponent("shared-settings.json")
        try JSONEncoder.stable.encode(self).write(to: url, options: .atomic)
    }
}
