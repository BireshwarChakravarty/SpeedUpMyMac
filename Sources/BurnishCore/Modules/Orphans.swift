import Foundation

/// Files left behind by apps that are no longer installed (Pearcleaner's "orphaned files").
///
/// Only reverse-DNS-named items are considered (com.vendor.thing), because those can be attributed
/// to a bundle ID with confidence. Everything found is `review` risk: never pre-selected.
public enum Orphans {
    static let roots: [(String, String)] = [
        ("~/Library/Application Support", "Application Support"),
        ("~/Library/Caches", "Cache"),
        ("~/Library/Containers", "Container"),
        ("~/Library/Group Containers", "Group Container"),
        ("~/Library/HTTPStorages", "HTTP Storage"),
        ("~/Library/Preferences", "Preferences"),
        ("~/Library/Saved Application State", "Saved State"),
        ("~/Library/WebKit", "WebKit Data"),
        ("~/Library/LaunchAgents", "Launch Agent"),
        ("~/Library/Application Scripts", "Application Scripts"),
    ]

    /// Bundle-ID prefixes that belong to the OS, frameworks, or shared infrastructure.
    static let ignoredPrefixes = ["com.apple.", "group.com.apple.", "apple.", "systemgroup.", "com.microsoft.office",
                                  "ubf8t346g9.", "com.google.keystone", "org.sparkle-project", "io.burnish", "com.crashlytics",
                                  "com.plausiblelabs", "com.segment", "com.getsentry", "ksdatabase", "nsurlsession"]

    public static func find(installed: [InstalledApp], minBytes: Int64 = 0) -> [Leftover] {
        var known = Set<String>()
        for app in installed {
            known.insert(app.bundleID.lowercased())
            known.insert(Uninstaller.baseBundleID(app.bundleID).lowercased())
            for id in app.embeddedBundleIDs { known.insert(id.lowercased()) }
        }
        // System apps also own preferences and containers.
        for dir in ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices"] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".app") {
                let plist = (dir as NSString).appendingPathComponent("\(name)/Contents/Info.plist")
                if let id = Uninstaller.readPlist(plist)?["CFBundleIdentifier"] as? String { known.insert(id.lowercased()) }
            }
        }

        var results: [Leftover] = []
        for (root, kind) in roots {
            let dir = Paths.expand(root)
            for child in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                let path = (dir as NSString).appendingPathComponent(child)
                var id = Uninstaller.leafName(child)
                if kind == "Container", child.count == 36, let owner = Uninstaller.containerOwner(path) { id = owner.lowercased() }
                if kind == "Group Container" { id = stripTeamPrefix(id) }
                                guard looksLikeBundleID(id), !ignoredPrefixes.contains(where: { id.hasPrefix($0) }) else { continue }
                guard !isOwned(id, by: known), Safety.isAllowed(path) else { continue }
                results.append(Leftover(path: path, bytes: 0, kind: kind, system: false,
                                        isUserData: kind == "Application Support" || kind.contains("Container")))
            }
        }
        results.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: buffer.count) { i in base[i].bytes = FileSizer.measure(base[i].path).bytes }
        }
        if !results.isEmpty { results = results.filter { !spotlightKnowsBundle(bundleID(of: $0)) } }
        return results.filter { $0.bytes >= minBytes }.sorted { $0.bytes > $1.bytes }
    }

    static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty } && !s.contains(" ")
    }

    /// `TEAMID.com.vendor.app` → `com.vendor.app`; `group.com.vendor` → `com.vendor`.
    static func stripTeamPrefix(_ id: String) -> String {
        var parts = id.split(separator: ".").map(String.init)
        if let first = parts.first, first.count == 10, first.allSatisfy({ $0.isLetter || $0.isNumber }) { parts.removeFirst() }
        if parts.first == "group" { parts.removeFirst() }
        return parts.joined(separator: ".")
    }

    /// Owned if it equals an installed ID or is a child/parent namespace of one.
    static func isOwned(_ id: String, by known: Set<String>) -> Bool {
        if known.contains(id) || known.contains(Uninstaller.baseBundleID(id).lowercased()) { return true }
        for k in known where id.hasPrefix(k + ".") || k.hasPrefix(id + ".") { return true }
        return false
    }

    static func bundleID(of leftover: Leftover) -> String {
        let name = Uninstaller.leafName(leftover.path)
        return leftover.kind == "Group Container" ? stripTeamPrefix(name) : name
    }

    /// Last check: an app with this bundle ID exists somewhere Spotlight can see (external drive, Downloads…).
    static func spotlightKnowsBundle(_ id: String) -> Bool {
        #if os(macOS)
        guard looksLikeBundleID(id.lowercased()), !id.contains("'") else { return false }
        let r = Shell.run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == '\(id)'c"], timeout: 5)
        return r.succeeded && !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #else
        return false
        #endif
    }
}
