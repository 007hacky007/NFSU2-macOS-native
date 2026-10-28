import Foundation
import CryptoKit

@main struct VaultTests {
    static func main() throws {
        let phrase = "nfsu2-xyz-acid-acorn-acre-acts-afar-affix-aged-agent"
        let keys = try VaultCrypto.keys(phrase)
        let normalized = try VaultCrypto.normalize("ACID acorn acre acts afar affix aged agent"); assert(normalized == phrase)
        assert(VaultWords.words.count == 1296)
        let plain = Data("browser-compatible test".utf8)
        let box = try VaultCrypto.seal(plain, keys: keys, nonce: Data(0..<12))
        let opened = try VaultCrypto.open(box, keys: keys); assert(opened == plain)
        var corrupt = box; corrupt[15] ^= 1
        do { _ = try VaultCrypto.open(corrupt, keys: keys); fatalError("Accepted corrupt box") } catch { }
        let compressed = try SaveArchive.deflate(plain, inflate: false)
        let inflated = try SaveArchive.deflate(compressed, inflate: true); assert(inflated == plain)
        let options = SaveEntry(path: "settings.ini", data: Data("fps = 30\nNFSU2_PAD=off\nlanguage=German\n".utf8))
        let filtered = VaultPayload.filtered([options,SaveEntry(path:"registry.txt",data:Data()),SaveEntry(path:"gamefile.bin",data:Data()),SaveEntry(path:"shot.png",data:Data()),SaveEntry(path:"NFS Underground 2/TEST DVD 1/TEST DVD 1",data:Data())])
        assert(filtered.count == 1)
        let text = String(decoding:filtered[0].data,as:UTF8.self)
        assert(!text.contains("fps =") && !text.contains("NFSU2_PAD") && text.contains("language=German"))
        let mergedZip = try VaultPayload.restorable(filtered,local:[options])
        let merged = try SaveArchive.decode(mergedZip)
        assert(String(decoding:merged[0].data,as:UTF8.self).contains("fps = 30"))
        let output = CommandLine.arguments[1]
        let json: [String:String] = ["phrase":phrase,"token":keys.token,"key":keys.bytes.base64EncodedString(),"plain":plain.base64EncodedString(),"box":box.base64EncodedString(),"deflated":compressed.base64EncodedString()]
        try JSONSerialization.data(withJSONObject: json, options: .sortedKeys).write(to: URL(fileURLWithPath: output))
        print("vault: phrase, AES-GCM authentication, compression and vector generation passed")
    }
}
