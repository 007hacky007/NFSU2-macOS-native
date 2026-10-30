// Making an NTXP texture pack (runtime/texpack.h) from a community texture mod, so the
// engine draws the mod's textures in place of the game's (runtime/texrep.m) and the
// game folder stays as it is.  Three kinds of mod, found anywhere in what the player
// downloaded (an archive, a folder or a single file):
//
//   TexMod packs (.tpf)  a ZIP, its bytes XOR'd with 0x3FA43FA4 and its files encrypted
//                        with TexMod's fixed password; texmod.def maps TexMod's hash of a
//                        texture (CRC-32 of level 0 as the game uploads it, without the
//                        final inversion) to a DDS or an image.  Also loose files named
//                        <exe>_0x<hash>.dds the way TexMod and uMod save them.  TexMod
//                        makes the lower mip levels when the file has only the first
//                        (D3DX's default); so does this.
//   TexWizard packs      a folder with textures.bin (a TPK, the game's own texture format)
//                        and meta.json, whose "textures" pairs say which of the game's
//                        textures (by name) shows which of the pack's.  Without meta.json
//                        each texture replaces the game's one of the same name.
//   texture files        mods that replace the game's own files (FrontB.lzc, GlobalB.lzc,
//                        ...).  For each texture that differs from the game's file of the
//                        same path, the pack keys the mod's by the game's texture's content
//                        (or by its name when the game's copy is compressed in a way this
//                        does not read).  Everything else in those files (menus, models,
//                        text) is not used.
//
// Payloads are DXT1/3/5 or A8R8G8B8 (as BGRA in memory), level 0 first.
import Foundation
import CryptoKit
import Compression
import ImageIO
import CoreGraphics

enum PackBuilder {
    typealias Failure = UHUDPack.Failure
    static let dxt1 = UHUDPack.dxt1, dxt3 = UHUDPack.dxt3, dxt5 = UHUDPack.dxt5, argb = UHUDPack.argb

    struct Summary { var textures = 0; var bytes: Int64 = 0; var texmod = 0; var named = 0; var content = 0
                     var sources = [String](); var skipped = [String]() }

    /// A texture: all its levels, level 0 first (DXT: rows of 4x4 blocks; A8R8G8B8: BGRA).
    struct Tex { let w: Int; let h: Int; let fmt: UInt32; let levels: Int; let data: [UInt8] }

    enum Key: Hashable {
        case content(crc: UInt32, adler: UInt32, w: Int, h: Int, fmt: UInt32)
        case texmod(UInt32)
        case name(UInt32)
    }

    // MARK: the pack file

    /// Collects the entries; the levels go to a temporary file as they come.
    final class Writer {
        struct Entry { let key: Key; let w, h: Int; let fmt: UInt32; let levels: Int; let off: Int; let size: Int; let label: String }
        private let tmp: URL
        private let fh: FileHandle
        private var size = 0
        private(set) var entries = [Entry]()
        private var keys = Set<Key>()
        private var same = [SHA256.Digest: Int]()       // identical levels are stored once
        init() throws {
            tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nfsu2-texpack-\(UUID().uuidString).levels")
            guard FileManager.default.createFile(atPath: tmp.path, contents: nil), let h = FileHandle(forWritingAtPath: tmp.path)
            else { throw Failure(message: "No room for a temporary file in \(tmp.deletingLastPathComponent().path).") }
            fh = h
        }
        deinit { try? fh.close(); try? FileManager.default.removeItem(at: tmp) }
        func has(_ k: Key) -> Bool { keys.contains(k) }
        var bytes: Int { size }
        /// false: an earlier source already replaces this texture
        @discardableResult
        func add(_ key: Key, _ t: Tex, _ label: String) throws -> Bool {
            guard !keys.contains(key) else { return false }
            guard entries.count < 65536 else { throw Failure(message: "The mod has more than 65536 textures.") }
            let digest = SHA256.hash(data: t.data)
            var off = same[digest] ?? -1
            if off < 0 {
                off = size
                var d = t.data
                d += [UInt8](repeating: 0, count: (16 - d.count % 16) % 16)
                fh.write(Data(d))
                size += d.count
                same[digest] = off
                guard size < 0xF000_0000 else { throw Failure(message: "The mod's textures are larger than 3.7 GB, more than a pack can hold.") }
            }
            keys.insert(key)
            entries.append(Entry(key: key, w: t.w, h: t.h, fmt: t.fmt, levels: t.levels, off: off, size: t.data.count, label: label))
            return true
        }
        /// header, entries sorted by key, names, then the levels (4 KB aligned)
        func finish(to dest: URL) throws {
            try fh.synchronize()
            func fields(_ k: Key) -> (UInt32, UInt32, Int, Int, UInt32) {
                switch k {
                case .content(let c, let a, let w, let h, let f): return (c, a, w, h, f)
                case .texmod(let v): return (v, 0, 0, 0, 1)
                case .name(let v): return (v, 0, 0, 0, 2)
                }
            }
            let order = entries.sorted { let a = fields($0.key), b = fields($1.key); return a.0 != b.0 ? a.0 < b.0 : a.1 < b.1 }
            var names = [UInt8]()
            let at = 16 + 40 * order.count
            var nameAt = [Int]()
            for e in order { nameAt.append(at + names.count); names += Array(e.label.utf8.prefix(1000)) + [0] }
            let base = (at + names.count + 4095) & ~4095
            var out = [UInt8]()
            out.reserveCapacity(base)
            func u32(_ v: Int) { out += withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian, Array.init) }
            func u16(_ v: Int) { out += withUnsafeBytes(of: UInt16(truncatingIfNeeded: v).littleEndian, Array.init) }
            out += Array("NTXP".utf8); u32(2); u32(order.count); u32(0)
            for (i, e) in order.enumerated() {
                let k = fields(e.key)
                u32(Int(k.0)); u32(Int(k.1)); u16(k.2); u16(k.3); u32(Int(k.4))
                u16(e.w); u16(e.h); u32(Int(e.fmt)); u32(e.levels); u32(base + e.off); u32(e.size); u32(nameAt[i])
            }
            out += names
            out += [UInt8](repeating: 0, count: base - out.count)
            let fm = FileManager.default
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let part = dest.appendingPathExtension("part")
            guard fm.createFile(atPath: part.path, contents: Data(out)), let w = FileHandle(forWritingAtPath: part.path),
                  let r = FileHandle(forReadingAtPath: tmp.path) else { throw Failure(message: "\(dest.path) could not be written.") }
            w.seekToEndOfFile()
            while true {
                let chunk = r.readData(ofLength: 8 << 20)
                if chunk.isEmpty { break }
                w.write(chunk)
            }
            try? r.close(); try? w.close()
            guard rename(part.path, dest.path) == 0 else {
                try? fm.removeItem(at: part)
                throw Failure(message: "\(dest.path) could not be written.")
            }
        }
    }

    // MARK: finding the mod's parts

    /// The pack from a mod as downloaded (archive, .tpf, folder).  include: if not empty, only
    /// paths that contain one of these are used (a mod's variant); exclude: paths not to use
    /// (its old versions, the originals it keeps for uninstalling).
    ///
    /// Safety: an archive is unpacked only into a new temporary folder of ours, and a mod
    /// (unpacked or a folder the player chose) that holds a symbolic link, or anything that
    /// is not a plain file or folder, is refused, so nothing outside it is ever read.
    static func build(mod: URL, game: URL, include: [String] = [], exclude: [String] = [], to dest: URL,
                      progress: @escaping (String) -> Void = { _ in }) throws -> Summary {
        let fm = FileManager.default
        var temps = [URL]()
        defer { for t in temps { try? fm.removeItem(at: t) } }
        func unpack(_ archive: URL) throws -> URL {
            let t = fm.temporaryDirectory.appendingPathComponent("nfsu2-texpack-\(UUID().uuidString)")
            try fm.createDirectory(at: t, withIntermediateDirectories: false)
            temps.append(t)
            // bsdtar (libarchive) reads ZIP, 7-Zip and RAR archives; it refuses absolute paths and ".."
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = ["-xf", archive.path, "-C", t.path, "--no-same-owner", "--no-same-permissions"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw Failure(message: "\(archive.lastPathComponent) could not be unpacked. Choose the mod as downloaded (.zip, .7z, .rar or .tpf), or the folder it was extracted to.")
            }
            return t
        }
        let modFile = !UHUDPack.isDirectory(mod)
        var root = mod
        if modFile && !isTPF(mod) {
            progress("Unpacking \(mod.lastPathComponent)…")
            root = try unpack(mod)
        }
        // the files, archives inside the archive unpacked too (two levels)
        var files = [(URL, String)]()           // file, path inside the mod
        func walk(_ top: URL, _ shown: String, depth: Int) throws {
            if !UHUDPack.isDirectory(top) { files.append((top, top.lastPathComponent)); return }
            let dir = URL(fileURLWithPath: realPath(top.path))
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: keys) else { return }
            var inner = [URL]()
            for case let u as URL in en {             // the enumerator does not follow links
                let v = try u.resourceValues(forKeys: Set(keys))
                let rel = u.path.hasPrefix(dir.path + "/") ? String(u.path.dropFirst(dir.path.count + 1)) : ""
                if v.isSymbolicLink == true || rel.isEmpty || rel.split(separator: "/").contains("..") {
                    throw Failure(message: "\(mod.lastPathComponent) contains a link (\(shown + (rel.isEmpty ? u.lastPathComponent : rel))) that could point outside the mod. It was not used; a texture pack has only plain files.")
                }
                if v.isDirectory == true { continue }
                guard v.isRegularFile == true else {
                    throw Failure(message: "\(mod.lastPathComponent) contains \(shown + rel), which is not a plain file. It was not used.")
                }
                let path = shown + rel, low = path.lowercased()
                if !include.isEmpty && !include.contains(where: { low.contains($0.lowercased()) }) { continue }
                if exclude.contains(where: { low.contains($0.lowercased()) }) { continue }
                if ["zip", "7z", "rar"].contains(u.pathExtension.lowercased()) { inner.append(u) }
                else { files.append((u, path)) }
            }
            for a in inner.sorted(by: { $0.path < $1.path }) where depth < 2 {
                progress("Unpacking \(a.lastPathComponent)…")
                try walk(try unpack(a), shown + String(a.path.dropFirst(dir.path.count + 1)) + "/", depth: depth + 1)
            }
        }
        try walk(root, "", depth: 0)
        files.sort { $0.1.lowercased() < $1.1.lowercased() }

        let writer = try Writer()
        var sum = Summary()
        var used = Set<String>()
        let gameIndex = GameIndex(game)
        // 1. the game's own files, changed
        for (f, rel) in files where ["bun", "bin", "lzc"].contains(f.pathExtension.lowercased()) {
            guard let g = try gameFile(for: f, rel, game: game, gameIndex) else { continue }
            progress("Comparing \(g.rel) with the game's…")
            used.insert(rel)
            let before = writer.entries.count
            try diffBundle(mod: f, game: g.url, label: g.rel, writer, &sum)
            if writer.entries.count > before { sum.sources.append(rel) }
        }
        // 2. TexWizard packs: textures.bin with meta.json, or in a TexturePacks folder
        for (f, rel) in files where f.lastPathComponent.lowercased() == "textures.bin" && !used.contains(rel) {
            let dir = f.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("meta.json").path)
                    || rel.lowercased().contains("texturepacks/") else { continue }
            progress("Reading the TexWizard pack \(dir.lastPathComponent)…")
            let before = writer.entries.count
            try texWizard(f, writer, &sum)
            if writer.entries.count > before { sum.sources.append(rel) }
        }
        // 3. TexMod packs, then loose TexMod files (named by their hash)
        for (f, rel) in files where isTPF(f) {
            progress("Reading \(f.lastPathComponent)…")
            let before = writer.entries.count
            let zip = try Zip(tpf: f)
            var named = [String: () throws -> [UInt8]]()
            for e in zip.entries { named[normal(e.name)] = { try zip.read(e) } }
            try texMod(def: zip.entries.first(where: { normal($0.name).hasSuffix("texmod.def") }).map { try zip.read($0) },
                       files: named, label: f.lastPathComponent, writer, &sum, progress)
            if writer.entries.count > before { sum.sources.append(rel) }
        }
        var loose = [String: () throws -> [UInt8]]()
        var looseDef: [UInt8]? = nil
        for (f, rel) in files where !isTPF(f) {
            if f.lastPathComponent.lowercased() == "texmod.def" { looseDef = try? [UInt8](Data(contentsOf: f)); continue }
            if imageExtensions.contains(f.pathExtension.lowercased()) {
                loose[normal(rel)] = { try [UInt8](Data(contentsOf: f)) }
            }
        }
        if looseDef != nil || loose.keys.contains(where: { texModHash($0) != nil }) {
            let before = writer.entries.count
            try texMod(def: looseDef, files: loose, label: "TexMod files", writer, &sum, progress, onlyPresent: true)
            if writer.entries.count > before { sum.sources.append("TexMod files") }
        }
        // 4. images named after the game's textures (as texture editors export them)
        // (other images only with a name as the game writes them, A-Z, 0-9 and _: not a preview)
        let named = files.filter { f in
            let ext = f.0.pathExtension.lowercased(), base = textureName(f.0.deletingPathExtension().lastPathComponent)
            guard texModHash(f.0.lastPathComponent) == nil else { return false }
            if ext == "dds" { return true }
            return ["png", "tga", "bmp"].contains(ext) && !base.isEmpty
                && base.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        }
        if !named.isEmpty {
            progress("Reading \(named.count) images…")
            let before = writer.entries.count
            for (f, rel) in named {
                let name = textureName(f.deletingPathExtension().lastPathComponent)
                let key = Key.name(UHUDPack.stringHash(name.uppercased()))
                guard !writer.has(key) else { continue }
                let ext = f.pathExtension.lowercased()
                guard let b = try? [UInt8](Data(contentsOf: f)), let t = ext == "dds" ? dds(b, mips: false) : image(b, ext: ext, mips: true) else {
                    sum.skipped.append("\(rel): a format this does not read"); continue
                }
                if try writer.add(key, t, rel) { sum.named += 1 }
            }
            if writer.entries.count > before { sum.sources.append("images named after the game's textures") }
        }
        guard !writer.entries.isEmpty else {
            throw Failure(message: "\(mod.lastPathComponent) has no textures this can use: no TexMod pack (.tpf), no TexWizard pack, none of the game's texture files and no image named after a game texture.")
        }
        progress("Writing the pack…")
        try writer.finish(to: dest)
        sum.textures = writer.entries.count
        let attrs = try? fm.attributesOfItem(atPath: dest.path)
        sum.bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return sum
    }

    static func realPath(_ p: String) -> String {
        guard let r = realpath(p, nil) else { return p }
        defer { free(r) }
        return String(cString: r)
    }

    /// The texture's name from an image file's name: NFS-TexEd exports "1-5-DXT1-nfs_u2_mw-NAME",
    /// Binary's folders number textures of the same name "103_NAME".
    static func textureName(_ base: String) -> String {
        let parts = base.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: false)
        if parts.count == 5, Int(parts[0]) != nil, Int(parts[1]) != nil, parts[3].lowercased().hasPrefix("nfs") {
            return String(parts[4])
        }
        if let u = base.firstIndex(of: "_"), u > base.startIndex, base[..<u].allSatisfy({ $0.isASCII && $0.isNumber }) {
            return String(base[base.index(after: u)...])
        }
        return base
    }

    /// The game's texture files by file name, for mods that ship one without its folder.
    struct GameIndex {
        var byName = [String: [String]]()          // file name, lowercased -> paths in the game folder
        init(_ game: URL) {
            for dir in ["GLOBAL", "FRONTEND", "FRONTEND/PLATFORMS", "TRACKS", "CARS", "CARS/WHEELS", "LANGUAGES"] {
                guard let d = UHUDPack.find(game, dir),
                      let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { continue }
                for n in names where ["bun", "bin", "lzc"].contains((n as NSString).pathExtension.lowercased()) {
                    byName[n.lowercased(), default: []].append(dir + "/" + n)
                }
            }
        }
    }

    static let imageExtensions: Set<String> = ["dds", "png", "bmp", "tga", "jpg", "jpeg"]
    static func isTPF(_ u: URL) -> Bool { u.pathExtension.lowercased() == "tpf" && !UHUDPack.isDirectory(u) }
    static func normal(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\", with: "/").lowercased()
        while t.hasPrefix("/") || t.hasPrefix("./") { t.removeFirst(t.hasPrefix("/") ? 1 : 2) }
        return t
    }

    /// The game file a mod's file replaces: the longest end of its path that is a file in the
    /// game folder; otherwise, of the game's texture files with its name (GlobalB.lzc in a
    /// "screen" folder, TEXTURES.BIN of the cars or the wheels), the one that shares the most
    /// texture names with it.
    static func gameFile(for file: URL, _ rel: String, game: URL, _ index: GameIndex) throws -> (url: URL, rel: String)? {
        let parts = rel.split(separator: "/").map(String.init)
        for k in 0..<max(0, parts.count - 1) {
            let r = parts[k...].joined(separator: "/")
            if let u = UHUDPack.find(game, r), !UHUDPack.isDirectory(u) { return (u, r) }
        }
        guard let n = parts.last, let cands = index.byName[n.lowercased()] else { return nil }
        if cands.count == 1 { return UHUDPack.find(game, cands[0]).map { ($0, cands[0]) } }
        let mine = Set(try tpkTextures(try loadBundle(file)).map { $0.nh })
        var best: (URL, String)? = nil, bestN = 0
        for c in cands {
            guard let u = UHUDPack.find(game, c), let b = try? loadBundle(u), let t = try? tpkTextures(b) else { continue }
            let k = Set(t.map { $0.nh }).intersection(mine).count
            if k > bestN { best = (u, c); bestN = k }
        }
        return best.map { (url: $0.0, rel: $0.1) }
    }
    static func loadBundle(_ u: URL) throws -> [UInt8] {
        var d = [UInt8](try Data(contentsOf: u))
        if d.starts(with: Array("JDLZ".utf8)) { d = try UHUDPack.jdlz(d) }
        return d
    }

    // MARK: TexMod

    /// TexMod's hash in a file name: ..._0x1234ABCD.dds
    static func texModHash(_ name: String) -> UInt32? {
        let base = (name as NSString).deletingPathExtension
        guard let r = base.range(of: "_0x", options: [.caseInsensitive, .backwards]) else { return nil }
        let hex = base[r.upperBound...]
        guard hex.count == 8 else { return nil }
        return UInt32(hex, radix: 16)
    }

    /// onlyPresent: loose files, where a texmod.def may list a whole pack of which only some are here
    static func texMod(def: [UInt8]?, files: [String: () throws -> [UInt8]], label: String,
                       _ w: Writer, _ sum: inout Summary, _ progress: (String) -> Void, onlyPresent: Bool = false) throws {
        var list = [(UInt32, String)]()
        if let d = def {
            for line in String(decoding: d, as: UTF8.self).split(whereSeparator: { $0.isNewline }) {
                let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                var h = parts[0]
                if h.lowercased().hasPrefix("0x") { h.removeFirst(2) }
                guard let v = UInt32(h, radix: 16) else { continue }
                list.append((v, normal(parts[1])))
            }
        }
        if list.isEmpty {
            for k in files.keys.sorted() { if let v = texModHash(k) { list.append((v, k)) } }
        }
        // decoding and making the lower levels takes the time: several at once, in order
        func present(_ f: String) -> Bool { files[f] != nil || files.keys.contains(where: { $0.hasSuffix("/" + f) }) }
        let todo = list.filter { !w.has(.texmod($0.0)) && (!onlyPresent || present($0.1)) }
        var i = 0
        while i < todo.count {
            let batch = Array(todo[i..<min(todo.count, i + 32)])
            progress("Converting \(label): \(i) of \(todo.count) textures…")
            var out = [Tex?](repeating: nil, count: batch.count)
            var errs = [String?](repeating: nil, count: batch.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: batch.count) { j in
                let (_, file) = batch[j]
                var t: Tex? = nil, e: String? = nil
                if let get = files[file] ?? files.first(where: { $0.key.hasSuffix("/" + file) })?.value,
                   let bytes = try? get() {
                    t = image(bytes, ext: (file as NSString).pathExtension.lowercased(), mips: true)
                    if t == nil { e = "\(label)/\(file): a format this does not read" }
                } else { e = "\(label)/\(file): missing" }
                lock.lock(); out[j] = t; errs[j] = e; lock.unlock()
            }
            for j in 0..<batch.count {
                if let t = out[j] {
                    if try w.add(.texmod(batch[j].0), t, "\(label)/\(batch[j].1)") { sum.texmod += 1 }
                } else if let e = errs[j] { sum.skipped.append(e) }
            }
            i += batch.count
        }
    }

    /// A TexMod pack: the ZIP inside a .tpf.
    struct Zip {
        struct Entry { let name: String; let method: Int; let flags: Int; let crc: UInt32; let csize: Int; let usize: Int; let local: Int }
        let data: [UInt8]
        let entries: [Entry]
        // TexMod's password for its packs (the same in every .tpf)
        static let password: [UInt8] = [0x73, 0x2A, 0x63, 0x7D, 0x5F, 0x0A, 0xA6, 0xBD, 0x7D, 0x65, 0x7E, 0x67, 0x61, 0x2A,
                                        0x7F, 0x7F, 0x74, 0x61, 0x67, 0x5B, 0x60, 0x70, 0x45, 0x74, 0x5C, 0x22, 0x74, 0x5D,
                                        0x6E, 0x6A, 0x73, 0x41, 0x77, 0x6E, 0x46, 0x47, 0x77, 0x49, 0x0C, 0x4B, 0x46, 0x6F]
        init(tpf: URL) throws {
            var d = [UInt8](try Data(contentsOf: tpf))
            if d.count >= 4 && !(d[0] == 0x50 && d[1] == 0x4B) {       // XOR'd with 0x3FA43FA4
                let key: [UInt8] = [0xA4, 0x3F, 0xA4, 0x3F]
                d.withUnsafeMutableBufferPointer { b in for i in 0..<b.count { b[i] ^= key[i & 3] } }
            }
            try self.init(zip: d, name: tpf.lastPathComponent)
        }
        init(zip d: [UInt8], name: String) throws {
            data = d
            let bad = Failure(message: "\(name) is not a TexMod pack this can read.")
            // the end of central directory record, from the end
            var eocd = -1
            var i = d.count - 22
            while i >= max(0, d.count - 22 - 65536 - 1024) {
                if UHUDPack.u32(d, i) == 0x0605_4B50 { eocd = i; break }
                i -= 1
            }
            guard eocd >= 0 else { throw bad }
            let n = UHUDPack.u16(d, eocd + 10), cd = Int(UHUDPack.u32(d, eocd + 16))
            var es = [Entry](), o = cd
            for _ in 0..<n {
                guard UHUDPack.u32(d, o) == 0x0201_4B50 else { throw bad }
                let nl = UHUDPack.u16(d, o + 28), xl = UHUDPack.u16(d, o + 30), cl = UHUDPack.u16(d, o + 32)
                let nm = String(decoding: UHUDPack.slice(d, o + 46, o + 46 + nl), as: UTF8.self)
                es.append(Entry(name: nm, method: UHUDPack.u16(d, o + 10), flags: UHUDPack.u16(d, o + 8),
                                crc: UHUDPack.u32(d, o + 16), csize: Int(UHUDPack.u32(d, o + 20)),
                                usize: Int(UHUDPack.u32(d, o + 24)), local: Int(UHUDPack.u32(d, o + 42))))
                o += 46 + nl + xl + cl
            }
            entries = es.filter { !$0.name.hasSuffix("/") }
        }
        func read(_ e: Entry) throws -> [UInt8] {
            let bad = Failure(message: "\(e.name) in a TexMod pack is damaged.")
            guard UHUDPack.u32(data, e.local) == 0x0403_4B50 else { throw bad }
            let start = e.local + 30 + UHUDPack.u16(data, e.local + 26) + UHUDPack.u16(data, e.local + 28)
            guard start + e.csize <= data.count, e.usize < 1 << 30 else { throw bad }
            var src = Array(data[start..<(start + e.csize)])
            if e.flags & 1 != 0 {                     // traditional PKWARE encryption
                var k0: UInt32 = 0x1234_5678, k1: UInt32 = 0x2345_6789, k2: UInt32 = 0x3456_7890
                func update(_ c: UInt8) {
                    k0 = UHUDPack.crcTable[Int((k0 ^ UInt32(c)) & 0xFF)] ^ (k0 >> 8)
                    k1 = (k1 &+ (k0 & 0xFF)) &* 134_775_813 &+ 1
                    k2 = UHUDPack.crcTable[Int((k2 ^ (k1 >> 24)) & 0xFF)] ^ (k2 >> 8)
                }
                for c in Zip.password { update(c) }
                for i in 0..<src.count {
                    let t = UInt16(truncatingIfNeeded: k2 | 2)
                    let c = src[i] ^ UInt8(truncatingIfNeeded: (UInt32(t) &* UInt32(t ^ 1)) >> 8)
                    src[i] = c; update(c)
                }
                guard src.count >= 12 else { throw bad }
                src.removeFirst(12)
            }
            var out: [UInt8]
            switch e.method {
            case 0: out = src
            case 8:
                out = [UInt8](repeating: 0, count: e.usize)
                let n = out.withUnsafeMutableBufferPointer { o in src.withUnsafeBufferPointer { s in
                    compression_decode_buffer(o.baseAddress!, e.usize, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB) } }
                guard n == e.usize || e.usize == 0 else { throw bad }
            default: throw bad
            }
            guard out.count == e.usize, UHUDPack.crc32(out) == e.crc else { throw bad }
            return out
        }
    }

    // MARK: TexWizard

    static func texWizard(_ bin: URL, _ w: Writer, _ sum: inout Summary) throws {
        let d = [UInt8](try Data(contentsOf: bin))
        var byName = [UInt32: Tex]()
        var order = [UInt32]()
        for t in try tpkTextures(d) { if let tx = t.tex, byName[t.nh] == nil { byName[t.nh] = tx; order.append(t.nh) } }
        let pack = bin.deletingLastPathComponent().lastPathComponent
        var pairs = [(String, UInt32, String)]()          // game texture, its hash, the pack's
        if let m = try? Data(contentsOf: bin.deletingLastPathComponent().appendingPathComponent("meta.json")),
           let j = try? JSONSerialization.jsonObject(with: m) as? [String: Any],
           let list = j["textures"] as? [[String]] {
            for p in list where p.count >= 2 { pairs.append((p[0], UHUDPack.stringHash(p[0].uppercased()), p[1])) }
            for p in list where p.count == 1 { pairs.append((p[0], UHUDPack.stringHash(p[0].uppercased()), p[0])) }
        } else {
            for h in order { pairs.append((String(format: "0x%08X", h), h, "")) }
        }
        for (game, gh, packName) in pairs {
            let src = packName.isEmpty ? gh : UHUDPack.stringHash(packName.uppercased())
            guard let t = byName[src] else { sum.skipped.append("\(pack)/\(packName.isEmpty ? game : packName): not in textures.bin"); continue }
            if try w.add(.name(gh), t, "\(pack)/\(game)") { sum.named += 1 }
        }
    }

    // MARK: the game's texture files

    static func diffBundle(mod: URL, game: URL, label: String, _ w: Writer, _ sum: inout Summary) throws {
        let load = loadBundle
        var gameTex = [UInt32: TPKTex]()
        for t in try tpkTextures(try load(game)) where gameTex[t.nh] == nil { gameTex[t.nh] = t }
        for t in try tpkTextures(try load(mod)) {
            guard let g = gameTex[t.nh] else { continue }                  // not one the game knows
            guard let mt = t.tex else { sum.skipped.append("\(label)/\(String(format: "0x%08X", t.nh)): a format this does not read"); continue }
            if let gt = g.tex {
                let lv0 = Array(gt.data.prefix(UHUDPack.levelSize(gt.w, gt.h, gt.fmt)))
                if (mt.w, mt.h, mt.fmt) == (gt.w, gt.h, gt.fmt) && mt.data.prefix(lv0.count).elementsEqual(lv0) { continue }  // unchanged
                if try w.add(.content(crc: UHUDPack.crc32(lv0), adler: UHUDPack.adler32(lv0), w: gt.w, h: gt.h, fmt: gt.fmt),
                             mt, "\(label)/\(t.name)") { sum.content += 1 }
            } else if try w.add(.name(t.nh), mt, "\(label)/\(t.name)") { sum.named += 1 }
        }
    }

    /// A texture of a TPK: its name hash and name, and its levels as the game uploads them
    /// (nil: compressed or stored in a way this does not read).
    struct TPKTex { let nh: UInt32; let name: String; let tex: Tex? }

    static func tpkTextures(_ d: [UInt8]) throws -> [TPKTex] {
        var r = [TPKTex]()
        for (b, e) in UHUDPack.tpks(d, 0, d.count) {
            var info: (Int, Int)? = nil, dat: (Int, Int)? = nil
            for (cid, cb, ce) in UHUDPack.chunks(d, b, e) {
                if cid == 0xB331_0000 { info = (cb, ce) } else if cid == 0xB332_0000 { dat = (cb, ce) }
            }
            guard let inf = info, let da = dat else { continue }
            var part = [UInt32: (Int, Int)]()
            for (cid, cb, ce) in UHUDPack.chunks(d, inf.0, inf.1) { part[cid] = (cb, ce) }
            let pix = UHUDPack.chunks(d, da.0, da.1).first(where: { $0.0 == 0x3332_0002 }).map { ($0.1 + 0x7F) & ~0x7F }
            if let (tb, te) = part[0x3331_0004], let pix = pix {
                let pl = part[0x3331_0005] ?? (0, 0)
                for i in 0..<((te - tb) / 0x7C) {
                    let pf = pl.0 + (i + 1) * 0x20 <= pl.1 ? UHUDPack.slice(d, pl.0 + i * 0x20, pl.0 + (i + 1) * 0x20) : []
                    r.append(tpkTexture(UHUDPack.slice(d, tb + i * 0x7C, tb + (i + 1) * 0x7C), pf, d, pix))
                }
            } else if let (cb, ce) = part[0x3331_0003] {
                // compressed textures: each one's data, then its TextureInfo (0x7C) and platform info (0x20)
                for i in 0..<((ce - cb) / 24) {
                    let nh = UHUDPack.u32(d, cb + i * 24), off = Int(UHUDPack.u32(d, cb + i * 24 + 4)), size = Int(UHUDPack.u32(d, cb + i * 24 + 8))
                    let blob = UHUDPack.slice(d, off, off + size)
                    guard blob.starts(with: Array("JDLZ".utf8)), let out = try? UHUDPack.jdlz(blob), out.count >= 0x9C else {
                        r.append(TPKTex(nh: nh, name: String(format: "0x%08X", nh), tex: nil)); continue
                    }
                    let ti = Array(out[(out.count - 0x9C)..<(out.count - 0x20)])
                    r.append(tpkTexture(ti, Array(out[(out.count - 0x20)...]), out, -Int(UHUDPack.u32(ti, 0x30))))
                }
            }
        }
        return r
    }

    static func tpkTexture(_ ti: [UInt8], _ pf: [UInt8], _ buf: [UInt8], _ base: Int) -> TPKTex {
        let nh = UHUDPack.u32(ti, 0x24)
        let nameBytes = UHUDPack.slice(ti, 0x0C, 0x24).prefix { $0 != 0 }
        let name = nameBytes.isEmpty ? String(format: "0x%08X", nh) : String(decoding: nameBytes, as: UTF8.self)
        let img = base + Int(UHUDPack.u32(ti, 0x30)), pal = base + Int(UHUDPack.u32(ti, 0x34))
        let palSize = Int(UHUDPack.u32(ti, 0x3C))
        let w = UHUDPack.u16(ti, 0x44), h = UHUDPack.u16(ti, 0x46)
        let levels = max(1, Int(ti.count > 0x4E ? ti[0x4E] : 1))
        let code = pf.count >= 0x18 ? UHUDPack.u32(pf, 0x14) : 0
        let none = TPKTex(nh: nh, name: name, tex: nil)
        guard w > 0, h > 0, w <= 16384, h <= 16384, levels <= 15 else { return none }
        if [dxt1, dxt3, dxt5, argb].contains(code) {
            var n = 0
            for l in 0..<levels { n += UHUDPack.levelSize(max(1, w >> l), max(1, h >> l), code) }
            let lv = UHUDPack.slice(buf, img, img + n)
            return lv.count == n ? TPKTex(nh: nh, name: name, tex: Tex(w: w, h: h, fmt: code, levels: levels, data: lv)) : none
        }
        if code == UHUDPack.p8 && palSize >= 1024 {
            // the game expands it with its palette (BGRA, as A8R8G8B8 is in memory) before the upload
            var n = 0
            for l in 0..<levels { n += max(1, w >> l) * max(1, h >> l) }
            let ix = UHUDPack.slice(buf, img, img + n), p = UHUDPack.slice(buf, pal, pal + 1024)
            guard ix.count == n, p.count == 1024 else { return none }
            var out = [UInt8](repeating: 0, count: n * 4)
            for (k, v) in ix.enumerated() { for c in 0..<4 { out[k * 4 + c] = p[Int(v) * 4 + c] } }
            return TPKTex(nh: nh, name: name, tex: Tex(w: w, h: h, fmt: argb, levels: levels, data: out))
        }
        return none
    }

    // MARK: images

    /// A DDS or an image file as a texture; mips: make the lower levels when it has only the first.
    static func image(_ b: [UInt8], ext: String, mips: Bool) -> Tex? {
        if b.starts(with: Array("DDS ".utf8)) { return dds(b, mips: mips) }
        guard let src = CGImageSourceCreateWithData(Data(b) as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        guard w > 0, h > 0, w <= 16384, h <= 16384 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { p in
            guard let cg = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            cg.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // BGRA, premultiplied -> straight alpha
        px.withUnsafeMutableBufferPointer { p in
            for i in stride(from: 0, to: p.count, by: 4) {
                let a = Int(p[i + 3])
                if a > 0 && a < 255 { for c in 0..<3 { p[i + c] = UInt8(min(255, (Int(p[i + c]) * 255 + a / 2) / a)) } }
            }
        }
        return mips ? withMips(Tex(w: w, h: h, fmt: argb, levels: 1, data: px)) : Tex(w: w, h: h, fmt: argb, levels: 1, data: px)
    }

    /// DXT1/3/5 as they are; other uncompressed formats (RGB masks, luminance, alpha) as A8R8G8B8.
    static func dds(_ b: [UInt8], mips: Bool) -> Tex? {
        guard b.count >= 128 else { return nil }
        let h = Int(UHUDPack.u32(b, 12)), w = Int(UHUDPack.u32(b, 16))
        let count = max(1, Int(UHUDPack.u32(b, 28)))
        let caps2 = UHUDPack.u32(b, 112)
        let flags = UHUDPack.u32(b, 80), four = UHUDPack.u32(b, 84), bits = Int(UHUDPack.u32(b, 88))
        let masks = [UHUDPack.u32(b, 92), UHUDPack.u32(b, 96), UHUDPack.u32(b, 100), UHUDPack.u32(b, 104)]
        guard w > 0, h > 0, w <= 16384, h <= 16384, caps2 & 0x200 == 0, caps2 & 0x20_0000 == 0 else { return nil }  // no cube maps, volumes
        var maxLevels = 1
        var d = max(w, h); while d > 1 { d >>= 1; maxLevels += 1 }
        let want = min(count, maxLevels)
        if flags & 4 != 0 {
            guard [dxt1, dxt3, dxt5].contains(four) else { return nil }
            var n = 0, lv = 0
            while lv < want && 128 + n + UHUDPack.levelSize(max(1, w >> lv), max(1, h >> lv), four) <= b.count {
                n += UHUDPack.levelSize(max(1, w >> lv), max(1, h >> lv), four); lv += 1
            }
            guard lv > 0 else { return nil }
            let t = Tex(w: w, h: h, fmt: four, levels: lv, data: Array(b[128..<(128 + n)]))
            return mips && lv == 1 && maxLevels > 1 ? withMips(t) : t
        }
        // uncompressed: each pixel through its masks
        guard [8, 16, 24, 32].contains(bits) else { return nil }
        let bpp = bits / 8
        let lum = flags & 0x2_0000 != 0, alphaOnly = flags & 0x2 != 0 && flags & 0x40 == 0 && !lum
        let hasAlpha = flags & 0x1 != 0 || alphaOnly
        func chan(_ v: UInt32, _ m: UInt32) -> UInt8 {
            guard m != 0 else { return 0 }
            let shift = m.trailingZeroBitCount, top = (m >> shift)
            return UInt8(((v & m) >> shift) * 255 / top)
        }
        var levelsOut = [UInt8](), lv = 0, at = 128
        while lv < want {
            let lw = max(1, w >> lv), lh = max(1, h >> lv)
            guard at + lw * lh * bpp <= b.count else { break }
            var px = [UInt8](repeating: 0, count: lw * lh * 4)
            for i in 0..<(lw * lh) {
                var v: UInt32 = 0
                for k in 0..<bpp { v |= UInt32(b[at + i * bpp + k]) << (8 * k) }
                if alphaOnly { px[i * 4 + 3] = chan(v, masks[3] != 0 ? masks[3] : 0xFF); continue }
                if lum {
                    let l = chan(v, masks[0] != 0 ? masks[0] : 0xFF)
                    px[i * 4] = l; px[i * 4 + 1] = l; px[i * 4 + 2] = l
                } else {
                    px[i * 4 + 2] = chan(v, masks[0]); px[i * 4 + 1] = chan(v, masks[1]); px[i * 4] = chan(v, masks[2])
                }
                px[i * 4 + 3] = hasAlpha && masks[3] != 0 ? chan(v, masks[3]) : 255
            }
            levelsOut += px; at += lw * lh * bpp; lv += 1
        }
        guard lv > 0 else { return nil }
        let t = Tex(w: w, h: h, fmt: argb, levels: lv, data: levelsOut)
        return mips && lv == 1 && maxLevels > 1 ? withMips(t) : t
    }

    // MARK: mip levels

    /// The texture with every lower level made from level 0 (a 2x2 box filter; DXT levels
    /// decoded, filtered and encoded again in the same format).
    static func withMips(_ t: Tex) -> Tex {
        var cur = t.fmt == argb ? Array(t.data.prefix(t.w * t.h * 4)) : decodeDXT(t.data, t.w, t.h, t.fmt)
        var out = Array(t.data.prefix(UHUDPack.levelSize(t.w, t.h, t.fmt)))
        var w = t.w, h = t.h, levels = 1
        while w > 1 || h > 1 {
            let nw = max(1, w / 2), nh = max(1, h / 2)
            var nx = [UInt8](repeating: 0, count: nw * nh * 4)
            cur.withUnsafeBufferPointer { s in nx.withUnsafeMutableBufferPointer { d in
                for y in 0..<nh {
                    let y0 = min(h - 1, y * 2), y1 = min(h - 1, y * 2 + 1)
                    for x in 0..<nw {
                        let x0 = min(w - 1, x * 2), x1 = min(w - 1, x * 2 + 1)
                        for c in 0..<4 {
                            let sum = Int(s[(y0 * w + x0) * 4 + c]) + Int(s[(y0 * w + x1) * 4 + c])
                                    + Int(s[(y1 * w + x0) * 4 + c]) + Int(s[(y1 * w + x1) * 4 + c])
                            d[(y * nw + x) * 4 + c] = UInt8((sum + 2) / 4)
                        }
                    }
                }
            } }
            out += t.fmt == argb ? nx : encodeDXT(nx, nw, nh, t.fmt)
            cur = nx; w = nw; h = nh; levels += 1
        }
        return Tex(w: t.w, h: t.h, fmt: t.fmt, levels: levels, data: out)
    }

    /// level 0 of a DXT texture as BGRA
    static func decodeDXT(_ src: [UInt8], _ w: Int, _ h: Int, _ fmt: UInt32) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let bw = (w + 3) / 4, bh = (h + 3) / 4, bs = fmt == dxt1 ? 8 : 16
        guard src.count >= bw * bh * bs else { return px }
        src.withUnsafeBufferPointer { s in px.withUnsafeMutableBufferPointer { p in
            var pal = [(Int, Int, Int, Int)](repeating: (0, 0, 0, 0), count: 4)
            var alpha = [Int](repeating: 255, count: 16)
            for by in 0..<bh { for bx in 0..<bw {
                let o = (by * bw + bx) * bs
                let co = fmt == dxt1 ? o : o + 8
                if fmt == dxt3 {
                    for i in 0..<16 { let v = (Int(s[o + i / 2]) >> ((i & 1) * 4)) & 15; alpha[i] = v * 17 }
                } else if fmt == dxt5 {
                    let a0 = Int(s[o]), a1 = Int(s[o + 1])
                    var bits: UInt64 = 0
                    for k in 0..<6 { bits |= UInt64(s[o + 2 + k]) << (8 * UInt64(k)) }
                    for i in 0..<16 {
                        let ix = Int((bits >> (3 * UInt64(i))) & 7)
                        switch ix {
                        case 0: alpha[i] = a0
                        case 1: alpha[i] = a1
                        default:
                            if a0 > a1 { alpha[i] = ((8 - ix) * a0 + (ix - 1) * a1) / 7 }
                            else if ix < 6 { alpha[i] = ((6 - ix) * a0 + (ix - 1) * a1) / 5 }
                            else { alpha[i] = ix == 6 ? 0 : 255 }
                        }
                    }
                } else { for i in 0..<16 { alpha[i] = 255 } }
                let c0 = Int(s[co]) | Int(s[co + 1]) << 8, c1 = Int(s[co + 2]) | Int(s[co + 3]) << 8
                func rgb(_ c: Int) -> (Int, Int, Int) {
                    let r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31
                    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))
                }
                let (r0, g0, b0) = rgb(c0), (r1, g1, b1) = rgb(c1)
                pal[0] = (r0, g0, b0, 255); pal[1] = (r1, g1, b1, 255)
                if c0 > c1 || fmt != dxt1 {
                    pal[2] = ((2 * r0 + r1) / 3, (2 * g0 + g1) / 3, (2 * b0 + b1) / 3, 255)
                    pal[3] = ((r0 + 2 * r1) / 3, (g0 + 2 * g1) / 3, (b0 + 2 * b1) / 3, 255)
                } else {
                    pal[2] = ((r0 + r1) / 2, (g0 + g1) / 2, (b0 + b1) / 2, 255)
                    pal[3] = (0, 0, 0, 0)
                }
                let idx = UInt32(s[co + 4]) | UInt32(s[co + 5]) << 8 | UInt32(s[co + 6]) << 16 | UInt32(s[co + 7]) << 24
                for i in 0..<16 {
                    let x = bx * 4 + (i & 3), y = by * 4 + (i >> 2)
                    guard x < w, y < h else { continue }
                    let c = pal[Int((idx >> (2 * UInt32(i))) & 3)]
                    let q = (y * w + x) * 4
                    p[q] = UInt8(c.2); p[q + 1] = UInt8(c.1); p[q + 2] = UInt8(c.0)
                    p[q + 3] = UInt8(fmt == dxt1 ? c.3 : alpha[i])
                }
            } }
        } }
        return px
    }

    /// BGRA as DXT1/3/5: a quick encoder for the lower levels (endpoints from the block's
    /// colour range along its main direction).
    static func encodeDXT(_ px: [UInt8], _ w: Int, _ h: Int, _ fmt: UInt32) -> [UInt8] {
        let bw = (w + 3) / 4, bh = (h + 3) / 4, bs = fmt == dxt1 ? 8 : 16
        var out = [UInt8](repeating: 0, count: bw * bh * bs)
        px.withUnsafeBufferPointer { p in out.withUnsafeMutableBufferPointer { o in
            var r = [Int](repeating: 0, count: 16), g = r, b = r, a = r
            for by in 0..<bh { for bx in 0..<bw {
                for i in 0..<16 {
                    let x = min(w - 1, bx * 4 + (i & 3)), y = min(h - 1, by * 4 + (i >> 2))
                    let q = (y * w + x) * 4
                    b[i] = Int(p[q]); g[i] = Int(p[q + 1]); r[i] = Int(p[q + 2]); a[i] = Int(p[q + 3])
                }
                let base = (by * bw + bx) * bs
                var co = base
                if fmt == dxt3 {
                    for i in 0..<8 {
                        let lo = (a[i * 2] * 15 + 127) / 255, hi = (a[i * 2 + 1] * 15 + 127) / 255
                        o[base + i] = UInt8(lo | hi << 4)
                    }
                    co = base + 8
                } else if fmt == dxt5 {
                    let amax = a.max()!, amin = a.min()!
                    o[base] = UInt8(amax); o[base + 1] = UInt8(amin)
                    var bits: UInt64 = 0
                    if amax > amin {
                        for i in 0..<16 {
                            let t = ((amax - a[i]) * 7 + (amax - amin) / 2) / (amax - amin)     // 0 = amax .. 7 = amin
                            let ix = t == 0 ? 0 : t == 7 ? 1 : t + 1
                            bits |= UInt64(ix) << (3 * UInt64(i))
                        }
                    }
                    for k in 0..<6 { o[base + 2 + k] = UInt8((bits >> (8 * UInt64(k))) & 0xFF) }
                    co = base + 8
                }
                // colour: the range along the main direction, inset a little
                let transparent = fmt == dxt1 && a.contains(where: { $0 < 128 })
                var mr = 0, mg = 0, mb = 0, n = 0
                for i in 0..<16 where !(transparent && a[i] < 128) { mr += r[i]; mg += g[i]; mb += b[i]; n += 1 }
                if n == 0 { o[co] = 0; o[co + 1] = 0; o[co + 2] = 0; o[co + 3] = 0
                            for k in 4..<8 { o[co + k] = 0xFF }; continue }
                mr /= n; mg /= n; mb /= n
                var crg = 0, cbg = 0, crb = 0
                for i in 0..<16 where !(transparent && a[i] < 128) {
                    crg += (r[i] - mr) * (g[i] - mg); cbg += (b[i] - mb) * (g[i] - mg); crb += (r[i] - mr) * (b[i] - mb)
                }
                var lo = (255, 255, 255), hi = (0, 0, 0)
                for i in 0..<16 where !(transparent && a[i] < 128) {
                    lo = (min(lo.0, r[i]), min(lo.1, g[i]), min(lo.2, b[i])); hi = (max(hi.0, r[i]), max(hi.1, g[i]), max(hi.2, b[i]))
                }
                // flip the axes that run against green (or red) on the diagonal
                if crg < 0 { swap(&lo.0, &hi.0) }
                if cbg < 0 || (crg == 0 && crb < 0) { swap(&lo.2, &hi.2) }
                let ins = ((hi.0 - lo.0) / 16, (hi.1 - lo.1) / 16, (hi.2 - lo.2) / 16)
                hi = (hi.0 - ins.0, hi.1 - ins.1, hi.2 - ins.2); lo = (lo.0 + ins.0, lo.1 + ins.1, lo.2 + ins.2)
                func pack(_ c: (Int, Int, Int)) -> Int {
                    (min(31, max(0, (c.0 * 31 + 127) / 255)) << 11) | (min(63, max(0, (c.1 * 63 + 127) / 255)) << 5) | min(31, max(0, (c.2 * 31 + 127) / 255))
                }
                func unpack(_ c: Int) -> (Int, Int, Int) {
                    let r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31
                    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))
                }
                var c0 = pack(hi), c1 = pack(lo)
                // four colours need c0 > c1 (DXT1); three colours and transparent need c0 <= c1
                if transparent { if c0 > c1 { swap(&c0, &c1) } } else if c0 < c1 { swap(&c0, &c1) }
                let e0 = unpack(c0), e1 = unpack(c1)
                var pal: [(Int, Int, Int)]
                if c0 > c1 || fmt != dxt1 {
                    pal = [e0, e1, ((2 * e0.0 + e1.0) / 3, (2 * e0.1 + e1.1) / 3, (2 * e0.2 + e1.2) / 3),
                           ((e0.0 + 2 * e1.0) / 3, (e0.1 + 2 * e1.1) / 3, (e0.2 + 2 * e1.2) / 3)]
                } else {
                    pal = [e0, e1, ((e0.0 + e1.0) / 2, (e0.1 + e1.1) / 2, (e0.2 + e1.2) / 2), (0, 0, 0)]
                }
                var idx: UInt32 = 0
                for i in 0..<16 {
                    var best = 0, bestD = Int.max
                    if transparent && a[i] < 128 { best = 3 } else {
                        for k in 0..<(transparent || (c0 <= c1 && fmt == dxt1) ? 3 : 4) {
                            let dr = r[i] - pal[k].0, dg = g[i] - pal[k].1, db = b[i] - pal[k].2
                            let dd = dr * dr + dg * dg + db * db
                            if dd < bestD { bestD = dd; best = k }
                        }
                    }
                    idx |= UInt32(best) << (2 * UInt32(i))
                }
                o[co] = UInt8(c0 & 0xFF); o[co + 1] = UInt8(c0 >> 8); o[co + 2] = UInt8(c1 & 0xFF); o[co + 3] = UInt8(c1 >> 8)
                for k in 0..<4 { o[co + 4 + k] = UInt8((idx >> (8 * UInt32(k))) & 0xFF) }
            } }
        } }
        return out
    }
}
