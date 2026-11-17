import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where an app's update comes from.
public enum UpdateSource: String, Codable, CaseIterable, Sendable {
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case builtIn = "Built-in updater"
}

/// One app with a newer version available.
public struct AppUpdate: Codable, Identifiable, Hashable, Sendable {
    public var id: String { appPath }
    public var appPath: String
    public var name: String
    public var bundleID: String
    /// Versions as people read them ("2.4.1"), not build numbers.
    public var installed: String
    public var latest: String
    public var source: UpdateSource
    /// Homebrew's name for the app, for `brew upgrade --cask`.
    public var caskToken: String?
    /// A page describing what's new, when the feed or store gives one.
    public var releaseNotesURL: String?
    /// The App Store page, for App Store apps.
    public var storeURL: String?
}

/// The result of one check.
public struct UpdateReport: Codable, Sendable {
    public var updates: [AppUpdate]
    /// Apps that were checked and are current.
    public var upToDate: [String]
    /// Apps that update themselves in a way Spruce can't read (Chrome, Electron apps, apps with
    /// their own installers). Their own "Check for Updates" still works.
    public var unchecked: [String]
    /// Apps whose feed or store didn't answer.
    public var failed: [String]
    /// Homebrew was found and asked.
    public var usedHomebrew: Bool
    public var checkedAt: Date
}

/// What Spruce needs to know about an installed app to check it.
public struct UpdateCandidate: Sendable, Equatable {
    public var path: String
    public var name: String
    public var bundleID: String
    /// CFBundleShortVersionString.
    public var version: String
    /// CFBundleVersion, which Sparkle feeds compare against.
    public var build: String
    /// SUFeedURL from Info.plist, for apps that use Sparkle.
    public var feedURL: String?
    public var isAppStore: Bool
    public var isApple: Bool

    public init(path: String, name: String, bundleID: String, version: String, build: String,
                feedURL: String?, isAppStore: Bool, isApple: Bool) {
        self.path = path; self.name = name; self.bundleID = bundleID; self.version = version
        self.build = build; self.feedURL = feedURL; self.isAppStore = isAppStore; self.isApple = isApple
    }
}

/// A cask Homebrew has installed, from `brew info --cask --json=v2 --installed`.
public struct BrewCask: Sendable, Equatable {
    public var token: String
    public var apps: [String]          // "Firefox.app"
    public var installed: String
    public var latest: String
    public var outdated: Bool
    /// The app updates itself; Homebrew leaves it alone unless asked with --greedy.
    public var autoUpdates: Bool
}

/// One `<item>` of a Sparkle appcast.
public struct AppcastItem: Sendable, Equatable {
    public var version: String
    public var shortVersion: String?
    public var minimumSystem: String?
    public var releaseNotes: String?
    public var channel: String?
}

/// Finds apps with newer versions. It only reads: updating is left to Homebrew, the App Store or
/// the app's own updater, so nothing here touches an app bundle.
///
/// Network use: each Sparkle app's own feed (the address the app itself checks), Apple's public
/// App Store lookup (bundle IDs only), and Homebrew's own update. Nothing else about the Mac is sent.
public enum AppUpdates {
    public typealias Fetch = @Sendable (URL) -> Data?

    // MARK: Checking

    public static func check(osVersion: String = currentOSVersion(), region: String = currentRegion(),
                             fetch: Fetch = AppUpdates.fetch) -> UpdateReport {
        let candidates = Uninstaller.installedApps(measureSizes: false).compactMap { candidate($0.path) }
        let brew = brewPath().flatMap { path -> [BrewCask]? in
            _ = Shell.run(path, ["update", "--quiet"], timeout: 120, environment: brewEnvironment())
            let r = Shell.run(path, ["info", "--cask", "--json=v2", "--installed"], timeout: 120, environment: brewEnvironment())
            return r.succeeded ? parseBrewCasks(Data(r.stdout.utf8)) : nil
        }
        return check(candidates, casks: brew, osVersion: osVersion, region: region, fetch: fetch)
    }

    /// The core of `check`, with everything it reads passed in (tests use this).
    public static func check(_ candidates: [UpdateCandidate], casks: [BrewCask]?, osVersion: String, region: String,
                             fetch: Fetch) -> UpdateReport {
        var caskByApp: [String: BrewCask] = [:]
        for cask in casks ?? [] { for app in cask.apps { caskByApp[app.lowercased()] = cask } }

        let outcomes = Locked([Outcome](repeating: .skip, count: candidates.count))
        DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
            let app = candidates[i]
            let bundleName = (app.path as NSString).lastPathComponent.lowercased()
            let outcome: Outcome
            if let cask = caskByApp[bundleName], !cask.autoUpdates {
                // Homebrew manages it: Homebrew's answer is the one that counts.
                outcome = cask.outdated
                    ? .update(AppUpdate(appPath: app.path, name: app.name, bundleID: app.bundleID,
                                        installed: displayVersion(app.version.isEmpty ? cask.installed : app.version),
                                        latest: displayVersion(cask.latest), source: .homebrew, caskToken: cask.token))
                    : .current(app.name)
            } else if app.isAppStore {
                outcome = checkAppStore(app, region: region, fetch: fetch)
            } else if app.isApple {
                outcome = .skip   // updated with macOS
            } else if let feed = app.feedURL {
                outcome = checkFeed(app, feed: feed, osVersion: osVersion, cask: caskByApp[bundleName], fetch: fetch)
            } else {
                outcome = .unchecked(app.name)
            }
            outcomes.mutate { $0[i] = outcome }
        }

        var report = UpdateReport(updates: [], upToDate: [], unchecked: [], failed: [], usedHomebrew: casks != nil, checkedAt: Date())
        for outcome in outcomes.value {
            switch outcome {
            case .update(let u): report.updates.append(u)
            case .current(let name): report.upToDate.append(name)
            case .unchecked(let name): report.unchecked.append(name)
            case .failed(let name): report.failed.append(name)
            case .skip: break
            }
        }
        let order = UpdateSource.allCases
        report.updates.sort { (order.firstIndex(of: $0.source)!, $0.name.lowercased()) < (order.firstIndex(of: $1.source)!, $1.name.lowercased()) }
        report.upToDate.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        report.unchecked.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        report.failed.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return report
    }

    private enum Outcome { case update(AppUpdate), current(String), unchecked(String), failed(String), skip }

    private static func checkAppStore(_ app: UpdateCandidate, region: String, fetch: Fetch) -> Outcome {
        var parts = URLComponents(string: "https://itunes.apple.com/lookup")!
        parts.queryItems = [URLQueryItem(name: "bundleId", value: app.bundleID), URLQueryItem(name: "country", value: region)]
        guard let url = parts.url, let data = fetch(url) else { return .failed(app.name) }
        guard let store = parseStoreLookup(data) else { return .current(app.name) }   // not sold in this region
        guard compareVersions(store.version, app.version) == .orderedDescending else { return .current(app.name) }
        return .update(AppUpdate(appPath: app.path, name: app.name, bundleID: app.bundleID,
                                 installed: app.version, latest: store.version, source: .appStore,
                                 storeURL: store.url))
        }

    private static func checkFeed(_ app: UpdateCandidate, feed: String, osVersion: String, cask: BrewCask?, fetch: Fetch) -> Outcome {
        guard let url = URL(string: feed), url.scheme?.lowercased() == "https" else { return .unchecked(app.name) }
        guard let data = fetch(url) else { return .failed(app.name) }
        let items = parseAppcast(data)
        guard !items.isEmpty else { return .failed(app.name) }
        guard let newest = latest(items, osVersion: osVersion) else { return .current(app.name) }
        // Sparkle compares the feed's sparkle:version with the app's CFBundleVersion.
        let installedBuild = app.build.isEmpty ? app.version : app.build
        guard compareVersions(newest.version, installedBuild) == .orderedDescending else { return .current(app.name) }
        let notes = newest.releaseNotes.flatMap { URL(string: $0) }.flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0.absoluteString : nil }
        return .update(AppUpdate(appPath: app.path, name: app.name, bundleID: app.bundleID,
                                 installed: displayVersion(app.version.isEmpty ? app.build : app.version),
                                 latest: displayVersion(newest.shortVersion ?? newest.version), source: .builtIn,
                                 caskToken: cask?.token, releaseNotesURL: notes))
    }

    /// Reads what the checker needs from an app's Info.plist. Nil for bundles without an identifier.
    public static func candidate(_ path: String) -> UpdateCandidate? {
        let plist = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String else { return nil }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateCandidate(path: path, name: name, bundleID: id,
                               version: (info["CFBundleShortVersionString"] as? String) ?? "",
                               build: (info["CFBundleVersion"] as? String) ?? "",
                               feedURL: (feed?.isEmpty ?? true) ? nil : feed,
                               isAppStore: FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("Contents/_MASReceipt")),
                               isApple: id.hasPrefix("com.apple."))
    }

    // MARK: Homebrew

    public static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The app's own environment plus Homebrew's folder on PATH (apps start with a bare PATH).
    public static func brewEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (dirs + [env["PATH"] ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        return env
    }

    /// Runs `brew upgrade --cask` for one cask. Nil on success, else Homebrew's last words.
    public static func upgrade(cask token: String) -> String? {
        guard let brew = brewPath() else { return "Homebrew isn't installed" }
        var env = brewEnvironment()
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"   // the check just updated
        let r = Shell.run(brew, ["upgrade", "--cask", token], timeout: 1800, environment: env)
        if r.succeeded { return nil }
        let text = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.localizedCaseInsensitiveContains("sudo") || text.localizedCaseInsensitiveContains("password") {
            return "needs your password. Run brew upgrade --cask \(token) in Terminal"
        }
        return text.split(separator: "\n").last.map(String.init) ?? "brew upgrade failed"
    }

    public static func parseBrewCasks(_ data: Data) -> [BrewCask] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { cask in
            guard let token = cask["token"] as? String else { return nil }
            var apps: [String] = []
            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                for entry in artifact["app"] as? [Any] ?? [] {
                    if let name = entry as? String { apps.append((name as NSString).lastPathComponent) }
                    else if let target = (entry as? [String: Any])?["target"] as? String { apps.append((target as NSString).lastPathComponent) }
                }
            }
            return BrewCask(token: token, apps: apps,
                            installed: (cask["installed"] as? String) ?? "",
                            latest: (cask["version"] as? String) ?? "",
                            outdated: (cask["outdated"] as? Bool) ?? false,
                            autoUpdates: (cask["auto_updates"] as? Bool) ?? false)
        }
    }

    // MARK: App Store

    public static func parseStoreLookup(_ data: Data) -> (version: String, url: String?)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let first = (root["results"] as? [[String: Any]])?.first,
              let version = first["version"] as? String else { return nil }
        return (version, first["trackViewUrl"] as? String)
    }

    // MARK: Sparkle appcasts

    public static func parseAppcast(_ data: Data) -> [AppcastItem] {
        let reader = AppcastReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        parser.parse()
        return reader.items
    }

    /// The newest release item this Mac can run, ignoring beta channels.
    public static func latest(_ items: [AppcastItem], osVersion: String) -> AppcastItem? {
        items.filter { item in
            guard item.channel == nil || item.channel?.isEmpty == true else { return false }
            guard let minimum = item.minimumSystem, !minimum.isEmpty else { return true }
            return compareVersions(minimum, osVersion) != .orderedDescending
        }
        .max { compareVersions($0.version, $1.version) == .orderedAscending }
    }

    // MARK: Versions

    /// Compares versions the way Sparkle does: numbers numerically, "1.10" after "1.9", and a
    /// pre-release ("1.0b2") before its release ("1.0").
    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let x = tokens(a), y = tokens(b)
        for i in 0..<max(x.count, y.count) {
            switch (i < x.count ? x[i] : nil, i < y.count ? y[i] : nil) {
            case let (.number(p)?, .number(q)?):
                if p != q { return p < q ? .orderedAscending : .orderedDescending }
            case let (.text(p)?, .text(q)?):
                let c = p.compare(q, options: .caseInsensitive)
                if c != .orderedSame { return c }
            case (.number?, .text?): return .orderedDescending
            case (.text?, .number?): return .orderedAscending
            case (.number?, nil): return .orderedDescending   // 1.0.1 > 1.0
            case (.text?, nil): return .orderedAscending      // 1.0b1 < 1.0
            case (nil, .number?): return .orderedAscending
            case (nil, .text?): return .orderedDescending
            case (nil, nil): return .orderedSame
            }
        }
        return .orderedSame
    }

    private enum Token { case number(Int), text(String) }

    private static func tokens(_ version: String) -> [Token] {
        var out: [Token] = []
        var current = ""
        var isDigit = false
        func flush() {
            guard !current.isEmpty else { return }
            out.append(isDigit ? .number(Int(current.prefix(18)) ?? 0) : .text(current))
            current = ""
        }
        for ch in version {
            if ch.isNumber && ch.isASCII {
                if !isDigit { flush(); isDigit = true }
                current.append(ch)
            } else if ch.isLetter {
                if isDigit { flush(); isDigit = false }
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    /// Homebrew versions can carry a build after a comma ("124.0,20240401"): show the first part.
    static func displayVersion(_ v: String) -> String {
        String(v.split(separator: ",").first ?? Substring(v))
    }

    // MARK: Environment

    public static func currentOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    public static func currentRegion() -> String {
        #if os(macOS)
        if #available(macOS 13, *), let region = Locale.current.region?.identifier { return region.lowercased() }
        #endif
        return "us"
    }

    /// A plain GET with a short timeout. Nil on any error or a non-2xx answer.
    public static let fetch: Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Spruce", forHTTPHeaderField: "User-Agent")
        let box = Locked<Data?>(nil)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) { box.mutate { $0 = data } }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        return box.value
    }
}

/// A value shared between threads.
final class Locked<Value>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout Value) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}

/// Collects `<item>`s from a Sparkle feed. Versions can be attributes of `<enclosure>` (Sparkle 1)
/// or elements of their own (Sparkle 2).
private final class AppcastReader: NSObject, XMLParserDelegate {
    var items: [AppcastItem] = []
    private var current: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { current = [:]; return }
        guard current != nil else { return }
        if name == "enclosure" {
            for key in ["sparkle:version", "sparkle:shortVersionString", "sparkle:minimumSystemVersion"] {
                if let value = attributes[key], current?[key] == nil { current?[key] = value }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" {
            if let c = current, let version = c["sparkle:version"], !version.isEmpty {
                items.append(AppcastItem(version: version, shortVersion: c["sparkle:shortVersionString"],
                                         minimumSystem: c["sparkle:minimumSystemVersion"],
                                         releaseNotes: c["sparkle:releaseNotesLink"] ?? c["sparkle:fullReleaseNotesLink"] ?? c["link"],
                                         channel: c["sparkle:channel"]))
            }
            current = nil
            return
        }
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["sparkle:version", "sparkle:shortVersionString", "sparkle:minimumSystemVersion", "sparkle:releaseNotesLink",
            "sparkle:fullReleaseNotesLink", "sparkle:channel", "link"].contains(name), !value.isEmpty {
            current?[name] = value
        }
    }
}
