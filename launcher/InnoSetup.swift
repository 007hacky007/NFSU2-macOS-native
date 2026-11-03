// Inno Setup installers, read, never run: the files of one, in Swift, so the launcher
// can build the Ukrainian language pack from its translation's installer as
// downloaded (LanguagePacks.swift).  Players have no innoextract.
//
// Written from the layout of Inno Setup 5.5.0's setup files as innoextract documents
// and reads them, and the LZMA decoder from Igor Pavlov's LZMA specification
// (LzmaSpec.cpp, public domain); no code of either is copied.  Only what the
// translation's installer needs: one file (no setup-*.bin slices), no encryption,
// chunks stored or LZMA1-compressed, files without the x86 call filter.  Every
// file's SHA-1 is checked against its data entry, every header block's CRC32 too.
//
// The installer's end: the loader's offset table ("rDlPtS" ...), which says where the
// setup data (setup-0: an id, then compressed header blocks) and the files (setup-1:
// "zlb\x1a" chunks) start.  Setup-0's first block is the setup header (the [Files]
// list and the rest), its second the data entries: where each file is, in which
// chunk, at what offset of the unpacked chunk, its size and SHA-1.  The [Files] list
// names them in the data entries' order, so a pinned installer's files are known by
// their index.
import Foundation
import CryptoKit

enum InnoSetup {
    struct Failure: Error { let message: String }

    /// Where one file is: its chunk (from setup-1's start), the chunk's packed size,
    /// the file's offset in the unpacked chunk and its size, its SHA-1, its flags.
    struct DataEntry {
        let chunkStart: Int, chunkSize: Int, offset: Int, size: Int
        let sha1: [UInt8]
        let flags: Int
    }
    struct Setup { let files: Int; let entries: [DataEntry] }

    static let tableID: [UInt8] = Array("rDlPtS".utf8) + [0xcd, 0xe6, 0xd7, 0x7b, 0x0b, 0x2a]
    static let ids = ["Inno Setup Setup Data (5.5.0)", "Inno Setup Setup Data (5.5.0) (u)"]
    static let entrySize = 74                     // a 5.5.0 data entry
    static let chunkMagic: [UInt8] = [0x7a, 0x6c, 0x62, 0x1a]   // "zlb\x1a"

    static func le32(_ d: [UInt8], _ o: Int) throws -> Int {
        guard o >= 0, o <= d.count - 4 else { throw Failure(message: "a damaged installer") }
        return Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24
    }
    static func le64(_ d: [UInt8], _ o: Int) throws -> Int {
        let lo = try le32(d, o), hi = try le32(d, o + 4)
        guard hi == 0 else { throw Failure(message: "a damaged installer") }
        return lo
    }
    static func crc32(_ b: ArraySlice<UInt8>) -> UInt32 {
        var c = RarArchive.CRC32()
        b.withUnsafeBytes { c.update($0) }
        return c.value
    }

    /// The installer's setup-1 offset and data entries.
    static func read(_ d: [UInt8]) throws -> Setup {
        // the loader's table: its id, version, total size, the setup exe's offset, size and
        // CRC, setup-0's offset, setup-1's offset, the table's CRC32
        var t = -1, from = 0
        while let i = find(tableID, in: d, from: from) {
            if i + 44 <= d.count, try UInt32(le32(d, i + 40)) == crc32(d[i..<(i + 40)]) { t = i; break }
            from = i + 1
        }
        guard t >= 0 else { throw Failure(message: "not an Inno Setup installer") }
        let total = try le32(d, t + 16), off0 = try le32(d, t + 32), off1 = try le32(d, t + 36)
        guard total == d.count, off0 > 0, off0 <= d.count - 64, off1 > 0, off1 < d.count else {
            throw Failure(message: "an Inno Setup installer in more than one file, or a damaged one")
        }
        let id = String(decoding: d[off0..<(off0 + 64)].prefix { $0 != 0 }, as: UTF8.self)
        guard ids.contains(id) else { throw Failure(message: "an Inno Setup installer of another version (\(id))") }
        let (_, next) = try block(d, off0 + 64, unpack: false)       // the setup header: not needed
        let (e, _) = try block(d, next, unpack: true)
        guard e.count % entrySize == 0 else { throw Failure(message: "an Inno Setup installer of another layout") }
        var out: [DataEntry] = []
        for k in 0..<(e.count / entrySize) {
            let o = k * entrySize
            let first = try le32(e, o), last = try le32(e, o + 4)
            guard first == 0, last == 0 else { throw Failure(message: "an Inno Setup installer in more than one file") }
            let start = try le32(e, o + 8), sub = try le64(e, o + 12), size = try le64(e, o + 20), packed = try le64(e, o + 28)
            let flags = Int(e[o + 72]) | Int(e[o + 73]) << 8
            guard start <= d.count - off1, packed <= d.count - off1 - start else { throw Failure(message: "a damaged installer") }
            out.append(DataEntry(chunkStart: off1 + start, chunkSize: packed, offset: sub, size: size,
                                 sha1: Array(e[(o + 36)..<(o + 56)]), flags: flags))
        }
        return Setup(files: off1, entries: out)
    }

    static func find(_ needle: [UInt8], in d: [UInt8], from: Int) -> Int? {
        guard let first = needle.first, needle.count <= d.count else { return nil }
        var i = max(from, 0)
        while i <= d.count - needle.count {
            if d[i] == first && Array(d[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return nil
    }

    /// One of setup-0's blocks at `at`: CRC32 of the next 5 bytes, its stored size, 1 if
    /// LZMA-compressed; then the stored bytes in pieces of up to 4096, each after its
    /// CRC32.  Its content (unpacked, when asked) and where the next block starts.
    static func block(_ d: [UInt8], _ at: Int, unpack: Bool) throws -> ([UInt8], Int) {
        guard at >= 0, at <= d.count - 9 else { throw Failure(message: "a damaged installer") }
        let crc = try le32(d, at), stored = try le32(d, at + 4), compressed = d[at + 8]
        guard UInt32(crc) == crc32(d[(at + 4)..<(at + 9)]), compressed <= 1, stored <= d.count - at - 9 else {
            throw Failure(message: "a damaged installer")
        }
        let end = at + 9 + stored
        guard unpack else { return ([], end) }
        var raw: [UInt8] = [], p = at + 9
        raw.reserveCapacity(stored)
        while p < end {
            guard end - p > 4 else { throw Failure(message: "a damaged installer") }
            let n = min(4096, end - p - 4)
            guard try UInt32(le32(d, p)) == crc32(d[(p + 4)..<(p + 4 + n)]) else { throw Failure(message: "a damaged installer (CRC)") }
            raw += d[(p + 4)..<(p + 4 + n)]
            p += 4 + n
        }
        guard compressed == 1 else { return (raw, end) }
        guard raw.count >= 5 else { throw Failure(message: "a damaged installer") }
        return (try LZMA.decode(Array(raw[5...]), props: Array(raw[0..<5]), size: nil), end)
    }

    /// The file of data entry i, its SHA-1 checked.
    static func file(_ d: [UInt8], _ e: DataEntry) throws -> Data {
        guard e.flags & 0x40 == 0 else { throw Failure(message: "an encrypted installer") }
        guard e.flags & 0x10 == 0 else { throw Failure(message: "a file with the x86 call filter, which this reader does not undo") }
        let p = e.chunkStart
        guard p <= d.count - 4 - e.chunkSize, Array(d[p..<(p + 4)]) == chunkMagic else { throw Failure(message: "a damaged installer (no chunk)") }
        let c = Array(d[(p + 4)..<(p + 4 + e.chunkSize)])
        guard e.offset <= Int(Int32.max), e.size <= Int(Int32.max) else { throw Failure(message: "a damaged installer") }
        let need = e.offset + e.size
        let out: [UInt8]
        if e.flags & 0x80 != 0 {
            guard c.count >= 5 else { throw Failure(message: "a damaged installer") }
            out = try LZMA.decode(Array(c[5...]), props: Array(c[0..<5]), size: need)
        } else {
            out = c
        }
        guard out.count >= need else { throw Failure(message: "a damaged installer (a file cut short)") }
        let f = Array(out[e.offset..<need])
        guard Array(Insecure.SHA1.hash(data: f)) == e.sha1 else { throw Failure(message: "a damaged installer (SHA-1)") }
        return Data(f)
    }
}

/// LZMA (LZMA1, raw: its 5 property bytes given apart, no .lzma or .xz header), as
/// Igor Pavlov's specification describes its decoder.  size: stop after that many bytes;
/// nil: decode until the end marker or until the input is used up.
enum LZMA {
    static let maxOutput = 256 << 20

    static func decode(_ input: [UInt8], props: [UInt8], size: Int?) throws -> [UInt8] {
        guard props.count == 5, props[0] < 9 * 5 * 5 else { throw InnoSetup.Failure(message: "unknown LZMA properties") }
        let d = Decoder(input, lc: Int(props[0] % 9), lp: Int(props[0] / 9 % 5), pb: Int(props[0] / 45))
        try d.run(size: size)
        return d.out
    }

    // the probabilities, in one array
    static let isMatch = 0, isRep = 192, isRepG0 = 204, isRepG1 = 216, isRepG2 = 228, isRep0Long = 240
    static let posSlot = 432, specPos = 688, align = 803, lenCoder = 819, repLenCoder = 1333, literal = 1847

    final class Decoder {
        let inp: [UInt8]
        var ip = 0
        var range: UInt32 = 0xffff_ffff, code: UInt32 = 0
        var p: [UInt16]
        var out: [UInt8] = []
        let lc: Int, lp: Int, pb: Int

        init(_ input: [UInt8], lc: Int, lp: Int, pb: Int) {
            inp = input; self.lc = lc; self.lp = lp; self.pb = pb
            p = [UInt16](repeating: 1024, count: LZMA.literal + (0x300 << (lc + lp)))
        }

        @inline(__always) func next() -> UInt32 {
            defer { ip += 1 }
            return ip < inp.count ? UInt32(inp[ip]) : 0
        }
        @inline(__always) func normalize() {
            if range < 1 << 24 { range <<= 8; code = code << 8 | next() }
        }
        @inline(__always) func bit(_ i: Int) -> Int {
            let v = UInt32(p[i]), bound = (range >> 11) &* v
            let r: Int
            if code < bound { range = bound; p[i] = UInt16(v + ((2048 - v) >> 5)); r = 0 }
            else { range &-= bound; code &-= bound; p[i] = UInt16(v - (v >> 5)); r = 1 }
            normalize()
            return r
        }
        func tree(_ base: Int, _ bits: Int) -> Int {
            var m = 1
            for _ in 0..<bits { m = m << 1 + bit(base + m) }
            return m - (1 << bits)
        }
        func reverse(_ base: Int, _ bits: Int) -> Int {
            var m = 1, s = 0
            for i in 0..<bits { let b = bit(base + m); m = m << 1 + b; s |= b << i }
            return s
        }
        func direct(_ bits: Int) throws -> Int {
            var r: UInt32 = 0
            for _ in 0..<bits {
                range >>= 1; code &-= range
                let t = 0 &- (code >> 31)
                code &+= range & t
                if code == range { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
                normalize()
                r = r << 1 &+ (t &+ 1)
            }
            return Int(r)
        }
        func length(_ base: Int, _ posState: Int) -> Int {
            if bit(base) == 0 { return tree(base + 2 + posState << 3, 3) }
            if bit(base + 1) == 0 { return 8 + tree(base + 2 + 128 + posState << 3, 3) }
            return 16 + tree(base + 2 + 256, 8)
        }
        func distance(_ len: Int) throws -> Int {
            let slot = tree(LZMA.posSlot + min(len, 3) << 6, 6)
            if slot < 4 { return slot }
            let bits = slot >> 1 - 1
            var dist = (2 | slot & 1) << bits
            if slot < 14 { dist += reverse(LZMA.specPos + dist - slot, bits) }
            else { dist += try direct(bits - 4) << 4; dist += reverse(LZMA.align, 4) }
            return dist
        }

        func run(size: Int?) throws {
            guard inp.count >= 5, inp[0] == 0 else { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
            ip = 1
            for _ in 0..<4 { code = code << 8 | next() }
            if code == range { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
            let limit = min(size ?? LZMA.maxOutput, LZMA.maxOutput)
            out.reserveCapacity(size ?? inp.count * 4)
            var state = 0, rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0
            let pbMask = (1 << pb) - 1, lpMask = (1 << lp) - 1
            while out.count < limit {
                if size == nil && ip == inp.count { return }              // the input used up
                if ip > inp.count { throw InnoSetup.Failure(message: "a damaged LZMA stream (cut short)") }
                let posState = out.count & pbMask
                if bit(LZMA.isMatch + state << 4 + posState) == 0 {
                    let prev = Int(out.last ?? 0)
                    let base = LZMA.literal + 0x300 * ((out.count & lpMask) << lc + prev >> (8 - lc))
                    var s = 1
                    if state >= 7 {
                        guard rep0 < out.count else { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
                        var match = Int(out[out.count - rep0 - 1])
                        while s < 0x100 {
                            let mb = match >> 7 & 1
                            match <<= 1
                            let b = bit(base + (1 + mb) << 8 + s)
                            s = s << 1 | b
                            if mb != b { break }
                        }
                    }
                    while s < 0x100 { s = s << 1 | bit(base + s) }
                    out.append(UInt8(s - 0x100))
                    state = state < 4 ? 0 : state < 10 ? state - 3 : state - 6
                    continue
                }
                var len: Int
                if bit(LZMA.isRep + state) != 0 {
                    guard !out.isEmpty else { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
                    if bit(LZMA.isRepG0 + state) == 0 {
                        if bit(LZMA.isRep0Long + state << 4 + posState) == 0 {
                            state = state < 7 ? 9 : 11
                            guard rep0 < out.count else { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
                            out.append(out[out.count - rep0 - 1])
                            continue
                        }
                    } else {
                        let dist: Int
                        if bit(LZMA.isRepG1 + state) == 0 { dist = rep1 }
                        else {
                            if bit(LZMA.isRepG2 + state) == 0 { dist = rep2 } else { dist = rep3; rep3 = rep2 }
                            rep2 = rep1
                        }
                        rep1 = rep0; rep0 = dist
                    }
                    len = length(LZMA.repLenCoder, posState)
                    state = state < 7 ? 8 : 11
                } else {
                    rep3 = rep2; rep2 = rep1; rep1 = rep0
                    len = length(LZMA.lenCoder, posState)
                    state = state < 7 ? 7 : 10
                    rep0 = try distance(len)
                    if rep0 == 0xffff_ffff {                             // the end marker
                        if ip > inp.count { throw InnoSetup.Failure(message: "a damaged LZMA stream (cut short)") }
                        return
                    }
                }
                len += 2
                guard rep0 < out.count else { throw InnoSetup.Failure(message: "a damaged LZMA stream") }
                for _ in 0..<len where out.count < limit { out.append(out[out.count - rep0 - 1]) }
            }
            if size == nil { throw InnoSetup.Failure(message: "an LZMA stream larger than expected") }
        }
    }
}
