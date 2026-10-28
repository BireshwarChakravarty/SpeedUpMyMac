# Root: product & design

## Name

**Root**: the superuser on every Unix system, and the root of the problem.

The app's defining feature is the **Sudo toggle**: run as you, or go all the way down to `root`. The name says that, and it doubles as the promise: clean every Mac *down to the root*. It's one short word with no "Clean/My/Mac/Pro" clutter, and the CLI reads like a shell session: `root clean --sudo`, `root uninstall Zoom`, `root fleet`.

A search found no Mac cleaner called Root. Two things to know: CERN's ROOT data-analysis framework also installs a `root` command, so `scripts/build-app.sh --install` never overwrites a `root` it didn't create; and settings, logs and the fleet folder live under `Root` (they move over automatically from the app's previous name, Burnish).

Tagline: **"Clean every Mac down to the root."**

Other directions explored (see the concept canvas): *Zephyr* (airy, wind-stroke Z), *Scour* (vortex), *Pristine* (diamond).

## Product principles

1. **Show the receipt.** Nothing is deleted without an itemised list of exactly what goes, how big it is, and whether it goes to the Trash or is gone for good. This fixes the #1 complaint about CleanMyMac.
2. **User first, sudo second.** Everything that can run as you runs as you. The **Sudo toggle** unlocks the system scope. On a standard account (your M3) the toggle is disabled with an explanation, and the app is still fully useful.
3. **Only fix what's broken.** Maintenance tasks probe first. Spotlight gets rebuilt only if search is actually slow, DNS gets flushed only when no VPN is up, permissions get reset only when ownership is actually wrong. That idea comes from Mole.
4. **No placebo.** Root doesn't "free RAM", repair permissions, or run periodic scripts on macOS 15+. Where an action has little real effect, the UI says so.
5. **Reversible by default.** Tweaks store the previous value, startup items get *disabled* rather than deleted, and user files go to the Trash.
6. **Fleet aware.** Each Mac publishes a small status file, so every Mac can show all of them.

## Privilege model (the Sudo toggle)

```
               ┌───────────── Sudo toggle OFF (or standard account) ─────────────┐
 scan ──► plan ┤  user-scope items ──► FileManager (trash / delete) as you        │
               └──────────────────────────────────────────────────────────────────┘
               ┌───────────── Sudo toggle ON (admin account) ────────────────────┐
               │  user-scope items ──► as you                                     │
               │  system-scope items ──► ONE generated /bin/sh script             │
               │      shown in the receipt ──► one auth prompt ──► runs as root   │
               └──────────────────────────────────────────────────────────────────┘
```

- **Admin detection:** checks whether you're in the `admin` group (`id -Gn`).
- **App:** runs the privileged script through `osascript` (`do shell script … with administrator privileges`). The script is passed as an *argument*, never written to a temp file, so nothing can swap it before root runs it. The password or Touch ID prompt appears once per batch.
- **CLI:** runs `sudo /bin/sh -c …`. Touch ID works once you apply the *Touch ID for sudo* tweak (`/etc/pam.d/sudo_local`).
- **The root script is built only from validated, shell-quoted paths and fixed commands.** It never comes from free-form input. That's a deliberate contrast with Pearcleaner's helper, which runs any string it's given.
- **Future:** the `PrivilegeRunner` protocol has room for an `SMAppService.daemon` helper if you ever sign Root with a Developer ID.

## Visual design: "a lit terminal under Liquid Glass"

Root targets **macOS 26 Tahoe's Liquid Glass** language, so it looks native on your M4 and M6 and still works on Sonoma/Sequoia, which fall back to `.regularMaterial`.

**Layout:** a hidden title bar over a near-black aurora backdrop that drifts and tints itself per module. A glass sidebar carries the `root_` wordmark (with a blinking cursor), gradient module tiles and live badges, grouped into *Clean*, *Speed*, *Protect*, *Fleet*. The content area is a scroll of **glass cards**, each module with one hero metric and one primary action. The top bar holds the **Sudo switch** (amber when armed) and a sound toggle.

**Typography:**
- *SF Mono* (heavy) for titles, hero numbers and buttons: the terminal voice of the brand
- *SF Pro* for body text
- *SF Mono* (regular) for paths and the privileged-script preview

**Colour tokens:**

| Token | Light | Dark | Use |
|---|---|---|---|
| `brand` gradient | `#BEF264 → #84CC16 → #10B981` | same | Primary CTA (with `ink` text), score ring, scan orb, icon `#` |
| `safe` | `#16A34A` | `#34D399` | Safe-to-remove items |
| `review` | `#D97706` | `#FBBF24` | Needs a look (orphans, large files) |
| `risky` | `#DC2626` | `#F87171` | Destructive or irreversible |
| `sudo` | `#B45309` | `#F59E0B` | Sudo toggle armed, system-scope rows |
| `ink` | `#0A0F0A` | `#0A0F0A` | Text on lime (buttons, checkmarks) |
| `base` | `#F1F5EE` | `#060907` | Window backdrop under the aurora |

**Motion and sound:** the scan orb spins and ripples with real progress, numbers count up, cards rise in, pages blur across, and a confetti burst marks every clean. Sounds are synthesized in-app (glassy bells in C major, filtered-noise whooshes) with trackpad haptics. Everything respects *Reduce Motion*, and Settings can mute sound or reduce effects.

**Signature visuals:**
- **Space Lens** is a sunburst (DaisyDisk-style) drawn with SwiftUI `Canvas`, swept in ring by ring and coloured by depth.
- **The receipt sheet** looks like a printed receipt: items, sizes, the destination (Trash, delete, or root), and a collapsible "script that will run as root".
- **Fleet** uses device cards showing a chip badge (M3 · M4 · M6), an *Admin*/*Standard* tag, a free-space bar and a health ring.

## Icon

![Root icon](../Assets/AppIcon-1024.png)

File: `Assets/AppIcon.svg`. The layered sources for Icon Composer are in `Assets/IconLayers/` (background, hash, cursor).

- **Shape:** the standard macOS rounded square (1024 canvas, 824 body, 100 px margin), with a soft drop shadow.
- **Background layer:** near-black with a green cast (`#18221A → #070A08`) and a soft lime glow behind the glyph, like a terminal at night.
- **Hash layer** (the hero): the root shell's prompt, `#`, drawn as four rounded, slightly italic strokes in a lime gradient (`#ECFCCB → #A3E635 → #4D7C0F`) with a bloom. In Icon Composer, set it to **Liquid Glass** so Tahoe refracts it.
- **Cursor layer:** a lime block cursor at the baseline: the prompt is waiting for you.
- **Small sizes:** 16 and 32 px use a bolder `#` without bloom or cursor so it stays crisp.
- **Why not a broom or trash can:** every competitor uses one. `#` says root, power and precision, and it's a silhouette nobody else in the category has.

`scripts/build-icon.sh` regenerates `AppIcon.icns` from the SVG on macOS (Quick Look → sips → iconutil). A pre-built `Assets/AppIcon.icns` and `.iconset` are committed, so the app builds without that step.

## Module map

| Sidebar group | Module | Hero metric | Primary action |
|---|---|---|---|
| — | **Smart Scan** | Health score + reclaimable | Scan / Clean now |
| Clean | **Cleanup** | GB reclaimable | Review & clean |
| Clean | **Dev Purge** | GB in build artifacts + toolchain caches | Purge |
| Clean | **Uninstaller** | Apps · leftovers · orphans | Uninstall |
| Clean | **Space Lens** | Disk map, large, old, duplicate | Collect → remove |
| Speed | **Processes** | CPU / memory hogs | Quit · Pause · E-cores |
| Speed | **Maintenance** | Tasks that need running | Run selected |
| Speed | **Startup** | Agents · daemons · unsigned | Disable |
| Speed | **Tweaks** | Applied / available | Apply preset |
| Protect | **Health** | Battery, SSD, thermal, security posture | — |
| Fleet | **Fleet** | Your Macs | Sync |
| — | **History** | Freed all-time | Reveal / undo tweaks |
