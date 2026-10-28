import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Path helpers: home expansion, globbing, and Burnish's own storage locations.
public enum Paths {
    /// The real home directory. Overridable for tests via `BURNISH_HOME`.
    public static var home: String {
        if let override = ProcessInfo.processInfo.environment["BURNISH_HOME"], !override.isEmpty { return override }
        return NSHomeDirectory()
    }

    /// Expands a leading `~` to the home directory.
    public static func expand(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    /// Replaces the home prefix with `~` for display.
    public static func abbreviate(_ path: String) -> String {
        let h = home
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }

    /// Burnish's support directory: ~/Library/Application Support/Burnish (created on demand).
    public static var support: String {
        let dir = expand("~/Library/Application Support/Burnish")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// iCloud Drive root, if this account has iCloud Drive enabled.
    public static var iCloudDrive: String? {
        let path = expand("~/Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Expands glob patterns component-by-component (`*`, `?`, `[...]`). Hidden entries only match
    /// patterns that start with a dot. Returns existing paths only, sorted.
    public static func glob(_ pattern: String) -> [String] {
        let expanded = expand(pattern)
        guard expanded.contains(where: { "*?[".contains($0) }) else {
            return lexists(expanded) ? [expanded] : []
        }
        let components = expanded.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var results = [expanded.hasPrefix("/") ? "/" : FileManager.default.currentDirectoryPath]
        for component in components {
            var next: [String] = []
            let isPattern = component.contains(where: { "*?[".contains($0) })
            for base in results {
                if isPattern {
                    guard let children = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
                    for child in children where matches(child, component) {
                        next.append((base as NSString).appendingPathComponent(child))
                    }
                } else {
                    let candidate = (base as NSString).appendingPathComponent(component)
                    if lexists(candidate) { next.append(candidate) }
                }
            }
            results = next
            if results.isEmpty { break }
        }
        return results.sorted()
    }

    /// fnmatch-style match of a single path component.
    public static func matches(_ name: String, _ pattern: String) -> Bool {
        if name.hasPrefix(".") && !pattern.hasPrefix(".") { return false }
        return fnmatch(pattern, name, 0) == 0
    }

    /// `true` if something exists at `path`, without following a final symlink.
    public static func lexists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    public static func isSymlink(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    public static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue && !isSymlink(path)
    }

    /// Standardizes and removes trailing slashes so prefix comparisons are reliable.
    /// Purely lexical (never touches the filesystem, never resolves symlinks — Safety needs to
    /// reason about a link and its target separately).
    public static func normalize(_ path: String) -> String {
        let expanded = expand(path)
        var parts: [Substring] = []
        for component in expanded.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(component)
        }
        let joined = parts.joined(separator: "/")
        return expanded.hasPrefix("/") ? "/" + joined : (joined.isEmpty ? "." : joined)
    }

    /// `true` if `path` equals `ancestor` or lies inside it.
    public static func isInside(_ path: String, _ ancestor: String) -> Bool {
        let p = normalize(path), a = normalize(ancestor)
        return p == a || p.hasPrefix(a == "/" ? "/" : a + "/")
    }
}
