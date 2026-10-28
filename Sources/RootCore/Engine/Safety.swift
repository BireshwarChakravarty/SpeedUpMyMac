import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SafetyError: Error, LocalizedError, Equatable {
    case notAbsolute(String)
    case protected(String)
    case ignored(String)
    case escapesViaSymlink(String)

    public var errorDescription: String? {
        switch self {
        case .notAbsolute(let p): return "Refusing relative path: \(p)"
        case .protected(let p): return "Protected location, never removed: \(p)"
        case .ignored(let p): return "On your ignore list: \(p)"
        case .escapesViaSymlink(let p): return "Path resolves somewhere unexpected via a symlink: \(p)"
        }
    }
}

/// The last line of defence: every deletion, user or root, goes through `validateForDeletion`.
public enum Safety {
    /// Paths that may never be removed themselves (their contents may be, if a target says so).
    static let protectedExact: [String] = [
        "/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/bin", "/cores", "/dev", "/etc",
        "/opt", "/private", "/private/etc", "/private/tmp", "/private/var", "/private/var/folders", "/private/var/log",
        "/sbin", "/tmp", "/usr", "/usr/local", "/var",
        "/Library/Caches", "/Library/Logs", "/Library/Application Support", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/Preferences", "/Users/Shared",
        "~", "~/Applications", "~/Desktop", "~/Developer", "~/Documents", "~/Downloads", "~/Library", "~/Movies",
        "~/Music", "~/Pictures", "~/Public", "~/.Trash", "~/.cache", "~/.config", "~/.local",
        "~/Library/Application Support", "~/Library/Caches", "~/Library/Containers", "~/Library/Group Containers",
        "~/Library/LaunchAgents", "~/Library/Logs", "~/Library/Preferences", "~/Library/Saved Application State",
        "~/Library/Developer", "~/Library/Developer/Xcode",
    ]

    /// Trees that are never touched at all, at any depth.
    static let protectedTrees: [String] = [
        "/System", "/bin", "/sbin", "/usr/bin", "/usr/lib", "/usr/libexec", "/usr/sbin", "/usr/share",
        "/private/etc", "/private/var/db", "/private/var/root", "/Library/Apple", "/Library/Keychains",
        "~/.ssh", "~/.gnupg", "~/Library/Keychains", "~/Library/Mobile Documents", "~/Library/CloudStorage",
        "~/Library/Accounts", "~/Library/Mail", "~/Library/Messages", "~/Library/Photos",
        "~/Library/Application Support/com.apple.TCC", "~/Library/Application Support/AddressBook",
        "~/Library/Calendars", "~/Library/Safari", "~/Library/Cookies", "~/Library/IdentityServices",
        "~/Library/Application Support/MobileSync", "~/Library/Application Support/1Password",
        "~/Library/Group Containers/group.com.apple.notes", "~/Pictures/Photos Library.photoslibrary",
    ]

    /// Specific subtrees inside protected trees that catalog targets are allowed to clean.
    static let exceptions: [String] = [
        "~/Library/Mail Downloads",
        "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        "~/Library/Messages/StickerCache",
        "~/Library/Application Support/MobileSync/Backup",
    ]

    /// Extra paths the user asked Root to never touch.
    public static var userIgnored: [String] = []

    public static func validateForDeletion(_ rawPath: String) throws {
        guard rawPath.hasPrefix("/") else { throw SafetyError.notAbsolute(rawPath) }
        let path = Paths.normalize(rawPath)
        try check(path, original: rawPath)

        // Resolve the parent directory for real (without following the final component, which may
        // itself be a symlink we intend to remove) and re-check the resolved location.
        let parent = (path as NSString).deletingLastPathComponent
        if let resolvedParent = realPath(parent) {
            let resolved = (resolvedParent as NSString).appendingPathComponent((path as NSString).lastPathComponent)
            if Paths.normalize(resolved) != path {
                do { try check(Paths.normalize(resolved), original: rawPath) } catch {
                    throw SafetyError.escapesViaSymlink(rawPath)
                }
            }
        }
    }

    public static func isAllowed(_ path: String) -> Bool {
        (try? validateForDeletion(path)) != nil
    }

    private static func check(_ path: String, original: String) throws {
        let lists = resolvedLists()
        if lists.exact.contains(path) { throw SafetyError.protected(original) }
        // Home itself and /Users/<anyone> are always protected.
        if (path as NSString).deletingLastPathComponent == "/Users" { throw SafetyError.protected(original) }
        let excepted = lists.exceptions.contains { Paths.isInside(path, $0) && $0 != path }
        if !excepted {
            for tree in lists.trees where Paths.isInside(path, tree) { throw SafetyError.protected(original) }
        }
        for ignored in userIgnored where Paths.isInside(path, ignored) { throw SafetyError.ignored(original) }
    }

    struct Lists { var exact: Set<String>; var trees: [String]; var exceptions: [String] }
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: (home: String, lists: Lists)?

    /// Each protected path in both its literal and symlink-resolved forms (on macOS /var, /tmp and
    /// /etc live under /private), cached per home directory.
    static func resolvedLists() -> Lists {
        let home = Paths.home
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache, cache.home == home { return cache.lists }
        func variants(_ list: [String]) -> [String] {
            list.flatMap { p -> [String] in
                let n = Paths.normalize(p)
                guard let r = realPath(n).map(Paths.normalize), r != n else { return [n] }
                return [n, r]
            }
        }
        let lists = Lists(exact: Set(variants(protectedExact)), trees: variants(protectedTrees), exceptions: variants(exceptions))
        cache = (home, lists)
        return lists
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
