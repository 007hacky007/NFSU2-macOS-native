// RAR 5 and RAR 7 archives: their files listed and unpacked, in Swift, so the
// launcher can read the language packs' mod archives itself (LanguagePacks.swift).
// macOS's bsdtar lists them but cannot unpack RAR 7's compression ("v6" in 7-Zip's
// listing: the Multi 13 languages mod's archives use it); players have no unrar.
//
// Written from the RAR 5.0 archive format description (rarlab.com, "RAR 5.0 archive
// format") and the public behaviour of the format; no code of unrar is used.  Only
// what the mods need: one volume, no encryption, methods store and 1-5 (LZ with
// Huffman tables), solid archives, the DELTA, E8, E8E9 and ARM filters.  Every
// file's CRC32 is checked against its header.
import Foundation

enum RarArchive {
    struct Failure: Error { let message: String }

    struct Entry {
        let name: String            // with "/" between folders
        let isDirectory: Bool
        let size: UInt64
        let crc: UInt32?
        let dataOffset: Int
        let packedSize: Int
        let algorithm: Int          // 0: RAR 5, 1: RAR 7 (longer distances)
        let solid: Bool
        let method: Int             // 0 = stored
        let dictionary: UInt64
        let encrypted: Bool
    }

    /// The archive's files, in their order.  A malformed archive throws: every read
    /// stays inside its header, and every header inside the archive.
    static func list(_ bytes: UnsafeRawBufferPointer) throws -> [Entry] {
        let sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]
        guard bytes.count >= 8, Array(bytes[0..<8]) == sig else {
            throw Failure(message: "not a RAR 5 archive")
        }
        var out: [Entry] = []
        var pos = 8
        while pos + 7 <= bytes.count {
            var p = pos + 4                                   // header CRC32
            let headerSize = try int(try vint(bytes, &p, end: bytes.count))
            let headerStart = p
            guard headerSize > 0, headerSize <= bytes.count - headerStart else { throw Failure(message: "damaged header") }
            let hend = headerStart + headerSize               // reads stay below this
            let type = try vint(bytes, &p, end: hend)
            let flags = try vint(bytes, &p, end: hend)
            var extraSize = 0, dataSize = 0
            if flags & 1 != 0 { extraSize = try int(try vint(bytes, &p, end: hend)) }
            if flags & 2 != 0 { dataSize = try int(try vint(bytes, &p, end: hend)) }
            guard extraSize <= headerSize else { throw Failure(message: "damaged header") }
            let dataStart = hend
            guard dataSize <= bytes.count - dataStart else { throw Failure(message: "the archive is cut short") }
            switch type {
            case 1:                                           // main archive header
                let aflags = try vint(bytes, &p, end: hend)
                if aflags & 1 != 0 { throw Failure(message: "a multi-volume archive") }
            case 4:
                throw Failure(message: "an encrypted archive")
            case 2:                                           // file
                let fflags = try vint(bytes, &p, end: hend)
                let size = try vint(bytes, &p, end: hend)
                _ = try vint(bytes, &p, end: hend)            // attributes
                if fflags & 2 != 0 { _ = try u32(bytes, &p, end: hend) }   // mtime
                var crc: UInt32? = nil
                if fflags & 4 != 0 { crc = try u32(bytes, &p, end: hend) }
                let ci = try vint(bytes, &p, end: hend)
                _ = try vint(bytes, &p, end: hend)            // host OS
                let nameLen = try int(try vint(bytes, &p, end: hend))
                guard nameLen <= hend - p else { throw Failure(message: "damaged file header") }
                let name = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[p..<(p + nameLen)]), as: UTF8.self)
                p += nameLen
                // the extra area: an encryption record (type 1) means a password
                var encrypted = false
                if extraSize > 0 {
                    var e = hend - extraSize
                    guard e >= p else { throw Failure(message: "damaged file header") }
                    while e < hend {
                        let recSize = try int(try vint(bytes, &e, end: hend)), recStart = e
                        guard recSize > 0, recSize <= hend - recStart else { throw Failure(message: "damaged file header") }
                        let recType = try vint(bytes, &e, end: recStart + recSize)
                        if recType == 1 { encrypted = true }
                        e = recStart + recSize                 // always moves on
                    }
                }
                let algo = Int(ci & 0x3f)
                var dict = UInt64(0x20000) << ((ci >> 10) & 0x1f)
                if algo == 1 { dict += dict / 32 * ((ci >> 15) & 0x1f) }
                out.append(Entry(name: name, isDirectory: fflags & 1 != 0, size: size, crc: crc,
                                 dataOffset: dataStart, packedSize: dataSize, algorithm: algo,
                                 solid: ci & 0x40 != 0, method: Int((ci >> 7) & 7), dictionary: dict,
                                 encrypted: encrypted))
            case 5:
                return out
            default:
                break                                         // service headers (comments...)
            }
            pos = dataStart + dataSize
        }
        return out
    }

    /// Unpacks the files in order (a solid archive needs every one before a file):
    /// `sink` gets each file and says where its bytes go (nil: nowhere).
    static func extract(_ bytes: UnsafeRawBufferPointer, entries: [Entry],
                        sink: (Entry) throws -> ((UnsafeRawBufferPointer) throws -> Void)?) throws {
        var unpacker: Unpacker? = nil
        defer { unpacker?.free() }
        let window = entries.filter { $0.method != 0 && !$0.isDirectory }.map { $0.dictionary }.max() ?? 0
        for e in entries where !e.isDirectory {
            if e.encrypted { throw Failure(message: "\(e.name) needs a password") }
            if e.algorithm > 1 { throw Failure(message: "\(e.name) uses a compression newer than RAR 7") }
            let write = try sink(e)
            var crc = CRC32()
            let out: (UnsafeRawBufferPointer) throws -> Void = { b in
                crc.update(b)
                try write?(b)
            }
            guard e.dataOffset >= 0, e.packedSize >= 0, e.dataOffset <= bytes.count, e.packedSize <= bytes.count - e.dataOffset else {
                throw Failure(message: "\(e.name) lies outside the archive")
            }
            let packed = UnsafeRawBufferPointer(rebasing: bytes[e.dataOffset..<(e.dataOffset + e.packedSize)])
            var produced: UInt64 = 0
            if e.method == 0 {
                try out(packed)
                produced = UInt64(packed.count)
            } else {
                if unpacker == nil { unpacker = try Unpacker(window: window) }
                produced = try unpacker!.unpack(packed, size: e.size, solid: e.solid,
                                                extraDist: e.algorithm == 1, output: out)
            }
            guard produced == e.size else { throw Failure(message: "\(e.name): \(produced) bytes unpacked, \(e.size) expected") }
            if let want = e.crc, crc.value != want { throw Failure(message: "\(e.name) is damaged (CRC mismatch)") }
        }
    }

    // MARK: helpers

    /// a variable-length number at p, below end
    static func vint(_ b: UnsafeRawBufferPointer, _ p: inout Int, end: Int) throws -> UInt64 {
        var v: UInt64 = 0, shift: UInt64 = 0
        let stop = min(end, b.count)
        guard p >= 0 else { throw Failure(message: "damaged header") }
        while p < stop {
            let x = b[p]; p += 1
            v |= UInt64(x & 0x7f) << shift
            if x & 0x80 == 0 { return v }
            shift += 7
            if shift > 63 { break }
        }
        throw Failure(message: "damaged header")
    }
    static func u32(_ b: UnsafeRawBufferPointer, _ p: inout Int, end: Int) throws -> UInt32 {
        guard p >= 0, p + 4 <= min(end, b.count) else { throw Failure(message: "damaged header") }
        let v = UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24
        p += 4
        return v
    }
    /// a size or offset that fits an Int
    static func int(_ v: UInt64) throws -> Int {
        guard v <= UInt64(Int32.max) * 64 else { throw Failure(message: "damaged header") }
        return Int(v)
    }

    struct CRC32 {
        static let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = c & 1 != 0 ? 0xedb8_8320 ^ (c >> 1) : c >> 1 }
            return c
        }
        private var c: UInt32 = 0xffff_ffff
        var value: UInt32 { c ^ 0xffff_ffff }
        mutating func update(_ b: UnsafeRawBufferPointer) {
            var x = c
            CRC32.table.withUnsafeBufferPointer { t in
                for byte in b { x = t[Int((x ^ UInt32(byte)) & 0xff)] ^ (x >> 8) }
            }
            c = x
        }
    }

    // MARK: the LZ decoder

    /// One Huffman table: 15-bit lookup, entry = symbol << 4 | code length (0: no code).
    struct Table {
        var lookup = [UInt16](repeating: 0, count: 1 << 15)
        mutating func build(_ lengths: ArraySlice<UInt8>) throws {
            var count = [Int](repeating: 0, count: 16)
            for l in lengths { count[Int(l)] += 1 }
            count[0] = 0
            var next = [Int](repeating: 0, count: 16)
            var code = 0
            for l in 1..<16 { code = (code + count[l - 1]) << 1; next[l] = code }
            for i in 0..<lookup.count { lookup[i] = 0 }
            var sym = 0
            for l in lengths {
                let len = Int(l)
                if len > 0 {
                    let c = next[len]; next[len] += 1
                    let from = c << (15 - len), to = (c + 1) << (15 - len)
                    guard to <= lookup.count else { throw Failure(message: "damaged Huffman table") }
                    let v = UInt16(sym << 4 | len)
                    for i in from..<to { lookup[i] = v }
                }
                sym += 1
            }
        }
    }

    struct Filter { var start: UInt64; var length: Int; var type: Int; var channels: Int }

    final class Unpacker {
        let window: UnsafeMutablePointer<UInt8>
        let size: Int, mask: Int
        var pos: UInt64 = 0                  // bytes produced since the first file (window position)
        var tables = [Table](repeating: Table(), count: 4)   // main, distance, low distance, repeat length
        var tablesRead = false
        var oldDist: [UInt64] = [0, 0, 0, 0]
        var lastLength = 0

        init(window dictionary: UInt64) throws {
            var s = 1 << 23
            while UInt64(s) < dictionary { s <<= 1 }
            guard s <= 1 << 30 else { throw Failure(message: "a dictionary larger than 1 GB") }
            size = s; mask = s - 1
            window = UnsafeMutablePointer<UInt8>.allocate(capacity: s)
            window.initialize(repeating: 0, count: s)
        }
        func free() { window.deallocate() }

        // bit input over one file's packed data, MSB first
        var inp: UnsafeRawBufferPointer = UnsafeRawBufferPointer(start: nil, count: 0)
        var addr = 0, bit = 0

        @inline(__always) func peek16() -> UInt32 {
            let a = addr
            let b0: UInt32, b1: UInt32, b2: UInt32
            if a + 2 < inp.count {
                b0 = UInt32(inp[a]); b1 = UInt32(inp[a + 1]); b2 = UInt32(inp[a + 2])
            } else {
                b0 = a < inp.count ? UInt32(inp[a]) : 0
                b1 = a + 1 < inp.count ? UInt32(inp[a + 1]) : 0
                b2 = 0
            }
            return ((b0 << 16 | b1 << 8 | b2) >> UInt32(8 - bit)) & 0xffff
        }
        @inline(__always) func skip(_ n: Int) { let t = bit + n; addr += t >> 3; bit = t & 7 }
        @inline(__always) func bits(_ n: Int) -> UInt32 {           // n <= 16
            if n == 0 { return 0 }
            let v = peek16() >> UInt32(16 - n); skip(n); return v
        }
        func bits64(_ n: Int) -> UInt64 {                             // n <= 64
            var v: UInt64 = 0, left = n
            while left > 0 { let k = min(16, left); v = v << UInt64(k) | UInt64(bits(k)); left -= k }
            return v
        }
        @inline(__always) func decode(_ t: Int) throws -> Int {
            let e = tables[t].lookup.withUnsafeBufferPointer { $0[Int(peek16() >> 1)] }
            let len = Int(e & 15)
            guard len != 0 else { throw Failure(message: "damaged data (no such code)") }
            skip(len)
            return Int(e >> 4)
        }

        struct Block { var end = 0; var endBit = 0; var last = false; var table = false }
        func blockHeader() throws -> Block {
            if bit != 0 { addr += 1; bit = 0 }
            guard addr + 3 <= inp.count else { throw Failure(message: "damaged data (block header)") }
            let flags = Int(inp[addr]), check = Int(inp[addr + 1]); addr += 2
            let n = ((flags >> 3) & 3) + 1
            guard n < 4, addr + n <= inp.count else { throw Failure(message: "damaged data (block size)") }
            var bsize = 0
            for i in 0..<n { bsize |= Int(inp[addr + i]) << (8 * i) }
            addr += n
            guard (0x5a ^ flags ^ bsize ^ (bsize >> 8) ^ (bsize >> 16)) & 0xff == check else {
                throw Failure(message: "damaged data (block checksum)")
            }
            var b = Block()
            b.end = addr + bsize - 1; b.endBit = (flags & 7) + 1
            b.last = flags & 0x40 != 0; b.table = flags & 0x80 != 0
            return b
        }

        func readTables(extraDist: Bool) throws {
            var bl = [UInt8](repeating: 0, count: 20)
            var i = 0
            while i < 20 {
                let l = UInt8(bits(4))
                if l == 15 {
                    let z = Int(bits(4))
                    if z == 0 { bl[i] = 15; i += 1 }
                    else { var k = z + 2; while k > 0 && i < 20 { bl[i] = 0; i += 1; k -= 1 } }
                } else { bl[i] = l; i += 1 }
            }
            var bd = Table()
            try bd.build(bl[...])
            let dc = extraDist ? 80 : 64
            let total = 306 + dc + 16 + 44
            var t = [UInt8](repeating: 0, count: total)
            i = 0
            while i < total {
                let e = bd.lookup[Int(peek16() >> 1)]
                guard e & 15 != 0 else { throw Failure(message: "damaged data (table)") }
                skip(Int(e & 15))
                let n = Int(e >> 4)
                if n < 16 { t[i] = UInt8(n); i += 1 }
                else if n < 18 {
                    var k = n == 16 ? Int(bits(3)) + 3 : Int(bits(7)) + 11
                    guard i > 0 else { throw Failure(message: "damaged data (table)") }
                    while k > 0 && i < total { t[i] = t[i - 1]; i += 1; k -= 1 }
                } else {
                    var k = n == 18 ? Int(bits(3)) + 3 : Int(bits(7)) + 11
                    while k > 0 && i < total { t[i] = 0; i += 1; k -= 1 }
                }
            }
            try tables[0].build(t[0..<306])
            try tables[1].build(t[306..<(306 + dc)])
            try tables[2].build(t[(306 + dc)..<(322 + dc)])
            try tables[3].build(t[(322 + dc)..<total])
            tablesRead = true
        }

        @inline(__always) func slotLength(_ slot: Int) -> Int {
            if slot < 8 { return slot + 2 }
            let lb = slot / 4 - 1
            return 2 + ((4 | (slot & 3)) << lb) + Int(bits(lb))
        }

        func unpack(_ packed: UnsafeRawBufferPointer, size want: UInt64, solid: Bool, extraDist: Bool,
                    output: (UnsafeRawBufferPointer) throws -> Void) throws -> UInt64 {
            inp = packed; addr = 0; bit = 0
            if !solid {
                tablesRead = false; oldDist = [0, 0, 0, 0]; lastLength = 0
            }
            let fileStart = pos
            var written = pos                // flushed up to here (window position)
            var filters: [Filter] = []
            let w = window, m = mask

            // writes [written, upTo) out, with the filters that are complete
            func flush(_ upTo: UInt64) throws {
                while written < upTo {
                    if let f = filters.first, f.start < upTo {
                        if f.start > written {
                            try emit(written, Int(f.start - written)); written = f.start
                        }
                        if f.start < written { filters.removeFirst(); continue }   // already behind: dropped
                        guard f.start + UInt64(f.length) <= pos else { return }    // not all there yet
                        try apply(f, fileOffset: f.start - fileStart)
                        written = f.start + UInt64(f.length)
                        filters.removeFirst()
                    } else {
                        try emit(written, Int(upTo - written)); written = upTo
                    }
                }
            }
            func emit(_ from: UInt64, _ n: Int) throws {
                var done = 0
                while done < n {
                    let s = Int((from + UInt64(done)) & UInt64(m))
                    let k = min(n - done, size - s)
                    try output(UnsafeRawBufferPointer(start: w + s, count: k))
                    done += k
                }
            }
            func apply(_ f: Filter, fileOffset: UInt64) throws {
                var d = [UInt8](repeating: 0, count: f.length)
                for i in 0..<f.length { d[i] = w[Int((f.start + UInt64(i)) & UInt64(m))] }
                let off = UInt32(truncatingIfNeeded: fileOffset)
                switch f.type {
                case 0:                                           // DELTA
                    var out = [UInt8](repeating: 0, count: f.length)
                    var src = 0
                    for ch in 0..<f.channels {
                        var prev: UInt8 = 0
                        var j = ch
                        while j < f.length { prev = prev &- d[src]; src += 1; out[j] = prev; j += f.channels }
                    }
                    d = out
                case 1, 2:                                        // E8, E8E9
                    let fileSize: UInt32 = 0x100_0000
                    var p = 0
                    while p + 4 < f.length {
                        let b = d[p]; p += 1
                        if b == 0xe8 || (f.type == 2 && b == 0xe9) {
                            let o = (UInt32(truncatingIfNeeded: p) &+ off) % fileSize
                            let a = UInt32(d[p]) | UInt32(d[p + 1]) << 8 | UInt32(d[p + 2]) << 16 | UInt32(d[p + 3]) << 24
                            var n: UInt32? = nil
                            if a & 0x8000_0000 != 0 { if (a &+ o) & 0x8000_0000 == 0 { n = a &+ fileSize } }
                            else if (a &- fileSize) & 0x8000_0000 != 0 { n = a &- o }
                            if let v = n { d[p] = UInt8(v & 0xff); d[p + 1] = UInt8(v >> 8 & 0xff); d[p + 2] = UInt8(v >> 16 & 0xff); d[p + 3] = UInt8(v >> 24) }
                            p += 4
                        }
                    }
                case 3:                                           // ARM
                    var p = 0
                    while p + 3 < f.length {
                        if d[p + 3] == 0xeb {
                            var o = UInt32(d[p]) | UInt32(d[p + 1]) << 8 | UInt32(d[p + 2]) << 16
                            o = o &- (off &+ UInt32(truncatingIfNeeded: p)) / 4
                            d[p] = UInt8(o & 0xff); d[p + 1] = UInt8(o >> 8 & 0xff); d[p + 2] = UInt8(o >> 16 & 0xff)
                        }
                        p += 4
                    }
                default:
                    break
                }
                try d.withUnsafeBytes { try output($0) }
            }

            var blk = try blockHeader()
            if blk.table { try readTables(extraDist: extraDist) }
            guard tablesRead else { throw Failure(message: "damaged data (no tables)") }
            let flushEvery = UInt64(size / 2)
            while true {
                if addr > blk.end || (addr == blk.end && bit >= blk.endBit) {
                    if blk.last { break }
                    blk = try blockHeader()
                    if blk.table { try readTables(extraDist: extraDist) }
                    continue
                }
                if addr >= inp.count { throw Failure(message: "damaged data (cut short)") }
                if pos - fileStart > want { throw Failure(message: "damaged data (more than the file's size)") }
                if pos - written >= flushEvery { try flush(pos) }
                let slot = try decode(0)
                if slot < 256 {
                    w[Int(pos & UInt64(m))] = UInt8(slot); pos += 1
                    continue
                }
                var length = 0
                var dist: UInt64 = 0
                if slot >= 262 {
                    length = slotLength(slot - 262)
                    let ds = try decode(1)
                    dist = 1
                    if ds < 4 { dist += UInt64(ds) }
                    else {
                        let db = ds / 2 - 1
                        dist += UInt64(2 | (ds & 1)) << UInt64(db)
                        if db >= 4 {
                            if db > 4 { dist += bits64(db - 4) << 4 }
                            dist += UInt64(try decode(2))
                        } else { dist += UInt64(bits(db)) }
                    }
                    if dist > 0x100 { length += 1; if dist > 0x2000 { length += 1; if dist > 0x40000 { length += 1 } } }
                    oldDist = [dist, oldDist[0], oldDist[1], oldDist[2]]
                    lastLength = length
                } else if slot == 256 {
                    func filterData() -> UInt64 {
                        let n = Int(bits(2)) + 1
                        var v: UInt64 = 0
                        for i in 0..<n { v |= UInt64(bits(8)) << UInt64(8 * i) }
                        return v
                    }
                    let start = filterData(), len = Int(filterData())
                    let type = Int(bits(3))
                    var ch = 0
                    if type == 0 { ch = Int(bits(5)) + 1 }
                    if len > 0 && len <= 0x40_0000 && type <= 3 {
                        filters.append(Filter(start: pos + start, length: len, type: type, channels: ch))
                    }
                    continue
                } else if slot == 257 {
                    if lastLength == 0 { continue }
                    length = lastLength; dist = oldDist[0]
                } else {
                    let n = slot - 258
                    dist = oldDist[n]
                    var k = n
                    while k > 0 { oldDist[k] = oldDist[k - 1]; k -= 1 }
                    oldDist[0] = dist
                    length = slotLength(try decode(3))
                    lastLength = length
                }
                // copy length bytes from dist back
                var src = Int((pos &- dist) & UInt64(m)), dst = Int(pos & UInt64(m))
                if src + length <= size && dst + length <= size && (dist >= UInt64(length)) {
                    (w + dst).update(from: w + src, count: length)
                } else {
                    for _ in 0..<length { w[dst] = w[src]; dst = (dst + 1) & m; src = (src + 1) & m }
                }
                pos += UInt64(length)
            }
            try flush(pos)
            return pos - fileStart
        }
    }
}
