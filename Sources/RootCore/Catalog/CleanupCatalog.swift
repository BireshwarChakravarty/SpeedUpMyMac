import Foundation

/// The curated list of things Root knows how to clean.
///
/// Order matters: specific targets come first and "claim" their paths; broad targets later in the
/// list (all of ~/Library/Caches, all of ~/Library/Logs) skip anything already claimed, so sizes are
/// never double counted and every item is attributed to the most descriptive rule.
public enum CleanupCatalog {
    public static let all: [CleanupTarget] = developer + browsers + communication + devices + installers
        + privacy + trash + system + general

    public static func target(_ id: String) -> CleanupTarget? { all.first { $0.id == id } }

    // MARK: Developer

    static let developer: [CleanupTarget] = [
        CleanupTarget(id: "xcode-derived-data", title: "Xcode DerivedData",
                      detail: "Build intermediates and indexes. Xcode rebuilds them on the next build.",
                      category: .developer, kind: .contents(["~/Library/Developer/Xcode/DerivedData"]),
                      skipWhileRunning: ["Xcode"]),
        CleanupTarget(id: "xcode-device-support", title: "Device support files",
                      detail: "Debug symbols for every iOS/watchOS version you ever connected. Re-downloaded when a device connects.",
                      category: .developer,
                      kind: .contents(["~/Library/Developer/Xcode/*DeviceSupport"]), minAgeDays: 60),
        CleanupTarget(id: "xcode-previews", title: "SwiftUI preview simulators",
                      detail: "Preview devices often grow to many gigabytes; Xcode recreates them.",
                      category: .developer, kind: .contents(["~/Library/Developer/Xcode/UserData/Previews"]),
                      skipWhileRunning: ["Xcode"]),
        CleanupTarget(id: "simulator-caches", title: "Simulator caches",
                      detail: "CoreSimulator dyld and runtime caches.", category: .developer,
                      kind: .contents(["~/Library/Developer/CoreSimulator/Caches"]), skipWhileRunning: ["Simulator"]),
        CleanupTarget(id: "simulators-unavailable", title: "Unavailable simulators",
                      detail: "Simulators for runtimes that are no longer installed (xcrun simctl delete unavailable).",
                      category: .developer,
                      kind: .command(tool: "xcrun", arguments: ["simctl", "delete", "unavailable"], estimate: [])),
        CleanupTarget(id: "xcode-archives", title: "Xcode archives",
                      detail: "Contains the dSYMs for builds you shipped. Keep archives for anything in the wild.",
                      category: .developer, risk: .risky, kind: .contents(["~/Library/Developer/Xcode/Archives"]),
                      useTrash: true),
        CleanupTarget(id: "homebrew", title: "Homebrew downloads & old versions",
                      detail: "brew cleanup -s --prune=all: cached bottles and outdated kegs.", category: .developer,
                      kind: .command(tool: "brew", arguments: ["cleanup", "-s", "--prune=all"],
                                     estimate: ["~/Library/Caches/Homebrew"])),
        CleanupTarget(id: "npm-cache", title: "npm cache", detail: "~/.npm/_cacache — packages are re-fetched on demand.",
                      category: .developer, kind: .contents(["~/.npm/_cacache"])),
        CleanupTarget(id: "yarn-cache", title: "Yarn cache", detail: "Yarn's offline package cache.",
                      category: .developer, kind: .contents(["~/Library/Caches/Yarn", "~/.yarn/berry/cache"])),
        CleanupTarget(id: "pnpm-store", title: "pnpm store (unreferenced)",
                      detail: "pnpm store prune removes packages no project references.", category: .developer,
                      kind: .command(tool: "pnpm", arguments: ["store", "prune"], estimate: ["~/Library/pnpm/store"])),
        CleanupTarget(id: "bun-cache", title: "Bun cache", detail: "Bun's global install cache.",
                      category: .developer, kind: .contents(["~/.bun/install/cache"])),
        CleanupTarget(id: "pip-cache", title: "pip & uv caches", detail: "Python wheel and HTTP caches.",
                      category: .developer, kind: .contents(["~/Library/Caches/pip", "~/.cache/pip", "~/.cache/uv"])),
        CleanupTarget(id: "go-build-cache", title: "Go build cache", detail: "Compiled package cache (go clean -cache).",
                      category: .developer, kind: .contents(["~/Library/Caches/go-build"])),
        CleanupTarget(id: "cocoapods-cache", title: "CocoaPods cache", detail: "Downloaded pod sources.",
                      category: .developer, kind: .contents(["~/Library/Caches/CocoaPods"])),
        CleanupTarget(id: "cargo-cache", title: "Cargo registry cache", detail: "Downloaded crate archives and git checkouts.",
                      category: .developer, risk: .review,
                      kind: .contents(["~/.cargo/registry/cache", "~/.cargo/git/checkouts"])),
        CleanupTarget(id: "gradle-cache", title: "Gradle caches", detail: "Dependency and build caches; first build afterwards is slow.",
                      category: .developer, risk: .review, kind: .contents(["~/.gradle/caches"]),
                      skipWhileRunning: ["java", "studio"]),
        CleanupTarget(id: "go-mod-cache", title: "Go module cache", detail: "go clean -modcache; modules re-download on next build.",
                      category: .developer, risk: .review,
                      kind: .command(tool: "go", arguments: ["clean", "-modcache"], estimate: ["~/go/pkg/mod"])),
        CleanupTarget(id: "maven-repo", title: "Maven local repository", detail: "~/.m2/repository; re-downloaded by builds.",
                      category: .developer, risk: .review, kind: .contents(["~/.m2/repository"])),
        CleanupTarget(id: "browser-automation", title: "Puppeteer & Playwright browsers",
                      detail: "Bundled test browsers; reinstalled by npx playwright install.", category: .developer,
                      risk: .review, kind: .contents(["~/.cache/puppeteer", "~/Library/Caches/ms-playwright"])),
        CleanupTarget(id: "editor-caches", title: "VS Code & Cursor caches",
                      detail: "Electron code/GPU caches and cached extension packages.", category: .developer,
                      kind: .paths(["Code", "Cursor", "Windsurf"].flatMap { app in
                          ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache", "CachedProfilesData"]
                              .map { "~/Library/Application Support/\(app)/\($0)" }
                      }),
                      skipWhileRunning: ["Code", "Electron", "Cursor", "Windsurf"]),
        CleanupTarget(id: "docker-prune", title: "Docker dangling data",
                      detail: "docker system prune -f: stopped containers, dangling images, unused networks, build cache.",
                      category: .developer, risk: .review,
                      kind: .command(tool: "docker", arguments: ["system", "prune", "-f"], estimate: [])),
        CleanupTarget(id: "huggingface-cache", title: "Hugging Face model cache",
                      detail: "Downloaded AI models. Large, but re-downloading can take a long time.", category: .developer,
                      risk: .risky, kind: .contents(["~/.cache/huggingface/hub"])),
    ]

    // MARK: Browsers

    private static func chromium(_ root: String) -> [String] {
        ["\(root)/*/Code Cache", "\(root)/*/GPUCache", "\(root)/*/DawnCache", "\(root)/*/DawnGraphiteCache",
         "\(root)/*/DawnWebGPUCache", "\(root)/*/Service Worker/CacheStorage", "\(root)/*/Service Worker/ScriptCache",
         "\(root)/GrShaderCache", "\(root)/GraphiteDawnCache", "\(root)/ShaderCache", "\(root)/component_crx_cache",
         "\(root)/Crashpad/completed"]
    }

    static let browsers: [CleanupTarget] = [
        CleanupTarget(id: "chrome-caches", title: "Chrome caches",
                      detail: "Code, GPU, shader and service-worker caches for every profile.", category: .browsers,
                      kind: .paths(chromium("~/Library/Application Support/Google/Chrome") + ["~/Library/Caches/Google/Chrome"]),
                      skipWhileRunning: ["Google Chrome"]),
        CleanupTarget(id: "chrome-ai-model", title: "Chrome on-device AI model",
                      detail: "Gemini Nano weights (often ~4 GB). Chrome re-downloads them if the feature stays on.",
                      category: .browsers, risk: .review,
                      kind: .paths(["~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel",
                                    "~/Library/Application Support/Google/Chrome/optimization_guide_model_store"]),
                      skipWhileRunning: ["Google Chrome"]),
        CleanupTarget(id: "edge-caches", title: "Edge caches", detail: "Microsoft Edge code/GPU/service-worker caches.",
                      category: .browsers,
                      kind: .paths(chromium("~/Library/Application Support/Microsoft Edge") + ["~/Library/Caches/Microsoft Edge"]),
                      skipWhileRunning: ["Microsoft Edge"]),
        CleanupTarget(id: "brave-caches", title: "Brave caches", detail: "Brave code/GPU/service-worker caches.",
                      category: .browsers,
                      kind: .paths(chromium("~/Library/Application Support/BraveSoftware/Brave-Browser")
                                   + ["~/Library/Caches/BraveSoftware"]),
                      skipWhileRunning: ["Brave Browser"]),
        CleanupTarget(id: "arc-caches", title: "Arc caches", detail: "Arc code/GPU/service-worker caches.",
                      category: .browsers,
                      kind: .paths(chromium("~/Library/Application Support/Arc/User Data") + ["~/Library/Caches/Arc"]),
                      skipWhileRunning: ["Arc"]),
        CleanupTarget(id: "firefox-caches", title: "Firefox caches", detail: "Network cache for every Firefox profile.",
                      category: .browsers, kind: .paths(["~/Library/Caches/Firefox/Profiles/*/cache2"]),
                      skipWhileRunning: ["firefox"]),
        CleanupTarget(id: "safari-caches", title: "Safari caches", detail: "WebKit network cache (needs Full Disk Access).",
                      category: .browsers,
                      kind: .paths(["~/Library/Caches/com.apple.Safari",
                                    "~/Library/Containers/com.apple.Safari/Data/Library/Caches"]),
                      skipWhileRunning: ["Safari"]),
    ]

    // MARK: Mail, messages, chat apps

    static let communication: [CleanupTarget] = [
        CleanupTarget(id: "mail-downloads", title: "Mail attachments cache",
                      detail: "Copies of attachments you opened from Mail, older than 30 days. The originals stay in your mail.",
                      category: .communication,
                      kind: .contents(["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                                       "~/Library/Mail Downloads"]),
                      minAgeDays: 30, skipWhileRunning: ["Mail"]),
        CleanupTarget(id: "chat-app-caches", title: "Slack, Discord & Teams caches",
                      detail: "Electron caches of chat apps; messages are kept server-side.", category: .communication,
                      kind: .paths(["~/Library/Application Support/Slack", "~/Library/Application Support/discord",
                                    "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack"]
                          .flatMap { ["\($0)/Cache", "\($0)/Code Cache", "\($0)/GPUCache", "\($0)/Service Worker/CacheStorage"] }
                          + ["~/Library/Containers/com.microsoft.teams2/Data/Library/Caches"]),
                      skipWhileRunning: ["Slack", "Discord", "MSTeams", "Microsoft Teams"]),
    ]

    // MARK: iPhone & iPad

    static let devices: [CleanupTarget] = [
        CleanupTarget(id: "ios-firmware", title: "iOS/iPadOS firmware files",
                      detail: "Downloaded .ipsw restore images. Re-downloaded if you ever need to restore.",
                      category: .devices, kind: .paths(["~/Library/iTunes/*Software Updates/*.ipsw",
                                                        "~/Library/Group Containers/*.group.com.apple.configurator/Library/Caches/Firmware/*.ipsw"])),
        CleanupTarget(id: "ios-backups", title: "iPhone & iPad backups",
                      detail: "Local device backups. Only remove backups of devices you no longer own or that back up to iCloud.",
                      category: .devices, risk: .risky, kind: .contents(["~/Library/Application Support/MobileSync/Backup"]),
                      useTrash: true),
    ]

    // MARK: Installers & downloads

    static let installers: [CleanupTarget] = [
        CleanupTarget(id: "download-installers", title: "Installers in Downloads",
                      detail: "Disk images and packages older than two weeks — usually already installed.",
                      category: .installers, risk: .review,
                      kind: .files(root: "~/Downloads", patterns: ["*.dmg", "*.pkg", "*.mpkg", "*.iso", "*.xip"], maxDepth: 2),
                      minAgeDays: 14, useTrash: true),
        CleanupTarget(id: "incomplete-downloads", title: "Incomplete downloads",
                      detail: "Abandoned partial downloads from Safari, Chrome and Firefox.", category: .installers,
                      kind: .files(root: "~/Downloads", patterns: ["*.download", "*.crdownload", "*.part"], maxDepth: 2),
                      minAgeDays: 2, useTrash: true),
        CleanupTarget(id: "macos-installers", title: "Old macOS installers",
                      detail: "\"Install macOS …\" apps left in /Applications after an upgrade.", category: .installers,
                      scope: .system, risk: .review, kind: .paths(["/Applications/Install macOS*.app"])),
    ]

    // MARK: Privacy

    static let privacy: [CleanupTarget] = [
        CleanupTarget(id: "recent-items", title: "Recent items lists",
                      detail: "Recent apps, documents and servers in the Apple menu and Finder.", category: .privacy,
                      risk: .review,
                      kind: .paths(["~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.Recent*.sfl*"])),
    ]

    // MARK: Trash

    static let trash: [CleanupTarget] = [
        CleanupTarget(id: "trash", title: "Trash", detail: "Everything currently in your Trash.", category: .trash,
                      kind: .contents(["~/.Trash"])),
    ]

    // MARK: System (needs the Sudo toggle)

    static let system: [CleanupTarget] = [
        CleanupTarget(id: "system-crash-reports", title: "System crash & hang reports",
                      detail: "/Library/Logs/DiagnosticReports older than a week.", category: .system, scope: .system,
                      kind: .contents(["/Library/Logs/DiagnosticReports"]), minAgeDays: 7),
        CleanupTarget(id: "system-logs", title: "System app logs", detail: "Third-party and installer logs in /Library/Logs.",
                      category: .system, scope: .system, kind: .contents(["/Library/Logs"]),
                      excludeNames: ["DiagnosticReports"]),
        CleanupTarget(id: "system-caches", title: "System-wide caches",
                      detail: "/Library/Caches — shared caches that apps and macOS regenerate.", category: .system,
                      scope: .system, kind: .contents(["/Library/Caches"])),
        CleanupTarget(id: "var-log-archives", title: "Rotated system logs",
                      detail: "Compressed, already-rotated logs in /private/var/log.", category: .system, scope: .system,
                      kind: .files(root: "/private/var/log", patterns: ["*.gz", "*.bz2", "*.old", "*.[0-9]"], maxDepth: 2)),
        CleanupTarget(id: "core-dumps", title: "Core dumps", detail: "Crash memory dumps in /cores (can be many GB each).",
                      category: .system, scope: .system, kind: .contents(["/cores"])),
        CleanupTarget(id: "apple-loops", title: "GarageBand & Logic sound libraries",
                      detail: "Apple Loops and instrument content. Remove only if you don't use GarageBand or Logic.",
                      category: .system, scope: .system, risk: .risky,
                      kind: .paths(["/Library/Application Support/GarageBand", "/Library/Application Support/Logic",
                                    "/Library/Audio/Apple Loops", "/Library/Audio/Impulse Responses/Apple"]),
                      skipWhileRunning: ["GarageBand", "Logic Pro", "Logic Pro X"]),
    ]

    // MARK: General (last, so specific targets above claim their paths first)

    static let general: [CleanupTarget] = [
        CleanupTarget(id: "user-crash-reports", title: "Crash & hang reports",
                      detail: "Your crash and spin reports older than a week.", category: .logs,
                      kind: .contents(["~/Library/Logs/DiagnosticReports"]), minAgeDays: 7),
        CleanupTarget(id: "user-logs", title: "App logs", detail: "Log files apps write to ~/Library/Logs.", category: .logs,
                      kind: .contents(["~/Library/Logs"]), excludeNames: ["DiagnosticReports", "Root"]),
        CleanupTarget(id: "container-logs", title: "Sandboxed app logs", detail: "Logs inside app containers.",
                      category: .logs, kind: .contents(["~/Library/Containers/*/Data/Library/Logs"])),
        CleanupTarget(id: "container-caches", title: "Sandboxed app caches",
                      detail: "Caches inside App Store and sandboxed app containers.", category: .caches,
                      kind: .contents(["~/Library/Containers/*/Data/Library/Caches"]),
                      excludeNames: ["com.apple.*"]),
        CleanupTarget(id: "saved-app-state", title: "Old saved window state",
                      detail: "Window-restoration state for apps you haven't opened in 30 days.", category: .caches,
                      kind: .contents(["~/Library/Saved Application State"]), minAgeDays: 30),
        CleanupTarget(id: "user-caches", title: "App caches",
                      detail: "~/Library/Caches — every app's regenerable cache. Apps rebuild what they need.",
                      category: .caches, kind: .contents(["~/Library/Caches"]),
                      excludeNames: ["CloudKit", "com.apple.bird", "com.apple.HomeKit", "com.apple.akd", "FamilyCircle",
                                     "com.apple.findmy*", "com.apple.containermanagerd", "com.apple.ap.adprivacyd",
                                     "com.apple.nsurlsessiond", "com.apple.Safari.SafeBrowsing", "io.rootapp.*", "Root"]),
    ]
}
