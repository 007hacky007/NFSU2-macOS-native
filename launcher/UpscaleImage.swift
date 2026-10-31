// The picture work of the upscaled texture pack (UpscaleBuilder.swift), as the old
// Python builder (tools/texpack/texpack.py) did it, step for step, so a pack made here
// matches one made there:
//   - the model's 4x result keeps the original's colour (chroma lock: the model's
//     brightness detail, the original's hue, bicubic) and the original's alpha
//     (bilinear: in this game alpha is data, reflection weights and cut-outs);
//   - back-projection: corrected until its 4x4 averages are the original's texels
//     again, so the model adds detail but cannot repaint;
//   - the levels above the original's size, in its own block format.
// The resampling is Pillow's (bicubic a = -0.5 and bilinear, its coefficient and
// fixed-point rules for 8-bit pictures, doubles for float ones), the padding numpy's
// "wrap" and "symmetric".  The block encoder is this file's own (principal axis, then
// least-squares endpoints); the old builder used etcpak, so blocks differ, not their
// quality (tests/upscale_pack.sh).
import Foundation

enum TexFormat: String {
    case dxt1 = "DXT1", dxt3 = "DXT3", dxt5 = "DXT5", argb = "A8R8G8B8"
    var d3d: UInt32 {
        switch self { case .dxt1: return 0x3154_5844; case .dxt3: return 0x3354_5844; case .dxt5: return 0x3554_5844; case .argb: return 21 }
    }
    var blockBytes: Int { self == .dxt1 ? 8 : 16 }
    func levelSize(_ w: Int, _ h: Int) -> Int {
        self == .argb ? w * h * 4 : ((w + 3) / 4) * ((h + 3) / 4) * blockBytes
    }
}

/// An RGBA picture, 8 bits per channel, rows top to bottom.
struct RGBA {
    var w: Int, h: Int
    var px: [UInt8]                   // w * h * 4
}

enum TexImage {
    // MARK: padding (numpy.pad)

    /// index i (may be outside 0..<n) of a padded axis
    @inline(__always) static func padIndex(_ i: Int, _ n: Int, _ wrap: Bool) -> Int {
        if i >= 0 && i < n { return i }
        if wrap { let m = i % n; return m < 0 ? m + n : m }
        let p = 2 * n
        var m = i % p; if m < 0 { m += p }
        return m < n ? m : p - 1 - m                     // "symmetric": the edge texel repeats
    }
    /// pad an h x w x c picture by p on every side; modes: (rows wrap, columns wrap)
    static func pad(_ a: [UInt8], _ h: Int, _ w: Int, _ c: Int, _ p: Int, _ modes: (Bool, Bool)) -> [UInt8] {
        padded(a, h, w, c, p, modes, 0)
    }
    static func pad(_ a: [Float], _ h: Int, _ w: Int, _ c: Int, _ p: Int, _ modes: (Bool, Bool)) -> [Float] {
        padded(a, h, w, c, p, modes, 0)
    }
    @inline(__always) private static func padded<T>(_ a: [T], _ h: Int, _ w: Int, _ c: Int, _ p: Int, _ modes: (Bool, Bool), _ zero: T) -> [T] {
        let H = h + 2 * p, W = w + 2 * p
        var out = [T](repeating: zero, count: H * W * c)
        var xs = [Int](repeating: 0, count: W)
        for x in 0..<W { xs[x] = padIndex(x - p, w, modes.1) }
        a.withUnsafeBufferPointer { s in out.withUnsafeMutableBufferPointer { o in
            for y in 0..<H {
                let sy = padIndex(y - p, h, modes.0) * w, row = y * W * c
                for x in 0..<W { let si = (sy + xs[x]) * c, di = row + x * c; for k in 0..<c { o[di + k] = s[si + k] } }
            }
        } }
        return out
    }

    // MARK: Pillow resampling (libImaging/Resample.c)

    private static func bicubic(_ x0: Double) -> Double {
        let a = -0.5, x = abs(x0)
        if x < 1 { return ((a + 2) * x - (a + 3)) * x * x + 1 }
        if x < 2 { return (((x - 5) * x + 8) * x - 4) * a }
        return 0
    }
    private static func bilinear(_ x0: Double) -> Double { let x = abs(x0); return x < 1 ? 1 - x : 0 }

    struct Coeffs { var ksize: Int; var bounds: [(Int, Int)]; var k: [Double] }
    static func coeffs(_ inSize: Int, _ outSize: Int, cubic: Bool) -> Coeffs {
        let support0 = cubic ? 2.0 : 1.0
        let scale = Double(Float(inSize) - Float(0)) / Double(outSize)
        let filterscale = max(scale, 1.0)
        let support = support0 * filterscale
        let ksize = Int(support.rounded(.up)) * 2 + 1
        var kk = [Double](repeating: 0, count: outSize * ksize)
        var bounds = [(Int, Int)](repeating: (0, 0), count: outSize)
        let ss = 1.0 / filterscale
        for xx in 0..<outSize {
            let center = (Double(xx) + 0.5) * scale
            var xmin = Int(center - support + 0.5); if xmin < 0 { xmin = 0 }
            var xmax = Int(center + support + 0.5); if xmax > inSize { xmax = inSize }
            xmax -= xmin
            var ww = 0.0
            for x in 0..<xmax {
                let w = cubic ? bicubic((Double(x + xmin) - center + 0.5) * ss) : bilinear((Double(x + xmin) - center + 0.5) * ss)
                kk[xx * ksize + x] = w; ww += w
            }
            if ww != 0 { for x in 0..<xmax { kk[xx * ksize + x] /= ww } }
            bounds[xx] = (xmin, xmax)
        }
        return Coeffs(ksize: ksize, bounds: bounds, k: kk)
    }
    private static let precision = 22
    private static func fixed(_ c: Coeffs) -> [Int32] {
        c.k.map { v in Int32(v < 0 ? (-0.5 + v * Double(1 << precision)) : (0.5 + v * Double(1 << precision))) }
    }
    @inline(__always) private static func clip8(_ v: Int64) -> UInt8 {
        if v >= Int64(1) << (precision + 8) { return 255 }
        if v <= 0 { return 0 }
        return UInt8(truncatingIfNeeded: v >> precision)
    }

    /// Image.resize of an 8-bit picture of c channels (1: "L", 3: "RGB")
    static func resize8(_ src: [UInt8], _ w: Int, _ h: Int, _ c: Int, _ ow: Int, _ oh: Int, cubic: Bool) -> [UInt8] {
        let ch = coeffs(w, ow, cubic: cubic), cv = coeffs(h, oh, cubic: cubic)
        let kh = fixed(ch), kv = fixed(cv)
        let half = Int64(1) << (precision - 1)
        // horizontal pass, rows the vertical pass uses
        let yFirst = cv.bounds[0].0, yLast = cv.bounds[oh - 1].0 + cv.bounds[oh - 1].1
        let needH = ow != w, needV = oh != h
        var tmp: [UInt8], th: Int, tw: Int, y0: Int
        if needH {
            th = yLast - yFirst; tw = ow; y0 = yFirst
            tmp = [UInt8](repeating: 0, count: th * tw * c)
            src.withUnsafeBufferPointer { s in tmp.withUnsafeMutableBufferPointer { t in kh.withUnsafeBufferPointer { kp in
                let sp = s.baseAddress!, tp = t.baseAddress!, k0 = kp.baseAddress!
                DispatchQueue.concurrentPerform(iterations: (th + 31) / 32) { bi in       // 32 rows a piece
                    for yy in (bi * 32)..<min(th, bi * 32 + 32) {
                        let row = sp + (yy + yFirst) * w * c
                        for xx in 0..<ow {
                            let (xmin, xmax) = ch.bounds[xx], kb = k0 + xx * ch.ksize
                            for k in 0..<c {
                                var ss = half
                                for x in 0..<xmax { ss += Int64(row[(x + xmin) * c + k]) * Int64(kb[x]) }
                                tp[(yy * tw + xx) * c + k] = clip8(ss)
                            }
                        }
                    }
                }
            } } }
        } else { tmp = src; th = h; tw = w; y0 = 0 }
        guard needV else { return tmp }
        var out = [UInt8](repeating: 0, count: oh * tw * c)
        tmp.withUnsafeBufferPointer { t in out.withUnsafeMutableBufferPointer { o in kv.withUnsafeBufferPointer { kp in
            let tp = t.baseAddress!, op = o.baseAddress!, k0 = kp.baseAddress!
            DispatchQueue.concurrentPerform(iterations: (oh + 31) / 32) { bi in
                let n = tw * c
                let a = UnsafeMutablePointer<Int64>.allocate(capacity: n)
                defer { a.deallocate() }
                for yy in (bi * 32)..<min(oh, bi * 32 + 32) {
                    let (ymin0, ymax) = cv.bounds[yy], ymin = ymin0 - y0, kb = k0 + yy * cv.ksize
                    for i in 0..<n { a[i] = half }
                    for y in 0..<ymax {                          // the same sum, a row at a time
                        let k = Int64(kb[y]), r = tp + (y + ymin) * n
                        for i in 0..<n { a[i] += Int64(r[i]) * k }
                    }
                    for i in 0..<n { op[yy * n + i] = clip8(a[i]) }
                }
            }
        } } }
        _ = th
        return out
    }

    /// Image.resize of a float picture ("F"): doubles, stored as float
    static func resizeF(_ src: [Float], _ w: Int, _ h: Int, _ ow: Int, _ oh: Int, cubic: Bool) -> [Float] {
        let ch = coeffs(w, ow, cubic: cubic), cv = coeffs(h, oh, cubic: cubic)
        let yFirst = cv.bounds[0].0, yLast = cv.bounds[oh - 1].0 + cv.bounds[oh - 1].1
        let th = yLast - yFirst
        let xmins = ch.bounds.map { $0.0 }, xmaxs = ch.bounds.map { $0.1 }
        var tmp = [Float](repeating: 0, count: th * ow)
        let band = 32                                         // rows per piece of work, on every core
        src.withUnsafeBufferPointer { s in tmp.withUnsafeMutableBufferPointer { t in ch.k.withUnsafeBufferPointer { kh in
            let sp = s.baseAddress!, tp = t.baseAddress!, kp = kh.baseAddress!
            DispatchQueue.concurrentPerform(iterations: (th + band - 1) / band) { bi in
                for yy in (bi * band)..<min(th, bi * band + band) {
                    let row = sp + (yy + yFirst) * w
                    for xx in 0..<ow {
                        let xmin = xmins[xx], xmax = xmaxs[xx], k = kp + xx * ch.ksize
                        var ss = 0.0
                        for x in 0..<xmax { ss += Double(row[x + xmin]) * k[x] }
                        tp[yy * ow + xx] = Float(ss)
                    }
                }
            }
        } } }
        var out = [Float](repeating: 0, count: oh * ow)
        tmp.withUnsafeBufferPointer { t in out.withUnsafeMutableBufferPointer { o in cv.k.withUnsafeBufferPointer { kv in
            let tp = t.baseAddress!, op = o.baseAddress!, kp = kv.baseAddress!
            DispatchQueue.concurrentPerform(iterations: (oh + band - 1) / band) { bi in
                let a = UnsafeMutablePointer<Double>.allocate(capacity: ow)
                defer { a.deallocate() }
                for yy in (bi * band)..<min(oh, bi * band + band) {
                    let (ymin0, ymax) = cv.bounds[yy], ymin = ymin0 - yFirst, kb = yy * cv.ksize
                    for xx in 0..<ow { a[xx] = 0 }
                    for y in 0..<ymax {                          // the same sum, a row at a time
                        let k = kp[kb + y], r = tp + (y + ymin) * ow
                        for xx in 0..<ow { a[xx] += Double(r[xx]) * k }
                    }
                    for xx in 0..<ow { op[yy * ow + xx] = Float(a[xx]) }
                }
            }
        } } }
        return out
    }

    // MARK: what decides whether and how a texture is made

    /// (rows wrap, columns wrap): opposite edges that match like neighbouring texels
    static func padModes(_ rgb: [UInt8], _ h: Int, _ w: Int) -> (Bool, Bool) {
        func tiles(_ rowsAxis: Bool) -> Bool {
            var edge = 0.0, inner = 0.0
            if rowsAxis {
                for x in 0..<w { for k in 0..<3 { edge += abs(Double(rgb[x * 3 + k]) - Double(rgb[((h - 1) * w + x) * 3 + k])) } }
                edge /= Double(w * 3)
                for y in 0..<(h - 1) { for x in 0..<w { for k in 0..<3 {
                    inner += abs(Double(rgb[((y + 1) * w + x) * 3 + k]) - Double(rgb[(y * w + x) * 3 + k])) } } }
                inner /= Double((h - 1) * w * 3)
            } else {
                for y in 0..<h { for k in 0..<3 { edge += abs(Double(rgb[(y * w) * 3 + k]) - Double(rgb[(y * w + w - 1) * 3 + k])) } }
                edge /= Double(h * 3)
                for y in 0..<h { for x in 0..<(w - 1) { for k in 0..<3 {
                    inner += abs(Double(rgb[(y * w + x + 1) * 3 + k]) - Double(rgb[(y * w + x) * 3 + k])) } } }
                inner /= Double(h * (w - 1) * 3)
            }
            return Float(edge) <= 1.5 * Float(inner) + 1
        }
        return (tiles(true), tiles(false))
    }
    /// mean |Laplacian| of the luma (below 7: a smooth texture, the model would add grain)
    static func smoothness(_ rgb: [UInt8], _ h: Int, _ w: Int) -> Double {
        guard h >= 3, w >= 3 else { return 0 }
        var y = [Float](repeating: 0, count: h * w)
        for i in 0..<(h * w) {
            y[i] = Float(rgb[i * 3]) * 0.299 + Float(rgb[i * 3 + 1]) * 0.587 + Float(rgb[i * 3 + 2]) * 0.114
        }
        var s = 0.0
        for r in 1..<(h - 1) { for c in 1..<(w - 1) {
            let i = r * w + c
            s += Double(abs(4 * y[i] - y[i - w] - y[i + w] - y[i - 1] - y[i + 1]))
        } }
        return s / Double((h - 2) * (w - 2))
    }

    // MARK: the levels of a pack file

    /// mean of k x k blocks of an h x w x c float picture
    static func boxDown(_ a: [Float], _ h: Int, _ w: Int, _ c: Int, _ k: Int) -> [Float] {
        let oh = h / k, ow = w / k
        var out = [Float](repeating: 0, count: oh * ow * c)
        let n = Float(k * k)
        a.withUnsafeBufferPointer { s in out.withUnsafeMutableBufferPointer { o in
            for y in 0..<oh { for x in 0..<ow { for ch in 0..<c {
                var sum: Float = 0
                for i in 0..<k { let row = ((y * k + i) * w + x * k) * c + ch
                    for j in 0..<k { sum += s[row + j * c] } }
                o[(y * ow + x) * c + ch] = sum / n
            } } }
        } }
        return out
    }
    /// [1 2 1] / 4 both ways at the original's size (the texel-sized checkerboard is not put back)
    private static func soften(_ d: [Float], _ h: Int, _ w: Int, _ modes: (Bool, Bool)) -> [Float] {
        let p = pad(d, h, w, 1, 1, modes)
        let W = w + 2
        var v = [Float](repeating: 0, count: h * W)
        for y in 0..<h { for x in 0..<W { v[y * W + x] = (p[y * W + x] + 2 * p[(y + 1) * W + x] + p[(y + 2) * W + x]) / 4 } }
        var o = [Float](repeating: 0, count: h * w)
        for y in 0..<h { for x in 0..<w { o[y * w + x] = (v[y * W + x] + 2 * v[y * W + x + 1] + v[y * W + x + 2]) / 4 } }
        return o
    }
    /// float h x w -> 4h x 4w, bicubic, with the texture's edge modes
    private static func bicubicUp(_ ch: [Float], _ h: Int, _ w: Int, _ k: Int, _ modes: (Bool, Bool)) -> [Float] {
        let p = pad(ch, h, w, 1, 2, modes)
        let up = resizeF(p, w + 4, h + 4, (w + 4) * k, (h + 4) * k, cubic: true)
        let UW = (w + 4) * k
        var o = [Float](repeating: 0, count: h * k * w * k)
        up.withUnsafeBufferPointer { u in o.withUnsafeMutableBufferPointer { ob in
            for y in 0..<(h * k) { let s = (y + 2 * k) * UW + 2 * k, d = y * w * k; for x in 0..<(w * k) { ob[d + x] = u[s + x] } }
        } }
        return o
    }
    /// 8-bit channel h x w -> kh x kw, bilinear (the GPU's own magnification)
    private static func bilinearUp(_ ch: [UInt8], _ h: Int, _ w: Int, _ k: Int, _ modes: (Bool, Bool)) -> [UInt8] {
        let p = pad(ch, h, w, 1, 1, modes)
        let up = resize8(p, w + 2, h + 2, 1, (w + 2) * k, (h + 2) * k, cubic: false)
        let UW = (w + 2) * k
        var o = [UInt8](repeating: 0, count: h * k * w * k)
        for y in 0..<(h * k) { for x in 0..<(w * k) { o[y * w * k + x] = up[(y + k) * UW + x + k] } }
        return o
    }

    static let backprojectPasses = 8

    /// orig: the texture (RGBA); up: the model's 4x of its RGB (4h x 4w x 3, 0..1);
    /// -> the pack's levels, largest first (scale 4: 4x and 2x; scale 2: 2x)
    static func levels(orig: RGBA, up: [Float], fmt: TexFormat, scale: Int, modes: (Bool, Bool)) -> [RGBA] {
        let h = orig.h, w = orig.w, W = w * 4, H = h * 4, N = H * W
        var rgb = [UInt8](repeating: 0, count: h * w * 3), alpha = [UInt8](repeating: 0, count: h * w)
        for i in 0..<(h * w) { for k in 0..<3 { rgb[i * 3 + k] = orig.px[i * 4 + k] }; alpha[i] = orig.px[i * 4 + 3] }
        // chroma lock: the model's luma, the original's chroma (bicubic), planar from here on
        let ref = resize8(rgb, w, h, 3, W, H, cubic: true)
        let k0: Float = 0.299, k1: Float = 0.587, k2: Float = 0.114
        var planes = [[Float]](repeating: [Float](repeating: 0, count: N), count: 3)
        var p0 = planes[0], p1 = planes[1], p2 = planes[2]
        planes = []
        up.withUnsafeBufferPointer { u in ref.withUnsafeBufferPointer { f in
        p0.withUnsafeMutableBufferPointer { a in p1.withUnsafeMutableBufferPointer { b in p2.withUnsafeMutableBufferPointer { c in
            for i in 0..<N {
                let u0 = u[i * 3] * 255, u1 = u[i * 3 + 1] * 255, u2 = u[i * 3 + 2] * 255
                let f0 = Float(f[i * 3]), f1 = Float(f[i * 3 + 1]), f2 = Float(f[i * 3 + 2])
                let dl = (u0 * k0 + u1 * k1 + u2 * k2) - (f0 * k0 + f1 * k1 + f2 * k2)
                a[i] = min(max(f0 + dl, 0), 255); b[i] = min(max(f1 + dl, 0), 255); c[i] = min(max(f2 + dl, 0), 255)
            }
        } } } } }
        // back-projection, each channel on its own (they do not mix)
        let src = rgb
        func backproject(_ pl: inout [Float], _ c: Int) {
            var o = [Float](repeating: 0, count: h * w)
            for i in 0..<(h * w) { o[i] = Float(src[i * 3 + c]) }
            for _ in 0..<backprojectPasses {
                let avg = boxDown(pl, H, W, 1, 4)
                var d = [Float](repeating: 0, count: h * w)
                for i in 0..<(h * w) { d[i] = o[i] - avg[i] }
                let u = bicubicUp(soften(d, h, w, modes), h, w, 4, modes)
                pl.withUnsafeMutableBufferPointer { p in u.withUnsafeBufferPointer { q in for i in 0..<N { p[i] += q[i] } } }
            }
            pl.withUnsafeMutableBufferPointer { p in for i in 0..<N { p[i] = min(max(p[i], 0), 255) } }
        }
        let group = DispatchGroup(), q = DispatchQueue.global(qos: .userInitiated)
        q.async(group: group) { backproject(&p1, 1) }
        q.async(group: group) { backproject(&p2, 2) }
        backproject(&p0, 0)
        group.wait()
        let flatA = alpha.min() == alpha.max()
        var out: [RGBA] = []
        for kk in (scale == 4 ? [4, 2] : [2]) {
            let lv = kk == 4 ? [p0, p1, p2] : [boxDown(p0, H, W, 1, 2), boxDown(p1, H, W, 1, 2), boxDown(p2, H, W, 1, 2)]
            let lw = w * kk, lh = h * kk
            let a: [UInt8]
            if flatA { a = [UInt8](repeating: alpha[0], count: lw * lh) }
            else {
                let b = bilinearUp(alpha, h, w, kk, modes)
                a = fmt == .dxt1 ? b.map { $0 >= 128 ? 255 : 0 } : b
            }
            var px = [UInt8](repeating: 0, count: lw * lh * 4)
            px.withUnsafeMutableBufferPointer { o in a.withUnsafeBufferPointer { ab in
                for c in 0..<3 { lv[c].withUnsafeBufferPointer { l in
                    for i in 0..<(lw * lh) { o[i * 4 + c] = UInt8(min(max(l[i].rounded(.toNearestOrEven), 0), 255)) }
                } }
                for i in 0..<(lw * lh) { o[i * 4 + 3] = ab[i] }
            } }
            out.append(RGBA(w: lw, h: lh, px: px))
        }
        return out
    }

    // MARK: block decoding (as Pillow's DDS reader: the old builder's input)

    @inline(__always) private static func c565(_ v: Int) -> (Int, Int, Int) {
        var r = (v & 0xF800) >> 8; r |= r >> 5
        var g = (v & 0x07E0) >> 3; g |= g >> 6
        var b = (v & 0x001F) << 3; b |= b >> 5
        return (r, g, b)
    }
    static func decode(_ d: [UInt8], _ w: Int, _ h: Int, _ fmt: TexFormat) -> RGBA {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        if fmt == .argb {
            for i in 0..<(w * h) { px[i * 4] = d[i * 4 + 2]; px[i * 4 + 1] = d[i * 4 + 1]; px[i * 4 + 2] = d[i * 4]; px[i * 4 + 3] = d[i * 4 + 3] }
            return RGBA(w: w, h: h, px: px)
        }
        let bw = (w + 3) / 4, bh = (h + 3) / 4, bb = fmt.blockBytes
        for by in 0..<bh { for bx in 0..<bw {
            let o = (by * bw + bx) * bb
            let co = fmt == .dxt1 ? o : o + 8
            let c0 = Int(d[co]) | Int(d[co + 1]) << 8, c1 = Int(d[co + 2]) | Int(d[co + 3]) << 8
            let lut = UInt32(d[co + 4]) | UInt32(d[co + 5]) << 8 | UInt32(d[co + 6]) << 16 | UInt32(d[co + 7]) << 24
            let (r0, g0, b0) = c565(c0), (r1, g1, b1) = c565(c1)
            var p = [(Int, Int, Int, Int)](repeating: (0, 0, 0, 255), count: 4)
            p[0] = (r0, g0, b0, 255); p[1] = (r1, g1, b1, 255)
            if c0 > c1 || fmt != .dxt1 {
                p[2] = ((2 * r0 + r1) / 3, (2 * g0 + g1) / 3, (2 * b0 + b1) / 3, 255)
                p[3] = ((r0 + 2 * r1) / 3, (g0 + 2 * g1) / 3, (b0 + 2 * b1) / 3, 255)
            } else {
                p[2] = ((r0 + r1) / 2, (g0 + g1) / 2, (b0 + b1) / 2, 255)
                p[3] = (0, 0, 0, 0)
            }
            var al = [Int](repeating: 255, count: 16)
            if fmt == .dxt3 {
                for n in 0..<16 { let a = Int(d[o + n / 2] >> (4 * UInt8(n & 1))) & 15; al[n] = a | a << 4 }
            } else if fmt == .dxt5 {
                let a0 = Int(d[o]), a1 = Int(d[o + 1])
                var a = [a0, a1, 0, 0, 0, 0, 0, 0]
                if a0 > a1 { for i in 2..<8 { a[i] = ((8 - i) * a0 + (i - 1) * a1) / 7 } }
                else { for i in 2..<6 { a[i] = ((6 - i) * a0 + (i - 1) * a1) / 5 }; a[6] = 0; a[7] = 255 }
                var bits: UInt64 = 0
                for i in 0..<6 { bits |= UInt64(d[o + 2 + i]) << (8 * UInt64(i)) }
                for n in 0..<16 { al[n] = a[Int((bits >> (3 * UInt64(n))) & 7)] }
            }
            for n in 0..<16 {
                let x = bx * 4 + n % 4, y = by * 4 + n / 4
                guard x < w, y < h else { continue }
                let c = p[Int((lut >> (2 * UInt32(n))) & 3)]
                let i = (y * w + x) * 4
                px[i] = UInt8(c.0); px[i + 1] = UInt8(c.1); px[i + 2] = UInt8(c.2)
                px[i + 3] = UInt8(fmt == .dxt1 ? c.3 : al[n])
            }
        } }
        return RGBA(w: w, h: h, px: px)
    }

    // MARK: block encoding (one block at a time, no allocations: a 2048 x 2048 level has 262144)

    typealias V3 = SIMD3<Float>
    @inline(__always) static func to565(_ c: V3) -> Int {
        @inline(__always) func q(_ v: Float) -> Int { Int(min(max(v.rounded(.toNearestOrEven), 0), 255)) }
        return ((q(c.x) * 31 + 127) / 255) << 11 | ((q(c.y) * 63 + 127) / 255) << 5 | ((q(c.z) * 31 + 127) / 255)
    }
    @inline(__always) static func from565(_ v: Int) -> V3 {
        V3(Float(Double((v >> 11) & 31) * 255 / 31), Float(Double((v >> 5) & 63) * 255 / 63), Float(Double(v & 31) * 255 / 31))
    }
    @inline(__always) private static func d2(_ a: V3, _ b: V3) -> Float { let d = a - b; return (d * d).sum() }
    /// best indices for the 4-colour palette of e0, e1 (2 bits a texel), and the error
    @inline(__always) private static func index4(_ px: UnsafePointer<V3>, _ e0: Int, _ e1: Int) -> (UInt32, Float) {
        let p0 = from565(e0), p1 = from565(e1)
        let p2 = (2 * p0 + p1) / 3, p3 = (p0 + 2 * p1) / 3
        var bits: UInt32 = 0, err: Float = 0
        for n in 0..<16 {
            let c = px[n]
            var best: UInt32 = 0, bd = d2(c, p0)
            let e1 = d2(c, p1); if e1 < bd { bd = e1; best = 1 }
            let e2 = d2(c, p2); if e2 < bd { bd = e2; best = 2 }
            let e3 = d2(c, p3); if e3 < bd { bd = e3; best = 3 }
            bits |= best << (2 * UInt32(n)); err += bd
        }
        return (bits, err)
    }
    private static let w4: (Float, Float, Float, Float) = (1, 0, 2.0 / 3, 1.0 / 3)

    /// the colour half of a block: 4-colour mode, c0 > c1 unless one colour (then all index 0);
    /// endpoints along the principal axis, then least squares on the indices while it helps
    static func colorBlock(_ px: UnsafePointer<V3>) -> (Int, Int, UInt32) {
        var mean = V3(0, 0, 0)
        for n in 0..<16 { mean += px[n] }
        mean /= 16
        var c00: Float = 0, c01: Float = 0, c02: Float = 0, c11: Float = 0, c12: Float = 0, c22: Float = 0
        for n in 0..<16 {
            let d = px[n] - mean
            c00 += d.x * d.x; c01 += d.x * d.y; c02 += d.x * d.z; c11 += d.y * d.y; c12 += d.y * d.z; c22 += d.z * d.z
        }
        var ax = V3(1, 1, 1)
        for _ in 0..<8 {
            let n = V3(c00 * ax.x + c01 * ax.y + c02 * ax.z, c01 * ax.x + c11 * ax.y + c12 * ax.z, c02 * ax.x + c12 * ax.y + c22 * ax.z)
            let m = max(abs(n.x), abs(n.y), abs(n.z))
            if m < 1e-12 { break }
            ax = n / m
        }
        var lo = Float.infinity, hi = -Float.infinity
        for n in 0..<16 { let t = ((px[n] - mean) * ax).sum(); lo = min(lo, t); hi = max(hi, t) }
        let n2 = (ax * ax).sum()
        var e0: Int, e1: Int
        if n2 < 1e-12 || hi - lo < 1e-6 { e0 = to565(mean); e1 = e0 }
        else { e0 = to565(mean + ax * (hi / n2)); e1 = to565(mean + ax * (lo / n2)) }
        if e0 < e1 { swap(&e0, &e1) }
        var (bits, err) = index4(px, e0, e1)
        if e0 == e1 {
            // one colour: the neighbouring 565 values as a pair (the third and fourth colours land between)
            for d0 in [0, 1, 32, 2048, 2081] {
                for d1 in [-1, -32, -2048, -2081] {
                    let a = e0 + d0, b = e0 + d1
                    guard a <= 0xFFFF, b >= 0, a > b else { continue }
                    let (b2, er2) = index4(px, a, b)
                    if er2 < err { (e0, e1, bits, err) = (a, b, b2, er2) }
                }
            }
        }
        // least squares: keep the indices, solve for the two endpoints, take them when better
        var iter = 0
        while iter < 3 && e0 > e1 {
            iter += 1
            var a11: Float = 0, a12: Float = 0, a22: Float = 0, b1 = V3(0, 0, 0), b2 = V3(0, 0, 0)
            for n in 0..<16 {
                let ix = (bits >> (2 * UInt32(n))) & 3
                let w: Float = ix == 0 ? w4.0 : ix == 1 ? w4.1 : ix == 2 ? w4.2 : w4.3, v = 1 - w
                a11 += w * w; a12 += w * v; a22 += v * v
                b1 += w * px[n]; b2 += v * px[n]
            }
            let det = a11 * a22 - a12 * a12
            guard abs(det) > 1e-6 else { break }
            var n0 = to565((a22 * b1 - a12 * b2) / det), n1 = to565((a11 * b2 - a12 * b1) / det)
            if n0 < n1 { swap(&n0, &n1) }
            guard n0 != n1 else { break }
            let (nb, ne) = index4(px, n0, n1)
            guard ne < err else { break }
            e0 = n0; e1 = n1; bits = nb; err = ne
        }
        if e0 == e1 { bits = 0 }
        return (e0, e1, bits)
    }
    /// BC1 in 3-colour mode (index 3 = transparent black) for a block with cut-outs:
    /// tools/texpack's bc1_punch, the same blocks
    static func punchBlock(_ px: UnsafePointer<V3>, _ alpha: UnsafePointer<Int>) -> (Int, Int, UInt32) {
        var lo = -1, hi = -1
        var lmin = Double.infinity, lmax = -Double.infinity
        for n in 0..<16 where alpha[n] >= 128 {
            let l = Double(px[n].x) * 0.299 + Double(px[n].y) * 0.587 + Double(px[n].z) * 0.114
            if l < lmin { lmin = l; lo = n }
            if l > lmax { lmax = l; hi = n }
        }
        guard lo >= 0 else { return (0, 0, 0xFFFF_FFFF) }                 // no texel: all transparent
        var c0 = to565(px[lo]), c1 = to565(px[hi])
        if c0 > c1 { swap(&c0, &c1) }                                    // c0 <= c1: 3-colour mode
        let p0 = from565(c0), p1 = from565(c1), p2 = (p0 + p1) / 2
        var bits: UInt32 = 0
        for n in 0..<16 {
            var best: UInt32 = 3
            if alpha[n] >= 128 {
                let c = SIMD3<Double>(Double(px[n].x), Double(px[n].y), Double(px[n].z))
                func dd(_ p: V3) -> Double { let d = c - SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z)); return (d * d).sum() }
                var bd = dd(p0); best = 0
                let e1 = dd(p1); if e1 < bd { bd = e1; best = 1 }
                if dd(p2) < bd { best = 2 }
            }
            bits |= best << (2 * UInt32(n))
        }
        return (c0, c1, bits)
    }
    /// BC3's alpha half: 8-value mode between the block's lowest and highest alpha
    @inline(__always) private static func alphaBlock(_ a: UnsafePointer<Int>, _ o: UnsafeMutablePointer<UInt8>) {
        var hi = 0, lo = 255
        for n in 0..<16 { hi = max(hi, a[n]); lo = min(lo, a[n]) }
        o[0] = UInt8(hi); o[1] = UInt8(lo)
        for i in 2..<8 { o[i] = 0 }
        guard hi > lo else { return }
        var vals = (hi, lo, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &vals) { vb in
            let v = vb.baseAddress!.assumingMemoryBound(to: Int.self)
            for i in 2..<8 { v[i] = ((8 - i) * hi + (i - 1) * lo) / 7 }
            var bits: UInt64 = 0
            for n in 0..<16 {
                var best = 0, bd = Int.max
                for j in 0..<8 { let d = abs(v[j] - a[n]); if d < bd { bd = d; best = j } }
                bits |= UInt64(best) << (3 * UInt64(n))
            }
            for i in 0..<6 { o[2 + i] = UInt8(truncatingIfNeeded: bits >> (8 * UInt64(i))) }
        }
    }
    @inline(__always) private static func putColor(_ o: UnsafeMutablePointer<UInt8>, _ c0: Int, _ c1: Int, _ bits: UInt32) {
        o[0] = UInt8(c0 & 255); o[1] = UInt8(c0 >> 8); o[2] = UInt8(c1 & 255); o[3] = UInt8(c1 >> 8)
        o[4] = UInt8(bits & 255); o[5] = UInt8((bits >> 8) & 255); o[6] = UInt8((bits >> 16) & 255); o[7] = UInt8(bits >> 24)
    }

    /// a level in the texture's own format
    static func encode(_ img: RGBA, _ fmt: TexFormat) -> [UInt8] {
        let w = img.w, h = img.h
        if fmt == .argb {
            var o = [UInt8](repeating: 0, count: w * h * 4)
            for i in 0..<(w * h) { o[i * 4] = img.px[i * 4 + 2]; o[i * 4 + 1] = img.px[i * 4 + 1]; o[i * 4 + 2] = img.px[i * 4]; o[i * 4 + 3] = img.px[i * 4 + 3] }
            return o
        }
        let bw = (w + 3) / 4, bh = (h + 3) / 4, bb = fmt.blockBytes
        var out = [UInt8](repeating: 0, count: bw * bh * bb)
        img.px.withUnsafeBufferPointer { sp in out.withUnsafeMutableBufferPointer { ob in
            let src = sp.baseAddress!, base = ob.baseAddress!
            DispatchQueue.concurrentPerform(iterations: bh) { by in
                let px = UnsafeMutablePointer<V3>.allocate(capacity: 16), al = UnsafeMutablePointer<Int>.allocate(capacity: 16)
                defer { px.deallocate(); al.deallocate() }
                for bx in 0..<bw {
                    var opaque = true
                    for n in 0..<16 {
                        let x = min(bx * 4 + n % 4, w - 1), y = min(by * 4 + n / 4, h - 1)     // "edge" padding
                        let p = src + (y * w + x) * 4
                        px[n] = V3(Float(p[0]), Float(p[1]), Float(p[2])); al[n] = Int(p[3])
                        if al[n] < 128 { opaque = false }
                    }
                    let o = base + (by * bw + bx) * bb
                    switch fmt {
                    case .dxt1:
                        let (c0, c1, bits) = opaque ? colorBlock(px) : punchBlock(px, al)
                        putColor(o, c0, c1, bits)
                    case .dxt3:
                        for i in 0..<8 { o[i] = 0 }
                        for n in 0..<16 {
                            let a4 = UInt8((al[n] * 15 + 127) / 255)
                            o[n / 2] |= n & 1 == 0 ? a4 : a4 << 4
                        }
                        let (c0, c1, bits) = colorBlock(px)
                        putColor(o + 8, c0, c1, bits)
                    default:
                        alphaBlock(al, o)
                        let (c0, c1, bits) = colorBlock(px)
                        putColor(o + 8, c0, c1, bits)
                    }
                }
            }
        } }
        return out
    }

    /// The DDS file of a pack texture: its levels, largest first.
    static func dds(_ w: Int, _ h: Int, _ fmt: TexFormat, _ levels: [[UInt8]]) -> Data {
        var hd = [UInt32](repeating: 0, count: 32)
        hd[0] = 0x2053_4444                                              // "DDS "
        hd[1] = 124; hd[2] = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000
        hd[3] = UInt32(h); hd[4] = UInt32(w); hd[7] = UInt32(levels.count)
        hd[19] = 32
        if fmt == .argb { hd[20] = 0x41; hd[22] = 32; hd[23] = 0x00ff_0000; hd[24] = 0x0000_ff00; hd[25] = 0x0000_00ff; hd[26] = 0xff00_0000 }
        else { hd[20] = 4; hd[21] = fmt.d3d }
        hd[27] = 0x1000 | 0x40_0000 | 0x8
        var d = Data(capacity: 128 + levels.reduce(0) { $0 + $1.count })
        for v in hd { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        for l in levels { d.append(contentsOf: l) }
        return d
    }
}
