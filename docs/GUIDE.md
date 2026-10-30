# Root: user guide

Root deep-cleans, speeds up and protects every Mac you own, from one app.
Nothing is ever removed without a **receipt**: a list of exactly what goes, where it goes, and the admin script if one is needed.

---

## 1. Install

### Download
1. Open the repo's **Actions** tab on GitHub, open the latest green **CI** run, and download the **Root** artifact. It's built with the macOS 27.2 SDK and runs on macOS 14 Sonoma and later. **Root-built-on-macOS-26** is the same app built with the Tahoe SDK, if you ever need it.
2. Safari unzips it to a folder in **Downloads**. If you see another `Root.zip` inside, double-click that too, until **Root.app** appears.

### Put it in Applications
- **On your M4 and M6 (admin):** drag **Root.app** into **Applications** in the Finder sidebar.
- **On the M3 (no admin):** drag it into the **Applications** folder inside your home folder (`~/Applications`). Create that folder if it isn't there.

### First launch
**Notarized builds** (once the Developer ID setup below is done) open normally: double-click, and macOS confirms once that it was downloaded from the internet.

**Builds that aren't notarized** are blocked the first time. Unblock it once:

1. Double-click Root. When macOS says it can't be opened, click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Root, and confirm.

If there's no **Open Anyway** button on your own Mac, run this once in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Root.app
```

**On a work Mac managed by your company** (Iru/Kandji, Jamf, Intune…), the company may have removed **Open Anyway** on purpose. Don't work around that: use a notarized build, or ask IT to approve Root. A notarized app from a named Developer ID is what most IT teams can allow with one rule.

### Give it Full Disk Access
Without it, Root can't see Mail, Safari, other apps' containers or the Trash.
Go to **System Settings → Privacy & Security → Full Disk Access**, click **+** and add Root.
The Smart Scan and Health pages also have a button that opens this setting.

**On macOS 27 this matters more.** macOS 27 no longer asks before an app reads another app's container. It just says no. Without Full Disk Access, Root skips the cleanup items inside other apps' containers (sandboxed app caches and logs, Slack, Teams, Mail downloads) and says so on the Cleanup page. For the `root` command, add your terminal app (Terminal, iTerm, Ghostty…) instead.

---

## 2. Sudo mode

The **Sudo** switch is at the top right of every page.

| State | What happens |
|---|---|
| **Off** (grey lock) | Root cleans everything your account owns. System folders are listed but skipped. |
| **On** (amber, open lock) | System-level items are included too. When a job needs them, Root shows the exact script, then macOS asks for your password. After that, Root doesn't ask again for **about five minutes**, so a clean, a maintenance run and an uninstall in a row need one password. |

- **Greyed out?** That account isn't an administrator on that Mac, which is expected on the M3. Point at the switch and it explains why.
- **Check whether an account is an admin:** `id -Gn | grep -o admin` prints `admin` if it is.
- **Use your fingerprint instead of typing the password:** go to **Tweaks**, then turn on **Touch ID for sudo**. Sudo mode must be on for this. That applies to the `root` command in Terminal; the app uses macOS's own administrator dialog.

### Fewer permission prompts
Root is built not to interrupt you:
- **Admin password:** once, then nothing for about five minutes (see above).
- **Desktop, Documents and Downloads:** without Full Disk Access, scans skip these instead of making macOS ask, and say so. Choosing one of them yourself in Space Lens is still allowed.
- **Quitting an app before uninstalling it** uses the same mechanism as the Dock's Quit, so macOS never asks "allow Root to control…".
- **Login Items** are only touched when the app is actually listed there.

Grant **Full Disk Access** once (Smart Scan shows a card for it) and the folder questions stop for good.

### Keep permissions across updates (one-time setup)
By default each build gets a throwaway signature, so macOS treats every update as a new app and asks for Full Disk Access again. Give Root a permanent signature once:

1. On your Mac, run `bash ~/Downloads/make-signing-identity.sh` (the script is `scripts/make-signing-identity.sh` in the repo). It creates a "Root Signing" certificate in `~/.root-signing` and your login keychain.
2. It opens GitHub's **New repository secret** page and copies each value to your clipboard in turn: paste `ROOT_SIGNING_P12`, then `ROOT_SIGNING_PASSWORD`. If you use the GitHub CLI (`gh`), it sets both itself.
3. From the next build on, every Root is signed with that certificate. Grant Full Disk Access to the first signed build, and later updates keep it.

The certificate is self-signed: it keeps permissions stable, but it isn't Apple notarization, so a fresh download may still need **Open Anyway** once. Keep `~/.root-signing` safe; anyone with it could sign an app that macOS treats as Root.
- **From Terminal:** `root sudo on` turns it on permanently, and `--sudo` applies it to a single command.

### Notarized builds: no Gatekeeper warning (one-time setup)
Notarization means Apple has scanned the app and vouches for it. A notarized Root opens on any Mac with no **Open Anyway** step, and it's the version a company's IT can approve. It needs a membership in the **Apple Developer Program** (US$99 a year).

1. Join at [developer.apple.com/programs](https://developer.apple.com/programs/) as an individual. Approval usually takes a day or two.
2. On one of your own Macs (not a managed work laptop), run `bash ~/Downloads/make-developer-id.sh` (the script is `scripts/make-developer-id.sh` in the repo). It makes a certificate request and opens Apple's certificate page: choose **Developer ID Application**, profile type **G2 Sub-CA**, upload the request it shows you, and download the certificate.
3. Run `bash ~/Downloads/make-developer-id.sh ~/Downloads/developerID_application.cer`. It asks for your Apple ID and an **app-specific password** (make one at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords; never your real password), checks them with Apple, and adds five GitHub secrets: `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `NOTARY_TEAM_ID`.
4. On GitHub, open **Actions → CI → Run workflow**. The build is signed with your Developer ID, sent to Apple, and the approval is stapled into the app. The log's **Notarize** step ends with `source=Notarized Developer ID`.

The switch from the "Root Signing" certificate to the Developer ID changes Root's identity once, so grant **Full Disk Access** one more time to the first notarized build. Later builds keep it. Keep `~/.root-developer-id` safe: it holds your Developer ID private key.

---

## 3. What each page does

| Page | What it does |
|---|---|
| **Smart Scan** | Tap the orb. One scan covers junk, idle build folders, health, security, maintenance and startup items. **Clean now** cleans only the safe items. |
| **Cleanup** | 50 cleanup rules: caches, logs, browser junk, installers, Trash and more. Items rated *Safe* are pre-selected; *Review* and *Risky* items never are. |
| **Dev Purge** | Removes `node_modules`, `target`, `.build`, Pods, venvs and similar folders from projects you haven't touched lately. Folders tracked by git are never touched. |
| **Uninstaller** | Removes apps **completely**, with no traces left (see below). Also finds files left behind by apps you deleted long ago. |
| **Space Lens** | A sunburst map of your disk (click to drill in), large and old files, and duplicate files. |
| **Processes** | Quit, pause, or move a resource hog onto the efficiency cores. |
| **Maintenance** | Runs only tasks whose check found a real problem. On macOS 27 it adds **Clean up Gatekeeper records** (`spctl` purge), which forgets launch approvals for apps that are gone. |
| **Startup Items** | Every launch agent and daemon, with signature checks. Disabling one is reversible. On macOS 27, launchd silently skips a job whose plist still carries the download quarantine flag; Root marks those **Won't load** and **Fix** clears the flag. |
| **Tweaks** | Reversible macOS tweaks. Presets: *balanced*, *privacy*, *snappy*. **Revert all** restores your previous settings. |
| **Health** | Disk, memory, battery, thermals, SIP, Gatekeeper, FileVault, firewall and a health score. |
| **Fleet** | All your Macs on one page, synced through iCloud Drive, or any folder you choose for the work Mac. |
| **History** | Every removal, with its paths. |

Keyboard: **⌘R** runs Smart Scan, and **⌘1** to **⌘9** jump between pages.

---

## 4. Uninstaller: complete removal

**Remove completely, leave no trace** is on by default. When you uninstall an app, Root does the following:

1. **Stops it first.** It quits the app, terminates its helper processes and unloads its background jobs, so nothing recreates files mid-removal.
2. **Deletes every file it made**, permanently rather than into the Trash, including its data and settings:
   - the app bundle;
   - Application Support, Caches, Containers, Group Containers and Preferences (including ByHost);
   - Saved State, WebKit, HTTP Storage, Logs and crash reports;
   - hidden `/var/folders` caches and temp files;
   - launch agents, launch daemons and privileged helpers;
   - plug-ins: audio, Quick Look, Spotlight, screen savers and others;
   - files its installer package placed elsewhere;
   - command-line links pointing into the app, such as `/usr/local/bin/code`;
   - at **Deep** level, also `~/.appname` folders.
3. **Clears the traces that aren't files:**
   - preference cache (`defaults delete`, so macOS can't write the settings back);
   - Launch Services registration (removes it from the *Open With* menus);
   - privacy permissions (camera, microphone, accessibility and others);
   - Login Items entry;
   - Dock tile;
   - installer receipts (`pkgutil --forget`);
   - on macOS 27, Gatekeeper's record of the app (`spctl` purge, run after the files are gone).
4. **Verifies the result.** It rescans and shows either **"Gone without a trace"** or exactly what's left and why.

Some items need Sudo mode: system daemons, root-owned files and receipts. With Sudo on, all of them run in **one** password prompt.
Turn complete removal off, on the Uninstaller page or in Settings, to send apps to the Trash and keep their personal data instead.

The matching level picker controls how hard Root looks:

- **Strict:** exact bundle ID or app name only.
- **Enhanced** (default): adds partial matches.
- **Deep:** also matches the vendor's name, team ID and dotfolders.

Because Deep finds more, check its list before you confirm.

Apps that are part of macOS can't be removed: the system volume is sealed.

---

## 5. Look & sound

Settings (**⌘,**) → **Look & Sound**:

- **Sound effects** and **volume**. Every sound is synthesized inside the app. The speaker button in the top bar mutes them instantly.
- **Always use the dark aurora theme.** Turn this off to follow your system appearance.
- **Reduce visual effects** gives a static background with no particles. Root also respects macOS **Reduce Motion**.

On a Force Touch trackpad, toggles and switches also give haptic feedback.

---

## 6. Command line

The CLI is bundled at `Root.app/Contents/Helpers/root`. `scripts/build-app.sh --install` puts it on your PATH.

```bash
root scan                 # what's reclaimable
root clean                # clean safe items (add --sudo for system items)
root uninstall "Zoom"     # complete removal, no traces (--keep-data to keep its data)
root purge                # dev build artifacts
root status               # health score, disk, memory, security
root doctor               # permissions and tools check
root fleet                # all your Macs
root schedule weekly      # unattended safe clean, never uses sudo
```

Flags: `-n` / `--dry-run` previews without removing, `-y` / `--yes` skips the confirmation, and `-j` / `--json` prints machine-readable output.

---

## 7. Safety rules Root never breaks

- No removal happens without a receipt you confirm.
- Protected places are never touched: system folders, Keychains, Mail, Messages, Photos, iCloud Drive, `~/.ssh` and more. Your own **Never touch** list in Settings adds to these.
- Symlink tricks are caught: every path is resolved and re-checked just before removal.
- Root runs only a script built from quoted arguments, and you can read that script in the receipt first.
- On a standard account (the M3), Root never asks for admin rights; it cleans what you own.
