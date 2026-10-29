# Project status: where Root stands

_Last updated: 29 Oct 2026, after the macOS 27 support commit `47fc41f` on branch `claude/clever-johnson-pnrg7t`._

## What Root is
Root is a native macOS cleaner. It was previously named Burnish. It has:
- a SwiftUI app (`Sources/RootApp`);
- a CLI called `root` (`Sources/root`);
- an engine that also builds on Linux (`Sources/RootCore`), covered by 60 tests.

It is built for three Macs: the M4 and M6, which have admin accounts, and the M3, which has a standard account.

- **User guide:** `docs/GUIDE.md`
- **Design:** `docs/DESIGN.md`
- **Competitor research:** `docs/RESEARCH.md`

## Done
- **Engine and CLI:**
  - cleanup catalog (50 rules), Dev Purge, Space Lens, processes, maintenance, startup items, tweaks, health, fleet sync, schedule and history;
  - safety layer (protected paths, symlink checks, user ignore list);
  - Sudo toggle (osascript in the app, sudo in the CLI).
- **Complete uninstall (default):**
  - deletes the app, its data and its leftovers outright;
  - clears processes, launchd jobs, preferences cache, Launch Services, privacy grants (TCC), Login Items, Dock tile and installer receipts;
  - rescans afterwards to verify nothing is left.
- **Rename to Root:**
  - new `#` + cursor icon (`Assets/AppIcon.svg`, `.icns`, Icon Composer layers);
  - settings, logs, iCloud fleet folder and schedule migrate automatically from the old name;
  - `build-app.sh --install` never overwrites a `root` command it didn't create (CERN ROOT also installs one).
- **Native redesign (approved mock):**
  - SF Pro type, plain grouped surfaces, a floating sidebar, and lime used only for the main action;
  - synthesized sound effects;
  - real screenshots in `docs/screenshots/`.
- **CI** (`.github/workflows/ci.yml`):
  - builds and tests on macOS and Linux;
  - packages `Root.zip` as the **Root** artifact;
  - runs a **screenshot tour**: `ROOTAPP_TOUR=<dir>` makes the app scan and show every page while CI captures each one. Screenshots go into the **Screenshots** artifact, and as base64 between `@@SHOT`/`@@END` markers in the job log.

## macOS 27 (Golden Gate) support
macOS 27.2 shipped on 26 Oct 2026 (build 26B123). Changes Root adapts to, all keyed on the running major version in `Sources/RootCore/System/OSFeatures.swift`:
- **Other apps' containers are denied by default.** Cleanup targets inside `Containers`/`Group Containers` are skipped with "Needs Full Disk Access" when Root doesn't have it; removal errors there explain the same; the Cleanup page offers Open Settings.
- **Apps can't read the TCC database; XProtect may shield app data malware targets.** The Full Disk Access probe never opens TCC.db and accepts any of several protected folders.
- **launchd won't load quarantined plists.** Startup Items flags them ("Won't load", `root startup fix <label>`), and the scheduled-clean agent's plist never carries the flag.
- **`spctl` purge.** New maintenance task, and an uninstall trace that runs after the files are deleted, in the same admin prompt. The exact syntax is read from `spctl`'s usage text.
- **SDK.** CI builds on GitHub's `xcode-27` image (macOS 27, Xcode 27.2) and on `macos-latest` (macOS 26). Root's menus are text-only, so SwiftUI 27 hiding menu-item icons changes nothing.

## Latest build
The latest green run is https://github.com/BireshwarChakravarty/SpeedUpMyMac/actions/runs/40828527911. Its **Root** artifact was built with Xcode 27.2 (Swift 6.4.2) on macOS 27.0.1, where all 65 tests passed and the screenshot tour ran. **Root-built-on-macOS-26** is the Tahoe-SDK build.

## How to see the real UI (from a cloud session)
1. Push. The `Screenshot tour` step runs at the end of the macOS job.
2. Get the job's `logs_url` (GitHub MCP `get_job_logs`, with `return_content: false`) and `curl` it to disk.
3. Decode the JPEGs between the `@@SHOT name` and `@@END` lines. Strip the timestamp prefix and any non-base64 characters, then fix the padding. The last shot sometimes arrives corrupted.

## Next up / open items
- Space Lens: the "Map your disk" card sits low on the page; align it to the top.
- The remaining pages (Dev Purge, Maintenance, Startup, Fleet, History, Settings, menu bar) use the shared components but haven't had page-specific polish like Smart Scan and Cleanup.
- Uninstaller: check the detail page with an app selected. The screenshot tour doesn't select one yet.
- Install and try it on each Mac (M4, M6, M3). On first launch: **Open Anyway**, then **Full Disk Access**.
- Not signed with a Developer ID, so Gatekeeper asks once per Mac. Notarizing would remove that step.
- No pull request has been opened (none was requested).
