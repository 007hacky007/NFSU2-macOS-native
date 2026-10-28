import Foundation

@main struct VaultHTTPTests {
    static func main() throws {
        let mode = CommandLine.arguments[1], fixture = URL(fileURLWithPath: CommandLine.arguments[2])
        if mode == "reject" {
            let endpoint = try VaultAPI.endpoint(CommandLine.arguments[3])
            let api = VaultAPI(endpoint: endpoint, token: String(repeating:"A",count:43))
            do { _ = try api.get(); fatalError("Expected unsafe response rejection") }
            catch { assert(error.localizedDescription.contains(CommandLine.arguments[4])) }
            print("vault_http: unsafe HTTP response rejected")
            return
        }
        if mode == "verify" {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String:String]
            let keys = try VaultCrypto.keys(json["phrase"]!), api = VaultAPI(endpoint: try VaultAPI.endpoint(json["endpoint"]!), token: keys.token)
            let downloaded = try api.get()!
            let zip = try VaultCrypto.unpack(downloaded.box, keys: keys)
            let entries = try SaveStore.validated(zip)
            assert(entries.count == 1 && SaveStore.profileName(entries[0].path) == "TEST")
            print("vault_http: browser upload decrypted and validated by native client")
            return
        }
        let endpoint = try VaultAPI.endpoint(CommandLine.arguments[3])
        let phrase = try VaultCrypto.newPhrase(), keys = try VaultCrypto.keys(phrase)
        let api = VaultAPI(endpoint: endpoint, token: keys.token)
        let missing = try api.get(); assert(missing == nil)
        var profile = Data(repeating: 0, count: 54966)
        profile.replaceSubrange(0..<4, with: Data("20CM".utf8))
        for (at, value) in [(4,54966),(8,8),(12,54930),(28,0x10d),(32,54930)] { profile.put32(at,UInt32(value)) }
        profile.replaceSubrange(53797..<53801, with: Data("TEST".utf8))
        for i in 0..<48 { profile.put32(36 + i * 24 + 20,UInt32.max) }
        profile.put32(16,SaveProfile.checksum(Data(profile[28..<36])))
        profile.put32(20,SaveProfile.checksum(Data(profile[36...])))
        profile.put32(24,SaveProfile.checksum(Data(profile[..<24])))
        let entries = [SaveEntry(path:"NFS Underground 2/TEST/TEST", data:profile)]
        let zip = try SaveArchive.encode(entries), box = try VaultCrypto.pack(entries,keys:keys)
        let initial = try api.put(box,revision:nil)
        let download = try api.get()!
        assert(download.remote.revision == initial.revision)
        let downloadedZip = try VaultCrypto.unpack(download.box,keys:keys)
        let decoded = try SaveArchive.decode(downloadedZip); assert(decoded[0].data == profile)
        do { _ = try api.put(box,revision:nil); fatalError("Allowed overwrite without current ETag") } catch is VaultConflict { }
        let next = try api.put(box,revision:initial.revision)
        do { _ = try api.put(box,revision:initial.revision); fatalError("Allowed stale revision") } catch is VaultConflict { }
        let afterConflict = try api.get()!; assert(afterConflict.remote.revision == next.revision)
        do { _ = try VaultAPI.endpoint("http://example.com/vault"); fatalError("Allowed insecure non-loopback URL") } catch { }
        let json: [String:String] = ["phrase":phrase,"token":keys.token,"endpoint":endpoint.absoluteString,"zip":zip.base64EncodedString()]
        try JSONSerialization.data(withJSONObject:json).write(to:fixture)
        print("vault_http: donor 404/create/get/update/stale conflict and HTTPS guard passed")
    }
}
