#!/bin/bash
# CI helper: puts a .p12 signing identity into a throwaway keychain that codesign can use without
# any prompt, and exports ROOT_SIGN_IDENTITY / ROOT_SIGN_KEYCHAIN for scripts/build-app.sh.
#
#   scripts/import-signing-identity.sh <file.p12> <password>
set -euo pipefail
P12="${1:?usage: import-signing-identity.sh <file.p12> <password>}"
PASSWORD="${2:?usage: import-signing-identity.sh <file.p12> <password>}"

KEYCHAIN="${RUNNER_TEMP:-$(mktemp -d)}/root-signing-$$.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a "codesign wants to use…" dialog.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# Add it to the search list, keeping the existing keychains.
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# A self-signed certificate isn't "trusted", so list identities without -v; sign by SHA-1.
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/^ *[0-9]+\)/ { print $2; exit }')"
[[ -n "$IDENTITY" ]] || { echo "No code-signing identity found in $P12" >&2; exit 1; }
echo "Imported signing identity $IDENTITY"

if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "ROOT_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
    echo "ROOT_SIGN_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
else
    echo "export ROOT_SIGN_IDENTITY=$IDENTITY ROOT_SIGN_KEYCHAIN=$KEYCHAIN"
fi
