import CryptoKit
import Foundation

/// Region packs are signed (M11 PR 3): the pipeline signs every `manifest.json` and the index `packs.json` with
/// Ed25519 in the GitHub environment `pack-publish` (pipeline/stages/sign.sh), and the app installs nothing whose
/// signature doesn't check. A `.sig` file is the raw 64-byte signature over the file's exact bytes. The manifest holds
/// every asset's sha256, so one signature covers the whole pack.
enum PackSignature {
    /// pipeline/keys/pack-signing.pub (raw 32 bytes, base64), made by tools/packkey/new-key.sh. A new key needs an
    /// app update before the next signed publish (DECISIONS 2026-11-14).
    static let publicKeyBase64 = ""

    /// The key packs are checked against; nil until the key exists (then nothing verifies).
    static let velix: Curve25519.Signing.PublicKey? = key(base64: publicKeyBase64)

    static func key(base64: String) -> Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 32 else {
            return nil
        }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    static func verify(_ data: Data, signature: Data, key: Curve25519.Signing.PublicKey? = velix) -> Bool {
        guard let key, signature.count == 64 else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
