#!/bin/bash
# Builds Root.app (SwiftUI app + bundled `root` CLI) from source.
#
#   scripts/build-app.sh            build dist/Root.app and dist/Root.zip
#   scripts/build-app.sh --install  also install the app and put `root` on your PATH
#
# No admin rights needed: on a standard account the app goes to ~/Applications and the CLI to
# ~/.local/bin. A locally built app carries no quarantine flag, so Gatekeeper doesn't block it.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="1.0.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="$DIST/Root.app"

if ! command -v swift >/dev/null; then
    echo "Swift not found. Install Xcode or the Command Line Tools (xcode-select --install)." >&2
    echo "No admin on this Mac? Build on another Mac and copy dist/Root.zip over (see README)." >&2
    exit 1
fi

echo "==> Building (release)…"
swift build -c release --product RootApp
swift build -c release --product root
BIN="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/RootApp" "$APP/Contents/MacOS/Root"
cp "$BIN/root" "$APP/Contents/Helpers/root"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP/Contents/Helpers/root"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Zipping for your other Macs"
rm -f "$DIST/Root.zip"
ditto -c -k --keepParent "$APP" "$DIST/Root.zip"

if [[ "${1:-}" == "--install" ]]; then
    if [[ -w /Applications ]]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
    echo "==> Installing to $DEST"
    rm -rf "$DEST/Root.app"
    ditto "$APP" "$DEST/Root.app"
    # The app used to be called Burnish: drop that copy and its CLI link.
    rm -rf "$DEST/Burnish.app"
    for old in /opt/homebrew/bin/burnish /usr/local/bin/burnish "$HOME/.local/bin/burnish"; do
        [[ -L "$old" && "$(readlink "$old")" == *"/Burnish.app/"* ]] && rm -f "$old"
    done

    for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [[ -d "$dir" && -w "$dir" ]] || [[ "$dir" == "$HOME/.local/bin" ]]; then
            # Never replace someone else's `root` (CERN ROOT installs one); only our own symlink.
            if [[ -e "$dir/root" && "$(readlink "$dir/root" 2>/dev/null)" != *"/Root.app/"* ]]; then
                echo "==> $dir/root already exists and isn't Root's; skipping the CLI link"
                continue
            fi
            mkdir -p "$dir"
            ln -sf "$DEST/Root.app/Contents/Helpers/root" "$dir/root"
            echo "==> CLI linked at $dir/root"
            case ":$PATH:" in *":$dir:"*) ;; *) echo "    add to your shell: export PATH=\"$dir:\$PATH\"";; esac
            break
        fi
    done
    echo "Done. Open Root from $DEST, or run: root doctor"
else
    echo "Done: $APP  (run with --install to install)"
fi
