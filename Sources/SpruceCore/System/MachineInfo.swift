import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Static facts about this Mac and the current account.
public struct MachineInfo: Codable, Sendable, Equatable {
    public var machineID: String
    /// A fingerprint of this Mac's hardware and account (not the hardware UUID itself). The same
    /// Mac and account always get the same one, even after a reinstall. nil in snapshots written
    /// by older versions.
    public var hardwareID: String? = nil
    public var name: String
    public var model: String
    public var chip: String
    public var osVersion: String
    public var osMajor: Int
    public var memoryBytes: Int64
    public var userName: String
    public var isAdmin: Bool

    public static func current() -> MachineInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return MachineInfo(
            machineID: stableMachineID(),
            hardwareID: hardwareFingerprint(),
            name: computerName(),
            model: sysctlString("hw.model") ?? "Mac",
            chip: chipName(),
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            osMajor: os.majorVersion,
            memoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            userName: NSUserName(),
            isAdmin: Privilege.currentUserIsAdmin()
        )
    }

    /// "Apple M4 Pro" → "M4 Pro". Falls back to the raw brand string (Intel or Linux).
    public static func chipName() -> String {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Unknown"
        return brand.hasPrefix("Apple ") ? String(brand.dropFirst(6)) : brand
    }

    public static func computerName() -> String {
        #if os(macOS)
        if let r = Shell.runTool("scutil", ["--get", "ComputerName"]), r.succeeded {
            let name = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        #endif
        return ProcessInfo.processInfo.hostName
    }

    public static func sysctlString(_ name: String) -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
        #else
        return nil
        #endif
    }

    public static func sysctlInt(_ name: String) -> Int64? {
        #if canImport(Darwin)
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size { return Int64(Int32(truncatingIfNeeded: value)) }
        return value
        #else
        return nil
        #endif
    }

    /// The ID that keys this Mac's fleet snapshot: the hardware fingerprint where there is one,
    /// so a reinstall (or a lost support folder) keeps the same card. Otherwise a random ID saved
    /// once in the support folder.
    static func stableMachineID() -> String {
        if let hardware = hardwareFingerprint() { return hardware }
        let file = (Paths.support as NSString).appendingPathComponent("machine-id")
        if let existing = try? String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        try? id.write(toFile: file, atomically: true, encoding: .utf8)
        return id
    }

    /// "hw-" and a 64-bit FNV-1a hash of the platform UUID and the account name. Two accounts on one
    /// Mac stay separate; the UUID itself never leaves the Mac.
    public static func hardwareFingerprint() -> String? {
        if let override = ProcessInfo.processInfo.environment["SPRUCE_HARDWARE_UUID"] {
            return override.isEmpty ? nil : fingerprint(platformUUID: override, user: NSUserName())
        }
        guard let uuid = platformUUID() else { return nil }
        return fingerprint(platformUUID: uuid, user: NSUserName())
    }

    static func fingerprint(platformUUID: String, user: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (platformUUID.uppercased() + "\u{0}" + user).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "hw-" + String(format: "%016llx", hash)
    }

    private static let cachedPlatformUUID: String? = {
        #if os(macOS)
        let r = Shell.run("/usr/sbin/ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"], timeout: 10)
        guard r.succeeded else { return nil }
        for line in r.stdout.split(separator: "\n") where line.contains("\"IOPlatformUUID\"") {
            let parts = line.split(separator: "\"")
            if parts.count >= 4 { return String(parts[3]) }
        }
        return nil
        #else
        let id = (try? String(contentsOfFile: "/etc/machine-id", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (id?.isEmpty ?? true) ? nil : id
        #endif
    }()

    static func platformUUID() -> String? { cachedPlatformUUID }
}
