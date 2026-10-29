import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Behaviour that changed in recent macOS releases and that Root adapts to. Each switch is keyed on
/// the running major version, so one build works from Sonoma through Golden Gate.
public enum OSFeatures {
    /// The running macOS major version. `ROOTAPP_OS_MAJOR` overrides it for tests.
    public static var major: Int {
        if let forced = ProcessInfo.processInfo.environment["ROOTAPP_OS_MAJOR"], let n = Int(forced) { return n }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// macOS 27: access to other developers' app containers and app group containers is denied by
    /// default instead of prompting. Full Disk Access still grants it.
    public static var containersProtected: Bool { major >= 27 }

    /// macOS 27: launchd no longer loads property lists that carry the quarantine attribute.
    public static var launchdRejectsQuarantined: Bool { major >= 27 }

    /// macOS 27 added `spctl` purge, which drops Gatekeeper records for apps that are no longer on disk.
    /// Returns the exact arguments the installed `spctl` advertises, or nil where it doesn't exist.
    public static var gatekeeperPurgeArguments: [String]? { purgeArguments }

    private static let purgeArguments: [String]? = {
        #if os(macOS)
        guard major >= 27 else { return nil }
        // spctl prints its usage (to stderr) when given an unknown option.
        let r = Shell.run("/usr/sbin/spctl", ["--usage"], timeout: 10)
        return parsePurgeArguments(r.stdout + r.stderr)
        #else
        return nil
        #endif
    }()

    /// Reads the purge syntax from spctl's usage text: `--purge` if offered as an option, else `purge`.
    static func parsePurgeArguments(_ usage: String) -> [String]? {
        if usage.contains("--purge") { return ["--purge"] }
        let words = usage.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "[" || $0 == "]" })
        return words.contains("purge") ? ["purge"] : nil
    }

    /// Paths inside other apps' sandboxes, which macOS 27 shields without Full Disk Access.
    public static func isInsideAppContainer(_ path: String) -> Bool {
        path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/")
            || path.hasSuffix("/Library/Containers") || path.hasSuffix("/Library/Group Containers")
    }
}

/// The `com.apple.quarantine` extended attribute that downloads carry.
public enum Quarantine {
    static let attribute = "com.apple.quarantine"

    public static func isQuarantined(_ path: String) -> Bool {
        #if os(macOS)
        return getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        #else
        return false // a macOS attribute; nothing to find elsewhere
        #endif
    }

    /// Removes the attribute. Returns true when the file no longer carries it.
    @discardableResult
    public static func clear(_ path: String) -> Bool {
        #if os(macOS)
        _ = removexattr(path, attribute, XATTR_NOFOLLOW)
        #endif
        return !isQuarantined(path)
    }
}
