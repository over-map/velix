#!/usr/bin/env bash
# Sign files with the pack key (Ed25519): <file> → <file>.sig, the raw 64-byte signature over the file's exact bytes,
# which the app checks with the public key it ships (App/Data/PackSignature.swift, pipeline/keys/pack-signing.pub).
# The private key comes from $PACK_SIGNING_KEY (PEM), set only in the `pack-publish` environment. Each signature is
# checked against the committed public key before it is kept, so a wrong secret fails the run instead of every phone.
# Usage: PACK_SIGNING_KEY="$(cat key.pem)" bash pipeline/stages/sign.sh <file>…   (runs on the host: OpenSSL 3)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
[ -n "${PACK_SIGNING_KEY:-}" ] || { echo "[sign] PACK_SIGNING_KEY is not set" >&2; exit 1; }
PUB="${PACK_SIGNING_PUB:-$HERE/keys/pack-signing.pub}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
umask 077
printf '%s\n' "$PACK_SIGNING_KEY" > "$TMP/key.pem"
# The committed public key is the raw 32 bytes, base64: wrap it in Ed25519's SubjectPublicKeyInfo DER prefix.
{ printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; base64 -d < "$PUB"; } > "$TMP/pub.der"
for F in "$@"; do
  openssl pkeyutl -sign -rawin -inkey "$TMP/key.pem" -in "$F" -out "$F.sig"
  openssl pkeyutl -verify -rawin -pubin -keyform DER -inkey "$TMP/pub.der" -in "$F" -sigfile "$F.sig" >/dev/null \
    || { echo "[sign] $F: the signature doesn't match keys/pack-signing.pub (wrong PACK_SIGNING_KEY?)" >&2; exit 1; }
  echo "[sign] $F.sig"
done
