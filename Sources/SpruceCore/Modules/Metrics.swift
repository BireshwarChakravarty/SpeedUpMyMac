import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(SQLite3)
import SQLite3
#endif

/// One reading of this Mac's vitals.
public struct MetricSample: Codable, Sendable, Equatable {
    public var time: Date
    /// CPU busy, 0–100 %, averaged since the previous sample.
    public var cpu: Double
    /// 1-minute load average.
    public var load: Double
    /// Memory in use, 0–100 %.
    public var memory: Double
    public var swapBytes: Int64
    public var diskFreeBytes: Int64
    /// Network throughput since the previous sample, bytes per second.
    public var netIn: Double
    public var netOut: Double

    public init(time: Date, cpu: Double, load: Double, memory: Double, swapBytes: Int64, diskFreeBytes: Int64,
                netIn: Double, netOut: Double) {
        self.time = time
        self.cpu = cpu
        self.load = load
        self.memory = memory
        self.swapBytes = swapBytes
        self.diskFreeBytes = diskFreeBytes
        self.netIn = netIn
        self.netOut = netOut
    }

    public func value(_ metric: Metric) -> Double {
        switch metric {
        case .cpu: return cpu
        case .load: return load
        case .memory: return memory
        case .swap: return Double(swapBytes)
        case .diskFree: return Double(diskFreeBytes)
        case .netIn: return netIn
        case .netOut: return netOut
        }
    }
}

/// The vitals Spruce records.
public enum Metric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, load, memory, swap, diskFree, netIn, netOut

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU usage"
        case .load: return "CPU load"
        case .memory: return "Memory"
        case .swap: return "Swap"
        case .diskFree: return "Disk free"
        case .netIn: return "Download"
        case .netOut: return "Upload"
        }
    }

    /// The value as a short reading: "31.2 %", "4.2", "12 GB", "16 KB/s".
    public func format(_ value: Double) -> String {
        switch self {
        case .cpu, .memory: return String(format: "%.1f %%", value)
        case .load: return String(format: "%.2f", value)
        case .swap, .diskFree: return Format.bytes(Int64(value))
        case .netIn, .netOut: return Format.bytes(Int64(value)) + "/s"
        }
    }

    var column: String {
        switch self {
        case .cpu: return "cpu"
        case .load: return "load"
        case .memory: return "memory"
        case .swap: return "swap"
        case .diskFree: return "disk_free"
        case .netIn: return "net_in"
        case .netOut: return "net_out"
        }
    }
}

/// A point on a history chart: the average and the peak of the samples in one time bucket.
public struct MetricPoint: Sendable, Equatable, Identifiable {
    public var id: Date { time }
    public var time: Date
    public var average: Double
    public var peak: Double

    public init(time: Date, average: Double, peak: Double) {
        self.time = time
        self.average = average
        self.peak = peak
    }
}

/// Reads CPU, load, memory, swap, disk and network. CPU and network are rates, so each reading
/// compares against the previous one (the first reading reports zero for both).
public final class MetricSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: (busy: UInt64, total: UInt64)?
    private var previousNet: (bytesIn: [String: UInt32], bytesOut: [String: UInt32], time: Date)?

    public init() {}

    public func sample(now: Date = Date()) -> MetricSample {
        lock.lock(); defer { lock.unlock() }
        let memory = Health.memoryStatus()
        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        let network = networkRates(now: now)
        return MetricSample(time: now, cpu: cpuPercent(), load: loads[0],
                            memory: Double(100 - (memory.freePercent ?? 100)), swapBytes: memory.swapUsedBytes,
                            diskFreeBytes: Health.diskStatus().availableBytes,
                            netIn: network.bytesIn, netOut: network.bytesOut)
    }

    private func cpuPercent() -> Double {
        #if canImport(Darwin)
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice, total = busy + idle
        defer { previousTicks = (busy, total) }
        guard let previous = previousTicks, total > previous.total else { return 0 }
        return min(100, max(0, Double(busy &- previous.busy) / Double(total - previous.total) * 100))
        #else
        return 0
        #endif
    }

    /// Bytes per second in and out across all non-loopback interfaces. Counters are 32-bit and wrap,
    /// so deltas use wrapping subtraction per interface.
    private func networkRates(now: Date) -> (bytesIn: Double, bytesOut: Double) {
        let current = Self.interfaceCounters()
        defer { previousNet = (current.bytesIn, current.bytesOut, now) }
        guard let previous = previousNet else { return (0, 0) }
        let seconds = now.timeIntervalSince(previous.time)
        guard seconds > 0 else { return (0, 0) }
        func rate(_ now: [String: UInt32], _ before: [String: UInt32]) -> Double {
            var total: UInt64 = 0
            for (name, value) in now { if let old = before[name] { total += UInt64(value &- old) } }
            return Double(total) / seconds
        }
        return (rate(current.bytesIn, previous.bytesIn), rate(current.bytesOut, previous.bytesOut))
    }

    static func interfaceCounters() -> (bytesIn: [String: UInt32], bytesOut: [String: UInt32]) {
        var bytesIn: [String: UInt32] = [:], bytesOut: [String: UInt32] = [:]
        #if os(macOS)
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return ([:], [:]) }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.pointee.ifa_data else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            if name.hasPrefix("lo") { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            bytesIn[name] = stats.ifi_ibytes
            bytesOut[name] = stats.ifi_obytes
        }
        #endif
        return (bytesIn, bytesOut)
    }
}

/// Months of samples in a small local database (~/Library/Application Support/Spruce/metrics.sqlite),
/// read back as charts. Falls back to memory where SQLite isn't available (Linux CI).
public final class MetricStore: @unchecked Sendable {
    public static let defaultPath = (Paths.support as NSString).appendingPathComponent("metrics.sqlite")

    private let queue = DispatchQueue(label: "io.spruceapp.metrics")
    #if canImport(SQLite3)
    private var db: OpaquePointer?
    #endif
    private var memory: [MetricSample] = []

    public init(path: String = MetricStore.defaultPath) {
        #if canImport(SQLite3)
        if sqlite3_open(path, &db) == SQLITE_OK {
            exec("PRAGMA journal_mode=WAL")
            exec("""
            CREATE TABLE IF NOT EXISTS samples (
              ts REAL PRIMARY KEY, cpu REAL, load REAL, memory REAL, swap INTEGER,
              disk_free INTEGER, net_in REAL, net_out REAL)
            """)
        } else {
            db = nil
        }
        #endif
    }

    deinit {
        #if canImport(SQLite3)
        if let db { sqlite3_close(db) }
        #endif
    }

    public func insert(_ sample: MetricSample) {
        queue.sync {
            #if canImport(SQLite3)
            if let db {
                var statement: OpaquePointer?
                let sql = "INSERT OR REPLACE INTO samples VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_double(statement, 1, sample.time.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, sample.cpu)
                sqlite3_bind_double(statement, 3, sample.load)
                sqlite3_bind_double(statement, 4, sample.memory)
                sqlite3_bind_int64(statement, 5, sample.swapBytes)
                sqlite3_bind_int64(statement, 6, sample.diskFreeBytes)
                sqlite3_bind_double(statement, 7, sample.netIn)
                sqlite3_bind_double(statement, 8, sample.netOut)
                sqlite3_step(statement)
                return
            }
            #endif
            memory.append(sample)
        }
    }

    /// Up to about `points` buckets between `from` and `to`, each with the average and the peak.
    public func series(_ metric: Metric, from: Date, to: Date = Date(), points: Int = 240) -> [MetricPoint] {
        let span = max(1, to.timeIntervalSince(from))
        let bucket = max(1, span / Double(max(points, 1)))
        return queue.sync {
            #if canImport(SQLite3)
            if let db {
                var statement: OpaquePointer?
                let sql = """
                SELECT CAST(ts / ?1 AS INTEGER) AS b, AVG(\(metric.column)), MAX(\(metric.column))
                FROM samples WHERE ts >= ?2 AND ts <= ?3 GROUP BY b ORDER BY b
                """
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_double(statement, 1, bucket)
                sqlite3_bind_double(statement, 2, from.timeIntervalSince1970)
                sqlite3_bind_double(statement, 3, to.timeIntervalSince1970)
                var out: [MetricPoint] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let start = Double(sqlite3_column_int64(statement, 0)) * bucket
                    out.append(MetricPoint(time: Date(timeIntervalSince1970: start), average: sqlite3_column_double(statement, 1),
                                           peak: sqlite3_column_double(statement, 2)))
                }
                return out
            }
            #endif
            return Self.bucketed(memory.filter { $0.time >= from && $0.time <= to }, metric, bucket: bucket)
        }
    }

    /// How many samples fall in the range.
    public func count(from: Date, to: Date = Date()) -> Int {
        queue.sync {
            #if canImport(SQLite3)
            if let db {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM samples WHERE ts >= ? AND ts <= ?", -1, &statement, nil) == SQLITE_OK else { return 0 }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_double(statement, 1, from.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, to.timeIntervalSince1970)
                return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
            }
            #endif
            return memory.filter { $0.time >= from && $0.time <= to }.count
        }
    }

    /// Deletes samples older than `date`.
    public func prune(olderThan date: Date) {
        queue.sync {
            #if canImport(SQLite3)
            if db != nil {
                exec("DELETE FROM samples WHERE ts < \(date.timeIntervalSince1970)")
                return
            }
            #endif
            memory.removeAll { $0.time < date }
        }
    }

    static func bucketed(_ samples: [MetricSample], _ metric: Metric, bucket: Double) -> [MetricPoint] {
        let groups = Dictionary(grouping: samples) { Int($0.time.timeIntervalSince1970 / bucket) }
        return groups.keys.sorted().map { key in
            let values = groups[key]!.map { $0.value(metric) }
            return MetricPoint(time: Date(timeIntervalSince1970: Double(key) * bucket),
                               average: values.reduce(0, +) / Double(values.count), peak: values.max() ?? 0)
        }
    }

    #if canImport(SQLite3)
    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
    #endif
}

/// When the disk will be full at the rate free space has been shrinking: a least-squares line
/// through daily points. nil when free space isn't shrinking or there's too little history.
public enum DiskForecast {
    public static func daysUntilFull(_ points: [MetricPoint]) -> Double? {
        guard points.count >= 3, let first = points.first, let last = points.last,
              last.time.timeIntervalSince(first.time) >= 2 * 86_400 else { return nil }
        let xs = points.map { $0.time.timeIntervalSince(first.time) / 86_400 }
        let ys = points.map(\.average)
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx   // bytes per day
        guard slope < 0 else { return nil }
        return last.average / -slope
    }
}
