import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The outcome of installing one update.
public struct InstallResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    /// The version now on disk, when it could be read.
    public var version: String?
}

/// Installs updates found by `AppUpdates`.
///
/// - Homebrew apps: `brew upgrade --cask`.
/// - App Store apps: `mas upgrade` (Spruce installs `mas` with Homebrew when it's missing).
/// - Everything else: Spruce downloads the new version itself, from the app's own update feed or
///   Homebrew's catalogue, and only installs it when
///     1. the file matches the developer's EdDSA signature (the key inside the installed app) or
///        Homebrew's SHA-256,
///     2. the new app's code signature is valid,
///     3. it's signed by the same developer (team ID) as the installed app,
///     4. it has the same bundle ID and a newer version.
///   The app is quit first if it's running, swapped in place (the old copy is kept until the new
///   one is in), and reopened afterwards.
public enum AppInstaller {
    /// Quits a running app politely (set by the app with NSRunningApplication; the CLI asks instead).
    /// Returns once the app has quit, or false if it wouldn't.
    nonisolated(unsafe) public static var quitApp: ((_ bundleID: String, _ appPath: String) -> Bool)?

    public static func install(_ update: AppUpdate, sudo: Bool, runner: PrivilegeRunner?,
                               progress: @escaping @Sendable (String) -> Void = { _ in }) -> InstallResult {
        #if os(macOS)
        switch update.source {
        case .homebrew:
            guard let token = update.caskToken else { return fail("Homebrew doesn't know this app") }
            progress("Updating \(update.name) with Homebrew…")
            if let error = AppUpdates.upgrade(cask: token) { return fail(error) }
            return finished(update)
        case .appStore:
            return installFromStore(update, sudo: sudo, runner: runner, progress: progress)
        case .builtIn:
            guard let download = update.download else {
                return fail("\(update.name) doesn't publish a download Spruce can verify. Use its own Check for Updates.")
            }
            return installDownload(update, download, sudo: sudo, runner: runner, progress: progress)
        }
        #else
        return fail("Installing updates needs macOS")
        #endif
    }

    static func fail(_ message: String) -> InstallResult { InstallResult(ok: false, message: message, version: nil) }

    /// Reads the version now installed and reports success only if it moved forward.
    static func finished(_ update: AppUpdate) -> InstallResult {
        let now = bundleVersion(update.appPath)
        if let now, AppUpdates.compareVersions(now, update.installed) != .orderedDescending {
            return fail("\(update.name) is still \(now) after the update")
        }
        return InstallResult(ok: true, message: "\(update.name) updated to \(now ?? update.latest)", version: now)
    }

    // MARK: App Store

    public static func masPath() -> String? {
        ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func installFromStore(_ update: AppUpdate, sudo: Bool, runner: PrivilegeRunner?,
                                 progress: @escaping @Sendable (String) -> Void) -> InstallResult {
        guard let id = update.storeID else { return fail("The App Store didn't give an ID for \(update.name)") }
        var mas = masPath()
        if mas == nil, let brew = AppUpdates.brewPath() {
            progress("Installing the mas tool with Homebrew…")
            var env = AppUpdates.brewEnvironment()
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            _ = Shell.run(brew, ["install", "mas"], timeout: 900, environment: env)
            mas = masPath()
        }
        guard let mas else {
            return fail("Updating App Store apps needs the mas tool, which Spruce installs with Homebrew. Install Homebrew, or update from the App Store.")
        }
        progress("Updating \(update.name) from the App Store…")
        var result = Shell.run(mas, ["upgrade", String(id)], timeout: 3600, environment: AppUpdates.brewEnvironment())
        // Newer versions of mas install as root.
        if finished(update).ok == false, sudo, let runner {
            var script = PrivilegedScript()
            script.add(mas, ["upgrade", String(id)], tolerateFailure: false)
            if let r = try? runner.run(script, reason: "Spruce needs your password to update \(update.name) from the App Store.") { result = r }
        }
        let done = finished(update)
        if done.ok { return done }
        let said = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sudo && Privilege.currentUserIsAdmin() {
            return fail("The App Store didn't install it. Turn on Admin mode and try again, or update from the App Store.")
        }
        return fail(said.isEmpty ? "The App Store didn't install it. Make sure you're signed in to the App Store." : said)
    }

    // MARK: Direct downloads

    enum Payload { case zip, tar, dmg, pkg }

    #if os(macOS)
    static func installDownload(_ update: AppUpdate, _ download: UpdateDownload, sudo: Bool, runner: PrivilegeRunner?,
                                progress: @escaping @Sendable (String) -> Void) -> InstallResult {
        let fm = FileManager.default
        let work = (NSTemporaryDirectory() as NSString).appendingPathComponent("Spruce-update-\(UUID().uuidString)")
        try? fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: work) }

        progress("Downloading \(update.name) \(update.latest)…")
        guard let url = URL(string: download.url), let file = downloadFile(url, into: work) else {
            return fail("Couldn't download \(update.name) \(update.latest)")
        }

        // 1. The file itself.
        progress("Checking \(update.name)…")
        var fileVerified = false
        if let expected = download.sha256 {
            guard sha256(file) == expected.lowercased() else { return fail("The download doesn't match Homebrew's checksum, so Spruce didn't install it") }
            fileVerified = true
        }
        let info = plist(update.appPath)
        if download.origin == "feed", let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            guard let signature = download.edSignature, verifyEdDSA(file: file, signature: signature, publicKey: key) else {
                return fail("The download isn't signed by \(update.name)'s developer, so Spruce didn't install it")
            }
            fileVerified = true
        }
        let oldTeam = Uninstaller.teamIdentifier(update.appPath)

        let kind = payloadKind(file, url: url)
        if kind == .pkg {
            return installPackage(update, file: file, oldTeam: oldTeam, sudo: sudo, runner: runner, progress: progress)
        }

        // 2–4. The app inside.
        progress("Unpacking \(update.name)…")
        let unpacked = (work as NSString).appendingPathComponent("unpacked")
        try? fm.createDirectory(atPath: unpacked, withIntermediateDirectories: true)
        guard unpack(file, kind: kind, into: unpacked, work: work) else { return fail("Couldn't open the downloaded \(kindName(kind))") }
        guard let newApp = findApp(in: unpacked, bundleID: update.bundleID) else {
            return fail("The download doesn't contain \(update.name) (\(update.bundleID))")
        }
        guard Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp], timeout: 300).succeeded else {
            return fail("The new version's code signature isn't valid, so Spruce didn't install it")
        }
        let newTeam = Uninstaller.teamIdentifier(newApp)
        if let oldTeam {
            guard newTeam == oldTeam else {
                return fail("The new version is signed by a different developer (\(newTeam ?? "unsigned") instead of \(oldTeam)), so Spruce didn't install it")
            }
        } else if !fileVerified {
            return fail("\(update.name) isn't signed by a known developer and the download can't be checked, so Spruce didn't install it")
        }
        let newVersion = bundleVersion(newApp) ?? ""
        let newBuild = plist(newApp)["CFBundleVersion"] as? String ?? ""
        let oldBuild = info["CFBundleVersion"] as? String ?? ""
        let newer = AppUpdates.compareVersions(newVersion, update.installed) == .orderedDescending
            || (AppUpdates.compareVersions(newVersion, update.installed) == .orderedSame && AppUpdates.compareVersions(newBuild, oldBuild) == .orderedDescending)
        guard newer else { return fail("The download is \(newVersion), which isn't newer than \(update.installed)") }

        // Swap it in.
        progress("Installing \(update.name) \(newVersion)…")
        let wasRunning = !Uninstaller.runningProcesses(inside: update.appPath).isEmpty
        if wasRunning {
            guard quitApp?(update.bundleID, update.appPath) == true,
                  Uninstaller.runningProcesses(inside: update.appPath).isEmpty else {
                return fail("Quit \(update.name) and try again")
            }
        }
        if let error = replace(update.appPath, with: newApp, sudo: sudo, runner: runner, name: update.name) { return fail(error) }
        _ = Shell.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                      ["-f", update.appPath], timeout: 30)
        if wasRunning { _ = Shell.run("/usr/bin/open", [update.appPath], timeout: 30) }
        return finished(update)
    }

    /// Installer packages run as root, so they need Admin mode and a package signed by the same developer.
    static func installPackage(_ update: AppUpdate, file: String, oldTeam: String?, sudo: Bool, runner: PrivilegeRunner?,
                               progress: @escaping @Sendable (String) -> Void) -> InstallResult {
        let check = Shell.run("/usr/sbin/pkgutil", ["--check-signature", file], timeout: 60)
        guard check.succeeded, check.stdout.contains("Status: signed") else {
            return fail("The installer package isn't signed, so Spruce didn't install it")
        }
        if let oldTeam, !check.stdout.contains("(\(oldTeam))") {
            return fail("The installer package is signed by a different developer, so Spruce didn't install it")
        }
        guard sudo, let runner else { return fail("\(update.name) updates with an installer package. Turn on Admin mode and try again.") }
        if !Uninstaller.runningProcesses(inside: update.appPath).isEmpty {
            guard quitApp?(update.bundleID, update.appPath) == true else { return fail("Quit \(update.name) and try again") }
        }
        progress("Installing \(update.name)…")
        var script = PrivilegedScript()
        script.add("/usr/sbin/installer", ["-pkg", file, "-target", "/"], tolerateFailure: false)
        do {
            let r = try runner.run(script, reason: "Spruce needs your password to install the \(update.name) update.")
            if !r.succeeded { return fail(r.stderr.isEmpty ? "The installer failed" : r.stderr) }
        } catch {
            return fail(error.localizedDescription)
        }
        return finished(update)
    }

    /// Copies the new app next to the old one, then swaps them, so the app is never missing.
    /// Uses Admin mode when the folder isn't writable (apps installed by a package are owned by root).
    static func replace(_ appPath: String, with newApp: String, sudo: Bool, runner: PrivilegeRunner?, name: String) -> String? {
        let parent = (appPath as NSString).deletingLastPathComponent
        let base = (appPath as NSString).lastPathComponent
        let staging = (parent as NSString).appendingPathComponent(".\(base).spruce-new")
        let backup = (parent as NSString).appendingPathComponent(".\(base).spruce-old")
        let fm = FileManager.default
        try? fm.removeItem(atPath: staging)
        try? fm.removeItem(atPath: backup)
        if fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: appPath),
           Shell.run("/usr/bin/ditto", [newApp, staging], timeout: 900).succeeded {
            do {
                try fm.moveItem(atPath: appPath, toPath: backup)
                do {
                    try fm.moveItem(atPath: staging, toPath: appPath)
                } catch {
                    try? fm.moveItem(atPath: backup, toPath: appPath)   // put the old one back
                    throw error
                }
                try? fm.removeItem(atPath: backup)
                return nil
            } catch {
                try? fm.removeItem(atPath: staging)
            }
        }
        try? fm.removeItem(atPath: staging)
        guard sudo, let runner else {
            return "\(name) is owned by the system. Turn on Admin mode and try again."
        }
        var script = PrivilegedScript()
        script.addChain([
            ["/usr/bin/ditto", newApp, staging],
            ["/bin/mv", appPath, backup],
            ["/bin/mv", staging, appPath],
            ["/bin/rm", "-rf", backup],
        ])
        // If the swap stopped half way, the old app goes back.
        script.addChain([["/bin/test", "-e", backup], ["/bin/test", "!", "-e", appPath], ["/bin/mv", backup, appPath]])
        script.add("/bin/rm", ["-rf", staging])
        do {
            _ = try runner.run(script, reason: "Spruce needs your password to replace \(name) with its new version.")
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    static func downloadFile(_ url: URL, into folder: String) -> String? {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Spruce", forHTTPHeaderField: "User-Agent")
        let result = Locked<String?>(nil)
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: request) { location, response, _ in
            defer { done.signal() }
            guard let location, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let name = (response?.suggestedFilename).flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
            let safe = name.replacingOccurrences(of: "/", with: "_")
            let target = (folder as NSString).appendingPathComponent(safe.isEmpty ? "download" : safe)
            if (try? FileManager.default.moveItem(atPath: location.path, toPath: target)) != nil { result.mutate { $0 = target } }
        }
        task.resume()
        if done.wait(timeout: .now() + 3600) == .timedOut { task.cancel(); return nil }
        return result.value
    }

    static func unpack(_ file: String, kind: Payload, into folder: String, work: String) -> Bool {
        switch kind {
        case .zip: return Shell.run("/usr/bin/ditto", ["-x", "-k", file, folder], timeout: 900).succeeded
        case .tar: return Shell.run("/usr/bin/tar", ["-xf", file, "-C", folder], timeout: 900).succeeded
        case .pkg: return false
        case .dmg:
            let mount = (work as NSString).appendingPathComponent("mount")
            try? FileManager.default.createDirectory(atPath: mount, withIntermediateDirectories: true)
            guard Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", "-noverify", "-readonly", "-mountpoint", mount, file],
                            timeout: 600).succeeded else { return false }
            defer { _ = Shell.run("/usr/bin/hdiutil", ["detach", mount, "-force"], timeout: 120) }
            let apps = appsIn(mount, depth: 2)
            guard !apps.isEmpty else { return false }
            for app in apps {
                let target = (folder as NSString).appendingPathComponent((app as NSString).lastPathComponent)
                guard Shell.run("/usr/bin/ditto", [app, target], timeout: 900).succeeded else { return false }
            }
            return true
        }
    }
    #endif

    static func kindName(_ kind: Payload) -> String {
        switch kind { case .zip: return "zip archive"; case .tar: return "archive"; case .dmg: return "disk image"; case .pkg: return "installer package" }
    }

    /// Tells archives apart by their first bytes (download names aren't reliable: "stable", "download").
    static func payloadKind(_ file: String, url: URL) -> Payload {
        let handle = FileHandle(forReadingAtPath: file)
        let head = [UInt8](handle?.readData(ofLength: 8) ?? Data())
        var tail = Data()
        if let handle, let size = try? handle.seekToEnd(), size >= 512 {
            try? handle.seek(toOffset: size - 512)
            tail = handle.readData(ofLength: 4)
        }
        try? handle?.close()
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .zip }
        if head.starts(with: Array("xar!".utf8)) { return .pkg }
        if head.starts(with: [0x1F, 0x8B]) || head.starts(with: Array("BZh".utf8)) || head.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A]) { return .tar }
        if tail == Data("koly".utf8) { return .dmg }
        switch url.pathExtension.lowercased() {
        case "zip": return .zip
        case "pkg", "mpkg": return .pkg
        case "tar", "tgz", "gz", "bz2", "xz", "tbz": return .tar
        default: return .dmg
        }
    }

    /// Finds the app with this bundle ID in an unpacked download (it may sit inside a folder).
    static func findApp(in folder: String, bundleID: String) -> String? {
        appsIn(folder, depth: 3).first { (plist($0)["CFBundleIdentifier"] as? String) == bundleID }
    }

    static func appsIn(_ folder: String, depth: Int) -> [String] {
        guard depth > 0, let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        var found: [String] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let path = (folder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil ? path : ""
            if resolved.isEmpty { continue }   // a link to /Applications in a disk image
            if name.hasSuffix(".app") { found.append(path) } else { found += appsIn(path, depth: depth - 1) }
        }
        return found
    }

    static func plist(_ appPath: String) -> [String: Any] {
        let path = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }

    static func bundleVersion(_ appPath: String) -> String? {
        let info = plist(appPath)
        return (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String)
    }

    static func sha256(_ file: String) -> String? {
        #if canImport(CryptoKit)
        guard let handle = FileHandle(forReadingAtPath: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 4 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        let r = Shell.run("/usr/bin/sha256sum", [file], timeout: 600)
        return r.succeeded ? r.stdout.split(separator: " ").first.map(String.init) : nil
        #endif
    }

    /// Sparkle's EdDSA check: the archive's bytes, signed with the developer's private key, against
    /// the public key (`SUPublicEDKey`) shipped inside the installed app.
    static func verifyEdDSA(file: String, signature: String, publicKey: String) -> Bool {
        #if canImport(CryptoKit)
        guard let keyData = Data(base64Encoded: publicKey), let sigData = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let data = try? Data(contentsOf: URL(fileURLWithPath: file), options: .alwaysMapped) else { return false }
        return key.isValidSignature(sigData, for: data)
        #else
        return false
        #endif
    }
}
