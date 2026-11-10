# Changelog

All notable changes to Spruce (formerly Root, and before that Burnish) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] — 2026-11-09

A new look, a live **Status** page with 90 days
of history, and an **Installers** sweep.

### Added

- **Status** (Overview → Status):
  - **Now** shows live cards for CPU, memory, load, disk, network and security, each with a chart. The disk card estimates when the disk will be full.
  - **History** charts every metric from 5 minutes to 90 days, with the average and peak for each period.
  - Spruce samples every 30 seconds while it runs (the menu bar counts), every 2 seconds while Status is open, and keeps 90 days in a local database on this Mac only.
- **Installers** (Clean → Installers):
  - Finds `.dmg`, `.pkg`, `.xip` and `.iso` files in Downloads, Desktop, Documents, Mail downloads and /Users/Shared.
  - Shows which installed app each one belongs to, how old it is and where it is.
  - Pre-selects installers for apps you already have, and anything older than a week. ISO images and mounted disk images are never pre-selected.
  - Moves selected files to the Trash after the usual receipt.

### Changed

- **New icon:** four rounded bars stacked into a spruce tree, which also read as disk-usage bars. The menu bar icon and the logo inside the app use the same mark.
- **New look:**
  - A warm, calm background with film grain, the same on every page.
  - A slim icon rail (Overview, Clean, Apps, Speed, Protect, Fleet, Settings), with each group's pages as pill tabs at the top.
  - Uppercase monospaced labels in each section's colour, flat cards with a hairline edge, and a soft sphere in each section's colour on page headers and start screens.
  - The primary button is a high-contrast pill.
- **Bundled fonts:** Geist for text and numbers, Geist Mono for labels and tabs, Cal Sans for titles (all SIL Open Font License).
- **History is now called Activity,** to make room for metric history.
- **Uninstaller is one full-width list.** Open a row to see the app's files, tick several apps and remove them with one receipt from the bar at the bottom.
- **Maintenance and Space Lens open on a start screen,** like Cleanup and Installers. Maintenance no longer runs its checks as soon as you open it.
- **The menu bar panel fits small screens.** It stops at the bottom of the screen and scrolls, instead of running off it.

### Fixed

- **Orphaned files never lists Apple's own data.** Group containers for Podcasts (`TEAMID.groups.com.apple.podcasts`) and Shortcuts (`group.is.workflow.*`) were shown as leftovers of deleted apps; so was the Swift toolchain's cache. Nothing was pre-selected, but they could have been removed by hand.
- **Tweaks presets ask first.** Balanced, Privacy, Snappy and Revert All list every change and which apps restart (the Dock, Finder) before anything happens.
- **The Safari tweak** is marked "Needs Full Disk Access" instead of failing when Spruce can't write Safari's settings.
- **Process names line up** in Processes. Names from `ps` kept leading spaces, which also stopped protected processes matching by name.
- **One colour per health score** everywhere: green 80 and up, amber 60–79, red below 60.
- **Startup Items** spacing: the switch no longer touches the item's name, and counts line up across cards. The headline matches the tab ("3 to review").
- **Long Mac names** stay on one line in Health and Fleet.
- **Activity** is named the same on its tab, heading and the confirmation screen.
- **Small layout fixes:** sub-tabs are pills that match the top tabs, Status cards line up in rows, every page has the same side margins, Dev Purge shows what it found when nothing is selected, the menu bar's uninstall card shows its size once, and the clean celebration stays up long enough to read.

## [2.0.0] — 2026-11-06 · Spruce

Root is now **Spruce**, with a new icon, a redesigned interface, Touch ID for admin steps, and a
menu bar panel you can drag apps into to uninstall them.

### ⚠️ Upgrade notes (breaking)

- **New name and identity.** The app is `Spruce.app` with bundle identifier `io.spruceapp.Spruce`
  (was `Root.app`, `io.rootapp.Root`). macOS treats it as a new app, so:
  - **Full Disk Access must be granted again**, once, in System Settings → Privacy & Security → Full Disk Access.
  - The first launch of an unnotarized download still needs **Open Anyway** (or `xattr -dr com.apple.quarantine /Applications/Spruce.app` on your own Macs).
- **Your data moves over automatically** on first launch: settings, history, tweak backups, logs,
  the scheduled clean, the iCloud fleet folder and the app's preferences (sound, appearance), from
  Root and from Burnish. Nothing is overwritten if Spruce already has its own copy.
- **The command-line tool is `spruce`**, replacing `root`. `scripts/build-app.sh --install` removes
  `Root.app` and the old `root` link, but only a link that points into `Root.app` (CERN ROOT also
  installs a `root` command and is never touched).
- **"Sudo mode" is now "Admin mode"** throughout the app. The CLI keeps its `--sudo` / `-s` flag.
- **For contributors:** Swift modules are `SpruceCore` / `SpruceApp`, the CLI target is `spruce`,
  and test/CI environment variables are `SPRUCE_*` (were `ROOTAPP_*`). The signing certificate keeps
  its name, "Root Signing", so existing keychains and repository secrets keep working.

### Added

- **Touch ID for admin steps.** With Touch ID set up for `sudo`, Spruce's admin steps ask for your
  fingerprint instead of your password, and one touch covers about the next five minutes.
  - Offered once, the first time Admin mode goes on; also in **Settings → Admin access** and **Tweaks**.
  - Uses Apple's `/etc/pam.d/sudo_local` (survives macOS updates), so `sudo` in Terminal takes your fingerprint too.
  - Falls back to the standard password dialog if Touch ID isn't available (lid closed, no Touch ID keyboard) or you cancel it.
  - **Test Touch ID** runs a harmless admin step and says how it was authorized, quoting `sudo`'s reason when the fingerprint wasn't used.
  - Every admin step is recorded in `~/Library/Logs/Spruce/admin.log` (**Show Log** in Settings).
  - If macOS blocks Spruce from writing `sudo_local`, Settings explains why and offers **Open Full Disk Access**, the equivalent Terminal command (**Copy Command**) and **Check Again**.
- **Drag-to-uninstall from the menu bar.** The menu bar panel stays open while you work in other
  apps, so you can drag an app into it from Finder, or drop it straight on the menu bar icon.
  - It lists everything the app keeps on the Mac (caches, support files, preferences, launch agents…) with the total size.
  - **Remove…** opens the usual receipt in the main window. Nothing is removed until you confirm.
  - **Details** opens the app on the Uninstaller page, and **Choose app…** picks one without dragging.
- **Menu bar panel gauges:** disk free, memory used and health score, plus **Spruce Up** for whatever the last scan found.
- **Select All for orphaned files:** a Select All / Deselect All checkbox (⇧⌘A) above the list, with a live
  count such as "3 of 12 selected · 1.4 GB".
- **Remove from Fleet:** hover a Mac's card and click ✕, or right-click → **Remove from Fleet**,
  with a confirmation. This Mac can't be removed while Spruce runs on it.
- **Smart Scan glass orb:** specks of junk drift into the orb while it scans and stay in proportion to
  what's found. The ring shows scan progress, then health. A clean Mac's orb is clear.
- **Section subtitles** in the toolbar ("Cleanup · Caches, logs, browser junk, installers and Trash").

### Changed

- **New design system**, chosen after an audit of the best-designed Mac apps (`docs/redesign/proposal.html`):
  - Each section has its own colour (Smart Scan spruce green, Cleanup sky, Uninstaller rose, Space Lens violet…). It appears in the section's sidebar icon, primary button, checkmarks, switches, bars and the light behind its page.
  - The sidebar uses coloured icon tiles, like System Settings.
  - Page headers lead with the section's icon, and numbers use SF Pro Rounded.
  - Content sits on solid surfaces with a lit top edge. Glass is kept for chrome (sidebar, toolbar, menu bar panel, toasts).
  - Smart Scan tiles carry small charts: junk by category, security issues, startup items and maintenance status.
- **New icon:** three stacked glass chevrons that read as both a spruce tree and "speed up", with
  Icon Composer layers for macOS 26/27. The menu bar icon is the same chevrons, tinted by macOS.
- **The menu bar panel is real glass** (behind-window blur) instead of a standard pop-up.
- **The Admin switch** shows a fingerprint once Touch ID is set up and glows amber while armed.
- **Each Mac has one Fleet card for good.** Its identity is now a hash of the Mac's hardware UUID and
  the account name (the UUID itself is never published), so reinstalling Spruce no longer creates a new card.
- **Error messages** stay on screen longer, wrap to four lines and can be selected and copied.
- **"Always use the dark theme"** replaces "dark aurora theme". Every page also supports light mode.

### Fixed

- **Clicking Spruce in the Dock** now brings back the main window after it was closed. Previously the Dock icon did nothing.
- **Duplicate Fleet cards** for the same Mac, left behind by earlier installs, now clear themselves the next time that Mac opens Spruce.
- **Touch ID followed by a password prompt.** Authorizing and running an admin step now happen in a
  single `sudo` call, instead of relying on `sudo` remembering an earlier fingerprint for an app without a terminal.
- **Turning on Touch ID failed with no explanation.** The setup now reports the actual cause (for example, macOS blocking the write to `/etc/pam.d`).
- **Admin prompt reliability.** If the in-app administrator prompt fails, Spruce retries with a
  separate system prompt instead of giving up, and logs both attempts.

### Security

- **Admin scripts are still built only from fixed commands and shell-quoted paths**, shown in the
  receipt before they run, and passed as an argument, never written to a file.
- **The Touch ID path never waits on a terminal.** It reads any password from an empty input, so it either uses your fingerprint or fails cleanly into the system password dialog.
- **Fleet cards identify a Mac by a hash, not its hardware UUID.**

### Known issues

- **Builds are not yet notarized,** so the first launch needs **Open Anyway** (or the `xattr` command above). Notarization is wired into CI and switches on once the Apple Developer ID secrets are added (`scripts/make-developer-id.sh`).
- **Managed work Macs** (for example, Iru/Kandji) may block unnotarized apps entirely. Use a notarized build or ask IT to approve Spruce.
- **The Touch ID setup can be blocked by macOS** ("Operation not permitted") until Spruce has Full Disk Access. Settings → Admin access offers the one-line Terminal alternative.
- **A Mac mini or Mac Studio needs a Magic Keyboard with Touch ID** for fingerprint authorization.
- **Not testable on CI runners** (no Touch ID sensor, no drag from Finder), so not yet confirmed in automated tests:
  - The fingerprint prompt itself. The authorization logic is covered by unit tests and a real `sudo` run as root.
  - Dragging an app from Finder into the menu bar panel. The panel and its scan were checked by loading an app directly.

### Verification

- CI builds and tests on **macOS 27 (Xcode 27.2 SDK)**, **macOS 26** and **Linux** (engine and CLI). **76 tests** pass on macOS.
- An automated 18-screen tour of the real app passes on both macOS versions. It covers:
  - every page, the receipt and the clean celebration;
  - the menu bar panel, empty and with an app scanned;
  - closing the window and reopening it the way a Dock click does.

## [1.1.0] — 2026-10-30 · Root

### Added

- **macOS 27 (Golden Gate) support**, built with the macOS 27.2 SDK. Behaviour keyed to the running macOS version:
  - Other apps' containers are denied by default, so those items are skipped with "Needs Full Disk Access" instead of failing.
  - The privacy database (TCC.db) is never read. Full Disk Access is detected by probing several protected folders instead.
  - launchd won't load quarantined plists. Startup Items marks them **Won't load**, and **Fix** clears the flag (`root startup fix <label>`).
  - **Clean up Gatekeeper records** (`spctl` purge) is a new maintenance task, and runs after complete uninstalls.
- **Stable code signing.** Every build is signed with the same certificate ("Root Signing", created on your
  Mac by `scripts/make-signing-identity.sh`). Full Disk Access and other permissions now survive updates.
  CI proves two builds share one designated requirement.
- **Notarization pipeline,** ready but switched off: Developer ID signing, hardened runtime, `notarytool` submission and stapling in CI. `scripts/make-developer-id.sh` sets up the certificate and secrets.
- **Run a build on demand** from GitHub Actions → CI → Run workflow.

### Changed

- **Far fewer password and permission prompts:**
  - One administrator prompt covers about five minutes of admin steps (one shared session instead of a new prompt per step).
  - Desktop, Documents and Downloads are skipped without Full Disk Access instead of making macOS ask, and the scan says so.
  - Apps are quit before uninstalling the way the Dock quits them, so macOS no longer asks "allow Root to control…".
  - Login Items are only touched when the app is actually listed there.
- **Signed builds use the hardened runtime,** with the single Apple Events entitlement the admin prompt needs.

## [1.0.0] — 2026-10-28 · Root

First release under the name Root (renamed from Burnish).

- **Cleaning:** Smart Scan, Cleanup (50 rules), Dev Purge, complete Uninstaller with verification,
  Space Lens, Processes, Maintenance, Startup Items, Tweaks, Health, Fleet and History, all with
  receipts before anything is removed.
- **Interface:** native macOS design with sound effects, plus the `root` command-line tool.
- **Migration:** settings, logs and the fleet folder move over automatically from Burnish.

[2.1.0]: https://github.com/BireshwarChakravarty/SpeedUpMyMac/compare/06075a6...c22e931
[2.0.0]: https://github.com/BireshwarChakravarty/SpeedUpMyMac/compare/8138fb2...000e70f
[1.1.0]: https://github.com/BireshwarChakravarty/SpeedUpMyMac/compare/396b95a...8138fb2
[1.0.0]: https://github.com/BireshwarChakravarty/SpeedUpMyMac/compare/9404342...396b95a
