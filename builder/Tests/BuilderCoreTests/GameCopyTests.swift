import CryptoKit
import XCTest
@testable import BuilderCore

/// The game-copy checks: game data from a folder, .iso, .cue/.bin or disc folders, and the game
/// program from SPEED2.EXE itself or an archive. Everything here is made up: small files whose
/// checksums stand in for the real releases.
final class GameCopyTests: XCTestCase {
    private let fm = FileManager.default
    private var tmp: URL!

    // A tiny "release": two core files, one region file each, one optional file.
    private let files: [String: String] = [
        "GLOBAL/GLOBALB.LZC": "global",
        "TRACKS/TRACKMAP4014.bin": "trackmap",
        "FRONTEND/FrontB.lzc": "frontend v1.2",
        "MOVIES/intro.vp6": "movie",
        "CARS/CORSA/GEOMETRY.BIN": "corsa",
    ]
    private let supportedEU = Data("MZfake supported SPEED2.EXE\n".utf8)
    private let supportedNA = Data("MZfake north american SPEED2.EXE\n".utf8)
    private let discExe = Data("MZfake disc SPEED2.EXE".utf8)
    private let patchExe = Data("MZfake patched SPEED2.EXE".utf8)
    private let server10 = Data("server v1.0".utf8)

    private var programs: [KnownProgram] {
        [KnownProgram(name: "European v1.2, no CD check", size: supportedEU.count, sha256: sha(supportedEU), crc32: crc(supportedEU), kind: .supported(.eu)),
         KnownProgram(name: "North American v1.2, no CD check", size: supportedNA.count, sha256: sha(supportedNA), crc32: crc(supportedNA), kind: .supported(.na)),
         KnownProgram(name: "European v1.0 disc", size: discExe.count, sha256: sha(discExe), crc32: crc(discExe), kind: .disc),
         KnownProgram(name: "official patch", size: patchExe.count, sha256: sha(patchExe), crc32: crc(patchExe), kind: .officialPatch)]
    }

    private var servers: [KnownServer] {
        [KnownServer(name: "v1.0", size: server10.count, sha256: sha(server10), crc32: crc(server10))]
    }

    private var manifest: ReleaseManifest {
        var lines = ["release\teu\tEuropean test release", "release\tna\tNorth American test release"]
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(text.utf8)
            let core = path.hasPrefix("GLOBAL/") || path.hasPrefix("TRACKS/") ? "1" : "0"
            let releases = path.hasPrefix("CARS/CORSA") ? "eu" : "eu,na"
            lines.append("file\t\(path)\t\(data.count)\t\(sha(data))\t\(String(format: "%08x", crc(data)))\t\(releases)\t\(core)")
        }
        let old = Data("frontend v1.0".utf8)
        lines.append("file\tFRONTEND/FrontB.lzc\t\(old.count)\t\(sha(old))\t\(String(format: "%08x", crc(old)))\tna\t0")
        return try! ReleaseManifest(text: lines.joined(separator: "\n") + "\n")
    }

    private var checker: GameDataChecker { GameDataChecker(manifest: manifest, programs: programs, servers: servers) }

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2 copy \"q\" ö-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    // MARK: - Game data: folders

    func testFolderWithSupportedProgramIsGreenAndProvidesTheProgram() throws {
        let game = try makeGameFolder("Game", exe: supportedEU)
        let report = checker.check([game])
        XCTAssertEqual(report.kind, .folder)
        XCTAssertNil(report.blocking)
        XCTAssertEqual(report.state, .ready("Game folder, matches the European test release release"))
        XCTAssertEqual(report.program, .supported(.eu, name: "European v1.2, no CD check"))
        XCTAssertEqual(report.server, "v1.0")
        XCTAssertTrue(report.providesProgram)
        XCTAssertEqual(report.bytes, Int64(files.values.reduce(0) { $0 + $1.utf8.count } + supportedEU.count + server10.count))
    }

    /// An NFSU2.app with the game inside (the update path) is checked like a folder: its
    /// Contents/Resources/Game is the data and its SPEED2.EXE the program. Nothing is written.
    func testInstalledAppWithTheGameInsideIsAGameSource() throws {
        let app = tmp.appendingPathComponent("Applications/NFSU2.app")
        let game = try makeGameFolder("Applications/NFSU2.app/Contents/Resources/Game", exe: supportedEU)
        try write("plist", to: app.appendingPathComponent("Contents/Info.plist"))
        let before = try snapshot(app)
        let report = checker.check([app])
        XCTAssertEqual(report.kind, .app)
        XCTAssertEqual(report.sources.map { $0.standardizedFileURL.path }, [game.standardizedFileURL.path])
        XCTAssertNil(report.blocking)
        XCTAssertEqual(report.state, .ready("Uses the game inside your current NFSU2.app, matches the European test release release"))
        XCTAssertTrue(report.providesProgram)
        XCTAssertEqual(try snapshot(app), before, "the app is only read")

        let empty = tmp.appendingPathComponent("Old/NFSU2.app")
        try write("plist", to: empty.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(checker.check([empty]).blocking, GameDataMessages.appWithoutGame)
    }

    func testParentFolderFindsTheGameInside() throws {
        let game = try makeGameFolder("Clean Edition/Need for Speed Underground 2", exe: supportedNA)
        let report = checker.check([tmp.appendingPathComponent("Clean Edition")])
        XCTAssertEqual(report.sources.map { $0.resolvingSymlinksInPath().path }, [game.resolvingSymlinksInPath().path])
        XCTAssertEqual(report.program, .supported(.na, name: "North American v1.2, no CD check"))
    }

    func testUnknownAndDifferingFilesGiveAmberNoteAndNeverBlock() throws {
        let game = try makeGameFolder("Modded", exe: supportedEU)
        try write("a mod", to: game.appendingPathComponent("FRONTEND/FrontB.lzc"))     // differs
        try write("extra", to: game.appendingPathComponent("SCRIPTS/mod.asi"))         // unknown path: ignored
        try fm.removeItem(at: game.appendingPathComponent("MOVIES/intro.vp6"))         // optional file missing
        let report = checker.check([game])
        XCTAssertNil(report.blocking)
        XCTAssertEqual(report.notes, [GameDataMessages.differs(differ: 1, missing: 1)])
        XCTAssertEqual(report.notes.first, "This copy has 1 file that differs from the releases we know and 1 file of the release missing (another language, a repack or mods). It should work; if something looks wrong, report it with Copy details.")
        guard case .automatic = report.state else { return XCTFail("amber expected, got \(report.state)") }
        XCTAssertTrue(canBuild(Dictionary(uniqueKeysWithValues: CheckID.allCases.map { ($0, $0 == .gameData ? report.state : .ready("")) })))
        XCTAssertTrue(report.details.contains("Differs: FRONTEND/FrontB.lzc"))
        XCTAssertTrue(report.details.contains("Missing: MOVIES/intro.vp6"))
        XCTAssertFalse(report.details.contains { $0.contains("SCRIPTS") })
    }

    func testCaseDoesNotMatter() throws {
        let game = try makeGameFolder("Lower", exe: supportedEU, lowercase: true)
        let report = checker.check([game])
        XCTAssertEqual(report.state, .ready("Game folder, matches the European test release release"))
    }

    func testOtherRegionFilesCountForThatRelease() throws {
        let game = try makeGameFolder("US", exe: supportedEU)
        try fm.removeItem(at: game.appendingPathComponent("CARS/CORSA"))
        try write("frontend v1.0", to: game.appendingPathComponent("FRONTEND/FrontB.lzc"))
        let report = checker.check([game])
        XCTAssertEqual(report.state, .ready("Game folder, matches the North American test release release"))
    }

    func testMissingCoreFilesBlock() throws {
        let game = try makeGameFolder("Broken", exe: supportedEU)
        try fm.removeItem(at: game.appendingPathComponent("GLOBAL"))
        let report = checker.check([game])
        XCTAssertEqual(report.blocking, GameDataMessages.coreMissing(["GLOBAL/GLOBALB.LZC"]))
        XCTAssertEqual(report.blocking, "This is not a complete NFSU2 game copy: GLOBAL/GLOBALB.LZC missing. Choose the folder that holds SPEED2.EXE and the GLOBAL, CARS and TRACKS folders, or the two disc images.")
        XCTAssertFalse(report.providesProgram)
        let empty = tmp.appendingPathComponent("Empty")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(checker.check([empty]).blocking,
                       GameDataMessages.coreMissing(["GLOBAL/GLOBALB.LZC", "TRACKS/TRACKMAP4014.bin"]))
    }

    func testMissingOrUnknownServerIsAmber() throws {
        let game = try makeGameFolder("NoServer", exe: supportedEU)
        try fm.removeItem(at: game.appendingPathComponent("server.dll"))
        XCTAssertEqual(checker.check([game]).state, .automatic(GameDataMessages.serverMissing))
        try write("someone's server", to: game.appendingPathComponent("server.dll"))
        XCTAssertEqual(checker.check([game]).state, .automatic(GameDataMessages.serverUnknown))
        XCTAssertEqual(GameDataMessages.serverMissing, "There is no server.dll, so LAN hosting may not work.")
    }

    func testProgramInDataIsExplainedWhenNotSupported() throws {
        let disc = checker.check([try makeGameFolder("Disc", exe: discExe)])
        XCTAssertEqual(disc.program, .refused(ProgramMessages.disc))
        XCTAssertEqual(ProgramMessages.disc, "This is the copy-protected disc version. The build needs v1.2 without the CD check.")
        XCTAssertFalse(disc.providesProgram)
        XCTAssertNil(disc.blocking)
        let patched = checker.check([try makeGameFolder("Patched", exe: patchExe)])
        XCTAssertEqual(patched.program, .refused(ProgramMessages.officialPatch))
        let protected = checker.check([try makeGameFolder("Protected", exe: pe(sections: [".text", "stxt774", "stxt371"]))])
        XCTAssertEqual(protected.program, .refused(ProgramMessages.protected))
        let none = try makeGameFolder("NoExe", exe: nil)
        XCTAssertNil(checker.check([none]).program)
        XCTAssertNil(checker.check([none]).blocking)
    }

    func testChoiceThatIsNoGameCopyIsRefused() throws {
        let game = try makeGameFolder("Game", exe: supportedEU)
        let discs = try makeDiscFolders()
        XCTAssertEqual(checker.check([game, discs.0]).blocking, GameDataMessages.chooseOne)
        let text = tmp.appendingPathComponent("notes.txt")
        try write("x", to: text)
        XCTAssertEqual(checker.check([text]).blocking, GameDataMessages.chooseOne)
        XCTAssertEqual(checker.check([discs.0, discs.1, discs.0]).blocking, GameDataMessages.chooseOne)
    }

    // MARK: - Game data: discs

    func testDiscFolders() throws {
        let (one, two) = try makeDiscFolders()
        let report = checker.check([two, one])
        XCTAssertEqual(report.kind, .discs)
        XCTAssertNil(report.blocking, report.detailsText)
        XCTAssertEqual(report.state, .ready("Disc data, matches the European test release release"))
        XCTAssertEqual(report.program, .refused(ProgramMessages.disc))
        XCTAssertEqual(report.server, "v1.0")
        XCTAssertEqual(report.sources.map { $0.lastPathComponent }, ["Disc 1", "Disc 2"])
    }

    func testISOImages() throws {
        let (one, two) = try makeDiscFolders()
        let report = checker.check([try makeISO(one), try makeISO(two)])
        XCTAssertNil(report.blocking, report.detailsText)
        XCTAssertEqual(report.state, .ready("Disc data, matches the European test release release"))
        XCTAssertEqual(report.program, .refused(ProgramMessages.disc))
    }

    func testCueBinImages() throws {
        let (one, two) = try makeDiscFolders()
        let cue = try makeCueBin(try makeISO(one), name: "Disc 1")
        let bin = cue.deletingPathExtension().appendingPathExtension("bin")
        // Choosing the .cue and its .bin together counts as one disc.
        let report = checker.check([cue, bin, try makeISO(two)])
        XCTAssertNil(report.blocking, report.detailsText)
        XCTAssertEqual(report.sources.count, 2)
        XCTAssertEqual(report.state, .ready("Disc data, matches the European test release release"))
        XCTAssertEqual(checker.check([bin, try makeISO(two)]).state, report.state)
    }

    func testOneDiscOnlyAsksForBoth() throws {
        let (one, _) = try makeDiscFolders()
        XCTAssertEqual(checker.check([try makeISO(one)]).blocking, GameDataMessages.bothDiscs)
        XCTAssertEqual(GameDataMessages.bothDiscs, "These are the files of one disc only. Choose both disc images together.")
    }

    func testDamagedImageIsRefusedPlainly() throws {
        let fake = tmp.appendingPathComponent("broken.iso")
        try Data(repeating: 7, count: 40_000).write(to: fake)
        let (_, two) = try makeDiscFolders()
        XCTAssertEqual(checker.check([fake, two]).blocking, "broken.iso is not a CD image (no ISO 9660 volume)")
    }

    func testDiscReaderReadsJolietNames() throws {
        let (_, two) = try makeDiscFolders()
        let image = try DiscImage(try makeISO(two))
        let names = try image.entries().map { $0.path }
        XCTAssertTrue(names.contains("compressed.zip"))
        XCTAssertTrue(names.contains("MOVIES/intro.vp6"))
        XCTAssertTrue(names.contains("speed2.exe"))
        let zip = try XCTUnwrap(try image.entries().first { $0.path == "compressed.zip" })
        let members = try ZipDirectory.members(size: zip.size) { try image.read(extent: zip.extent, at: $0, length: $1) }
        XCTAssertEqual(Set(members.filter { !$0.isDirectory }.map { $0.path }),
                       ["GLOBAL/GLOBALB.LZC", "FRONTEND/FrontB.lzc", "server.dll", "CARS/CORSA/GEOMETRY.BIN"])
    }

    // MARK: - Game program

    func testProgramFileSupportedIsKept() throws {
        let exe = tmp.appendingPathComponent("Downloads/SPEED2.EXE")
        try write(supportedEU, to: exe)
        let keep = tmp.appendingPathComponent("support/program/SPEED2.EXE")
        XCTAssertEqual(ProgramChecker(programs: programs, temporaryParent: tmp).check(exe, keep: keep),
                       .supported(.eu, name: "European v1.2, no CD check"))
        XCTAssertEqual(try Data(contentsOf: keep), supportedEU)
        XCTAssertEqual(try Data(contentsOf: exe), supportedEU, "the chosen file is only read")
    }

    func testProgramFileRefusals() throws {
        let checker = ProgramChecker(programs: programs, temporaryParent: tmp)
        let keep = tmp.appendingPathComponent("keep/SPEED2.EXE")
        func verdict(_ data: Data, _ name: String = "SPEED2.EXE") throws -> ProgramVerdict {
            let url = tmp.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
            try write(data, to: url)
            return checker.check(url, keep: keep)
        }
        XCTAssertEqual(try verdict(discExe), .refused(ProgramMessages.disc))
        XCTAssertEqual(try verdict(patchExe), .refused(ProgramMessages.officialPatch))
        XCTAssertEqual(try verdict(pe(sections: [".text", "stxt774"])), .refused(ProgramMessages.protected))
        let other = pe(sections: [".text", ".data"])
        XCTAssertEqual(try verdict(other), .refused(ProgramMessages.unknown(other.count)))
        XCTAssertEqual(ProgramMessages.unknown(4_788_225), "This SPEED2.EXE (4,788,225 bytes) is not one of the two supported versions. The build needs v1.2 without the CD check.")
        XCTAssertEqual(try verdict(Data("hello".utf8), "SPEED2.EXE"), .refused(ProgramMessages.notProgram))
        XCTAssertEqual(try verdict(Data("hello".utf8), "notes.txt"), .refused(ProgramChoiceMessages.unreadable))
        XCTAssertFalse(fm.fileExists(atPath: keep.path), "nothing refused is kept")
    }

    func testProgramFromZipArchiveInSubfolder() throws {
        let checker = ProgramChecker(programs: programs, temporaryParent: tmp)
        let keep = tmp.appendingPathComponent("keep/SPEED2.EXE")
        let archive = tmp.appendingPathComponent("NFSU2 v1.2.zip")
        try zip([("readme.txt", Data("hi".utf8)), ("NFSU2/Bin/SPEED2.EXE", supportedEU)]).write(to: archive)
        let before = try Data(contentsOf: archive)
        XCTAssertEqual(checker.check(archive, keep: keep), .supported(.eu, name: "European v1.2, no CD check"))
        XCTAssertEqual(try Data(contentsOf: keep), supportedEU)
        XCTAssertEqual(try Data(contentsOf: archive), before)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: tmp.path).filter { $0.hasPrefix("nfsu2-program-") }, [],
                       "the private temporary folder is removed")
    }

    func testZipArchiveRefusals() throws {
        let checker = ProgramChecker(programs: programs, temporaryParent: tmp)
        let keep = tmp.appendingPathComponent("keep/SPEED2.EXE")
        let disc = tmp.appendingPathComponent("disc.zip")
        try zip([("Game/SPEED2.EXE", discExe)]).write(to: disc)
        XCTAssertEqual(checker.check(disc, keep: keep), .refused(ProgramChoiceMessages.inArchive(ProgramMessages.disc)))
        XCTAssertEqual(ProgramChoiceMessages.inArchive(ProgramMessages.disc),
                       "The archive holds no supported SPEED2.EXE. This is the copy-protected disc version. The build needs v1.2 without the CD check.")
        let none = tmp.appendingPathComponent("none.zip")
        try zip([("Game/readme.txt", Data("hi".utf8))]).write(to: none)
        XCTAssertEqual(checker.check(none, keep: keep), .refused(ProgramChoiceMessages.noneInArchive))
        let broken = tmp.appendingPathComponent("broken.zip")
        try write("not a zip", to: broken)
        XCTAssertEqual(checker.check(broken, keep: keep), .refused(ProgramChoiceMessages.unreadable))
        XCTAssertFalse(fm.fileExists(atPath: keep.path))
    }

    /// RAR 5 and RAR 4, stored, holding Game/SPEED2.EXE = `supportedEU` (written by hand from the
    /// format descriptions, the same bytes rar would store).
    static let rar5 = "UmFyIRoHAQDFGjMyAwEAAErjMJgcAgIcBBwgJPZgqAAAD0dhbWUvU1BFRUQyLkVYRU1aZmFrZSBzdXBwb3J0ZWQgU1BFRUQyLkVYRQoZsjo1AwUAAA=="
    static let rar4 = "UmFyIRoHAM+QcwAADQAAAAAAAABEMXQAgC8AHAAAABwAAAAAJPZgqAAAACEUMA8AIAAAAEdhbWVcU1BFRUQyLkVYRU1aZmFrZSBzdXBwb3J0ZWQgU1BFRUQyLkVYRQrEPXsAQAcA"
    /// 7-Zip's 7z archive of the same file.
    static let sevenZip = "N3q8ryccAAQhwtdfIAAAAAAAAABqAAAAAAAAAFQA3d0BABtNWmZha2Ugc3VwcG9ydGVkIFNQRUVEMi5FWEUKAAEEBgABCSAABwsBAAEhIQEADBwACAoBJPZgqAAABQEZDAAAAAAAAAAAAAAAABEhAEcAYQBtAGUALwBTAFAARQBFAEQAMgAuAEUAWABFAAAAGQIAABQKAQBf3+O8kWndARUGAQAggKSBAAA="

    func testProgramFromRarAnd7zArchives() throws {
        let checker = ProgramChecker(programs: programs, temporaryParent: tmp)
        for (name, base64) in [("five.rar", Self.rar5), ("four.rar", Self.rar4), ("seven.7z", Self.sevenZip)] {
            let archive = tmp.appendingPathComponent(name)
            try XCTUnwrap(Data(base64Encoded: base64)).write(to: archive)
            let keep = tmp.appendingPathComponent("keep-\(name)/SPEED2.EXE")
            XCTAssertEqual(checker.check(archive, keep: keep), .supported(.eu, name: "European v1.2, no CD check"), name)
            XCTAssertEqual(try Data(contentsOf: keep), supportedEU, name)
        }
    }

    func testRarFallbackReaderUnpacksTheSameFile() throws {
        let data = try XCTUnwrap(Data(base64Encoded: Self.rar5))
        var out = Data()
        try data.withUnsafeBytes { bytes in
            let entries = try RarArchive.list(bytes)
            XCTAssertEqual(entries.map { $0.name }, ["Game/SPEED2.EXE"])
            try RarArchive.extract(bytes, entries: entries) { _ in { out.append(contentsOf: $0) } }
        }
        XCTAssertEqual(out, supportedEU)
        let folder = tmp.appendingPathComponent("unpacked")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let archive = tmp.appendingPathComponent("odd.rar")
        try data.write(to: archive)
        XCTAssertTrue(ProgramChecker(programs: programs, temporaryParent: tmp).unpackExecutables(archive, into: folder))
    }

    // MARK: - The real lists

    func testCommittedManifestAndProgramLists() throws {
        var root = URL(fileURLWithPath: #filePath)
        while root.path != "/" && !fm.fileExists(atPath: root.appendingPathComponent("build.sh").path) { root.deleteLastPathComponent() }
        let manifest = try ReleaseManifest.load(root.appendingPathComponent("tools/known_releases.tsv"))
        XCTAssertEqual(manifest.releases.map { $0.id }, ["eu-disc", "eu-v12", "na-v12"])
        XCTAssertEqual(manifest.corePaths.count, 21)
        XCTAssertTrue(manifest.corePaths.map { $0.lowercased() }.contains("global/globalb.lzc"))
        XCTAssertNil(manifest.files["speed2.exe"])
        // The supported pair is the one tools/gen_v2.sh and tools/builder_cli.py accept.
        let genV2 = try String(contentsOf: root.appendingPathComponent("tools/gen_v2.sh"), encoding: .utf8)
        let cli = try String(contentsOf: root.appendingPathComponent("tools/builder_cli.py"), encoding: .utf8)
        for program in KnownProgram.supported {
            XCTAssertTrue(genV2.contains(program.sha256))
            XCTAssertTrue(cli.contains(program.sha256))
        }
        XCTAssertEqual(KnownProgram.supported.map { $0.size }, [4_788_224, 4_800_512])
    }

    // MARK: - Fixtures

    /// Every path under `root` with its size, contents digest and modification date.
    private func snapshot(_ root: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        for case let url as URL in fm.enumerator(at: root, includingPropertiesForKeys: nil)! {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let data = (attributes[.type] as? FileAttributeType) == .typeRegular ? try Data(contentsOf: url) : Data()
            out[url.path] = "\(attributes[.size] ?? 0) \(sha(data)) \(attributes[.modificationDate] ?? "")"
        }
        return out
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func crc(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    private func write(_ text: String, to url: URL) throws { try write(Data(text.utf8), to: url) }

    private func write(_ data: Data, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A PE header with the given section names.
    private func pe(sections: [String]) -> Data {
        var b = [UInt8](repeating: 0, count: 1024)
        b[0] = 0x4D; b[1] = 0x5A; b[0x3C] = 0x80
        b[0x80] = 0x50; b[0x81] = 0x45
        b[0x86] = UInt8(sections.count)
        b[0x94] = 0xE0          // optional header size
        var at = 0x80 + 24 + 0xE0
        for name in sections {
            for (i, c) in name.utf8.prefix(8).enumerated() { b[at + i] = c }
            at += 40
        }
        return Data(b)
    }

    @discardableResult
    private func makeGameFolder(_ name: String, exe: Data?, lowercase: Bool = false) throws -> URL {
        let game = tmp.appendingPathComponent(name)
        for (path, text) in files { try write(text, to: game.appendingPathComponent(lowercase ? path.lowercased() : path)) }
        if let exe = exe { try write(exe, to: game.appendingPathComponent(lowercase ? "speed2.exe" : "SPEED2.EXE")) }
        try write(server10, to: game.appendingPathComponent("server.dll"))
        return game
    }

    /// Two disc folders laid out like the PC discs: compressed.zip with backslash names,
    /// loose MOVIES and speed2.exe on disc 2, installer files that are skipped.
    private func makeDiscFolders() throws -> (URL, URL) {
        let one = tmp.appendingPathComponent("Disc 1"), two = tmp.appendingPathComponent("Disc 2")
        try write(zip([("TRACKS\\TRACKMAP4014.bin", Data("trackmap".utf8))]), to: one.appendingPathComponent("compressed.zip"))
        try write("[autorun]", to: one.appendingPathComponent("autorun.inf"))
        try write("help", to: one.appendingPathComponent("Support/readme.txt"))
        try write(zip([("GLOBAL\\", Data()), ("GLOBAL\\GLOBALB.LZC", Data("global".utf8)),
                       ("FRONTEND\\FrontB.lzc", Data("frontend v1.2".utf8)), ("server.dll", server10),
                       ("CARS\\CORSA\\GEOMETRY.BIN", Data("corsa".utf8))]),
                  to: two.appendingPathComponent("compressed.zip"))
        try write("movie", to: two.appendingPathComponent("MOVIES/intro.vp6"))
        try write(discExe, to: two.appendingPathComponent("speed2.exe"))
        try write("x", to: two.appendingPathComponent("00000001.TMP"))
        return (one, two)
    }

    private func makeISO(_ folder: URL) throws -> URL {
        let iso = tmp.appendingPathComponent("\(folder.lastPathComponent)-\(UUID().uuidString).iso")
        let result = SystemCommandRunner().run("/usr/bin/hdiutil", ["makehybrid", "-iso", "-joliet", "-quiet",
                                                                    "-default-volume-name", "NFSUG2", "-o", iso.path, folder.path])
        XCTAssertEqual(result.status, 0, result.output)
        return iso
    }

    /// A raw MODE1/2352 .bin of the ISO and its .cue.
    private func makeCueBin(_ iso: URL, name: String) throws -> URL {
        let data = try Data(contentsOf: iso)
        var raw = Data()
        let sync: [UInt8] = [0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00]
        for sector in 0..<(data.count / 2048) {
            raw.append(contentsOf: sync + [0, 0, 0, 1])
            raw.append(data[(sector * 2048)..<((sector + 1) * 2048)])
            raw.append(contentsOf: [UInt8](repeating: 0, count: 288))
        }
        let bin = tmp.appendingPathComponent("\(name).bin")
        try raw.write(to: bin)
        let cue = tmp.appendingPathComponent("\(name).cue")
        try write("FILE \"\(name).bin\" BINARY\r\n  TRACK 01 MODE1/2352\r\n    INDEX 01 00:00:00\r\n", to: cue)
        return cue
    }

    /// A stored (uncompressed) zip with the names as given.
    private func zip(_ entries: [(String, Data)]) -> Data {
        var out = Data(), directory = Data()
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
        for (name, data) in entries {
            let offset = UInt32(out.count), crc = self.crc(data), size = UInt32(data.count)
            let nameBytes = [UInt8](name.utf8)
            out.append(contentsOf: u32(0x0403_4B50) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(crc) + u32(size) + u32(size)
                + u16(nameBytes.count) + u16(0) + nameBytes)
            out.append(data)
            directory.append(contentsOf: u32(0x0201_4B50) + u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(crc)
                + u32(size) + u32(size) + u16(nameBytes.count) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(offset) + nameBytes)
        }
        let start = UInt32(out.count)
        out.append(directory)
        out.append(contentsOf: u32(0x0605_4B50) + u16(0) + u16(0) + u16(entries.count) + u16(entries.count)
            + u32(UInt32(directory.count)) + u32(start) + u16(0))
        return out
    }
}
