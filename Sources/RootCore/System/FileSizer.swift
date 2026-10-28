import Foundation

/// Measures on-disk (allocated) size and the newest modification time under a path.
public enum FileSizer {
    public struct Measurement: Sendable {
        public var bytes: Int64
        /// Newest modification date of the path or anything inside it.
        public var newest: Date?
        public var isDirectory: Bool
        public var fileCount: Int
    }

    static let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
                                         .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

    /// Never follows symlinks; unreadable subtrees are skipped rather than failing the whole measurement.
    public static func measure(_ path: String) -> Measurement {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: Set(keys))
        let isLink = values?.isSymbolicLink ?? Paths.isSymlink(path)
        let isDir = (values?.isDirectory ?? false) && !isLink
        var newest = values?.contentModificationDate
        if !isDir {
            return Measurement(bytes: allocated(values), newest: newest, isDirectory: false, fileCount: 1)
        }
        var total: Int64 = 0
        var count = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                           errorHandler: { _, _ in true }) {
            for case let child as URL in enumerator {
                guard let v = try? child.resourceValues(forKeys: Set(keys)) else { continue }
                if let m = v.contentModificationDate, m > (newest ?? .distantPast) { newest = m }
                if v.isDirectory == true && v.isSymbolicLink != true { continue }
                total += allocated(v)
                count += 1
            }
        }
        return Measurement(bytes: total, newest: newest, isDirectory: true, fileCount: count)
    }

    static func allocated(_ v: URLResourceValues?) -> Int64 {
        guard let v else { return 0 }
        #if os(Linux)
        // corelibs-foundation over-reports allocated sizes; logical size is close enough for tests/CI.
        return Int64(v.fileSize ?? 0)
        #else
        if let t = v.totalFileAllocatedSize { return Int64(t) }
        if let a = v.fileAllocatedSize { return Int64(a) }
        return Int64(v.fileSize ?? 0)
        #endif
    }

    /// Total size of several paths, measured concurrently.
    public static func total(_ paths: [String]) -> Int64 {
        var sizes = [Int64](repeating: 0, count: paths.count)
        sizes.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: paths.count) { i in base[i] = measure(paths[i]).bytes }
        }
        return sizes.reduce(0, +)
    }
}

/// Names of running processes, for "quit Chrome first" style checks.
public enum ProcessList {
    public static func runningNames() -> Set<String> {
        #if os(macOS)
        let r = Shell.run("/bin/ps", ["-axco", "comm="])
        #else
        let r = Shell.run("/bin/ps", ["-axo", "comm="])
        #endif
        return Set(r.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
