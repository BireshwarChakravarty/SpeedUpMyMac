#!/bin/bash
# Sends a Developer ID-signed Root.app to Apple's notary service, staples the ticket, checks that
# Gatekeeper accepts it, and rebuilds dist/Root.zip from the stapled app.
#
#   NOTARY_APPLE_ID=you@example.com NOTARY_PASSWORD=<app-specific password> NOTARY_TEAM_ID=ABCDE12345 \
#       scripts/notarize.sh dist/Root.app
set -euo pipefail
APP="${1:-dist/Root.app}"
: "${NOTARY_APPLE_ID:?set NOTARY_APPLE_ID}" "${NOTARY_PASSWORD:?set NOTARY_PASSWORD}" "${NOTARY_TEAM_ID:?set NOTARY_TEAM_ID}"
AUTH=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -c -k --keepParent "$APP" "$WORK/Root-notarize.zip"

echo "==> Submitting to Apple's notary service (usually a few minutes)"
xcrun notarytool submit "$WORK/Root-notarize.zip" "${AUTH[@]}" --wait --timeout 30m --output-format json > "$WORK/result.json" || true
STATUS="$(plutil -extract status raw -o - "$WORK/result.json" 2>/dev/null || echo unknown)"
ID="$(plutil -extract id raw -o - "$WORK/result.json" 2>/dev/null || echo "")"
echo "    submission $ID: $STATUS"
if [[ "$STATUS" != "Accepted" ]]; then
    cat "$WORK/result.json" || true
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" "${AUTH[@]}" || true
    echo "Notarization failed" >&2
    exit 1
fi

echo "==> Stapling the ticket so the app opens even offline"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper's verdict"
spctl --assess --type execute -vv "$APP"

ZIP="$(dirname "$APP")/Root.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Notarized and stapled: $ZIP"
