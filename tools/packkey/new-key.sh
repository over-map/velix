#!/usr/bin/env bash
# Make the region-pack signing key (Ed25519, M11 PR 3), once, or again to replace a lost or leaked key.
#   - The private key goes straight into the GitHub secret PACK_SIGNING_KEY of the `pack-publish` environment
#     (read from stdin, never printed) and is then deleted, unless you name a backup file.
#   - The public key is written to pipeline/keys/pack-signing.pub; commit it. The app reads the same key
#     (App/Data/PackSignature.swift), so a new key needs an app update before the next signed publish.
# Needs: OpenSSL 3 or newer (Homebrew's; macOS's LibreSSL can't sign raw Ed25519), gh logged in as over-map, and the
# `pack-publish` environment (Settings → Environments, required reviewer: you).
# Usage: tools/packkey/new-key.sh [backup.pem]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO=over-map/velix
# The first OpenSSL (3 or newer) that signs raw Ed25519 like CI does; macOS's LibreSSL can't.
OPENSSL=""
for O in /opt/homebrew/bin/openssl /usr/local/bin/openssl $(which -a openssl 2>/dev/null); do
  [ -x "$O" ] && "$O" version 2>/dev/null | grep -Eq '^OpenSSL ([3-9]|[1-9][0-9])\.' \
    && "$O" pkeyutl -help 2>&1 | grep -q -- '-rawin' && { OPENSSL="$O"; break; }
done
[ -n "$OPENSSL" ] || { echo "needs OpenSSL 3 or newer (brew install openssl)" >&2; exit 1; }
gh auth status 2>&1 | grep -A1 "account over-map" | grep -q "Active account: true" \
  || { echo "gh: switch to over-map first (gh auth switch -u over-map)" >&2; exit 1; }
gh api "repos/$REPO/environments/pack-publish" >/dev/null \
  || { echo "create the pack-publish environment first (Settings → Environments)" >&2; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
umask 077
"$OPENSSL" genpkey -algorithm ed25519 -out "$TMP/key.pem"
gh secret set PACK_SIGNING_KEY --repo "$REPO" --env pack-publish < "$TMP/key.pem"
"$OPENSSL" pkey -in "$TMP/key.pem" -pubout -outform DER | tail -c 32 | base64 > "$ROOT/pipeline/keys/pack-signing.pub"
if [ $# -ge 1 ]; then cp "$TMP/key.pem" "$1"; echo "private key backup: $1 (keep it offline)"; fi
echo "secret PACK_SIGNING_KEY set in pack-publish"
echo "public key → pipeline/keys/pack-signing.pub: $(cat "$ROOT/pipeline/keys/pack-signing.pub")"
