import Foundation

public enum TweakGroup: String, Codable, CaseIterable, Sendable {
    case privacy = "Privacy"
    case snappy = "Snappier UI"
    case finder = "Finder"
    case quiet = "Fewer Interruptions"
    case system = "System (admin)"
}

public enum TweakValue: Codable, Equatable, Sendable {
    case bool(Bool), int(Int), float(Double), string(String)

    var defaultsArgs: [String] {
        switch self {
        case .bool(let b): return ["-bool", b ? "true" : "false"]
        case .int(let i): return ["-int", String(i)]
        case .float(let f): return ["-float", String(f)]
        case .string(let s): return ["-string", s]
        }
    }

    /// Compares with the textual output of `defaults read`.
    func matches(_ raw: String) -> Bool {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .bool(let b): return r == (b ? "1" : "0") || r.lowercased() == (b ? "true" : "false")
        case .int(let i): return Int(r) == i
        case .float(let f): return Double(r).map { abs($0 - f) < 0.0001 } ?? false
        case .string(let s): return r == s
        }
    }
}

/// A reversible `defaults` change (RemoveMacAI / TinkerTool style).
public struct Tweak: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var group: TweakGroup
    /// A domain like `com.apple.dock`, `NSGlobalDomain`, or an absolute plist path for system tweaks.
    public var domain: String
    public var key: String
    public var value: TweakValue
    public var needsAdmin: Bool
    /// Process to restart so the change takes effect.
    public var restart: String?
    public var presets: Set<String>

    init(_ id: String, _ title: String, _ detail: String, _ group: TweakGroup, domain: String, key: String,
         value: TweakValue, admin: Bool = false, restart: String? = nil, presets: Set<String> = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.group = group
        self.domain = domain
        self.key = key
        self.value = value
        self.needsAdmin = admin
        self.restart = restart
        self.presets = presets
    }
}

/// Values captured before a tweak was applied: nil means the key didn't exist.
struct TweakBackup: Codable {
    var previous: [String: String?] = [:]
}

public enum Tweaks {
    public static let presets = ["balanced", "privacy", "snappy"]

    public static let all: [Tweak] = [
        // Privacy
        Tweak("no-personalized-ads", "Turn off personalized Apple ads", "Stops Apple using your activity to target ads in the App Store, News and Stocks.",
              .privacy, domain: "com.apple.AdLib", key: "allowApplePersonalizedAdvertising", value: .bool(false), presets: ["balanced", "privacy"]),
        Tweak("no-ad-tracking", "Limit ad tracking", "Asks apps not to track you for advertising.",
              .privacy, domain: "com.apple.AdLib", key: "forceLimitAdTracking", value: .bool(true), presets: ["privacy"]),
        Tweak("no-siri-data-sharing", "Don't share Siri audio with Apple", "Opts out of \"Improve Siri & Dictation\".",
              .privacy, domain: "com.apple.assistant.support", key: "Siri Data Sharing Opt-In Status", value: .int(2), presets: ["privacy"]),
        Tweak("no-safari-suggestions", "No Safari search suggestions to Apple", "Stops Safari sending what you type to Apple for suggestions (needs Full Disk Access).",
              .privacy, domain: "com.apple.Safari", key: "UniversalSearchEnabled", value: .bool(false), presets: ["privacy"]),
        Tweak("no-analytics-submit", "Don't send Mac analytics", "Turns off automatic submission of diagnostics and usage data to Apple.",
              .system, domain: "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist", key: "AutoSubmit",
              value: .bool(false), admin: true, presets: ["privacy"]),
        Tweak("no-third-party-analytics", "Don't share crash data with developers", "Turns off sharing crash data with app developers.",
              .system, domain: "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist", key: "ThirdPartyDataSubmit",
              value: .bool(false), admin: true, presets: ["privacy"]),

        // Snappier UI
        Tweak("fast-window-resize", "Instant window resize animation", "Makes sheet and window resize animations near-instant.",
              .snappy, domain: "NSGlobalDomain", key: "NSWindowResizeTime", value: .float(0.001), presets: ["snappy", "balanced"]),
        Tweak("no-window-animations", "No window open/close zoom", "Disables the zoom animation when windows open.",
              .snappy, domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled", value: .bool(false), presets: ["snappy"]),
        Tweak("fast-dock-autohide", "Instant Dock auto-hide", "Removes the delay before a hidden Dock appears.",
              .snappy, domain: "com.apple.dock", key: "autohide-delay", value: .float(0), restart: "Dock", presets: ["snappy", "balanced"]),
        Tweak("fast-dock-reveal", "Faster Dock reveal", "Speeds up the Dock's slide-in animation.",
              .snappy, domain: "com.apple.dock", key: "autohide-time-modifier", value: .float(0.15), restart: "Dock", presets: ["snappy"]),
        Tweak("fast-mission-control", "Faster Mission Control", "Speeds up the Mission Control animation.",
              .snappy, domain: "com.apple.dock", key: "expose-animation-duration", value: .float(0.1), restart: "Dock", presets: ["snappy"]),
        Tweak("no-dock-recents", "Hide recent apps in Dock", "Removes the \"recent applications\" section from the Dock.",
              .snappy, domain: "com.apple.dock", key: "show-recents", value: .bool(false), restart: "Dock", presets: ["balanced", "snappy"]),
        Tweak("stable-spaces", "Don't rearrange Spaces", "Stops macOS reordering desktops by most recent use.",
              .snappy, domain: "com.apple.dock", key: "mru-spaces", value: .bool(false), restart: "Dock", presets: ["balanced", "snappy"]),
        Tweak("fast-quicklook", "Instant Quick Look", "Removes the Quick Look panel animation.",
              .snappy, domain: "NSGlobalDomain", key: "QLPanelAnimationDuration", value: .float(0), presets: ["snappy"]),

        // Finder
        Tweak("show-extensions", "Show all file extensions", "Always show .pdf, .zip and so on.",
              .finder, domain: "NSGlobalDomain", key: "AppleShowAllExtensions", value: .bool(true), restart: "Finder", presets: ["balanced"]),
        Tweak("finder-path-bar", "Show Finder path bar", "Shows where you are at the bottom of every window.",
              .finder, domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true), restart: "Finder", presets: ["balanced"]),
        Tweak("finder-status-bar", "Show Finder status bar", "Shows item count and free space.",
              .finder, domain: "com.apple.finder", key: "ShowStatusBar", value: .bool(true), restart: "Finder", presets: ["balanced"]),
        Tweak("search-current-folder", "Search the current folder", "Finder search defaults to the folder you're in, not the whole Mac.",
              .finder, domain: "com.apple.finder", key: "FXDefaultSearchScope", value: .string("SCcf"), restart: "Finder", presets: ["balanced"]),
        Tweak("folders-first", "Keep folders on top", "Sort folders before files in Finder windows.",
              .finder, domain: "com.apple.finder", key: "_FXSortFoldersFirst", value: .bool(true), restart: "Finder", presets: ["balanced"]),
        Tweak("auto-empty-trash", "Empty Trash after 30 days", "Finder removes items that have been in the Trash for 30 days.",
              .finder, domain: "com.apple.finder", key: "FXRemoveOldTrashItems", value: .bool(true), restart: "Finder", presets: ["balanced"]),
        Tweak("no-ds-store-network", "No .DS_Store on network shares", "Stops Finder littering SMB/AFP shares with .DS_Store files.",
              .finder, domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", value: .bool(true), presets: ["balanced", "privacy"]),
        Tweak("no-ds-store-usb", "No .DS_Store on USB drives", "Stops Finder writing .DS_Store files to removable drives.",
              .finder, domain: "com.apple.desktopservices", key: "DSDontWriteUSBStores", value: .bool(true), presets: ["balanced", "privacy"]),

        // Fewer interruptions
        Tweak("no-crash-dialog", "No crash reporter pop-ups", "Crashes are still logged, just without the dialog.",
              .quiet, domain: "com.apple.CrashReporter", key: "DialogType", value: .string("none"), presets: ["snappy"]),
        Tweak("no-photos-autolaunch", "Don't open Photos when a phone connects", "Stops Photos launching every time you plug in an iPhone or camera.",
              .quiet, domain: "com.apple.ImageCapture", key: "disableHotPlug", value: .bool(true), presets: ["balanced"]),
        Tweak("no-tm-new-disk-prompt", "No Time Machine prompt for new disks", "Stops \"Use this disk for Time Machine?\" for every drive.",
              .quiet, domain: "com.apple.TimeMachine", key: "DoNotOfferNewDisksForBackup", value: .bool(true), presets: ["balanced"]),
        Tweak("no-extension-warning", "No warning when changing extensions", "Skips the \"Are you sure you want to change the extension?\" alert.",
              .quiet, domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning", value: .bool(false), restart: "Finder", presets: ["snappy"]),
    ]

    public static func tweak(_ id: String) -> Tweak? { all.first { $0.id == id } }

    public static func inPreset(_ preset: String) -> [Tweak] { all.filter { $0.presets.contains(preset) } }

    static var backupURL: URL { URL(fileURLWithPath: Paths.support).appendingPathComponent("tweaks-backup.json") }

    static func loadBackup() -> TweakBackup {
        (try? Data(contentsOf: backupURL)).flatMap { try? JSONDecoder.burnish.decode(TweakBackup.self, from: $0) } ?? TweakBackup()
    }

    static func saveBackup(_ backup: TweakBackup) {
        if let data = try? JSONEncoder.burnish.encode(backup) { try? data.write(to: backupURL, options: .atomic) }
    }

    /// Current raw value via `defaults read`, nil if unset.
    public static func currentValue(_ tweak: Tweak) -> String? {
        let r = Shell.run("/usr/bin/defaults", ["read", tweak.domain, tweak.key])
        return r.succeeded ? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    public static func isApplied(_ tweak: Tweak) -> Bool {
        currentValue(tweak).map(tweak.value.matches) ?? false
    }

    /// Applies tweaks. User tweaks run directly; admin tweaks go into one root script.
    public static func apply(_ tweaks: [Tweak], sudo: Bool, runner: PrivilegeRunner?) -> [String: String] {
        var errors: [String: String] = [:]
        var backup = loadBackup()
        var script = PrivilegedScript()
        var restarts = Set<String>()
        for tweak in tweaks {
            if backup.previous[tweak.id] == nil { backup.previous[tweak.id] = .some(currentValue(tweak)) }
            if tweak.needsAdmin {
                guard sudo else { errors[tweak.id] = "Needs Sudo mode"; continue }
                script.add("/usr/bin/defaults", ["write", tweak.domain, tweak.key] + tweak.value.defaultsArgs, tolerateFailure: false)
            } else {
                let r = Shell.run("/usr/bin/defaults", ["write", tweak.domain, tweak.key] + tweak.value.defaultsArgs)
                if !r.succeeded { errors[tweak.id] = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            if let restart = tweak.restart { restarts.insert(restart) }
        }
        saveBackup(backup)
        if !script.isEmpty {
            do {
                guard let runner else { throw PrivilegeError.failed("No privilege runner") }
                let r = try runner.run(script, reason: "apply system tweaks")
                if !r.succeeded { for t in tweaks where t.needsAdmin { errors[t.id] = r.stderr } }
            } catch {
                for t in tweaks where t.needsAdmin { errors[t.id] = error.localizedDescription }
            }
        }
        for process in restarts { Shell.run("/usr/bin/killall", [process]) }
        History.append(HistoryEntry(action: "tweaks", detail: "Applied \(tweaks.count - errors.count) tweak(s)"))
        return errors
    }

    /// Restores the value each tweak had before Burnish first changed it.
    public static func revert(_ tweaks: [Tweak], sudo: Bool, runner: PrivilegeRunner?) -> [String: String] {
        var errors: [String: String] = [:]
        var backup = loadBackup()
        var script = PrivilegedScript()
        var restarts = Set<String>()
        for tweak in tweaks {
            guard let entry = backup.previous[tweak.id] else { continue }
            let args: [String]
            if let previous = entry {
                args = ["write", tweak.domain, tweak.key] + restoreArgs(previous, like: tweak.value)
            } else {
                args = ["delete", tweak.domain, tweak.key]
            }
            if tweak.needsAdmin {
                guard sudo else { errors[tweak.id] = "Needs Sudo mode"; continue }
                script.add("/usr/bin/defaults", args)
            } else {
                Shell.run("/usr/bin/defaults", args)
            }
            backup.previous.removeValue(forKey: tweak.id)
            if let restart = tweak.restart { restarts.insert(restart) }
        }
        if !script.isEmpty, let runner { _ = try? runner.run(script, reason: "revert system tweaks") }
        saveBackup(backup)
        for process in restarts { Shell.run("/usr/bin/killall", [process]) }
        History.append(HistoryEntry(action: "tweaks", detail: "Reverted \(tweaks.count - errors.count) tweak(s)"))
        return errors
    }

    static func restoreArgs(_ raw: String, like value: TweakValue) -> [String] {
        switch value {
        case .bool: return ["-bool", (raw == "1" || raw.lowercased() == "true") ? "true" : "false"]
        case .int: return ["-int", raw]
        case .float: return ["-float", raw]
        case .string: return ["-string", raw]
        }
    }

    // MARK: Touch ID for sudo (admin, special-cased because it edits a PAM file)

    public static let touchIDPamPath = "/etc/pam.d/sudo_local"

    public static func touchIDForSudoEnabled() -> Bool {
        guard let text = try? String(contentsOfFile: touchIDPamPath, encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("auth") && $0.contains("pam_tid.so") }
    }

    /// Script that enables/disables pam_tid in /etc/pam.d/sudo_local (survives macOS updates since Sonoma).
    /// Existing lines (e.g. pam_reattach for tmux) are preserved; only the pam_tid line is touched.
    public static func touchIDScript(enable: Bool) -> PrivilegedScript {
        var script = PrivilegedScript()
        let f = touchIDPamPath
        if enable {
            script.addTrusted("[ -f \(f) ] || printf '%s\\n' '# sudo_local: local config file which survives system update and is included for sudo' > \(f)")
            script.addTrusted("if grep -q '^#[[:space:]]*auth.*pam_tid.so' \(f); then sed -i '' 's/^#[[:space:]]*\\(auth.*pam_tid.so\\)/\\1/' \(f); fi")
            script.addTrusted("grep -q '^auth.*pam_tid.so' \(f) || printf '%s\\n' 'auth       sufficient     pam_tid.so' >> \(f)")
            script.addTrusted("chmod 444 \(f)")
        } else {
            script.addTrusted("[ -f \(f) ] && chmod 644 \(f) && sed -i '' 's/^\\(auth.*pam_tid.so\\)/#\\1/' \(f) && chmod 444 \(f) || true")
        }
        return script
    }
}
