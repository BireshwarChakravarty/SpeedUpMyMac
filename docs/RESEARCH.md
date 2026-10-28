# Research: how the Mac cleaner apps actually work

This is the research behind **Burnish**. I went through the cleaners, uninstallers, disk visualizers, maintenance tools, monitors and security auditors that people actually use in 2026. For each one I wrote down what it does, how it does it under the hood, and what Burnish takes from it. I also list the things Burnish should *not* copy, because some popular "speed up" features are placebo or risky.

Research date: October 2026. Target OS: macOS 26 Tahoe on Apple silicon (M3 / M4 / M6). Older releases back to macOS 14 Sonoma still work.

---

## 1. The landscape at a glance

| App | Category | Price / license | What it's best at | How it works |
|---|---|---|---|---|
| **CleanMyMac** (MacPaw, v5.x) | All-in-one | ~$40/yr | One-click "Smart Care", polish, malware (Moonlock) | Curated path database + heuristics; privileged helper; Space Lens bubble map; Cloud Cleanup (iCloud/Drive/OneDrive) |
| **Mole** (`tw93/Mole`, `mo`) | CLI all-in-one | Free, OSS (Bash + Go) | Transparent, scriptable deep clean, dev purge | Bash scripts over `~/Library`, `sudo` session on demand, dry-run ledger, whitelist, op log |
| **Pearcleaner** | Uninstaller | Free, Apache-2.0 + Commons Clause (on hold since end of 2025) | Most thorough leftover finder; Sentinel | Bundle-ID / name / team-ID matching over ~70 locations + Spotlight; SMAppService helper; FSEvents on `~/.Trash` |
| **AppCleaner** (FreeMacSoft) | Uninstaller | Free | Simple drag-to-uninstall | Bundle-ID + name match in `~/Library` subfolders |
| **OnyX** (Titanium) | Maintenance | Free | Rebuild caches/DBs, hidden prefs | Wraps `lsregister`, `mdutil`, `atsutil`, `kextcache`, `defaults`; one build per macOS release |
| **Sensei** (Cindori) | Monitor + optimize | $29/yr or $59 lifetime | Hardware health dashboard | IOKit / SMC sensors, battery registry, SMART, disk benchmarks |
| **DaisyDisk** | Disk visualizer | $9.99, 5 Macs | Fast sunburst map, purgeable space | Parallel low-level scan (`getattrlistbulk`-style); purgeable shown as "hidden space" |
| **GrandPerspective** | Disk visualizer | Free, OSS | Treemap | Recursive scan, squarified treemap |
| **OmniDiskSweeper** | Disk list | Free | Sorted size list | Recursive `du`-style scan |
| **DevCleaner for Xcode** | Dev cache cleaner | Free, GPL | DerivedData / Archives / Device Support | Reads Xcode folders, groups by version/device |
| **npkill / Mole purge** | Dev artifacts | Free | `node_modules`, `target`, `.build` | Walks project roots, filters by marker files and age |
| **App Tamer** (St. Clair) | CPU tamer | ~$15 | Pause/throttle background hogs | `SIGSTOP`/`SIGCONT` duty-cycling; `PRIO_DARWIN_BG` to push onto E-cores |
| **KnockKnock** (Objective-See) | Persistence audit | Free, OSS | What auto-starts and is it signed | Enumerates launch items, login items, extensions; code-sign check; VirusTotal hash lookup |
| **LaunchControl / Lingon** | launchd manager | Paid | Enable/disable/edit launch agents | Parses plists, drives `launchctl` |
| **Stats** (exelban) | Menu-bar monitor | Free, MIT | CPU/GPU/RAM/disk/net/sensors | Mach host stats, IOKit, SMC |
| **iStat Menus** | Menu-bar monitor | Paid | Polished sensors | Same sources as Stats |
| **RemoveMacAI** | Debloat / privacy | Free, MIT | Reversible privacy toggles | `defaults write` with undo, presets |
| **TinkerTool / TinkerTool System** | Hidden prefs | Free / paid | Hidden Finder/Dock settings | `defaults`, privileged helper for system |
| **Gemini 2 / dupeGuru** | Duplicates | Paid / OSS | Duplicate + similar files | Size bucket → partial hash → full hash |
| **BuhoCleaner, CCleaner Mac, PowerMyMac, MacKeeper** | All-in-one clones | Paid | Nothing unique | Same path lists; MacKeeper has a bad reputation. Ignore. |
| **DiskCleaner Pro** | Cleaner | Paid | "No silent deletes", checkbox review | Pitches itself against CleanMyMac's background deletion |

Roundups this year mostly agree: CleanMyMac is still the default all-in-one, but you get the same cleanup for free with **Pearcleaner/AppCleaner + OnyX + DaisyDisk/GrandPerspective**. Mole has become the go-to free CLI. The two main complaints about CleanMyMac are the subscription and that it removes things in the background without showing exactly what went. Burnish fixes both: it's free and open, and every deletion is itemised, previewed and logged.

---

## 2. Deep dives

### 2.1 CleanMyMac (MacPaw)
- **Modules (2025–26 redesign):** Smart Care (one button that runs clean, protect and speed together), Cleanup, Protection, Performance, Applications, My Clutter (large, old and duplicate files). v5.5 (Apr 2026) added a pinnable **My Tools** hub. v5.2.6 (Oct 2025) added **Cloud Cleanup**, which runs Space Lens and Large Files over iCloud Drive, Google Drive and OneDrive. v5.3 (Dec 2025) added Dropbox and OneDrive.
- **How:** a curated, signed database of junk paths plus heuristics. A privileged helper handles system paths. Malware detection uses the proprietary Moonlock engine. Space Lens is a bubble/treemap of directory sizes.
- **Take:** the *Smart Scan* one-button flow; one score summarising "how healthy is this Mac"; a pinnable tool hub; large/old/duplicate finder; a "maintenance" task list.
- **Don't take:** silent background deletion, the subscription, and malware signatures (no way to maintain them). Burnish uses Apple's own XProtect status plus a KnockKnock-style signing audit instead.

### 2.2 Mole (`tw93/Mole`)
Mole is the most useful reference because the whole implementation is readable shell.
- **Commands:** `clean`, `uninstall`, `optimize`, `analyze`, `status`, `purge`, `installer`, `slim`, `touchid`, `history`. Every destructive command supports `--dry-run`. There's a whitelist at `~/.config/mole/whitelist` and an operations log at `~/Library/Logs/mole/operations.log`.
- **Privilege model:** it **refuses to run as root** ("Run Mole without sudo; it requests administrator access when needed"). It scans as the user, then asks once for a `sudo` session for the system section. If you say no, it carries on with user-level work only. **That's exactly the behaviour you need on the M3 where you aren't admin.**
- **Clean targets (user):** `~/Library/Caches/*` (with guards for things like the Deno cache), `~/Library/Logs` (keeps `DiagnosticReports`), Mail Downloads older than 30 days (skipped while Mail runs), browser caches (Chrome `Code Cache`/`GPUCache`/`ShaderCache`/`OptGuideOnDeviceModel`, Firefox `cache2`, Safari, Arc), old Chromium/Edge/Brave app versions, cloud-sync caches (Dropbox/Drive/OneDrive), `~/Library/Containers/*/Data/Library/Caches/*`, `~/.cache/puppeteer`, iOS `.ipsw` updates, `.DS_Store`, and incomplete downloads (`*.download`, `*.crdownload`, `*.part`, skipped while still open).
- **Optimize (exact commands):**
  - DNS: `sudo dscacheutil -flushcache` plus SIGHUP to `system/com.apple.mDNSResponder`, *skipped when a VPN is up* (`scutil --nc list`, `utun` default route)
  - QuickLook/icon caches: `qlmanage -r cache`, `qlmanage -r`, then remove `com.apple.QuickLook.thumbnailcache` and `com.apple.iconservices*`
  - Saved Application State older than N days
  - Lint `~/Library/Preferences/*.plist` with `plutil` and drop the corrupt ones
  - Route/ARP flush **only if a probe fails**
  - `diskutil resetUserPermissions / <uid>` **only if** home folder ownership is actually wrong
  - Spotlight: time two `mdfind` probes and rebuild with `mdutil -E /` **only if both are slow and the Mac is on AC power**
  - Quarantine history DB: `DELETE FROM LSQuarantineEvent; VACUUM;`
  - SQLite `VACUUM` on Mail Envelope Index, Messages `chat.db` and Safari History, but only if the app is closed, the file is under 100 MB, the freelist is at least 5%, and `PRAGMA integrity_check` returns ok
  - Read-only audit of launch agents and BTM (`sfltool dumpbtm`)
- **Deliberately removed from Mole** (this matters, it's hard-won knowledge): periodic scripts (gone in macOS 15), swap cleanup ("VM operations pose crash risk"), dyld cache rebuild, deleting local snapshots ("deletes Time Machine recovery points"), radio refresh, startup-item cleanup.
- **Purge:** `node_modules`, `target`, `.build`, `build`, `dist` under `~/Projects`, `~/GitHub`, `~/dev` and custom roots, up to 6 levels deep. It **skips Git-tracked dirs, dirs with keypair files, and anything touched in the last 7 days**.
- **Uninstall:** searches `/Applications`, `~/Applications`, Input Methods and `/Volumes/*/Applications`. It reads the bundle ID with `plutil -extract CFBundleIdentifier raw` and last-used date with `mdls kMDItemLastUsedDate`. Leftovers go to **Trash by default** (`--permanent` to skip). Personal data is kept unless you pass `--with-data`.
- **Status:** a health score from 0 to 100 combining CPU, memory, disk, SMART, I/O, thermals, battery and uptime. JSON output when piped.
- **Take:** nearly all of it. Conditional optimisation (only fix what a probe says is broken), the no-root rule, dry-run, whitelist, op log, purge safety rules, and the "removed on purpose" list.

### 2.3 Pearcleaner (alienator88)
- **Features:** app uninstall, **orphaned file search** (leftovers from apps you deleted long ago), dev environment manager, file search, Homebrew manager, **App Lipo** (strips unused CPU slices), PKG manager (`pkgutil` receipts), plugin manager, services manager, app updater, Finder extension, and the **Sentinel** Trash monitor (~2 MB RAM).
- **Leftover search:** about 70 roots. These include `~/Library/{Application Support, Application Scripts, Caches, Containers, Group Containers, HTTPStorages, LaunchAgents, Logs, Preferences, Preferences/ByHost, Saved Application State, WebKit, Services, Internet Plug-Ins, PreferencePanes}`, the `/Library` equivalents plus `LaunchDaemons`, `PrivilegedHelperTools` and `Extensions`, `/private/var/db/receipts`, `/Users/Shared`, `/usr/local/{bin,etc,opt,share,var}`, tracker caches (`Sparkle`, `Crashlytics`, `SentryCrash`, `Amplitude`…), and Steam.
- **Matching** has three sensitivity levels:
  - *Strict:* exact name or bundle ID
  - *Enhanced:* contains-match, the last two bundle-ID components joined (`knollsoftrectangle`), and the app name stripped of version numbers (`Bartender 6` → `bartender`)
  - *Deep:* adds company component and Team ID, plus Spotlight over many metadata attributes
  - Sandboxed containers are matched by reading `.com.apple.containermanagerd.metadata.plist` → `MCMMetadataIdentifier`. Helper suffixes (`.helper`, `.agent`, `.launcher`, `.updater`…) are stripped to find the base bundle ID.
- **Privilege:** an `SMAppService.daemon` helper over XPC (Developer-ID signed). Note: its helper takes a free-form shell command string as root, which is a design Burnish should *not* copy.
- **Sentinel:** a tiny separate process. It runs an FSEvents stream on `~/.Trash`, and when a `.app` lands there it opens the main app via a URL scheme to offer leftover cleanup.
- **Take:** the leftover root list, the 3-level sensitivity matcher, container metadata matching, orphan finder, Trash sentinel and pkg receipts.
- **Don't take:** language pruning or lipo *inside* signed bundles. Modifying a sealed bundle breaks its code signature, which can trip Gatekeeper or the app's own updater. Burnish reports it as possible savings but doesn't do it by default.

### 2.4 AppCleaner (FreeMacSoft)
- The simplest model: drag an app in and it lists `~/Library/*/<bundle-id>*` and `*<App Name>*`. It's the "strict" level above. **Take:** drag-and-drop onto the window or Dock icon.

### 2.5 OnyX (Titanium Software)
- One build per macOS version (OnyX 5 for Tahoe). It verifies the system volume, cleans caches and logs, and rebuilds Launch Services, the CoreDuet DB and the XPC cache. It also exposes hidden Finder/Dock/Safari parameters. It needs Full Disk Access.
- Periodic scripts were **removed in macOS 15** (`/etc/periodic` is gone and `periodic` is no longer shipped). OnyX and Maintenance dropped that action, so Burnish hides it on 15+.
- **Take:** the maintenance catalogue (Launch Services rebuild, Spotlight reindex, font cache reset, QuickLook reset, DNS flush, Dock/Finder restart) and a hidden-preferences panel.

### 2.6 Sensei (Cindori)
- Dashboard of CPU/GPU/RAM/network/battery/40+ temperature sensors/fans. Battery health (cycle count, design vs. current capacity), SMART, disk benchmark, Trim toggle, startup optimizer, cleaner, uninstaller.
- **How:** IOKit (`AppleSmartBattery` registry entry: `CycleCount`, `AppleRawMaxCapacity`, `DesignCapacity`), SMC keys for sensors, `diskutil info` for SMART.
- **Take:** the health dashboard (battery, SMART, thermal state, memory pressure, swap). Trim is always on for Apple SSDs, so Burnish just displays it.

### 2.7 DaisyDisk / GrandPerspective / OmniDiskSweeper
- DaisyDisk: a parallel, low-level scan; a **sunburst** map; drag items to a "collector" before deleting. It also shows **purgeable space** (mostly APFS local snapshots) separately, because no scan can see inside it, and it can force-reclaim it.
- GrandPerspective: a squarified **treemap**. OmniDiskSweeper: a sorted list.
- **Take:** a fast concurrent scanner (`FileManager.enumerator` with prefetched `totalFileAllocatedSize`), both a sunburst and a sorted list, a staging "collector", and the free / purgeable / snapshot breakdown via `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` and `tmutil listlocalsnapshots /`.

### 2.8 Developer cleaners (DevCleaner for Xcode, npkill, Mole purge)
- **Xcode:**
  - `~/Library/Developer/Xcode/DerivedData` (safe)
  - `iOS DeviceSupport` / `watchOS DeviceSupport` per OS version (safe; re-downloaded on connect)
  - `Archives` (**keep**, it holds the dSYMs for shipped builds; opt-in only)
  - `~/Library/Developer/CoreSimulator/Caches`
  - unavailable simulators via `xcrun simctl delete unavailable`
  - SwiftUI preview simulators (`~/Library/Developer/Xcode/UserData/Previews`)
- **Toolchain caches:** `brew cleanup -s --prune=all`, `npm cache clean --force` (`~/.npm/_cacache`), `~/Library/Caches/Yarn`, `pnpm store prune`, `~/Library/Caches/pip`, `~/.cargo/registry/cache`, `~/go/pkg/mod/cache` (`go clean -modcache`), `~/.gradle/caches`, `~/Library/Caches/CocoaPods`, `~/.cocoapods/repos`, `~/.m2/repository` (opt-in), `docker system prune` (opt-in, it kills stopped containers), `~/.cache/huggingface` (opt-in, it holds AI models).
- **Project artifacts:** `node_modules` (marker `package.json`), `target` (`Cargo.toml` or `pom.xml`), `.build` (`Package.swift`), `Pods` (`Podfile`), `.venv`/`venv` (`pyvenv.cfg`), `__pycache__`, `.gradle`/`build` (`build.gradle*`), `.next`, `.nuxt`, `.turbo`, `.parcel-cache`.

### 2.9 App Tamer (St. Clair Software)
- Sends **`SIGSTOP`** to an app when it goes to the background and **`SIGCONT`** when it comes back. Throttling alternates the two (90% stopped ≈ 10% CPU). "Run on efficiency cores" sets `PRIO_DARWIN_BG` (the same as `taskpolicy -b -p <pid>`). No root is needed for your own processes.
- **Take:** a process view with Quit / Force-quit / **Pause** / **Push to E-cores**. All of it works on a standard (non-admin) account for your own processes.

### 2.10 KnockKnock / BlockBlock (Objective-See), LaunchControl
- Enumerates persistence (launch agents/daemons, login items, background task management (BTM) items, kernel and system extensions, browser extensions, cron, periodic). Checks code signatures and looks up hashes on VirusTotal.
- On Ventura and later, the source of truth is BTM: `sudo sfltool dumpbtm` lists items (read-only). `sfltool resetbtm` wipes them all, so never use that casually. Per-item control is `launchctl bootout` / `launchctl disable gui/<uid>/<label>` for user agents, `system/<label>` with sudo.
- **Take:** a "Startup & Background" audit. Each item gets its signer (`codesign -dv --verbose=2` → Authority / TeamIdentifier), an unsigned/ad-hoc flag, whether the target binary still exists (broken agents are common), and a reversible disable via `launchctl disable`, no deletion.

### 2.11 Stats / iStat Menus
- Mach `host_statistics64` for VM/memory, `host_processor_info` for per-core CPU, IOKit for disks and battery, SMC for sensors. macOS 26 adds a **Menu Bar privacy pane** that can hide third-party menu-bar items, so the menu-bar extra has to be allowed there.
- **Take:** a lightweight `MenuBarExtra` showing memory pressure, free disk and a one-click quick clean.

### 2.12 RemoveMacAI / TinkerTool / "debloat" scripts
- macOS 26 has a **Signed System Volume** with SIP. You **cannot delete system apps or truly disable Siri/Spotlight daemons** without turning SIP off, and Burnish will never ask you to. Eclectic Light (Jan 2026) confirms that switching off all Spotlight settings doesn't stop indexing.
- What *is* possible, and reversible: `defaults` toggles for analytics, personalized ads, Siri suggestions, Spotlight web results, the crash-reporter dialog, `.DS_Store` on network and USB volumes, Photos auto-open, the Time Machine new-disk prompt, animation speeds and Dock delays. Removing *deletable* Apple extras (GarageBand + `/Library/Application Support/GarageBand` + `/Library/Audio/Apple Loops`, iMovie, Keynote/Pages/Numbers) often frees 2–10 GB.
- **Take:** reversible tweaks. Every change records its previous value to a restore file, as RemoveMacAI does. Presets: *Balanced*, *Privacy*, *Snappy*.

### 2.13 Time Machine snapshots & "System Data"
- The biggest mystery blob in Settings → Storage is usually **local APFS snapshots**. List them with `tmutil listlocalsnapshots /`. `tmutil thinlocalsnapshots / <bytes> <urgency 1-4>` asks macOS to reclaim space. `tmutil deletelocalsnapshots <date>` deletes one (needs admin). Only do this if you have a real backup, because snapshots *are* recovery points. Mole removed auto-deletion for this reason. Burnish shows them and offers *thin* with an explicit confirmation.

---

## 3. Platform facts that shape the design

1. **Admin vs. standard account.** Your M3 is a standard account. Membership of the `admin` group (`id -Gn` contains `admin`, or `dsmemberutil checkmembership -U <user> -G admin`) decides whether the sudo toggle can be switched on. A standard user can still:
   - clean everything under `~` (caches, logs, containers, dev caches, project artifacts, Trash)
   - uninstall apps in `~/Applications`, and `/Applications` apps that the user owns (most drag-installed apps are owned by whoever copied them)
   - pause, throttle and quit their own processes
   - disable *their own* launch agents (`gui/<uid>` domain)
   - run user-domain maintenance: `lsregister` user domain, `qlmanage -r`, `atsutil databases -removeUser`, Dock/Finder restart
   - write user `defaults` tweaks
   - install a user LaunchAgent for scheduled cleaning (no admin needed)
2. **Running it on a standard account.** Gatekeeper only checks files that carry the `com.apple.quarantine` attribute. **An app you build yourself on the Mac never gets that attribute**, so a source build into `~/Applications` runs with no admin and no Developer ID. That's the install path for the M3.
3. **Privilege escalation without a Developer ID.** `SMAppService.daemon` and `SMJobBless` helpers need a Developer-ID-signed, notarized bundle. Unsigned helpers show as "unidentified developer" and won't run on Sequoia/Tahoe. For a personal tool, the practical, transparent route is:
   - **App:** collect every privileged step into one generated shell script, show it to you, and run it with a *single* authorization prompt via `do shell script … with administrator privileges`. Apple DTS calls this "not a valid alternative" for *shipping* software, but it's fine for a personal tool. A `PrivilegedHelper` protocol keeps the door open to swap in an `SMAppService` helper if you ever sign it.
   - **CLI:** plain `sudo`, and Touch ID works if `/etc/pam.d/sudo_local` enables `pam_tid.so` (survives updates since Sonoma). Burnish offers that as a one-time admin tweak.
4. **Full Disk Access.** Mail, Safari, Messages, `~/Library/Containers/*` of other apps, and `~/.Trash` from a terminal all need FDA. Burnish probes for it by trying to read `~/Library/Safari` and links to *System Settings → Privacy & Security → Full Disk Access* when it's missing. A standard user *can* grant FDA to apps for their own account on recent macOS, though some managed (MDM) machines lock it.
5. **Things that don't speed up a modern Mac** (so Burnish doesn't pretend they do):
   - `purge` to "free RAM": the memory compressor manages this. It's offered only as a diagnostic.
   - Repairing disk permissions: gone since El Capitan, apart from the user-home reset that Mole runs only when ownership is wrong.
   - Running periodic scripts: removed in macOS 15.
   - Rebuilding the dyld cache or kext cache: the sealed system volume makes this meaningless.
   - Clearing swap: dangerous.
   - What *does* help: freeing disk when the SSD is under ~10–15% free (swap and snapshots need room), killing runaway processes, trimming login and background items, fixing a broken Spotlight index, and reducing transparency and motion on older GPUs.

---

## 4. Feature matrix: what Burnish combines

| Burnish module | Borrowed from | Works without admin? | With sudo toggle adds |
|---|---|---|---|
| **Smart Scan** (one button, health score) | CleanMyMac Smart Care, Mole status | ✅ | System caches/logs, snapshots |
| **Cleanup** (50 curated targets) | Mole clean, CleanMyMac, BleachBit | ✅ user scope | `/Library/Caches`, `/Library/Logs`, `/private/var/log` archives, old installers in `/Library/Updates`, `/Users/Shared` junk |
| **Dev Purge** (artifacts + toolchain caches) | Mole purge, DevCleaner, npkill | ✅ | — |
| **Uninstaller** + orphans + Trash Sentinel | Pearcleaner, AppCleaner, Mole | ✅ for user-owned apps | Root-owned apps, `/Library/LaunchDaemons`, helper tools, pkg receipts |
| **Space Lens** (sunburst + list + large/old + duplicates) | DaisyDisk, GrandPerspective, Gemini | ✅ | Scan `/Library`, `/private/var` |
| **Speed** (processes: quit/pause/E-cores) | App Tamer, Activity Monitor | ✅ own processes | Other users' processes |
| **Maintenance** (conditional tasks) | OnyX, Mole optimize | ✅ user-domain tasks | DNS flush, Spotlight reindex, system font cache, snapshot thinning |
| **Startup & Background** audit | KnockKnock, LaunchControl, BTM | ✅ user agents | System daemons, `sfltool dumpbtm` |
| **Debloat & Tweaks** (reversible) | RemoveMacAI, TinkerTool, OnyX params | ✅ user defaults | GarageBand/loops, analytics auto-submit, Touch ID sudo, pmset |
| **Health** (battery, SSD, thermal, security posture) | Sensei, Stats, CleanMyMac Protection | ✅ | — |
| **Fleet** (all your Macs side by side) | *new*: nobody does this | ✅ | — |
| **History & Undo** | Mole op log, RemoveMacAI restore | ✅ | — |

The **Fleet** module is the gap in the market. None of these tools know you own more than one Mac. Burnish writes a small JSON snapshot per Mac (chip, macOS, admin or not, free space, reclaimable, last clean, health score) to a shared folder: iCloud Drive by default, or any folder or synced drive you pick for the M3, where personal iCloud may not be signed in. Every Mac then shows the whole fleet. Shared settings (ignore list, tweak preset, schedule) sync the same way, with per-machine overrides.

---

## 5. Sources

- CleanMyMac: [What's new (MacPaw)](https://macpaw.com/de/cleanmymac/whats-new), [Introducing the new CleanMyMac](https://macpaw.com/news/introducing-new-cleanmymac), [Gadgetbond on the redesign](https://gadgetbond.com/macpaw-cleanmymac-redesign-smart-care-my-clutter/), [Wikipedia](https://en.wikipedia.org/wiki/CleanMyMac)
- Roundups: [Cindori, best Mac cleaners 2026](https://cindori.com/reviews/best-mac-cleaner-apps-2026), [Crumb, CleanMyMac alternatives](https://cleanwithcrumb.com/blog/cleanmymac-alternatives/), [DiskCleaner, safer cleaners](https://www.diskcleaner.pro/blog/cleanmymac-alternative/), [Toolradar, free cleaners](https://toolradar.com/blog/best-free-mac-cleaners)
- Mole: [github.com/tw93/Mole](https://github.com/tw93/Mole) (README, `bin/clean.sh`, `bin/optimize.sh`, `bin/purge.sh`, `bin/uninstall.sh`, `lib/optimize/tasks.sh`, `lib/clean/user.sh`), [recca0120 review](https://recca0120.github.io/en/2026/03/09/mole-macos-cleaner/)
- Pearcleaner: [github.com/alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner) (`Logic/AppPathsFetch.swift`, `Logic/Locations.swift`, `Logic/HelperToolManager.swift`, `PearcleanerSentinel/FileWatcher.swift`)
- OnyX: [Titanium Software](https://titanium-software.fr/en/onyx.html), [Wikipedia](https://en.wikipedia.org/wiki/OnyX)
- Periodic removal: [heise: macOS 15 removes periodic](https://www.heise.de/en/news/Cleanup-scripts-macOS-15-removes-periodic-but-no-longer-needs-it-10007870.html), [Eclectic Light](https://eclecticlight.co/tag/periodic/)
- Sensei: [cindori.com/sensei](https://cindori.com/sensei)
- DaisyDisk: [purgeable space](https://daisydiskapp.com/guide/purgeable-space), [hidden space](https://daisydiskapp.com/guide/hidden-space), [snapshots](https://daisydiskapp.com/guide/snapshots)
- Snapshots: [Eclectic Light, take control of snapshots](https://eclecticlight.co/2026/09/09/take-control-of-snapshots/), [Mole guide](https://mole.fit/blog/how-to-delete-local-time-machine-snapshots-mac)
- DevCleaner: [Product Hunt, DevCleaner 1.8](https://www.producthunt.com/p/devcleaner-reclaim-gbs-from-dev-tools/devcleaner-1-8-0-now-cleans-up-your-ai-coding-tools-too), [Mole Xcode guide](https://mole.fit/blog/how-to-clean-up-xcode-mac.md)
- App Tamer: [stclairsoft.com/AppTamer](https://stclairsoft.com/AppTamer/index.html), [sspai deep dive](https://sspai.com/prime/story/manage-macos-background-activities-with-app-tamer)
- KnockKnock: [objective-see.org](https://objective-see.org/products/knockknock.html); BTM: [Apple deployment guide](https://support.apple.com/guide/deployment/depdca572563), [Eclectic Light, login & background items](https://eclecticlight.co/2025/12/03/manage-login-and-background-items/)
- Stats: [github.com/exelban/stats](https://github.com/exelban/stats)
- Debloat limits: [Eclectic Light, can you disable Spotlight and Siri in Tahoe?](https://eclecticlight.co/2026/01/16/can-you-disable-spotlight-and-siri-in-macos-tahoe/), [RemoveMacAI](https://github.com/omlahore/RemoveMacAI/wiki)
- Privilege: [Apple forums, migrating from SMJobBless](https://developer.apple.com/forums/thread/725811), [unsigned daemon on Sequoia](https://developer.apple.com/forums/thread/756846), [SMJobBless readme](https://developer.apple.com/library/mac/samplecode/smjobbless/listings/readme_txt.html)
- Touch ID sudo: [Six Colors, sudo_local survives updates](https://sixcolors.com/post/2023/08/in-macos-sonoma-touch-id-for-sudo-can-survive-updates/)
- Gatekeeper & quarantine: [Wikipedia](https://en.wikipedia.org/wiki/Gatekeeper_(macOS)), [OSNews on 15.1](https://www.osnews.com/story/141055/bug-or-intentional-macos-15-1-completely-removes-ability-to-launch-unsigned-applications/)
- Icons: [Apple Icon Composer](https://developer-mdn.apple.com/icon-composer/), [Xojo forum, Tahoe icons + legacy](https://forum.xojo.com/t/how-to-create-app-icons-for-macos-26-and-maintain-compatibility-with-older-oss/86527)
