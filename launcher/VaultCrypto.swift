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
    static func normalize(_ text: String) throws -> String {
        var words = text.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
        if words.prefix(2) == ["nfsu2", "xyz"] { words.removeFirst(2) }
        guard words.count == 8, words.allSatisfy(Set(VaultWords.words).contains) else { throw SaveError("Enter the eight words of a browser-compatible NFSU2 keyphrase.") }
        return (["nfsu2", "xyz"] + words).joined(separator: "-")
    }
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
        let phrase = try normalize(phrase), password = Array(phrase.utf8)
        var output = [UInt8](repeating: 0, count: 64)
        let result = password.withUnsafeBytes { pass in
            context.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.bindMemory(to: Int8.self).baseAddress, password.count,
                                    salt.bindMemory(to: UInt8.self).baseAddress, context.count,
                                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000, &output, output.count)
            }
        }
        guard result == kCCSuccess else { throw SaveError("Could not derive the encryption key.") }
        let token = Data(output[32...]).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return VaultKeys(bytes: Data(output[..<32]), token: token)
    }
    static func seal(_ plain: Data, keys: VaultKeys, nonce: Data? = nil) throws -> Data {
        let iv = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plain, using: keys.key, nonce: iv, authenticating: context)
        return Data([1]) + Data(iv) + sealed.ciphertext + sealed.tag
    }
    static func open(_ box: Data, keys: VaultKeys) throws -> Data {
        guard (29...maxBox).contains(box.count), box[0] == 1 else { throw SaveError("The server returned an unsupported encrypted save.") }
        do {
            let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: box[1..<13]), ciphertext: box[13..<(box.count - 16)], tag: box.suffix(16))
            return try AES.GCM.open(sealed, using: keys.key, authenticating: context)
        } catch { throw SaveError("The cloud save could not be authenticated with this keyphrase.") }
    }
    static func pack(_ entries: [SaveEntry], keys: VaultKeys) throws -> Data {
        let box = try seal(SaveArchive.deflate(SaveArchive.encode(entries), inflate: false), keys: keys)
        guard box.count <= maxBox else { throw SaveError("These saves exceed the cloud's 256 KiB encrypted limit.") }
        return box
    }
    static func unpack(_ box: Data, keys: VaultKeys) throws -> Data {
        try SaveArchive.deflate(open(box, keys: keys), inflate: true)
    }
}

enum VaultKeychain {
    private static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"NFSU2 Native Save Vault", kSecAttrAccount as String:"Explicit cloud link"] }
    static func remember(phrase: String, endpoint: String) throws {
        var item = query
        let data = try JSONSerialization.data(withJSONObject: ["phrase":phrase,"endpoint":endpoint])
        let status = SecItemUpdate(item as CFDictionary, [kSecValueData as String:data] as CFDictionary)
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
              let object = try JSONSerialization.jsonObject(with: data) as? [String:String], let phrase = object["phrase"], let endpoint = object["endpoint"] else { throw SaveError("No saved Keychain link is available.") }
        return (phrase,endpoint)
    }
    static func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SaveError("Could not remove the Keychain link.") }
    }
}
