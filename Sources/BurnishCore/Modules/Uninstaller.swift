import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// An installed application bundle.
public struct InstalledApp: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var bundleID: String
    public var version: String
    public var bytes: Int64
    public var lastUsed: Date?
    public var teamID: String?
    /// Bundle IDs of helpers, login items and extensions embedded in the app.
    public var embeddedBundleIDs: [String]
    /// The current user can delete it without admin rights.
    public var userRemovable: Bool
    public var isAppleApp: Bool
    public var isAppStore: Bool

    /// Apple apps that are safe to delete (they come from the App Store or as optional installs).
    public static let deletableAppleApps: Set<String> = [
        "com.apple.garageband10", "com.apple.iMovieApp", "com.apple.iWork.Keynote", "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers", "com.apple.logic10", "com.apple.FinalCut", "com.apple.mainstage3",
        "com.apple.Compressor", "com.apple.motionapp", "com.apple.dt.Xcode", "com.apple.configurator.ui",
    ]

    public var canUninstall: Bool { !isAppleApp || InstalledApp.deletableAppleApps.contains(bundleID) }
}

/// A file that belongs to an app outside its bundle.
public struct Leftover: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var bytes: Int64
    public var kind: String
    /// True when removal needs root (system Library locations).
    public var system: Bool
    /// Personal data (Application Support, Containers, Group Containers) — not pre-selected by default.
    public var isUserData: Bool
}

public enum Uninstaller {
    public static var appRoots: [String] {
        ["/Applications", "/Applications/Utilities", "~/Applications", "/Library/Input Methods", "~/Library/Input Methods"]
            .map(Paths.expand)
    }

    // MARK: Listing apps

    public static func installedApps(measureSizes: Bool = true) -> [InstalledApp] {
        var bundles: [String] = []
        for root in appRoots {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in children where name.hasSuffix(".app") {
                bundles.append((root as NSString).appendingPathComponent(name))
            }
        }
        var apps = [InstalledApp?](repeating: nil, count: bundles.count)
        apps.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: bundles.count) { i in
                base[i] = describe(bundles[i], measureSize: measureSizes)
            }
        }
        return apps.compactMap { $0 }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func describe(_ path: String, measureSize: Bool = true) -> InstalledApp? {
        let info = readPlist((path as NSString).appendingPathComponent("Contents/Info.plist"))
        guard let bundleID = info?["CFBundleIdentifier"] as? String else { return nil }
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String) ?? ""
        let isAppStore = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("Contents/_MASReceipt"))
        return InstalledApp(path: path, name: name, bundleID: bundleID, version: version,
                            bytes: measureSize ? FileSizer.measure(path).bytes : 0,
                            lastUsed: lastUsedDate(path), teamID: nil,
                            embeddedBundleIDs: embeddedBundleIDs(path),
                            userRemovable: isUserRemovable(path), isAppleApp: bundleID.hasPrefix("com.apple."),
                            isAppStore: isAppStore)
    }

    /// Deleting a bundle needs write access to its parent folder and to the bundle itself.
    static func isUserRemovable(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        return access(parent, W_OK) == 0 && access(path, W_OK) == 0
    }

    static func lastUsedDate(_ path: String) -> Date? {
        #if os(macOS)
        guard let r = Shell.runTool("mdls", ["-raw", "-name", "kMDItemLastUsedDate", path], timeout: 5), r.succeeded else { return nil }
        let raw = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw != "(null)" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.date(from: raw)
        #else
        return nil
        #endif
    }

    static func embeddedBundleIDs(_ path: String) -> [String] {
        var ids: [String] = []
        for sub in ["Contents/Library/LoginItems", "Contents/Library/LaunchServices", "Contents/Helpers",
                    "Contents/PlugIns", "Contents/XPCServices", "Contents/Frameworks", "Contents/Library/SystemExtensions"] {
            let dir = (path as NSString).appendingPathComponent(sub)
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for child in children {
                let plist = (dir as NSString).appendingPathComponent("\(child)/Contents/Info.plist")
                if let id = readPlist(plist)?["CFBundleIdentifier"] as? String { ids.append(id) }
                // Bare helper tools in LaunchServices are named by their bundle ID.
                if sub == "Contents/Library/LaunchServices" && child.split(separator: ".").count >= 3 { ids.append(child) }
            }
        }
        return Array(Set(ids)).sorted()
    }

    static func readPlist(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    // MARK: Leftovers (Pearcleaner-style matching)

    /// Where apps leave files. `true` marks locations holding personal data.
    static let userRoots: [(String, String, Bool)] = [
        ("~/Library/Application Support", "Application Support", true),
        ("~/Library/Application Scripts", "Application Scripts", false),
        ("~/Library/Caches", "Cache", false),
        ("~/Library/Containers", "Container", true),
        ("~/Library/Group Containers", "Group Container", true),
        ("~/Library/HTTPStorages", "HTTP Storage", false),
        ("~/Library/Logs", "Logs", false),
        ("~/Library/Logs/DiagnosticReports", "Crash Reports", false),
        ("~/Library/Preferences", "Preferences", false),
        ("~/Library/Preferences/ByHost", "Preferences", false),
        ("~/Library/Saved Application State", "Saved State", false),
        ("~/Library/WebKit", "WebKit Data", false),
        ("~/Library/LaunchAgents", "Launch Agent", false),
        ("~/Library/Cookies", "Cookies", false),
        ("~/Library/Internet Plug-Ins", "Plug-in", false),
        ("~/Library/PreferencePanes", "Preference Pane", false),
        ("~/Library/Services", "Service", false),
        ("~/Library/Application Support/CrashReporter", "Crash Reporter", false),
        ("~/Library/Caches/com.crashlytics", "Crash SDK Cache", false),
        ("~/Library/Caches/org.sparkle-project.Sparkle", "Updater Cache", false),
        ("~/Library/Caches/SentryCrash", "Crash SDK Cache", false),
    ]

    static let systemRoots: [(String, String)] = [
        ("/Library/Application Support", "Application Support"),
        ("/Library/Caches", "Cache"),
        ("/Library/Preferences", "Preferences"),
        ("/Library/LaunchAgents", "Launch Agent"),
        ("/Library/LaunchDaemons", "Launch Daemon"),
        ("/Library/PrivilegedHelperTools", "Privileged Helper"),
        ("/Library/Logs", "Logs"),
        ("/Library/Logs/DiagnosticReports", "Crash Reports"),
        ("/Library/Extensions", "Kernel Extension"),
        ("/Library/Internet Plug-Ins", "Plug-in"),
        ("/Library/PreferencePanes", "Preference Pane"),
        ("/Library/Audio/Plug-Ins/Components", "Audio Unit"),
        ("/Library/Audio/Plug-Ins/HAL", "Audio Driver"),
        ("/private/var/db/receipts", "Install Receipt"),
        ("/Users/Shared", "Shared Data"),
    ]

    /// Name fragments that must never be matched on their own (too generic).
    static let stopWords: Set<String> = ["app", "apple", "com", "org", "net", "io", "mac", "macos", "helper", "agent",
                                         "pro", "lite", "free", "plus", "the", "studio", "desktop", "player", "editor",
                                         "tools", "utility", "update", "updater", "launcher", "service", "group"]

    /// Builds the matcher for an app at a given sensitivity.
    public static func matcher(for app: InstalledApp, level: MatchLevel) -> (String) -> Bool {
        let ids = ([app.bundleID] + app.embeddedBundleIDs).map { $0.lowercased() }
        let baseID = baseBundleID(app.bundleID).lowercased()
        let name = normalizeName(app.name)
        let fileName = normalizeName(((app.path as NSString).lastPathComponent as NSString).deletingPathExtension)
        let stripped = normalizeName(stripVersion(app.name))
        let parts = app.bundleID.lowercased().split(separator: ".").map(String.init)
        let joinedTail = parts.count >= 2 ? parts.suffix(2).joined() : ""
        let company = parts.count >= 3 ? parts[1] : ""
        let team = app.teamID?.lowercased()

        let names = Set([name, fileName, stripped].filter { $0.count >= 3 && !stopWords.contains($0) })

        return { candidate in
            let raw = leafName(candidate)
            let norm = normalizeName(raw)
            // Bundle-ID matches: exact, "<id>.<suffix>", or "<prefix>.<id>" (group containers: TEAMID.<id>).
            for id in ids + [baseID] where !id.isEmpty {
                if raw == id || raw.hasPrefix(id + ".") || raw.hasSuffix("." + id) { return true }
                if level != .strict && raw.contains(id) { return true }
            }
            if names.contains(norm) { return true }
            guard level != .strict else { return false }
            if joinedTail.count >= 6 && norm == joinedTail { return true }
            for n in names where n.count >= 5 && norm.hasPrefix(n) && norm.count <= n.count + 12 { return true }
            guard level == .deep else { return false }
            if company.count >= 4 && !stopWords.contains(company) && norm == company { return true }
            if let team, raw.hasPrefix(team + ".") { return true }
            return false
        }
    }

    /// Finds files an app left outside its bundle. Sandboxed containers are matched by their metadata.
    /// `otherApps` lets the matcher drop files that clearly belong to a different installed app
    /// (e.g. "Notion Calendar" data when uninstalling "Notion").
    public static func leftovers(for app: InstalledApp, level: MatchLevel = .enhanced,
                                 otherApps: [InstalledApp] = []) -> [Leftover] {
        var app = app
        if level == .deep && app.teamID == nil { app.teamID = teamIdentifier(app.path) }
        let match = matcher(for: app, level: level)
        let ownID = app.bundleID.lowercased()
        let others = otherApps.filter { $0.path != app.path }
        let otherIDs = others.map { $0.bundleID.lowercased() }.filter { !ownID.hasPrefix($0) && !$0.hasPrefix(ownID) }
        let otherNames = Set(others.map { normalizeName($0.name) })
        var found: [String: Leftover] = [:]
        func consider(_ path: String, kind: String, system: Bool, userData: Bool) {
            guard found[path] == nil, !Paths.isInside(path, app.path), Safety.isAllowed(path) else { return }
            let raw = leafName(path)
            if otherIDs.contains(where: { raw == $0 || raw.hasPrefix($0 + ".") }) { return }
            if otherNames.contains(normalizeName(raw)) && !raw.contains(ownID) { return }
            found[path] = Leftover(path: path, bytes: 0, kind: kind, system: system, isUserData: userData)
        }
        for (root, kind, userData) in userRoots {
            let dir = Paths.expand(root)
            for child in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                let path = (dir as NSString).appendingPathComponent(child)
                if match(child) { consider(path, kind: kind, system: false, userData: userData) }
            }
        }
        // UUID-named containers: read the owner's bundle ID from the container metadata.
        let containers = Paths.expand("~/Library/Containers")
        let ids = Set(([app.bundleID] + app.embeddedBundleIDs).map { $0.lowercased() })
        for child in (try? FileManager.default.contentsOfDirectory(atPath: containers)) ?? [] where child.count == 36 {
            let path = (containers as NSString).appendingPathComponent(child)
            if let owner = containerOwner(path), ids.contains(owner.lowercased()) {
                consider(path, kind: "Container", system: false, userData: true)
            }
        }
        for (root, kind) in systemRoots {
            for child in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] {
                let path = (root as NSString).appendingPathComponent(child)
                if match(child) { consider(path, kind: kind, system: !isUserRemovable(path), userData: false) }
            }
        }
        var list = Array(found.values)
        list.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: buffer.count) { i in base[i].bytes = FileSizer.measure(base[i].path).bytes }
        }
        return list.sorted { $0.bytes > $1.bytes }
    }

    /// The signing team (e.g. "UBF8T346G9"), used only at the deep level.
    static func teamIdentifier(_ path: String) -> String? {
        #if os(macOS)
        let r = Shell.run("/usr/bin/codesign", ["-dv", "--verbose=2", path], timeout: 10)
        for line in (r.stderr + r.stdout).split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let team = String(line.dropFirst("TeamIdentifier=".count))
            return team == "not set" ? nil : team
        }
        #endif
        return nil
    }

    static func containerOwner(_ container: String) -> String? {
        let meta = (container as NSString).appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        return readPlist(meta)?["MCMMetadataIdentifier"] as? String
    }

    /// Lowercased last path component with only file-type suffixes removed. `deletingPathExtension`
    /// would turn the folder `com.vendor.app` into `com.vendor`, so bundle-ID-named folders keep their name.
    static func leafName(_ path: String) -> String {
        var name = (path as NSString).lastPathComponent.lowercased()
        for ext in [".plist", ".savedstate", ".binarycookies", ".sfl2", ".sfl3", ".sfl4", ".log", ".lock", ".db"]
            where name.hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
            break
        }
        return name
    }

    /// `com.vendor.App.helper` → `com.vendor.App`.
    static func baseBundleID(_ id: String) -> String {
        let suffixes: Set<String> = ["helper", "agent", "daemon", "service", "xpc", "launcher", "updater", "installer",
                                     "uninstaller", "login", "loginitem", "extension", "plugin", "mac", "macos"]
        var parts = id.split(separator: ".").map(String.init)
        while parts.count >= 4, let last = parts.last, suffixes.contains(last.lowercased()) { parts.removeLast() }
        return parts.joined(separator: ".")
    }

    /// Lowercase, letters and digits only: "Visual Studio Code" → "visualstudiocode".
    static func normalizeName(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// "Bartender 6" → "Bartender", "Foo 2.1" → "Foo".
    static func stripVersion(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        while let last = words.last, words.count > 1, last.allSatisfy({ $0.isNumber || $0 == "." }) { words.removeLast() }
        return words.joined(separator: " ")
    }

    // MARK: Removing

    /// Removal requests for an uninstall: the bundle goes to the Trash, leftovers as selected.
    public static func requests(app: InstalledApp, leftovers: [Leftover], sudo: Bool) -> [RemovalRequest] {
        var requests = [RemovalRequest(item: ScanItem(path: app.path, bytes: app.bytes, isDirectory: true),
                                       scope: app.userRemovable ? .user : .system, preferTrash: true)]
        for l in leftovers {
            requests.append(RemovalRequest(item: ScanItem(path: l.path, bytes: l.bytes), scope: l.system ? .system : .user,
                                           preferTrash: !l.kind.contains("Cache") && !l.kind.contains("Log")))
        }
        return requests
    }

    /// Commands to unload launchd jobs before their plists are removed.
    public static func unloadScript(for leftovers: [Leftover]) -> (user: [[String]], root: PrivilegedScript) {
        var user: [[String]] = []
        var root = PrivilegedScript()
        let uid = getuid()
        for l in leftovers where l.path.hasSuffix(".plist") {
            if l.kind == "Launch Agent" && !l.system {
                user.append(["/bin/launchctl", "bootout", "gui/\(uid)", l.path])
            } else if l.kind == "Launch Daemon" || (l.kind == "Launch Agent" && l.system) {
                root.add("/bin/launchctl", ["bootout", l.kind == "Launch Daemon" ? "system" : "gui/\(uid)", l.path])
            }
        }
        return (user, root)
    }
}
