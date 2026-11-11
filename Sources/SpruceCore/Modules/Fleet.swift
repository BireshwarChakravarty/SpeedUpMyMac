import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// What each Mac publishes to the shared fleet folder (one small JSON file per Mac).
public struct FleetSnapshot: Codable, Identifiable, Sendable {
    public var id: String { machine.machineID }
    public var machine: MachineInfo
    public var updatedAt: Date
    public var appVersion: String
    public var sudoEnabled: Bool
    public var diskTotal: Int64
    public var diskAvailable: Int64
    public var reclaimableBytes: Int64?
    public var healthScore: Int?
    public var lastClean: Date?
    public var totalFreed: Int64
    public var notes: [String]

    public var isStale: Bool { Date().timeIntervalSince(updatedAt) > 7 * 86_400 }
}

/// "Works across all my Macs": no server, just a synced folder (iCloud Drive by default; any
/// Dropbox/Drive/SMB folder works — useful on a work Mac without your personal iCloud).
public enum Fleet {
    public static let version = "2.1.1"

    public static func folder(_ settings: Settings) -> String {
        let dir = (settings.resolvedFleetFolder as NSString).appendingPathComponent("machines")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes this Mac's snapshot. `reclaimable` and `health` come from the latest scans, if any.
    @discardableResult
    public static func publish(settings: Settings, reclaimable: Int64?, health: HealthReport?) throws -> FleetSnapshot {
        let machine = health?.machine ?? MachineInfo.current()
        let disk = health?.disk ?? Health.diskStatus()
        let previous = load(settings: settings).first { $0.machine.machineID == machine.machineID }
        let snapshot = FleetSnapshot(machine: machine, updatedAt: Date(), appVersion: version,
                                     sudoEnabled: settings.sudoEnabled(machine: machine), diskTotal: disk.totalBytes,
                                     diskAvailable: disk.availableBytes,
                                     reclaimableBytes: reclaimable ?? previous?.reclaimableBytes,
                                     healthScore: health?.score ?? previous?.healthScore,
                                     lastClean: History.lastClean, totalFreed: History.totalFreed,
                                     notes: health?.notes ?? previous?.notes ?? [])
        let url = URL(fileURLWithPath: folder(settings)).appendingPathComponent("\(machine.machineID).json")
        try JSONEncoder.stable.encode(snapshot).write(to: url, options: .atomic)
        // Cards this same Mac left behind under an older ID (a reinstall, or an earlier version).
        for old in superseded(by: machine, in: load(settings: settings)) { forget(old.machine.machineID, settings: settings) }
        return snapshot
    }

    /// Older snapshots of the Mac and account described by `machine`: the same hardware fingerprint
    /// under another ID, or, for snapshots from versions that didn't record one, the same name,
    /// model, chip and account.
    public static func superseded(by machine: MachineInfo, in snapshots: [FleetSnapshot]) -> [FleetSnapshot] {
        snapshots.filter { other in
            guard other.machine.machineID != machine.machineID else { return false }
            if let mine = machine.hardwareID, let theirs = other.machine.hardwareID { return mine == theirs }
            return other.machine.hardwareID == nil && machine.hardwareID != nil
                && other.machine.name == machine.name && other.machine.model == machine.model
                && other.machine.chip == machine.chip && other.machine.userName == machine.userName
        }
    }

    public static func load(settings: Settings) -> [FleetSnapshot] {
        let dir = folder(settings)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
        return files.compactMap { name in
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder.stable.decode(FleetSnapshot.self, from: data)
        }.sorted { $0.machine.name.localizedCaseInsensitiveCompare($1.machine.name) == .orderedAscending }
    }

    /// Removes a Mac from the fleet. It comes back the next time that Mac runs Spruce, so this is
    /// for Macs you no longer own and old duplicates.
    public static func forget(_ machineID: String, settings: Settings) {
        let url = URL(fileURLWithPath: folder(settings)).appendingPathComponent("\(machineID).json")
        try? FileManager.default.removeItem(at: url)
    }
}

/// Scheduled cleaning via a per-user LaunchAgent — no admin needed, so it works on the M3 too.
public enum Scheduler {
    public static let label = "io.spruceapp.autoclean"
    public static var plistPath: String { Paths.expand("~/Library/LaunchAgents/\(label).plist") }

    public static func install(_ schedule: Schedule, cliPath: String) throws {
        uninstall()
        guard schedule != .off else { return }
        var interval: [String: Int] = ["Hour": 11, "Minute": 17]
        if schedule == .weekly { interval["Weekday"] = 0 }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [cliPath, "autoclean"],
            "StartCalendarInterval": interval,
            "LowPriorityIO": true,
            "ProcessType": "Background",
            "Nice": 10,
            "StandardOutPath": Paths.expand("~/Library/Logs/Spruce/autoclean.log"),
            "StandardErrorPath": Paths.expand("~/Library/Logs/Spruce/autoclean.log"),
        ]
        try FileManager.default.createDirectory(atPath: Paths.expand("~/Library/Logs/Spruce"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: Paths.expand("~/Library/LaunchAgents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        // macOS 27's launchd won't load a quarantined plist; files written by a downloaded app can inherit it.
        Quarantine.clear(plistPath)
        Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
    }

    public static func uninstall() {
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    /// Replaces a schedule set up under one of the app's old names with the same schedule under this one.
    public static func migrateLegacy(_ schedule: Schedule, cliPath: String) {
        var found = false
        for label in Legacy.agentLabels {
            let old = Paths.expand("~/Library/LaunchAgents/\(label).plist")
            guard FileManager.default.fileExists(atPath: old) else { continue }
            Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            try? FileManager.default.removeItem(atPath: old)
            found = true
        }
        if found && schedule != .off { try? install(schedule, cliPath: cliPath) }
    }
}

/// The app was called Burnish, then Root, before it was Spruce. Its folders move over once, the
/// first time they're needed, so settings, history, tweak backups and the fleet survive the renames.
public enum Legacy {
    /// Newest first: if both exist, the more recent app's data wins.
    static let names = ["Root", "Burnish"]
    static let agentLabels = ["io.rootapp.autoclean", "io.burnish.autoclean"]
    static let defaultsDomains = ["io.rootapp.Root"]

    static let movedFolders: Void = {
        for name in names {
            move("~/Library/Application Support/\(name)", to: "~/Library/Application Support/Spruce")
            move("~/Library/Logs/\(name)", to: "~/Library/Logs/Spruce")
        }
    }()

    static let movedFleetFolder: Void = {
        guard let icloud = Paths.iCloudDrive else { return }
        for name in names {
            move((icloud as NSString).appendingPathComponent(name), to: (icloud as NSString).appendingPathComponent("Spruce"))
        }
    }()

    /// The app's own preferences (sound, appearance) under the old bundle identifier.
    public static func migrateDefaults(into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "migratedLegacyDefaults") else { return }
        for domain in defaultsDomains {
            for (key, value) in defaults.persistentDomain(forName: domain) ?? [:] where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "migratedLegacyDefaults")
    }

    static func move(_ from: String, to: String) {
        let old = Paths.expand(from), new = Paths.expand(to)
        let fm = FileManager.default
        guard fm.fileExists(atPath: old), !fm.fileExists(atPath: new) else { return }
        try? fm.createDirectory(atPath: (new as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? fm.moveItem(atPath: old, toPath: new)
    }
}
