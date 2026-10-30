#!/bin/bash
# Sets up notarized builds of Root, once, after you've joined the Apple Developer Program.
# Run it on one of your own Macs (not a managed work laptop). Two steps:
#
#   bash make-developer-id.sh                    1) make a certificate request and open Apple's page
#   bash make-developer-id.sh <downloaded .cer>  2) turn Apple's certificate into the GitHub secrets
#
# The private key is created here and stays in ~/.root-developer-id and your GitHub secrets.
set -euo pipefail

REPO="BireshwarChakravarty/SpeedUpMyMac"
OPENSSL=/usr/bin/openssl   # macOS's LibreSSL writes .p12 files the macOS keychain can import
DIR="$HOME/.root-developer-id"
KEY="$DIR/developer-id.key"
CSR="$DIR/Root-Developer-ID.certSigningRequest"
mkdir -p "$DIR"
chmod 700 "$DIR"

# ---------------------------------------------------------------- step 1: request
if [[ $# -eq 0 ]]; then
    if [[ ! -s "$KEY" ]]; then
        "$OPENSSL" genrsa -out "$KEY" 2048 2>/dev/null
        chmod 600 "$KEY"
    fi
    "$OPENSSL" req -new -key "$KEY" -subj "/CN=Root Developer ID/C=US" -out "$CSR"
    echo "Step 1 of 2: ask Apple for a Developer ID certificate."
    echo
    echo "  1. On the page that's opening, choose  Developer ID Application, then Continue."
    echo "  2. Profile Type: G2 Sub-CA. Upload this file (shown in Finder):"
    echo "       $CSR"
    echo "  3. Click Download. You'll get developerID_application.cer in Downloads."
    echo
    echo "Then run:  bash $0 ~/Downloads/developerID_application.cer"
    open "https://developer.apple.com/account/resources/certificates/add" 2>/dev/null || true
    open -R "$CSR" 2>/dev/null || true
    exit 0
fi

# ---------------------------------------------------------------- step 2: secrets
CER="$1"
[[ -s "$KEY" ]] || { echo "Run step 1 first (no private key in $DIR)." >&2; exit 1; }
[[ -s "$CER" ]] || { echo "Can't read $CER" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"$OPENSSL" x509 -inform DER -in "$CER" -out "$WORK/cert.pem" 2>/dev/null || cp "$CER" "$WORK/cert.pem"

# The certificate must belong to the key from step 1.
if [[ "$("$OPENSSL" x509 -noout -modulus -in "$WORK/cert.pem")" != "$("$OPENSSL" rsa -noout -modulus -in "$KEY" 2>/dev/null)" ]]; then
    echo "That certificate wasn't made from this Mac's request. Upload $CSR again and use the new download." >&2
    exit 1
fi
SUBJECT="$("$OPENSSL" x509 -noout -subject -in "$WORK/cert.pem")"
[[ "$SUBJECT" == *"Developer ID Application"* ]] || { echo "That's not a Developer ID Application certificate: $SUBJECT" >&2; exit 1; }
TEAM_ID="$(sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' <<<"$SUBJECT")"
echo "==> Developer ID Application certificate for team ${TEAM_ID:-unknown}"

# Bundle Apple's intermediate so codesign can build the chain anywhere.
curl -fsSL https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$WORK/g2.cer"
"$OPENSSL" x509 -inform DER -in "$WORK/g2.cer" -out "$WORK/g2.pem"
P12="$DIR/developer-id.p12"
PASSWORD="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -name "Root Developer ID" -inkey "$KEY" -in "$WORK/cert.pem" -certfile "$WORK/g2.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout "pass:$PASSWORD" -out "$P12"
printf '%s' "$PASSWORD" > "$DIR/password"
chmod 600 "$P12" "$DIR/password"
security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null 2>&1 || true

echo
echo "Notarization signs in to Apple with an app-specific password (not your normal one)."
echo "Make one at https://account.apple.com → Sign-In and Security → App-Specific Passwords."
open "https://account.apple.com/account/manage" 2>/dev/null || true
read -r -p "Apple ID email: " APPLE_ID
read -r -s -p "App-specific password (xxxx-xxxx-xxxx-xxxx): " APP_PASSWORD; echo
if [[ -z "$TEAM_ID" ]]; then read -r -p "Team ID (developer.apple.com → Account → Membership): " TEAM_ID; fi

if xcrun --find notarytool >/dev/null 2>&1; then
    echo "==> Checking those credentials with Apple"
    xcrun notarytool history --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID" >/dev/null \
        && echo "    OK" || { echo "Apple rejected those credentials. Check the email, password and Team ID." >&2; exit 1; }
fi

set_secret() { # name value
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
        printf '%s' "$2" | gh secret set "$1" --repo "$REPO"
        echo "    set $1"
    else
        printf '%s' "$2" | pbcopy
        echo
        echo "  New secret:  Name = $1   Secret = ⌘V (copied)   → Add secret"
        read -r -p "  Press Return when it's saved… " _
    fi
}

echo
echo "Adding five secrets to $REPO."
if ! (command -v gh >/dev/null && gh auth status >/dev/null 2>&1); then
    open "https://github.com/$REPO/settings/secrets/actions/new" 2>/dev/null || true
    echo "GitHub's New repository secret page is opening. For each one below, click New repository secret."
fi
set_secret DEVELOPER_ID_P12 "$(base64 -i "$P12")"
set_secret DEVELOPER_ID_PASSWORD "$PASSWORD"
set_secret NOTARY_APPLE_ID "$APPLE_ID"
set_secret NOTARY_PASSWORD "$APP_PASSWORD"
set_secret NOTARY_TEAM_ID "$TEAM_ID"
printf '' | pbcopy 2>/dev/null || true

echo
echo "All set. The next CI build of Root is Developer ID-signed and notarized."
echo "Keep $DIR safe: it holds your Developer ID private key."
