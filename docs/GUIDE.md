# Burnish: user guide

Burnish deep-cleans, speeds up and protects every Mac you own, from one app.
Nothing is ever removed without a **receipt**: a list of exactly what goes, where it goes, and the admin script if one is needed.

---

## 1. Install

### Download
1. Open the repo's **Actions** tab on GitHub, open the latest green **CI** run, and download the **Burnish** artifact.
2. Safari unzips it to a folder in **Downloads**. If you see another `Burnish.zip` inside, double-click that too, until **Burnish.app** appears.

### Put it in Applications
- **On your M4 and M6 (admin):** drag **Burnish.app** into **Applications** in the Finder sidebar.
- **On the M3 (no admin):** drag it into the **Applications** folder inside your home folder (`~/Applications`). Create that folder if it isn't there.

### First launch
macOS blocks apps that aren't from a registered developer. Unblock it once:

1. Double-click Burnish. When macOS says it can't be opened, click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Burnish, and confirm.

If there's no **Open Anyway** button, run this once in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Burnish.app
```

On the M3, use `~/Applications/Burnish.app` instead.

### Give it Full Disk Access
Without it, Burnish can't see Mail, Safari, other apps' containers or the Trash.
Go to **System Settings → Privacy & Security → Full Disk Access**, click **+** and add Burnish.
The Smart Scan and Health pages also have a button that opens this setting.

---

## 2. Sudo mode

The **Sudo** switch is at the top right of every page.

| State | What happens |
|---|---|
| **Off** (grey lock) | Burnish cleans everything your account owns. System folders are listed but skipped. |
| **On** (amber, open lock) | System-level items are included too. When a job needs them, Burnish shows the exact script, then macOS asks for your password **once for that batch**. |

- **Greyed out?** That account isn't an administrator on that Mac, which is expected on the M3. Point at the switch and it explains why.
- **Check whether an account is an admin:** `id -Gn | grep -o admin` prints `admin` if it is.
- **Use your fingerprint instead of typing the password:** go to **Tweaks**, then turn on **Touch ID for sudo**. Sudo mode must be on for this.
- **From Terminal:** `burnish sudo on` turns it on permanently, and `--sudo` applies it to a single command.

---

## 3. What each page does

| Page | What it does |
|---|---|
| **Smart Scan** | Tap the orb. One scan covers junk, idle build folders, health, security, maintenance and startup items. **Burnish now** cleans only the safe items. |
| **Cleanup** | 50 cleanup rules: caches, logs, browser junk, installers, Trash and more. Items rated *Safe* are pre-selected; *Review* and *Risky* items never are. |
| **Dev Purge** | Removes `node_modules`, `target`, `.build`, Pods, venvs and similar folders from projects you haven't touched lately. Folders tracked by git are never touched. |
| **Uninstaller** | Removes apps **completely**, with no traces left (see below). Also finds files left behind by apps you deleted long ago. |
| **Space Lens** | A sunburst map of your disk (click to drill in), large and old files, and duplicate files. |
| **Processes** | Quit, pause, or move a resource hog onto the efficiency cores. |
| **Maintenance** | Runs only tasks whose check found a real problem. |
| **Startup Items** | Every launch agent and daemon, with signature checks. Disabling one is reversible. |
| **Tweaks** | Reversible macOS tweaks. Presets: *balanced*, *privacy*, *snappy*. **Revert all** restores your previous settings. |
| **Health** | Disk, memory, battery, thermals, SIP, Gatekeeper, FileVault, firewall and a health score. |
| **Fleet** | All your Macs on one page, synced through iCloud Drive, or any folder you choose for the work Mac. |
| **History** | Every removal, with its paths. |

Keyboard: **⌘R** runs Smart Scan, and **⌘1** to **⌘9** jump between pages.

---

## 4. Uninstaller: complete removal

**Remove completely, leave no trace** is on by default. When you uninstall an app, Burnish does the following:

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
   - installer receipts (`pkgutil --forget`).
4. **Verifies the result.** It rescans and shows either **"Gone without a trace"** or exactly what's left and why.

Some items need Sudo mode: system daemons, root-owned files and receipts. With Sudo on, all of them run in **one** password prompt.
Turn complete removal off, on the Uninstaller page or in Settings, to send apps to the Trash and keep their personal data instead.

The matching level picker controls how hard Burnish looks:

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
- **Reduce visual effects** gives a static background with no particles. Burnish also respects macOS **Reduce Motion**.

On a Force Touch trackpad, toggles and switches also give haptic feedback.

---

## 6. Command line

The CLI is bundled at `Burnish.app/Contents/Helpers/burnish`. `scripts/build-app.sh --install` puts it on your PATH.

```bash
burnish scan                 # what's reclaimable
burnish clean                # clean safe items (add --sudo for system items)
burnish uninstall "Zoom"     # complete removal, no traces (--keep-data to keep its data)
burnish purge                # dev build artifacts
burnish status               # health score, disk, memory, security
burnish doctor               # permissions and tools check
burnish fleet                # all your Macs
burnish schedule weekly      # unattended safe clean, never uses sudo
```

Flags: `-n` / `--dry-run` previews without removing, `-y` / `--yes` skips the confirmation, and `-j` / `--json` prints machine-readable output.

---

## 7. Safety rules Burnish never breaks

- No removal happens without a receipt you confirm.
- Protected places are never touched: system folders, Keychains, Mail, Messages, Photos, iCloud Drive, `~/.ssh` and more. Your own **Never touch** list in Settings adds to these.
- Symlink tricks are caught: every path is resolved and re-checked just before removal.
- Root runs only a script built from quoted arguments, and you can read that script in the receipt first.
- On a standard account (the M3), Burnish never asks for admin rights; it cleans what you own.
