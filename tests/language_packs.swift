// tests/language_packs.swift: the language pack builder (launcher/LanguagePacks.swift)
// on made-up data: an endscript's texts merged into a language file, the gzip and
// Astrum installer readers (the Polish layout and the older Hungarian one), the Inno
// Setup reader and its LZMA decoder (the Ukrainian installer), the Clickteam patch reader
// and its deflate (the Czech translation), the NSIS reader and its bzip2 (the Slovak
// one), a pack holding only what
// differs from the game folder, and the RAR reader refusing what it is not.  No game
// files, no internet.
import Foundation
import CryptoKit

@main
struct LanguagePackTests {
    static var fails = 0
    static func check(_ ok: Bool, _ what: String) {
        print((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { fails += 1 }
    }
    static func le(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    static func rd(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }

    /// a language file: a chunk before, the text chunk, a pad chunk, a "font" chunk at 0x80
    static func languageFile(_ texts: [(UInt32, String)]) -> [UInt8] {
        let sorted = texts.sorted { $0.0 < $1.0 }
        let tab = 16 + 8                                 // header, then an 8-byte character table
        var strs: [UInt8] = [], table: [UInt8] = []
        for (h, t) in sorted { table += le(Int(h)) + le(strs.count); strs += Array(t.utf8) + [0] }
        while strs.count % 4 != 0 { strs.append(0) }
        let body = le(16) + le(sorted.count) + le(tab) + le(tab + table.count) + [UInt8](repeating: 7, count: 8) + table + strs
        var f = le(0x1234) + le(8) + [UInt8](repeating: 1, count: 8)
        f += le(0x39000) + le(body.count) + body
        let pad = (0x80 - (f.count + 8) % 0x80) % 0x80
        f += le(0) + le(pad) + [UInt8](repeating: 0, count: pad)
        f += le(0x30201) + le(4) + [9, 9, 9, 9]
        return f
    }
    static func texts(_ f: [UInt8]) -> [UInt32: String] {
        var q = 0
        while rd(f, q) != 0x39000 { q += 8 + rd(f, q + 4) }
        let c = Array(f[(q + 8)...]), n = rd(c, 4), tab = rd(c, 8), sd = rd(c, 12)
        var out: [UInt32: String] = [:]
        for i in 0..<n {
            let o = sd + rd(c, tab + 8 * i + 4)
            var e = o
            while c[e] != 0 { e += 1 }
            out[UInt32(rd(c, tab + 8 * i))] = String(decoding: c[o..<e], as: UTF8.self)
        }
        return out
    }

    static func main() throws {
        // endscript
        let end = """
            update_string LANGUAGES\\ENGLISH.BIN STRBlocks STR_1 0xD1619869 Text "But if you can't beat them, join them."
            update_string LANGUAGES\\ENGLISH.BIN STRBlocks STR_1 0xD1619869 Label "SCENE01_A"
            update_string LANGUAGES\\ENGLISH.BIN STRBlocks STR_1 0x00000010 Text "Rachel: Hey."
            update_string LANGUAGES\\GERMAN.BIN STRBlocks STR_1 0x00000011 Text "Nein"
            """
        let t = try LanguagePacks.endTexts(end)
        check(t == [0xd161_9869: "But if you can't beat them, join them.", 0x10: "Rachel: Hey."], "endscript texts for English only")
        do { _ = try LanguagePacks.endTexts("update_string LANGUAGES\\ENGLISH.BIN STRBlocks S 0x10 Key 0x11"); check(false, "a Key moving a text is refused") }
        catch { check(true, "a Key moving a text is refused") }

        // language file
        let file = languageFile([(0x10, "Hi"), (0xd161_9869, "But if you"), (0x20, "Same")])
        let (out, changed) = try LanguagePacks.withTexts(Data(file), t.merging([0x20: "Same"]) { a, _ in a })
        let o = [UInt8](out)
        check(changed == 2, "two texts changed, the same one left (\(changed))")
        check(texts(o) == [0x10: "Rachel: Hey.", 0xd161_9869: "But if you can't beat them, join them.", 0x20: "Same"], "the file has the new texts")
        check(Array(o[0..<16]) == Array(file[0..<16]), "the chunk before the text is kept")
        let font = o.count - 12
        check(font % 0x80 == 0 && Array(o[font...]) == le(0x30201) + le(4) + [9, 9, 9, 9], "the font chunk stays 0x80-aligned and unchanged")

        // gzip
        let gz: [UInt8] = [0x1f,0x8b,0x08,0x00,0x00,0x00,0x00,0x00,0x02,0x03,0xf3,0x48,0xcd,0xc9,0xc9,0xd7,0x51,0xf0,0x73,0x0b,0x0e,0x35,0x52,0x28,0x48,0x4c,0xce,0x2e,0x56,0xe4,0x02,0x00,0x2a,0xd9,0xad,0xa0,0x14,0x00,0x00,0x00]
        check(String(decoding: try LanguagePacks.gunzipIfNeeded(Data(gz)), as: UTF8.self) == "Hello, NFSU2 packs!\n", "a gzip stream is read")
        check(try LanguagePacks.gunzipIfNeeded(Data("plain".utf8)) == Data("plain".utf8), "other bytes stay as they are")

        // Astrum installer
        var inst: [UInt8] = Array("MZ".utf8) + [UInt8](repeating: 0, count: 300)
        let start = inst.count
        for (name, data) in [("LANGUAGES\\Polish.bin", Array("polish text".utf8)), ("CREDITS\\POLISH.TXT", gz)] {
            let nm = Array("<InstallDir>\\\(name)".utf8).map { b -> UInt8 in
                var v: UInt8 = 0
                for i in 0..<8 where b >> (i ^ 6) & 1 != 0 { v |= 1 << i }
                return v
            }
            var rec = [UInt8](repeating: 0, count: 0x40)
            rec.replaceSubrange(0x2c..<0x30, with: le(nm.count))
            let endAt = inst.count + 0x40 + nm.count + 4 + data.count
            inst += rec + nm + le(endAt) + data
        }
        let head = inst.count
        var words = [Int](repeating: 0, count: 59); words[48] = start; words[49] = head - start
        for w in words { inst += [UInt8(w >> 24 & 255), UInt8(w >> 16 & 255), UInt8(w >> 8 & 255), UInt8(w & 255)] }
        inst += le(head) + [UInt8](repeating: 0, count: 20) + le(20) + le(0x0b1c2d3e) + le(0x1234_5678)
        let files = try LanguagePacks.astrumFiles(Data(inst))
        check(files["languages/polish.bin"] == Data("polish text".utf8), "the installer's stored file")
        check(files["credits/polish.txt"] == Data("Hello, NFSU2 packs!\n".utf8), "the installer's gzip file")
        do { _ = try LanguagePacks.astrumFiles(Data("MZ not an installer".utf8)); check(false, "another .exe is refused") }
        catch { check(true, "another .exe is refused") }

        // a pack in a made-up game folder
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-langtest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let game = tmp.appendingPathComponent("game"), mod = tmp.appendingPathComponent("mod/script")
        try fm.createDirectory(at: game.appendingPathComponent("Languages"), withIntermediateDirectories: true)
        try fm.createDirectory(at: mod, withIntermediateDirectories: true)
        try Data(file).write(to: game.appendingPathComponent("Languages/English.bin"))
        try end.write(to: mod.appendingPathComponent("main.end"), atomically: true, encoding: .utf8)
        let s = try LanguagePacks.buildSubtitles(mod: tmp.appendingPathComponent("mod"), game: game)
        let built = game.appendingPathComponent("LANGPACKS/english/Languages/English.bin")
        check(fm.fileExists(atPath: built.path), "English's pack, spelled as the game folder spells it (\(s))")
        check(texts([UInt8](try Data(contentsOf: built)))[0xd161_9869] == "But if you can't beat them, join them.", "the pack has the whole line")
        let p = LanguagePacks.Pack(game: game, lang: "english")
        try p.add(Data(file), "LANGUAGES/English.bin")      // the game's own file: nothing to add
        try "stale".write(to: game.appendingPathComponent("LANGPACKS/english/old.txt"), atomically: true, encoding: .utf8)
        p.finish()
        check(p.files == 0 && !fm.fileExists(atPath: built.path) && !fm.fileExists(atPath: game.appendingPathComponent("LANGPACKS/english").path),
              "a file like the game's is not kept, an earlier build's are removed")

        // RAR reader
        let junk = Data("Rar!\u{1a}\u{07}\u{00} RAR 4".utf8)
        let refused = junk.withUnsafeBytes { b -> Bool in (try? RarArchive.list(b)) == nil }
        check(refused, "a RAR 4 archive is left to bsdtar")
        var crc = RarArchive.CRC32()
        "123456789".utf8CString.dropLast().withUnsafeBytes { crc.update($0) }
        check(crc.value == 0xcbf4_3926, "CRC32 check value")
        try installers()
        try czech()
        try slovak()
        try malicious()
        exit(fails == 0 ? 0 : 1)
    }

    // MARK: Hungarian and Ukrainian installers

    static func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = [], it = s.makeIterator()
        while let a = it.next(), let b = it.next() { out.append(UInt8(String([a, b]), radix: 16)!) }
        return out
    }
    static func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
    /// an Astrum InstallWizard installer with these files; tail: what comes between the
    /// header's offset and the magic (n bytes, then n)
    static func astrum(_ files: [(String, [UInt8])], tail: [UInt8]) -> [UInt8] {
        var inst: [UInt8] = Array("MZ".utf8) + [UInt8](repeating: 0, count: 300)
        let start = inst.count
        for (name, data) in files {
            let nm = Array("<InstallDir>\\\(name)".utf8).map { b -> UInt8 in
                var v: UInt8 = 0
                for i in 0..<8 where b >> (i ^ 6) & 1 != 0 { v |= 1 << i }
                return v
            }
            var rec = [UInt8](repeating: 0, count: 0x40)
            rec.replaceSubrange(0x2c..<0x30, with: le(nm.count))
            let endAt = inst.count + 0x40 + nm.count + 4 + data.count
            inst += rec + nm + le(endAt) + data
        }
        let head = inst.count
        var words = [Int](repeating: 0, count: 59); words[48] = start; words[49] = head - start
        for w in words { inst += be32(w) }
        return inst + le(head) + tail + le(0x0b1c2d3e) + le(0x1234_5678)
    }

    // the Ukrainian fixture's nine files, one LZMA chunk (tools: Python's lzma, FORMAT_RAW,
    // LZMA1, dict 64 KB, lc 3, lp 0, pb 2: it ends with the end marker)
    static let ukContents: [[UInt8]] = (0..<9).map { i in
        Array("uk\(i): \(String(repeating: "Ukrainian text \(i % 3) ", count: 8 + i))".utf8) + (i * 20..<(i * 20 + 40)).map { UInt8($0) }
    }
    static let ukProps: [UInt8] = [0x5d, 0, 0, 1, 0]
    static let ukStream = hex(
        "003a9ac2022029593b7ddbc4024976bed0341031830ce407c24ede8013445eddcc5cb0b63fbeca1330c8e97a207e9f45aa1c59913d7ca431bb9862be"
        + "7ad3a93ec9d8a066dca646b4b31b5c417b8941506458ee74b4cdc41c573613b77d3e5fc27183c66338c6211f38509183a0f363d386348c8298577394"
        + "053be505330a19aadccedef84a4399c07d93f22634ef348e6cf2ae48b88e4a0abe1f2c46d4431e6e34283a1e1efbbc1ab85f5089b3866cbfa53fe8d4"
        + "9bfe5f682e074ef413a2b8ab63691acd9a213ff01d0b7bed49a152ab0e99059499b93640fe69963da0da81a3a7852c976395d56559cae04486bd0e27"
        + "8ad1a36387bb5a10630b9e415179a36484a9e8a8e04c10fab73cae0c3e3462d2b53a33a15e497de005fb86c3069a44c9b839468660394a27d4c7fffb"
        + "e2f233")

    static func crc(_ b: [UInt8]) -> Int {
        var c = RarArchive.CRC32()
        b.withUnsafeBytes { c.update($0) }
        return Int(c.value)
    }
    /// one of setup-0's blocks, stored (not compressed)
    static func innoBlock(_ content: [UInt8]) -> [UInt8] {
        var pieces: [UInt8] = [], q = 0
        repeat {
            let n = min(4096, content.count - q)
            let piece = Array(content[q..<(q + n)])
            pieces += le(crc(piece)) + piece; q += n
        } while q < content.count
        let head = le(pieces.count) + [0]
        return le(crc(head)) + head + pieces
    }
    /// an Inno Setup 5.5.0 installer: the files in one LZMA chunk, flags for every entry
    static func inno(flags: Int = 0x80, chunk: [UInt8]? = nil) -> [UInt8] {
        var exe: [UInt8] = Array("MZ".utf8) + [UInt8](repeating: 0, count: 0x200 - 2)
        let tableAt = 0x100
        let off1 = exe.count
        let packed = chunk ?? ukProps + ukStream
        exe += InnoSetup.chunkMagic + packed
        var entries: [UInt8] = [], sub = 0
        for f in ukContents {
            var e = le(0) + le(0) + le(0) + le(sub) + le(0) + le(f.count) + le(0) + le(packed.count) + le(0)
            e += Array(Insecure.SHA1.hash(data: f)) + [UInt8](repeating: 0, count: 16) + [UInt8(flags & 255), UInt8(flags >> 8)]
            entries += e; sub += f.count
        }
        let off0 = exe.count
        var id = Array("Inno Setup Setup Data (5.5.0)".utf8); id += [UInt8](repeating: 0, count: 64 - id.count)
        exe += id + innoBlock(Array("the setup header, not read".utf8)) + innoBlock(entries)
        let table0 = InnoSetup.tableID + le(1) + le(exe.count) + le(0) + le(0) + le(0) + le(off0) + le(off1)
        let table = table0 + le(crc(table0))
        exe.replaceSubrange(tableAt..<(tableAt + table.count), with: table)
        return exe
    }

    static func installers() throws {
        // LZMA: the whole stream to its end marker, and only its start
        let all = ukContents.flatMap { $0 }
        check(try LZMA.decode(ukStream, props: ukProps, size: nil) == all, "an LZMA stream to its end marker (\(all.count) bytes)")
        check(try LZMA.decode(ukStream, props: ukProps, size: 100) == Array(all[0..<100]), "an LZMA stream's first 100 bytes")
        refused("an LZMA stream cut short of the size asked") { _ = try LZMA.decode(Array(ukStream.prefix(150)), props: ukProps, size: all.count) }
        // without a size it ends where its input does (the installer's header blocks have
        // no end marker; their CRC32s say they are whole)
        let head = try LZMA.decode(Array(ukStream.prefix(150)), props: ukProps, size: nil)
        check(head.count < all.count && head == Array(all[0..<head.count]), "an LZMA stream without a size ends with its input (\(head.count) bytes)")
        refused("LZMA properties out of range") { _ = try LZMA.decode(ukStream, props: [225, 0, 0, 1, 0], size: nil) }
        for cut in stride(from: 0, to: ukStream.count, by: 7) {             // must not trap
            var bad = ukStream; bad[cut] ^= 0x5a
            _ = try? LZMA.decode(bad, props: ukProps, size: nil)
            _ = try? LZMA.decode(Array(ukStream.prefix(cut)), props: ukProps, size: all.count)
        }
        check(true, "every damaged LZMA stream returned or threw")

        // the Inno Setup reader
        let exe = inno()
        let setup = try InnoSetup.read(exe)
        check(setup.entries.count == 9, "the installer's nine data entries")
        check(try InnoSetup.file(exe, setup.entries[4]) == Data(ukContents[4]), "a file in the middle of its chunk, SHA-1 checked")
        refused("not an Inno Setup installer") { _ = try InnoSetup.read(Array("MZ nothing".utf8) + [UInt8](repeating: 0, count: 100)) }
        var badCRC = exe; badCRC[badCRC.count - 3] ^= 1
        refused("a data entries block whose CRC32 is wrong") { _ = try InnoSetup.read(badCRC) }
        var badFile = exe; badFile[0x200 + 4 + 5 + 40] ^= 1
        refused("a file whose SHA-1 is wrong") {
            let s = try InnoSetup.read(badFile)
            for e in s.entries { _ = try InnoSetup.file(badFile, e) }
        }
        let enc = inno(flags: 0xc0)
        refused("an encrypted file") { _ = try InnoSetup.file(enc, try InnoSetup.read(enc).entries[0]) }
        let bcj = inno(flags: 0x90)
        refused("a file with the x86 call filter") { _ = try InnoSetup.file(bcj, try InnoSetup.read(bcj).entries[0]) }
        var newer = exe
        let at = 0x200 + 4 + ukProps.count + ukStream.count
        newer.replaceSubrange((at + 23)..<(at + 26), with: Array("6.0".utf8))
        refused("an Inno Setup installer of another version") { _ = try InnoSetup.read(newer) }

        // the packs, in a made-up game folder
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-langinst-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let game = tmp.appendingPathComponent("game"), packs = tmp.appendingPathComponent("packs")
        try fm.createDirectory(at: game.appendingPathComponent("CREDITS"), withIntermediateDirectories: true)
        try Data(ukContents[8]).write(to: game.appendingPathComponent("CREDITS/UK_ENGLISH.TXT"))   // as the game's: not kept
        let ukExe = tmp.appendingPathComponent("uk.exe")
        try Data(exe).write(to: ukExe)
        let s = try LanguagePacks.buildUkrainian(installer: ukExe, game: game, packs: packs)
        let uk = packs.appendingPathComponent("ukrainian")
        check(s == "ukrainian: 5 files, 0.0 MB", "Ukrainian's pack (\(s))")
        check((try? Data(contentsOf: uk.appendingPathComponent("GLOBAL/GLOBALA.BUN"))) == Data(ukContents[4]), "entry 4 is its GLOBAL/GLOBALA.BUN")
        check((try? Data(contentsOf: uk.appendingPathComponent("CREDITS/NA_ENGLISH.TXT"))) == Data(ukContents[7]), "entry 7 is its CREDITS/NA_ENGLISH.TXT")
        check(!fm.fileExists(atPath: uk.appendingPathComponent("LANGUAGES/Labels.bin").path)
              && !fm.fileExists(atPath: uk.appendingPathComponent("CREDITS/UK_ENGLISH.TXT").path),
              "the files the game does not read, and the one like the game's, are left out")
        refused("an imported Ukrainian installer that is not the pinned release") {
            _ = try LanguagePacks.importCopy(lang: "ukrainian", src: ukExe, game: game, packs: packs)
        }

        let huExe = tmp.appendingPathComponent("nfs_underground2.exe")
        try Data(astrum([("LANGUAGES\\English.bin", Array("magyar sz\u{F6}veg".utf8)), ("memcard\\LOCALE_ENGLISH.loc", Array("loc".utf8)),
                         ("CREDITS\\NA_ENGLISH.TXT", Array("na".utf8)), ("CREDITS\\UK_ENGLISH.TXT", Array("uk".utf8))],
                        tail: le(0xffff_ffff))).write(to: huExe)
        let files = try LanguagePacks.astrumFiles(try Data(contentsOf: huExe))
        check(files["languages/english.bin"] == Data("magyar sz\u{F6}veg".utf8), "the older Astrum layout (no block before the magic, 0xffffffff)")
        let h = try LanguagePacks.buildHungarian(installer: huExe, game: game, packs: packs)
        check(h == "hungarian: 4 files, 0.0 MB" && fm.fileExists(atPath: packs.appendingPathComponent("hungarian/memcard/LOCALE_ENGLISH.loc").path),
              "Hungarian's pack (\(h))")
        refused("an imported Hungarian installer that is not the pinned release") {
            _ = try LanguagePacks.importCopy(lang: "hungarian", src: tmp, game: game, packs: packs)
        }
        let partial = tmp.appendingPathComponent("partial.exe")
        try Data(astrum([("LANGUAGES\\English.bin", [1])], tail: le(0xffff_ffff))).write(to: partial)
        refused("a Hungarian installer without all the translation's files") { _ = try LanguagePacks.buildHungarian(installer: partial, game: game, packs: packs) }
        check(LanguagePacks.way("hungarian") == .download && LanguagePacks.way("ukrainian") == .download, "both download in one click")
    }

    // MARK: the Czech translation's Clickteam patch

    /// the fixture's text, and it in Clickteam's deflate with dynamic codes (zlib's raw
    /// deflate at level 9, its block headers, code length order and stored lengths
    /// rewritten as Clickteam's; checked with a decoder written from the patch program)
    static let ctText: [UInt8] = cat(Array(String(repeating: "Cestina do hry Need for Speed: Underground 2 - zkusebni text. ", count: 3).utf8),
        Array(String(repeating: "Zpet na hlavni menu. Opravdu chces prepsat predchozi ulozeni hry? ", count: 4).utf8),
        (0..<120).map { (i: Int) -> UInt8 in UInt8(65 + (i * 7) % 26) })
    static let ctDynamic = hex(
        "bedb931cd04e020000b8cabb802c5cba318af3002ae2c0aed2af2562db7420cae9ad873026aedecb1b63b2ae920c5c41981712228eab32c874603de4"
        + "9293b919e52547171db4776fe9222b387aba08f10fdb852687d016356b82f820e923a4dab0867b94a2240b6d485be63ec84ba1da0abe562d8574f8eb"
        + "ffc9c260961ee2c5f6345e65c534c987f3cd71b4dc9d27ebfd779d37")
    /// the patch's title block, as the translation's patch has it (fixed codes)
    static let ctTitle = hex("7d22755649665ea2424abe424651a5825f6a6a8a425a7e914270019065a5109a97925a945e945f9a97a260c40000")

    /// data as one stored block of Clickteam's deflate (header 7 | last, its length, no complement)
    static func ctStored(_ data: [UInt8]) -> [UInt8] { [0x0f, UInt8(data.count & 255), UInt8(data.count >> 8)] + data }
    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
    static func ctBlock(_ id: Int, _ data: [UInt8], packed: [UInt8]? = nil) -> [UInt8] {
        if let p = packed { return le16(id) + le16(1) + le(4 + p.count) + le(data.count) + p }
        return le16(id) + le16(0) + le(data.count) + data
    }
    /// a Clickteam patch carrying these files whole: (path, data, the old version's size)
    static func ctPatch(_ files: [(String, [UInt8], Int)], packed: [String: [UInt8]] = [:]) -> [UInt8] {
        var exe = [UInt8](repeating: 0, count: 0x100)
        exe[0] = 0x4d; exe[1] = 0x5a; exe[0x3c] = 0x40
        exe.replaceSubrange(0x40..<0x44, with: Array("PE".utf8) + [0, 0])
        exe[0x46] = 1                                       // one section, no optional header
        exe.replaceSubrange((0x58 + 16)..<(0x58 + 24), with: le(0x80) + le(0x80))   // its size and offset: it ends at 0x100
        var list = le(files.count), data: [UInt8] = []
        for (path, content, old) in files {
            let stream = packed[path] ?? ctStored(content)
            var r = [UInt8](repeating: 0, count: 0x36) + Array(path.utf8) + [0, 0]
            let at = r.count
            r += le(0x1234_5678) + le(old) + le(data.count) + le(stream.count)
            r.replaceSubrange(0..<4, with: le(r.count))
            r[8] = 0x22
            r.replaceSubrange(0x0a..<0x12, with: le(Int(Clickteam.checksum(content))) + le(content.count))
            r.replaceSubrange(0x14..<0x18, with: le16(1) + le16(at))
            list += r; data += stream
        }
        exe += ctBlock(0x1238, Array("Čeština do hry Need for Speed: Underground 2".data(using: .windowsCP1250)!) + [0], packed: ctTitle)
        exe += ctBlock(0x1242, list, packed: ctStored(list))
        exe += le16(0x7f7f) + le16(0) + le(4 + data.count) + le(4 + data.count) + data
        return exe
    }

    static func czech() throws {
        check(Clickteam.checksum([1, 0, 0, 0, 2, 0, 0, 0, 3]) == 11, "the patch program's checksum (turn left, add; the last bytes one at a time)")
        check(try Clickteam.inflate(ArraySlice(ctDynamic), size: ctText.count) == ctText, "Clickteam's deflate with dynamic codes (\(ctText.count) bytes)")
        refused("a Clickteam stream asked for more than it holds") { _ = try Clickteam.inflate(ArraySlice(ctDynamic), size: ctText.count + 1) }
        refused("a Clickteam stream asked for less than it holds") { _ = try Clickteam.inflate(ArraySlice(ctDynamic), size: ctText.count - 1) }
        refused("a Clickteam stream with RFC 1951's block header") { _ = try Clickteam.inflate([0x01, 3, 0, 0xfc, 0xff, 1, 2, 3], size: 3) }
        for cut in stride(from: 0, to: ctDynamic.count, by: 3) {          // must not trap
            var bad = ctDynamic; bad[cut] ^= 0xa5
            _ = try? Clickteam.inflate(ArraySlice(bad), size: ctText.count)
            _ = try? Clickteam.inflate(ArraySlice(ctDynamic.prefix(cut)), size: ctText.count)
        }
        check(true, "every damaged Clickteam stream returned or threw")

        let english = languageFile([(0x1111, "Zurück zum Hauptmenü"), (0x0381_2413, ""), (0x2222, "Zpet")])
        let patch = ctPatch([("LANGUAGES\\English.bin", english, 270_456), ("LANGUAGES\\German.bin", english, 283_896),
                             ("memcard\\LOCALE_ENGLISH.loc", ctText, 668)], packed: ["memcard\\LOCALE_ENGLISH.loc": ctDynamic])
        let read = try Clickteam.read(patch)
        check(read.title == "Čeština do hry Need for Speed: Underground 2" && read.entries.map { $0.path }
                == ["LANGUAGES\\English.bin", "LANGUAGES\\German.bin", "memcard\\LOCALE_ENGLISH.loc"],
              "the patch's title and file list (\(read.title))")
        check(try Clickteam.file(patch, read, read.entries[2]) == Data(ctText), "a file the patch carries whole, its checksum checked")
        var badSum = patch
        badSum[badSum.count - 1] ^= 1
        refused("a file whose checksum is wrong") { let r = try Clickteam.read(badSum); _ = try Clickteam.file(badSum, r, r.entries[2]) }
        refused("not a Clickteam patch") { _ = try Clickteam.read(Array(patch[0..<0x100]) + [0x99, 0x99, 0, 0, 4, 0, 0, 0, 1, 2, 3, 4]) }
        refused("a patch with no file list") { _ = try Clickteam.read(Array(patch[0..<0x100]) + le16(0x7f7f) + le16(0) + le(4) + le(4)) }
        for cut in stride(from: 0x100, to: patch.count, by: 5) {           // must not trap
            var bad = patch; bad[cut] ^= 0x5a
            if let r = try? Clickteam.read(bad) { for e in r.entries { _ = try? Clickteam.file(bad, r, e) } }
            _ = try? Clickteam.read(Array(patch.prefix(cut)))
        }
        check(true, "every damaged patch returned or threw")

        // the pack: the patch's English.bin with our texts, its memory-card texts
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-langcz-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let game = tmp.appendingPathComponent("game"), packs = tmp.appendingPathComponent("packs")
        try fm.createDirectory(at: game.appendingPathComponent("LANGUAGES"), withIntermediateDirectories: true)
        try Data(languageFile([(0x1111, "Back to Main Menu")])).write(to: game.appendingPathComponent("LANGUAGES/English.bin"))
        let exe = tmp.appendingPathComponent("nfsu2cz-v1.1.exe")
        try Data(patch).write(to: exe)
        let s = try LanguagePacks.buildCzech(installer: exe, game: game, packs: packs)
        check(s.hasPrefix("czech: 2 files"), "Czech's pack (\(s))")
        let built = [UInt8](try Data(contentsOf: packs.appendingPathComponent("czech/LANGUAGES/English.bin")))
        var q = 0
        while rd(built, q) != 0x39000 { q += 8 + rd(built, q + 4) }
        let c = Array(built[(q + 8)...]), n = rd(c, 4), tab = rd(c, 8), sd = rd(c, 12)
        var got: [UInt32: [UInt8]] = [:]
        for i in 0..<n {
            let o = sd + rd(c, tab + 8 * i + 4)
            got[UInt32(rd(c, tab + 8 * i))] = Array(c[o..<c[o...].firstIndex(of: 0)!])
        }
        let ours = try CzechTexts.bytes()
        check(ours[0x0381_2413] != nil && got[0x0381_2413] == ours[0x0381_2413] && got[0x2222] == Array("Zpet".utf8),
              "the empty movie line filled in, in the game's letters; the translation's own texts kept")
        let acute: Set<UInt8> = [0xc1, 0xc9, 0xcd, 0xd3, 0xda, 0xdd, 0xe1, 0xe9, 0xed, 0xf3, 0xfa, 0xfd]
        func fontLetter(_ b: UInt8) -> Bool { (b >= 0x20 && b < 0x7f) || acute.contains(b) }
        check(ours.values.allSatisfy { t in !t.isEmpty && t.allSatisfy(fontLetter) },
              "our Czech texts use only ASCII and the fonts' \u{E1}\u{E9}\u{ED}\u{F3}\u{FA}\u{FD} (\(ours.count) texts)")
        check(fm.fileExists(atPath: packs.appendingPathComponent("czech/memcard/LOCALE_ENGLISH.loc").path)
              && !fm.fileExists(atPath: packs.appendingPathComponent("czech/LANGUAGES/German.bin").path), "its memory-card texts; not its German.bin")
        let same = tmp.appendingPathComponent("same.exe")
        try Data(ctPatch([("LANGUAGES\\English.bin", languageFile([(0x1111, "Back to Main Menu")]), 1), ("memcard\\LOCALE_ENGLISH.loc", [1], 1)])).write(to: same)
        refused("a patch whose English.bin is the game's own") { _ = try LanguagePacks.buildCzech(installer: same, game: game, packs: packs) }
        refused("an imported Czech patch that is not the pinned release") {
            _ = try LanguagePacks.importCopy(lang: "czech", src: exe, game: game, packs: packs)
        }
        check(LanguagePacks.way("czech") == .download && LanguagePacks.installers["czech"]?.inner?.name == "nfsu2cz-v1.1.exe",
              "Czech downloads in one click, as the zip abcgames.cz serves")
    }

    // MARK: the Slovak translation's NSIS installer

    /// the fixture's text, and it in NSIS's bzip2 (Python's bz2 at level 9, its stream
    /// header, block magic, CRCs, randomised bit and end magic rewritten as NSIS's)
    static let bzText: [UInt8] = cat(Array(String(repeating: "Slovencina do hry Need for Speed: Underground 2. ", count: 3).utf8),
        [UInt8](repeating: 0x61, count: 42), (0..<256).map { UInt8($0) }, Array(String(repeating: "zzzzz", count: 40).utf8))
    static let bzNSIS = hex(
        "31000079ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6002368c24c0013000130000000000000000000000"
        + "000000000000000000000000000000000010d0982600000000684c000004c00023013000000000000000000000000000004c00000000019faa21a834"
        + "1a641341e80862309a00311a68d31304c40c9847a219033447a00460234d0c988609a6418868d0d0d1a190d31061190c8c2340c46430830cb12518"
        + "3268b46474849369496989a7138e9e4f505152c829e472593ca1f5455402043010843102900341f415159616970501025e6063fa323338006a286c"
        + "6e2800e024e4e8ecf0f4f87401f8fa020a121a222a323a47ed25292d313539b9bf587c3838b96b75de12c11b0d8941cdd364eaeceef1b3da20797e"
        + "0c812f6a56d8c901ec80f6502c18202984218110241934373ab1ba303766c6f1f5f8f842641b0882a0804d078e038120248713c48360e8de9d08fb"
        + "e2c22241c51812c41634210e84910b0d0f1113bfe04545c646c747c87078523c392e27178d21232527292b2d2f31333537393b3d3f41434547494b"
        + "4d4f51535557595b5d5f61636567696b6d6f71737577797b7d7f81828b84e387898b8d8f91939597999b9d9fa1a3a5a7a9abadafb1b3b5b7b9bbbd"
        + "bfc1c3c5c7c9cbcdcfd1d3d5d7d9dbdddfe1e3e5e7e9ebedeff1f3f5f7f9fa2e")

    /// an NSIS 2 installer: its program, the first header, a script header, these files
    /// (compressed when given as NSIS bzip2), its CRC
    static func nsis(_ files: [(data: [UInt8], packed: Bool)]) -> [UInt8] {
        var exe: [UInt8] = Array("MZ".utf8) + [UInt8](repeating: 0, count: 0x400 - 2)   // the first header at 0x400
        var body = le(0x8000_0000 | 6) + [0x31, 1, 2, 3, 4, 0x17]          // the script header, not read
        for f in files { body += le(f.data.count | (f.packed ? 0x8000_0000 : 0)) + f.data }
        let total = 28 + body.count + 4
        exe += le(0) + NSIS.magic + le(6) + le(total) + body + le(0x1234_5678)
        return exe
    }

    static func slovak() throws {
        check(try NSIS.bunzip(ArraySlice(bzNSIS)) == bzText, "NSIS's bzip2 (\(bzText.count) bytes: runs, every byte value)")
        refused("NSIS bzip2 with bzip2's own header") { _ = try NSIS.bunzip(ArraySlice(Array("BZh9".utf8) + bzNSIS)) }
        for cut in stride(from: 0, to: bzNSIS.count, by: 3) {              // must not trap
            var bad = bzNSIS; bad[cut] ^= 0x5a
            _ = try? NSIS.bunzip(ArraySlice(bad))
            _ = try? NSIS.bunzip(ArraySlice(bzNSIS.prefix(cut)))
        }
        check(true, "every damaged NSIS bzip2 stream returned or threw")

        let inst = nsis([(Array("as it is".utf8), false), (bzNSIS, true)])
        let es = try NSIS.entries(inst)
        let stored = try NSIS.file(inst, es[0]), packed = try NSIS.file(inst, es[1])
        check(es.count == 2 && stored == Array("as it is".utf8) && packed == bzText, "an NSIS installer's files, stored and compressed")
        refused("not an NSIS installer") { _ = try NSIS.entries(Array("MZ".utf8) + [UInt8](repeating: 0, count: 2000)) }
        for cut in stride(from: 0x400, to: inst.count, by: 7) {            // must not trap
            var bad = inst; bad[cut] ^= 0xa5
            if let e = try? NSIS.entries(bad) { for x in e { _ = try? NSIS.file(bad, x) } }
            _ = try? NSIS.entries(Array(inst.prefix(cut)))
        }
        check(true, "every damaged NSIS installer returned or threw")

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-langsk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp.appendingPathComponent("game"), withIntermediateDirectories: true)
        let exe = tmp.appendingPathComponent("NFSU2UK_SK.exe")
        try Data(nsis((0..<14).map { _ in (bzNSIS, true) })).write(to: exe)
        refused("a Slovak installer whose files are not the release's") {
            _ = try LanguagePacks.buildSlovak(installer: exe, game: tmp.appendingPathComponent("game"), packs: tmp.appendingPathComponent("packs"))
        }
        check(!fm.fileExists(atPath: tmp.appendingPathComponent("packs/slovak").path), "nothing of it written")
        refused("an imported Slovak installer that is not the pinned release") {
            _ = try LanguagePacks.importCopy(lang: "slovak", src: tmp, game: tmp.appendingPathComponent("game"), packs: tmp.appendingPathComponent("packs"))
        }
        check(LanguagePacks.way("slovak") == .download && LanguagePacks.installers["slovak"]?.others.first?.inner.name == "NFSU2US_SK.exe",
              "Slovak downloads in one click; Import… takes the American game's installer too")
    }

    // MARK: crafted inputs: each must be refused with an error, never trap or write outside

    static func vint(_ v: Int) -> [UInt8] {
        var v = v, o: [UInt8] = []
        repeat { var b = UInt8(v & 0x7f); v >>= 7; if v > 0 { b |= 0x80 }; o.append(b) } while v > 0
        return o
    }
    /// joins byte arrays; long + chains are too slow to type-check for older Swift compilers
    static func cat(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }
    /// one RAR 5 block: CRC (not checked), size, the header's fields
    static func block(_ fields: [UInt8]) -> [UInt8] { cat([0, 0, 0, 0], vint(fields.count), fields) }
    /// a RAR 5 archive with one stored file
    static func rar(name: String, data: [UInt8], extra: [UInt8] = []) -> [UInt8] {
        let sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]
        let main = block(cat(vint(1), vint(0), vint(0)))
        let n: [UInt8] = Array(name.utf8)
        var f: [UInt8] = cat(vint(2), vint(extra.isEmpty ? 2 : 3))
        if !extra.isEmpty { f += vint(extra.count) }
        f += cat(vint(data.count), vint(0), vint(data.count), vint(0), vint(0), vint(0), vint(n.count), n, extra)
        return cat(sig, main, block(f), data, block(cat(vint(5), vint(0), vint(0))))
    }
    static func refused(_ what: String, _ body: () throws -> Void) {
        do { try body(); check(false, "refused: " + what) } catch { check(true, "refused: " + what) }
    }

    static func malicious() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-langevil-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let game = tmp.appendingPathComponent("game"), outside = tmp.appendingPathComponent("outside")
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)

        // 1. names that point outside the pack
        let p = LanguagePacks.Pack(game: game, lang: "french")
        for bad in ["../evil.txt", "/tmp/evil.txt", "speech/../../evil.txt", "speech\\..\\..\\evil.txt", "a//b", "./a", "", "a/"] {
            refused("pack file name \"\(bad)\"") { try p.add(Data("x".utf8), bad) }
        }
        try fm.createDirectory(at: game.appendingPathComponent("LANGPACKS/french"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: game.appendingPathComponent("LANGPACKS/french/MOVIES"), withDestinationURL: outside)
        refused("a pack file through a link to another folder") { try p.add(Data("x".utf8), "MOVIES/evil.vp6") }
        check(((try? fm.contentsOfDirectory(atPath: outside.path)) ?? []).isEmpty, "nothing was written outside the pack")
        let evilRar = tmp.appendingPathComponent("evil.rar")
        try Data(rar(name: "../outside/evil.txt", data: Array("evil".utf8))).write(to: evilRar)
        refused("a RAR whose file name climbs out of the folder it is unpacked to") {
            _ = try LanguagePacks.importCopy(lang: "portuguese", src: evilRar, game: game)
        }
        check(!fm.fileExists(atPath: outside.appendingPathComponent("evil.txt").path), "the RAR's file was not written outside")
        let goodRar = tmp.appendingPathComponent("ok.rar")
        try Data(rar(name: "dir/hello.txt", data: Array("hello".utf8))).write(to: goodRar)
        let (dir, t) = try LanguagePacks.unpackedFolder(goodRar)
        check((try? String(contentsOf: dir.appendingPathComponent("dir/hello.txt"), encoding: .utf8)) == "hello", "a well-formed stored RAR 5 unpacks")
        if let t = t { try? fm.removeItem(at: t) }
        let fakeCore = tmp.appendingPathComponent("m13/nfsug2Multi13Core.rar")
        try fm.createDirectory(at: fakeCore.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(rar(name: "Languages/Chinese.bin", data: Array("not the mod".utf8))).write(to: fakeCore)
        refused("an imported Multi 13 archive that is not the pinned release") {
            _ = try LanguagePacks.importCopy(lang: "chinese", src: fakeCore.deletingLastPathComponent(), game: game)
        }
        let fake7z = tmp.appendingPathComponent("subs.7z")
        try Data("7z?".utf8).write(to: fake7z)
        refused("an imported subtitles file that is not the pinned release") {
            _ = try LanguagePacks.importCopy(lang: "english", src: fake7z, game: game)
        }

        // 2. .viv archives with sizes that lie
        func viv(n: Int, hdr: Int, entries: [(Int, Int, String)], total: Int) -> Data {
            func be(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
            var d: [UInt8] = Array("BIGF".utf8) + be(total) + be(n) + be(hdr)
            for (o, s, nm) in entries { d += be(o) + be(s) + Array(nm.utf8) + [0] }
            while d.count < total { d.append(0) }
            return Data(d)
        }
        refused(".viv shorter than its header") { _ = try LanguagePacks.vivEntries(Data("BIG".utf8)) }
        refused(".viv whose header runs past the file") { _ = try LanguagePacks.vivEntries(viv(n: 1, hdr: 4096, entries: [(0, 1, "a")], total: 64)) }
        refused(".viv claiming millions of files") { _ = try LanguagePacks.vivEntries(viv(n: 0x7fff_ffff, hdr: 64, entries: [], total: 64)) }
        refused(".viv file past the end") { _ = try LanguagePacks.vivEntries(viv(n: 1, hdr: 40, entries: [(60, 0x7fff_0000, "speech/x")], total: 64)) }
        refused(".viv name without its end") { _ = try LanguagePacks.vivEntries(viv(n: 1, hdr: 30, entries: [(0, 1, "speech/abcdefghijklmnop")], total: 64)) }
        let ok = try LanguagePacks.vivEntries(viv(n: 1, hdr: 40, entries: [(40, 4, "speech/x")], total: 64))
        check(ok.count == 1 && ok[0].0 == "speech/x" && ok[0].1 == 40, "a well-formed .viv is read")

        // 3. RAR 5 headers that lie
        let sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]
        func list(_ b: [UInt8]) throws { _ = try b.withUnsafeBytes { try RarArchive.list($0) } }
        let zero4: [UInt8] = [0, 0, 0, 0]
        refused("RAR header size past the end") { try list(cat(sig, zero4, vint(1000), [2, 0])) }
        refused("RAR number that never ends") { try list(cat(sig, zero4, [UInt8](repeating: 0xff, count: 11))) }
        refused("RAR extra area larger than its header") { try list(cat(sig, block(cat(vint(2), vint(1), vint(500), vint(0))))) }
        refused("RAR file name past its header") {
            try list(cat(sig, block(cat(vint(2), vint(0), vint(0), vint(0), vint(0), vint(0), vint(0), vint(200), [65]))))
        }
        refused("RAR data area past the end") {
            try list(cat(sig, block(cat(vint(2), vint(2), vint(1_000_000), vint(0), vint(0), vint(0), vint(0), vint(0), vint(1), [65]))))
        }
        refused("RAR CRC field past its header") { try list(cat(sig, block(cat(vint(2), vint(0), vint(4), vint(0), vint(0))))) }
        refused("RAR extra record of size 0") { try list(rar(name: "a", data: [1], extra: vint(0))) }
        refused("RAR extra record larger than the area") { try list(rar(name: "a", data: [1], extra: cat(vint(50), vint(1)))) }
        refused("RAR fields cut off mid-header") { try list(cat(sig, block(cat(vint(2), vint(0), [0x80])))) }
        for cut in stride(from: 9, to: rar(name: "abc", data: [1, 2, 3]).count, by: 3) {
            _ = try? list(Array(rar(name: "abc", data: [1, 2, 3]).prefix(cut)))   // must not trap
        }
        check(true, "every cut-off archive returned or threw")
    }
}
