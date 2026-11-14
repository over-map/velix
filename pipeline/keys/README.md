# Pack signing key

`pack-signing.pub`: the Ed25519 public key (raw 32 bytes, base64) that signs every region-pack `manifest.json` and the
index `packs.json` (`*.sig`: the raw 64-byte signature over the file's bytes). The app ships the same key
(`App/Data/PackSignature.swift`) and refuses anything unsigned.

The private key lives only in the GitHub secret `PACK_SIGNING_KEY` of the `pack-publish` environment, which needs
Filippo's approval for each run. Make or replace it with `tools/packkey/new-key.sh` (DECISIONS 2026-11-14).
