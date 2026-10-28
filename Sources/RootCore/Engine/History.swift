import Foundation

/// One line in the operation log (~/Library/Application Support/Root/history.jsonl).
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var action: String
    public var detail: String
    public var bytes: Int64
    public var itemCount: Int
    public var trashed: Int
    public var deleted: Int
    public var asRoot: Int
    public var errors: [String]
    /// First 500 paths, so you can always see what went.
    public var paths: [String]
    public var machine: String

    public init(action: String, detail: String, report: CleanReport) {
        self.action = action
        self.detail = detail
        bytes = report.freedBytes
        itemCount = report.removed.count
        trashed = report.removed.filter { $0.method == .trash }.count
        deleted = report.removed.filter { $0.method == .delete }.count
        asRoot = report.removed.filter { $0.method == .root }.count
        errors = Array(report.failures.map { "\($0.path): \($0.reason)" }.prefix(100))
        paths = Array(report.removed.map(\.path).prefix(500))
        machine = MachineInfo.computerName()
    }

    public init(action: String, detail: String) {
        self.action = action
        self.detail = detail
        bytes = 0; itemCount = 0; trashed = 0; deleted = 0; asRoot = 0
        errors = []; paths = []
        machine = MachineInfo.computerName()
    }
}

public enum History {
    public static var fileURL: URL { URL(fileURLWithPath: Paths.support).appendingPathComponent("history.jsonl") }

    public static func append(_ entry: HistoryEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func load() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder.stable
        return text.split(separator: "\n").compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0.utf8)) }
            .sorted { $0.date > $1.date }
    }

    public static var totalFreed: Int64 { load().reduce(0) { $0 + $1.bytes } }
    public static var lastClean: Date? { load().first(where: { $0.bytes > 0 })?.date }
}
