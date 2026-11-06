import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Walks the cleanup catalog and measures what each target would free.
public struct Scanner {
    public var settings: Settings
    /// Whether system-scope targets are actionable. They are still measured when false, so the UI
    /// can say "turn on Sudo to free 2.1 GB more".
    public var sudo: Bool
    public var running: Set<String>
    public var now: Date

    public init(settings: Settings, sudo: Bool, running: Set<String> = ProcessList.runningNames(), now: Date = Date()) {
        self.settings = settings
        self.sudo = sudo
        self.running = running
        self.now = now
    }

    public func scan(_ targets: [CleanupTarget] = CleanupCatalog.all,
                     progress: ((CleanupTarget) -> Void)? = nil) -> ScanReport {
        var claimed = ClaimSet()
        var results: [TargetResult] = []
        let fullDiskAccess = Scanner.fullDiskAccess()
        let containersReadable = !OSFeatures.containersProtected || fullDiskAccess
        for target in targets where !settings.disabledTargets.contains(target.id) {
            progress?(target)
            if let result = scanTarget(target, claimed: &claimed, containersReadable: containersReadable,
                                       promptingFoldersOK: fullDiskAccess) { results.append(result) }
        }
        return ScanReport(date: now, results: results, sudo: sudo)
    }

    /// Full Disk Access probe; replaceable in tests.
    nonisolated(unsafe) static var fullDiskAccess: () -> Bool = { Health.hasFullDiskAccess() }

    public static let needsFullDiskAccess = "Needs Full Disk Access: macOS 27 protects other apps' containers"

    public static let needsFolderAccess = "Needs Full Disk Access, so macOS doesn't stop to ask about this folder"

    func scanTarget(_ target: CleanupTarget, claimed: inout ClaimSet, containersReadable: Bool = true,
                    promptingFoldersOK: Bool = true) -> TargetResult? {
        var skipped: String?
        if target.scope == .system && !sudo { skipped = "Needs Sudo mode" }
        if !containersReadable && Scanner.touchesAppContainers(target) { skipped = Scanner.needsFullDiskAccess }
        // Without Full Disk Access, reading Downloads/Documents/Desktop pops a dialog mid-scan.
        // Skip instead (without touching the folder at all) and say why.
        if !promptingFoldersOK && Scanner.paths(of: target).contains(where: OSFeatures.isInPromptingFolder) {
            return TargetResult(target: target, items: [], skippedReason: Scanner.needsFolderAccess)
        }
        let blockers = target.skipWhileRunning.filter { running.contains($0) }
        if !blockers.isEmpty { skipped = "Quit \(blockers.joined(separator: ", ")) first" }

        let candidates: [String]
        var claims: [String] = []
        switch target.kind {
        case .contents(let dirs):
            let roots = dirs.flatMap(Paths.glob).filter(Paths.isDirectory)
            claims = roots
            candidates = roots.flatMap { root -> [String] in
                let children = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
                return children
                    .filter { name in !target.excludeNames.contains { fnmatch($0, name, 0) == 0 } }
                    .map { (root as NSString).appendingPathComponent($0) }
            }
        case .paths(let globs):
            candidates = globs.flatMap(Paths.glob)
            claims = candidates
        case .files(let root, let patterns, let maxDepth):
            candidates = Scanner.findFiles(in: Paths.expand(root), patterns: patterns, maxDepth: maxDepth)
            claims = candidates
        case .command(let tool, _, let estimate):
            guard Shell.which(tool) != nil else { return nil }
            candidates = estimate.flatMap(Paths.glob)
            claims = candidates
        }

        let fresh = candidates.filter { !claimed.overlaps($0) && Safety.isAllowed($0) }
        claimed.insert(claims)
        let cutoff = now.addingTimeInterval(-Double(target.minAgeDays) * 86_400)

        var measured = [ScanItem?](repeating: nil, count: fresh.count)
        measured.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: fresh.count) { i in
                let m = FileSizer.measure(fresh[i])
                if target.minAgeDays > 0, let newest = m.newest, newest > cutoff { return }
                base[i] = ScanItem(path: fresh[i], bytes: m.bytes, modified: m.newest, isDirectory: m.isDirectory)
            }
        }
        var items = measured.compactMap { $0 }.filter { $0.bytes > 0 }
        items.sort { $0.bytes > $1.bytes }

        if case .command = target.kind {
            // Command targets are always offered when the tool exists, even if we can't estimate.
            return TargetResult(target: target, items: items, skippedReason: skipped)
        }
        guard !items.isEmpty else { return nil }
        return TargetResult(target: target, items: items, skippedReason: skipped)
    }

    /// Depth-limited file search by name glob. Does not descend into packages' hidden dirs or symlinks.
    static func paths(of target: CleanupTarget) -> [String] {
        switch target.kind {
        case .contents(let dirs): return dirs
        case .paths(let globs): return globs
        case .files(let root, _, _): return [root]
        case .command(_, _, let estimate): return estimate
        }
    }

    static func touchesAppContainers(_ target: CleanupTarget) -> Bool {
        paths(of: target).contains { OSFeatures.isInsideAppContainer($0) }
    }

    public static func findFiles(in root: String, patterns: [String], maxDepth: Int) -> [String] {
        var found: [String] = []
        func walk(_ dir: String, depth: Int) {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in children {
                let path = (dir as NSString).appendingPathComponent(name)
                if Paths.isDirectory(path) {
                    if name.hasSuffix(".app") || name.hasPrefix(".") { continue }
                    if depth < maxDepth { walk(path, depth: depth + 1) }
                } else if patterns.contains(where: { fnmatch($0, name, 0) == 0 }) {
                    found.append(path)
                }
            }
        }
        walk(root, depth: 1)
        return found.sorted()
    }
}

/// Paths already attributed to a more specific target.
struct ClaimSet {
    private var paths: [String] = []

    mutating func insert(_ new: [String]) { paths.append(contentsOf: new.map(Paths.normalize)) }

    /// True if `path` equals, contains, or is contained by any claimed path.
    func overlaps(_ path: String) -> Bool {
        let p = Paths.normalize(path)
        return paths.contains { ClaimSet.within(p, $0) || ClaimSet.within($0, p) }
    }

    /// Prefix check on already-normalized paths.
    static func within(_ path: String, _ ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }
}
