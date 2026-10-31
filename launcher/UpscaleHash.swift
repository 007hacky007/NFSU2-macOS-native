// XXH3-64 (xxHash by Yann Collet, BSD 2-Clause; runtime/xxhash.h is the C original) in
// Swift, for the upscaled texture pack (UpscaleBuilder.swift): a pack file is named after
// XXH3-64 of the texture's level 0 as the game uploads it, seeded with
// w | h << 16 | D3DFORMAT << 32, the value runtime/texrep.m computes at the upload.
// tests/upscale_pack.sh checks it against the C version for every length up to 4 kB.
import Foundation

enum XXH3 {
    private static let p32_1: UInt64 = 0x9E3779B1, p32_2: UInt64 = 0x85EBCA77, p32_3: UInt64 = 0xC2B2AE3D
    private static let p64_1: UInt64 = 0x9E3779B185EBCA87, p64_2: UInt64 = 0xC2B2AE3D27D4EB4F
    private static let p64_3: UInt64 = 0x165667B19E3779F9, p64_4: UInt64 = 0x85EBCA77C2B2AE63
    private static let p64_5: UInt64 = 0x27D4EB2F165667C5
    private static let mx1: UInt64 = 0x165667919E3779F9, mx2: UInt64 = 0x9FB21C651E98DF25
    static let secret: [UInt8] = [
        0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c, 0xf7, 0x21, 0xad, 0x1c,
        0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb, 0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f,
        0xcb, 0x79, 0xe6, 0x4e, 0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21,
        0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6, 0x81, 0x3a, 0x26, 0x4c,
        0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb, 0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3,
        0x71, 0x64, 0x48, 0x97, 0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8,
        0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7, 0xc7, 0x0b, 0x4f, 0x1d,
        0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31, 0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64,
        0xea, 0xc5, 0xac, 0x83, 0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb,
        0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26, 0x29, 0xd4, 0x68, 0x9e,
        0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc, 0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce,
        0x45, 0xcb, 0x3a, 0x8f, 0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e,
    ]

    @inline(__always) private static func r64(_ p: UnsafeRawPointer, _ o: Int) -> UInt64 {
        UInt64(littleEndian: p.loadUnaligned(fromByteOffset: o, as: UInt64.self))
    }
    @inline(__always) private static func r32(_ p: UnsafeRawPointer, _ o: Int) -> UInt64 {
        UInt64(UInt32(littleEndian: p.loadUnaligned(fromByteOffset: o, as: UInt32.self)))
    }
    @inline(__always) private static func fold(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let m = a.multipliedFullWidth(by: b)
        return m.low ^ m.high
    }
    @inline(__always) private static func rotl(_ x: UInt64, _ r: UInt64) -> UInt64 { (x << r) | (x >> (64 - r)) }
    private static func avalanche64(_ h0: UInt64) -> UInt64 {
        var h = h0
        h ^= h >> 33; h = h &* p64_2; h ^= h >> 29; h = h &* p64_3; h ^= h >> 32
        return h
    }
    private static func avalanche(_ h0: UInt64) -> UInt64 {
        var h = h0
        h ^= h >> 37; h = h &* mx1; h ^= h >> 32
        return h
    }
    private static func rrmxmx(_ h0: UInt64, _ len: UInt64) -> UInt64 {
        var h = h0
        h ^= rotl(h, 49) ^ rotl(h, 24)
        h = h &* mx2
        h ^= (h >> 35) &+ len
        h = h &* mx2
        return h ^ (h >> 28)
    }
    @inline(__always) private static func mix16(_ i: UnsafeRawPointer, _ io: Int, _ s: UnsafeRawPointer, _ so: Int, _ seed: UInt64) -> UInt64 {
        fold(r64(i, io) ^ (r64(s, so) &+ seed), r64(i, io + 8) ^ (r64(s, so + 8) &- seed))
    }

    /// XXH3_64bits_withSeed
    static func hash(_ data: UnsafeRawBufferPointer, seed: UInt64) -> UInt64 {
        secret.withUnsafeBytes { sb in
            let s = sb.baseAddress!
            let n = data.count
            let len = UInt64(n)
            guard n > 0, let i = data.baseAddress else {
                return avalanche64(seed ^ (r64(s, 56) ^ r64(s, 64)))
            }
            if n <= 3 {
                let c1 = UInt32(i.load(fromByteOffset: 0, as: UInt8.self))
                let c2 = UInt32(i.load(fromByteOffset: n >> 1, as: UInt8.self))
                let c3 = UInt32(i.load(fromByteOffset: n - 1, as: UInt8.self))
                let combined = (c1 << 16) | (c2 << 24) | c3 | (UInt32(n) << 8)
                let bitflip = (r32(s, 0) ^ r32(s, 4)) &+ seed
                return avalanche64(UInt64(combined) ^ bitflip)
            }
            if n <= 8 {
                let sd = seed ^ (UInt64(UInt32(truncatingIfNeeded: seed).byteSwapped) << 32)
                let in1 = r32(i, 0), in2 = r32(i, n - 4)
                let bitflip = (r64(s, 8) ^ r64(s, 16)) &- sd
                let in64 = in2 &+ (in1 << 32)
                return rrmxmx(in64 ^ bitflip, len)
            }
            if n <= 16 {
                let bf1 = (r64(s, 24) ^ r64(s, 32)) &+ seed
                let bf2 = (r64(s, 40) ^ r64(s, 48)) &- seed
                let lo = r64(i, 0) ^ bf1, hi = r64(i, n - 8) ^ bf2
                let acc = len &+ lo.byteSwapped &+ hi &+ fold(lo, hi)
                return avalanche(acc)
            }
            if n <= 128 {
                var acc = len &* p64_1
                if n > 32 {
                    if n > 64 {
                        if n > 96 {
                            acc = acc &+ mix16(i, 48, s, 96, seed)
                            acc = acc &+ mix16(i, n - 64, s, 112, seed)
                        }
                        acc = acc &+ mix16(i, 32, s, 64, seed)
                        acc = acc &+ mix16(i, n - 48, s, 80, seed)
                    }
                    acc = acc &+ mix16(i, 16, s, 32, seed)
                    acc = acc &+ mix16(i, n - 32, s, 48, seed)
                }
                acc = acc &+ mix16(i, 0, s, 0, seed)
                acc = acc &+ mix16(i, n - 16, s, 16, seed)
                return avalanche(acc)
            }
            if n <= 240 {
                var acc = len &* p64_1
                let rounds = n / 16
                for k in 0..<8 { acc = acc &+ mix16(i, 16 * k, s, 16 * k, seed) }
                var accEnd = mix16(i, n - 16, s, 136 - 17, seed)
                acc = avalanche(acc)
                for k in 8..<max(rounds, 8) { accEnd = accEnd &+ mix16(i, 16 * k, s, 16 * (k - 8) + 3, seed) }
                return avalanche(acc &+ accEnd)
            }
            if seed == 0 { return long(i, n, s) }
            var custom = [UInt8](repeating: 0, count: 192)
            for k in 0..<12 {
                let lo = r64(s, 16 * k) &+ seed, hi = r64(s, 16 * k + 8) &- seed
                withUnsafeBytes(of: lo.littleEndian) { custom.replaceSubrange(16 * k..<16 * k + 8, with: $0) }
                withUnsafeBytes(of: hi.littleEndian) { custom.replaceSubrange(16 * k + 8..<16 * k + 16, with: $0) }
            }
            return custom.withUnsafeBytes { long(i, n, $0.baseAddress!) }
        }
    }

    /// XXH3_hashLong_64b_internal with a 192-byte secret
    private static func long(_ i: UnsafeRawPointer, _ n: Int, _ s: UnsafeRawPointer) -> UInt64 {
        var acc: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) =
            (p32_3, p64_1, p64_2, p64_3, p64_4, p32_2, p64_5, p32_1)
        withUnsafeMutableBytes(of: &acc) { ab in
            let a = ab.baseAddress!.assumingMemoryBound(to: UInt64.self)
            @inline(__always) func stripe(_ io: Int, _ so: Int) {
                for k in 0..<8 {
                    let v = r64(i, io + 8 * k)
                    let key = v ^ r64(s, so + 8 * k)
                    a[k ^ 1] = a[k ^ 1] &+ v
                    a[k] = a[k] &+ (key & 0xFFFF_FFFF) &* (key >> 32)
                }
            }
            let perBlock = (192 - 64) / 8, blockLen = 64 * perBlock
            let blocks = (n - 1) / blockLen
            for b in 0..<blocks {
                for st in 0..<perBlock { stripe(b * blockLen + st * 64, st * 8) }
                for k in 0..<8 {                                   // scramble
                    var v = a[k]
                    v ^= v >> 47; v ^= r64(s, 192 - 64 + 8 * k); v = v &* p32_1
                    a[k] = v
                }
            }
            let stripes = ((n - 1) - blockLen * blocks) / 64
            for st in 0..<stripes { stripe(blocks * blockLen + st * 64, st * 8) }
            stripe(n - 64, 192 - 64 - 7)
        }
        var r = UInt64(n) &* p64_1
        withUnsafeBytes(of: &acc) { ab in
            let a = ab.baseAddress!.assumingMemoryBound(to: UInt64.self)
            for k in 0..<4 { r = r &+ fold(a[2 * k] ^ r64(s, 11 + 16 * k), a[2 * k + 1] ^ r64(s, 11 + 16 * k + 8)) }
        }
        return avalanche(r)
    }

    static func hash(_ d: Data, seed: UInt64) -> UInt64 { d.withUnsafeBytes { hash($0, seed: seed) } }
    static func hash(_ d: [UInt8], seed: UInt64) -> UInt64 { d.withUnsafeBytes { hash($0, seed: seed) } }
}
