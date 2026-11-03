// Clickteam Patch Maker patches, read, never run: the files of one, in Swift, so the
// launcher can build the Czech language pack from its translation's patch as
// downloaded (LanguagePacks.swift).
//
// Worked out from the patch program itself (its own code, disassembled; nothing of it
// is copied).  Only what the translation's patch needs: files carried whole (not as
// differences to the old file), in one piece (no disks).
//
// The program's sections end where the patch starts: blocks of { id (2 bytes), flags
// (2), size (4), data }, up to the one with id 0x7f7f, whose data (its size, then the
// files' data) runs to the end.  A block with flags bit 0 is compressed: its size
// unpacked (4 bytes), then the data in Clickteam's own deflate, which is RFC 1951's but
// with each block's header 4 bits (the type in the low 3: 5 fixed codes, 6 dynamic, 7
// stored; then the last-block bit), the code length codes in the order 18, 17, 16, 0,
// 1, ... 15, and a stored block's length without its complement.  Block 0x1238 is
// the patch's title, 0x1242 its file list: a count, then a record per file:
//   0x00 its size        0x08 flags (bit 1: the file carried whole)
//   0x0a the new file's checksum   0x0e its size
//   0x14 how many old versions it replaces   0x16 where their list is in the record
//   0x36 the file's path in the game folder, 0-terminated
// and per old version (16 bytes): its checksum (xor a key the program makes from its
// own code), its size, where its data starts in block 0x7f7f's (after its size) and
// how long it is.  A file carried whole is its data compressed as a block's is.  The
// checksum: for each 4 bytes (little-endian) the sum so far turned left by one bit
// plus them; the 1-3 bytes left after the last 4 one at a time, the same way.
import Foundation

enum Clickteam {
    struct Failure: Error { let message: String }

    struct Version { let sum: UInt32, size: Int, offset: Int, length: Int }
    struct Entry { let path: String, flags: Int, sum: UInt32, size: Int, versions: [Version] }
    struct Patch { let title: String; let entries: [Entry]; let data: Int }   // data: block 0x7f7f's files' data in the patch

    static let fileList = 0x1242, title = 0x1238, lastBlock = 0x7f7f
    static let maxFile = 64 << 20

    static func le16(_ d: [UInt8], _ o: Int) throws -> Int {
        guard o >= 0, o <= d.count - 2 else { throw Failure(message: "a damaged patch") }
        return Int(d[o]) | Int(d[o + 1]) << 8
    }
    static func le32(_ d: [UInt8], _ o: Int) throws -> Int {
        guard o >= 0, o <= d.count - 4 else { throw Failure(message: "a damaged patch") }
        return Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24
    }

    /// the patch program's checksum of a file
    static func checksum(_ b: [UInt8]) -> UInt32 {
        var h: UInt32 = 0, i = 0
        b.withUnsafeBufferPointer { p in
            while i + 4 <= p.count {
                let w = UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24
                h = (h << 1 | h >> 31) &+ w; i += 4
            }
            while i < p.count { h = (h << 1 | h >> 31) &+ UInt32(p[i]); i += 1 }
        }
        return h
    }

    /// Where the patch starts: the end of the program's sections.
    static func start(_ d: [UInt8]) throws -> Int {
        guard d.count > 0x40, d[0] == 0x4d, d[1] == 0x5a else { throw Failure(message: "not a Windows program") }
        let pe = try le32(d, 0x3c)
        guard pe > 0, pe <= d.count - 24, d[pe] == 0x50, d[pe + 1] == 0x45, d[pe + 2] == 0, d[pe + 3] == 0 else {
            throw Failure(message: "not a Windows program")
        }
        let n = try le16(d, pe + 6), opt = try le16(d, pe + 20)
        guard n > 0, n <= 96 else { throw Failure(message: "a damaged patch") }
        var end = 0
        for i in 0..<n {
            let s = pe + 24 + opt + 40 * i
            end = max(end, try le32(d, s + 20) + le32(d, s + 16))
        }
        guard end > 0, end <= d.count - 8 else { throw Failure(message: "not a Clickteam patch") }
        return end
    }

    /// The patch's title and files.
    static func read(_ d: [UInt8]) throws -> Patch {
        var p = try start(d), title = "", list: [UInt8]? = nil
        while true {
            let id = try le16(d, p), flags = try le16(d, p + 2), size = try le32(d, p + 4)
            guard size >= 0, size <= d.count - p - 8 else { throw Failure(message: "not a Clickteam patch (a block runs past its end)") }
            if id == lastBlock {
                guard size >= 4 else { throw Failure(message: "a damaged patch") }
                guard let l = list else { throw Failure(message: "the patch has no file list") }
                return Patch(title: title, entries: try entries(l), data: p + 12)
            }
            guard id >= 0x1234, id <= 0x1250 else { throw Failure(message: "not a Clickteam patch (block \(String(id, radix: 16)))") }
            if id == fileList || id == Clickteam.title {
                var body = Array(d[(p + 8)..<(p + 8 + size)])
                if flags & 1 != 0 {
                    let n = try le32(body, 0)
                    guard n <= 1 << 20 else { throw Failure(message: "a damaged patch") }
                    body = try inflate(body[4...], size: n)
                }
                if id == fileList { list = body }
                else { title = String(data: Data(body.prefix { $0 != 0 }), encoding: .windowsCP1250) ?? "" }
            }
            p += 8 + size
        }
    }

    static func entries(_ l: [UInt8]) throws -> [Entry] {
        let n = try le32(l, 0)
        guard n <= 1000 else { throw Failure(message: "a damaged file list") }
        var out: [Entry] = [], q = 4
        for _ in 0..<n {
            let size = try le32(l, q)
            guard size >= 0x37, size <= l.count - q else { throw Failure(message: "a damaged file list") }
            let r = Array(l[q..<(q + size)])
            let count = try le16(r, 0x14), at = try le16(r, 0x16)
            var versions: [Version] = []
            for k in 0..<count {
                let v = at + 16 * k
                versions.append(Version(sum: UInt32(try le32(r, v)), size: try le32(r, v + 4),
                                        offset: try le32(r, v + 8), length: try le32(r, v + 12)))
            }
            let name = r[0x36...].prefix { $0 != 0 }
            guard name.count < r.count - 0x36 else { throw Failure(message: "a damaged file list") }
            out.append(Entry(path: String(decoding: name.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self),
                             flags: try le16(r, 8), sum: UInt32(try le32(r, 0x0a)), size: try le32(r, 0x0e), versions: versions))
            q += size
        }
        return out
    }

    /// A file the patch carries whole, its size and checksum checked.
    static func file(_ d: [UInt8], _ patch: Patch, _ e: Entry) throws -> Data {
        guard e.flags & 2 != 0, let v = e.versions.first else { throw Failure(message: "\(e.path): not a file the patch carries whole") }
        guard e.size >= 0, e.size <= maxFile, v.offset >= 0, v.length > 0, v.offset <= d.count - patch.data,
              v.length <= d.count - patch.data - v.offset else { throw Failure(message: "\(e.path): a damaged patch") }
        let out = try inflate(d[(patch.data + v.offset)..<(patch.data + v.offset + v.length)], size: e.size)
        guard checksum(out) == e.sum else { throw Failure(message: "\(e.path): its checksum is wrong (a damaged patch)") }
        return Data(out)
    }

    // MARK: Clickteam's deflate

    struct Bits {
        let s: ArraySlice<UInt8>
        var p: Int, b: UInt32 = 0, n = 0
        init(_ s: ArraySlice<UInt8>) { self.s = s; p = s.startIndex }
        mutating func get(_ k: Int) throws -> Int {
            while n < k {
                guard p < s.endIndex else { throw Failure(message: "a compressed stream cut short (a damaged patch)") }
                b |= UInt32(s[p]) << UInt32(n); p += 1; n += 8
            }
            let v = Int(b & ((1 << UInt32(k)) - 1))
            b = k == 32 ? 0 : b >> UInt32(k); n -= k
            return v
        }
    }
    /// a canonical Huffman code: how many codes of each length, the symbols in code order
    struct Huffman {
        var count = [Int](repeating: 0, count: 16), symbol: [Int] = []
        init(_ lengths: [Int]) throws {
            for l in lengths { count[l] += 1 }
            var left = 1
            for l in 1...15 {
                left = left << 1 - count[l]
                guard left >= 0 else { throw Failure(message: "a damaged compressed stream") }   // over-subscribed
            }
            var offs = [Int](repeating: 0, count: 16)
            for l in 1..<15 { offs[l + 1] = offs[l] + count[l] }
            symbol = [Int](repeating: 0, count: lengths.count)
            for (s, l) in lengths.enumerated() where l != 0 { symbol[offs[l]] = s; offs[l] += 1 }
        }
        func decode(_ bits: inout Bits) throws -> Int {
            var code = 0, first = 0, index = 0
            for l in 1...15 {
                code |= try bits.get(1)
                let c = count[l]
                if code - c < first { return symbol[index + code - first] }
                index += c; first = (first + c) << 1; code <<= 1
            }
            throw Failure(message: "a damaged compressed stream")
        }
    }
    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                           4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let order = [18, 17, 16] + Array(0...15)
    static let fixed: (Huffman, Huffman) = (try! Huffman([Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112)
                                                         + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)),
                                            try! Huffman([Int](repeating: 5, count: 30)))

    /// A stream of Clickteam's deflate, unpacked to its size: refused if it ends
    /// before, says more, or refers back past its start.
    static func inflate(_ src: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        guard size >= 0, size <= maxFile else { throw Failure(message: "a damaged patch") }
        var bits = Bits(src), out: [UInt8] = []
        out.reserveCapacity(size)
        while out.count < size {
            let head = try bits.get(4), type = head & 7, last = head & 8 != 0
            switch type {
            case 7:
                _ = try bits.get(bits.n & 7)
                let n = try bits.get(16)
                guard out.count + n <= size else { throw Failure(message: "a compressed stream longer than its file") }
                for _ in 0..<n { out.append(UInt8(try bits.get(8))) }
            case 5, 6:
                var codes = fixed
                if type == 6 {
                    let nlen = try bits.get(5) + 257, ndist = try bits.get(5) + 1, ncode = try bits.get(4) + 4
                    guard nlen <= 286, ndist <= 30 else { throw Failure(message: "a damaged compressed stream") }
                    var cl = [Int](repeating: 0, count: 19)
                    for i in 0..<ncode { cl[order[i]] = try bits.get(3) }
                    let lc = try Huffman(cl)
                    var lengths: [Int] = []
                    while lengths.count < nlen + ndist {
                        let s = try lc.decode(&bits)
                        var rep = 0, v = 0
                        switch s {
                        case 0...15: lengths.append(s); continue
                        case 16:
                            guard let prev = lengths.last else { throw Failure(message: "a damaged compressed stream") }
                            v = prev; rep = 3 + (try bits.get(2))
                        case 17: rep = 3 + (try bits.get(3))
                        default: rep = 11 + (try bits.get(7))
                        }
                        guard lengths.count + rep <= nlen + ndist else { throw Failure(message: "a damaged compressed stream") }
                        lengths += [Int](repeating: v, count: rep)
                    }
                    codes = (try Huffman(Array(lengths[0..<nlen])), try Huffman(Array(lengths[nlen...])))
                }
                while true {
                    let s = try codes.0.decode(&bits)
                    if s < 256 {
                        guard out.count < size else { throw Failure(message: "a compressed stream longer than its file") }
                        out.append(UInt8(s))
                    } else if s == 256 {
                        break
                    } else {
                        let li = s - 257
                        guard li < lengthBase.count else { throw Failure(message: "a damaged compressed stream") }
                        let len = lengthBase[li] + (try bits.get(lengthExtra[li]))
                        let di = try codes.1.decode(&bits)
                        guard di < distBase.count else { throw Failure(message: "a damaged compressed stream") }
                        let dist = distBase[di] + (try bits.get(distExtra[di]))
                        guard dist <= out.count, dist <= 32768 else { throw Failure(message: "a damaged compressed stream") }
                        guard out.count + len <= size else { throw Failure(message: "a compressed stream longer than its file") }
                        let from = out.count - dist
                        for k in 0..<len { out.append(out[from + k]) }
                    }
                }
            default:
                throw Failure(message: "a damaged compressed stream (block type \(type))")
            }
            if last { break }
        }
        guard out.count == size else { throw Failure(message: "a compressed stream shorter than its file") }
        return out
    }
}
