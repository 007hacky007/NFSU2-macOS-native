import Foundation

func tryChecked(_ body: () throws -> Bool) -> Bool { try! body() }

@main struct SaveManagerTests {
    static func main() throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("save-manager-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let saves = root.appendingPathComponent("saves"), registry = root.appendingPathComponent("registry")
        let store = SaveStore(saves: saves, registry: registry)
        var profile = Data(repeating: 0, count: 54966)
        profile.replaceSubrange(0..<4, with: Data("20CM".utf8))
        for (at, value) in [(4,54966),(8,8),(12,54930),(28,0x10d),(32,54930)] { profile.put32(at, UInt32(value)) }
        profile.replaceSubrange(53797..<53801, with: Data("TEST".utf8))
        for i in 0..<48 { profile.put32(36 + i * 24 + 20, UInt32.max) }
        profile.put32(16, SaveProfile.checksum(Data(profile[28..<36])))
        profile.put32(20, SaveProfile.checksum(Data(profile[36...])))
        profile.put32(24, SaveProfile.checksum(Data(profile[..<24])))
        let entries = [SaveEntry(path: "NFS Underground 2/TEST/TEST", data: profile)]
        let zip = try SaveArchive.encode(entries)
        assert(tryChecked { try SaveArchive.decode(zip).first!.data == profile })
        try store.restore(zip, gameRunning: { false })
        assert(tryChecked { try store.profiles().map { $0.name } == ["TEST"] })
        let before = try store.snapshot()
        func rejects(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection") } catch { }
        }
        rejects { try store.restore(zip, gameRunning: { true }) }
        var broken = zip; broken[45] ^= 1
        rejects { try store.restore(broken, gameRunning: { false }) }
        rejects { _ = try SaveArchive.encode([SaveEntry(path: "../escape", data: Data())]) }
        rejects { _ = try SaveArchive.encode([SaveEntry(path: "A", data: Data()), SaveEntry(path: "a", data: Data())]) }
        let aliasArchive = try SaveArchive.encode(entries + [SaveEntry(path:"nfs underground 2/BAD/BAD",data:Data("invalid".utf8))])
        rejects { try store.restore(aliasArchive,gameRunning:{ false }) }
        let central = Int(zip.u32(zip.count - 6))
        var symlinkZip = zip; symlinkZip.put32(central + 38, 0o120777 << 16)
        rejects { _ = try SaveArchive.decode(symlinkZip) }
        var hugeZip = zip; hugeZip.put32(central + 24, UInt32.max)
        rejects { _ = try SaveArchive.decode(hugeZip) }
        var encryptedZip = zip; encryptedZip.put16(central + 8, 0x801)
        rejects { _ = try SaveArchive.decode(encryptedZip) }
        var mismatchedName = zip; mismatchedName[30] ^= 1
        rejects { _ = try SaveArchive.decode(mismatchedName) }
        rejects { _ = try SaveArchive.encode([SaveEntry(path: "a", data: Data()), SaveEntry(path: "a/b", data: Data())]) }
        let compressedBomb = try SaveArchive.deflate(Data(repeating: 0, count: 1 << 20), inflate: false)
        rejects { _ = try SaveArchive.deflate(compressedBomb, inflate: true, limit: 64) }
        var checkedGame = 0
        rejects { try store.restore(zip, gameRunning: { checkedGame += 1; return checkedGame > 1 }) }
        var invalid = profile; invalid[100] ^= 1
        rejects { try store.restore(SaveArchive.encode([SaveEntry(path: entries[0].path, data: invalid)]), gameRunning: { false }) }
        assert(tryChecked { try store.snapshot().map { $0.data } == before.map { $0.data } })
        var replacement = profile
        replacement.replaceSubrange(53797..<53829, with: Data(repeating:0,count:32))
        replacement.replaceSubrange(53797..<53800, with: Data("NEW".utf8))
        replacement.put32(20,SaveProfile.checksum(Data(replacement[36...])))
        replacement.put32(24,SaveProfile.checksum(Data(replacement[..<24])))
        let withRegistry = try SaveArchive.encode([SaveEntry(path:"NFS Underground 2/NEW/NEW",data:replacement),SaveEntry(path:"registry.txt",data:Data("test registry".utf8))])
        var restoreChecks = 0
        rejects {
            try store.restore(withRegistry,gameRunning:{
                restoreChecks += 1
                if restoreChecks == 3 { try! FileManager.default.createDirectory(at:registry,withIntermediateDirectories:true) }
                return false
            })
        }
        assert(restoreChecks == 3)
        assert(!FileManager.default.fileExists(atPath:saves.appendingPathComponent("NFS Underground 2/NEW/NEW").path))
        try FileManager.default.removeItem(at:registry)
        assert(tryChecked { try store.snapshot().map { $0.data } == before.map { $0.data } })
        let link = saves.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: registry)
        rejects { _ = try store.snapshot() }
        try FileManager.default.removeItem(at: link)
        assert(tryChecked { try FileManager.default.contentsOfDirectory(atPath: store.backups.path).contains { $0.hasSuffix(".zip") } })
        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1])
            let fixtureStore = SaveStore(saves: folder, registry: folder.appendingPathComponent("absent-registry"))
            let entries = try fixtureStore.snapshot()
            var tested = 0
            for entry in entries {
                if let name = SaveStore.profileName(entry.path) { try SaveProfile.validate(entry.data, name: name); tested += 1 }
            }
            assert(tested > 0)
            print("save_manager: validated \(tested) native smoke-test profiles read-only")
        }
        print("save_manager: archive, profile, game guard, rollback and symlink checks passed")
    }
}
