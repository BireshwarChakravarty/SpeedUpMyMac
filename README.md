<p align="center"><img src="Assets/AppIcon-1024.png" width="160" alt="Burnish icon"></p>

<h1 align="center">Burnish</h1>
<p align="center"><b>Deep-clean every Mac you own.</b><br>
Cleanup · Dev purge · Uninstaller · Space Lens · Speed · Maintenance · Startup audit · Tweaks · Health · Fleet</p>

---

Burnish pulls the best parts of CleanMyMac, Mole, Pearcleaner, AppCleaner, OnyX, DaisyDisk, DevCleaner, App Tamer, KnockKnock, Sensei and RemoveMacAI into one free, native macOS app plus a CLI. Every deletion is itemised on a **receipt** before it happens, and every action is logged.

- **Sudo toggle.** Everything that can run as you does. Turning on Sudo mode adds system-level cleaning, maintenance and tweaks, and you authorize once per batch after seeing the exact script that will run as root. On a **standard (non-admin) account** the toggle is disabled and Burnish still cleans everything you own.
- **Works across all your Macs.** Each Mac publishes a small status file to a synced folder (iCloud Drive by default, or any Dropbox/Drive/SMB folder), and the **Fleet** view shows them side by side: chip, admin or standard account, free space, reclaimable space, health score and last clean.
- **Honest.** Burnish doesn't "free RAM", repair permissions on modern macOS, or ask you to disable SIP. Maintenance tasks check for a real symptom before they recommend themselves.

Research and design rationale: [`docs/RESEARCH.md`](docs/RESEARCH.md) · [`docs/DESIGN.md`](docs/DESIGN.md)

## Modules

| | Module | What it does | Inspired by |
|---|---|---|---|
| ✨ | **Smart Scan** | One button: junk, idle build folders, health, maintenance, startup audit → "Burnish now" | CleanMyMac Smart Care |
| 🧹 | **Cleanup** | 50 curated targets: app/browser/container caches, logs, crash reports, Xcode, Homebrew, npm/yarn/pnpm/pip/cargo/go, Mail downloads, iOS firmware, installers, Trash; system caches/logs with sudo | Mole, CleanMyMac, BleachBit |
| 🔨 | **Dev Purge** | `node_modules`, `target`, `.build`, `Pods`, venvs, `.next`… in your project roots; skips git-tracked and recently active projects | Mole purge, npkill, DevCleaner |
| 🗑 | **Uninstaller** | App + leftovers (strict / enhanced / deep matching, container metadata, launch agents unloaded first), orphaned files, Trash Sentinel | Pearcleaner, AppCleaner |
| 🔭 | **Space Lens** | Sunburst disk map with a collector, large & old files, SHA-256 duplicate finder | DaisyDisk, GrandPerspective, Gemini |
| ⚡ | **Processes** | Top CPU/memory; quit, pause (SIGSTOP), push to efficiency cores | App Tamer |
| 🔧 | **Maintenance** | DNS flush (skipped on VPN), Spotlight rebuild (only if slow), Launch Services, Quick Look, icon/font caches, corrupt prefs, DB vacuum, snapshot thinning, XProtect update | OnyX, Mole optimize |
| ⏻ | **Startup Items** | Every launch agent/daemon with signing status; reversible disable | KnockKnock, LaunchControl |
| 🎛 | **Tweaks** | 26 reversible `defaults` tweaks with presets *Balanced / Privacy / Snappy*; Touch ID for sudo | RemoveMacAI, TinkerTool |
| ❤️ | **Health** | Score, storage incl. purgeable/snapshots, memory pressure, swap, battery health, SMART, SIP/Gatekeeper/FileVault/Firewall/XProtect | Sensei, Stats |
| 💻 | **Fleet** | All your Macs on one screen | — |
| 🕘 | **History** | Every removal with its paths | Mole op log |

## Install

### On a Mac where you're an admin (M4, M6)

```bash
git clone https://github.com/bireshwarchakravarty/SpeedUpMyMac.git
```

```bash
cd SpeedUpMyMac && scripts/build-app.sh --install
```

This needs Xcode or the Command Line Tools (`xcode-select --install`). Then open **Burnish**, grant it **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access) so it can see Mail, Safari, other apps' containers and the Trash, and optionally run `burnish touchid on` to use Touch ID for sudo.

### On a Mac where you're *not* an admin (M3)

You need neither admin rights nor a Developer ID:

1. If the Command Line Tools are already installed there, run the same two commands. The app installs to `~/Applications` and the CLI to `~/.local/bin`.
2. Otherwise build on your M4, copy `dist/Burnish.zip` over, and unpack it into your own Applications folder:

```bash
ditto -x -k ~/Downloads/Burnish.zip ~/Applications
```

```bash
xattr -dr com.apple.quarantine ~/Applications/Burnish.app
```

Removing the quarantine flag from your own copy needs no admin rights. Copying with `scp`/`rsync` doesn't add the flag in the first place.

On the standard account the Sudo toggle shows as unavailable. Cleanup, Dev Purge, user-owned app uninstalls, orphans, Space Lens, process control, user-level maintenance, user tweaks, startup agents in your session, Health, Fleet and scheduled cleaning all still work. A managed work Mac may block Full Disk Access via MDM. Burnish then skips the protected folders and says so.

### Fleet setup

Each Mac publishes to `iCloud Drive/Burnish/machines/` automatically. On a Mac without your personal iCloud, point it at any synced folder:

```bash
burnish fleet folder ~/Dropbox/Burnish
```

Put `shared-settings.json` (`{"ignorePaths": […], "purgeRoots": […]}`) in that folder to share an ignore list and project roots across every Mac.

## CLI

```bash
burnish status
```

```bash
burnish clean --dry-run
```

```bash
burnish clean --sudo --include-review
```

```bash
burnish purge
```

```bash
burnish uninstall "Some App" --level deep
```

```bash
burnish optimize --list
```

```bash
burnish tweaks apply balanced
```

```bash
burnish fleet
```

```bash
burnish schedule weekly
```

`burnish help` lists everything. `-n/--dry-run` previews, `-y/--yes` skips prompts, `-j/--json` prints machine-readable output, and `-s/--sudo` includes system items. Burnish refuses to run *as* root and asks for admin rights only for the steps that need them.

## Safety model

- **Protected forever:** `/System`, `/usr`, `/bin`, Keychains, iCloud Drive, CloudStorage, Mail and Messages stores, Photos libraries, Safari data, TCC, `~/.ssh`, and your top-level folders. Symlinks that resolve into those locations are refused too.
- **Receipts:** every destructive action lists its items, sizes and destination (Trash, delete, or as admin) first.
- **Trash by default** for apps, user files and anything personal. Regenerable caches are deleted outright, because sending them to the Trash wouldn't free anything.
- **One root script per batch:** it's built only from fixed commands and shell-quoted paths, shown to you, and passed to the authorization prompt as an argument (never written to a temp file).
- **Never by default:** Xcode archives, device backups, AI model caches and snapshot thinning are marked *risky*, and nothing marked *review* or *risky* is pre-selected.
- **Your ignore list:** Settings → Never touch, or `ignorePaths` in the shared settings.

## Development

```bash
swift build && swift test
```

The engine (`BurnishCore`) and CLI build on Linux too, so the 48 tests also run there in CI. The SwiftUI app target builds on macOS only.

```
Sources/BurnishCore   engine: catalog, scanner, safety, cleaner, privilege, modules
Sources/burnish       CLI
Sources/BurnishApp    SwiftUI app (macOS 14+, Liquid Glass on macOS 26)
Assets/               icon SVG, layered Icon Composer sources, .icns
scripts/              build-app.sh, build-icon.sh
```
