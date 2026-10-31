// The Texture Packs window's list: the community's NFSU2 texture mods, most popular first.
// The list is launcher/texture-packs.json in the repository (pack.sh puts it in the app's
// Resources).  So that a pack whose author uploads a new file can be fixed without a new
// app release, the window also fetches the same file from the repository's main branch
// (at most once per launch, HTTPS only), checks it strictly and uses it when it is valid
// and not older than the app's own; the last good copy is kept in Application Support for
// the next start without a connection.  Nothing else is ever fetched from that address,
// and a download is still always checked against the list's SHA-256: the list comes from
// the same repository as the app's code.
//
// texture-packs.json: {"version": 1, "updated": "YYYY-MM-DD", "packs": [...]}, each pack:
//   id, name, author, category (ui | world | sky | cars), kind (what the mod is made of),
//   description, page (the author's page), fileName and size (as downloaded), releases
//   ("EU and NA": tested with both), note, include / exclude (parts of the download used
//   or left out: a mod's variants, the originals it keeps for uninstalling);
//   download + sha256: only for a release that was downloaded from the author's page and
//   tested in the game (the launcher refuses any other file); knownSHA256: tested releases
//   without a direct link, so Import… recognizes them.  Entries without download are
//   "Details and Import": the player downloads the file on the page and imports it.
//
// Adding or fixing an entry: download the release from the author's page, make a pack of it
// with NFSU2_LAUNCHER_TEST=texpack:<file>:<game>:<pack> (it says which textures it found),
// run the game with NFSU2_TEXPACKS=<pack> NFSU2_TEXPACKS_LOG=1 on both builds, then put the
// URL, size and SHA-256 in texture-packs.json and move "updated" to the day.
// tools/check_texpacks.py checks that every download still serves the pinned file.
//
//   NFSU2_TEXPACKS_CATALOG_URL=<url>   fetch the list from there instead (tests: https,
//                                      file:// or http://127.0.0.1); "off": no fetch
//   NFSU2_TEXPACKS_BUNDLED=<file>      the app's own list, for a launcher outside an app
import Foundation

struct CatalogPack: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let author: String
    let category: String          // ui | world | sky | cars
    let kind: String              // "TexMod pack" ...
    let description: String       // what it changes, in plain words
    let page: URL                 // the author's page
    let download: URL?            // the tested release; nil: Details and Import
    let sha256: String?           // its SHA-256 (with download only)
    let knownSHA256: [String]?    // tested releases without a direct link
    let fileName: String          // the file as downloaded ("" when not known)
    let size: Int64               // its size (0: not known)
    let include: [String]?        // only these parts of the download are used
    let exclude: [String]?        // these are not
    let releases: String          // "EU and NA" (tested) or "not checked"
    let note: String?
    static let categories = [("all", "All"), ("ui", "Menus and HUD"), ("world", "World"), ("sky", "Sky"), ("cars", "Cars")]
}

final class TexturePackCatalog: ObservableObject {
    static let shared = TexturePackCatalog()
    static let onlineURL = URL(string: "https://raw.githubusercontent.com/TalhaMudo/NFSU2Recomp/main/launcher/texture-packs.json")!
    // where a pack's page and its download may be (the sites the list was made from)
    static let pageHosts: Set<String> = ["nfsmods.xyz", "www.gamepressure.com"]
    static let downloadHosts: Set<String> = ["nfsmods.xyz"]

    struct File: Decodable { let version: Int; let updated: String; let packs: [CatalogPack] }

    @Published private(set) var packs: [CatalogPack] = []
    @Published private(set) var source = ""          // "built in", "online", "saved online copy", "none"
    private(set) var updated = ""
    private var fetched = false

    static func pack(_ id: String) -> CatalogPack? { shared.packs.first { $0.id == id } }
    /// The entry a file the player imports is a tested release of.
    static func pack(sha256: String) -> CatalogPack? {
        shared.packs.first { $0.sha256 == sha256 || ($0.knownSHA256 ?? []).contains(sha256) }
    }

    init() { loadLocal() }

    static var cacheURL: URL { TexturePackStore.dir.appendingPathComponent("texture-packs.json") }
    static var bundledURL: URL? {
        if let e = ProcessInfo.processInfo.environment["NFSU2_TEXPACKS_BUNDLED"], !e.isEmpty { return URL(fileURLWithPath: e) }
        return Bundle.main.url(forResource: "texture-packs", withExtension: "json")
    }

    /// The app's own list, or the saved online copy when that is not older.
    func loadLocal() {
        var best: File? = nil, from = "none"
        if let u = Self.bundledURL, let d = try? Data(contentsOf: u) {
            do { best = try Self.validate(d); from = "built in" }
            catch { NSLog("texture-packs.json in the app: \(error)") }
        }
        if let d = try? Data(contentsOf: Self.cacheURL), let f = try? Self.validate(d), f.updated >= (best?.updated ?? "") {
            best = f; from = "saved online copy"
        }
        packs = best?.packs ?? []; updated = best?.updated ?? ""; source = from
    }

    /// Once per launch: the list from the repository, if it is valid and not older than ours.
    func refresh(done: ((String) -> Void)? = nil) {
        guard !fetched else { done?(source); return }
        fetched = true
        let env = ProcessInfo.processInfo.environment["NFSU2_TEXPACKS_CATALOG_URL"] ?? ""
        if env == "off" { done?(source); return }
        guard let u = env.isEmpty ? Self.onlineURL : URL(string: env), Self.allowedListURL(u, overridden: !env.isEmpty) else {
            NSLog("texture packs: list address not allowed: \(env)"); done?(source); return
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let s = URLSession(configuration: cfg)
        s.dataTask(with: u) { data, resp, err in
            var file: File? = nil, why = err?.localizedDescription ?? "no answer"
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 { why = "HTTP \(http.statusCode)" }
            else if let d = data, d.count <= 2 << 20 {
                do { file = try Self.validate(d) } catch { why = "\(error)" }
            } else if data != nil { why = "too large" }
            DispatchQueue.main.async {
                if let f = file, f.updated >= self.updated {
                    self.packs = f.packs; self.updated = f.updated; self.source = "online"
                    try? FileManager.default.createDirectory(at: TexturePackStore.dir, withIntermediateDirectories: true)
                    try? data?.write(to: Self.cacheURL, options: .atomic)
                } else if file == nil {
                    NSLog("texture packs: the online list was not used (\(why)); using the \(self.source) one")
                }
                done?(self.source)
            }
        }.resume()
        s.finishTasksAndInvalidate()
    }

    static func allowedListURL(_ u: URL, overridden: Bool) -> Bool {
        if u.scheme == "https" { return overridden || u == onlineURL }
        guard overridden else { return false }
        return u.isFileURL || (u.scheme == "http" && ["127.0.0.1", "localhost"].contains(u.host ?? ""))
    }

    struct Invalid: Error, CustomStringConvertible { let description: String }

    /// The list, if every field is what the launcher expects; otherwise an error.
    static func validate(_ data: Data) throws -> File {
        let f: File
        do { f = try JSONDecoder().decode(File.self, from: data) } catch { throw Invalid(description: "not a texture pack list: \(error)") }
        func bad(_ id: String, _ s: String) -> Invalid { Invalid(description: "\(id): \(s)") }
        guard f.version == 1 else { throw Invalid(description: "version \(f.version) is not one this launcher reads") }
        guard f.updated.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { throw Invalid(description: "bad date") }
        guard (1...1000).contains(f.packs.count) else { throw Invalid(description: "\(f.packs.count) packs") }
        // only in the launcher's tests (NFSU2_LAUNCHER_TEST): downloads from a server on this Mac
        let testHosts = ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil
        func hex(_ s: String) -> Bool { s.count == 64 && s.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) } }
        func text(_ s: String, _ max: Int) -> Bool { s.count <= max && !s.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
        var ids = Set<String>()
        for p in f.packs {
            guard p.id.range(of: #"^[a-z0-9-]{1,64}$"#, options: .regularExpression) != nil, ids.insert(p.id).inserted
            else { throw bad(p.id, "bad or repeated id") }
            guard !p.name.isEmpty, text(p.name, 120), text(p.author, 120), text(p.kind, 80), text(p.description, 400),
                  text(p.fileName, 200), text(p.releases, 80), text(p.note ?? "", 600)
            else { throw bad(p.id, "a text field is empty, too long or has control characters") }
            guard ["ui", "world", "sky", "cars"].contains(p.category) else { throw bad(p.id, "unknown category") }
            guard p.page.scheme == "https", pageHosts.contains(p.page.host ?? "") else { throw bad(p.id, "page not on an allowed site") }
            guard (0...4_000_000_000).contains(p.size) else { throw bad(p.id, "bad size") }
            if let d = p.download {
                let local = testHosts && d.scheme == "http" && d.host == "127.0.0.1"
                guard local || (d.scheme == "https" && downloadHosts.contains(d.host ?? "")) else {
                    throw bad(p.id, "download not over HTTPS from an allowed site")
                }
                guard let s = p.sha256, hex(s) else { throw bad(p.id, "download without a valid SHA-256") }
                guard p.size > 0 else { throw bad(p.id, "download without its size") }
            } else if p.sha256 != nil { throw bad(p.id, "SHA-256 without a download") }
            guard (p.knownSHA256 ?? []).count <= 20, (p.knownSHA256 ?? []).allSatisfy(hex) else { throw bad(p.id, "bad known SHA-256") }
            for l in [p.include ?? [], p.exclude ?? []] {
                guard l.count <= 20, l.allSatisfy({ !$0.isEmpty && text($0, 100) }) else { throw bad(p.id, "bad include or exclude") }
            }
        }
        return f
    }
}
