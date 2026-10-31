// Cloud saves without a server (tests/vault.sh): keyphrases, keys, the sealed box,
// what is sent and what a download replaces; writes known-answer vectors for
// tests/vault_interop.mjs (the browser's WebCrypto must agree byte for byte).
import Foundation
import CryptoKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "PASS " : "FAIL ") + what)
    if !ok { failures += 1 }
}
func throwsError(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }

/// A profile the game would accept (SaveProfile.validate): the 20CM container, its name, checksums.
func profile(_ name: String) -> Data {
    var p = Data(repeating: 0, count: 54966)
    p.replaceSubrange(0..<4, with: Data("20CM".utf8))
    for (at, value) in [(4, 54966), (8, 8), (12, 54930), (28, 0x10d), (32, 54930)] { p.put32(at, UInt32(value)) }
    p.replaceSubrange(53797..<(53797 + name.utf8.count), with: Data(name.utf8))
    for i in 0..<48 { p.put32(36 + i * 24 + 20, UInt32.max) }
    p.put32(16, SaveProfile.checksum(Data(p[28..<36])))
    p.put32(20, SaveProfile.checksum(Data(p[36...])))
    p.put32(24, SaveProfile.checksum(Data(p[..<24])))
    return p
}
func cover() -> Data {
    var p = Data(repeating: 7, count: 1048612)
    p.replaceSubrange(0..<4, with: Data("20CM".utf8))
    for (at, value) in [(4, 1048612), (8, 8), (12, 0x100000), (28, 0x10d), (32, 0x100000)] { p.put32(at, UInt32(value)) }
    p.put32(16, SaveProfile.checksum(Data(p[28..<36])))
    p.put32(20, SaveProfile.checksum(Data(p[36...])))
    p.put32(24, SaveProfile.checksum(Data(p[..<24])))
    return p
}

@main struct VaultTests {
    static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        // keyphrases
        let phrase = "nfsu2-xyz-acid-acorn-acre-acts-afar-affix-aged-agent"
        check(VaultWords.words.count == 1296 && VaultWords.set.count == 1296, "1296 distinct keyphrase words")
        check((try? VaultCrypto.normalize("ACID acorn, acre/acts afar_affix aged agent")) == phrase, "keyphrase read in any case, any separators, prefix optional")
        check((try? VaultCrypto.normalize("NFSU2 xyz acid acorn acre acts afar affix aged agent")) == phrase, "keyphrase with its prefix")
        check(throwsError { _ = try VaultCrypto.normalize("acid acorn acre acts afar affix aged") }, "seven words refused")
        check(throwsError { _ = try VaultCrypto.normalize("acid acorn acre acts afar affix aged agent agile") }, "nine words refused")
        check(throwsError { _ = try VaultCrypto.normalize("acid acorn acre acts afar affix aged zzzz") }, "a word not in the list refused")
        var made = Set<String>()
        for _ in 0..<50 { let p = try VaultCrypto.newPhrase(); made.insert(p); _ = try VaultCrypto.normalize(p) }
        check(made.count == 50, "50 new keyphrases, all valid and different")

        // keys and the box
        let keys = try VaultCrypto.keys(phrase)
        check(keys.bytes.count == 32 && keys.token.count == 43 && !keys.token.contains("=") && !keys.token.contains("+") && !keys.token.contains("/"),
              "PBKDF2: a 32-byte key and a 43-character base64url token")
        check(try VaultCrypto.keys("acid acorn acre acts afar affix aged agent").token == keys.token, "same keyphrase, same token")
        let other = try VaultCrypto.keys("nfsu2-xyz-acid-acorn-acre-acts-afar-affix-aged-agile")
        check(other.token != keys.token && other.bytes != keys.bytes, "another keyphrase, other keys")
        let plain = Data("browser-compatible test".utf8)
        let box = try VaultCrypto.seal(plain, keys: keys, testNonce: Data(0..<12))
        check(box.count == 1 + 12 + plain.count + 16 && box[0] == 1 && Data(box[1..<13]) == Data(0..<12), "box: version 1, nonce, ciphertext, tag")
        check((try? VaultCrypto.open(box, keys: keys)) == plain, "box opens with its keyphrase")
        check((try? VaultCrypto.open(box.dropFirst(0), keys: keys)) == plain, "box opens from a slice too")
        check(throwsError { _ = try VaultCrypto.open(box, keys: other) }, "box refused with another keyphrase")
        for (at, what) in [(0, "version"), (5, "nonce"), (15, "ciphertext"), (box.count - 1, "tag")] {
            var bad = box; bad[at] ^= 1
            check(throwsError { _ = try VaultCrypto.open(bad, keys: keys) }, "box refused with a changed \(what) byte")
        }
        check(throwsError { _ = try VaultCrypto.open(Data(box.prefix(28)), keys: keys) }, "box shorter than version+nonce+tag refused")
        check(throwsError { _ = try VaultCrypto.open(Data(repeating: 1, count: VaultCrypto.maxBox + 1), keys: keys) }, "box over 256 KiB refused")
        let a = try VaultCrypto.seal(plain, keys: keys), b = try VaultCrypto.seal(plain, keys: keys)
        check(a[1..<13] != b[1..<13] && a != b, "every seal takes a fresh random nonce")
        let compressed = try SaveArchive.deflate(plain, inflate: false)
        check((try? SaveArchive.deflate(compressed, inflate: true)) == plain, "raw deflate round trip")
        check(throwsError { _ = try SaveArchive.deflate(SaveArchive.deflate(Data(count: 1 << 20), inflate: false), inflate: true, limit: 1 << 19) },
              "inflating stops at its limit")

        // what is sent
        let settings = SaveEntry(path: "settings.ini", data: Data("fps = 30\nNFSU2_PAD=off\nlanguage=German\n".utf8))
        let sent = VaultPayload.filtered([settings, SaveEntry(path: "registry.txt", data: Data()), SaveEntry(path: "gamefile.bin", data: Data()),
            SaveEntry(path: "shot.png", data: Data()), SaveEntry(path: "NFS Underground 2/TEST DVD 1/TEST DVD 1", data: Data()),
            SaveEntry(path: "NFS Underground 2/Talha Magazine 2/Talha Magazine 2", data: cover()),
            SaveEntry(path: "NFS Underground 2/TEST/TEST", data: profile("TEST"))])
        check(sent.map(\.path) == ["settings.ini", "NFS Underground 2/TEST/TEST"], "sent: profiles and settings.ini; no screenshots, covers, registry or LAN file")
        let text = String(decoding: sent[0].data, as: UTF8.self)
        check(!text.contains("fps =") && !text.contains("NFSU2_PAD") && text.contains("language=German"), "settings.ini sent without the device's own lines")
        let packed = try VaultCrypto.pack(sent, keys: keys)
        check(packed.count < 32 << 10, "a profile packs into a small box (\(packed.count) bytes)")
        let back = try SaveArchive.decode(VaultCrypto.unpack(packed, keys: keys))
        check(back.map(\.path) == sent.map(\.path) && back[1].data == sent[1].data, "box unpacks to the same files")
        check(throwsError { _ = try VaultCrypto.pack([SaveEntry(path: "big.bin", data: Data((0..<(300 << 10)).map { _ in UInt8.random(in: 0...255) }))], keys: keys) },
              "saves over the 256 KiB box refused before sending")

        // a download: the cloud's profiles replace this Mac's, the rest stays
        let tmp = FileManager.default.temporaryDirectory.path, real = realpath(tmp, nil)!   // no symbolic link on the way (/var, /tmp)
        defer { free(real) }
        let dir = URL(fileURLWithPath: String(cString: real)).appendingPathComponent("vault-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SaveStore(saves: dir.appendingPathComponent("NFSU2 Saves"), registry: dir.appendingPathComponent("registry"))
        func put(_ path: String, _ data: Data) throws {
            let url = store.saves.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try put("NFS Underground 2/OLD/OLD", profile("OLD"))
        try put("NFS Underground 2/MINE/MINE", profile("MINE"))
        try put("NFS Underground 2/Talha Magazine 2/Talha Magazine 2", cover())
        try put("shot.png", Data([1, 2, 3]))
        try Data("d g_CarLodLevel=2\n".utf8).write(to: store.registry)
        let cloud = [SaveEntry(path: "NFS Underground 2/MINE/MINE", data: profile("MINE")),
                     SaveEntry(path: "NFS Underground 2/CLOUD/CLOUD", data: profile("CLOUD")),
                     SaveEntry(path: "registry.txt", data: Data("d g_CarLodLevel=0\n".utf8)),
                     SaveEntry(path: "NFS Underground 2/../../escape", data: Data([0]))].filter { SaveArchive.validPath($0.path) }
        let checked = try SaveStore.validated(SaveArchive.encode(cloud)).entries
        try store.restore(VaultPayload.restorable(checked), gameRunning: { false }, cloud: true)
        let after = Set(try store.snapshot().map(\.path))
        check(after.contains("NFS Underground 2/CLOUD/CLOUD") && after.contains("NFS Underground 2/MINE/MINE"), "download: the cloud's careers are here")
        check(!after.contains("NFS Underground 2/OLD/OLD"), "download: a career only on this Mac is replaced (it is in the backup)")
        check(after.contains("NFS Underground 2/Talha Magazine 2/Talha Magazine 2") && after.contains("shot.png"), "download: covers and screenshots stay")
        check(String(decoding: try Data(contentsOf: store.registry), as: UTF8.self) == "d g_CarLodLevel=2\n", "download: this Mac's graphics options stay")
        let backups = try FileManager.default.contentsOfDirectory(atPath: store.backups.path)
        check(backups.contains { $0.hasPrefix("before-restore-") }, "download: the previous saves were backed up first")
        check(throwsError { try store.restore(VaultPayload.restorable(checked), gameRunning: { true }, cloud: true) }, "no download while the game runs")
        // a cloud ZIP whose path leaves the save folder (written by hand: encode refuses it)
        var evil = try SaveArchive.encode([SaveEntry(path: "NFS Underground 2/xx/xx", data: profile("XX")),
                                           SaveEntry(path: "zz/escape", data: Data([0]))])
        let zz = Data("zz/escape".utf8)
        while let r = evil.range(of: zz) { evil.replaceSubrange(r, with: Data("../escape".utf8)) }
        check(throwsError { _ = try SaveStore.validated(evil) }, "a cloud ZIP with a path out of the save folder refused")
        let kept = try store.keepArchive(SaveArchive.encode(cloud), label: "cloud-copy")
        check(kept.lastPathComponent.hasPrefix("cloud-copy-") && FileManager.default.fileExists(atPath: kept.path), "Keep both copies: the cloud ZIP in the backups folder")

        // vault addresses
        check((try? VaultAPI.endpoint("https://nfsu2.xyz/vault")) != nil, "https vault URL accepted")
        check((try? VaultAPI.endpoint("http://127.0.0.1:8080/vault")) != nil && (try? VaultAPI.endpoint("http://localhost:1/vault")) != nil,
              "plain http to this Mac accepted")
        for bad in ["http://example.com/vault", "ftp://example.com/vault", "https://user:pw@example.com/vault", "https://example.com/vault?x=1",
                    "https://example.com/vault#a", "https://example.com/vault\n", "https://example.com:99999/vault", "http://127.0.0.1.example.com/vault", ""] {
            check(throwsError { _ = try VaultAPI.endpoint(bad) }, "vault URL refused: \(bad.debugDescription)")
        }
        check(VaultAPI.defaultEndpoint(server: "wss://nfsu2.xyz/lan") == "https://nfsu2.xyz/vault", "default vault: /vault on the game server")
        check(VaultAPI.defaultEndpoint(server: "ws://127.0.0.1:8080/lan?x=1") == "http://127.0.0.1:8080/vault", "default vault of a local test server")

        if CommandLine.arguments.count > 1 {
            let json: [String: String] = ["phrase": phrase, "token": keys.token, "key": keys.bytes.base64EncodedString(), "plain": plain.base64EncodedString(),
                                          "box": box.base64EncodedString(), "deflated": compressed.base64EncodedString()]
            try JSONSerialization.data(withJSONObject: json, options: .sortedKeys).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print(failures == 0 ? "vault: all passed" : "vault: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
