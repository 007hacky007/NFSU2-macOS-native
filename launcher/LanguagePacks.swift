// Language packs: LANGPACKS/<language> in the game folder, read by the engine in
// place of the game folder's files of the same path (runtime/language.c, fileio.c).
// When the game is inside the app the packs go outside it instead (`packs`,
// Paths.outsideLanguagePacks, NFSU2_LANGPACKS for the engine): nothing is written
// into the bundle.
// A pack holds only what differs from the game folder.  After th0mk's nfsu2-web
// tools/langpacks.py, which builds the same packs.
//
// Where they come from (none of it is part of this app):
//   - KyoriAsh's "Multi 13 languages" mod (nfsmods.xyz/mod/5749; the author's MEGA
//     folder): the dubbed speech and movies of French, German, Italian, Spanish,
//     Japanese and Russian, the full Chinese, Japanese and Thai texts with their
//     fonts, Russian's text, and the Danish, Dutch and Swedish EA logos.  Download
//     fetches the archives a language needs from the author's folder, only when the
//     player clicks, and checks each against the release this was made with (SHA-256);
//     RarArchive.swift unpacks them.
//   - VileStuff's "English Subtitles Fixed" (nfsmods.xyz/mod/5286): English's movie
//     lines whole and with who speaks them; English's pack is the game's English.bin
//     with those texts.  The engine shows them with Movie subtitles on.
//   - TraduMix's and MixMods' Brazilian Portuguese translation (joao13traducoes.com),
//     PLProjekt's Polish one (portal24h.pl) and muntazam's Turkish one (moddb.com):
//     their sites refuse downloads that do not come from a browser, so the player
//     downloads them there and uses Import…  Portuguese and Polish take English's
//     place: their text, credits and memory-card texts; Polish also its fonts'
//     textures, which draw the accented letters its text uses as the Polish ones, and
//     Polish words for the two texts it left in English (the race HUD's DRAFT and its
//     tip, plTexts).  Turkish takes English's place with a text of its own, every one
//     of the game's texts translated anew (TurkishTexts.swift, from th0mk's nfsu2-web),
//     in the translation's fonts, its only files used; the credits stay the game's.
//     Thai's ordinal suffixes are emptied (thaiTexts): the race HUD drew them in a font
//     without Thai letters.  Ported from th0mk's nfsu2-web tools/langpacks.py (MIT).
//   - GameHunter's Hungarian translation (v1.1, 2005, by L_zooltan; gamehunter.hu) and
//     Clark X.'s Ukrainian one (2022, kuli.com.ua): Download fetches the installer from
//     where the author's page links it, only when the player clicks, and checks it
//     against the release this was made with (size and SHA-256); the launcher reads its
//     files and never runs it (Hungarian's is an Astrum InstallWizard one, as the Polish
//     ones; Ukrainian's an Inno Setup one, InnoSetup.swift).  Both take English's place:
//     Hungarian its text (which writes o and u with the double acute as the fonts' o
//     with the tilde and u with the circumflex), memory-card texts and credits;
//     Ukrainian also the Russian pack's fonts, which its text is written in.  Ported
//     from th0mk's nfsu2-web tools/langpacks.py --hu and --uk (MIT).
//   - ROXOR's and PINĎA & syn's Czech translation (v1.1, 2004; abcgames.cz): Download
//     fetches the zip abcgames.cz serves, checks it (size and SHA-256) and the patch in
//     it, and reads the patch's files, never running it (a Clickteam Patch Maker one,
//     Clickteam.swift).  It takes English's place: its text, in the game's own fonts
//     (it writes c, r, s, z, e for the letters with the caron, as the translation
//     says itself: "partial diacritics"), and memory-card texts.  The translation was
//     made on German's text: the texts it left in German and the movies' lines it left
//     empty (German's movies are dubbed) are ours, in its spelling (CzechTexts.swift).
//   - MixerX's Slovak translation (v1.0, 2011; abcgames.cz): Download fetches the zip of
//     its installer for the European game abcgames.cz serves, checks it (size and
//     SHA-256), and reads the installer's files, never running it (an NSIS one,
//     NSIS.swift); Import… also takes the one for the American game, whose language
//     files are the same.  It takes English's place: its text (written in Windows-1250,
//     with every Slovak letter) and the fonts' textures it comes with, which draw those
//     letters, memory-card texts and credits, all as they are.  Not used: its own
//     SPEED2.EXE and a CD image (for the movies' subtitles, which the engine shows
//     itself), and the American one's Corsa and 106, which the game folder has.
import Foundation
import CryptoKit

enum LanguagePacks {
    struct Failure: Error { let message: String }

    // MARK: sources

    struct Archive { let name: String; let size: Int64; let sha256: String }
    static let multi13Page = URL(string: "https://nfsmods.xyz/mod/5749")!
    static let multi13Folder = "https://mega.nz/folder/iooQkaIT#6ORoFSmd3vuyNoPCCY0THw"
    static let core = Archive(name: "nfsug2Multi13Core.rar", size: 11_885_599,
                              sha256: "2d22dd35c420828cb2fcf68a782885d1036c97498cf48be5e7d78501aaff5a21")
    // the dubs: Lang/Movies/<dir> and Lang/Sdata/sdat<dir lower-cased>.viv
    static let dubs: [String: (dir: String, archive: Archive)] = [
        "french": ("Fr", Archive(name: "nfsug2Multi13FrDub.rar", size: 451_317_781, sha256: "6c522442e3a24b569e8a896210159aac49dbd5c7bbab2b9fbb0a92e4737e46a5")),
        "german": ("De", Archive(name: "nfsug2Multi13DeDub.rar", size: 456_060_426, sha256: "622ac55301cd00b8cf9038d305894c4e4fa74c012cf52b4af03c6601f9395083")),
        "italian": ("It", Archive(name: "nfsug2Multi13ItDub.rar", size: 456_815_128, sha256: "47fb68f833f5db4740549184ce1dd0bfecd230b47afe9d8c64e87ae2b1e74507")),
        "spanish": ("Es", Archive(name: "nfsug2Multi13EsDub.rar", size: 456_992_873, sha256: "03af06838532f9ce0958eae5cd7f9cdc62dd547a74149e80a570befb9ae964ac")),
        "japanese": ("Ja", Archive(name: "nfsug2Multi13JaDub.rar", size: 450_622_238, sha256: "23f29c832b466d9464c2fe9173bb75fc559efc7bc9871f1ec8b20f944abfb45c")),
        "russian": ("Ru", Archive(name: "nfsug2Multi13RuDub.rar", size: 481_357_503, sha256: "85ad5889bacc307425c2869f158863a4fd3feaf5783df351c39b50a38b72317b")),
    ]
    static let subtitlesPage = URL(string: "https://nfsmods.xyz/mod/5286")!
    static let subtitlesURL = URL(string: "https://nfsmods.xyz/uploads/mods/5286/5fa362-English%20Subtitles%20Fixed%20(v1.0).7z")!
    static let subtitles = Archive(name: "English Subtitles Fixed (v1.0).7z", size: 7_592,
                                   sha256: "b8a9f123ed9779001770c408687845b58ca9c77adff5a578d397edbe7f77b5aa")
    /// The translations fetched as one installer: the author's page, where it links the
    /// installer (Ukrainian's: the Google Drive file kuli.com.ua's Download leads to), and
    /// the release this was made with; inner: the installer in it when the download is a
    /// zip (Czech's), which Import… also takes as it is; others: the same translation's
    /// other releases Import… takes too, as (zip, installer in it) (Slovak's for the
    /// American game).
    struct Installer {
        let page: URL; let url: URL; let file: Archive; var inner: Archive? = nil
        var others: [(zip: Archive, inner: Archive)] = []
    }
    static let installers: [String: Installer] = [
        "hungarian": Installer(page: URL(string: "http://www.gamehunter.hu/2010/08/need-for-speed-underground-2-pc.html")!,
                               url: URL(string: "https://lukacs.eu/gamehunter/nfs_underground2.exe")!,
                               file: Archive(name: "nfs_underground2.exe", size: 595_280,
                                             sha256: "9447106c71e74b269ab4ef5ceb613cb592d2165cd556886310c622a1a6f3348e")),
        "ukrainian": Installer(page: URL(string: "https://kuli.com.ua/need-for-speed-underground-2")!,
                               url: URL(string: "https://drive.usercontent.google.com/download?id=10t3yk3a1bBQiHrLWF5nywx4PiWp-2-5a&export=download&confirm=t")!,
                               file: Archive(name: "Need for Speed Underground 2 - Ukrainian.exe", size: 4_038_701,
                                             sha256: "c378c2f99f41679e0ab12d28765c4f83d9603f3c613a2b940d0b3b63cbd60b0e")),
        "czech": Installer(page: URL(string: "https://www.abcgames.cz/?p=preklady_zobraz&id=7774")!,
                           url: URL(string: "https://www.abcgames.cz/download/file.ashx?s=7&id=1371")!,
                           file: Archive(name: "nfs-underground-2-cz.zip", size: 376_277,
                                         sha256: "9d4e140c5d7d49bd59d49feecfb97724a15e6f4454c41355d5eb4fbaf2f2ff5c"),
                           inner: Archive(name: "nfsu2cz-v1.1.exe", size: 421_341,
                                          sha256: "8cf760e988e8410549f40e5150dee0cabbd98534ebbc6d1ced971104f811bdd1")),
        "slovak": Installer(page: URL(string: "https://www.abcgames.cz/?p=preklady_zobraz&id=7774")!,
                            url: URL(string: "https://www.abcgames.cz/download/file.ashx?s=7&id=461")!,
                            file: Archive(name: "nfs-underground-2-uk-sk.zip", size: 7_894_784,
                                          sha256: "c4c00562698a834efdfe6a410ff79a11bc3a50d946f2efb679bc2d8032a39590"),
                            inner: Archive(name: "NFSU2UK_SK.exe", size: 7_916_820,
                                           sha256: "9c2db534e8a26bb2b8bdc471d8e936c0ed2581009555779c09b80f879e239870"),
                            others: [(Archive(name: "nfs-underground-2-us-sk.zip", size: 43_738_195,
                                              sha256: "a332b2dcbe65ffbaf0c6303e1a5d8d290f85551dad5c60c2e4369443a875f1a4"),
                                      Archive(name: "NFSU2US_SK.exe", size: 43_782_674,
                                              sha256: "b0119095ba161aaa6392cb1d68ee7863155664f33563d1095fb9e924d94d724c"))]),
    ]
    static let pages: [String: URL] = [
        "portuguese": URL(string: "https://joao13traducoes.com/2018/08/pc-need-for-speed-underground-2-traduzido-e-dublado-varios-autores/")!,
        "polish": URL(string: "https://www.portal24h.pl/spolszczenia-gier/spolszczenia-gier/mo/Need-For-Speed-Underground-2-(plprojekt)-1456/")!,
        "turkish": URL(string: "https://www.moddb.com/mods/need-for-speed-underground-2-turkish-translation-patch")!,
    ]

    // (language, file in the Multi 13 mod, the game's file it stands in for)
    static let multi13Files: [(String, String, String)] = [
        ("chinese", "Languages/Chinese.bin", "LANGUAGES/Chinese.bin"),
        ("chinese", "Lang/Languages/LanguageTexturesGl.bin", "LANGUAGES/LanguageTextures.bin"),
        ("chinese", "Credits/CHINESE.TXT", "CREDITS/CHINESE.TXT"),
        ("chinese", "Memcard/LOCALE_CHINESE.loc", "memcard/LOCALE_CHINESE.loc"),
        ("japanese", "Languages/Japanese.bin", "LANGUAGES/Japanese.bin"),
        ("japanese", "Lang/Languages/LanguageTexturesGl.bin", "LANGUAGES/LanguageTextures.bin"),
        ("japanese", "Lang/Global/GlobalB_ja.lzc", "GLOBAL/GlobalB.lzc"),
        ("japanese", "Credits/JAPANESE.TXT", "CREDITS/JAPANESE.TXT"),
        ("japanese", "Memcard/LOCALE_JAPANESE.loc", "memcard/LOCALE_JAPANESE.loc"),
        ("thai", "Languages/Thailand.bin", "LANGUAGES/Thailand.bin"),
        ("thai", "Lang/Languages/LanguageTexturesGl.bin", "LANGUAGES/LanguageTextures.bin"),
        ("thai", "Credits/THAILAND.TXT", "CREDITS/THAILAND.TXT"),
        ("thai", "Memcard/LOCALE_THAILAND.loc", "memcard/LOCALE_THAILAND.loc"),
        ("russian", "Lang/Languages/English_ru.bin", "LANGUAGES/English.bin"),
        ("russian", "Lang/Languages/LanguageTexturesRu.bin", "LANGUAGES/LanguageTextures.bin"),
        ("russian", "Lang/Global/GLOBALA_ru.BUN", "GLOBAL/GLOBALA.BUN"),
        ("russian", "Lang/Credits/UK_ENGLISH_ru.txt", "CREDITS/NA_ENGLISH.TXT"),
        ("russian", "Lang/Credits/UK_ENGLISH_ru.txt", "CREDITS/UK_ENGLISH.TXT"),
        ("russian", "Lang/Memcard/LOCALE_ENGLISH_Ru.loc", "memcard/LOCALE_ENGLISH.loc"),
        ("danish", "Movies/ealogo_dn.vp6", "MOVIES/ealogo.vp6"),
        ("dutch", "Movies/ealogo_du.vp6", "MOVIES/ealogo.vp6"),
        ("swedish", "Movies/ealogo_sw.vp6", "MOVIES/ealogo.vp6"),
    ]
    // Portuguese and Turkish: (file in the translation, the game's file it stands in for)
    static let ptbrFiles = [("LANGUAGES/English.bin", "LANGUAGES/English.bin"),
                            ("CREDITS/NA_ENGLISH.TXT", "CREDITS/NA_ENGLISH.TXT"),
                            ("CREDITS/NA_ENGLISH.TXT", "CREDITS/UK_ENGLISH.TXT")]
    // Turkish: the translation's fonts only; the text is TurkishTexts', in the game's
    // English.bin and memory-card texts (buildTranslation)
    static let trFiles = [("LANGUAGES/LanguageTextures.bin", "LANGUAGES/LanguageTextures.bin"),
                          ("GLOBAL/GLOBALA.BUN", "GLOBAL/GLOBALA.BUN")]
    // Polish: texts the translation left in English, by their hash, in its letters (as its
    // fonts draw them; no Z with the acute in it), the rest Latin-1
    static let plTexts: [UInt32: String] = [
        0x9148097e: "TUNEL AERODYNAMICZNY",          // STYLE_DRAFTING, the race HUD's "DRAFT"
        0x227eba64: "Drag - Tunel aerodynamiczny",   // ENGAGE_TIPS_DRAFT_SUBJECT, "Drag - Draftowanie"
    ]
    static let plLetters: [Character: UInt8] = ["ę": 0xbf, "ł": 0xee, "ś": 0xe2, "ą": 0xe7, "ć": 0xe9, "ż": 0xe1, "ź": 0xeb,
                                                "ń": 0xf1, "Ę": 0xc7, "Ł": 0xfa, "Ś": 0xda, "Ą": 0xfd, "Ć": 0xc8, "Ż": 0xc9, "Ń": 0xd1]
    static func plBytes(_ s: String) -> [UInt8] {
        s.map { ch in plLetters[ch] ?? UInt8(truncatingIfNeeded: ch.unicodeScalars.first?.value ?? 0x3f) }
    }
    // Thai: its ordinal suffixes (ORDINAL_FIRST ... _NINTH, _ZEROTH) are "number n" in Thai,
    // which the race HUD draws after the position in a font without Thai letters (4th
    // showed as "4 4 /4"): empty, as German's are "."
    static let thaiTexts: [UInt32: [UInt8]] = Dictionary(uniqueKeysWithValues: [
        0x7447c0e3, 0xbc4ce12f, 0x63eb6a03, 0xbd498562, 0x46573b3f, 0xbc4cae38, 0xbd383957, 0xe2ab0284, 0x438da7c0, 0xbcdd9448,
    ].map { (UInt32($0), [UInt8]()) })
    // Polish: (file in the installer, the game's file it stands in for)
    static let plFiles = [("LANGUAGES/Polish.bin", "LANGUAGES/English.bin"),
                          ("LANGUAGES/LanguageTextures.bin", "LANGUAGES/LanguageTextures.bin"),
                          ("GLOBAL/GLOBALA.BUN", "GLOBAL/GLOBALA.BUN"),
                          ("MEMCARD/LOCALE_POLISH.loc", "memcard/LOCALE_ENGLISH.loc"),
                          ("CREDITS/POLISH.TXT", "CREDITS/NA_ENGLISH.TXT"),
                          ("CREDITS/POLISH.TXT", "CREDITS/UK_ENGLISH.TXT")]

    // Hungarian: (file in the installer, the game's file it stands in for)
    static let huFiles = [("LANGUAGES/English.bin", "LANGUAGES/English.bin"),
                          ("memcard/LOCALE_ENGLISH.loc", "memcard/LOCALE_ENGLISH.loc"),
                          ("CREDITS/NA_ENGLISH.TXT", "CREDITS/NA_ENGLISH.TXT"),
                          ("CREDITS/UK_ENGLISH.TXT", "CREDITS/UK_ENGLISH.TXT")]
    // Ukrainian: (data entry of the installer, the game's file it stands in for).  Its
    // [Files] list, in the data entries' order: LANGUAGES\English.bin, Labels.bin,
    // LanguageTextures.bin, Largest.bin, GLOBAL\GLOBALA.BUN, memcard\LOCALE_ENGLISH.loc,
    // GLOBAL\GlobalB.lzc, CREDITS\NA_ENGLISH.txt, UK_ENGLISH.txt.  Not used: Labels.bin
    // and Largest.bin, which the game never reads, and a GlobalB.lzc that differs from
    // the game's in one byte (the trademark sign of a shave gel's name).
    static let ukFiles = [(0, "LANGUAGES/English.bin"), (2, "LANGUAGES/LanguageTextures.bin"),
                          (4, "GLOBAL/GLOBALA.BUN"), (5, "memcard/LOCALE_ENGLISH.loc"),
                          (7, "CREDITS/NA_ENGLISH.TXT"), (8, "CREDITS/UK_ENGLISH.TXT")]
    static let ukEntries = 9
    // Czech: (file in the patch, the game's file it stands in for).  Not used: its German.bin
    // and LOCALE_GERMAN.loc, the same translation for the German game.
    static let czFiles = [("LANGUAGES\\English.bin", "LANGUAGES/English.bin"),
                          ("memcard\\LOCALE_ENGLISH.loc", "memcard/LOCALE_ENGLISH.loc")]
    // Slovak: (data entry of the installer, its SHA-256, the game's file it stands in for).
    // Its files in the data entries' order: the installer's pictures and plugins (0-6),
    // NFSU2UK-SK.rtf, slovencina.reg, CREDITS/SWEDISH.TXT, Global/GLOBALA.BUN,
    // memcard/LOCALE_SWEDISH.loc, Languages/Swedish.bin, Languages/LanguageTextures.bin,
    // Speed2.exe, ... (the same in the American game's installer, which has the cars after).
    static let skFiles = [
        (12, "b57d95e18f2d9119a7a525d1145292fd08cbfb182e14a5d3bde79f2e00a42f16", "LANGUAGES/English.bin"),
        (13, "e2955afca09ab6128eabed6b35ae99f8f43c198f83f5e64803555d8af9d10531", "LANGUAGES/LanguageTextures.bin"),
        (10, "6cb8547b480ba44bc5015b639223a8a8dd19e65e607e56e93093fe7027d7e5d1", "GLOBAL/GLOBALA.BUN"),
        (11, "c53c78601e7ba05dedcbf652c71135199a78333a6c7be3873726c39e02536068", "memcard/LOCALE_ENGLISH.loc"),
        (9, "cb49b54123ed28eb79a5bafd4ed5a5fb6f1dab9bb5ebd3f108b85b623104f2a0", "CREDITS/NA_ENGLISH.TXT"),
        (9, "cb49b54123ed28eb79a5bafd4ed5a5fb6f1dab9bb5ebd3f108b85b623104f2a0", "CREDITS/UK_ENGLISH.TXT"),
    ]

    /// How a language's pack is made.
    enum Way { case download, importOnly }
    static func way(_ lang: String) -> Way? {
        if lang == "english" || dubs[lang] != nil || multi13Files.contains(where: { $0.0 == lang }) { return .download }
        if installers[lang] != nil { return .download }
        if pages[lang] != nil { return .importOnly }
        return nil
    }
    /// The Multi 13 archives a language needs.
    static func archives(_ lang: String) -> [Archive] {
        var a: [Archive] = []
        if multi13Files.contains(where: { $0.0 == lang }) { a.append(core) }
        if let d = dubs[lang] { a.append(d.archive) }
        return a
    }
    static func downloadSize(_ lang: String) -> Int64 {
        lang == "english" ? subtitles.size : installers[lang]?.file.size ?? archives(lang).reduce(0) { $0 + $1.size }
    }

    // MARK: the pack

    static func find(_ root: URL, _ rel: String) -> URL? { UHUDPack.find(root, rel) }

    /// A path inside a pack or a temporary folder, from a name an archive gives:
    /// "\\" taken as "/", then refused with an empty, "." or ".." part or a leading "/".
    static func safeRel(_ name: String) throws -> String {
        let rel = name.replacingOccurrences(of: "\\", with: "/")
        let parts = rel.split(separator: "/", omittingEmptySubsequences: false)
        guard !rel.isEmpty, !rel.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw Failure(message: "a file name that points outside its folder (\(name))")
        }
        return rel
    }
    /// root/rel, refused unless it stays inside root (symbolic links followed).
    static func inside(_ root: URL, _ rel: String) throws -> URL {
        let dst = root.appendingPathComponent(try safeRel(rel))
        func real(_ u: URL) -> String? {
            guard let c = realpath(u.path, nil) else { return nil }
            defer { free(c) }
            return String(cString: c)
        }
        // (standardizedFileURL would drop "/private" from paths that exist only)
        let d = dst.path, rs = root.path
        guard let r = real(root) else { throw Failure(message: "the pack's folder is not there") }
        // the deepest folder of dst that exists, links followed (realpath), must be root or below it
        var probe = dst.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: probe.path) && probe.path.count > rs.count { probe.deleteLastPathComponent() }
        let p = real(probe) ?? ""
        guard (p == r || p.hasPrefix(r + "/")), d.hasPrefix(rs + "/") else {
            throw Failure(message: "a file name that points outside its folder (\(rel))")
        }
        if let a = try? FileManager.default.destinationOfSymbolicLink(atPath: d), !a.isEmpty {
            throw Failure(message: "\(rel) is a link in the pack's folder")
        }
        return dst
    }

    /// rel spelled as the game folder spells it, as far as it has it
    static func gameName(_ game: URL, _ rel: String) -> String {
        var out: [String] = [], cur = game
        for part in rel.split(separator: "/").map(String.init) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: cur.path)) ?? []
            let hit = names.first { $0.lowercased() == part.lowercased() } ?? part
            out.append(hit); cur = cur.appendingPathComponent(hit)
        }
        return out.joined(separator: "/")
    }

    final class Pack {
        let game: URL, root: URL, lang: String
        private(set) var files = 0, bytes: Int64 = 0
        private var made = Set<String>()
        /// packs: the folder that holds the packs (nil: the game folder's LANGPACKS)
        init(game: URL, lang: String, packs: URL? = nil) {
            self.game = game; self.lang = lang
            root = (packs ?? game.appendingPathComponent("LANGPACKS")).appendingPathComponent(lang)
        }
        func sameAsGame(_ rel: String, _ data: Data) -> Bool {
            guard let g = find(game, rel), let a = try? FileManager.default.attributesOfItem(atPath: g.path),
                  (a[.size] as? NSNumber)?.intValue == data.count else { return false }
            return (try? Data(contentsOf: g, options: .alwaysMapped)) == data
        }
        func add(_ data: Data, _ name: String) throws {
            let rel = try safeRel(name)
            if sameAsGame(rel, data) { return }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let dst = try inside(root, gameName(game, rel))
            if (try? Data(contentsOf: dst, options: .alwaysMapped)) != data {
                try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: dst)
            }
            files += 1; bytes += Int64(data.count); made.insert(dst.standardizedFileURL.path)
        }
        func add(file src: URL, _ rel: String) throws { try add(try Data(contentsOf: src, options: .alwaysMapped), rel) }
        /// what an earlier build put here and this one did not
        func finish() {
            let fm = FileManager.default
            if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let u as URL in e where !UHUDPack.isDirectory(u) && !made.contains(u.standardizedFileURL.path) {
                    try? fm.removeItem(at: u)
                }
            }
            func prune(_ d: URL) {
                for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where UHUDPack.isDirectory(u) { prune(u) }
                if ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).isEmpty { try? fm.removeItem(at: d) }
            }
            if UHUDPack.isDirectory(root) { prune(root) }
        }
        var summary: String { files == 0 ? "\(lang): nothing needed" : String(format: "%@: %d files, %.1f MB", lang, files, Double(bytes) / 1_048_576) }
    }

    // MARK: Multi 13

    /// EA's .viv (BIG4/BIGF): (name, offset, size) of its files
    static func vivEntries(_ d: Data) throws -> [(String, Int, Int)] {
        let b = [UInt8](d)
        guard b.count >= 16, b[0] == 0x42, b[1] == 0x49, b[2] == 0x47 else { throw Failure(message: "not a .viv archive") }
        func be(_ o: Int) throws -> Int {
            guard o >= 0, o + 4 <= b.count else { throw Failure(message: "damaged .viv archive") }
            let b0 = Int(b[o]) << 24, b1 = Int(b[o + 1]) << 16, b2 = Int(b[o + 2]) << 8
            return b0 | b1 | b2 | Int(b[o + 3])
        }
        let n = try be(8), hdr = try be(12)
        guard hdr >= 16, hdr <= b.count, n >= 0, n <= hdr / 9 else { throw Failure(message: "damaged .viv archive") }
        var out: [(String, Int, Int)] = [], q = 16
        for _ in 0..<n {
            guard q + 8 <= hdr else { throw Failure(message: "damaged .viv archive") }
            let off = try be(q), size = try be(q + 4); q += 8
            var e = q
            while e < hdr && b[e] != 0 { e += 1 }
            guard e < hdr, off >= 0, size >= 0, off <= b.count, size <= b.count - off else { throw Failure(message: "damaged .viv archive") }
            out.append((String(decoding: b[q..<e], as: UTF8.self), off, size))
            q = e + 1
        }
        return out
    }

    /// The Multi 13 archives unpacked: path (lower-cased) -> its bytes, for the paths `want` takes.
    static func unpack(_ rar: URL, want: (String) -> Bool) throws -> [String: Data] {
        final class Box { var data = Data() }
        let data = try Data(contentsOf: rar, options: .alwaysMapped)
        var boxes: [String: Box] = [:]
        try data.withUnsafeBytes { b in
            let entries = try RarArchive.list(b)
            try RarArchive.extract(b, entries: entries) { e in
                let key = e.name.lowercased()
                guard want(key) else { return nil }
                let box = Box()
                box.data.reserveCapacity(Int(e.size))
                boxes[key] = box
                return { chunk in box.data.append(chunk.bindMemory(to: UInt8.self)) }
            }
        }
        return boxes.mapValues { $0.data }
    }

    /// A Multi 13 language's pack from its archives (core: may be nil when not needed).
    static func buildMulti13(lang: String, game: URL, core: URL?, dub: URL?, packs: URL? = nil) throws -> String {
        let p = Pack(game: game, lang: lang, packs: packs)
        let mine = multi13Files.filter { $0.0 == lang }
        if !mine.isEmpty {
            guard let c = core else { throw Failure(message: "the mod's core archive is missing") }
            let srcs = Set(mine.map { $0.1.lowercased() })
            let files = try unpack(c) { srcs.contains($0) }
            for (_, src, rel) in mine {
                guard let d = files[src.lowercased()] else { throw Failure(message: "\(c.lastPathComponent) has no \(src): not the Multi 13 languages mod") }
                try p.add(lang == "thai" && rel == "LANGUAGES/Thailand.bin" ? try withTexts(d, bytes: thaiTexts).0 : d, rel)
            }
        }
        if let (dir, _) = dubs[lang] {
            guard let dubURL = dub else { throw Failure(message: "the \(lang) dub archive is missing") }
            let viv = "lang/sdata/sdat\(dir.lowercased()).viv", movies = "lang/movies/\(dir.lowercased())/"
            let files = try unpack(dubURL) { $0 == viv || $0.hasPrefix(movies) }
            guard let v = files[viv] else { throw Failure(message: "\(dubURL.lastPathComponent) has no \(viv): not the mod's \(lang) dub") }
            for (name, off, size) in try vivEntries(v) where name.lowercased().hasPrefix("speech/ug2_speech") {
                guard off >= 0, size >= 0, off <= v.count, size <= v.count - off else { throw Failure(message: "damaged \(viv)") }
                try p.add(v.subdata(in: (v.startIndex + off)..<(v.startIndex + off + size)), name)
            }
            let movieFiles = files.keys.filter { $0.hasPrefix(movies) && $0.count > movies.count }.sorted()
            guard !movieFiles.isEmpty else { throw Failure(message: "\(dubURL.lastPathComponent) has no movies") }
            // the archive's own spelling of the movie's name
            let names = try Data(contentsOf: dubURL, options: .alwaysMapped).withUnsafeBytes { try RarArchive.list($0) }
            for k in movieFiles {
                let name = names.first { $0.name.lowercased() == k }.map { ($0.name as NSString).lastPathComponent } ?? (k as NSString).lastPathComponent
                try p.add(files[k]!, "MOVIES/" + name)
            }
        }
        p.finish()
        return p.summary
    }

    // MARK: English subtitles

    /// {hash: text} of a Binary endscript's update_string lines for LANGUAGES\ENGLISH.BIN
    static func endTexts(_ text: String) throws -> [UInt32: String] {
        var out: [UInt32: String] = [:]
        let re = try NSRegularExpression(pattern: #"^update_string\s+(\S+)\s+STRBlocks\s+\S+\s+(\S+)\s+(Text|Label|Key)\s+(.*?)\s*$"#)
        for (n, line) in text.components(separatedBy: .newlines).enumerated() {
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  ns.substring(with: m.range(at: 1)).uppercased() == "LANGUAGES\\ENGLISH.BIN" else { continue }
            func num(_ s: String) -> UInt32? { s.hasPrefix("0x") || s.hasPrefix("0X") ? UInt32(s.dropFirst(2), radix: 16) : UInt32(s) }
            guard let h = num(ns.substring(with: m.range(at: 2))) else { throw Failure(message: "line \(n + 1): a hash it does not read") }
            let kind = ns.substring(with: m.range(at: 3)), v = ns.substring(with: m.range(at: 4))
            if kind == "Key" && num(v) != h { throw Failure(message: "line \(n + 1) moves a text to another hash") }
            guard kind == "Text" else { continue }
            guard v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\"") else { throw Failure(message: "line \(n + 1): a text not in quotes") }
            let t = String(v.dropFirst().dropLast())
            guard t.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7e }) else {
                throw Failure(message: "line \(n + 1): letters beyond ASCII, which the game spells its own way")
            }
            out[h] = t
        }
        return out
    }

    /// A language file with these texts: its text chunk (id 0x39000: { 16, count, table,
    /// strings } and a character table, the table of (hash, offset) in hash order, the
    /// strings) rebuilt with the changed texts after the others; the chunks after it (the
    /// fonts) go 0x80-aligned behind a pad chunk (id 0), as in the game's own file (the
    /// Polish translation's has them unaligned; the game reads either).
    static func withTexts(_ file: Data, _ texts: [UInt32: String]) throws -> (Data, Int) {
        try withTexts(file, bytes: texts.mapValues { Array($0.utf8) })
    }
    /// The same with the texts as the file's bytes (a translation's letters).  whole: the
    /// strings written anew, each once, so that a translation of every text leaves no
    /// English behind (the file stays the size of a language's).
    static func withTexts(_ file: Data, bytes texts: [UInt32: [UInt8]], whole: Bool = false) throws -> (Data, Int) {
        let d = [UInt8](file)
        func u32(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
        func put(_ v: Int, _ a: inout [UInt8]) { for i in 0..<4 { a.append(UInt8(truncatingIfNeeded: v >> (8 * i))) } }
        var q = 0
        while q + 8 <= d.count && u32(q) != 0x39000 { q += 8 + u32(q + 4) }
        guard q + 8 <= d.count else { throw Failure(message: "English.bin has no text") }
        let size = u32(q + 4), c = Array(d[(q + 8)..<(q + 8 + size)])
        func cu(_ o: Int) -> Int { Int(c[o]) | Int(c[o + 1]) << 8 | Int(c[o + 2]) << 16 | Int(c[o + 3]) << 24 }
        let head = cu(0), n = cu(4), tab = cu(8), sd = cu(12)
        guard head == 16, tab + 8 * n == sd, sd <= size else { throw Failure(message: "English.bin's text is of another layout") }
        var at: [UInt32: Int] = [:]
        for i in 0..<n { at[UInt32(cu(tab + 8 * i))] = cu(tab + 8 * i + 4) }
        func old(_ h: UInt32) -> [UInt8]? {
            guard let o = at[h] else { return nil }
            var e = sd + o
            while e < c.count && c[e] != 0 { e += 1 }
            return Array(c[(sd + o)..<e])
        }
        var strs: [UInt8] = [], changed = 0
        if whole {
            var new: [UInt32: [UInt8]] = [:], offs: [[UInt8]: Int] = [:]
            for h in at.keys { new[h] = old(h) ?? [] }
            for (h, b) in texts { if old(h) != b { changed += 1 }; new[h] = b }
            for h in new.keys.sorted() {
                let b = new[h]!
                if offs[b] == nil { offs[b] = strs.count; strs += b + [0] }
                at[h] = offs[b]!
            }
        } else {
            strs = Array(c[sd...])
            for (h, b) in texts.sorted(by: { $0.key < $1.key }) {
                if old(h) == b { continue }
                at[h] = strs.count; strs += b + [0]; changed += 1
            }
        }
        strs += [UInt8](repeating: 0, count: (4 - strs.count % 4) % 4)
        var body: [UInt8] = []
        put(16, &body); put(at.count, &body); put(tab, &body); put(tab + 8 * at.count, &body)
        body += c[16..<tab]
        for h in at.keys.sorted() { put(Int(h), &body); put(at[h]!, &body) }
        body += strs
        var r = q + 8 + size
        while r + 8 <= d.count && u32(r) == 0 { r += 8 + u32(r + 4) }
        var out = Array(d[0..<q])
        put(0x39000, &out); put(body.count, &out); out += body
        if r < d.count {
            let pad = (0x80 - (out.count + 8) % 0x80) % 0x80
            put(0, &out); put(pad, &out); out += [UInt8](repeating: 0, count: pad)
        }
        out += d[r...]
        return (Data(out), changed)
    }

    /// A memory-card text file (memcard/LOCALE_*.loc) with these texts (bytes, in the
    /// language file's letters).  Its chunks LOCH and LOCI, then LOCL, the last: tag, size
    /// (its 8 bytes in it), 0, the count, each text's offset from the chunk's start, the
    /// texts in UTF-16 each followed by four 0 bytes, then padding to 4.
    static func withLoc(_ file: Data, _ texts: [[UInt8]]) throws -> Data {
        let d = [UInt8](file)
        func u32(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
        func put(_ v: Int, _ a: inout [UInt8]) { for i in 0..<4 { a.append(UInt8(truncatingIfNeeded: v >> (8 * i))) } }
        var q = -1
        if d.count >= 16 { for i in 0...(d.count - 16) where d[i] == 0x4c && d[i + 1] == 0x4f && d[i + 2] == 0x43 && d[i + 3] == 0x4c { q = i; break } }
        guard q >= 0, q + u32(q + 4) == d.count else { throw Failure(message: "LOCALE_ENGLISH.loc is of another layout") }
        let n = u32(q + 12)
        guard texts.count == n else { throw Failure(message: "\(texts.count) memory-card texts, the game has \(n)") }
        var body: [UInt8] = [], offs: [Int] = []
        for t in texts {
            offs.append(16 + 4 * n + body.count)
            for b in t { body += [b, 0] }                  // Latin-1 as UTF-16
            body += [0, 0, 0, 0]
        }
        body += [UInt8](repeating: 0, count: (4 - body.count % 4) % 4)
        var out = Array(d[0..<q]) + Array("LOCL".utf8)
        put(16 + 4 * n + body.count, &out); put(0, &out); put(n, &out)
        for o in offs { put(o, &out) }
        return Data(out + body)
    }

    /// English's pack from the subtitles mod (its .7z or the folder it was extracted to).
    static func buildSubtitles(mod: URL, game: URL, packs: URL? = nil) throws -> String {
        let (root, temp) = try unpackedFolder(mod)
        defer { if let t = temp { try? FileManager.default.removeItem(at: t) } }
        var texts: [UInt32: String] = [:]
        let ends = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "end" }.sorted { $0.path < $1.path }
        for e in ends { try endTexts(try String(contentsOf: e, encoding: .utf8)).forEach { texts[$0.key] = $0.value } }
        guard !texts.isEmpty else { throw Failure(message: "\(mod.lastPathComponent) has no endscript that changes English's text: not the English Subtitles Fixed mod") }
        guard let eng = find(game, "LANGUAGES/English.bin") else { throw Failure(message: "The game folder has no LANGUAGES/English.bin.") }
        let (data, _) = try withTexts(try Data(contentsOf: eng), texts)
        let p = Pack(game: game, lang: "english", packs: packs)
        try p.add(data, "LANGUAGES/English.bin")
        p.finish()
        return p.summary
    }

    // MARK: imports

    /// An archive (bsdtar: zip, 7z, RAR 4; RarArchive: RAR 5 and 7) or a folder: the
    /// folder to read, and the temporary folder to remove afterwards.
    static func unpackedFolder(_ src: URL) throws -> (URL, URL?) {
        if UHUDPack.isDirectory(src) { return (src, nil) }
        let fm = FileManager.default
        let t = fm.temporaryDirectory.appendingPathComponent("nfsu2-langpack-\(UUID().uuidString)")
        try fm.createDirectory(at: t, withIntermediateDirectories: true)
        let head = (try? FileHandle(forReadingFrom: src))?.readData(ofLength: 8) ?? Data()
        if head == Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]) {
            let data = try Data(contentsOf: src, options: .alwaysMapped)
            do {
                try data.withUnsafeBytes { b in
                    let entries = try RarArchive.list(b)
                    try RarArchive.extract(b, entries: entries) { e in
                        let f = try inside(t, e.name)
                        try fm.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                        fm.createFile(atPath: f.path, contents: nil)
                        let h = try FileHandle(forWritingTo: f)
                        return { h.write(Data($0)) }
                    }
                }
            } catch let e as RarArchive.Failure {
                try? fm.removeItem(at: t)
                throw Failure(message: "\(src.lastPathComponent) could not be unpacked (\(e.message)). Unpack it yourself and choose the folder.")
            } catch {
                try? fm.removeItem(at: t)
                throw error
            }
            return (t, t)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xf", src.path, "-C", t.path]      // bsdtar refuses ".." and absolute paths
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !UHUDPack.hasLink(t) else {
            try? fm.removeItem(at: t)
            throw Failure(message: "\(src.lastPathComponent) could not be unpacked. Unpack it yourself and choose the folder.")
        }
        return (t, t)
    }

    /// the folder at or below dir with LANGUAGES/English.bin
    static func translationRoot(_ dir: URL, has rel: String = "LANGUAGES/English.bin") -> URL? {
        if find(dir, rel) != nil { return dir }
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let u = e?.nextObject() as? URL {
            if UHUDPack.isDirectory(u), find(u, rel) != nil { return u }
        }
        return nil
    }

    static func buildTranslation(lang: String, src: URL, game: URL, packs: URL? = nil) throws -> String {
        let (dir, temp) = try unpackedFolder(src)
        defer { if let t = temp { try? FileManager.default.removeItem(at: t) } }
        let p = Pack(game: game, lang: lang, packs: packs)
        if lang == "polish" {
            let files = try polishFiles(dir)
            for (s, rel) in plFiles {
                guard let d = files[s.lowercased()] else { throw Failure(message: "The Polish translation's installer has no \(s).") }
                try p.add(rel == "LANGUAGES/English.bin" ? try withTexts(d, bytes: plTexts.mapValues(plBytes)).0 : d, rel)
            }
        } else if lang == "turkish" {
            guard let root = translationRoot(dir, has: "LANGUAGES/LanguageTextures.bin") else {
                throw Failure(message: "\(src.lastPathComponent) has no LANGUAGES/LanguageTextures.bin. The Turkish translation comes as a Windows installer (nfsu2tr11.exe): unpack it with innoextract and choose the folder it made.")
            }
            for (s, _) in trFiles where find(root, s) == nil { throw Failure(message: "The translation is not all there: it has no \(s).") }
            let tex = try Data(contentsOf: find(root, "LANGUAGES/LanguageTextures.bin")!)
            if p.sameAsGame("LANGUAGES/LanguageTextures.bin", tex) { throw Failure(message: "Its LANGUAGES/LanguageTextures.bin is the game's own, not the translation.") }
            guard let eng = find(game, "LANGUAGES/English.bin"), let loc = find(game, "memcard/LOCALE_ENGLISH.loc") else {
                throw Failure(message: "The game folder has no LANGUAGES/English.bin or memcard/LOCALE_ENGLISH.loc.")
            }
            try p.add(try withTexts(try Data(contentsOf: eng), bytes: try TurkishTexts.bytes(), whole: true).0, "LANGUAGES/English.bin")
            try p.add(try withLoc(try Data(contentsOf: loc), try TurkishTexts.memcard()), "memcard/LOCALE_ENGLISH.loc")
            for (s, rel) in trFiles { try p.add(file: find(root, s)!, rel) }
        } else {
            guard let root = translationRoot(dir) else {
                throw Failure(message: "\(src.lastPathComponent) has no LANGUAGES/English.bin: not the translation. Unpack its archive (password on its page) and choose the folder.")
            }
            let list = ptbrFiles
            for (s, _) in list where find(root, s) == nil { throw Failure(message: "The translation is not all there: it has no \(s).") }
            let eng = try Data(contentsOf: find(root, "LANGUAGES/English.bin")!)
            if p.sameAsGame("LANGUAGES/English.bin", eng) { throw Failure(message: "Its LANGUAGES/English.bin is the game's own, not the translation.") }
            for (s, rel) in list { try p.add(file: find(root, s)!, rel) }
            if lang == "portuguese", let loc = find(game, "memcard/LOCALE_BRAZILIAN_PORTUGUESE.loc") {
                try p.add(file: loc, "memcard/LOCALE_ENGLISH.loc")      // the game's own Brazilian memory-card texts
            }
        }
        p.finish()
        return p.summary
    }

    // MARK: the Polish and Hungarian installers

    /// {path in the game folder, lower-cased: data} of an Astrum InstallWizard 2
    /// installer (NFSU2PLv1.1US.exe / UK.exe, the Hungarian nfs_underground2.exe), read,
    /// never run.  It ends with the package's header offset, a block of n bytes, n
    /// (0xffffffff for none, in the older Hungarian one) and a magic; the header
    /// (big-endian words) says where the files start, and they end where it begins.
    /// Each file: a 0x40-byte record whose word 0x2c is its name's length, the name
    /// ("<InstallDir>\...", each byte's bit i stored as bit i^6), the offset its data
    /// ends at, the data: a gzip stream or the file as it is.
    static func astrumFiles(_ file: Data) throws -> [String: Data] {
        let d = [UInt8](file)
        func le(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
        func be(_ o: Int) -> Int { Int(d[o]) << 24 | Int(d[o + 1]) << 16 | Int(d[o + 2]) << 8 | Int(d[o + 3]) }
        guard d.count > 300, le(d.count - 8) == 0x0b1c2d3e, le(d.count - 4) == 0x1234_5678 else {
            throw Failure(message: "not an Astrum InstallWizard installer")
        }
        var n = le(d.count - 12)
        if n == 0xffff_ffff { n = 0 }
        guard n < d.count, d.count - 16 - n > 0 else { throw Failure(message: "a damaged installer") }
        let head = le(d.count - 16 - n)
        guard head > 0, head + 236 <= d.count else { throw Failure(message: "a damaged installer") }
        var pos = be(head + 48 * 4)
        guard pos + be(head + 49 * 4) == head else { throw Failure(message: "an Astrum package of another layout") }
        var out: [String: Data] = [:]
        while pos < head {
            let size = le(pos + 0x2c)
            guard pos + 0x44 + size <= head else { throw Failure(message: "a damaged installer") }
            let name = (0..<size).map { k -> UInt8 in
                let b = d[pos + 0x40 + k]
                var v: UInt8 = 0
                for i in 0..<8 where b >> i & 1 != 0 { v |= 1 << (i ^ 6) }
                return v
            }
            let end = le(pos + 0x40 + size)
            guard end > pos, end <= head else { throw Failure(message: "a damaged installer") }
            let full = String(decoding: name, as: UTF8.self)
            let rel = full.split(separator: "\\", maxSplits: 1).dropFirst().first.map { $0.replacingOccurrences(of: "\\", with: "/") } ?? full
            let data = Data(d[(pos + 0x44 + size)..<end])
            out[rel.lowercased()] = try gunzipIfNeeded(data)
            pos = end
        }
        return out
    }

    /// a gzip stream's content (its raw DEFLATE data), or the bytes as they are
    static func gunzipIfNeeded(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return data }
        let flags = b[3]
        var p = 10
        if flags & 4 != 0 { p += 2 + (Int(b[p]) | Int(b[p + 1]) << 8) }
        if flags & 8 != 0 { while p < b.count && b[p] != 0 { p += 1 }; p += 1 }
        if flags & 16 != 0 { while p < b.count && b[p] != 0 { p += 1 }; p += 1 }
        if flags & 2 != 0 { p += 2 }
        guard p < b.count - 8 else { throw Failure(message: "a damaged gzip stream") }
        let isize = Int(b[b.count - 4]) | Int(b[b.count - 3]) << 8 | Int(b[b.count - 2]) << 16 | Int(b[b.count - 1]) << 24
        // NSData's zlib algorithm is raw DEFLATE (RFC 1951)
        guard let out = try? (Data(b[p..<(b.count - 8)]) as NSData).decompressed(using: .zlib) as Data,
              out.count == isize else { throw Failure(message: "a damaged gzip stream") }
        return out
    }

    /// The Polish installer in dir (or dir is the installer): its files.
    static func polishFiles(_ dir: URL) throws -> [String: Data] {
        var exe: URL? = nil
        if !UHUDPack.isDirectory(dir) { exe = dir }
        else {
            let all = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
            exe = all.filter { $0.lastPathComponent.lowercased().hasPrefix("nfsu2pl") && $0.pathExtension.lowercased() == "exe" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }.first
        }
        guard let e = exe else { throw Failure(message: "No NFSU2PLv1.1US.exe or NFSU2PLv1.1UK.exe in it: not the Polish translation.") }
        return try astrumFiles(try Data(contentsOf: e))
    }

    // MARK: Hungarian and Ukrainian

    /// Hungarian's pack from its installer (as downloaded, checked by the caller).
    static func buildHungarian(installer: URL, game: URL, packs: URL? = nil) throws -> String {
        let files = try astrumFiles(try Data(contentsOf: installer))
        let p = Pack(game: game, lang: "hungarian", packs: packs)
        for (s, rel) in huFiles {
            guard let d = files[s.lowercased()] else { throw Failure(message: "The Hungarian translation's installer has no \(s).") }
            try p.add(d, rel)
        }
        p.finish()
        return p.summary
    }

    /// Ukrainian's pack from its installer (as downloaded, checked by the caller).
    static func buildUkrainian(installer: URL, game: URL, packs: URL? = nil) throws -> String {
        let d = [UInt8](try Data(contentsOf: installer))
        let setup = try InnoSetup.read(d)
        guard setup.entries.count == ukEntries else { throw Failure(message: "The Ukrainian translation's installer has other files than the release this was made for.") }
        let p = Pack(game: game, lang: "ukrainian", packs: packs)
        for (i, rel) in ukFiles {
            let data = try InnoSetup.file(d, setup.entries[i])
            if rel == "LANGUAGES/English.bin", p.sameAsGame(rel, data) { throw Failure(message: "Its LANGUAGES/English.bin is the game's own, not the translation.") }
            try p.add(data, rel)
        }
        p.finish()
        return p.summary
    }

    /// Czech's pack from its patch (as downloaded, checked by the caller): the patch's
    /// English.bin with our texts (CzechTexts.swift) and its memory-card texts.
    static func buildCzech(installer: URL, game: URL, packs: URL? = nil) throws -> String {
        let d = [UInt8](try Data(contentsOf: installer))
        let patch = try Clickteam.read(d)
        let p = Pack(game: game, lang: "czech", packs: packs)
        for (s, rel) in czFiles {
            guard let e = patch.entries.first(where: { $0.path.lowercased() == s.lowercased() }) else {
                throw Failure(message: "The Czech translation's patch has no \(s).")
            }
            var data = try Clickteam.file(d, patch, e)
            if rel == "LANGUAGES/English.bin" {
                if p.sameAsGame(rel, data) { throw Failure(message: "Its LANGUAGES/English.bin is the game's own, not the translation.") }
                data = try withTexts(data, bytes: try CzechTexts.bytes()).0
            }
            try p.add(data, rel)
        }
        p.finish()
        return p.summary
    }

    /// Slovak's pack from its installer (either one, as downloaded, checked by the caller):
    /// its files by their index, each checked against the release this was made with.
    static func buildSlovak(installer: URL, game: URL, packs: URL? = nil) throws -> String {
        let d = [UInt8](try Data(contentsOf: installer))
        let entries = try NSIS.entries(d)
        let p = Pack(game: game, lang: "slovak", packs: packs)
        var got: [Int: [UInt8]] = [:]
        for (i, sha, rel) in skFiles {
            guard i < entries.count else { throw Failure(message: "The Slovak translation's installer has other files than the release this was made for.") }
            let data = try got[i] ?? NSIS.file(d, entries[i])
            got[i] = data
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha else {
                throw Failure(message: "The Slovak translation's installer has other files than the release this was made for (\(rel)).")
            }
            try p.add(Data(data), rel)
        }
        p.finish()
        return p.summary
    }

    /// The pinned installer at src (the file, or a folder with it; for Czech also the
    /// zip it comes in, unpacked to a temporary folder, the second URL, for the caller to
    /// remove), refused unless it is the release this was made with.
    static func pinnedInstaller(_ lang: String, _ src: URL) throws -> (URL, URL?) {
        guard let i = installers[lang] else { throw Failure(message: "\(lang) has no installer") }
        let a = i.inner ?? i.file
        // (zip, installer) of every release taken; a plain installer has no zip
        let forms: [(zip: Archive?, exe: Archive)] = [(i.inner == nil ? nil : i.file, a)] + i.others.map { ($0.zip, $0.inner) }
        func size(_ u: URL) -> Int64 { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.int64Value ?? -1 }
        func pinned(_ u: URL, _ x: Archive) -> Bool { size(u) == x.size && (try? sha256(u)) == x.sha256 }
        func search(_ dir: URL, _ x: Archive) -> URL? {
            let all = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
            return all.filter { !UHUDPack.isDirectory($0) && size($0) == x.size }
                .sorted { ($0.lastPathComponent == x.name ? 0 : 1, $0.path) < ($1.lastPathComponent == x.name ? 0 : 1, $1.path) }
                .first { pinned($0, x) }
        }
        var found: URL? = nil, zip: (URL, Archive)? = nil
        for f in forms where found == nil && zip == nil {
            if UHUDPack.isDirectory(src) {
                found = search(src, f.exe)
                if found == nil, let z = f.zip, let u = search(src, z) { zip = (u, f.exe) }
            } else if pinned(src, f.exe) {
                found = src
            } else if let z = f.zip, pinned(src, z) {
                zip = (src, f.exe)
            }
        }
        if found == nil, let (z, exe) = zip {
            let (dir, temp) = try unpackedFolder(z)
            if let f = search(dir, exe) { return (f, temp) }
            if let t = temp { try? FileManager.default.removeItem(at: t) }
        }
        guard let f = found else {
            throw Failure(message: "\(src.lastPathComponent) is not the release this was made for (\(i.inner == nil ? a.name : "\(i.file.name) or the \(a.name) in it"), \(formatBytesPlain(a.size))). Choose it as downloaded from its page, or the folder it is in.")
        }
        return (f, nil)
    }

    static func buildInstaller(lang: String, installer: URL, game: URL, packs: URL?) throws -> String {
        switch lang {
        case "hungarian": return try buildHungarian(installer: installer, game: game, packs: packs)
        case "czech": return try buildCzech(installer: installer, game: game, packs: packs)
        case "slovak": return try buildSlovak(installer: installer, game: game, packs: packs)
        default: return try buildUkrainian(installer: installer, game: game, packs: packs)
        }
    }

    static func formatBytesPlain(_ n: Int64) -> String { String(format: "%.1f MB", Double(n) / 1_048_576) }

    // MARK: download

    static func sha256(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { h.closeFile() }
        var s = SHA256()
        while true {
            let d = h.readData(ofLength: 8 << 20)
            if d.isEmpty { break }
            s.update(data: d)
        }
        return s.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads what a language needs from its author's page and builds its pack.
    /// progress: (what, bytes so far of all, total bytes).
    static func download(lang: String, game: URL, packs: URL? = nil, progress: @escaping (String, Int64, Int64) -> Void) throws -> String {
        let fm = FileManager.default
        let total = downloadSize(lang)
        if lang == "english" {
            let f = try UHUDPack.Downloader(progress: { progress("Downloading", $0, total) }).fetch(subtitlesURL)
            defer { try? fm.removeItem(at: f) }
            guard try sha256(f) == subtitles.sha256 else {
                throw Failure(message: "The file on nfsmods.xyz is not the release this was made for. Download the mod from its page yourself and use Import….")
            }
            progress("Building", total, total)
            return try buildSubtitles(mod: f, game: game, packs: packs)
        }
        if let i = installers[lang] {
            let host = i.page.host ?? "its page"
            let f = try UHUDPack.Downloader(progress: { progress("Downloading", $0, total) }, host: i.url.host ?? host, hint: "use Import…").fetch(i.url)
            defer { try? fm.removeItem(at: f) }
            guard let (got, temp) = try? pinnedInstaller(lang, f) else {
                throw Failure(message: "The file \(host) links is not the release this was made for (\(i.file.name)). Download it from its page yourself and use Import….")
            }
            defer { if let t = temp { try? fm.removeItem(at: t) } }
            progress("Building", total, total)
            return try buildInstaller(lang: lang, installer: got, game: game, packs: packs)
        }
        let need = archives(lang)
        guard !need.isEmpty else { throw Failure(message: "\(lang) has no download") }
        let (folder, nodes) = try Mega.list(multi13Folder)
        var got: [String: URL] = [:]
        defer { for u in got.values { try? fm.removeItem(at: u) } }
        var before: Int64 = 0
        for a in need {
            guard let n = nodes.first(where: { $0.name == a.name }) else {
                throw Failure(message: "The mod's MEGA folder has no \(a.name) any more. Download it from the mod's page yourself and use Import….")
            }
            let f = fm.temporaryDirectory.appendingPathComponent("nfsu2-\(UUID().uuidString)-\(a.name)")
            got[a.name] = f
            let base = before
            try Mega.download(n, folder: folder, to: f) { progress("Downloading \(a.name)", base + $0, total) }
            guard try sha256(f) == a.sha256 else {
                throw Failure(message: "\(a.name) on MEGA is not the release this was made for. Download the mod from its page yourself and use Import….")
            }
            before += a.size
        }
        progress("Building", total, total)
        return try buildMulti13(lang: lang, game: game, core: got[core.name], dub: dubs[lang].flatMap { got[$0.archive.name] }, packs: packs)
    }

    /// Import: a local copy of what the language needs (an archive or folder).
    /// Multi 13: a folder with the archives (or the archives' files extracted), or one archive.
    static func importCopy(lang: String, src: URL, game: URL, packs: URL? = nil) throws -> String {
        if lang == "english" {
            if !UHUDPack.isDirectory(src), try sha256(src) != subtitles.sha256 {
                throw Failure(message: "\(src.lastPathComponent) is not the release this was made for (\(subtitles.name)). Choose it as downloaded, or the folder it was unpacked to.")
            }
            return try buildSubtitles(mod: src, game: game, packs: packs)
        }
        if pages[lang] != nil { return try buildTranslation(lang: lang, src: src, game: game, packs: packs) }
        if installers[lang] != nil {
            let (exe, temp) = try pinnedInstaller(lang, src)
            defer { if let t = temp { try? FileManager.default.removeItem(at: t) } }
            return try buildInstaller(lang: lang, installer: exe, game: game, packs: packs)
        }
        // Multi 13: the pinned archives in a folder, or a single archive
        var core: URL? = nil, dub: URL? = nil
        let candidates = UHUDPack.isDirectory(src)
            ? ((FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [])
            : [src]
        for u in candidates where u.pathExtension.lowercased() == "rar" {
            let n = u.lastPathComponent.lowercased()
            if n.contains("multi13core") { core = u }
            if let d = dubs[lang], n.contains("multi13\(d.dir.lowercased())dub") { dub = u }
        }
        // checked as a download is: only the release this was made with
        for (u, a) in [(core, LanguagePacks.core), (dub, dubs[lang]?.archive ?? LanguagePacks.core)] {
            guard let u = u else { continue }
            guard try sha256(u) == a.sha256 else {
                throw Failure(message: "\(u.lastPathComponent) is not the release this was made for (\(a.name), \(formatBytesPlain(a.size))).")
            }
        }
        return try buildMulti13(lang: lang, game: game, core: core, dub: dub, packs: packs)
    }
}
