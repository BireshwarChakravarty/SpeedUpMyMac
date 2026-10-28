import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A directory tree with sizes (DaisyDisk / GrandPerspective). Small children are folded into "other".
public final class DiskNode: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let name: String
    public let path: String
    public var bytes: Int64
    public var isDirectory: Bool
    public var children: [DiskNode]
    public var fileCount: Int

    init(name: String, path: String, bytes: Int64, isDirectory: Bool, children: [DiskNode] = [], fileCount: Int = 1) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.children = children
        self.fileCount = fileCount
    }

    /// Synthetic "other" nodes have no real path and can't be removed.
    public var isAggregate: Bool { path.isEmpty }
}

public struct LargeFile: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var bytes: Int64
    public var modified: Date?
    public var accessed: Date?
}

public enum SpaceLens {
    /// Scans `root` into a tree `depth` levels deep, measuring everything below concurrently.
    public static func scan(_ root: String, depth: Int = 4, keepChildren: Int = 40,
                            progress: ((String) -> Void)? = nil) -> DiskNode {
        let path = Paths.normalize(root)
        return build(path, name: (path as NSString).lastPathComponent, depth: depth, keep: keepChildren, progress: progress)
    }

    private static func build(_ path: String, name: String, depth: Int, keep: Int, progress: ((String) -> Void)?) -> DiskNode {
        // App bundles and other leaves are measured whole.
        guard Paths.isDirectory(path), !path.hasSuffix(".app") else {
            let m = FileSizer.measure(path)
            return DiskNode(name: name, path: path, bytes: m.bytes, isDirectory: m.isDirectory, fileCount: m.fileCount)
        }
        if depth == 0 {
            let m = FileSizer.measure(path)
            return DiskNode(name: name, path: path, bytes: m.bytes, isDirectory: true, fileCount: m.fileCount)
        }
        progress?(path)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        var children = [DiskNode?](repeating: nil, count: names.count)
        children.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: names.count) { i in
                let child = (path as NSString).appendingPathComponent(names[i])
                if Paths.isSymlink(child) { return }
                base[i] = build(child, name: names[i], depth: depth - 1, keep: keep, progress: nil)
            }
        }
        var list = children.compactMap { $0 }.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        let total = list.reduce(0) { $0 + $1.bytes }
        let files = list.reduce(0) { $0 + $1.fileCount }
        if list.count > keep {
            let rest = list[keep...]
            let other = DiskNode(name: "\(rest.count) smaller items", path: "", bytes: rest.reduce(0) { $0 + $1.bytes },
                                 isDirectory: false, fileCount: rest.reduce(0) { $0 + $1.fileCount })
            list = Array(list[..<keep]) + [other]
        }
        return DiskNode(name: name, path: path, bytes: total, isDirectory: true, children: list, fileCount: files)
    }

    /// Big files, optionally only those not opened for `olderThanDays`. Skips app bundles and Photos libraries.
    public static func largeFiles(in root: String, minBytes: Int64, olderThanDays: Int? = nil, limit: Int = 300) -> [LargeFile] {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey,
                                      .contentModificationDateKey, .contentAccessDateKey, .isPackageKey]
        let cutoff = olderThanDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        var found: [LargeFile] = []
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: Paths.expand(root)), includingPropertiesForKeys: keys,
                                                     options: [], errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                let name = url.lastPathComponent
                if v.isPackage == true || name == ".Trash" || name == "Library" && url.deletingLastPathComponent().path == Paths.home {
                    e.skipDescendants()
                }
                continue
            }
            let size = FileSizer.allocated(v)
            guard size >= minBytes else { continue }
            if let cutoff {
                let last = max(v.contentAccessDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
                guard last < cutoff else { continue }
            }
            found.append(LargeFile(path: url.path, bytes: size, modified: v.contentModificationDate, accessed: v.contentAccessDate))
        }
        return Array(found.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}

public struct DuplicateGroup: Codable, Identifiable, Sendable {
    public var id: String { hash }
    public var hash: String
    public var bytesEach: Int64
    public var paths: [String]
    /// Space freed by keeping one copy.
    public var reclaimable: Int64 { bytesEach * Int64(max(paths.count - 1, 0)) }
}

/// Duplicate finder: size buckets → first/last 64 KB fingerprint → full SHA-256 (Gemini / dupeGuru approach).
public enum Duplicates {
    public static func find(in root: String, minBytes: Int64 = 1_000_000) -> [DuplicateGroup] {
        var bySize: [Int64: [String]] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isPackageKey, .isDirectoryKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: Paths.expand(root)), includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if v.isPackage == true || url.lastPathComponent == "Library" { e.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true, let size = v.fileSize, Int64(size) >= minBytes else { continue }
            bySize[Int64(size), default: []].append(url.path)
        }
        var groups: [DuplicateGroup] = []
        for (size, paths) in bySize where paths.count > 1 {
            let byFingerprint = Dictionary(grouping: paths) { fingerprint($0, size: size) ?? UUID().uuidString }
            for (_, candidates) in byFingerprint where candidates.count > 1 {
                let byHash = Dictionary(grouping: candidates) { fullHash($0) ?? UUID().uuidString }
                for (hash, same) in byHash where same.count > 1 {
                    groups.append(DuplicateGroup(hash: hash, bytesEach: size, paths: same.sorted()))
                }
            }
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    static func fingerprint(_ path: String, size: Int64) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let chunk = 65_536
        var data = h.readData(ofLength: chunk)
        if size > Int64(chunk * 2) {
            h.seek(toFileOffset: UInt64(size) - UInt64(chunk))
            data.append(h.readData(ofLength: chunk))
        }
        return digest(data)
    }

    static func fullHash(_ path: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        #if canImport(CryptoKit)
        var hasher = SHA256()
        while true {
            let block = h.readData(ofLength: 1 << 20)
            if block.isEmpty { break }
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        var hash: UInt64 = 0xcbf29ce484222325
        while true {
            let block = h.readData(ofLength: 1 << 20)
            if block.isEmpty { break }
            for byte in block { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        }
        return String(hash, radix: 16)
        #endif
    }

    static func digest(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
        #endif
    }
}
