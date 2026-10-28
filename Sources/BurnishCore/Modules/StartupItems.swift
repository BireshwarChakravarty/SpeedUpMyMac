import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SigningStatus: String, Codable, Sendable {
    case apple = "Apple"
    case developerID = "Developer ID"
    case appStore = "App Store"
    case adHoc = "Ad-hoc"
    case unsigned = "Unsigned"
    case missing = "Missing binary"
    case unknown = "Unknown"

    /// Worth a closer look (KnockKnock-style flag).
    public var suspicious: Bool { self == .unsigned || self == .adHoc || self == .missing }
}

/// A launchd job found on disk (KnockKnock / LaunchControl style audit).
public struct StartupItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { plistPath }
    public var label: String
    public var plistPath: String
    public var program: String?
    public var domain: Domain
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var disabled: Bool
    public var signing: SigningStatus
    public var signer: String?

    public enum Domain: String, Codable, Sendable {
        case userAgent = "User Agent"
        case globalAgent = "Global Agent"
        case daemon = "System Daemon"

        /// Agents (even global ones in /Library/LaunchAgents) run in your GUI session, so you can
        /// disable them for yourself without admin rights. Daemons run as root.
        public var needsAdmin: Bool { self == .daemon }
    }
}

public enum StartupItems {
    static let locations: [(String, StartupItem.Domain)] = [
        ("~/Library/LaunchAgents", .userAgent),
        ("/Library/LaunchAgents", .globalAgent),
        ("/Library/LaunchDaemons", .daemon),
    ]

    public static func scan(checkSignatures: Bool = true) -> [StartupItem] {
        let disabledUser = disabledLabels(domain: "gui/\(getuid())")
        let disabledSystem = disabledLabels(domain: "system")
        var items: [StartupItem] = []
        for (dir, domain) in locations {
            let path = Paths.expand(dir)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] where name.hasSuffix(".plist") {
                let plistPath = (path as NSString).appendingPathComponent(name)
                guard let plist = Uninstaller.readPlist(plistPath) else { continue }
                let label = (plist["Label"] as? String) ?? (name as NSString).deletingPathExtension
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                let keepAlive: Bool = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
                let disabledHere = domain != .daemon ? disabledUser.contains(label) : disabledSystem.contains(label)
                items.append(StartupItem(label: label, plistPath: plistPath, program: program, domain: domain,
                                         runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false, keepAlive: keepAlive,
                                         disabled: disabledHere || ((plist["Disabled"] as? Bool) ?? false),
                                         signing: .unknown, signer: nil))
            }
        }
        if checkSignatures {
            items.withUnsafeMutableBufferPointer { buffer in
                let base = buffer.baseAddress!
                DispatchQueue.concurrentPerform(iterations: buffer.count) { i in
                    let (status, signer) = signature(of: base[i].program)
                    base[i].signing = status
                    base[i].signer = signer
                }
            }
        }
        return items.sorted { ($0.signing.suspicious ? 0 : 1, $0.label) < ($1.signing.suspicious ? 0 : 1, $1.label) }
    }

    /// Reads `launchctl print-disabled` for a domain.
    static func disabledLabels(domain: String) -> Set<String> {
        #if os(macOS)
        let r = Shell.run("/bin/launchctl", ["print-disabled", domain], timeout: 10)
        var labels = Set<String>()
        for line in r.stdout.split(separator: "\n") where line.contains("=> disabled") || line.contains("=> true") {
            if let first = line.split(separator: "\"").dropFirst().first { labels.insert(String(first)) }
        }
        return labels
        #else
        return []
        #endif
    }

    /// Code-signing status via `codesign -dv`.
    public static func signature(of program: String?) -> (SigningStatus, String?) {
        guard let program, !program.isEmpty else { return (.unknown, nil) }
        let path = Paths.expand(program)
        guard FileManager.default.fileExists(atPath: path) else {
            // Bare command names (e.g. "sh") resolve via PATH; only absolute paths can be "missing".
            return path.hasPrefix("/") ? (.missing, nil) : (.unknown, nil)
        }
        #if os(macOS)
        let r = Shell.run("/usr/bin/codesign", ["-dv", "--verbose=2", path], timeout: 15)
        let text = r.stderr + r.stdout
        if text.contains("not signed at all") { return (.unsigned, nil) }
        if text.contains("Signature=adhoc") { return (.adHoc, nil) }
        let authorities = text.split(separator: "\n").filter { $0.hasPrefix("Authority=") }
            .map { String($0.dropFirst("Authority=".count)) }
        guard let leaf = authorities.first else { return (.unknown, nil) }
        if leaf.hasPrefix("Software Signing") || authorities.contains("Apple Root CA") && leaf.contains("Apple") {
            return (.apple, "Apple")
        }
        if leaf.hasPrefix("Apple Mac OS Application Signing") { return (.appStore, leaf) }
        if leaf.hasPrefix("Developer ID Application") {
            let name = leaf.replacingOccurrences(of: "Developer ID Application: ", with: "")
            return (.developerID, name)
        }
        return (.unknown, leaf)
        #else
        return (.unknown, nil)
        #endif
    }

    /// Disables (or re-enables) a job. User agents need no admin; others go through the root script.
    /// `launchctl disable` persists across reboots and is fully reversible; nothing is deleted.
    public static func setEnabled(_ item: StartupItem, enabled: Bool, sudo: Bool, runner: PrivilegeRunner?) throws {
        let domain = item.domain == .daemon ? "system" : "gui/\(getuid())"
        let target = "\(domain)/\(item.label)"
        if !item.domain.needsAdmin {
            Shell.run("/bin/launchctl", [enabled ? "enable" : "disable", target])
            if enabled {
                Shell.run("/bin/launchctl", ["bootstrap", domain, item.plistPath])
            } else {
                Shell.run("/bin/launchctl", ["bootout", target])
            }
        } else {
            guard sudo, let runner else { throw PrivilegeError.failed("Turn on Sudo mode to change system items") }
            var script = PrivilegedScript()
            script.add("/bin/launchctl", [enabled ? "enable" : "disable", target])
            if enabled {
                script.add("/bin/launchctl", ["bootstrap", domain, item.plistPath])
            } else {
                script.add("/bin/launchctl", ["bootout", target])
            }
            let r = try runner.run(script, reason: "\(enabled ? "enable" : "disable") \(item.label)")
            if !r.succeeded { throw PrivilegeError.failed(r.stderr) }
        }
        History.append(HistoryEntry(action: "startup", detail: "\(enabled ? "Enabled" : "Disabled") \(item.label)"))
    }

    /// Full Background Task Management dump (login items + launchd + SMAppService), admin only.
    public static func backgroundTaskDump(runner: PrivilegeRunner) throws -> String {
        var script = PrivilegedScript()
        script.add("/usr/bin/sfltool", ["dumpbtm"], tolerateFailure: false)
        return try runner.run(script, reason: "list background items").stdout
    }
}
