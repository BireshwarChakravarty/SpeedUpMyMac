#!/bin/bash
# Builds Burnish.app (SwiftUI app + bundled `burnish` CLI) from source.
#
#   scripts/build-app.sh            build dist/Burnish.app and dist/Burnish.zip
#   scripts/build-app.sh --install  also install the app and put `burnish` on your PATH
#
# No admin rights needed: on a standard account the app goes to ~/Applications and the CLI to
# ~/.local/bin. A locally built app carries no quarantine flag, so Gatekeeper doesn't block it.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="1.0.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="$DIST/Burnish.app"

if ! command -v swift >/dev/null; then
    echo "Swift not found. Install Xcode or the Command Line Tools (xcode-select --install)." >&2
    echo "No admin on this Mac? Build on another Mac and copy dist/Burnish.zip over (see README)." >&2
    exit 1
fi

echo "==> Building (release)…"
swift build -c release --product BurnishApp
swift build -c release --product burnish
BIN="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/BurnishApp" "$APP/Contents/MacOS/Burnish"
cp "$BIN/burnish" "$APP/Contents/Helpers/burnish"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP/Contents/Helpers/burnish"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Zipping for your other Macs"
rm -f "$DIST/Burnish.zip"
ditto -c -k --keepParent "$APP" "$DIST/Burnish.zip"

if [[ "${1:-}" == "--install" ]]; then
    if [[ -w /Applications ]]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
    echo "==> Installing to $DEST"
    rm -rf "$DEST/Burnish.app"
    ditto "$APP" "$DEST/Burnish.app"

    for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [[ -d "$dir" && -w "$dir" ]] || [[ "$dir" == "$HOME/.local/bin" ]]; then
            mkdir -p "$dir"
            ln -sf "$DEST/Burnish.app/Contents/Helpers/burnish" "$dir/burnish"
            echo "==> CLI linked at $dir/burnish"
            case ":$PATH:" in *":$dir:"*) ;; *) echo "    add to your shell: export PATH=\"$dir:\$PATH\"";; esac
            break
        fi
    done
    echo "Done. Open Burnish from $DEST, or run: burnish doctor"
else
    echo "Done: $APP  (run with --install to install)"
fi
