// tests/upscale_hash.swift (tests/upscale_pack.sh): launcher/UpscaleHash.swift's XXH3-64 for
// every length 0 to 4100 and three seeds, one line each, to compare with runtime/xxhash.h.
var b = [UInt8](repeating: 0, count: 5000)
for i in 0..<5000 { b[i] = UInt8(truncatingIfNeeded: (i * 131 + 7) >> 3) }
var out = ""
for s: UInt64 in [0, 0x1234567890, 64 | 64 << 16 | 0x31545844 << 32] {
    for n in 0...4100 {
        let h = b.withUnsafeBytes { XXH3.hash(UnsafeRawBufferPointer(rebasing: $0[0..<n]), seed: s) }
        out += String(h, radix: 16) + "\n"
    }
}
print(out, terminator: "")
