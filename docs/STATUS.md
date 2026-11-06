# Project status: where Spruce stands

_Last updated: 6 Nov 2026, after the Spruce rename and redesign on branch `claude/clever-johnson-pnrg7t`._

## What Spruce is
Spruce is a native macOS cleaner. It was previously named Spruce, and before that Burnish. It has:
- a SwiftUI app (`Sources/SpruceApp`);
- a CLI called `spruce` (`Sources/spruce`);
- an engine that also builds on Linux (`Sources/SpruceCore`), covered by 74 tests.

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
- **Rename to Spruce:**
  - new `#` + cursor icon (`Assets/AppIcon.svg`, `.icns`, Icon Composer layers);
  - settings, logs, iCloud fleet folder and schedule migrate automatically from the old name;
  - `build-app.sh --install` never overwrites a `spruce` command it didn't create, and removes the old `root` link only if it pointed into Root.app (CERN ROOT also installs a `root`).
- **Native redesign (approved mock):**
  - SF Pro type, plain grouped surfaces, a floating sidebar, and lime used only for the main action;
  - synthesized sound effects;
  - real screenshots in `docs/screenshots/`.
- **CI** (`.github/workflows/ci.yml`):
  - builds and tests on macOS and Linux;
  - packages `Spruce.zip` as the **Spruce** artifact;
  - runs a **screenshot tour**: `ROOTAPP_TOUR=<dir>` makes the app scan and show every page while CI captures each one. Screenshots go into the **Screenshots** artifact, and as base64 between `@@SHOT`/`@@END` markers in the job log.

## macOS 27 (Golden Gate) support
macOS 27.2 shipped on 26 Oct 2026 (build 26B123). Changes Spruce adapts to, all keyed on the running major version in `Sources/SpruceCore/System/OSFeatures.swift`:
- **Other apps' containers are denied by default.** Cleanup targets inside `Containers`/`Group Containers` are skipped with "Needs Full Disk Access" when Spruce doesn't have it; removal errors there explain the same; the Cleanup page offers Open Settings.
- **Apps can't read the TCC database; XProtect may shield app data malware targets.** The Full Disk Access probe never opens TCC.db and accepts any of several protected folders.
- **launchd won't load quarantined plists.** Startup Items flags them ("Won't load", `spruce startup fix <label>`), and the scheduled-clean agent's plist never carries the flag.
- **`spctl` purge.** New maintenance task, and an uninstall trace that runs after the files are deleted, in the same admin prompt. The exact syntax is read from `spctl`'s usage text.
- **SDK.** CI builds on GitHub's `xcode-27` image (macOS 27, Xcode 27.2) and on `macos-latest` (macOS 26). Spruce's menus are text-only, so SwiftUI 27 hiding menu-item icons changes nothing.

## Signing
`scripts/build-app.sh` signs with `ROOT_SIGN_IDENTITY` (CI imports it from the `ROOT_SIGNING_P12` / `ROOT_SIGNING_PASSWORD` secrets via `scripts/import-signing-identity.sh`), else the "Root Signing" identity in the login keychain, else ad-hoc. `scripts/make-signing-identity.sh` creates that certificate on the user's Mac and walks through adding the secrets. CI's "Signing self-test" proves two different builds share one designated requirement (what TCC keys permissions on).

### Notarization (ready, waiting on an Apple Developer membership)
- Real identities sign with the hardened runtime and `Resources/Spruce.entitlements` (Apple Events, for the admin prompt and quitting apps before uninstall). `ROOT_SIGN_TIMESTAMP=1` adds Apple's secure timestamp.
- `scripts/make-developer-id.sh` (run on the user's own Mac): step 1 makes a key and CSR and opens Apple's certificate page; step 2 takes the downloaded `.cer`, bundles Apple's Developer ID G2 intermediate into a `.p12`, checks the Apple ID + app-specific password with `notarytool history`, and sets `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID`.
- CI prefers `DEVELOPER_ID_P12` over `ROOT_SIGNING_P12`, then runs `scripts/notarize.sh` (notarytool submit --wait, staple, `spctl --assess`, re-zip).
- Why: the M3 is a work laptop managed by Iru (Kandji), which removes Gatekeeper's **Open Anyway**. A notarized Developer ID app is the legitimate route; IT may still need to allow it.

## Latest build
The latest green run is https://github.com/BireshwarChakravarty/SpeedUpMyMac/actions/runs/41014078042. Its **Spruce** artifact was built with Xcode 27.2 on macOS 27, signed with the "Root Signing" certificate **with the hardened runtime** (designated requirement unchanged: `identifier "io.rootapp.Root" and certificate leaf = H"021d6e02…"`, so existing permissions carry over), and the hardened app passed the full 15-page screenshot tour on macOS 27 and 26. Notarize was skipped because the Developer ID secrets don't exist yet. Start a new build any time from Actions → CI → Run workflow.

## How to see the real UI (from a cloud session)
1. Push. The `Screenshot tour` step runs at the end of the macOS job.
2. Get the job's `logs_url` (GitHub MCP `get_job_logs`, with `return_content: false`) and `curl` it to disk.
3. Decode the JPEGs between the `@@SHOT name` and `@@END` lines. Strip the timestamp prefix and any non-base64 characters, then fix the padding. The last shot sometimes arrives corrupted.

## Touch ID and the Dock (6 Nov 2026)
- **Touch ID instead of the admin password.** `TouchIDSudo` (SpruceCore) runs root scripts through `sudo -S -p '' -v` then `sudo -n /bin/sh -c`, authorized by pam_tid, with no terminal. `AdminSession` tries it first and falls back to the password dialog whenever it returns nil (not set up, lid closed, cancelled). Turned on from the one-time offer when Admin mode first goes on, Settings → Admin access, or Tweaks. Tests: fake-sudo cases, plus a real passwordless-sudo run on CI (`id -u` = 0). The fingerprint prompt itself can't run on CI (no sensor).
- **Dock click reopens the window.** SwiftUI skipped it because the menu bar panel counts as a visible window. `AppDelegate.applicationShouldHandleReopen` now raises, un-minimizes or reopens the main window. The CI tour closes the window, runs `open Spruce.app` (the same reopen event as a Dock click), and checks the window is back: `REOPEN OK`, screenshot `16-reopened-from-dock`.

## Spruce: rename and redesign (6 Nov 2026)
- **Audit and direction:** `docs/redesign/proposal.html` (published as an artifact for review). The user picked the name **Spruce** and approved the direction.
- **Rename:** Spruce.app, `io.spruceapp.Spruce`, CLI `spruce`, modules SpruceCore/SpruceApp, env vars `SPRUCE_*`. `Legacy` moves data from Root and Burnish; `Legacy.migrateDefaults` copies the old preferences domain. The bundle id changed, so Full Disk Access must be granted once more. The signing certificate keeps its name "Root Signing" (it's in the user's keychain and the repo secrets).
- **Design system:** `Module.palette` gives each section a colour; `pageModule` environment value; `IconTile`, `ModuleBackdrop`, `SpruceMark`, `SpruceChevrons`, `GlassOrb` (Design/Orb.swift); surfaces with a lit top edge; SF Pro Rounded numerals; Sudo switch renamed Admin (fingerprint when Touch ID is on).
- **Menu bar:** own floating glass panel (`StatusItemController`, NSVisualEffectView, borderless) with drag-to-uninstall (drop zone or the menu bar icon), gauges and Spruce Up.
- **Orphaned files:** Select All / Deselect All with a selection count (⇧⌘A).

## Next up / open items
- Space Lens: the "Map your disk" card sits low on the page; align it to the top.
- The remaining pages (Dev Purge, Maintenance, Startup, Fleet, History, Settings, menu bar) use the shared components but haven't had page-specific polish like Smart Scan and Cleanup.
- Uninstaller: check the detail page with an app selected. The screenshot tour doesn't select one yet.
- Install and try it on each Mac (M4, M6, M3). On first launch: **Open Anyway** (until notarized), then **Full Disk Access** (again, because of the new bundle id).
- Pages other than Smart Scan and the menu bar pick up the new system through shared components; check each in the CI screenshots and give the busiest ones (Space Lens, Uninstaller detail) page-specific polish.
- Notarization: the user joins the Apple Developer Program and runs `scripts/make-developer-id.sh`; then a CI run produces the first notarized build. Its Notarize step hasn't run for real yet.
- No pull request has been opened (none was requested).
