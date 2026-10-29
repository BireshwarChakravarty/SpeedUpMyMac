import Foundation

/// A rebuildable build artifact inside one of your projects.
public struct ProjectArtifact: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var project: String
    public var kind: String
    public var bytes: Int64
    public var lastActivity: Date?
    /// Recently active projects are listed but not pre-selected.
    public var recentlyActive: Bool
}

/// Finds node_modules, target, .build, Pods, venvs… (Mole purge / npkill / DevCleaner).
public struct ProjectPurge {
    /// Directory name → marker files that must sit next to it (any one). Empty markers = name alone is enough.
    public static let rules: [(name: String, markers: [String], kind: String)] = [
        ("node_modules", ["package.json"], "Node modules"),
        ("target", ["Cargo.toml", "pom.xml", "build.sbt"], "Rust/JVM build"),
        (".build", ["Package.swift"], "SwiftPM build"),
        ("Pods", ["Podfile"], "CocoaPods"),
        ("DerivedData", ["*.xcodeproj", "*.xcworkspace"], "Xcode build"),
        (".venv", ["pyvenv.cfg@self"], "Python venv"),
        ("venv", ["pyvenv.cfg@self"], "Python venv"),
        ("__pycache__", [], "Python bytecode"),
        (".pytest_cache", [], "pytest cache"),
        (".mypy_cache", [], "mypy cache"),
        (".gradle", ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], "Gradle cache"),
        ("build", ["build.gradle", "build.gradle.kts", "CMakeLists.txt", "pubspec.yaml"], "Build output"),
        (".next", ["package.json"], "Next.js build"),
        (".nuxt", ["package.json"], "Nuxt build"),
        (".turbo", ["package.json", "turbo.json"], "Turborepo cache"),
        (".parcel-cache", ["package.json"], "Parcel cache"),
        (".svelte-kit", ["package.json"], "SvelteKit build"),
        (".angular", ["angular.json"], "Angular cache"),
        (".dart_tool", ["pubspec.yaml"], "Dart tool cache"),
        ("vendor", ["Gemfile", "composer.json"], "Vendored deps"),
        ("zig-cache", ["build.zig"], "Zig cache"),
        (".zig-cache", ["build.zig"], "Zig cache"),
        ("_build", ["mix.exs"], "Elixir build"),
        ("deps", ["mix.exs"], "Elixir deps"),
    ]

    public var roots: [String]
    public var minAgeDays: Int
    public var maxDepth: Int
    public var now: Date

    public init(roots: [String], minAgeDays: Int = 7, maxDepth: Int = 6, now: Date = Date()) {
        self.roots = roots.map(Paths.expand).filter(Paths.isDirectory)
        self.minAgeDays = minAgeDays
        self.maxDepth = maxDepth
        self.now = now
    }

    public func scan(progress: ((String) -> Void)? = nil) -> [ProjectArtifact] {
        var hits: [(path: String, project: String, kind: String)] = []
        var seen = Set<String>()
        let blocked = Set(ProjectPurge.rootsNeedingAccess(roots))
        for root in roots where !blocked.contains(root) { walk(root, depth: 0, hits: &hits, seen: &seen, progress: progress) }

        var artifacts = [ProjectArtifact?](repeating: nil, count: hits.count)
        let cutoff = now.addingTimeInterval(-Double(minAgeDays) * 86_400)
        artifacts.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: hits.count) { i in
                let hit = hits[i]
                if ProjectPurge.isGitTracked(hit.path, project: hit.project) { return }
                let measured = FileSizer.measure(hit.path)
                let size = measured.bytes
                guard size > 0 else { return }
                // Fall back to the artifact's own newest file when the project has nothing else in it.
                let activity = ProjectPurge.projectActivity(hit.project, excluding: hit.path) ?? measured.newest
                base[i] = ProjectArtifact(path: hit.path, project: hit.project, kind: hit.kind, bytes: size,
                                          lastActivity: activity, recentlyActive: (activity ?? now) > cutoff)
            }
        }
        return artifacts.compactMap { $0 }.sorted { $0.bytes > $1.bytes }
    }

    /// Project roots inside Desktop/Documents/Downloads, which macOS would stop and ask about
    /// without Full Disk Access. They're skipped (not touched) until Root has it.
    public static func rootsNeedingAccess(_ roots: [String]) -> [String] {
        guard roots.contains(where: OSFeatures.isInPromptingFolder), !Scanner.fullDiskAccess() else { return [] }
        return roots.filter(OSFeatures.isInPromptingFolder)
    }

    private func walk(_ dir: String, depth: Int, hits: inout [(path: String, project: String, kind: String)],
                      seen: inout Set<String>, progress: ((String) -> Void)?) {
        guard depth <= maxDepth, let children = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let childSet = Set(children)
        for name in children {
            let path = (dir as NSString).appendingPathComponent(name)
            guard Paths.isDirectory(path) else { continue }
            if let rule = ProjectPurge.rules.first(where: { $0.name == name }),
               ProjectPurge.markersPresent(rule.markers, siblings: childSet, artifact: path) {
                let key = Paths.normalize(path)
                if !seen.contains(key) {
                    seen.insert(key)
                    hits.append((path, dir, rule.kind))
                }
                continue // never descend into an artifact
            }
            // Skip hidden dirs (.git etc.), app bundles and other heavy non-project trees.
            if name.hasPrefix(".") || name.hasSuffix(".app") || name == "Library" || name.hasSuffix(".photoslibrary") { continue }
            if depth == 0 { progress?(path) }
            walk(path, depth: depth + 1, hits: &hits, seen: &seen, progress: progress)
        }
    }

    static func markersPresent(_ markers: [String], siblings: Set<String>, artifact: String) -> Bool {
        if markers.isEmpty { return true }
        for marker in markers {
            if marker.hasSuffix("@self") {
                let file = String(marker.dropLast(5))
                if FileManager.default.fileExists(atPath: (artifact as NSString).appendingPathComponent(file)) { return true }
            } else if marker.contains("*") {
                if siblings.contains(where: { Paths.matches($0, marker) }) { return true }
            } else if siblings.contains(marker) {
                return true
            }
        }
        return false
    }

    /// Never purge something checked into git (e.g. a committed `vendor/` or `build/`).
    static func isGitTracked(_ artifact: String, project: String) -> Bool {
        guard let git = Shell.which("git") else { return false }
        let name = (artifact as NSString).lastPathComponent
        let r = Shell.run(git, ["-C", project, "ls-files", "--", name], timeout: 10)
        return r.succeeded && !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Newest modification among the project's top-level entries (ignoring the artifact itself).
    static func projectActivity(_ project: String, excluding artifact: String) -> Date? {
        var newest: Date?
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: project)) ?? [] where name != (artifact as NSString).lastPathComponent {
            let path = (project as NSString).appendingPathComponent(name)
            if let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, m > (newest ?? .distantPast) { newest = m }
        }
        return newest
    }
}
