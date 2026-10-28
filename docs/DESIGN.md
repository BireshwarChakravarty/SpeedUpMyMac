# Burnish: product & design

## Name

**Burnish** (verb): *to polish metal by rubbing until it shines.*

Every Mac is a slab of aluminium. Burnish takes it back to the factory shine. It's one word with no "Clean/My/Mac/Pro" clutter, which is the opposite of the genre's naming. The CLI reads naturally too: `burnish clean`, `burnish purge`, `burnish fleet`. A search for Mac apps called Burnish turned up nothing.

Tagline: **"Deep-clean every Mac you own."**

Runner-up names, if you want to swap: *Lustre*, *Fathom* (depth), *Kiln*, *Sift*.

## Product principles

1. **Show the receipt.** Nothing is deleted without an itemised list of exactly what goes, how big it is, and whether it goes to the Trash or is gone for good. This fixes the #1 complaint about CleanMyMac.
2. **User first, sudo second.** Everything that can run as you runs as you. The **Sudo toggle** unlocks the system scope. On a standard account (your M3) the toggle is disabled with an explanation, and the app is still fully useful.
3. **Only fix what's broken.** Maintenance tasks probe first. Spotlight gets rebuilt only if search is actually slow, DNS gets flushed only when no VPN is up, permissions get reset only when ownership is actually wrong. That idea comes from Mole.
4. **No placebo.** Burnish doesn't "free RAM", repair permissions, or run periodic scripts on macOS 15+. Where an action has little real effect, the UI says so.
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
- **Future:** the `PrivilegeRunner` protocol has room for an `SMAppService.daemon` helper if you ever sign Burnish with a Developer ID.

## Visual design: "Liquid Glass, instrument-grade"

Burnish targets **macOS 26 Tahoe's Liquid Glass** language, so it looks native on your M4 and M6 and still works on Sonoma/Sequoia, which fall back to `.regularMaterial`.

**Layout:** a `NavigationSplitView` with a translucent sidebar (SF Symbols, grouped into *Clean*, *Speed*, *Protect*, *Fleet*). The content area is a scroll of **glass cards**. Each module has one hero metric at the top (a big rounded number such as "18.4 GB reclaimable") and a single primary action. The toolbar holds the **Sudo capsule** (lock-shield icon, amber when armed) and the scan button.

**Typography:**
- *SF Pro Rounded* for hero numbers, which keeps them friendly rather than clinical
- *SF Pro* for body text
- *SF Mono* for paths and the privileged-script preview

**Colour tokens:**

| Token | Light | Dark | Use |
|---|---|---|---|
| `polish` gradient | `#2FD4B5 → #2F8CFF → #6A5CFF` | same, +8% luminance | Primary CTA, score ring, icon swirl |
| `safe` | `#16A34A` | `#34D399` | Safe-to-remove items |
| `review` | `#D97706` | `#FBBF24` | Needs a look (orphans, large files) |
| `risky` | `#DC2626` | `#F87171` | Destructive or irreversible |
| `sudo` | `#B45309` | `#F59E0B` | Sudo toggle armed, system-scope rows |
| `ink` | `#0B1220` | `#E6EDF7` | Primary text |
| `graphite` | `#F4F6FA` | `#0B0F17` | Window backdrop under glass |

**Motion:** the score ring sweeps once after a scan. Rows that get removed slide out with a burnish "glint" (a quick specular sweep). Everything respects *Reduce Motion*.

**Signature visuals:**
- **Space Lens** is a sunburst (DaisyDisk-style) drawn with SwiftUI `Canvas`, coloured by the polish gradient at depth.
- **The receipt sheet** looks like a printed receipt: items, sizes, the destination (Trash, delete, or root), and a collapsible "script that will run as root".
- **Fleet** uses device cards showing a chip badge (M3 · M4 · M6), an *Admin*/*Standard* tag, a free-space bar and a health ring.

## Icon

![Burnish icon](../Assets/AppIcon-1024.png)

File: `Assets/AppIcon.svg`. The layered sources for Icon Composer are in `Assets/IconLayers/` (background, swoosh, glint).

- **Shape:** the standard macOS rounded square (1024 canvas, 824 body, 100 px margin, corner radius ≈ 186), with a soft drop shadow.
- **Background layer:** deep graphite-titanium, a radial gradient `#2E3D5C → #080B12`. Horizontal brushed-metal grain and a faint diagonal reflection band make it read as anodized aluminium, the thing being burnished.
- **Swoosh layer** (the hero): a tapered polishing stroke, pointed at both ends and thick in the middle, sweeping from lower-left up to the top-right. It's filled with the `polish` gradient (mint `#2FD4B5` → azure `#2F8CFF` → violet `#8A6CFF`), with a soft glow and a top specular. In Icon Composer, set it to **Liquid Glass** (translucency ~40%, specular on) so Tahoe refracts it.
- **Glint layer:** a large four-point sparkle where the stroke ends, plus a small secondary one, both white with bloom. That's the shine the polish leaves behind.
- **Why not a broom or trash can:** every competitor uses one. A swipe plus a sparkle says "polish", reads at 16 px as a bright curve and a dot on dark, and keeps its silhouette in Tahoe's tinted and clear icon modes.

`scripts/build-icon.sh` regenerates `AppIcon.icns` from the SVG on macOS (Quick Look → sips → iconutil). A pre-built `Assets/AppIcon.icns` and `.iconset` are committed, so the app builds without that step.

## Module map

| Sidebar group | Module | Hero metric | Primary action |
|---|---|---|---|
| — | **Smart Scan** | Health score + reclaimable | Scan / Burnish now |
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
