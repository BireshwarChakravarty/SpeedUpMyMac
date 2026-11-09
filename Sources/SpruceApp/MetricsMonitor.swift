import Foundation
import Observation
import SpruceCore

/// Samples this Mac's vitals while Spruce runs: every 2 seconds while a live view is on screen,
/// every 30 seconds otherwise. One sample every 30 seconds goes into the local history, which
/// keeps 90 days.
@MainActor
@Observable
final class MetricsMonitor {
    static let shared = MetricsMonitor()

    static let persistInterval: TimeInterval = 30
    static let retentionDays: Double = 90
    static let liveCapacity = 180

    @ObservationIgnored let store = MetricStore()
    @ObservationIgnored private let sampler = MetricSampler()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastPersist = Date.distantPast
    @ObservationIgnored private var lastPrune = Date.distantPast

    /// Recent samples, oldest first.
    private(set) var live: [MetricSample] = []
    var latest: MetricSample? { live.last }
    /// How many views want fast sampling right now.
    private(set) var watchers = 0

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                // Sleep in short steps so a newly opened live view speeds sampling up at once.
                let started = Date()
                while !Task.isCancelled {
                    let interval: TimeInterval = self.watchers > 0 ? (AppModel.tourFolder != nil ? 1 : 2) : Self.persistInterval
                    if Date().timeIntervalSince(started) >= interval { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    func watch() {
        watchers += 1
        if watchers == 1 { Task { await tick() } }
    }

    func unwatch() { watchers = max(0, watchers - 1) }

    private func tick() async {
        let sampler = self.sampler, store = self.store
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.retentionDays * 86_400)
        let persist = now.timeIntervalSince(lastPersist) >= Self.persistInterval - 1
        let prune = now.timeIntervalSince(lastPrune) >= 3600
        if persist { lastPersist = now }
        if prune { lastPrune = now }
        let sample = await Task.detached(priority: .utility) { () -> MetricSample in
            let sample = sampler.sample(now: now)
            if persist { store.insert(sample) }
            if prune { store.prune(olderThan: cutoff) }
            return sample
        }.value
        live.append(sample)
        if live.count > Self.liveCapacity { live.removeFirst(live.count - Self.liveCapacity) }
    }

    func series(_ metric: Metric, over seconds: TimeInterval, points: Int = 240) async -> [MetricPoint] {
        let store = self.store
        let now = Date()
        return await Task.detached(priority: .userInitiated) {
            store.series(metric, from: now.addingTimeInterval(-seconds), to: now, points: points)
        }.value
    }

    func sampleCount(over seconds: TimeInterval) async -> Int {
        let store = self.store
        let now = Date()
        return await Task.detached { store.count(from: now.addingTimeInterval(-seconds), to: now) }.value
    }
}
