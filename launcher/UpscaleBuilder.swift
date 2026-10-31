// The upscaled texture pack: sharper world, sign, car and garage textures, made on
// this Mac from the player's own game files (runtime/texrep.m draws them).  This is
// the old tools/texpack/texpack.py builder in the launcher, without Python: the same
// steps, the same file names, the same pack (UpscaleImage.swift has the picture work,
// UpscaleModel.swift the model).  Nothing of the game leaves the Mac and no game
// file changes.  Per texture:
//   1. every texture pack (TPK) in the game's uncompressed bundles, level 0 as the game
//      uploads it (P8 textures expanded with their palette, as the game does), plus
//      the textures the engine collected while the player played (texture dump:
//      compressed front-end and car bundles this scan cannot read);
//   2. the colour 4x with PBRify Upscaler SPAN v4, padded by wrapping for tiling
//      textures, by mirroring for the others;
//   3. the original's colour and alpha kept, back-projected onto the original;
//   4. only the levels ABOVE the original's size (4x pack: 4x and 2x; 2x pack: 2x),
//      in its block format; the engine puts the game's own levels underneath.
// Skipped: 32 x 32 texels or less, one colour, smooth (skies, glows: the model would
// add grain), the cars' 32-bit skin layers, animated flipbooks, cube maps.  The
// largest level is at most 2048 texels wide.
//
// <pack>/<part>/<NAME>_<w>x<h>_<hash>.dds, manifest.csv, pack.ini.  <hash>: XXH3-64 of
// level 0 seeded with w | h << 16 | D3DFORMAT << 32 (UpscaleHash.swift), which the
// engine computes at the upload.  A build can be stopped and started again: the
// textures made are kept.
import Foundation

enum UpscalePack {
    /// The model: fetched only when the player builds, from its author's repository,
    /// at the commit tested here, and used only with this SHA-256.
    static let modelFile = "4x-PBRify_UpscalerSPANV4.pth"
    static let modelURL = URL(string: "https://raw.githubusercontent.com/Kim2091/PBRify_Remix/67acc20b8fe44bf09530032b01f81859d532dc74/Extras/Old_Models/4x-PBRify_UpscalerSPANV4.pth")!
    static let modelSHA256 = "d1f1fa1af7a5ab23fcf143e75aac4951e6c52d56bf77d9ccd4d004a4831d0461"
    static let modelSize: Int64 = 9_016_813
    static let modelLicence = "CC0-1.0 (Kim2091, github.com/Kim2091/PBRify_Remix)"
    static let modelPage = URL(string: "https://github.com/Kim2091/PBRify_Remix")!

    static let parts = ["world", "signs", "cars", "garage", "sky", "effects", "frontend", "hud", "other"]
    /// the parts the engine uses unless the player picks others (sky, effects, menus and
    /// the HUD showed no gain or added grain)
    static let defaultParts = ["world", "signs", "cars", "garage"]
    static let partNames = ["world": "Roads and buildings", "signs": "Signs and ads", "cars": "Cars",
                            "garage": "Garage", "sky": "Sky", "effects": "Effects", "frontend": "Menus",
                            "hud": "HUD", "other": "Other"]

    static var testDir: URL? = nil
    static var dir: URL { testDir ?? Paths.home.appendingPathComponent("Library/Application Support/NFSU2/TexturePacks") }
    static var pack: URL { dir.appendingPathComponent("Upscaled") }
    static var dump: URL { dir.appendingPathComponent("Upscaled-collected") }
    static var model: URL { dir.appendingPathComponent("Models/" + modelFile) }
}

struct UpscaleFailure: Error { let message: String }

/// A texture of the game: where its level 0 is, and what it is.
struct GameTexture {
    var hash: UInt64
    var name: String
    var file: String                 // relative to the game folder ("" for a collected one)
    var part: String
    var w: Int, h: Int
    var fmt: TexFormat
    var mips: Int
    var src: (offset: Int, size: Int, palette: Int)     // palette -1: not P8
    var dds: URL? = nil              // a collected texture's file
}

enum TextureScan {
    /// The pack part of a texture, from its file and name (texpack.py part_of).
    static func part(_ path: String, _ name: String) -> String {
        let p = path.replacingOccurrences(of: "\\", with: "/").uppercased(), n = name.uppercased()
        let eff = ["SFX_", "XE_", "XETT_", "SKID_", "DUSTA", "GENERICA", "SPARK", "TIREPATCH", "RADIAL",
                   "RAINDROP", "WATERDROPLET", "ICESPLASH", "NEONBLUR", "SHADOWRAMP", "HEADLIGHTFLARE",
                   "HEADLIGHTGLOW", "FLOCKOFSEAGULLS"]
        let car = ["BRAKE", "GRILL", "HEADLIGHTS", "CHROME", "CARBON", "EXHAUST", "WINDOW", "LICENSE_PLATE",
                   "TIREBACK", "DRIVER", "TRAFFIC_", "INTERCOOLER", "HOODSLATS", "RUBBER_", "CARBOTTOM",
                   "ALUMINUM", "REAR_DEFROSTER", "2PLAYERHEADLIGHT"]
        func starts(_ s: String, _ l: [String]) -> Bool { l.contains { s.hasPrefix($0) } }
        if p.contains("DYNTEX") || n.contains("SKYDOME") { return "sky" }
        if starts(n, eff) { return "effects" }
        if p.hasPrefix("CARS/") { return "cars" }
        if p.hasPrefix("TRACKS/") || p.hasPrefix("NIS/") {
            if starts(n, ["SGN", "ADS_"]) { return "signs" }
            if n.hasPrefix("TRACKMAP") { return "frontend" }
            return "world"
        }
        if p.hasPrefix("FRONTEND/PLATFORMS/") { return "garage" }
        if p.hasPrefix("FRONTEND/") || p.hasPrefix("LANGUAGES/") { return "frontend" }
        if p.hasPrefix("GLOBAL/") {
            if starts(n, car) { return "cars" }
            if n.hasPrefix("ADS_") { return "signs" }
            if n.hasPrefix("OBJ_") { return "world" }
            if p.hasPrefix("GLOBAL/INGAME") || p.hasPrefix("GLOBAL/HUD") { return "hud" }
            return "frontend"
        }
        return "other"
    }

    static func seed(_ w: Int, _ h: Int, _ f: TexFormat) -> UInt64 { UInt64(w) | UInt64(h) << 16 | UInt64(f.d3d) << 32 }

    /// Every texture of the game's uncompressed bundles, by content (the first file wins).
    static func scan(game: URL, cancelled: () -> Bool = { false }) -> (textures: [UInt64: GameTexture], files: Int) {
        var out: [UInt64: GameTexture] = [:]
        var nfiles = 0
        let fm = FileManager.default
        // the order of os.walk with sorted folders and files: a folder's files, then its folders
        func walk(_ dir: URL, _ rel: String) {
            guard !cancelled(), let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            var files: [String] = [], dirs: [String] = []
            for n in names {
                var isDir: ObjCBool = false
                let u = dir.appendingPathComponent(n)
                // links are not followed (a game folder has none; one could point anywhere)
                if let v = try? u.resourceValues(forKeys: [.isSymbolicLinkKey]), v.isSymbolicLink == true { continue }
                if fm.fileExists(atPath: u.path, isDirectory: &isDir) { if isDir.boolValue { dirs.append(n) } else { files.append(n) } }
            }
            let byBytes: (String, String) -> Bool = { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            for f in files.sorted(by: byBytes) {
                let lf = f.lowercased()
                guard lf.hasSuffix(".bun") || lf.hasSuffix(".bin") else { continue }
                let r = rel.isEmpty ? f : rel + "/" + f
                let up = r.uppercased()
                if up.hasSuffix("VINYLS.BIN") || up.hasPrefix("FRONTEND/ENVMAPS/") || up.hasPrefix("MOVIES/") { continue }
                guard let d = try? Data(contentsOf: dir.appendingPathComponent(f), options: .mappedIfSafe) else { continue }
                let n = scanFile([UInt8](d), r) { e in if out[e.hash] == nil { out[e.hash] = e } }
                if n > 0 { nfiles += 1 }
            }
            for s in dirs.sorted(by: byBytes) { walk(dir.appendingPathComponent(s), rel.isEmpty ? s : rel + "/" + s) }
        }
        walk(game, "")
        return (out, nfiles)
    }

    @inline(__always) private static func u32(_ d: [UInt8], _ o: Int) -> Int {
        Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24
    }
    private static let tpkTag: [UInt8] = [0x00, 0x00, 0x30, 0xB3]

    /// the TPKs of one file (layout observed in the v1.2 files):
    ///   0xB3300000 TPK > 0xB3310000 info > 0x33310004 TextureInfo[0x7C]
    ///                                    > 0x33310005 platform records[0x20] (FourCC +0x14)
    ///                  > 0xB3320000 data > 0x33320002 pixels (128-byte aligned)
    static func scanFile(_ d: [UInt8], _ rel: String, _ found: (GameTexture) -> Void) -> Int {
        guard let first = find(d, tpkTag, 0) else { return 0 }
        _ = first
        var n = 0
        walkChunks(d, 0, d.count, rel, 0) { found($0); n += 1 }
        if n == 0 {                                        // padded / sectioned file: find TPK roots
            var i = find(d, tpkTag, 0)
            while let at = i {
                if at % 4 == 0 && at + 8 <= d.count {
                    let sz = u32(d, at + 4)
                    if at + 8 + sz <= d.count {
                        parseTPK(d, at + 8, at + 8 + sz, rel) { found($0); n += 1 }
                        i = find(d, tpkTag, at + 8 + sz)
                        continue
                    }
                }
                i = find(d, tpkTag, at + 1)
            }
        }
        return n
    }
    private static func find(_ d: [UInt8], _ pat: [UInt8], _ from: Int) -> Int? {
        guard from >= 0, d.count >= pat.count else { return nil }
        var i = from
        let last = d.count - pat.count
        while i <= last {
            if d[i] == pat[0] && d[i + 1] == pat[1] && d[i + 2] == pat[2] && d[i + 3] == pat[3] { return i }
            i += 1
        }
        return nil
    }
    private static func walkChunks(_ d: [UInt8], _ off: Int, _ end: Int, _ rel: String, _ depth: Int, _ found: (GameTexture) -> Void) {
        var o = off
        while o + 8 <= end {
            let cid = UInt32(truncatingIfNeeded: u32(d, o)), sz = u32(d, o + 4)
            let b = o + 8
            if sz > end - b { return }
            if cid == 0xB330_0000 { parseTPK(d, b, b + sz, rel, found) }
            else if cid & 0x8000_0000 != 0 && depth < 6 { walkChunks(d, b, b + sz, rel, depth + 1, found) }
            o = b + sz
        }
    }
    private static func parseTPK(_ d: [UInt8], _ off: Int, _ end: Int, _ rel: String, _ found: (GameTexture) -> Void) {
        var info: (Int, Int)? = nil, data: (Int, Int)? = nil
        var o = off
        while o + 8 <= end {
            let cid = UInt32(truncatingIfNeeded: u32(d, o)), sz = u32(d, o + 4), b = o + 8
            if b + sz > end { break }
            if cid == 0xB331_0000 { info = (b, b + sz) } else if cid == 0xB332_0000 { data = (b, b + sz) }
            o = b + sz
        }
        guard let inf = info, let dat = data else { return }
        var ents: (Int, Int)? = nil, plat: (Int, Int)? = nil
        o = inf.0
        while o + 8 <= inf.1 {
            let cid = UInt32(truncatingIfNeeded: u32(d, o)), sz = u32(d, o + 4), b = o + 8
            if cid == 0x3331_0004 { ents = (b, sz) } else if cid == 0x3331_0005 { plat = (b, sz) }
            o = b + sz
        }
        var pix: Int? = nil
        o = dat.0
        while o + 8 <= dat.1 {
            let cid = UInt32(truncatingIfNeeded: u32(d, o)), sz = u32(d, o + 4), b = o + 8
            if cid == 0x3332_0002 { pix = (b + 0x7F) & ~0x7F }
            o = b + sz
        }
        guard let es = ents, let px = pix else { return }
        for i in 0..<(es.1 / 0x7C) {
            let e = es.0 + i * 0x7C
            guard e + 0x7C <= d.count else { break }
            var nameBytes = Array(d[(e + 0x0C)..<(e + 0x24)])
            if let z = nameBytes.firstIndex(of: 0) { nameBytes = Array(nameBytes[..<z]) }
            let name = String(nameBytes.map { Character(Unicode.Scalar($0)) })      // latin-1
            let imgOff = u32(d, e + 0x30), palOff = u32(d, e + 0x34), palSize = u32(d, e + 0x3C), baseSize = u32(d, e + 0x40)
            let w = Int(d[e + 0x44]) | Int(d[e + 0x45]) << 8, h = Int(d[e + 0x46]) | Int(d[e + 0x47]) << 8
            let comp = d[e + 0x4A], mips = Int(d[e + 0x4E])
            var four: [UInt8] = []
            if let p = plat, p.1 >= (i + 1) * 0x20, p.0 + i * 0x20 + 0x18 <= d.count { four = Array(d[(p.0 + i * 0x20 + 0x14)..<(p.0 + i * 0x20 + 0x18)]) }
            let fourcc = String(bytes: four, encoding: .isoLatin1) ?? ""
            var fmt: TexFormat
            var lv0: ArraySlice<UInt8>
            var p8: [UInt8] = []
            var src: (Int, Int, Int)
            if let f = TexFormat(rawValue: fourcc), f != .argb, baseSize > 0, px + imgOff + baseSize <= d.count {
                fmt = f; lv0 = d[(px + imgOff)..<(px + imgOff + baseSize)]; src = (px + imgOff, baseSize, -1)
            } else if comp == 0x08 && palSize >= 1024 && px + imgOff + w * h <= d.count && px + palOff + 1024 <= d.count {
                // P8: the game expands it with its BGRA palette to A8R8G8B8 before the upload
                fmt = .argb
                p8 = [UInt8](repeating: 0, count: w * h * 4)
                for t in 0..<(w * h) {
                    let c = px + palOff + Int(d[px + imgOff + t]) * 4
                    p8[t * 4] = d[c]; p8[t * 4 + 1] = d[c + 1]; p8[t * 4 + 2] = d[c + 2]; p8[t * 4 + 3] = d[c + 3]
                }
                lv0 = p8[...]; src = (px + imgOff, w * h, px + palOff)
            } else { continue }
            let hash = lv0.withUnsafeBytes { XXH3.hash($0, seed: seed(w, h, fmt)) }
            found(GameTexture(hash: hash, name: name, file: rel, part: part(rel, name), w: w, h: h, fmt: fmt,
                              mips: max(1, mips), src: src))
        }
    }

    /// Textures the engine collected (runtime/texrep.m texture dump):
    /// <dir>/<part>/<w>x<h>_<fmt>_<hash>.dds and index.csv
    static func scanCollected(_ dirs: [URL]) -> [UInt64: GameTexture] {
        var out: [UInt64: GameTexture] = [:]
        let fm = FileManager.default
        for d in dirs {
            var meta: [String: [String: String]] = [:]
            if let s = try? String(contentsOf: d.appendingPathComponent("index.csv"), encoding: .utf8) {
                let lines = s.split(whereSeparator: \.isNewline).map(String.init)
                if let head = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
                    for l in lines.dropFirst() {
                        let v = l.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                        var r: [String: String] = [:]
                        for (k, x) in zip(head, v) { r[k] = x }
                        if let hx = r["hash"] { meta[hx] = r }
                    }
                }
            }
            guard let en = fm.enumerator(at: d, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { continue }
            for case let u as URL in en {
                let f = u.lastPathComponent
                let parts = f.split(separator: "_").map(String.init)
                guard f.hasSuffix(".dds"), parts.count == 3, let fmt = TexFormat(rawValue: parts[1]),
                      parts[2].count == 20, let hv = UInt64(parts[2].dropLast(4), radix: 16) else { continue }
                let wh = parts[0].split(separator: "x")
                guard wh.count == 2, let w = Int(wh[0]), let h = Int(wh[1]) else { continue }
                if (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { continue }
                var part = u.deletingLastPathComponent().lastPathComponent
                if !UpscalePack.parts.contains(part) { part = "other" }
                let hx = String(parts[2].dropLast(4))
                let r = meta[hx] ?? [:]
                if let s = r["source"], !s.isEmpty { part = Self.part(s, "") }
                out[hv] = GameTexture(hash: hv, name: "", file: r["source"] ?? "", part: part, w: w, h: h, fmt: fmt,
                                      mips: Int(r["levels"] ?? "") ?? 1, src: (0, 0, -1), dds: u)
            }
        }
        return out
    }

    static func level0(_ game: URL, _ e: GameTexture) throws -> [UInt8] {
        if let u = e.dds {
            let b = [UInt8](try Data(contentsOf: u))
            let n = e.fmt.levelSize(e.w, e.h)
            guard b.count >= 128 + n else { throw UpscaleFailure(message: "\(u.lastPathComponent) is cut short") }
            return Array(b[128..<(128 + n)])
        }
        let h = try FileHandle(forReadingFrom: game.appendingPathComponent(e.file))
        defer { try? h.close() }
        try h.seek(toOffset: UInt64(e.src.offset))
        let b = [UInt8](h.readData(ofLength: e.src.size))
        guard b.count == e.src.size else { throw UpscaleFailure(message: "\(e.file) is cut short") }
        if e.src.palette < 0 { return b }
        try h.seek(toOffset: UInt64(e.src.palette))
        let p = [UInt8](h.readData(ofLength: 1024))
        guard p.count == 1024 else { throw UpscaleFailure(message: "\(e.file) is cut short") }
        var o = [UInt8](repeating: 0, count: b.count * 4)
        for i in 0..<b.count { let c = Int(b[i]) * 4; o[i * 4] = p[c]; o[i * 4 + 1] = p[c + 1]; o[i * 4 + 2] = p[c + 2]; o[i * 4 + 3] = p[c + 3] }
        return o
    }
}

/// One build (or the completion of one): the launcher's Build button, and the test mode.
final class UpscaleBuilder {
    struct Summary { var made = 0, flat = 0, smooth = 0, failed = 0, kept = 0, textures = 0; var bytes: Int64 = 0; var seconds = 0.0 }
    static let maxSide = 2048
    static let smooth = 7.0

    let game: URL, out: URL, collected: [URL], scale: Int, model: URL
    var limit: Int? = nil
    var only: Set<UInt64>? = nil          // tests: just these textures
    var log: (String) -> Void = { _ in }
    var rawLevels: URL? = nil             // tests: the levels before block encoding, <hash>_<i>.rgba

    init(game: URL, out: URL, collected: [URL], scale: Int, model: URL) {
        self.game = game; self.out = out; self.collected = collected; self.scale = scale; self.model = model
    }

    /// 4 with 16 GB of memory or more, otherwise 2
    static var autoScale: Int { ProcessInfo.processInfo.physicalMemory >= 15 << 30 ? 4 : 2 }

    static func texScale(_ e: GameTexture, _ scale: Int) -> Int {
        var s = scale
        while s > 1 && max(e.w, e.h) * s > maxSide { s /= 2 }
        return s
    }
    static func eligible(_ e: GameTexture, _ scale: Int) -> String? {
        if e.w < 16 || e.h < 16 || e.w * e.h <= 1024 { return "small" }
        if texScale(e, scale) < 2 { return "large" }
        if e.part == "cars" && (e.fmt == .argb || e.file.uppercased().contains("VINYLS")) { return "carskin" }
        if e.name.uppercased().hasPrefix("ANM_") { return "animated" }
        return nil
    }
    static func fileName(_ e: GameTexture) -> String {
        let nm: String
        if e.name.isEmpty { nm = e.fmt.rawValue }
        else {
            nm = String(String(e.name.unicodeScalars.map { s -> Character in
                let c = Character(s)
                return (s.isASCII && (c.isLetter || c.isNumber)) || c == "_" || c == "-" ? c : "_"
            }).prefix(40))
        }
        return "\(nm)_\(e.w)x\(e.h)_\(String(format: "%016llx", e.hash)).dds"
    }

    /// progress: (what, fraction)
    func build(progress: @escaping (String, Double?) -> Void, cancelled: @escaping () -> Bool) throws -> Summary {
        let fm = FileManager.default
        var sum = Summary()
        let t0 = Date()
        progress("Reading the game's textures…", nil)
        var (ents, nfiles) = TextureScan.scan(game: game, cancelled: cancelled)
        log("game \(game.path): \(ents.count) textures in \(nfiles) files")
        let dirs = collected.filter { fm.fileExists(atPath: $0.path) }
        if !dirs.isEmpty {
            let dd = TextureScan.scanCollected(dirs)
            var new = 0
            for (h, e) in dd where ents[h] == nil { ents[h] = e; new += 1 }
            log("collected \(dirs.map { $0.path }.joined(separator: ", ")): \(dd.count) textures, \(new) not in the game's uncompressed files")
        }
        if cancelled() { throw UpscaleFailure(message: "Stopped.") }
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        // the pack holds one scale; another one starts it again
        let ini = out.appendingPathComponent("pack.ini")
        if let s = try? String(contentsOf: ini, encoding: .utf8), !s.contains("\nscale = \(scale)\n") {
            for p in UpscalePack.parts { try? fm.removeItem(at: out.appendingPathComponent(p)) }
            try? fm.removeItem(at: ini)
        }
        let key: (GameTexture) -> [[UInt8]] = { [Array($0.part.utf8), Array($0.file.utf8), Array($0.name.utf8)] }
        let sorted = ents.values.sorted { a, b in
            let ka = key(a), kb = key(b)
            for i in 0..<3 where ka[i] != kb[i] { return ka[i].lexicographicallyPrecedes(kb[i]) }
            return a.hash < b.hash
        }
        var todo: [(GameTexture, URL)] = [], plan: [(GameTexture, URL)] = [], skipped: [String: Int] = [:]
        for e in sorted {
            if let o = only, !o.contains(e.hash) { continue }
            if let why = Self.eligible(e, scale) { skipped[why, default: 0] += 1; continue }
            let u = out.appendingPathComponent(e.part).appendingPathComponent(Self.fileName(e))
            plan.append((e, u))
            if fm.fileExists(atPath: u.path) { sum.kept += 1; continue }
            todo.append((e, u))
        }
        if let l = limit { todo = Array(todo.prefix(l)) }
        // the same sizes one after the other: the model's GPU graph is made once per size
        todo.sort { ($0.0.h, $0.0.w, $0.0.hash) < ($1.0.h, $1.0.w, $1.0.hash) }
        let mpix = Double(todo.reduce(0) { $0 + $1.0.w * $1.0.h }) / 1e6
        log("pack \(out.path): \(scale)x; \(todo.count) textures to look at (\(String(format: "%.1f", mpix)) Mpix), \(sum.kept) already there; skipped: "
            + skipped.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
        for p in UpscalePack.parts { try fm.createDirectory(at: out.appendingPathComponent(p), withIntermediateDirectories: true) }

        var up: SPANUpscaler? = nil
        if !todo.isEmpty {
            progress("Loading the model…", nil)
            try UpscaleStore.checkModel(model)
            up = try SPANUpscaler(weights: TorchWeights(file: model))
            log("model \(UpscalePack.modelFile) (\(up!.name))")
        }
        // the GPU works through the textures in order; the CPU finishes them alongside
        let lock = NSLock()
        let group = DispatchGroup()
        let jobs = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
        let slots = DispatchSemaphore(value: 2 * jobs)
        // and at most this much memory in the textures being finished (about 100 bytes a
        // texel of the 4x picture): a 1024 x 1024 texture alone needs some 1.6 GB
        let gate = MemoryGate(limit: max(512 << 20, Int(ProcessInfo.processInfo.physicalMemory / 16)))
        let workers = DispatchQueue(label: "nfsu2.upscale.finish", qos: .userInitiated, attributes: .concurrent)
        var pxDone = 0.0
        var firstError: String? = nil
        var made = 0, wfailed = 0, wbytes: Int64 = 0                 // the workers' (under lock)
        for (i, (e, u)) in todo.enumerated() {
            if cancelled() { break }
            let orig: RGBA
            do { orig = TexImage.decode(try TextureScan.level0(game, e), e.w, e.h, e.fmt) }
            catch { sum.failed += 1; log("  cannot read \(e.name.isEmpty ? String(format: "%016llx", e.hash) : e.name): \(error)"); continue }
            var rgb = [UInt8](repeating: 0, count: e.w * e.h * 3)
            var lo: UInt8 = 255, hi: UInt8 = 0
            for t in 0..<(e.w * e.h) { for k in 0..<3 { let v = orig.px[t * 4 + k]; rgb[t * 3 + k] = v; lo = min(lo, v); hi = max(hi, v) } }
            if Int(hi) - Int(lo) <= 2 { sum.flat += 1; continue }                          // one colour
            if TexImage.smoothness(rgb, e.h, e.w) < Self.smooth { sum.smooth += 1; continue }   // sky, glow
            let modes = TexImage.padModes(rgb, e.h, e.w)
            let p = 16
            let padded = TexImage.pad(rgb, e.h, e.w, 3, p, modes)
            let big: [Float]
            do { big = try up!.upscale(padded, e.h + 2 * p, e.w + 2 * p) }
            catch { throw UpscaleFailure(message: (error as? ModelFailure)?.message ?? "\(error)") }
            // the texture's own part of the padded result
            let PW = (e.w + 2 * p) * 4, W = e.w * 4, H = e.h * 4
            var crop = [Float](repeating: 0, count: W * H * 3)
            big.withUnsafeBufferPointer { b in crop.withUnsafeMutableBufferPointer { c in
                for y in 0..<H { let s = ((y + p * 4) * PW + p * 4) * 3; for x in 0..<(W * 3) { c[y * W * 3 + x] = b[s + x] } }
            } }
            let cost = W * H * 100
            slots.wait()
            gate.take(cost)
            group.enter()
            let sc = Self.texScale(e, scale)
            workers.async {
                defer { gate.give(cost); slots.signal(); group.leave() }
                let lv = TexImage.levels(orig: orig, up: crop, fmt: e.fmt, scale: sc, modes: modes)
                if let r = self.rawLevels {
                    for (k, l) in lv.enumerated() { try? Data(l.px).write(to: r.appendingPathComponent(String(format: "%016llx_%d.rgba", e.hash, k))) }
                }
                let data = TexImage.dds(e.w * sc, e.h * sc, e.fmt, lv.map { TexImage.encode($0, e.fmt) })
                let tmp = u.appendingPathExtension("tmp")
                do {
                    try data.write(to: tmp)
                    _ = try? fm.removeItem(at: u)
                    try fm.moveItem(at: tmp, to: u)
                    lock.lock(); made += 1; wbytes += Int64(data.count); lock.unlock()
                } catch {
                    lock.lock(); wfailed += 1; if firstError == nil { firstError = "\(u.lastPathComponent): \(error.localizedDescription)" }; lock.unlock()
                }
            }
            pxDone += Double(e.w * e.h) / 1e6
            let el = Date().timeIntervalSince(t0)
            let rate = pxDone / max(el, 1e-6)
            let left = (mpix - pxDone) / max(rate, 1e-6)
            progress("Upscaling \(i + 1) of \(todo.count)… about \(left < 90 ? "\(Int(left.rounded())) s" : "\(Int((left / 60).rounded())) min") left",
                     mpix > 0 ? pxDone / mpix : nil)
            if (i + 1) % 100 == 0 || i + 1 == todo.count {
                log(String(format: "  %d/%d  %6.0f s  %.2f Mpix/s", i + 1, todo.count, el, rate))
            }
        }
        group.wait()
        sum.made = made; sum.failed += wfailed; _ = wbytes
        if let f = firstError { log("  failed: \(f)") }
        // a texture this build placed elsewhere leaves no stale copy; other files (hand-made) stay
        var want: [UInt64: String] = [:]
        for (e, u) in plan { want[e.hash] = u.standardizedFileURL.path }
        var count = 0, total: Int64 = 0
        if let en = fm.enumerator(at: out, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in en where u.pathExtension == "dds" {
                let f = u.deletingPathExtension().lastPathComponent
                if let r = f.range(of: "_", options: .backwards), let h = UInt64(f[r.upperBound...], radix: 16), f[r.upperBound...].count == 16,
                   let w = want[h], w != u.standardizedFileURL.path, fm.fileExists(atPath: w) {
                    try? fm.removeItem(at: u); continue
                }
                count += 1
                total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        var man = "hash,name,part,source,w,h,fmt,scale,model,file\n"
        for (e, u) in plan where fm.fileExists(atPath: u.path) {
            man += "\(String(format: "%016llx", e.hash)),\(e.name),\(e.part),\(e.file),\(e.w),\(e.h),\(e.fmt.rawValue),\(Self.texScale(e, scale)),span,\(e.part)/\(u.lastPathComponent)\n"
        }
        try man.write(to: out.appendingPathComponent("manifest.csv"), atomically: true, encoding: .utf8)
        let stamp = ISO8601DateFormatter().string(from: Date())
        try ("# NFSU2 texture pack (made by the launcher, UpscaleBuilder.swift)\nformat = 1\ntool = launcher 1.0\nmodel = span\n"
             + "model_file = \(UpscalePack.modelFile)\nmodel_licence = \(UpscalePack.modelLicence)\n"
             + "scale = \(scale)\ntextures = \(count)\nbytes = \(total)\nbuilt = \(stamp)\n")
            .write(to: ini, atomically: true, encoding: .utf8)
        sum.textures = count; sum.bytes = total; sum.seconds = Date().timeIntervalSince(t0)
        log("done: \(sum.made) made, \(sum.flat) single-colour and \(sum.smooth) smooth skipped, \(sum.failed) failed, in \(Int(sum.seconds)) s; "
            + "pack \(count) textures, \(total >> 20) MB at \(out.path)")
        if cancelled() { throw UpscaleFailure(message: "Stopped. The \(count) textures made so far are kept; Build goes on from there.") }
        return sum
    }
}

/// Waits until the work in hand leaves room for cost bytes (one piece always goes).
final class MemoryGate {
    private let cond = NSCondition()
    private var used = 0
    let limit: Int
    init(limit: Int) { self.limit = limit }
    func take(_ cost: Int) {
        cond.lock()
        while used > 0 && used + cost > limit { cond.wait() }
        used += cost
        cond.unlock()
    }
    func give(_ cost: Int) { cond.lock(); used -= cost; cond.broadcast(); cond.unlock() }
}
