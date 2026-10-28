import Foundation

public enum Format {
    /// Human-readable size using decimal units, matching Finder ("1.2 GB").
    public static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = Double(max(value, 0))
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        if i == 0 { return "\(Int(v)) B" }
        return v >= 100 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        let days = Int(seconds / 86_400)
        if days < 60 { return "\(days) d ago" }
        return "\(days / 30) mo ago"
    }

    public static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension JSONEncoder {
    /// Encoder used for every file Root writes: stable keys, ISO dates.
    public static var stable: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    public static var stable: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
