#!/bin/bash
# Builds Spruce.app (SwiftUI app + bundled `spruce` CLI) from source.
#
#   scripts/build-app.sh            build dist/Spruce.app and dist/Spruce.zip
#   scripts/build-app.sh --install  also install the app and put `spruce` on your PATH
#
# No admin rights needed: on a standard account the app goes to ~/Applications and the CLI to
# ~/.local/bin. A locally built app carries no quarantine flag, so Gatekeeper doesn't block it.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="1.0.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="$DIST/Spruce.app"

if ! command -v swift >/dev/null; then
    echo "Swift not found. Install Xcode or the Command Line Tools (xcode-select --install)." >&2
    echo "No admin on this Mac? Build on another Mac and copy dist/Spruce.zip over (see README)." >&2
    exit 1
fi

echo "==> Building (release)…"
swift build -c release --product SpruceApp
swift build -c release --product spruce
BIN="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/SpruceApp" "$APP/Contents/MacOS/Spruce"
cp "$BIN/spruce" "$APP/Contents/Helpers/spruce"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

# Signing, best first:
#   ROOT_SIGN_IDENTITY  set by CI from repository secrets: a Developer ID (notarizable) or "Root Signing"
#   "Root Signing"      the certificate from scripts/make-signing-identity.sh, if it's in your keychain
#   ad-hoc              otherwise (permissions then reset with each new build)
# Real identities get the hardened runtime, which notarization requires. ROOT_SIGN_TIMESTAMP=1 adds
# Apple's secure timestamp (also required for notarization; needs network).
IDENTITY="${ROOT_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Root Signing"'; then
    IDENTITY="Root Signing"
fi
SIGN_ARGS=(--force)
if [[ "${ROOT_SIGN_TIMESTAMP:-}" == 1 ]]; then SIGN_ARGS+=(--timestamp); else SIGN_ARGS+=(--timestamp=none); fi
if [[ -n "${ROOT_SIGN_KEYCHAIN:-}" ]]; then SIGN_ARGS+=(--keychain "$ROOT_SIGN_KEYCHAIN"); fi
if [[ -n "$IDENTITY" ]]; then
    echo "==> Signing with \"$IDENTITY\" (hardened runtime)"
    SIGN_ARGS+=(--options runtime)
    APP_ARGS=(--entitlements Resources/Spruce.entitlements)
else
    IDENTITY="-"
    APP_ARGS=()
    echo "==> Signing (ad-hoc: permissions reset with each new build; see scripts/make-signing-identity.sh)"
fi
codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" --identifier io.spruceapp.spruce-cli "$APP/Contents/Helpers/spruce"
codesign "${SIGN_ARGS[@]}" ${APP_ARGS[@]+"${APP_ARGS[@]}"} --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "    designated requirement: $(codesign -d -r- "$APP" 2>&1 | sed -n 's/.*designated => //p')"

echo "==> Zipping for your other Macs"
rm -f "$DIST/Spruce.zip"
ditto -c -k --keepParent "$APP" "$DIST/Spruce.zip"

if [[ "${1:-}" == "--install" ]]; then
    if [[ -w /Applications ]]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
    echo "==> Installing to $DEST"
    rm -rf "$DEST/Spruce.app"
    ditto "$APP" "$DEST/Spruce.app"
    # The app used to be called Burnish, then Root: drop those copies and their CLI links. Only our
    # own symlinks are removed (CERN ROOT installs a `root` command of its own).
    for old in Burnish Root; do
        rm -rf "$DEST/$old.app"
        lower="$(tr '[:upper:]' '[:lower:]' <<<"$old")"
        for link in /opt/homebrew/bin/$lower /usr/local/bin/$lower "$HOME/.local/bin/$lower"; do
            if [[ -L "$link" && "$(readlink "$link")" == *"/$old.app/"* ]]; then rm -f "$link"; fi
        done
    done

    for dir in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
        if [[ -d "$dir" && -w "$dir" ]] || [[ "$dir" == "$HOME/.local/bin" ]]; then
            if [[ -e "$dir/spruce" && "$(readlink "$dir/spruce" 2>/dev/null)" != *"/Spruce.app/"* ]]; then
                echo "==> $dir/spruce already exists and isn't Spruce's; skipping the CLI link"
                continue
            fi
            mkdir -p "$dir"
            ln -sf "$DEST/Spruce.app/Contents/Helpers/spruce" "$dir/spruce"
            echo "==> CLI linked at $dir/spruce"
            case ":$PATH:" in *":$dir:"*) ;; *) echo "    add to your shell: export PATH=\"$dir:\$PATH\"";; esac
            break
        fi
    done
    echo "Done. Open Spruce from $DEST, or run: spruce doctor"
else
    echo "Done: $APP  (run with --install to install)"
fi
