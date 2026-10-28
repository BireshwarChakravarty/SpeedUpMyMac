import Foundation
import BurnishCore

/// Pearcleaner-style Sentinel: watches ~/.Trash and reports apps dropped into it, so Burnish can
/// offer to remove their leftovers. Needs Full Disk Access to read the Trash on recent macOS.
final class TrashSentinel: @unchecked Sendable {
    var onAppTrashed: ((String) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    private let queue = DispatchQueue(label: "io.burnish.sentinel")
    private let trash = Paths.expand("~/.Trash")

    func start() {
        guard source == nil else { return }
        let fd = open(trash, O_EVTONLY)
        guard fd >= 0 else { return }
        known = currentApps()
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
        src.setEventHandler { [weak self] in self?.check() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func currentApps() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: trash)) ?? []
        return Set(names.filter { $0.hasSuffix(".app") }.map { (trash as NSString).appendingPathComponent($0) })
    }

    private func check() {
        let now = currentApps()
        let added = now.subtracting(known)
        known = now
        for path in added { onAppTrashed?(path) }
    }
}
