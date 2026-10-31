// Cloud saves (VaultViews.swift): the keyphrase, the keys made from it and the
// sealed box, in exactly the format the browser game uses, so a career sent from
// this Mac opens in a browser and the other way round.
//   keyphrase  "nfsu2-xyz-" and 8 of VaultWords' 1296 words (about 2^83), read back
//              in any case with any separators, the prefix optional
//   keys       PBKDF2-SHA-256 of the keyphrase, 100,000 rounds, a fixed salt (the
//              keyphrase is all there is): 64 bytes, an AES-256-GCM key (the first
//              32) and the server's token (the last 32, base64url).  The server
//              never sees the key.
//   box        version byte 1, a random 12-byte nonce, the AES-GCM ciphertext and
//              its tag, the context string as associated data; the plaintext is a
//              stored ZIP (SaveArchive) compressed with raw deflate.  At most
//              256 KiB, what the server takes.
// Ported from th0mk's nfsu2-web web/src/app/vault.ts (MIT).
import Foundation
import CryptoKit
import CommonCrypto
import Security

struct VaultKeys {
    let bytes: Data
    let token: String
    var key: SymmetricKey { SymmetricKey(data: bytes) }
}

enum VaultCrypto {
    static let context = Data("nfsu2-xyz keyphrase saves v1".utf8)
    static let maxBox = 256 << 10
    static let minBox = 1 + 12 + 16             // version, nonce, tag: an empty plaintext
    static let rounds: UInt32 = 100_000

    /// The keyphrase in its one spelling ("nfsu2-xyz-acid-..."), or why it is not one.
    static func normalize(_ text: String) throws -> String {
        var words = text.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
        if words.prefix(2) == ["nfsu2", "xyz"] { words.removeFirst(2) }
        guard words.count == 8, words.allSatisfy(VaultWords.set.contains) else {
            throw SaveError("Enter the eight words of a browser-compatible NFSU2 keyphrase.")
        }
        return (["nfsu2", "xyz"] + words).joined(separator: "-")
    }

    /// A new keyphrase from the system's secure random numbers (no value past the
    /// last whole multiple of the word count, which would favour the first words).
    static func newPhrase() throws -> String {
        var words = [String]()
        let limit = 65536 / VaultWords.words.count * VaultWords.words.count
        while words.count < 8 {
            var random: UInt16 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 2, &random) == errSecSuccess else { throw SaveError("Could not generate a secure keyphrase.") }
            if Int(random) < limit { words.append(VaultWords.words[Int(random) % VaultWords.words.count]) }
        }
        return (["nfsu2", "xyz"] + words).joined(separator: "-")
    }

    static func keys(_ phrase: String) throws -> VaultKeys {
        let password = Array(try normalize(phrase).utf8)
        var output = [UInt8](repeating: 0, count: 64)
        defer { output.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        let result = password.withUnsafeBytes { pass in
            context.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.bindMemory(to: Int8.self).baseAddress, password.count,
                                     salt.bindMemory(to: UInt8.self).baseAddress, context.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &output, output.count)
            }
        }
        guard result == kCCSuccess else { throw SaveError("Could not derive the encryption key.") }
        let token = Data(output[32...]).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return VaultKeys(bytes: Data(output[..<32]), token: token)
    }

    /// A fresh random nonce for every box (CryptoKit's AES.GCM.Nonce()); a fixed
    /// one only for the tests' known-answer vectors.
    static func seal(_ plain: Data, keys: VaultKeys, testNonce: Data? = nil) throws -> Data {
        let nonce = try testNonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plain, using: keys.key, nonce: nonce, authenticating: context)
        return Data([1]) + Data(nonce) + sealed.ciphertext + sealed.tag
    }
    static func open(_ box: Data, keys: VaultKeys) throws -> Data {
        let box = Data([UInt8](box))                // indices from 0, whatever slice came in
        guard (minBox...maxBox).contains(box.count), box[0] == 1 else { throw SaveError("The server returned an unsupported encrypted save.") }
        do {
            let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: box[1..<13]), ciphertext: box[13..<(box.count - 16)], tag: box.suffix(16))
            return try AES.GCM.open(sealed, using: keys.key, authenticating: context)
        } catch { throw SaveError("The cloud save could not be opened with this keyphrase.") }
    }

    static func pack(_ entries: [SaveEntry], keys: VaultKeys) throws -> Data {
        let box = try seal(SaveArchive.deflate(SaveArchive.encode(entries), inflate: false), keys: keys)
        guard box.count <= maxBox else { throw SaveError("These saves exceed the cloud's 256 KiB encrypted limit.") }
        return box
    }
    /// The ZIP in a box; inflating stops at SaveArchive's limit (a box cannot unpack
    /// into more than a backup may hold).
    static func unpack(_ box: Data, keys: VaultKeys) throws -> Data {
        try SaveArchive.deflate(open(box, keys: keys), inflate: true, limit: SaveArchive.maxTotal)
    }
}

/// "Remember this link": the keyphrase and the vault URL in the login Keychain,
/// this Mac only, readable while it is unlocked.  Only when the player ticks it.
enum VaultKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "NFSU2 Native Save Vault",
         kSecAttrAccount as String: "Explicit cloud link"]
    }
    static func remember(phrase: String, endpoint: String) throws {
        var item = query
        let data = try JSONSerialization.data(withJSONObject: ["phrase": phrase, "endpoint": endpoint])
        let status = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SaveError("Could not remember this link in Keychain.") }
        } else if status != errSecSuccess { throw SaveError("Could not update the Keychain link.") }
    }
    static func recall() throws -> (phrase: String, endpoint: String) {
        var item = query; item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let phrase = object["phrase"], let endpoint = object["endpoint"] else { throw SaveError("No saved Keychain link is available.") }
        return (phrase, endpoint)
    }
    static func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SaveError("Could not remove the Keychain link.") }
    }
}
