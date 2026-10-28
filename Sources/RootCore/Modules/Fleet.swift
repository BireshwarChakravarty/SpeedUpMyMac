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
    public static let version = "1.0.0"

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
        return snapshot
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

    /// Removes a Mac you no longer own from the fleet.
    public static func forget(_ machineID: String, settings: Settings) {
        let url = URL(fileURLWithPath: folder(settings)).appendingPathComponent("\(machineID).json")
        try? FileManager.default.removeItem(at: url)
    }
}

/// Scheduled cleaning via a per-user LaunchAgent — no admin needed, so it works on the M3 too.
public enum Scheduler {
    public static let label = "io.rootapp.autoclean"
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
            "StandardOutPath": Paths.expand("~/Library/Logs/Root/autoclean.log"),
            "StandardErrorPath": Paths.expand("~/Library/Logs/Root/autoclean.log"),
        ]
        try FileManager.default.createDirectory(atPath: Paths.expand("~/Library/Logs/Root"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: Paths.expand("~/Library/LaunchAgents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
    }

    public static func uninstall() {
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    /// Replaces a schedule set up under the app's old name with the same schedule under this one.
    public static func migrateLegacy(_ schedule: Schedule, cliPath: String) {
        let old = Paths.expand("~/Library/LaunchAgents/\(Legacy.agentLabel).plist")
        guard FileManager.default.fileExists(atPath: old) else { return }
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Legacy.agentLabel)"])
        try? FileManager.default.removeItem(atPath: old)
        if schedule != .off { try? install(schedule, cliPath: cliPath) }
    }
}

/// The app was called Burnish before it was Root. Its folders move over once, the first time
/// they're needed, so settings, history, tweak backups and the fleet survive the rename.
enum Legacy {
    static let name = "Burnish"
    static let agentLabel = "io.burnish.autoclean"

    static let movedFolders: Void = {
        move("~/Library/Application Support/\(name)", to: "~/Library/Application Support/Root")
        move("~/Library/Logs/\(name)", to: "~/Library/Logs/Root")
    }()

    static let movedFleetFolder: Void = {
        guard let icloud = Paths.iCloudDrive else { return }
        move((icloud as NSString).appendingPathComponent(name), to: (icloud as NSString).appendingPathComponent("Root"))
    }()

    static func move(_ from: String, to: String) {
        let old = Paths.expand(from), new = Paths.expand(to)
        let fm = FileManager.default
        guard fm.fileExists(atPath: old), !fm.fileExists(atPath: new) else { return }
        try? fm.createDirectory(atPath: (new as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? fm.moveItem(atPath: old, toPath: new)
    }
}
