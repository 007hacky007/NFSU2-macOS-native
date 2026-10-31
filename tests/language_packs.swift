// tests/language_packs.swift: the language pack builder (launcher/LanguagePacks.swift)
// on made-up data: an endscript's texts merged into a language file, the gzip and
// Astrum installer readers, a pack holding only what differs from the game folder,
// and the RAR reader refusing what it is not.  No game files, no internet.
import Foundation

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
        exit(fails == 0 ? 0 : 1)
    }
}
