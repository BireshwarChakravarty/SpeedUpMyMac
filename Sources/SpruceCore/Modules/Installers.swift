import Foundation

/// A disk image or installer package left behind after installing something.
public struct InstallerFile: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case diskImage = "Disk image"
        case package = "Installer package"
        case xcodeArchive = "Xcode archive"
        case isoImage = "ISO image"
    }

    public var id: String { path }
    public var path: String
    public var bytes: Int64
    public var modified: Date?
    public var kind: Kind
    /// The installed app this looks like it installed ("Zoom.pkg" → "zoom.us"), if any.
    public var installedApp: String?
    /// A disk image that's mounted right now; it can't be removed until it's ejected.
    public var mounted: Bool

    public init(path: String, bytes: Int64, modified: Date?, kind: Kind, installedApp: String? = nil, mounted: Bool = false) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
        self.kind = kind
        self.installedApp = installedApp
        self.mounted = mounted
    }

    public var name: String { (path as NSString).lastPathComponent }

    public func ageDays(now: Date = Date()) -> Int {
        guard let modified else { return 0 }
        return max(0, Int(now.timeIntervalSince(modified) / 86_400))
    }

    /// Pre-selected: its app is already installed, or it's been sitting for a week. ISO images
    /// (often a VM's operating system) and mounted images never are.
    public func suggested(now: Date = Date()) -> Bool {
        guard !mounted, kind != .isoImage else { return false }
        return installedApp != nil || ageDays(now: now) >= 7
    }
}

/// Finds installers you've already used: .dmg, .pkg, .mpkg, .xip and .iso files in Downloads,
/// Desktop, Documents, Mail downloads and the shared folder.
public enum InstallerSweep {
    static let kinds: [String: InstallerFile.Kind] = [
        "dmg": .diskImage, "sparseimage": .diskImage, "pkg": .package, "mpkg": .package,
        "xip": .xcodeArchive, "iso": .isoImage,
    ]

    public static var defaultRoots: [String] {
        ["~/Downloads", "~/Desktop", "~/Documents", "/Users/Shared",
         "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "~/Library/Mail Downloads"].map(Paths.expand)
    }

    /// Scans `roots` (not following symlinks, not entering app bundles) up to `maxDepth` levels deep.
    public static func scan(roots: [String] = defaultRoots, installedApps: [String] = [], mounted: Set<String> = [],
                            maxDepth: Int = 4) -> [InstallerFile] {
        var found: [InstallerFile] = []
        var seen = Set<String>()
        for root in roots where FileManager.default.fileExists(atPath: root) {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            let rootDepth = URL(fileURLWithPath: root).pathComponents.count
            for case let url as URL in enumerator {
                if url.pathComponents.count - rootDepth >= maxDepth { enumerator.skipDescendants() }
                let ext = url.pathExtension.lowercased()
                guard let kind = kinds[ext] else { continue }
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
                if values?.isSymbolicLink == true { continue }
                let path = url.resolvingSymlinksInPath().path
                guard seen.insert(path).inserted, (try? Safety.validateForDeletion(path)) != nil else { continue }
                let measured = FileSizer.measure(path)
                found.append(InstallerFile(path: path, bytes: measured.bytes,
                                           modified: values?.contentModificationDate ?? measured.newest, kind: kind,
                                           installedApp: matchApp(fileName: url.lastPathComponent, installedApps: installedApps),
                                           mounted: mounted.contains(path)))
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    /// The installed app whose name the installer's file name starts with, ignoring case, spaces,
    /// punctuation and version numbers ("GoogleChrome-131.dmg" → "Google Chrome"). The longest
    /// match wins, and names shorter than three letters never match.
    public static func matchApp(fileName: String, installedApps: [String]) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        let fileKey = key(base)
        guard !fileKey.isEmpty else { return nil }
        return installedApps
            .map { ($0, key($0)) }
            .filter { $0.1.count >= 3 && fileKey.hasPrefix($0.1) }
            .max { $0.1.count < $1.1.count }?.0
    }

    static func key(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && !CharacterSet.decimalDigits.contains($0) })
    }

    /// Paths of disk images mounted right now (`hdiutil info`).
    public static func mountedImages() -> Set<String> {
        #if os(macOS)
        let r = Shell.run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 20)
        guard r.succeeded, let data = r.stdout.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [] }
        return Set(images.compactMap { ($0["image-path"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } })
        #else
        return []
        #endif
    }
}
