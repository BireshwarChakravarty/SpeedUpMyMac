# Spruce: product & design

## Name

**Spruce**, as in *spruce up*: to tidy and smarten. It says what the app does in plain English, it's short and easy to say aloud, and the icon carries both ideas: four rounded bars stacked into a spruce tree, which also read as the disk-usage bars of a cleaner.

The CLI reads naturally: `spruce clean --sudo`, `spruce uninstall Zoom`, `spruce fleet`.

Tagline: **"Spruce up every Mac you own."**

The app was called Burnish, then Root. Settings, history, logs, the fleet folder, the scheduled clean and the app's preferences move over automatically from either name (`Legacy` in `Sources/SpruceCore/Modules/Fleet.swift`). Names considered in the last round: *Halcyon*, *Fettle*, *Kestrel* (see `docs/redesign/proposal.html`).

## Product principles

1. **Show the receipt.** Nothing is deleted without an itemised list of exactly what goes, how big it is, and whether it goes to the Trash or is gone for good. This fixes the #1 complaint about CleanMyMac.
2. **User first, admin second.** Everything that can run as you runs as you. The **Admin switch** unlocks the system scope. On a standard account (your M3) the toggle is disabled with an explanation, and the app is still fully useful.
3. **Only fix what's broken.** Maintenance tasks probe first. Spotlight gets rebuilt only if search is actually slow, DNS gets flushed only when no VPN is up, permissions get reset only when ownership is actually wrong. That idea comes from Mole.
4. **No placebo.** Spruce doesn't "free RAM", repair permissions, or run periodic scripts on macOS 15+. Where an action has little real effect, the UI says so.
5. **Reversible by default.** Tweaks store the previous value, startup items get *disabled* rather than deleted, and user files go to the Trash.
6. **Fleet aware.** Each Mac publishes a small status file, so every Mac can show all of them.

## Privilege model (the Admin switch)

```
               ┌───────────── Admin switch OFF (or standard account) ─────────────┐
 scan ──► plan ┤  user-scope items ──► FileManager (trash / delete) as you        │
               └──────────────────────────────────────────────────────────────────┘
               ┌───────────── Admin switch ON (admin account) ───────────────────┐
               │  user-scope items ──► as you                                     │
               │  system-scope items ──► ONE generated /bin/sh script             │
               │      shown in the receipt ──► one auth prompt ──► runs as root   │
               └──────────────────────────────────────────────────────────────────┘
```

- **Admin detection:** checks whether you're in the `admin` group (`id -Gn`).
- **App:** with Touch ID set up for sudo (pam_tid in `/etc/pam.d/sudo_local`), runs the script through `sudo` and a fingerprint authorizes it (`TouchIDSudo`). Otherwise, or if Touch ID can't be used right now, it uses one compiled in-process AppleScript (`do shell script … with administrator privileges`). Either way the script is passed as an *argument*, never written to a temp file, and one authorization covers about five minutes.
- **CLI:** runs `sudo /bin/sh -c …`. Touch ID works once you apply the *Touch ID for sudo* tweak (`/etc/pam.d/sudo_local`).
- **The root script is built only from validated, shell-quoted paths and fixed commands.** It never comes from free-form input. That's a deliberate contrast with Pearcleaner's helper, which runs any string it's given.
- **Future:** the `PrivilegeRunner` protocol has room for an `SMAppService.daemon` helper now that Spruce can be signed with a Developer ID.

## Visual design: "warm and calm, with bright tool accents"

**Layout:** a hidden title bar over a warm coffee ground (warm paper in light mode) with a faint
corner glow and film grain, the same on every page. On the left, a slim rail: the Spruce mark,
one icon per group (Overview, Clean, Apps, Speed, Protect, Fleet) and Settings at the bottom; the
selected group is a solid tile in its accent. Across the top, the group's pages as pill tabs
(monospaced, live counts beside the name), with sound and the Admin switch on the right.

**Tool screens:** each tool starts and finishes on the same composition: a matte sphere in the
tool's accent, a Cal Sans title with one line under it, and pill actions (a white primary pill
and a dark secondary one). Results replace the title with a large monospaced reading such as
"443 MB found". Lists and dashboards sit on flat cards: a warm-white fill a few percent over the
ground and a hairline edge.

**Section accents** (`Module.palette`, light / middle / deep): Smart Scan teal, Status green,
Cleanup blue, Dev Purge gold, Installers ginger, Uninstaller coral, Space Lens lilac, Processes
amber, Maintenance violet, Startup moss, Tweaks apricot, Health red, Fleet blue, Activity stone.
Accents mark labels, icons, charts, checkmarks, switches and the selected rail tile; they never
tint the background. The `pageModule` environment value carries the current section's accent.

**Typography** (bundled, SIL Open Font License):
- *Geist Mono* for every number, for labels (uppercase with tracking) and for tabs
- *Geist* for body text and buttons
- *Cal Sans* for page and tool titles

**Colour tokens:**

| Token | Light | Dark | Use |
|---|---|---|---|
| `base` | `#F4EFE6` | `#17120A` | Window ground |
| `text` | `#221B11` | `#EDE6DA` | Warm text; secondary text is the same colour at lower opacity |
| `cardFill` | white 66% | `#F2ECE0` 7% | Cards and tiles |
| `hairline` | espresso 12% | `#F2ECE0` 10% | Card edges and dividers |
| `inverse` / `onInverse` | `#221B11` / `#F4EFE6` | white / `#0F0B05` | The primary pill |
| `safe` · `review` · `risky` | green · amber · red | | State, separate from section accents |
| `sudo` | `#B45309` | `#F0B24A` | Admin mode armed |

**Signature moments:**
- **Smart Scan:** the sphere breathes while it scans; the result reads "… found" in large mono, with Spruce Up as the white pill and a health chip below.
- **Status:** live cards for CPU, memory, load, disk, network and security, and History charts from 5 minutes to 90 days.
- **The menu bar panel:** a small dashboard (health, live CPU, memory, disk and network tiles, Spruce Up) that stays open while you drag an app onto its drop box, or onto the menu bar icon, to uninstall it.
- **Admin with Touch ID:** the switch shows a fingerprint and glows amber while unlocked.

Motion and sound: numbers count, cards rise in, pages cross-fade, and sounds are synthesized
in-app with trackpad haptics. Everything respects *Reduce Motion*, and Settings can mute sound or
reduce effects.

## Icon

![Spruce icon](../Assets/AppIcon-1024.png)

File: `Assets/AppIcon.svg`. Layered sources for Icon Composer are in `Assets/IconLayers/` (background, bars, highlights).

- **Shape:** the standard macOS rounded square (1024 canvas, 824 body, 100 px margin) with a soft drop shadow.
- **Background:** deep forest green (`#17463A → #06170F`) with a mint glow behind the top of the tree.
- **Bars** (the hero): four capsules, 100 units tall, 196 / 344 / 492 / 640 wide, stacked 124 units apart. They run from pale mint at the top to deep spruce at the bottom. Together a spruce tree; on their own, disk-usage bars. Four plain shapes keep it readable down to 16 px. In Icon Composer, set this layer to **Liquid Glass**.
- **Highlights:** a soft white line along the top of each bar.
- **In the app:** the sidebar and menu bar panel show the same mark (`SpruceMark`).
- **Menu bar:** the four bars alone, drawn as a template image so macOS tints them.

`scripts/build-icon.sh` regenerates `AppIcon.icns` from the SVG on macOS (Quick Look → sips → iconutil). The committed `.icns` and `.iconset` were rendered from the SVG, so the app builds without that step.

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
