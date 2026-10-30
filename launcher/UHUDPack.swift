// The UHUD texture pack: LunicAura106's "Upscaled HUD" mod (nfsmods.xyz/mod/4319),
// the menus, HUD, fonts, icons and logos redrawn at four times their size, made
// into one file the engine reads (runtime/uhud.m).  After th0mk's nfsu2-web
// tools/texpacks.py, which writes the same file.
//
// The mod is not part of this app.  The launcher's Download button fetches its
// archive (NFSU2UHUD11192022a.7z) from the mod's own page on nfsmods.xyz, only when
// the player clicks it, and checks it against the release this was made for
// (SHA-256); Add File... takes a copy the player already has.  The mod's installer
// writes its textures into the game's own files; this leaves the game folder as it is.
// For each of the mod's textures it finds the game's texture of the same name in
// the game's bundles and keys the mod's one by what the game uploads for that
// texture: CRC-32 and Adler-32 of level 0, its size and its format.
//
// Pack layout (little-endian):
//   header   "NTXP", version 1, entry count, 0
//   entries  40 bytes each, sorted by (crc, adler):
//            crc, adler, ow, oh (u16), ofmt   the game's texture: CRC-32 and Adler-32 of
//                                             level 0 as uploaded, its size, its D3DFORMAT
//            w, h (u16), fmt, levels          the replacement
//            off, size                        its levels, level 0 first (DXT: rows of 4x4 blocks)
//            name                             file offset of its name (for the log)
//   the names, then the levels, in the order of the game files and textures they replace
import Foundation
import CryptoKit

enum UHUDPack {
    struct Failure: Error { let message: String }
    struct Summary { let textures: Int; let shared: Int; let bytes: Int; let skipped: [String] }

    // The release this was tested with (19 Nov 2022); another file is not used.
    static let archive = URL(string: "https://nfsmods.xyz/uploads/mods/4319/e17d26-NFSU2UHUD11192022a.7z")!
    static let archiveSize: Int64 = 2_818_583
    static let archiveSHA256 = "28a71f5bc166110d827c4c2d1e95ce7cddaf138a497a353e3f33eeeb28d9dadd"

    /// Downloads the mod's archive (progress: bytes so far), checks it and makes the pack.
    static func download(game: URL, to dest: URL, progress: @escaping (Int64) -> Void) throws -> Summary {
        let file = try Downloader(progress: progress).fetch(archive)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try Data(contentsOf: file)
        let sum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard sum == archiveSHA256 else {
            throw Failure(message: "The file on nfsmods.xyz is not the release this was made for. Download the mod from its page yourself and use Add File….")
        }
        return try make(mod: file, game: game, to: dest)
    }

    /// One download into a temporary .7z, waiting for it (call it off the main thread).
    final class Downloader: NSObject, URLSessionDownloadDelegate {
        private let progress: (Int64) -> Void
        private let done = DispatchSemaphore(value: 0)
        private var file: URL?
        private var failure: Error?
        init(progress: @escaping (Int64) -> Void) { self.progress = progress }

        func fetch(_ url: URL) throws -> URL {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 30
            let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            s.downloadTask(with: url).resume()
            done.wait()
            s.finishTasksAndInvalidate()
            if let f = file { return f }
            throw Failure(message: "The mod could not be downloaded (\((failure as? Failure)?.message ?? failure?.localizedDescription ?? "no answer from nfsmods.xyz")). Try again later, or download it from its page and use Add File….")
        }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
            progress(totalBytesWritten)
        }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
                failure = Failure(message: "HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)"); return
            }
            // the system removes location when this returns
            let f = FileManager.default.temporaryDirectory.appendingPathComponent("nfsu2-uhud-\(UUID().uuidString).7z")
            do { try FileManager.default.moveItem(at: location, to: f); file = f } catch { failure = error }
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let e = error { failure = e }
            done.signal()
        }
    }

    // UHUD's folders (under assets/) and the game files whose textures they replace, as its
    // install.end binds them.  The per-HUD files hold compressed copies of
    // HUD_CustomTextures_ALL.bin's textures, some in EA's HUFF, which this does not read: those
    // are keyed from _ALL's copy (the JDLZ ones are the same bytes).
    static let folders: [(String, [String])] = [
        ("FRONTB/FRONTENDTEXTURES", ["FRONTEND/FrontB.lzc"]),
        ("GLOBALA", ["GLOBAL/GLOBALA.BUN"]),
        ("GLOBALB/GLOBALTEXTURES", ["GLOBAL/GlobalB.lzc"]),
        ("GLOBALB/GLOBALTEXTURESPC", ["GLOBAL/GlobalB.lzc"]),
        ("LANGUAGETEXTURES", ["LANGUAGES/LanguageTextures.bin"]),
        ("INGAMECOMMON/INGAMETEXTURES", ["GLOBAL/InGameCommon.lzc"]),
        ("INGAMECOMMON/HUDTEXTURESGLOBAL", ["GLOBAL/InGameCommon.lzc"]),
        ("INGAMERACE", ["GLOBAL/InGameRace.bun"]),
        ("INGAMEDRIFT", ["GLOBAL/InGameDrift.bun"]),
        ("INGAMEDRAG", ["GLOBAL/InGameDrag.bun"]),
        ("INGAMEFREEROAM", ["GLOBAL/InGameFreeRoam.bun"]),
        ("HUD_CUSTOMTEXTURES_ALL", ["GLOBAL/HUD_CustomTextures_ALL.bin"]),
    ] + (0..<11).map { i in
        let n = String(format: "%02d", i)
        return ("HUD_CUSTOMTEXTURES_\(n)", ["GLOBAL/HUD_CustomTextures_\(n).bin", "GLOBAL/HUD_CustomTextures_ALL.bin"])
    }

    // D3DFORMATs
    static let argb: UInt32 = 21, p8: UInt32 = 41
    static let dxt1: UInt32 = 0x3154_5844, dxt3: UInt32 = 0x3354_5844, dxt5: UInt32 = 0x3554_5844

    // MARK: making the pack

    /// The pack from the mod (its .7z, or the folder it was extracted to) and the game folder.
    static func make(mod: URL, game: URL, to dest: URL) throws -> Summary {
        let fm = FileManager.default
        var temp: URL? = nil
        defer { if let t = temp { try? fm.removeItem(at: t) } }
        var root = mod
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: mod.path, isDirectory: &isDir), !isDir.boolValue {
            let t = fm.temporaryDirectory.appendingPathComponent("nfsu2-uhud-\(UUID().uuidString)")
            try fm.createDirectory(at: t, withIntermediateDirectories: true)
            temp = t
            // bsdtar (libarchive) reads 7-Zip archives
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = ["-xf", mod.path, "-C", t.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw Failure(message: "\(mod.lastPathComponent) could not be unpacked. Choose the mod's .7z file as downloaded, or the folder it was extracted to.") }
            root = t
        }
        guard let assets = findAssets(root, depth: 0) else {
            throw Failure(message: "\(mod.lastPathComponent) is not the Upscaled HUD mod: it has no assets/FRONTB/FRONTENDTEXTURES folder.")
        }
        return try build(assets: assets, game: game, to: dest)
    }

    /// The folder with UHUD's texture folders: <dir>/assets or <dir>, also a few levels down.
    static func findAssets(_ dir: URL, depth: Int) -> URL? {
        for d in [dir.appendingPathComponent("assets"), dir] where isDirectory(d.appendingPathComponent("FRONTB/FRONTENDTEXTURES")) {
            return d
        }
        guard depth < 3, let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for i in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where isDirectory(i) {
            if let a = findAssets(i, depth: depth + 1) { return a }
        }
        return nil
    }

    static func isDirectory(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    /// rel under root, each part matched case-insensitively
    static func find(_ root: URL, _ rel: String) -> URL? {
        var cur = root
        for part in rel.split(separator: "/").map(String.init) {
            guard isDirectory(cur), let names = try? FileManager.default.contentsOfDirectory(atPath: cur.path),
                  let hit = names.first(where: { $0.lowercased() == part.lowercased() }) else { return nil }
            cur = cur.appendingPathComponent(hit)
        }
        return cur
    }

    struct GameTex { let index: Int; let w: Int; let h: Int; let fmt: UInt32; let level0: [UInt8]? }
    struct Entry { let crc: UInt32; let adler: UInt32; let ow, oh: Int; let ofmt: UInt32
                   let w, h: Int; let fmt: UInt32; let levels: Int; let off: Int; let size: Int; let name: String }

    static func build(assets: URL, game: URL, to dest: URL) throws -> Summary {
        var bundles: [String: [UInt32: GameTex]] = [:]
        var entries: [UInt64: Entry] = [:]
        var data = [UInt8]()
        var dataAt: [[UInt8]: Int] = [:]
        var shared = 0
        var skipped = [String]()
        for (folder, files) in folders {
            let src = assets.appendingPathComponent(folder)
            guard isDirectory(src) else { continue }
            var texs = [[UInt32: GameTex]]()
            for rel in files {
                if bundles[rel] == nil {
                    guard let p = find(game, rel) else { throw Failure(message: "The game folder has no \(rel).") }
                    var d = [UInt8](try Data(contentsOf: p))
                    if d.starts(with: Array("JDLZ".utf8)) { d = try jdlz(d) }
                    var byName = [UInt32: GameTex]()
                    for (i, t) in try textures(d).enumerated() {
                        byName[t.0] = GameTex(index: i, w: t.1, h: t.2, fmt: t.3, level0: t.4)
                    }
                    bundles[rel] = byName
                }
                texs.append(bundles[rel]!)
            }
            var todo = [(Int, String, GameTex)]()
            for fn in (try? FileManager.default.contentsOfDirectory(atPath: src.path)) ?? [] where fn.lowercased().hasSuffix(".dds") {
                let name = String(fn.dropLast(4))
                let nh = stringHash(name.uppercased())
                guard let t = texs.lazy.compactMap({ $0[nh] }).first(where: { $0.level0 != nil }) else {
                    skipped.append("\(folder)/\(name)"); continue
                }
                todo.append((t.index, name, t))
            }
            todo.sort { $0.0 != $1.0 ? $0.0 < $1.0 : Array($0.1.utf8).lexicographicallyPrecedes(Array($1.1.utf8)) }
            for (_, name, t) in todo {
                let label = "\(folder)/\(name)"
                guard let r = dds(src.appendingPathComponent(name + ".dds")),
                      r.w * t.h == r.h * t.w, r.w >= t.w, let lv0 = t.level0 else { skipped.append(label); continue }
                let crc = crc32(lv0), adler = adler32(lv0)
                let key = UInt64(crc) << 32 | UInt64(adler)
                if let e = entries[key] {
                    if Array(data[e.off..<e.off + e.size]) == r.levels && (e.w, e.h, e.fmt) == (r.w, r.h, r.fmt) { shared += 1 }
                    else { skipped.append(label) }
                    continue
                }
                if dataAt[r.levels] == nil {
                    dataAt[r.levels] = data.count
                    data += r.levels
                    data += [UInt8](repeating: 0, count: (16 - data.count % 16) % 16)
                }
                entries[key] = Entry(crc: crc, adler: adler, ow: t.w, oh: t.h, ofmt: t.fmt, w: r.w, h: r.h, fmt: r.fmt,
                                     levels: r.count, off: dataAt[r.levels]!, size: r.levels.count, name: label)
            }
        }
        guard !entries.isEmpty else { throw Failure(message: "None of the mod's textures matched the game's files.") }
        try write(dest, entries.keys.sorted().map { entries[$0]! }, data)
        return Summary(textures: entries.count, shared: shared, bytes: data.count, skipped: skipped)
    }

    static func write(_ dest: URL, _ order: [Entry], _ data: [UInt8]) throws {
        var names = [UInt8]()
        let at = 16 + 40 * order.count
        var nameAt = [Int]()
        for e in order { nameAt.append(at + names.count); names += Array(e.name.utf8) + [0] }
        let base = (at + names.count + 4095) & ~4095
        var out = [UInt8]()
        out.reserveCapacity(base + data.count)
        func u32(_ v: Int) { out += withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian, Array.init) }
        func u16(_ v: Int) { out += withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian, Array.init) }
        out += Array("NTXP".utf8); u32(1); u32(order.count); u32(0)
        for (i, e) in order.enumerated() {
            u32(Int(e.crc)); u32(Int(e.adler)); u16(e.ow); u16(e.oh); u32(Int(e.ofmt))
            u16(e.w); u16(e.h); u32(Int(e.fmt)); u32(e.levels); u32(base + e.off); u32(e.size); u32(nameAt[i])
        }
        out += names
        out += [UInt8](repeating: 0, count: base - out.count)
        out += data
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = dest.appendingPathExtension("part")
        try Data(out).write(to: part)
        guard rename(part.path, dest.path) == 0 else {
            try? FileManager.default.removeItem(at: part)
            throw Failure(message: "\(dest.path) could not be written.")
        }
    }

    // MARK: the game's bundles

    static func u32(_ d: [UInt8], _ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= d.count else { return 0 }
        return UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
    }
    static func u16(_ d: [UInt8], _ o: Int) -> Int { o >= 0 && o + 2 <= d.count ? Int(d[o]) | Int(d[o + 1]) << 8 : 0 }
    static func slice(_ d: [UInt8], _ a: Int, _ b: Int) -> [UInt8] {
        let lo = max(0, min(a, d.count)), hi = max(lo, min(b, d.count))
        return Array(d[lo..<hi])
    }

    /// EA's JDLZ: the .lzc bundles and compressed textures
    static func jdlz(_ b: [UInt8]) throws -> [UInt8] {
        let n = Int(u32(b, 8))
        var out = [UInt8](repeating: 0, count: n)
        var i = 16, o = 0, f1 = 1, f2 = 1
        while i < b.count && o < n {
            if f1 == 1 { f1 = Int(b[i]) | 0x100; i += 1 }
            if f2 == 1 { f2 = Int(b[i]) | 0x100; i += 1 }
            if f1 & 1 != 0 {
                guard i + 1 < b.count else { break }
                let ln: Int, t: Int
                if f2 & 1 != 0 { ln = (Int(b[i + 1]) | (Int(b[i]) & 0xF0) << 4) + 3; t = (Int(b[i]) & 0x0F) + 1 }
                else { t = (Int(b[i + 1]) | (Int(b[i]) & 0xE0) << 3) + 17; ln = (Int(b[i]) & 0x1F) + 3 }
                i += 2
                guard o - t >= 0, o + ln <= n else { throw Failure(message: "A game file is damaged (JDLZ).") }
                for k in 0..<ln { out[o + k] = out[o + k - t] }
                o += ln; f2 >>= 1
            } else {
                out[o] = b[i]; o += 1; i += 1
            }
            f1 >>= 1
        }
        guard o == n else { throw Failure(message: "A game file is damaged (JDLZ: \(o) of \(n) bytes).") }
        return out
    }

    static func chunks(_ d: [UInt8], _ start: Int, _ end: Int) -> [(UInt32, Int, Int)] {
        var r = [(UInt32, Int, Int)](), off = start
        while off + 8 <= end {
            let cid = u32(d, off), sz = Int(u32(d, off + 4))
            if sz > end - off - 8 { break }
            r.append((cid, off + 8, off + 8 + sz))
            off += 8 + sz
        }
        return r
    }

    static func tpks(_ d: [UInt8], _ start: Int, _ end: Int, _ depth: Int = 0) -> [(Int, Int)] {
        var r = [(Int, Int)]()
        for (cid, b, e) in chunks(d, start, end) {
            if cid == 0xB330_0000 { r.append((b, e)) }
            else if cid & 0x8000_0000 != 0 && depth < 6 { r += tpks(d, b, e, depth + 1) }
        }
        return r
    }

    static func levelSize(_ w: Int, _ h: Int, _ fmt: UInt32) -> Int {
        switch fmt {
        case dxt1: return max(1, (w + 3) / 4) * max(1, (h + 3) / 4) * 8
        case dxt3, dxt5: return max(1, (w + 3) / 4) * max(1, (h + 3) / 4) * 16
        default: return w * h * 4
        }
    }

    typealias Tex = (UInt32, Int, Int, UInt32, [UInt8]?)    // name hash, w, h, D3DFORMAT, level 0 as uploaded

    static func texture(_ ti: [UInt8], _ pf: [UInt8], _ buf: [UInt8], _ base: Int) -> Tex {
        let nh = u32(ti, 0x24)
        let imgOff = Int(u32(ti, 0x30)), palOff = Int(u32(ti, 0x34)), palSize = Int(u32(ti, 0x3C))
        let w = u16(ti, 0x44), h = u16(ti, 0x46)
        let code = pf.count >= 0x18 ? u32(pf, 0x14) : 0
        let p = base + imgOff
        var fmt: UInt32, lv0: [UInt8]
        if [dxt1, dxt3, dxt5].contains(code) {
            fmt = code; lv0 = slice(buf, p, p + levelSize(w, h, fmt))
        } else if code == argb {
            fmt = argb; lv0 = slice(buf, p, p + w * h * 4)
        } else if code == p8 && palSize >= 1024 {
            // the game expands it with its palette (BGRA, as A8R8G8B8 is in memory) before the upload
            fmt = argb
            let ix = slice(buf, p, p + w * h), pal = slice(buf, base + palOff, base + palOff + 1024)
            guard ix.count == w * h, pal.count == 1024 else { return (nh, w, h, fmt, nil) }
            lv0 = [UInt8](repeating: 0, count: w * h * 4)
            for (k, v) in ix.enumerated() { for c in 0..<4 { lv0[k * 4 + c] = pal[Int(v) * 4 + c] } }
        } else {
            return (nh, w, h, code, nil)
        }
        return (nh, w, h, fmt, lv0.count == levelSize(w, h, fmt) ? lv0 : nil)
    }

    /// the textures of a bundle's TPKs, in their order
    static func textures(_ d: [UInt8]) throws -> [Tex] {
        var r = [Tex]()
        for (b, e) in tpks(d, 0, d.count) {
            var info: (Int, Int)? = nil, dat: (Int, Int)? = nil
            for (cid, cb, ce) in chunks(d, b, e) {
                if cid == 0xB331_0000 { info = (cb, ce) } else if cid == 0xB332_0000 { dat = (cb, ce) }
            }
            guard let inf = info, let da = dat else { continue }
            var part = [UInt32: (Int, Int)]()
            for (cid, cb, ce) in chunks(d, inf.0, inf.1) { part[cid] = (cb, ce) }
            let pix = chunks(d, da.0, da.1).first(where: { $0.0 == 0x3332_0002 }).map { ($0.1 + 0x7F) & ~0x7F }
            if let (tb, te) = part[0x3331_0004], let pix = pix {
                let pl = part[0x3331_0005] ?? (0, 0)
                for i in 0..<((te - tb) / 0x7C) {
                    let pf = pl.0 + (i + 1) * 0x20 <= pl.1 ? slice(d, pl.0 + i * 0x20, pl.0 + (i + 1) * 0x20) : []
                    r.append(texture(slice(d, tb + i * 0x7C, tb + (i + 1) * 0x7C), pf, d, pix))
                }
            } else if let (cb, ce) = part[0x3331_0003] {
                // compressed textures: each one's data, then its TextureInfo (0x7C) and platform info (0x20)
                for i in 0..<((ce - cb) / 24) {
                    let nh = u32(d, cb + i * 24), off = Int(u32(d, cb + i * 24 + 4)), size = Int(u32(d, cb + i * 24 + 8))
                    let blob = slice(d, off, off + size)
                    guard blob.starts(with: Array("JDLZ".utf8)) else { r.append((nh, 0, 0, 0, nil)); continue }
                    let out = try jdlz(blob)
                    guard out.count >= 0x9C else { r.append((nh, 0, 0, 0, nil)); continue }
                    let ti = Array(out[(out.count - 0x9C)..<(out.count - 0x20)])
                    r.append(texture(ti, Array(out[(out.count - 0x20)...]), out, -Int(u32(ti, 0x30))))
                }
            }
        }
        return r
    }

    /// the game's name hash (bStringHash)
    static func stringHash(_ s: String) -> UInt32 {
        var h: UInt32 = 0xFFFF_FFFF
        for c in s.unicodeScalars { h = h &* 33 &+ UInt32(c.value & 0xFF) }
        return h
    }

    /// a DDS file's size, D3DFORMAT and levels; nil if this cannot use it
    static func dds(_ url: URL) -> (w: Int, h: Int, fmt: UInt32, count: Int, levels: [UInt8])? {
        guard let b = try? [UInt8](Data(contentsOf: url)), b.count >= 128, b.starts(with: Array("DDS ".utf8)) else { return nil }
        let h = Int(u32(b, 12)), w = Int(u32(b, 16))
        let mips = max(1, Int(u32(b, 28)))
        let flags = u32(b, 80), four = u32(b, 84), bits = u32(b, 88)
        var fmt: UInt32? = nil
        if flags & 4 != 0 { fmt = [dxt1, dxt3, dxt5].contains(four) ? four : nil }
        else if bits == 32 && (u32(b, 92), u32(b, 96), u32(b, 100), u32(b, 104)) == (0xFF0000, 0xFF00, 0xFF, 0xFF00_0000) { fmt = argb }
        guard let f = fmt, w > 0, h > 0 else { return nil }
        var n = 0, lv = 0
        while lv < mips && 128 + n + levelSize(max(1, w >> lv), max(1, h >> lv), f) <= b.count {
            n += levelSize(max(1, w >> lv), max(1, h >> lv), f); lv += 1
        }
        return lv > 0 ? (w, h, f, lv, Array(b[128..<(128 + n)])) : nil
    }

    // MARK: checksums (zlib's)

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ d: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
    static func adler32(_ d: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        var i = 0
        while i < d.count {
            let end = min(d.count, i + 5552)
            while i < end { a += UInt32(d[i]); b += a; i += 1 }
            a %= 65521; b %= 65521
        }
        return b << 16 | a
    }
}
