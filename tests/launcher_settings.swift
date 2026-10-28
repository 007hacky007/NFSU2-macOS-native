import Foundation

@main
struct LauncherSettingsTests {
    static func main() throws {
        assert(SupportedExe.builds.count == 1)
        assert(SupportedExe.builds[0].size == 4_800_512 && SupportedExe.builds[0].engineSuffix.isEmpty)
        assert(Paths.engine(SupportedExe.builds[0], hd: false).lastPathComponent == "nfsu2-engine")
        assert(Paths.engine(SupportedExe.builds[0], hd: true).lastPathComponent == "nfsu2-engine-hd")
        assert(!PortableBuilder.skippedGameItems.contains("MOVIES") && !PortableBuilder.skippedGameItems.contains("server.dll"))
        assert(LaunchSettings.serverURL("wss://nfsu2.xyz/lan") != nil)
        assert(LaunchSettings.serverURL("ws://127.0.0.1:8080/lan") != nil)
        assert(LaunchSettings.serverURL("ws://[::1]:8080/lan") != nil)
        for bad in ["ws://example.com/lan", "https://example.com", "wss://user:pass@example.com/lan", "wss://example.com/#secret", "wss://example.com:99999/lan", "wss://example.com/lan\n"] {
            assert(LaunchSettings.serverURL(bad) == nil, bad)
        }
        assert(LaunchSettings.countsURL(for: "ws://localhost:8080/custom?secret=x") == "http://localhost:8080/players")
        assert(LaunchSettings.countsURL(for: LaunchSettings.defaultServer) == LaunchSettings.defaultCounts)
        assert(LaunchSettings.countsEndpoint("https://example.com/players?crews=123,456") != nil)
        assert(LaunchSettings.countsEndpoint("http://example.com/players") == nil)
        assert(LaunchSettings.countsEndpoint("http://localhost:8080/players") != nil)
        assert(LaunchSettings.validPlayerName("Player_2-ABC"))
        for bad in ["", "ab", "abcdefghijklmnop", "Player Name", "René", "user\n"] {
            assert(!LaunchSettings.validPlayerName(bad), bad)
        }
        let inherited = ["NFSU2_SERVER_URL": "wss://stale.example/lan", "NFSU2_UI_TEXPACK": "/stale.pak", "NFSU2_ROAM_NAME": "stale", "NFSU2_NET_NAME": "host", "PATH": "/bin"]
        let offline = try LaunchSettings.environment(inherited: inherited, online: false, server: "invalid", name: "", textures: "original", pack: nil, data: "/game/SPEED2.EXE", saves: "/saves", registry: "/registry")
        assert(offline["NFSU2_ONLINE"] == "0" && offline["NFSU2_ROAM"] == "0" && offline["NFSU2_NET"] == "off")
        assert(offline["NFSU2_SERVER_URL"] == nil && offline["NFSU2_ROAM_NAME"] == nil && offline["NFSU2_UI_TEXPACK"] == nil && offline["NFSU2_NET_NAME"] == nil)
        assert(offline["PATH"] == "/bin" && offline["NFSU2_DATA"] == "/game/SPEED2.EXE")
        assert(offline["NFSU2_SAVEDIR"] == "/saves" && offline["NFSU2_REGFILE"] == "/registry")
        let online = try LaunchSettings.environment(inherited: inherited, online: true, server: LaunchSettings.defaultServer, name: "Driver_1", textures: "uhud", pack: "/custom.pak", data: "/game/SPEED2.EXE", saves: "/saves", registry: "/registry")
        assert(online["NFSU2_NET"] == "online" && online["NFSU2_ONLINE"] == "1" && online["NFSU2_ROAM"] == "1")
        assert(online["NFSU2_ROAM_NAME"] == "Driver_1" && online["NFSU2_NET_NAME"] == "Driver_1")
        assert(online["NFSU2_UI_TEXTURES"] == "uhud" && online["NFSU2_UI_TEXPACK"] == "/custom.pak")
        do {
            _ = try LaunchSettings.environment(inherited: [:], online: true, server: LaunchSettings.defaultServer, name: "", textures: "original", pack: nil, data: "/game", saves: "/saves", registry: "/registry")
            assertionFailure("Online must require a name")
        } catch {}
        let counts = try JSONDecoder().decode(PlayerCounts.self, from: Data(#"{"players":12,"online":4,"roam":8,"full":true,"queue":2,"roamBusy":false,"crews":[3,1]}"#.utf8))
        assert(counts.summary.contains("12 players") && counts.summary.contains("Crews: 3, 1"))
        let disabled = try JSONDecoder().decode(PlayerCounts.self, from: Data(#"{"players":0,"online":null,"roam":null,"full":false,"queue":0,"roamBusy":false}"#.utf8))
        assert(disabled.summary.contains("0 players"))
        let invalidCounts = try JSONDecoder().decode(PlayerCounts.self, from: Data(#"{"players":-1,"online":null,"roam":null,"full":false,"queue":0,"roamBusy":false}"#.utf8))
        assert(!invalidCounts.valid)

        var pack = Data([0x4e, 0x54, 0x58, 0x50])
        func word(_ n: UInt32) { var v = n.littleEndian; withUnsafeBytes(of: &v) { pack.append(contentsOf: $0) } }
        word(1); word(1); word(0)
        for n: UInt32 in [1, 1, 0x00010001, 21, 0x00010001, 21, 1, 58, 4, 56] { word(n) }
        pack.append(contentsOf: [120, 0, 1, 2, 3, 4])
        try TexturePack.validate(pack)
        func settingWord(_ data: Data, _ offset: Int, _ value: UInt32) -> Data {
            var result = data, little = value.littleEndian
            withUnsafeBytes(of: &little) { result.replaceSubrange(offset..<offset + 4, with: $0) }
            return result
        }
        var malformed: [Data] = []
        for (offset, value): (Int, UInt32) in [
            (24, 0), (24, 0x00011001), (28, 0), // zero/oversized original dimensions, unsupported original format
            (32, 0), (32, 0x00014001), (32, 0x00010002), // zero/oversized replacement, changed aspect ratio
            (36, 0), (40, 0), (40, 2), (48, 3), // unsupported replacement format, invalid mip count/bytes
        ] { malformed.append(settingWord(pack, offset, value)) }
        var longName = Data(pack.prefix(56))
        longName.append(Data(repeating: 120, count: 1024)); longName.append(0)
        longName.append(contentsOf: [1, 2, 3, 4])
        longName = settingWord(longName, 44, 1081)
        malformed.append(longName)
        var pair = settingWord(Data(pack.prefix(16)), 8, 2)
        let entry = settingWord(settingWord(Data(pack[16..<56]), 28, 98), 36, 96)
        pair.append(entry); pair.append(settingWord(entry, 4, 2))
        pair.append(contentsOf: [120, 0, 1, 2, 3, 4])
        try TexturePack.validate(pair)
        malformed.append(settingWord(pair, 56, 0))
        malformed.append(settingWord(pair, 60, 0))
        for format: UInt32 in [21, 22, 0x31545844, 0x33545844, 0x35545844] {
            let bytes: UInt32 = format == 21 || format == 22 ? 4 : format == 0x31545844 ? 8 : 16
            var valid = settingWord(settingWord(settingWord(pack, 28, format), 36, format), 48, bytes)
            valid.append(Data(repeating: 0, count: Int(bytes) - 4))
            try TexturePack.validate(valid)
        }
        var mipPack = settingWord(settingWord(settingWord(settingWord(pack, 24, 0x00050003), 32, 0x00050003), 40, 3), 48, 72)
        mipPack.append(Data(repeating: 0, count: 68))
        try TexturePack.validate(mipPack)
        var upscaled = settingWord(settingWord(settingWord(pack, 32, 0x00020002), 40, 2), 48, 20)
        upscaled.append(Data(repeating: 0, count: 16))
        try TexturePack.validate(upscaled)
        for bad in [Data(), pack.prefix(15), pack.prefix(57)] {
            do { try TexturePack.validate(Data(bad)); assertionFailure("Must reject truncated pack") } catch {}
        }
        var badOffset = pack
        badOffset[44] = 0
        do { try TexturePack.validate(badOffset); assertionFailure("Must reject overlapping table and payload") } catch {}
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.pak"), target = dir.appendingPathComponent("Textures/uhud.pak")
        try pack.write(to: source)
        try TexturePack.install(from: source, to: target)
        let installed = try Data(contentsOf: target)
        assert(installed == pack)
        var zeroDimensions = pack
        zeroDimensions.replaceSubrange(24..<28, with: [0, 0, 0, 0])
        try zeroDimensions.write(to: source)
        do { try TexturePack.install(from: source, to: target); assertionFailure("Must reject malformed metadata before replacing a good pack") } catch {}
        let preservedAfterMetadata = try Data(contentsOf: target)
        assert(preservedAfterMetadata == pack)
        for invalid in malformed {
            try invalid.write(to: source)
            do { try TexturePack.install(from: source, to: target); assertionFailure("Must preserve prior pack for invalid texture metadata") } catch {}
            let stillInstalled = try Data(contentsOf: target)
            assert(stillInstalled == pack)
        }
        try Data("bad".utf8).write(to: source)
        do { try TexturePack.install(from: source, to: target); assertionFailure("Must reject corrupt import") } catch {}
        let preserved = try Data(contentsOf: target)
        assert(preserved == pack)
        print("launcher settings tests passed")
    }
}
