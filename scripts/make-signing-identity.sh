#!/bin/bash
# Creates Root's code-signing certificate, once, on your Mac.
#
# Every build signed with the same certificate is the same app to macOS, so Full Disk Access,
# folder access and other permissions survive updates instead of resetting each time.
#
#   bash make-signing-identity.sh          create it (or reuse it), add it to your login keychain,
#                                          and walk you through adding two GitHub secrets
#   bash make-signing-identity.sh --ci DIR non-interactive: write root-signing.p12 + password into DIR
#
# The private key stays on your Mac (~/.root-signing) and in your GitHub repository's secrets.
# This is a self-signed certificate: it keeps permissions stable, but it isn't Apple notarization,
# so a freshly downloaded build may still need "Open Anyway" once.
set -euo pipefail

NAME="Root Signing"
REPO_URL="https://github.com/BireshwarChakravarty/SpeedUpMyMac"
OPENSSL=/usr/bin/openssl   # macOS's LibreSSL writes .p12 files the macOS keychain can import
CI_MODE=0
DIR="$HOME/.root-signing"
if [[ "${1:-}" == "--ci" ]]; then CI_MODE=1; DIR="${2:?usage: --ci DIR}"; fi
[[ -x "$OPENSSL" ]] || OPENSSL="$(command -v openssl)"

mkdir -p "$DIR"
chmod 700 "$DIR"
P12="$DIR/root-signing.p12"
PASSFILE="$DIR/password"

if [[ -s "$P12" && -s "$PASSFILE" ]]; then
    echo "==> Reusing the certificate in $DIR"
else
    echo "==> Creating a code-signing certificate \"$NAME\" (valid 10 years)"
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    cat > "$WORK/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Root Signing
[codesign]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
    "$OPENSSL" req -new -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
        -config "$WORK/cert.cnf" -extensions codesign \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1
    PASSWORD="$("$OPENSSL" rand -hex 16)"
    # Classic 3DES/SHA-1 PKCS#12 encryption: the format `security import` reads on every macOS.
    "$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "pass:$PASSWORD" -out "$P12"
    printf '%s' "$PASSWORD" > "$PASSFILE"
    chmod 600 "$P12" "$PASSFILE"
fi
PASSWORD="$(cat "$PASSFILE")"

if [[ $CI_MODE == 1 ]]; then
    echo "==> Wrote $P12"
    exit 0
fi

# Local builds (scripts/build-app.sh) find the identity in your login keychain automatically.
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "==> \"$NAME\" is already in your login keychain"
else
    echo "==> Adding \"$NAME\" to your login keychain (codesign may use it without asking)"
    security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
fi

echo
echo "Now give GitHub the certificate so every CI build is signed with it."
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    echo "==> GitHub CLI found; setting the two repository secrets for you"
    base64 -i "$P12" | gh secret set ROOT_SIGNING_P12 --repo "${REPO_URL#https://github.com/}"
    printf '%s' "$PASSWORD" | gh secret set ROOT_SIGNING_PASSWORD --repo "${REPO_URL#https://github.com/}"
    echo "Done. The next push builds a signed Root."
    exit 0
fi

SECRETS_URL="$REPO_URL/settings/secrets/actions/new"
echo "Two secrets, one at a time. Each value is copied to your clipboard for you."
echo
base64 -i "$P12" | pbcopy
echo "1) Opening $SECRETS_URL"
echo "   Name:   ROOT_SIGNING_P12"
echo "   Secret: press ⌘V (already copied), then click Add secret."
open "$SECRETS_URL" 2>/dev/null || true
read -r -p "   Press Return when it's saved… " _
printf '%s' "$PASSWORD" | pbcopy
echo
echo "2) Click New repository secret again."
echo "   Name:   ROOT_SIGNING_PASSWORD"
echo "   Secret: press ⌘V (already copied), then click Add secret."
read -r -p "   Press Return when it's saved… " _
printf '' | pbcopy
echo
echo "All set. The next CI build of Root is signed with \"$NAME\"."
echo "Keep $DIR safe: it's the only copy of the private key besides the GitHub secret."
