#!/bin/bash
# Offline test of bendcnc-install.sh signature/checksum/install logic (WSL).
set -u
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/pkg"; printf '#!/bin/sh\n' > "$T/pkg/prototype"; chmod +x "$T/pkg/prototype"
tar -cf "$T/app.tar" -C "$T/pkg" .
SHA=$(sha256sum "$T/app.tar" | cut -d' ' -f1)
openssl genpkey -algorithm ed25519 -out "$T/k.pem" 2>/dev/null
PUB=$(openssl pkey -in "$T/k.pem" -pubout -outform DER | tail -c 32 | base64 -w0)
b64u() { base64 -w0 | tr '+/' '-_' | tr -d '='; }
mk() { local p; p=$(printf '%s' "$1" | b64u); printf '%s' "$p" > "$T/p"
       openssl pkeyutl -sign -inkey "$T/k.pem" -rawin -in "$T/p" | b64u > "$T/s"; echo "$p.$(cat "$T/s")"; }
GOOD=$(mk "{\"object\":\"a\",\"sha256\":\"$SHA\",\"version\":\"1\"}")
BADSHA=$(mk "{\"object\":\"a\",\"sha256\":\"$(printf '0%.0s' {1..64})\",\"version\":\"1\"}")
fail=0
run() { BENDCNC_TEST_PUBKEY_B64="$PUB" BENDCNC_TEST_APP_DIR="$T/app" bash ./bendcnc-install.sh "file://$T/app.tar" "$1" >/dev/null 2>&1; echo $?; }
chk() { [ "$2" = "$3" ] && echo "PASS $1" || { echo "FAIL $1 (got $2 want $3)"; fail=1; }; }
chown() { :; }; export -f chown
chk good "$(run "$GOOD")" 0
[ -x "$T/app/prototype" ] && echo "PASS installed" || { echo "FAIL installed"; fail=1; }
chk badsha "$(run "$BADSHA")" 13
# Published releases are .tar.zst; GNU tar auto-detects the compression.
zstd -q -19 "$T/app.tar" -o "$T/app.tar.zst"; mv "$T/app.tar.zst" "$T/app.tar"; rm -rf "$T/app"
GOODXZ=$(mk "{\"object\":\"a\",\"sha256\":\"$(sha256sum "$T/app.tar" | cut -d' ' -f1)\",\"version\":\"1\"}")
chk good-zst "$(run "$GOODXZ")" 0
chk tampered "$(run "${GOOD%.*}x.${GOOD#*.}")" 10
exit $fail
