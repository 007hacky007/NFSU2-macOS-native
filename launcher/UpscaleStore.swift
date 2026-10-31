// The upscaled texture pack on this Mac (UpscaleBuilder.swift makes it, runtime/texrep.m
// draws it): Build, Stop, Delete, and its options.  Build fetches the model the first
// time (9 MB, from its author's GitHub, refused unless it is the tested release by
// SHA-256); Import Model… takes a copy the player has.  The switch is LauncherModel's
// upscaledTextures (off: the original game); play() calls environment().
import AppKit
import CryptoKit

final class UpscaleStore: ObservableObject {
    struct Info { var textures: Int; var bytes: Int64; var scale: Int; var built: String }

    @Published private(set) var info: Info? = nil
    @Published private(set) var hasModel = false
    @Published private(set) var phase: String? = nil
    @Published private(set) var fraction: Double? = nil
    @Published var error: String? = nil
    private let defaults = UserDefaults.standard
    private var stop = false
    /// the parts the engine uses (pack folders)
    @Published var parts: Set<String> { didSet { defaults.set(UpscalePack.parts.filter { parts.contains($0) }, forKey: Prefs.upscaledParts) } }
    /// GPU memory for the pack's textures, MB; 0: a sixth of the Mac's memory, at most 4 GB
    @Published var budget: Int { didSet { defaults.set(budget, forKey: Prefs.upscaledBudget) } }
    /// 0: 4x with 16 GB of memory or more, otherwise 2x
    @Published var scale: Int { didSet { defaults.set(scale, forKey: Prefs.upscaledScale) } }
    /// the engine collects the textures it loads (menus, cars) for the next build
    @Published var collect: Bool { didSet { defaults.set(collect, forKey: Prefs.upscaledCollect) } }

    static let budgets = [0, 1024, 2048, 4096, 8192]
    static var autoBudget: Int { Int(min(ProcessInfo.processInfo.physicalMemory / 6, 4096 << 20) >> 20) }

    init() {
        parts = Set(defaults.stringArray(forKey: Prefs.upscaledParts) ?? UpscalePack.defaultParts)
        budget = defaults.integer(forKey: Prefs.upscaledBudget)
        scale = defaults.integer(forKey: Prefs.upscaledScale)
        collect = defaults.bool(forKey: Prefs.upscaledCollect)
        refresh()
    }

    var busy: Bool { phase != nil }
    var buildScale: Int { scale == 2 || scale == 4 ? scale : UpscaleBuilder.autoScale }
    /// A made-up state for the launcher's snapshot (main.swift NFSU2_LAUNCHER_STATE).
    func fake(info: Info?, phase: String? = nil, fraction: Double? = nil) {
        self.info = info; self.phase = phase; self.fraction = fraction; hasModel = info != nil
    }

    func refresh() {
        hasModel = FileManager.default.fileExists(atPath: UpscalePack.model.path)
        guard let s = try? String(contentsOf: UpscalePack.pack.appendingPathComponent("pack.ini"), encoding: .utf8) else { info = nil; return }
        var kv: [String: String] = [:]
        for l in s.split(whereSeparator: \.isNewline) {
            let p = l.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if p.count == 2 { kv[p[0]] = p[1] }
        }
        let n = Int(kv["textures"] ?? "") ?? 0
        info = n > 0 ? Info(textures: n, bytes: Int64(kv["bytes"] ?? "") ?? 0, scale: Int(kv["scale"] ?? "") ?? 0,
                            built: String((kv["built"] ?? "").prefix(10))) : nil
    }

    /// The engine's variables (runtime/texrep.m); a variable set by hand still wins.
    func environment(on: Bool) {
        if on, info != nil {
            setenv("NFSU2_TEXTURES", "upscaled", 0)
            setenv("NFSU2_TEXPACK", UpscalePack.pack.path, 0)
            setenv("NFSU2_TEXPARTS", UpscalePack.parts.filter { parts.contains($0) }.joined(separator: ","), 0)
            if budget > 0 { setenv("NFSU2_TEXBUDGET", String(budget), 0) }
        }
        if collect { setenv("NFSU2_TEXDUMP", UpscalePack.dump.path, 0) }
    }

    // MARK: the model

    static func sha256(_ u: URL) throws -> String { try TexturePackStore.sha256(u) }
    /// The model file is the tested release (checked before every build).
    static func checkModel(_ u: URL) throws {
        guard FileManager.default.fileExists(atPath: u.path) else { throw UpscaleFailure(message: "The model is not on this Mac.") }
        guard try sha256(u) == UpscalePack.modelSHA256 else {
            throw UpscaleFailure(message: "The model file is not the release this was tested with; delete the pack and build again.")
        }
    }
    private func fetchModel(_ report: @escaping (String, Double?) -> Void) throws {
        let dest = UpscalePack.model
        if (try? Self.checkModel(dest)) != nil { return }
        let host = UpscalePack.modelURL.host ?? "github.com"
        report("Downloading the model from \(host)…", 0)
        let file = try UHUDPack.Downloader(progress: { got in
            report("Downloading the model from \(host)… \(formatBytes(got)) of \(formatBytes(UpscalePack.modelSize))",
                   min(1, Double(got) / Double(UpscalePack.modelSize)))
        }, host: host, hint: "use Import Model…").fetch(UpscalePack.modelURL)
        defer { try? FileManager.default.removeItem(at: file) }
        try install(file, from: host)
    }
    private func install(_ file: URL, from: String) throws {
        guard try Self.sha256(file) == UpscalePack.modelSHA256 else {
            throw UpscaleFailure(message: "The file from \(from) is not the model release this was tested with (\(UpscalePack.modelFile), SHA-256 \(UpscalePack.modelSHA256.prefix(12))…).")
        }
        let dest = UpscalePack.model
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: file, to: dest)
    }
    /// Import Model…: a copy of 4x-PBRify_UpscalerSPANV4.pth the player has.
    func importModelPanel() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.prompt = "Import"
        p.message = "Choose \(UpscalePack.modelFile) (from \(UpscalePack.modelPage.absoluteString), Extras/Old_Models)."
        p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let u = p.url else { return }
        importModel(u)
    }
    func importModel(_ u: URL) {
        do { try install(u, from: u.lastPathComponent); error = nil } catch { self.error = (error as? UpscaleFailure)?.message ?? error.localizedDescription }
        refresh()
    }

    // MARK: Build, Stop, Delete

    func build(game: URL, done: ((Bool) -> Void)? = nil) {
        guard phase == nil else { return }
        stop = false; error = nil
        phase = "Starting…"; fraction = nil
        let scale = buildScale
        DispatchQueue.global(qos: .userInitiated).async {
            let report: (String, Double?) -> Void = { t, f in
                DispatchQueue.main.async { if self.phase != nil { self.phase = t; self.fraction = f } }
            }
            var err: String? = nil
            do {
                try self.fetchModel(report)
                DispatchQueue.main.async { self.hasModel = true }
                let b = UpscaleBuilder(game: game, out: UpscalePack.pack, collected: [UpscalePack.dump], scale: scale, model: UpscalePack.model)
                if ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil { b.log = { print($0) } }
                let sum = try b.build(progress: report, cancelled: { self.stop })
                if sum.textures == 0 {
                    throw UpscaleFailure(message: "No texture of the game could be read in \(game.path). Is it the game's folder?")
                }
            } catch let e as UpscaleFailure { err = e.message }
            catch let e as UHUDPack.Failure { err = e.message }
            catch let e as ModelFailure { err = "The model cannot be used: \(e.message)." }
            catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                self.phase = nil; self.fraction = nil; self.error = err
                self.refresh()
                done?(err == nil)
            }
        }
    }
    func cancel() { stop = true; if phase != nil { phase = "Stopping after the textures being made…" } }
    /// The pack, the textures collected while playing and the model.
    func delete() {
        for u in [UpscalePack.pack, UpscalePack.dump, UpscalePack.model.deletingLastPathComponent()] {
            try? FileManager.default.removeItem(at: u)
        }
        error = nil
        refresh()
    }
}

/// main.swift's test modes for the upscaled pack (NFSU2_LAUNCHER_TEST=upscale…); true if handled.
func runUpscaleTest(_ t: String) -> Bool {
    let p = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    let env = ProcessInfo.processInfo.environment
    switch p[0] {
    case "upscale" where p.count >= 3:
        DispatchQueue.global().async {
            let model = env["NFSU2_UPSCALE_MODEL"].map { URL(fileURLWithPath: $0) } ?? UpscalePack.model
            let scale = Int(env["NFSU2_UPSCALE_SCALE"] ?? "") ?? UpscaleBuilder.autoScale
            let dump = env["NFSU2_UPSCALE_COLLECTED"].map { [URL(fileURLWithPath: $0)] } ?? []
            let b = UpscaleBuilder(game: URL(fileURLWithPath: p[1]), out: URL(fileURLWithPath: p[2]), collected: dump, scale: scale, model: model)
            if p.count >= 4, let n = Int(p[3]), n > 0 { b.limit = n }
            if p.count >= 5, !p[4].isEmpty { b.only = Set(p[4].split(separator: ",").compactMap { UInt64($0, radix: 16) }) }
            b.log = { print($0); fflush(stdout) }
            b.rawLevels = env["NFSU2_UPSCALE_RAW"].map { URL(fileURLWithPath: $0) }
            do { _ = try b.build(progress: { _, _ in }, cancelled: { false }); exit(0) }
            catch { print("upscale FAILED: \((error as? UpscaleFailure)?.message ?? (error as? ModelFailure)?.message ?? "\(error)")"); exit(1) }
        }
        return true
    case "upscale-build" where p.count == 3, "upscale-import" where p.count == 3:
        UpscalePack.testDir = URL(fileURLWithPath: p[2])
        let s = UpscaleStore()
        if p[0] == "upscale-import" {
            s.importModel(URL(fileURLWithPath: p[1]))
            print(s.error.map { "import FAILED: \($0)" } ?? "model imported: \(s.hasModel)"); exit(s.error == nil ? 0 : 1)
        }
        s.build(game: URL(fileURLWithPath: p[1])) { ok in
            if ok, let i = s.info { print("pack: \(i.textures) textures, \(i.bytes) bytes, \(i.scale)x") }
            else { print("build FAILED: \(s.error ?? "?")") }
            exit(ok ? 0 : 1)
        }
        return true
    case "upscale-scan" where p.count == 2:
        let (ents, files) = TextureScan.scan(game: URL(fileURLWithPath: p[1]))
        print("\(ents.count) textures in \(files) files")
        for e in ents.values.sorted(by: { $0.hash < $1.hash }) {
            print(String(format: "%016llx", e.hash), e.name, e.part, "\(e.w)x\(e.h)", e.fmt.rawValue, UpscaleBuilder.eligible(e, 4) ?? "ok")
        }
        exit(0)
    case "upscale-verify" where p.count == 3:
        // every pack file against the game's texture: its 4x4 (2x2) averages are the original
        // again (back-projection), within what block compression leaves
        let game = URL(fileURLWithPath: p[1]), pack = URL(fileURLWithPath: p[2])
        let (ents, _) = TextureScan.scan(game: game)
        guard let man = try? String(contentsOf: pack.appendingPathComponent("manifest.csv"), encoding: .utf8) else { print("no manifest"); exit(1) }
        var worst = 99.0, n = 0
        for row in man.split(separator: "\n").dropFirst() {
            let c = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard c.count == 10, let h = UInt64(c[0], radix: 16), let e = ents[h], let d = try? Data(contentsOf: pack.appendingPathComponent(c[9])) else {
                print("FAIL \(row)"); exit(1)
            }
            let b = [UInt8](d), sc = Int(c[7]) ?? 0
            let lw = e.w * sc, lh = e.h * sc
            guard b.count >= 128 + e.fmt.levelSize(lw, lh), Int(b[16]) | Int(b[17]) << 8 == lw, Int(b[12]) | Int(b[13]) << 8 == lh,
                  Int(b[28]) == (sc == 4 ? 2 : 1) else { print("FAIL \(c[9]): header"); exit(1) }
            let big = TexImage.decode(Array(b[128..<(128 + e.fmt.levelSize(lw, lh))]), lw, lh, e.fmt)
            let orig = TexImage.decode((try? TextureScan.level0(game, e)) ?? [], e.w, e.h, e.fmt)
            var se = 0.0
            for y in 0..<e.h { for x in 0..<e.w { for k in 0..<3 {
                var a = 0.0
                for i in 0..<sc { for j in 0..<sc { a += Double(big.px[((y * sc + i) * lw + x * sc + j) * 4 + k]) } }
                let dv = a / Double(sc * sc) - Double(orig.px[(y * e.w + x) * 4 + k]); se += dv * dv
            } } }
            let psnr = se == 0 ? 99 : 10 * log10(255 * 255 / (se / Double(e.w * e.h * 3)))
            print(String(format: "%@ %.1f dB", c[9], psnr)); worst = min(worst, psnr); n += 1
        }
        print(String(format: "verified %d, lowest %.1f dB", n, worst))
        exit(n > 0 && worst >= 30 ? 0 : 1)
    default: return false
    }
}
