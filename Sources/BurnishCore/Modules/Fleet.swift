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
        try JSONEncoder.burnish.encode(snapshot).write(to: url, options: .atomic)
        return snapshot
    }

    public static func load(settings: Settings) -> [FleetSnapshot] {
        let dir = folder(settings)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
        return files.compactMap { name in
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder.burnish.decode(FleetSnapshot.self, from: data)
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
    public static let label = "io.burnish.autoclean"
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
            "StandardOutPath": Paths.expand("~/Library/Logs/Burnish/autoclean.log"),
            "StandardErrorPath": Paths.expand("~/Library/Logs/Burnish/autoclean.log"),
        ]
        try FileManager.default.createDirectory(atPath: Paths.expand("~/Library/Logs/Burnish"), withIntermediateDirectories: true)
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
}
