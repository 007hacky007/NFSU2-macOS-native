// Texture packs: the community's texture mods, made into packs the engine draws in place
// of the game's textures (runtime/texrep.m, launcher/TexturePackBuilder.swift).
//
// None of them is part of this app.  The catalog lists the most downloaded ones.  Where
// the author's page has a direct link, Download fetches the release this was tested
// with, only when the player clicks it, and refuses any other file (SHA-256).  Where the
// file sits behind a browser-only page (a wait, a captcha, a login), the entry says so
// and Import… takes the copy the player downloaded; Import… also takes any other
// TexMod pack, TexWizard pack or texture mod, and works when a server is down.
//
// Everything lives in ~/Library/Application Support/NFSU2/TexturePacks: one .ntxp per
// pack and packs.json (the list, in its order, and which are on).  The game folder is
// never changed.  play() hands the engine the packs that are on, in order, in
// NFSU2_TEXPACKS (where two change the same texture, the higher one's is drawn; the
// Upscaled HUD pack, which has its own switch, comes after them).
import AppKit
import CryptoKit

struct CatalogPack: Identifiable {
    let id: String
    let name: String
    let author: String
    let changes: String           // what it changes, in plain words
    let kind: String              // "TexMod pack" ...
    let page: URL                 // the author's page
    let download: URL?            // nil: Import only
    let fileName: String          // the file as downloaded
    let size: Int64               // the file's size (0: not known)
    let sha256: String?           // the release this was tested with (Download only)
    let exclude: [String]         // parts of the download not to use
    let note: String              // terms, why Import only, what it needs
}

enum TexturePackCatalog {
    static let packs: [CatalogPack] = [
        CatalogPack(id: "remastered-ug2", name: "Remastered Underground 2", author: "instanity",
                    changes: "Roads, walls, sky, vegetation, billboards, car textures, HUD and effects.",
                    kind: "TexMod pack",
                    page: URL(string: "https://www.gamepressure.com/download/need-for-speed-underground-2-remastered-underground-2-v10-mod/z014c4d")!,
                    download: nil, fileName: "underground2rem10.zip", size: 121_453_867, sha256: nil, exclude: [],
                    note: "Import only: gamepressure.com gives the file to a browser after a wait. Download it there, then Import… the .zip (or REMASTER.tpf). Its ReShade preset and plugins are not used."),
        CatalogPack(id: "retextured", name: "RETextured v2.0", author: "Dragozool",
                    changes: "Higher-resolution roads, fences, trees and buildings.",
                    kind: "TexMod pack",
                    page: URL(string: "https://www.gamepressure.com/download/need-for-speed-underground-2-retextured-v20-mod/ze142be")!,
                    download: nil, fileName: "nfsu2retex20.zip", size: 140_432_669, sha256: nil, exclude: [],
                    note: "Import only: gamepressure.com gives the file to a browser after a wait. Download it there, then Import… the .zip (or the .tpf in it)."),
        CatalogPack(id: "last-breath", name: "Last Breath Final", author: "Stre1itzia",
                    changes: "4K roads, remastered map and tracks, 250+ HD textures, HD HUD.",
                    kind: "TexMod pack",
                    page: URL(string: "https://nfsmods.xyz/mod/1717")!,
                    download: nil, fileName: "U2_LastBreath_Final.rar", size: 0, sha256: nil, exclude: [],
                    note: "Import only: the mod's page links to a file host that needs a browser (about 372 MB). Import… the .rar or its .tpf. The author asks that its textures are not repacked; the pack made here stays on this Mac."),
        CatalogPack(id: "hdri-sky-8k", name: "8K HDRI Skyboxes", author: "BadassBaboon, TexWizard port by RKBDI",
                    changes: "The sky at sunrise, sunset and night, at 8192 × 2048.",
                    kind: "TexWizard pack",
                    page: URL(string: "https://nfsmods.xyz/mod/7417")!,
                    download: URL(string: "https://nfsmods.xyz/uploads/mods/7417/e318e2-UG2HDR8KSKY_UPDATE.7z")!,
                    fileName: "UG2HDR8KSKY_UPDATE.7z", size: 42_963_808,
                    sha256: "c62d71ab1742cb97d0598f69be1449afeda59747b27f65ff56c455486d9911b8",
                    exclude: ["optional/"],
                    note: "Uses about 205 MB on disk."),
        CatalogPack(id: "scout-ui", name: "Scout's UI Remaster", author: "BlackScout",
                    changes: "Menus, HUD, fonts, speedometers and part of the map redrawn at four times the detail.",
                    kind: "texture files",
                    page: URL(string: "https://nfsmods.xyz/mod/378")!,
                    download: URL(string: "https://nfsmods.xyz/uploads/mods/378/af6d1b-ScoutNFSU2UIRemaster1.0.1.zip")!,
                    fileName: "ScoutNFSU2UIRemaster1.0.1.zip", size: 11_685_588,
                    sha256: "57cd1ca8ff93df4c4d155eabe57c40587f8925c50f19e17ce8452ae3e39e8f23",
                    exclude: ["old tpf version/"],
                    note: "Its textures may be reused with credit to BlackScout. The HD Content Support plugin it asks for is not needed here."),
    ]
    static func pack(_ id: String) -> CatalogPack? { packs.first { $0.id == id } }
}

/// A pack the launcher made (packs.json).
struct InstalledPack: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var author: String
    var file: String              // in TexturePackStore.dir
    var enabled: Bool
    var textures: Int
    var bytes: Int64
    var source: String            // where it came from
}

final class TexturePackStore: ObservableObject {
    static var testDir: URL? = nil                                 // main.swift's test modes
    static var dir: URL { testDir ?? Paths.home.appendingPathComponent("Library/Application Support/NFSU2/TexturePacks") }
    static var list: URL { dir.appendingPathComponent("packs.json") }

    @Published private(set) var installed: [InstalledPack] = []    // in priority order
    @Published var phase: [String: String] = [:]                   // id -> what it is doing
    @Published var fraction: [String: Double] = [:]                // id -> download progress
    @Published var errors: [String: String] = [:]
    var game: () -> URL? = { nil }                                 // the game folder (the model's)

    init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: Self.list), let l = try? JSONDecoder().decode([InstalledPack].self, from: d) else { installed = []; return }
        installed = l.filter { FileManager.default.fileExists(atPath: Self.dir.appendingPathComponent($0.file).path) }
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(installed).write(to: Self.list, options: .atomic)
        } catch { errors["store"] = "The list of texture packs could not be saved: \(error.localizedDescription)" }
    }

    /// The packs that are on, highest first (NFSU2_TEXPACKS).
    var enabledPaths: [String] { installed.filter { $0.enabled }.map { Self.dir.appendingPathComponent($0.file).path } }
    var enabledCount: Int { installed.filter { $0.enabled }.count }
    func pack(_ id: String) -> InstalledPack? { installed.first { $0.id == id } }
    var busy: Bool { !phase.isEmpty }
    /// A made-up list for the launcher's snapshot (main.swift NFSU2_LAUNCHER_STATE).
    func fake(_ l: [InstalledPack]) { installed = l }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let i = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[i].enabled = on; save()
    }
    func move(_ id: String, by d: Int) {
        guard let i = installed.firstIndex(where: { $0.id == id }), i + d >= 0, i + d < installed.count else { return }
        installed.swapAt(i, i + d); save()
    }
    func remove(_ id: String) {
        guard let i = installed.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent(installed[i].file))
        installed.remove(at: i); save()
    }

    // MARK: adding a pack

    /// Download (catalog entries with a direct link): fetch, check, make the pack, turn it on.
    func download(_ c: CatalogPack, done: ((Bool) -> Void)? = nil) {
        guard let url = c.download, let sha = c.sha256, let game = game() else { return }
        let host = url.host ?? "the mod's site"
        start(c.id, "Downloading from \(host)…") { report in
            let file = try UHUDPack.Downloader(progress: { got in
                report(got >= c.size ? "Checking the download…" : "Downloading from \(host)… \(formatBytes(got)) of \(formatBytes(c.size))",
                       c.size > 0 ? min(1, Double(got) / Double(c.size)) : 0)
            }, host: host, hint: "use Import…").fetch(url)
            defer { try? FileManager.default.removeItem(at: file) }
            guard try Self.sha256(file) == sha else {
                throw UHUDPack.Failure(message: "The file on \(host) is not the release this was tested with. Download it from its page yourself and use Import….")
            }
            return try self.make(c.id, name: c.name, author: c.author, mod: file, game: game, exclude: c.exclude,
                                 source: "Downloaded from \(host) (\(c.fileName))", report)
        } done: { done?($0) }
    }

    /// Import…: a file or folder the player chooses, for a catalog entry or any other mod.
    func importPanel(for c: CatalogPack?) {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Import"
        p.message = c.map { "Choose \($0.name) as downloaded (\($0.fileName)), or the folder it was extracted to. Your game folder stays as it is." }
            ?? "Choose a texture mod: a TexMod pack (.tpf), a TexWizard pack (its folder), or a mod's archive (.zip, .7z, .rar) or folder. Your game folder stays as it is."
        p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let mod = p.url else { return }
        importMod(mod, for: c)
    }

    func importMod(_ mod: URL, for c: CatalogPack?, done: ((Bool) -> Void)? = nil) {
        guard let game = game() else { return }
        let base = mod.deletingPathExtension().lastPathComponent
        let id = c?.id ?? "import-" + String(base.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(40))
            + "-" + String(UUID().uuidString.prefix(6)).lowercased()
        start(id, "Making the pack from \(mod.lastPathComponent)…") { report in
            try self.make(id, name: c?.name ?? base, author: c?.author ?? "", mod: mod, game: game,
                          exclude: c?.exclude ?? [], source: "Imported from \(mod.lastPathComponent)", report)
        } done: { done?($0) }
    }

    /// Runs work off the main thread with its progress shown on the entry.
    private func start(_ id: String, _ first: String,
                       _ work: @escaping (@escaping (String, Double?) -> Void) throws -> InstalledPack,
                       done: @escaping (Bool) -> Void) {
        phase[id] = first; fraction[id] = nil; errors[id] = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let report: (String, Double?) -> Void = { text, f in
                DispatchQueue.main.async { if self.phase[id] != nil { self.phase[id] = text; self.fraction[id] = f } }
            }
            var made: InstalledPack? = nil, err: String? = nil
            do { made = try work(report) }
            catch let e as UHUDPack.Failure { err = e.message }
            catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                self.phase[id] = nil; self.fraction[id] = nil
                if let m = made {
                    if let i = self.installed.firstIndex(where: { $0.id == m.id }) { self.installed[i] = m }
                    else { self.installed.insert(m, at: 0) }        // a new pack goes on top
                    self.save()
                } else { self.errors[id] = err }
                done(made != nil)
            }
        }
    }

    private func make(_ id: String, name: String, author: String, mod: URL, game: URL, exclude: [String],
                      source: String, _ report: @escaping (String, Double?) -> Void) throws -> InstalledPack {
        let file = id + ".ntxp"
        let s = try PackBuilder.build(mod: mod, game: game, exclude: exclude, to: Self.dir.appendingPathComponent(file)) { report($0, nil) }
        if ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil {
            print("texture pack \(id): \(s.textures) textures (\(s.texmod) TexMod, \(s.named) by name, \(s.content) by content), \(s.bytes) bytes")
            print("  from: " + s.sources.joined(separator: ", "))
            if !s.skipped.isEmpty { print("  skipped \(s.skipped.count): " + s.skipped.prefix(8).joined(separator: "; ")) }
        }
        return InstalledPack(id: id, name: name, author: author, file: file, enabled: true,
                             textures: s.textures, bytes: s.bytes, source: source)
    }

    static func sha256(_ u: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: u)
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk = h.readData(ofLength: 8 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
