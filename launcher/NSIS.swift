// NSIS (Nullsoft) installers, read, never run: the files of one, in Swift, so the
// launcher can build the Slovak language pack from its translation's installer as
// downloaded (LanguagePacks.swift).  Players have no 7-Zip.
//
// Written from the NSIS 2 installer layout as 7-Zip documents and reads it, and the
// bzip2 format as its specification and Julian Seward's decoder describe it; no code
// of either is copied.  Only what the translation's installer needs: NSIS 2, files
// compressed one by one (not solid) with NSIS's bzip2, which is bzip2 without the
// stream header ("BZh"), the CRCs and the randomised bit: a block starts with the byte
// 0x31 (bzip2's 0x314159265359) and its origPtr, the stream ends with 0x17 (its
// 0x177245385090), blocks of up to 900 000 bytes.
//
// The installer's data follow its program: the first header (flags, 0xdeadbeef,
// "NullsoftInst", the header's size, the size of all that follows), then the script
// header and the files, each as its size (bit 31: compressed) and its data.  The
// script names them in the data's order, so a pinned installer's files are known by
// their index; every one the launcher takes is checked against its SHA-256 by the
// caller.
import Foundation

enum NSIS {
    struct Failure: Error { let message: String }
    struct Entry { let offset: Int, size: Int, compressed: Bool }

    static let magic: [UInt8] = [0xef, 0xbe, 0xad, 0xde] + Array("NullsoftInst".utf8)
    static let maxFile = 64 << 20

    static func le32(_ d: [UInt8], _ o: Int) throws -> Int {
        guard o >= 0, o <= d.count - 4 else { throw Failure(message: "a damaged installer") }
        return Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24
    }

    /// The installer's data entries after its script header, in order.
    static func entries(_ d: [UInt8]) throws -> [Entry] {
        var at = -1, i = 0x200
        while i + 28 <= d.count {          // the first header sits at a 512-byte boundary
            if Array(d[(i + 4)..<(i + 20)]) == magic { at = i; break }
            i += 0x200
        }
        guard at >= 0 else { throw Failure(message: "not an NSIS installer") }
        let total = try le32(d, at + 24)
        guard total >= 32, total <= d.count - at else { throw Failure(message: "a damaged installer") }
        let end = at + total - 4                                   // a CRC32 ends it
        let head = try le32(d, at + 28) & 0x7fff_ffff
        var p = at + 32 + head, out: [Entry] = []
        guard p <= end else { throw Failure(message: "a damaged installer") }
        while p + 4 <= end {
            let w = try le32(d, p), n = w & 0x7fff_ffff
            guard n <= end - p - 4 else { break }                  // what follows the files (the uninstaller's data)
            out.append(Entry(offset: p + 4, size: n, compressed: w & 0x8000_0000 != 0))
            p += 4 + n
        }
        return out
    }

    /// An entry's file, unpacked.
    static func file(_ d: [UInt8], _ e: Entry) throws -> [UInt8] {
        guard e.offset >= 0, e.size >= 0, e.offset <= d.count - e.size else { throw Failure(message: "a damaged installer") }
        let s = d[e.offset..<(e.offset + e.size)]
        return e.compressed ? try bunzip(s) : Array(s)
    }

    // MARK: NSIS's bzip2

    struct Bits {           // most significant bit first
        let s: ArraySlice<UInt8>
        var p: Int, b: UInt64 = 0, n = 0
        init(_ s: ArraySlice<UInt8>) { self.s = s; p = s.startIndex }
        mutating func get(_ k: Int) throws -> Int {
            while n < k {
                guard p < s.endIndex else { throw Failure(message: "a compressed file cut short (a damaged installer)") }
                b = b << 8 | UInt64(s[p]); p += 1; n += 8
            }
            n -= k
            return Int(b >> UInt64(n) & ((1 << UInt64(k)) - 1))
        }
    }

    /// One NSIS bzip2 stream, unpacked.
    static func bunzip(_ src: ArraySlice<UInt8>) throws -> [UInt8] {
        var bits = Bits(src), out: [UInt8] = []
        func bad(_ what: String = "a damaged compressed file") -> Failure { Failure(message: what) }
        while true {
            let mark = try bits.get(8)
            if mark == 0x17 { break }
            guard mark == 0x31 else { throw bad() }
            let origPtr = try bits.get(24)                      // (NSIS's has no randomised bit before it)
            // the bytes the block uses
            var seq: [UInt8] = []
            let used16 = try bits.get(16)
            for i in 0..<16 where used16 & (0x8000 >> i) != 0 {
                let w = try bits.get(16)
                for j in 0..<16 where w & (0x8000 >> j) != 0 { seq.append(UInt8(i * 16 + j)) }
            }
            guard !seq.isEmpty else { throw bad() }
            let alpha = seq.count + 2, groups = try bits.get(3), nsel = try bits.get(15)
            guard groups >= 2, groups <= 6, nsel >= 1 else { throw bad() }
            var mtfG = Array(0..<groups), selectors: [Int] = []
            selectors.reserveCapacity(nsel)
            for _ in 0..<nsel {
                var j = 0
                while try bits.get(1) == 1 { j += 1; guard j < groups else { throw bad() } }
                let g = mtfG.remove(at: j); mtfG.insert(g, at: 0); selectors.append(g)
            }
            // each group's code: lengths as deltas, then (limit, base, symbols) by length
            var tables: [(minLen: Int, limit: [Int], base: [Int], perm: [Int])] = []
            for _ in 0..<groups {
                var len = [Int](repeating: 0, count: alpha), cur = try bits.get(5)
                for i in 0..<alpha {
                    while true {
                        guard cur >= 1, cur <= 20 else { throw bad() }
                        if try bits.get(1) == 0 { break }
                        cur += try bits.get(1) == 0 ? 1 : -1
                    }
                    len[i] = cur
                }
                let lo = len.min()!, hi = len.max()!
                var perm: [Int] = [], limit = [Int](repeating: -1, count: 22), base = [Int](repeating: 0, count: 22)
                for l in lo...hi { for (s, x) in len.enumerated() where x == l { perm.append(s) } }
                var code = 0, idx = 0
                for l in lo...hi {
                    let c = len.filter { $0 == l }.count
                    base[l] = idx - code                 // symbol index = code + base[l]
                    code += c; idx += c
                    limit[l] = code - 1
                    code <<= 1
                }
                tables.append((lo, limit, base, perm))
            }
            // the symbols: runs of the first (RUNA, RUNB), move-to-front indices, end of block
            var mtf = Array(0..<seq.count).map { UInt8($0) }, block: [UInt8] = [], counts = [Int](repeating: 0, count: 256)
            var run = 0, weight = 1, sel = 0, left = 0
            let eob = seq.count + 1
            func flush() throws {
                guard run > 0 else { return }
                guard block.count + run <= 900_000 else { throw bad() }
                let b = seq[Int(mtf[0])]
                block += [UInt8](repeating: b, count: run); counts[Int(b)] += run
                run = 0; weight = 1
            }
            while true {
                if left == 0 {
                    guard sel < selectors.count else { throw bad() }
                    left = 50; sel += 1
                }
                left -= 1
                let t = tables[selectors[sel - 1]]
                var l = t.minLen, v = try bits.get(l)
                while l <= 20 && v > t.limit[l] { v = v << 1 | (try bits.get(1)); l += 1 }
                guard l <= 20 else { throw bad() }
                let si = v + t.base[l]
                guard si >= 0, si < t.perm.count else { throw bad() }
                let s = t.perm[si]
                if s <= 1 {                                         // RUNA 1, RUNB 2 (times the weight)
                    run += (s + 1) * weight; weight <<= 1
                    guard run <= 900_000 else { throw bad() }
                    continue
                }
                try flush()
                if s == eob { break }
                let k = s - 1
                guard k < mtf.count else { throw bad() }
                let m = mtf.remove(at: k); mtf.insert(m, at: 0)
                guard block.count < 900_000 else { throw bad() }
                let b = seq[Int(m)]
                block.append(b); counts[Int(b)] += 1
            }
            guard origPtr < block.count else { throw bad() }
            // the Burrows-Wheeler transform undone
            var start = [Int](repeating: 0, count: 256), sum = 0
            for c in 0..<256 { start[c] = sum; sum += counts[c] }
            var next = [Int](repeating: 0, count: block.count)
            for (i, b) in block.enumerated() { next[start[Int(b)]] = i; start[Int(b)] += 1 }
            var p = next[origPtr], plain: [UInt8] = []
            plain.reserveCapacity(block.count)
            for _ in 0..<block.count { plain.append(block[p]); p = next[p] }
            // the first run-length coding undone: 4 equal bytes, then how many more
            var i = 0, last = -1, same = 0
            while i < plain.count {
                let b = plain[i]; i += 1
                out.append(b)
                if Int(b) == last { same += 1 } else { last = Int(b); same = 1 }
                if same == 4 {
                    guard i < plain.count else { throw bad() }
                    let more = Int(plain[i]); i += 1
                    out += [UInt8](repeating: b, count: more)
                    same = 0; last = -1
                }
                guard out.count <= maxFile else { throw bad("a compressed file larger than expected") }
            }
        }
        return out
    }
}
