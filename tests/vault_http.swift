// The cloud client against a vault server on this Mac (tests/vault_local.py):
//   vault_http seed <fixture.json> <endpoint>    404, create, get, update, stale and
//                                                 duplicate-create conflicts; writes the
//                                                 keyphrase for tests/vault_browser.mjs
//   vault_http verify <fixture.json>              what the browser code sent opens and
//                                                 passes the save checks
//   vault_http reject <unused> <endpoint> <text>  an unsafe answer (redirect, too large)
//                                                 is refused with <text> in the error
import Foundation

@main struct VaultHTTPTests {
    static func main() throws {
        let mode = CommandLine.arguments[1], fixture = URL(fileURLWithPath: CommandLine.arguments[2])
        if mode == "reject" {
            let api = VaultAPI(endpoint: try VaultAPI.endpoint(CommandLine.arguments[3]), token: String(repeating: "A", count: 43))
            do { _ = try api.get(); print("FAIL vault_http: unsafe answer accepted"); exit(1) }
            catch {
                guard error.localizedDescription.contains(CommandLine.arguments[4]) else {
                    print("FAIL vault_http: expected \"\(CommandLine.arguments[4])\", got \"\(error.localizedDescription)\""); exit(1)
                }
            }
            print("PASS vault_http: unsafe answer refused (\(CommandLine.arguments[4]))")
            return
        }
        if mode == "verify" {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: String]
            let keys = try VaultCrypto.keys(json["phrase"]!), api = VaultAPI(endpoint: try VaultAPI.endpoint(json["endpoint"]!), token: keys.token)
            let downloaded = try api.get()!
            let entries = try SaveStore.validated(VaultCrypto.unpack(downloaded.box, keys: keys)).entries
            guard entries.count == 1, SaveStore.profileName(entries[0].path) == "TEST" else { print("FAIL vault_http: browser upload"); exit(1) }
            print("PASS vault_http: the browser code's upload opens and passes the save checks here")
            return
        }
        func expect(_ ok: Bool, _ what: String) { if !ok { print("FAIL vault_http: \(what)"); exit(1) } }
        let endpoint = try VaultAPI.endpoint(CommandLine.arguments[3])
        let phrase = try VaultCrypto.newPhrase(), keys = try VaultCrypto.keys(phrase)
        let api = VaultAPI(endpoint: endpoint, token: keys.token)
        expect(try api.get() == nil, "a new keyphrase has no version (404)")
        var profile = Data(repeating: 0, count: 54966)
        profile.replaceSubrange(0..<4, with: Data("20CM".utf8))
        for (at, value) in [(4, 54966), (8, 8), (12, 54930), (28, 0x10d), (32, 54930)] { profile.put32(at, UInt32(value)) }
        profile.replaceSubrange(53797..<53801, with: Data("TEST".utf8))
        for i in 0..<48 { profile.put32(36 + i * 24 + 20, UInt32.max) }
        profile.put32(16, SaveProfile.checksum(Data(profile[28..<36])))
        profile.put32(20, SaveProfile.checksum(Data(profile[36...])))
        profile.put32(24, SaveProfile.checksum(Data(profile[..<24])))
        let entries = [SaveEntry(path: "NFS Underground 2/TEST/TEST", data: profile)]
        let zip = try SaveArchive.encode(entries), box = try VaultCrypto.pack(entries, keys: keys)
        let initial = try api.put(box, revision: nil)
        let download = try api.get()!
        expect(download.remote.revision == initial.revision, "GET returns the revision PUT made")
        expect(try SaveArchive.decode(VaultCrypto.unpack(download.box, keys: keys))[0].data == profile, "the profile comes back unchanged")
        do { _ = try api.put(box, revision: nil); expect(false, "a second create (If-None-Match: *) was allowed") } catch is VaultConflict { }
        let next = try api.put(box, revision: initial.revision)
        do { _ = try api.put(box, revision: initial.revision); expect(false, "a stale revision was allowed") } catch is VaultConflict { }
        expect(try api.get()!.remote.revision == next.revision, "after the conflicts the cloud holds the last good send")
        let json: [String: String] = ["phrase": phrase, "token": keys.token, "endpoint": endpoint.absoluteString, "zip": zip.base64EncodedString()]
        try JSONSerialization.data(withJSONObject: json).write(to: fixture)
        print("PASS vault_http: 404, create, get, update, stale and duplicate conflicts against the server")
    }
}
