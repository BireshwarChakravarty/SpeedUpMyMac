import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Static facts about this Mac and the current account.
public struct MachineInfo: Codable, Sendable, Equatable {
    public var machineID: String
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

    /// A random ID generated once per Mac and account, used to key fleet snapshots.
    static func stableMachineID() -> String {
        let file = (Paths.support as NSString).appendingPathComponent("machine-id")
        if let existing = try? String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        try? id.write(toFile: file, atomically: true, encoding: .utf8)
        return id
    }
}
