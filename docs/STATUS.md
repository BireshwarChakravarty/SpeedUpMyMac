# Project status: where Root stands

_Last updated: 30 Oct 2026, after the notarization commit `d0c2cd9` on branch `claude/clever-johnson-pnrg7t`._

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

## Signing
`scripts/build-app.sh` signs with `ROOT_SIGN_IDENTITY` (CI imports it from the `ROOT_SIGNING_P12` / `ROOT_SIGNING_PASSWORD` secrets via `scripts/import-signing-identity.sh`), else the "Root Signing" identity in the login keychain, else ad-hoc. `scripts/make-signing-identity.sh` creates that certificate on the user's Mac and walks through adding the secrets. CI's "Signing self-test" proves two different builds share one designated requirement (what TCC keys permissions on).

### Notarization (ready, waiting on an Apple Developer membership)
- Real identities sign with the hardened runtime and `Resources/Root.entitlements` (Apple Events, for the admin prompt and quitting apps before uninstall). `ROOT_SIGN_TIMESTAMP=1` adds Apple's secure timestamp.
- `scripts/make-developer-id.sh` (run on the user's own Mac): step 1 makes a key and CSR and opens Apple's certificate page; step 2 takes the downloaded `.cer`, bundles Apple's Developer ID G2 intermediate into a `.p12`, checks the Apple ID + app-specific password with `notarytool history`, and sets `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID`.
- CI prefers `DEVELOPER_ID_P12` over `ROOT_SIGNING_P12`, then runs `scripts/notarize.sh` (notarytool submit --wait, staple, `spctl --assess`, re-zip).
- Why: the M3 is a work laptop managed by Iru (Kandji), which removes Gatekeeper's **Open Anyway**. A notarized Developer ID app is the legitimate route; IT may still need to allow it.

## Latest build
The latest green run is https://github.com/BireshwarChakravarty/SpeedUpMyMac/actions/runs/41014078042. Its **Root** artifact was built with Xcode 27.2 on macOS 27, signed with the "Root Signing" certificate **with the hardened runtime** (designated requirement unchanged: `identifier "io.rootapp.Root" and certificate leaf = H"021d6e02…"`, so existing permissions carry over), and the hardened app passed the full 15-page screenshot tour on macOS 27 and 26. Notarize was skipped because the Developer ID secrets don't exist yet. Start a new build any time from Actions → CI → Run workflow.

## How to see the real UI (from a cloud session)
1. Push. The `Screenshot tour` step runs at the end of the macOS job.
2. Get the job's `logs_url` (GitHub MCP `get_job_logs`, with `return_content: false`) and `curl` it to disk.
3. Decode the JPEGs between the `@@SHOT name` and `@@END` lines. Strip the timestamp prefix and any non-base64 characters, then fix the padding. The last shot sometimes arrives corrupted.

## Next up / open items
- Space Lens: the "Map your disk" card sits low on the page; align it to the top.
- The remaining pages (Dev Purge, Maintenance, Startup, Fleet, History, Settings, menu bar) use the shared components but haven't had page-specific polish like Smart Scan and Cleanup.
- Uninstaller: check the detail page with an app selected. The screenshot tour doesn't select one yet.
- Install and try it on each Mac (M4, M6, M3). On first launch: **Open Anyway** (until notarized), then **Full Disk Access**.
- Notarization: the user joins the Apple Developer Program and runs `scripts/make-developer-id.sh`; then a CI run produces the first notarized build. Its Notarize step hasn't run for real yet.
- No pull request has been opened (none was requested).
