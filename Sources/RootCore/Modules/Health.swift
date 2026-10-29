import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct DiskStatus: Codable, Sendable {
    public var totalBytes: Int64
    public var freeBytes: Int64
    /// Free + purgeable (what Finder calls "available").
    public var availableBytes: Int64
    public var smartStatus: String?
    public var localSnapshots: Int

    public var purgeableBytes: Int64 { max(availableBytes - freeBytes, 0) }
    public var usedFraction: Double { totalBytes > 0 ? 1 - Double(availableBytes) / Double(totalBytes) : 0 }
}

public struct MemoryStatus: Codable, Sendable {
    public var totalBytes: Int64
    /// kern.memorystatus_level: percentage of memory the kernel considers free (0–100).
    public var freePercent: Int?
    public var swapUsedBytes: Int64
    public var pressure: String {
        guard let free = freePercent else { return "Unknown" }
        return free >= 40 ? "Normal" : free >= 20 ? "Elevated" : "Critical"
    }
}

public struct BatteryStatus: Codable, Sendable {
    public var cycleCount: Int
    public var healthPercent: Int?
    public var designCapacity: Int?
    public var maxCapacity: Int?
    public var charging: Bool
    public var condition: String?
}

public struct SecurityPosture: Codable, Sendable {
    public var sip: Bool?
    public var gatekeeper: Bool?
    public var fileVault: Bool?
    public var firewall: Bool?
    public var xprotectVersion: String?
    public var fullDiskAccess: Bool

    public var issues: [String] {
        var list: [String] = []
        if sip == false { list.append("System Integrity Protection is off") }
        if gatekeeper == false { list.append("Gatekeeper is off") }
        if fileVault == false { list.append("FileVault disk encryption is off") }
        if firewall == false { list.append("Firewall is off") }
        return list
    }
}

/// A snapshot of how this Mac is doing (Sensei / Stats / Mole status).
public struct HealthReport: Codable, Sendable {
    public var date = Date()
    public var machine: MachineInfo
    public var disk: DiskStatus
    public var memory: MemoryStatus
    public var battery: BatteryStatus?
    public var security: SecurityPosture
    public var load: [Double]
    public var uptimeSeconds: Double
    public var thermal: String
    public var score: Int
    public var notes: [String]
}

public enum Health {
    public static func report(includeSecurity: Bool = true) -> HealthReport {
        let machine = MachineInfo.current()
        let disk = diskStatus()
        let memory = memoryStatus()
        let battery = batteryStatus()
        let security = includeSecurity ? securityPosture() : SecurityPosture(fullDiskAccess: hasFullDiskAccess())
        var load = [Double](repeating: 0, count: 3)
        _ = getloadavg(&load, 3)
        let thermal = thermalState()
        let (score, notes) = computeScore(disk: disk, memory: memory, battery: battery, security: security, thermal: thermal,
                                          cores: ProcessInfo.processInfo.activeProcessorCount, load: load.first ?? 0)
        return HealthReport(machine: machine, disk: disk, memory: memory, battery: battery, security: security, load: load,
                            uptimeSeconds: ProcessInfo.processInfo.systemUptime, thermal: thermal, score: score, notes: notes)
    }

    /// 0–100. Weighted towards things that actually slow a Mac down: low disk space, memory pressure, heat.
    static func computeScore(disk: DiskStatus, memory: MemoryStatus, battery: BatteryStatus?, security: SecurityPosture,
                             thermal: String, cores: Int, load: Double) -> (Int, [String]) {
        var score = 100.0
        var notes: [String] = []
        let freeFraction = disk.totalBytes > 0 ? Double(disk.availableBytes) / Double(disk.totalBytes) : 1
        if freeFraction < 0.05 { score -= 35; notes.append("Startup disk is almost full — macOS needs room for swap and updates") }
        else if freeFraction < 0.10 { score -= 22; notes.append("Less than 10% disk space free") }
        else if freeFraction < 0.20 { score -= 8; notes.append("Disk space is getting low") }
        if let free = memory.freePercent {
            if free < 20 { score -= 20; notes.append("Memory pressure is high — quit memory-hungry apps") }
            else if free < 40 { score -= 8; notes.append("Memory pressure is elevated") }
        }
        if memory.swapUsedBytes > 4_000_000_000 { score -= 7; notes.append("Using \(Format.bytes(memory.swapUsedBytes)) of swap") }
        if thermal == "Serious" || thermal == "Critical" { score -= 15; notes.append("Mac is running hot and may be throttling") }
        if cores > 0 && load > Double(cores) * 1.5 { score -= 8; notes.append("CPU is heavily loaded") }
        if let health = battery?.healthPercent, health < 80 { score -= 5; notes.append("Battery health is \(health)%") }
        if !security.issues.isEmpty { score -= Double(5 * security.issues.count); notes.append(contentsOf: security.issues) }
        if !security.fullDiskAccess { notes.append("Grant Full Disk Access for a complete scan") }
        return (max(0, min(100, Int(score.rounded()))), notes)
    }

    public static func diskStatus(volume: String = "/") -> DiskStatus {
        let url = URL(fileURLWithPath: volume)
        var total: Int64 = 0, free: Int64 = 0, available: Int64 = 0
        #if os(macOS)
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                    .volumeAvailableCapacityForImportantUsageKey]) {
            total = Int64(v.volumeTotalCapacity ?? 0)
            free = Int64(v.volumeAvailableCapacity ?? 0)
            available = v.volumeAvailableCapacityForImportantUsage ?? free
        }
        #else
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: volume) {
            total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            available = free
        }
        #endif
        return DiskStatus(totalBytes: total, freeBytes: free, availableBytes: max(available, free),
                          smartStatus: smartStatus(), localSnapshots: localSnapshotCount())
    }

    static func smartStatus() -> String? {
        #if os(macOS)
        let r = Shell.run("/usr/sbin/diskutil", ["info", "-plist", "disk0"], timeout: 10)
        guard r.succeeded, let data = r.stdout.data(using: .utf8),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return plist["SMARTStatus"] as? String
        #else
        return nil
        #endif
    }

    static func localSnapshotCount() -> Int {
        #if os(macOS)
        return Maintenance.localSnapshots().count
        #else
        return 0
        #endif
    }

    public static func memoryStatus() -> MemoryStatus {
        var swapUsed: Int64 = 0
        #if os(macOS)
        let swap = Shell.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"]).stdout
        // "total = 2048.00M  used = 1024.50M  free = 1023.50M  (encrypted)"
        if let range = swap.range(of: "used = ") {
            let rest = swap[range.upperBound...]
            let token = rest.prefix { $0 != " " }
            swapUsed = parseSize(String(token))
        }
        #endif
        let level = MachineInfo.sysctlInt("kern.memorystatus_level").map { Int($0) }
        return MemoryStatus(totalBytes: Int64(ProcessInfo.processInfo.physicalMemory), freePercent: level, swapUsedBytes: swapUsed)
    }

    /// "1024.50M" → bytes.
    static func parseSize(_ s: String) -> Int64 {
        guard let unit = s.last, let value = Double(s.dropLast()) else { return 0 }
        let table: [Character: Double] = ["K": 1024, "M": 1_048_576, "G": 1_073_741_824]
        let mult = table[Character(unit.uppercased())] ?? 1
        return Int64(value * mult)
    }

    public static func batteryStatus() -> BatteryStatus? {
        #if os(macOS)
        let r = Shell.run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-a"], timeout: 10)
        guard r.succeeded, let data = r.stdout.data(using: .utf8),
              let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]],
              let b = list.first else { return nil }
        let design = b["DesignCapacity"] as? Int
        let rawMax = (b["AppleRawMaxCapacity"] as? Int) ?? (b["NominalChargeCapacity"] as? Int)
        var health: Int?
        if let design, design > 0, let rawMax { health = min(100, Int((Double(rawMax) / Double(design) * 100).rounded())) }
        let condition = Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType"], timeout: 20).stdout
            .split(separator: "\n").first { $0.contains("Condition:") }
            .map { $0.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }
        return BatteryStatus(cycleCount: (b["CycleCount"] as? Int) ?? 0, healthPercent: health, designCapacity: design,
                             maxCapacity: rawMax, charging: (b["IsCharging"] as? Bool) ?? false, condition: condition)
        #else
        return nil
        #endif
    }

    public static func securityPosture() -> SecurityPosture {
        #if os(macOS)
        let sip = Shell.run("/usr/bin/csrutil", ["status"]).stdout
        let gk = Shell.run("/usr/sbin/spctl", ["--status"])
        let fv = Shell.run("/usr/bin/fdesetup", ["status"]).stdout
        let fw = Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]).stdout
        let xp = Uninstaller.readPlist("/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist")
        return SecurityPosture(
            sip: sip.isEmpty ? nil : sip.contains("enabled"),
            gatekeeper: (gk.stdout + gk.stderr).isEmpty ? nil : (gk.stdout + gk.stderr).contains("enabled"),
            fileVault: fv.isEmpty ? nil : fv.contains("On"),
            firewall: fw.isEmpty ? nil : (fw.contains("enabled") || fw.contains("State = 1") || fw.contains("State = 2")),
            xprotectVersion: xp?["CFBundleShortVersionString"] as? String,
            fullDiskAccess: hasFullDiskAccess())
        #else
        return SecurityPosture(fullDiskAccess: hasFullDiskAccess())
        #endif
    }

    /// Full Disk Access probe: TCC-protected folders are only listable with FDA. Any one readable
    /// folder proves it. Several are tried because macOS 27's XProtect may also shield app data that
    /// malware targets (browser profiles, for one), and Root never opens the TCC database itself
    /// (macOS 27 forbids apps from reading it directly).
    public static func hasFullDiskAccess() -> Bool {
        #if os(macOS)
        for probe in ["/Library/Application Support/com.apple.TCC", "~/Library/Mail", "~/Library/Messages",
                      "~/Library/Safari", "~/Library/Containers/com.apple.stocks"] {
            let path = Paths.expand(probe)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil { return true }
        }
        return false
        #else
        return true
        #endif
    }

    static func thermalState() -> String {
        #if os(macOS)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
        #else
        return "Nominal"
        #endif
    }
}
