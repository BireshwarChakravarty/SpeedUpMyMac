import XCTest
@testable import RootCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Every test runs against a throwaway home directory (ROOTAPP_HOME), never your real one.
class SandboxedTestCase: XCTestCase {
    var home: String!

    override func setUp() {
        super.setUp()
        home = (NSTemporaryDirectory() as NSString).appendingPathComponent("root-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        setenv("ROOTAPP_HOME", home, 1)
        Safety.userIgnored = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("ROOTAPP_HOME")
        super.tearDown()
    }

    @discardableResult
    func makeFile(_ relative: String, bytes: Int = 1024, age days: Double = 0) -> String {
        let path = (home as NSString).appendingPathComponent(relative)
        try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x2A, count: bytes))
        if days > 0 {
            let date = Date().addingTimeInterval(-days * 86_400)
            try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
        }
        return path
    }

    /// Back-dates every file and folder under `relative`.
    func age(_ relative: String, days: Double) {
        let root = (home as NSString).appendingPathComponent(relative)
        let date = Date().addingTimeInterval(-days * 86_400)
        var paths = [root]
        if let e = FileManager.default.enumerator(atPath: root) { while let p = e.nextObject() as? String { paths.append((root as NSString).appendingPathComponent(p)) } }
        for p in paths { try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: p) }
    }

    func makeDir(_ relative: String) -> String {
        let path = (home as NSString).appendingPathComponent(relative)
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }
}

final class SafetyTests: SandboxedTestCase {
    func testProtectedLocationsAreRefused() {
        for path in ["/", "/System", "/System/Library/CoreServices", "/usr/bin/true", "/Applications", "/Library",
                     home!, "\(home!)/Library", "\(home!)/Documents", "\(home!)/Library/Caches",
                     "\(home!)/Library/Keychains/login.keychain-db", "\(home!)/Library/Mobile Documents/x",
                     "\(home!)/Library/Mail/V10/inbox", "\(home!)/.ssh/id_ed25519", "/Users/someone"] {
            XCTAssertThrowsError(try Safety.validateForDeletion(path), path)
        }
    }

    func testCacheChildrenAndExceptionsAreAllowed() {
        XCTAssertNoThrow(try Safety.validateForDeletion("\(home!)/Library/Caches/com.vendor.app"))
        XCTAssertNoThrow(try Safety.validateForDeletion("\(home!)/Library/Mail Downloads/attachment.pdf"))
        XCTAssertNoThrow(try Safety.validateForDeletion("\(home!)/Library/Application Support/MobileSync/Backup/abc"))
        XCTAssertNoThrow(try Safety.validateForDeletion("/Applications/Foo.app"))
    }

    func testRelativePathsAreRefused() {
        XCTAssertThrowsError(try Safety.validateForDeletion("Library/Caches/x"))
    }

    func testDotDotCannotEscape() {
        XCTAssertThrowsError(try Safety.validateForDeletion("\(home!)/Library/Caches/../Keychains/x"))
    }

    func testSymlinkedParentIntoProtectedTreeIsRefused() throws {
        let keychains = makeDir("Library/Keychains")
        _ = makeDir("Library/Caches")
        let link = "\(home!)/Library/Caches/sneaky"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: keychains)
        XCTAssertThrowsError(try Safety.validateForDeletion("\(link)/login.keychain-db"))
        // Removing the link itself is fine: that doesn't touch the destination.
        XCTAssertNoThrow(try Safety.validateForDeletion(link))
    }

    func testUserIgnoreList() {
        Safety.userIgnored = ["\(home!)/Library/Caches/com.keep.me"]
        XCTAssertThrowsError(try Safety.validateForDeletion("\(home!)/Library/Caches/com.keep.me/data"))
        XCTAssertNoThrow(try Safety.validateForDeletion("\(home!)/Library/Caches/com.other"))
    }
}

final class PathsTests: SandboxedTestCase {
    func testExpandAndAbbreviate() {
        XCTAssertEqual(Paths.expand("~/Library"), "\(home!)/Library")
        XCTAssertEqual(Paths.abbreviate("\(home!)/Library/Caches"), "~/Library/Caches")
    }

    func testGlobMatchesComponents() {
        makeFile("Library/Containers/a/Data/Library/Caches/x")
        makeFile("Library/Containers/b/Data/Library/Caches/y")
        makeFile("Library/Containers/.hidden/Data/Library/Caches/z")
        let found = Paths.glob("~/Library/Containers/*/Data/Library/Caches")
        XCTAssertEqual(found.map { Paths.abbreviate($0) },
                       ["~/Library/Containers/a/Data/Library/Caches", "~/Library/Containers/b/Data/Library/Caches"])
    }

    func testIsInside() {
        XCTAssertTrue(Paths.isInside("/a/b/c", "/a/b"))
        XCTAssertTrue(Paths.isInside("/a/b", "/a/b"))
        XCTAssertFalse(Paths.isInside("/a/bc", "/a/b"))
    }
}

final class ScannerTests: SandboxedTestCase {
    func scan(_ targets: [CleanupTarget]) -> ScanReport {
        Scanner(settings: Settings(), sudo: false, running: []).scan(targets)
    }

    func testSpecificTargetsClaimPathsBeforeGeneralOnes() {
        makeFile("Library/Caches/Google/Chrome/Default/blob", bytes: 5000)
        makeFile("Library/Caches/com.vendor.app/blob", bytes: 3000)
        let report = scan(CleanupCatalog.all)
        let chrome = report.results.first { $0.target.id == "chrome-caches" }
        let general = report.results.first { $0.target.id == "user-caches" }
        XCTAssertEqual(chrome?.items.map { Paths.abbreviate($0.path) }, ["~/Library/Caches/Google/Chrome"])
        XCTAssertEqual(general?.items.map { Paths.abbreviate($0.path) }, ["~/Library/Caches/com.vendor.app"])
    }

    func testMinimumAgeFiltersRecentItems() {
        makeFile("Library/Logs/DiagnosticReports/old.ips", age: 30)
        makeFile("Library/Logs/DiagnosticReports/new.ips", age: 0)
        let report = scan(CleanupCatalog.all.filter { $0.id == "user-crash-reports" })
        XCTAssertEqual(report.results.first?.items.map { ($0.path as NSString).lastPathComponent }, ["old.ips"])
    }

    func testExcludedNamesAreSkipped() {
        makeFile("Library/Caches/CloudKit/db")
        makeFile("Library/Caches/com.vendor.app/db")
        let report = scan(CleanupCatalog.all.filter { $0.id == "user-caches" })
        XCTAssertEqual(report.results.first?.items.map { ($0.path as NSString).lastPathComponent }, ["com.vendor.app"])
    }

    func testRunningAppMarksTargetSkipped() {
        makeFile("Library/Developer/Xcode/DerivedData/Proj/x")
        let target = CleanupCatalog.target("xcode-derived-data")!
        let report = Scanner(settings: Settings(), sudo: false, running: ["Xcode"]).scan([target])
        XCTAssertEqual(report.results.first?.skippedReason, "Quit Xcode first")
    }

    func testSystemTargetsNeedSudo() {
        let target = CleanupTarget(id: "t", title: "t", detail: "", category: .system, scope: .system,
                                   kind: .contents([makeDir("fake-system")]))
        makeFile("fake-system/x")
        let report = scan([target])
        XCTAssertEqual(report.results.first?.skippedReason, "Needs Sudo mode")
    }

    func testDisabledTargetsAreOmitted() {
        makeFile("Library/Caches/com.vendor.app/blob")
        var settings = Settings()
        settings.disabledTargets = ["user-caches"]
        let report = Scanner(settings: settings, sudo: false, running: []).scan(CleanupCatalog.all)
        XCTAssertNil(report.results.first { $0.target.id == "user-caches" })
    }

    func testFilesKindMatchesPatternsWithDepthLimit() {
        makeFile("Downloads/a.dmg", age: 30)
        makeFile("Downloads/sub/b.pkg", age: 30)
        makeFile("Downloads/sub/deeper/c.dmg", age: 30)
        makeFile("Downloads/notes.txt", age: 30)
        let report = scan([CleanupCatalog.target("download-installers")!])
        XCTAssertEqual(Set(report.results.first?.items.map { ($0.path as NSString).lastPathComponent } ?? []), ["a.dmg", "b.pkg"])
    }

    func testCatalogIDsAreUnique() {
        let ids = CleanupCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}

final class CleanerTests: SandboxedTestCase {
    func testDryRunRemovesNothing() {
        let path = makeFile("Library/Caches/com.vendor.app/blob")
        let report = Cleaner(settings: Settings(), sudo: false, runner: nil, dryRun: true)
            .remove([RemovalRequest(item: ScanItem(path: path, bytes: 1024), scope: .user, preferTrash: false)], reason: "test")
        XCTAssertEqual(report.removed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testDeletesUserItems() {
        let dir = (makeFile("Library/Caches/com.vendor.app/blob") as NSString).deletingLastPathComponent
        let report = Cleaner(settings: Settings(), sudo: false, runner: nil)
            .remove([RemovalRequest(item: ScanItem(path: dir, bytes: 1024), scope: .user, preferTrash: false)], reason: "test")
        XCTAssertEqual(report.freedBytes, 1024)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir))
    }

    func testProtectedPathsAreNeverRemoved() {
        let keychain = makeFile("Library/Keychains/login.keychain-db")
        let report = Cleaner(settings: Settings(), sudo: false, runner: nil)
            .remove([RemovalRequest(item: ScanItem(path: keychain, bytes: 1), scope: .user, preferTrash: false)], reason: "test")
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keychain))
    }

    func testSystemItemsWithoutSudoAreReportedNotRemoved() {
        let path = makeFile("fake-system/blob")
        let report = Cleaner(settings: Settings(), sudo: false, runner: nil)
            .remove([RemovalRequest(item: ScanItem(path: path, bytes: 1), scope: .system, preferTrash: false)], reason: "test")
        XCTAssertEqual(report.needsSudo.count, 1)
        XCTAssertTrue(report.removed.isEmpty)
    }

    func testSystemItemsWithSudoGoThroughOneQuotedScript() {
        let a = makeFile("fake-system/it's here/blob")
        let b = makeFile("fake-system/other/blob")
        let runner = RecordingRunner()
        let report = Cleaner(settings: Settings(), sudo: true, runner: runner).remove([
            RemovalRequest(item: ScanItem(path: a, bytes: 1), scope: .system, preferTrash: false),
            RemovalRequest(item: ScanItem(path: b, bytes: 1), scope: .system, preferTrash: false),
        ], reason: "test")
        XCTAssertEqual(runner.scripts.count, 1, "one authorization prompt per batch")
        let text = runner.scripts[0].text
        XCTAssertTrue(text.contains("'/bin/rm' '-rf' '--' '\(a.replacingOccurrences(of: "'", with: "'\\''"))'"))
        // RecordingRunner doesn't delete, so the items are still there and reported as failures.
        XCTAssertEqual(report.failures.count, 2)
    }
}

final class PrivilegedScriptTests: XCTestCase {
    func testQuotingNeutralizesShellMetacharacters() {
        var script = PrivilegedScript()
        script.remove("/tmp/x; rm -rf / #'$(whoami)`id`")
        XCTAssertEqual(script.lines, ["'/bin/rm' '-rf' '--' '/tmp/x; rm -rf / #'\\''$(whoami)`id`' || true"])
    }

    func testQuoteRoundTripsThroughShell() {
        let nasty = "a'b \"c\" $HOME `x` \\ ; |"
        let r = Shell.run("/bin/sh", ["-c", "printf %s \(Shell.quote(nasty))"])
        XCTAssertEqual(r.stdout, nasty)
    }
}

final class UninstallerTests: SandboxedTestCase {
    func app(_ name: String, _ id: String, embedded: [String] = []) -> InstalledApp {
        InstalledApp(path: "/Applications/\(name).app", name: name, bundleID: id, version: "1", bytes: 0, lastUsed: nil,
                     teamID: nil, embeddedBundleIDs: embedded, userRemovable: true, isAppleApp: false, isAppStore: false)
    }

    func testStrictMatchesOnlyExactIDsAndNames() {
        let m = Uninstaller.matcher(for: app("Rectangle", "com.knollsoft.Rectangle"), level: .strict)
        XCTAssertTrue(m("com.knollsoft.Rectangle.plist"))
        XCTAssertTrue(m("Rectangle"))
        XCTAssertTrue(m("ABCDE12345.com.knollsoft.Rectangle"))
        XCTAssertFalse(m("RectangleProStuff"))
        XCTAssertFalse(m("com.other.app"))
    }

    func testEnhancedMatchesJoinedComponentsAndVersionlessNames() {
        let m = Uninstaller.matcher(for: app("Bartender 6", "com.surteesstudios.Bartender"), level: .enhanced)
        XCTAssertTrue(m("Bartender"))
        XCTAssertTrue(m("com.surteesstudios.Bartender.plist"))
        XCTAssertFalse(m("Bar"))
    }

    func testBundleIDNamedFoldersMatch() {
        // Regression: deletingPathExtension would turn "com.knollsoft.Rectangle" into "com.knollsoft".
        let m = Uninstaller.matcher(for: app("Rectangle", "com.knollsoft.Rectangle"), level: .strict)
        XCTAssertTrue(m("/Users/x/Library/Application Support/com.knollsoft.Rectangle"))
        XCTAssertTrue(m("/Users/x/Library/Saved Application State/com.knollsoft.Rectangle.savedState"))
    }

    func testGenericNamesDontMatch() {
        let m = Uninstaller.matcher(for: app("Studio", "com.vendor.studio"), level: .deep)
        XCTAssertFalse(m("Studio Display Calibration"))
    }

    func testBaseBundleIDStripsHelperSuffixes() {
        XCTAssertEqual(Uninstaller.baseBundleID("com.vendor.App.helper"), "com.vendor.App")
        XCTAssertEqual(Uninstaller.baseBundleID("com.vendor.App.LoginItem.helper"), "com.vendor.App")
        XCTAssertEqual(Uninstaller.baseBundleID("com.vendor.helper"), "com.vendor.helper")
    }

    func testStripVersion() {
        XCTAssertEqual(Uninstaller.stripVersion("Bartender 6"), "Bartender")
        XCTAssertEqual(Uninstaller.stripVersion("Foo 2.1"), "Foo")
        XCTAssertEqual(Uninstaller.stripVersion("1Password 8"), "1Password")
    }

    func testLeftoversExcludeOtherInstalledApps() {
        makeFile("Library/Application Support/Notion/state")
        makeFile("Library/Application Support/Notion Calendar/state")
        makeFile("Library/Preferences/notion.id.plist")
        let notion = app("Notion", "notion.id")
        let calendar = app("Notion Calendar", "com.cron.electron")
        let found = Uninstaller.leftovers(for: notion, level: .enhanced, otherApps: [calendar])
            .map { ($0.path as NSString).lastPathComponent }
        XCTAssertTrue(found.contains("Notion"))
        XCTAssertTrue(found.contains("notion.id.plist"))
        XCTAssertFalse(found.contains("Notion Calendar"))
    }

    func testUserDataIsFlagged() {
        makeFile("Library/Application Support/com.vendor.App/db")
        makeFile("Library/Caches/com.vendor.App/c")
        let found = Uninstaller.leftovers(for: app("App", "com.vendor.App"))
        XCTAssertEqual(found.first { $0.kind == "Application Support" }?.isUserData, true)
        XCTAssertEqual(found.first { $0.kind == "Cache" }?.isUserData, false)
    }
}

final class CompleteUninstallTests: SandboxedTestCase {
    func app(at path: String, _ name: String, _ id: String) -> InstalledApp {
        InstalledApp(path: path, name: name, bundleID: id, version: "1", bytes: 0, lastUsed: nil, teamID: nil,
                     embeddedBundleIDs: [], userRemovable: true, isAppleApp: false, isAppStore: false)
    }

    func testCrashReportsAreMatchedByExecutableName() {
        let m = Uninstaller.crashReportMatcher(for: app(at: "/Applications/Zed.app", "Zed", "dev.zed.Zed"))
        XCTAssertTrue(m("Zed-2026-01-02-030405.ips"))
        XCTAssertTrue(m("zed_2026-01-02-030405_mac.diag"))
        XCTAssertFalse(m("Zedge-2026-01-02.ips"))
        XCTAssertFalse(m("Safari-2026-01-02.ips"))
    }

    func testCommandLineLinksIntoTheBundleAreFound() throws {
        let bundle = makeDir("Applications/Code.app/Contents/Resources/bin")
        FileManager.default.createFile(atPath: bundle + "/code", contents: Data())
        let appPath = (home as NSString).appendingPathComponent("Applications/Code.app")
        _ = makeDir("bin")
        try FileManager.default.createSymbolicLink(atPath: home + "/bin/code", withDestinationPath: bundle + "/code")
        try FileManager.default.createSymbolicLink(atPath: home + "/bin/other", withDestinationPath: "/usr/bin/true")
        XCTAssertEqual(Uninstaller.commandLineLinks(into: appPath), [home + "/bin/code"])
        let found = Uninstaller.leftovers(for: app(at: appPath, "Visual Studio Code", "com.microsoft.VSCode"))
        XCTAssertTrue(found.contains { $0.path == home + "/bin/code" && $0.kind == "Command-line Link" })
    }

    func testDotFoldersOnlyAtDeepLevel() {
        makeFile(".zoomus/config")
        makeFile(".unrelated/config")
        let zoom = app(at: "/Applications/zoom.us.app", "zoom.us", "us.zoom.xos")
        XCTAssertFalse(Uninstaller.leftovers(for: zoom, level: .enhanced).contains { $0.kind == "Dotfolder" })
        let deep = Uninstaller.leftovers(for: zoom, level: .deep).filter { $0.kind == "Dotfolder" }.map(\.path)
        XCTAssertEqual(deep, [home + "/.zoomus"])
    }

    func testPreferenceDomainsIncludeByHost() {
        let plain = makeFile("Library/Preferences/com.vendor.App.plist")
        let host = makeFile("Library/Preferences/ByHost/com.vendor.App.0A1B2C3D-0000-1111-2222-333344445555.plist")
        let leftovers = [plain, host].map { Leftover(path: $0, bytes: 1, kind: "Preferences", system: false, isUserData: false) }
        XCTAssertEqual(Uninstaller.preferenceDomains(in: leftovers), ["com.vendor.App", "host:com.vendor.App"])
    }

    func testProcessesInsideTheBundle() {
        let ps = """
          101   501 /Applications/Foo.app/Contents/MacOS/Foo -psn_0
          102   501 /Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper --type=gpu
          103     0 /Library/PrivilegedHelperTools/com.foo.helper
          104   501 /Applications/Foobar.app/Contents/MacOS/Foobar
        """
        let found = Uninstaller.parseProcesses(ps, inside: "/Applications/Foo.app")
        XCTAssertEqual(found.map(\.pid), [101, 102])
    }

    func testLaunchdLabelsAreMatchedByBundleID() {
        let list = "PID\tStatus\tLabel\n-\t0\tcom.vendor.App.helper\n42\t0\tcom.vendor.Apple\n-\t0\tcom.vendor.App\n"
        let labels = Uninstaller.loadedLabels(list)
        XCTAssertEqual(labels.filter { Uninstaller.ownsLabel($0, ids: ["com.vendor.App"]) }, ["com.vendor.App.helper", "com.vendor.App"])
    }

    func testCompleteRemovalNeverUsesTheTrash() {
        let a = app(at: "/Applications/Foo.app", "Foo", "com.foo")
        let leftovers = [Leftover(path: "/x/Application Support/Foo", bytes: 1, kind: "Application Support", system: false, isUserData: true)]
        XCTAssertTrue(Uninstaller.requests(app: a, leftovers: leftovers, sudo: false, complete: true).allSatisfy { !$0.preferTrash })
        XCTAssertTrue(Uninstaller.requests(app: a, leftovers: leftovers, sudo: false).allSatisfy { $0.preferTrash })
    }

    func testRemainingReportsSurvivors() {
        let appPath = makeDir("Applications/Foo.app/Contents")
            .replacingOccurrences(of: "/Contents", with: "")
        makeFile("Library/Caches/com.foo.Foo/cache.db")
        let foo = app(at: appPath, "Foo", "com.foo.Foo")
        let left = Uninstaller.remaining(after: foo, level: .enhanced)
        XCTAssertEqual(left.first?.kind, "Application")
        XCTAssertTrue(left.contains { $0.kind == "Cache" })
        try? FileManager.default.removeItem(atPath: appPath)
        try? FileManager.default.removeItem(atPath: home + "/Library/Caches/com.foo.Foo")
        XCTAssertTrue(Uninstaller.remaining(after: foo, level: .enhanced).isEmpty)
    }

    func testUninstallRemovesEverythingAndRunsRootTracesOnce() {
        let appPath = makeDir("Applications/Foo.app/Contents").replacingOccurrences(of: "/Contents", with: "")
        let cache = makeFile("Library/Caches/com.foo.Foo/cache.db")
        let data = makeFile("Library/Application Support/Foo/library.db")
        let foo = app(at: appPath, "Foo", "com.foo.Foo")
        let leftovers = Uninstaller.leftovers(for: foo)
        XCTAssertEqual(Set(leftovers.map(\.path)), [home + "/Library/Caches/com.foo.Foo", home + "/Library/Application Support/Foo"])
        let receipts = UninstallTrace(kind: .receipts, title: "Forget", detail: "", items: ["com.foo.pkg"], needsAdmin: true)
        let runner = RecordingRunner()
        let report = Uninstaller.uninstall(foo, leftovers: leftovers, traces: [receipts], complete: true,
                                           settings: Settings(), sudo: true, runner: runner)
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
        XCTAssertTrue(report.removed.allSatisfy { $0.method == .delete })
        for path in [appPath, cache, data] { XCTAssertFalse(Paths.lexists(path), path) }
        XCTAssertEqual(runner.scripts.count, 1)
        var expected = PrivilegedScript()
        expected.add("/usr/sbin/pkgutil", ["--forget", "com.foo.pkg"])
        XCTAssertEqual(runner.scripts[0], expected)
        XCTAssertTrue(Uninstaller.remaining(after: foo, level: .enhanced).isEmpty)
    }

    func testDockTilesAreMatchedByURL() {
        let entry: [String: Any] = ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Foo%20Bar.app/", "_CFURLStringType": 15]]]
        XCTAssertTrue(Uninstaller.dockEntry(entry, points: "/Applications/Foo Bar.app"))
        XCTAssertFalse(Uninstaller.dockEntry(entry, points: "/Applications/Foo.app"))
    }

    func testCompleteUninstallIsTheDefaultAndDecodesTolerantly() throws {
        XCTAssertTrue(Settings().uninstallCompletely)
        let old = try JSONDecoder.stable.decode(Settings.self, from: Data("{\"adminMode\": true}".utf8))
        XCTAssertTrue(old.uninstallCompletely)
    }
}

final class LegacyTests: SandboxedTestCase {
    func testOldFoldersMoveOverOnceAndNeverOverwrite() throws {
        makeFile("Library/Application Support/Burnish/settings.json", bytes: 10)
        Legacy.move("~/Library/Application Support/Burnish", to: "~/Library/Application Support/Root")
        XCTAssertTrue(Paths.lexists(home + "/Library/Application Support/Root/settings.json"))
        XCTAssertFalse(Paths.lexists(home + "/Library/Application Support/Burnish"))

        makeFile("Library/Logs/Burnish/old.log")
        makeFile("Library/Logs/Root/new.log")
        Legacy.move("~/Library/Logs/Burnish", to: "~/Library/Logs/Root")
        XCTAssertTrue(Paths.lexists(home + "/Library/Logs/Root/new.log"))
        XCTAssertFalse(Paths.lexists(home + "/Library/Logs/Root/old.log"))
    }
}

final class OrphanTests: SandboxedTestCase {
    func testFindsLeftoversOfUninstalledAppsOnly() {
        makeFile("Library/Application Support/com.gone.app/data", bytes: 2048)
        makeFile("Library/Application Support/com.installed.app/data")
        makeFile("Library/Preferences/com.installed.app.helper.plist")
        makeFile("Library/Preferences/com.apple.finder.plist")
        makeFile("Library/Application Support/Some Folder/data")
        let installed = InstalledApp(path: "/Applications/X.app", name: "X", bundleID: "com.installed.app", version: "1",
                                     bytes: 0, lastUsed: nil, teamID: nil, embeddedBundleIDs: [], userRemovable: true,
                                     isAppleApp: false, isAppStore: false)
        let orphans = Orphans.find(installed: [installed]).map { ($0.path as NSString).lastPathComponent }
        XCTAssertEqual(orphans, ["com.gone.app"])
    }

    func testStripTeamPrefix() {
        XCTAssertEqual(Orphans.stripTeamPrefix("ubf8t346g9.com.vendor.app"), "com.vendor.app")
        XCTAssertEqual(Orphans.stripTeamPrefix("group.com.vendor.app"), "com.vendor.app")
    }
}

final class ProjectPurgeTests: SandboxedTestCase {
    func testFindsArtifactsWithMarkersOnly() {
        makeFile("Projects/web/package.json", age: 30)
        makeFile("Projects/web/node_modules/lodash/index.js", bytes: 4096, age: 30)
        makeFile("Projects/notnode/node_modules/x.js", age: 30)          // no package.json → ignored
        makeFile("Projects/rs/Cargo.toml", age: 30)
        makeFile("Projects/rs/target/debug/bin", bytes: 8192, age: 30)
        makeFile("Projects/py/.venv/pyvenv.cfg", age: 30)
        makeFile("Projects/py/.venv/lib/site.py", age: 30)
        age("Projects", days: 30)
        let found = ProjectPurge(roots: ["~/Projects"], minAgeDays: 7).scan()
        XCTAssertEqual(Set(found.map { Paths.abbreviate($0.path) }),
                       ["~/Projects/web/node_modules", "~/Projects/rs/target", "~/Projects/py/.venv"])
        XCTAssertTrue(found.allSatisfy { !$0.recentlyActive })
    }

    func testRecentProjectsAreMarkedActive() {
        makeFile("Projects/web/package.json", age: 0)
        makeFile("Projects/web/node_modules/x.js", age: 0)
        let found = ProjectPurge(roots: ["~/Projects"], minAgeDays: 7).scan()
        XCTAssertEqual(found.first?.recentlyActive, true)
    }

    func testGitTrackedArtifactsAreSkipped() throws {
        guard Shell.which("git") != nil else { throw XCTSkip("git not installed") }
        makeFile("Projects/rb/Gemfile", age: 30)
        makeFile("Projects/rb/vendor/lib.rb", age: 30)
        let project = "\(home!)/Projects/rb"
        Shell.run(Shell.which("git")!, ["-C", project, "init", "-q"])
        Shell.run(Shell.which("git")!, ["-C", project, "add", "vendor/lib.rb"])
        let found = ProjectPurge(roots: ["~/Projects"], minAgeDays: 7).scan()
        XCTAssertTrue(found.isEmpty)
    }
}

final class SettingsTests: SandboxedTestCase {
    func testDecodesPartialFilesWithDefaults() throws {
        let json = #"{"adminMode": true, "ignorePaths": ["~/keep"]}"#
        let s = try JSONDecoder.stable.decode(Settings.self, from: Data(json.utf8))
        XCTAssertTrue(s.adminMode)
        XCTAssertEqual(s.ignorePaths, ["~/keep"])
        XCTAssertEqual(s.purgeMinAgeDays, 7)
        XCTAssertEqual(s.leftoverLevel, .enhanced)
    }

    func testSudoRequiresAdminAccount() {
        var s = Settings()
        s.adminMode = true
        var m = MachineInfo.current()
        m.isAdmin = false
        XCTAssertFalse(s.sudoEnabled(machine: m))
        m.isAdmin = true
        XCTAssertTrue(s.sudoEnabled(machine: m))
    }

    func testSharedSettingsMergeFromFleetFolder() throws {
        var s = Settings()
        s.fleetFolder = "~/fleet"
        s.save()
        try SharedSettings(ignorePaths: ["~/Shared/keep"], purgeRoots: ["~/Shared/code"]).save(to: Paths.expand("~/fleet"))
        let loaded = Settings.load()
        XCTAssertTrue(loaded.ignorePaths.contains("~/Shared/keep"))
        XCTAssertTrue(loaded.purgeRoots.contains("~/Shared/code"))
    }
}

final class FleetAndHistoryTests: SandboxedTestCase {
    func testPublishAndLoadRoundTrip() throws {
        var s = Settings()
        s.fleetFolder = "~/fleet"
        let snap = try Fleet.publish(settings: s, reclaimable: 42, health: nil)
        let loaded = Fleet.load(settings: s)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.machine.machineID, snap.machine.machineID)
        XCTAssertEqual(loaded.first?.reclaimableBytes, 42)
    }

    func testHistoryAppendsAndTotals() {
        var report = CleanReport()
        report.removed = [RemovedItem(path: "/x", bytes: 100, method: .delete), RemovedItem(path: "/y", bytes: 50, method: .trash)]
        History.append(HistoryEntry(action: "clean", detail: "a", report: report))
        History.append(HistoryEntry(action: "clean", detail: "b", report: report))
        XCTAssertEqual(History.load().count, 2)
        XCTAssertEqual(History.totalFreed, 300)
        XCTAssertEqual(History.load().first?.trashed, 1)
    }
}

final class MiscTests: XCTestCase {
    func testTweakValueMatching() {
        XCTAssertTrue(TweakValue.bool(true).matches("1"))
        XCTAssertTrue(TweakValue.bool(false).matches("0\n"))
        XCTAssertTrue(TweakValue.float(0.15).matches("0.15"))
        XCTAssertTrue(TweakValue.string("SCcf").matches("SCcf"))
        XCTAssertFalse(TweakValue.int(2).matches("1"))
    }

    func testTweakIDsUniqueAndPresetsValid() {
        XCTAssertEqual(Tweaks.all.count, Set(Tweaks.all.map(\.id)).count)
        for t in Tweaks.all { XCTAssertTrue(t.presets.isSubset(of: Set(Tweaks.presets)), t.id) }
    }

    func testSwapParsing() {
        XCTAssertEqual(Health.parseSize("1024.00M"), 1_073_741_824)
        XCTAssertEqual(Health.parseSize("2.00G"), 2 * 1_073_741_824)
    }

    func testHealthScorePenalizesFullDisk() {
        let disk = DiskStatus(totalBytes: 1_000, freeBytes: 20, availableBytes: 30, smartStatus: nil, localSnapshots: 0)
        let memory = MemoryStatus(totalBytes: 1, freePercent: 60, swapUsedBytes: 0)
        let security = SecurityPosture(sip: true, gatekeeper: true, fileVault: true, firewall: true, xprotectVersion: nil,
                                       fullDiskAccess: true)
        let (score, notes) = Health.computeScore(disk: disk, memory: memory, battery: nil, security: security,
                                                 thermal: "Nominal", cores: 8, load: 1)
        XCTAssertLessThanOrEqual(score, 65)
        XCTAssertFalse(notes.isEmpty)
    }

    func testFormatBytes() {
        XCTAssertEqual(Format.bytes(999), "999 B")
        XCTAssertEqual(Format.bytes(1_500_000), "1.5 MB")
        XCTAssertEqual(Format.bytes(250_000_000_000), "250 GB")
    }

    func testTouchIDScriptPreservesOtherLines() {
        let text = Tweaks.touchIDScript(enable: true).text
        XCTAssertFalse(text.contains("rm -f"))
        XCTAssertTrue(text.contains("pam_tid.so"))
    }
}
