// The upscaling model of the upscaled texture pack (UpscaleBuilder.swift): Kim2091's
// PBRify Upscaler SPAN v4 (CC0-1.0, github.com/Kim2091/PBRify_Remix), a 4x network for
// game textures, run on the Mac's GPU with MPSGraph.  SPAN (Wan et al., "Swift
// Parameter-free Attention Network for Efficient Super-Resolution", 2024) is a small
// convolutional network: 3x3 convolutions, SiLU, a sigmoid "attention" and a pixel
// shuffle; written here from the paper's structure as spandrel (MIT) and the model's
// own weights lay it out.  No Python, no PyTorch: the weights are read from the
// model's .pth file (a zip of stored entries with a pickled table of tensors) by a
// reader that knows only the few pickle operations and names such a table uses and
// refuses anything else, so no code from the file is ever run.  The file's SHA-256
// is checked first (UpscalePack.model).
import Foundation
import Metal
import MetalPerformanceShadersGraph

struct ModelFailure: Error { let message: String }

/// Tensors from a PyTorch .pth file (float32, contiguous).
struct TorchWeights {
    struct Tensor { var shape: [Int]; var values: [Float] }
    var tensors: [String: Tensor] = [:]

    init(file: URL) throws {
        let d = try Data(contentsOf: file)
        let entries = try Self.zipEntries(d)
        guard let pkl = entries.keys.first(where: { $0.hasSuffix("/data.pkl") }) ?? entries.keys.first(where: { $0 == "data.pkl" }) else {
            throw ModelFailure(message: "the model file has no weights table (data.pkl)")
        }
        let prefix = String(pkl.dropLast("data.pkl".count))
        if let bo = entries[prefix + "byteorder"], String(decoding: d[bo], as: UTF8.self) != "little" {
            throw ModelFailure(message: "the model file is not little-endian")
        }
        var up = Unpickler(d[entries[pkl]!])
        let root = try up.run()
        var table = root
        if case .dict(let items) = root, items.count == 1, case .str = items[0].0, case .dict = items[0].1 { table = items[0].1 }   // {"params": ...}
        guard case .dict(let items) = table else { throw ModelFailure(message: "the weights table is not a table") }
        for (k, v) in items {
            guard case .str(let name) = k, case .tensor(let key, let offset, let shape, let stride) = v else { continue }
            guard let r = entries[prefix + "data/" + key] else { throw ModelFailure(message: "the model file lacks tensor data \(key)") }
            // any strides (the model stores some weights channels-last): gathered into row-major order
            let count = shape.reduce(1, *)
            guard shape.count == stride.count, shape.allSatisfy({ $0 > 0 }), stride.allSatisfy({ $0 >= 0 }) else {
                throw ModelFailure(message: "tensor \(name) has a bad shape")
            }
            let span = zip(shape, stride).reduce(1) { $0 + ($1.0 - 1) * $1.1 }
            guard offset >= 0, (offset + span) * 4 <= r.count else { throw ModelFailure(message: "tensor \(name) is out of its data") }
            var src = [Float](repeating: 0, count: span)
            _ = src.withUnsafeMutableBytes { dst in
                d.copyBytes(to: dst, from: (r.lowerBound + offset * 4)..<(r.lowerBound + (offset + span) * 4))
            }
            var vals = [Float](repeating: 0, count: count)
            var idx = [Int](repeating: 0, count: shape.count)
            for e in 0..<count {
                var o = 0
                for k in 0..<shape.count { o += idx[k] * stride[k] }
                vals[e] = src[o]
                var k = shape.count - 1
                while k >= 0 { idx[k] += 1; if idx[k] < shape[k] { break }; idx[k] = 0; k -= 1 }
            }
            tensors[name] = Tensor(shape: shape, values: vals)
        }
    }

    /// name -> byte range of each stored zip member
    static func zipEntries(_ d: Data) throws -> [String: Range<Int>] {
        func u16(_ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let n = d.count
        guard n >= 22 else { throw ModelFailure(message: "the model file is not a zip") }
        var eocd = -1
        var o = n - 22
        while o >= max(0, n - 22 - 65536) { if u32(o) == 0x06054b50 { eocd = o; break }; o -= 1 }
        guard eocd >= 0 else { throw ModelFailure(message: "the model file is not a zip") }
        var count = u16(eocd + 10), cd = u32(eocd + 16)
        if count == 0xFFFF || cd == 0xFFFF_FFFF {                        // zip64 (PyTorch writes it for large files)
            let loc = eocd - 20
            guard loc >= 0, u32(loc) == 0x07064b50 else { throw ModelFailure(message: "the model file's zip directory cannot be read") }
            let z = u32(loc + 8)
            guard z + 56 <= n, u32(z) == 0x06064b50 else { throw ModelFailure(message: "the model file's zip directory cannot be read") }
            count = u32(z + 32); cd = u32(z + 48)
        }
        var out: [String: Range<Int>] = [:]
        var p = cd
        for _ in 0..<count {
            guard p + 46 <= n, u32(p) == 0x02014b50 else { throw ModelFailure(message: "the model file's zip directory is damaged") }
            let method = u16(p + 10)
            var size = u32(p + 20), lho = u32(p + 42)
            let nl = u16(p + 28), xl = u16(p + 30), cl = u16(p + 32)
            guard p + 46 + nl <= n else { throw ModelFailure(message: "the model file's zip directory is damaged") }
            let name = String(decoding: d[(d.startIndex + p + 46)..<(d.startIndex + p + 46 + nl)], as: UTF8.self)
            var x = p + 46 + nl
            while x + 4 <= p + 46 + nl + xl {                            // zip64 extra field
                let id = u16(x), len = u16(x + 2)
                if id == 1 {
                    var q = x + 4
                    if u32(p + 24) == 0xFFFF_FFFF { q += 8 }
                    if size == 0xFFFF_FFFF { size = u32(q); q += 8 }
                    if lho == 0xFFFF_FFFF { lho = u32(q) }
                }
                x += 4 + len
            }
            guard method == 0 else { throw ModelFailure(message: "the model file has a compressed member (\(name))") }
            guard lho + 30 <= n, u32(lho) == 0x04034b50 else { throw ModelFailure(message: "the model file's zip member \(name) is damaged") }
            let start = lho + 30 + u16(lho + 26) + u16(lho + 28)
            guard start + size <= n else { throw ModelFailure(message: "the model file's zip member \(name) is cut short") }
            out[name] = (d.startIndex + start)..<(d.startIndex + start + size)
            p += 46 + nl + xl + cl
        }
        return out
    }
}

/// The pickle subset of a PyTorch state dict (protocol 2): tuples, dicts, strings, ints,
/// OrderedDict, and tensors from torch._utils._rebuild_tensor_v2 over FloatStorage.
/// Any other operation or name is refused.
private struct Unpickler {
    indirect enum V {
        case none, bool(Bool), int(Int), str(String), tuple([V]), list([V]), dict([(V, V)])
        case global(String), storage(String), tensor(String, Int, [Int], [Int]), mark
    }
    let b: [UInt8]
    var pos = 0
    var stack: [V] = []
    var memo: [Int: V] = [:]
    init(_ d: Data) { b = [UInt8](d) }

    mutating func u8() throws -> Int { guard pos < b.count else { throw bad("ends early") }; pos += 1; return Int(b[pos - 1]) }
    mutating func le(_ n: Int) throws -> Int {
        guard pos + n <= b.count else { throw bad("ends early") }
        var v = 0
        for i in 0..<n { v |= Int(b[pos + i]) << (8 * i) }
        pos += n
        return v
    }
    mutating func line() throws -> String {
        guard let e = b[pos...].firstIndex(of: 10) else { throw bad("ends early") }
        let s = String(decoding: b[pos..<e], as: UTF8.self); pos = e + 1; return s
    }
    func bad(_ s: String) -> ModelFailure { ModelFailure(message: "the model's weights table cannot be read (\(s))") }
    mutating func pop() throws -> V { guard let v = stack.popLast() else { throw bad("stack") }; return v }
    mutating func popMark() throws -> [V] {
        guard let m = stack.lastIndex(where: { if case .mark = $0 { return true }; return false }) else { throw bad("mark") }
        let items = Array(stack[(m + 1)...]); stack.removeSubrange(m...); return items
    }
    func ints(_ v: V) throws -> [Int] {
        guard case .tuple(let t) = v else { throw bad("shape") }
        return try t.map { if case .int(let i) = $0 { return i }; throw bad("shape") }
    }
    mutating func setItems(_ items: [V]) throws {
        guard items.count % 2 == 0, case .dict(var d) = try pop() else { throw bad("setitems") }
        for i in stride(from: 0, to: items.count, by: 2) { d.append((items[i], items[i + 1])) }
        stack.append(.dict(d))
    }

    mutating func run() throws -> V {
        while true {
            let op = try u8()
            switch op {
            case 0x80: _ = try u8()                                         // PROTO
            case 0x2E: return try pop()                                     // STOP
            case 0x7D: stack.append(.dict([]))                              // EMPTY_DICT
            case 0x5D: stack.append(.list([]))                              // EMPTY_LIST
            case 0x29: stack.append(.tuple([]))                             // EMPTY_TUPLE
            case 0x28: stack.append(.mark)                                  // MARK
            case 0x74: stack.append(.tuple(try popMark()))                  // TUPLE
            case 0x85: stack.append(.tuple([try pop()]))                    // TUPLE1
            case 0x86: let b2 = try pop(), a = try pop(); stack.append(.tuple([a, b2]))
            case 0x87: let c = try pop(), b2 = try pop(), a = try pop(); stack.append(.tuple([a, b2, c]))
            case 0x88: stack.append(.bool(true))                            // NEWTRUE
            case 0x89: stack.append(.bool(false))                           // NEWFALSE
            case 0x4E: stack.append(.none)                                  // NONE
            case 0x4B: stack.append(.int(try le(1)))                        // BININT1
            case 0x4D: stack.append(.int(try le(2)))                        // BININT2
            case 0x4A: stack.append(.int(Int(Int32(truncatingIfNeeded: try le(4)))))   // BININT
            case 0x8A:                                                      // LONG1
                let n = try u8(); guard n <= 8 else { throw bad("long") }
                var v = try le(n); if n > 0 && n < 8 && (v >> (8 * n - 1)) & 1 == 1 { v -= 1 << (8 * n) }
                stack.append(.int(v))
            case 0x58: let n = try le(4); guard pos + n <= b.count else { throw bad("ends early") }   // BINUNICODE
                stack.append(.str(String(decoding: b[pos..<(pos + n)], as: UTF8.self))); pos += n
            case 0x8C: let n = try u8(); guard pos + n <= b.count else { throw bad("ends early") }    // SHORT_BINUNICODE
                stack.append(.str(String(decoding: b[pos..<(pos + n)], as: UTF8.self))); pos += n
            case 0x71: guard let v = stack.last else { throw bad("put") }; memo[try le(1)] = v       // BINPUT
            case 0x72: guard let v = stack.last else { throw bad("put") }; memo[try le(4)] = v       // LONG_BINPUT
            case 0x94: guard let v = stack.last else { throw bad("put") }; memo[memo.count] = v      // MEMOIZE
            case 0x68: guard let v = memo[try le(1)] else { throw bad("get") }; stack.append(v)      // BINGET
            case 0x6A: guard let v = memo[try le(4)] else { throw bad("get") }; stack.append(v)      // LONG_BINGET
            case 0x63:                                                      // GLOBAL
                let name = try line() + " " + line()
                guard ["collections OrderedDict", "torch._utils _rebuild_tensor_v2", "torch FloatStorage"].contains(name) else {
                    throw bad("refused name \(name)")
                }
                stack.append(.global(name))
            case 0x51:                                                      // BINPERSID
                guard case .tuple(let t) = try pop(), t.count >= 3, case .str("storage") = t[0],
                      case .global("torch FloatStorage") = t[1], case .str(let key) = t[2] else { throw bad("storage") }
                stack.append(.storage(key))
            case 0x52:                                                      // REDUCE
                let args = try pop(), f = try pop()
                guard case .global(let g) = f, case .tuple(let a) = args else { throw bad("reduce") }
                if g == "collections OrderedDict" { stack.append(.dict([])) }
                else if g == "torch._utils _rebuild_tensor_v2", a.count >= 4, case .storage(let key) = a[0], case .int(let off) = a[1] {
                    stack.append(.tensor(key, off, try ints(a[2]), try ints(a[3])))
                } else { throw bad("reduce \(g)") }
            case 0x73: let v = try pop(), k = try pop(); try setItems([k, v])                       // SETITEM
            case 0x75: try setItems(try popMark())                          // SETITEMS
            case 0x62: _ = try pop()                                        // BUILD (an OrderedDict's metadata: not needed)
            case 0x65:                                                      // APPENDS
                let items = try popMark(); guard case .list(var l) = try pop() else { throw bad("appends") }
                l.append(contentsOf: items); stack.append(.list(l))
            case 0x61:                                                      // APPEND
                let v = try pop(); guard case .list(var l) = try pop() else { throw bad("append") }
                l.append(v); stack.append(.list(l))
            default: throw bad(String(format: "operation 0x%02x", op))
            }
        }
    }
}

/// SPAN on the GPU: rgb (H x W x 3, 0..1) -> 4x (4H x 4W x 3, 0..1).
final class SPANUpscaler {
    let scale = 4
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private struct Conv { var w: [Float]; var b: [Float]; var o: Int; var i: Int; var k: Int }
    private var convs: [String: Conv] = [:]
    private var graphs: [String: (MPSGraph, MPSGraphTensor, MPSGraphTensor)] = [:]
    private var recent: [String] = []                   // graph keys, last used last (at most maxGraphs kept)
    private let maxGraphs = 12                          // each holds its compiled form, 10 to 100 MB
    private let lock = NSLock()
    let name: String

    init(weights: TorchWeights) throws {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else {
            throw ModelFailure(message: "this Mac has no Metal GPU for the model")
        }
        device = dev; queue = q; name = "SPAN on \(dev.name)"
        let t = weights.tensors
        func get(_ n: String) throws -> TorchWeights.Tensor {
            guard let v = t[n] else { throw ModelFailure(message: "the model lacks \(n): not PBRify Upscaler SPAN") }
            return v
        }
        // Conv3XC: 1x1 -> 3x3 -> 1x1 plus a 1x1 skip, folded into one 3x3 convolution
        // (spandrel's update_params, which its eval mode runs before every forward)
        func fold(_ p: String) throws -> Conv {
            let w1 = try get(p + ".conv.0.weight"), b1 = try get(p + ".conv.0.bias")
            let w2 = try get(p + ".conv.1.weight"), b2 = try get(p + ".conv.1.bias")
            let w3 = try get(p + ".conv.2.weight"), b3 = try get(p + ".conv.2.bias")
            let sk = try get(p + ".sk.weight"), skb = try get(p + ".sk.bias")
            let cin = w1.shape[1], g1 = w1.shape[0], g2 = w2.shape[0], cout = w3.shape[0]
            guard w2.shape == [g2, g1, 3, 3], w3.shape == [cout, g2, 1, 1], sk.shape == [cout, cin, 1, 1] else {
                throw ModelFailure(message: "the model's \(p) has an unexpected shape")
            }
            // W12[m][i][ky][kx] = sum_n w2[m][n][ky][kx] * w1[n][i]
            var w12 = [Double](repeating: 0, count: g2 * cin * 9)
            for m in 0..<g2 { for n in 0..<g1 { for i in 0..<cin {
                let a = Double(w1.values[n * cin + i])
                for k in 0..<9 { w12[(m * cin + i) * 9 + k] += Double(w2.values[(m * g1 + n) * 9 + k]) * a }
            } } }
            var w = [Float](repeating: 0, count: cout * cin * 9), bias = [Float](repeating: 0, count: cout)
            for o in 0..<cout {
                var acc = [Double](repeating: 0, count: cin * 9)
                for m in 0..<g2 {
                    let a = Double(w3.values[o * g2 + m])
                    for j in 0..<(cin * 9) { acc[j] += a * w12[m * cin * 9 + j] }
                }
                for i in 0..<cin { acc[i * 9 + 4] += Double(sk.values[o * cin + i]) }
                for j in 0..<(cin * 9) { w[o * cin * 9 + j] = Float(acc[j]) }
            }
            // b12[m] = sum over n, kernel of w2 * b1[n] + b2[m]
            var b12 = [Double](repeating: 0, count: g2)
            for m in 0..<g2 {
                var s = Double(b2.values[m])
                for n in 0..<g1 { for k in 0..<9 { s += Double(w2.values[(m * g1 + n) * 9 + k]) * Double(b1.values[n]) } }
                b12[m] = s
            }
            for o in 0..<cout {
                var s = Double(b3.values[o]) + Double(skb.values[o])
                for m in 0..<g2 { s += Double(w3.values[o * g2 + m]) * b12[m] }
                bias[o] = Float(s)
            }
            return Conv(w: w, b: bias, o: cout, i: cin, k: 3)
        }
        func plain(_ p: String) throws -> Conv {
            let w = try get(p + ".weight"), b = try get(p + ".bias")
            return Conv(w: w.values, b: b.values, o: w.shape[0], i: w.shape[1], k: w.shape[2])
        }
        convs["conv_1"] = try fold("conv_1")
        for i in 1...6 { for c in ["c1_r", "c2_r", "c3_r"] { convs["block_\(i).\(c)"] = try fold("block_\(i).\(c)") } }
        convs["conv_2"] = try fold("conv_2")
        convs["conv_cat"] = try plain("conv_cat")
        convs["upsampler"] = try plain("upsampler.0")
        guard let c1 = convs["conv_1"], c1.i == 3, let up = convs["upsampler"], up.o == 3 * 16, t["no_norm"] != nil else {
            throw ModelFailure(message: "the model is not a 4x SPAN without input normalisation (PBRify Upscaler SPAN v4)")
        }
    }

    private func graph(_ h: Int, _ w: Int) -> (MPSGraph, MPSGraphTensor, MPSGraphTensor) {
        let key = "\(h)x\(w)"
        lock.lock(); defer { lock.unlock() }
        if let i = recent.firstIndex(of: key) { recent.remove(at: i) }
        recent.append(key)
        if let g = graphs[key] { return g }
        while recent.count > maxGraphs { graphs[recent.removeFirst()] = nil }
        let g = MPSGraph()
        let x = g.placeholder(shape: [1, 3, NSNumber(value: h), NSNumber(value: w)], dataType: .float32, name: nil)
        func conv(_ t: MPSGraphTensor, _ n: String) -> MPSGraphTensor {
            let c = convs[n]!
            let p = c.k / 2
            let d = MPSGraphConvolution2DOpDescriptor(strideInX: 1, strideInY: 1, dilationRateInX: 1, dilationRateInY: 1,
                                                       groups: 1, paddingLeft: p, paddingRight: p, paddingTop: p, paddingBottom: p,
                                                       paddingStyle: .explicit, dataLayout: .NCHW, weightsLayout: .OIHW)!
            let wt = g.constant(c.w.withUnsafeBufferPointer { Data(buffer: $0) },
                                shape: [NSNumber(value: c.o), NSNumber(value: c.i), NSNumber(value: c.k), NSNumber(value: c.k)], dataType: .float32)
            let bt = g.constant(c.b.withUnsafeBufferPointer { Data(buffer: $0) },
                                shape: [1, NSNumber(value: c.o), 1, 1], dataType: .float32)
            return g.addition(g.convolution2D(t, weights: wt, descriptor: d, name: nil), bt, name: nil)
        }
        func silu(_ t: MPSGraphTensor) -> MPSGraphTensor { g.multiplication(t, g.sigmoid(with: t, name: nil), name: nil) }
        let half = g.constant(0.5, dataType: .float32)
        func spab(_ t: MPSGraphTensor, _ n: String) -> (MPSGraphTensor, MPSGraphTensor) {
            // the second result is out1 after SiLU: spandrel's SiLU(inplace=True) changes out1 itself
            let o1 = silu(conv(t, n + ".c1_r"))
            let o2 = conv(o1, n + ".c2_r")
            let o3 = conv(silu(o2), n + ".c3_r")
            let att = g.subtraction(g.sigmoid(with: o3, name: nil), half, name: nil)
            return (g.multiplication(g.addition(o3, t, name: nil), att, name: nil), o1)
        }
        let f = conv(x, "conv_1")
        let (b1, _) = spab(f, "block_1")
        var b = b1
        for i in 2...5 { b = spab(b, "block_\(i)").0 }
        let (b6, b5_2) = spab(b, "block_6")
        let c2 = conv(b6, "conv_2")
        let cat = conv(g.concatTensors([f, c2, b1, b5_2], dimension: 1, name: nil), "conv_cat")
        let y = conv(cat, "upsampler")
        let r = (g, x, y)
        graphs[key] = r
        return r
    }

    /// One pass over an input of h x w (CHW planes, 0..1) -> 48 x h x w (before the pixel shuffle).
    private func run(_ chw: [Float], _ h: Int, _ w: Int) throws -> [Float] {
        let (g, x, y) = graph(h, w)
        // MPSGraph hands back autoreleased results: without a pool of its own, the build's one
        // long loop would keep every tile's result until it ends (gigabytes)
        return try autoreleasepool {
            guard let buf = chw.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
                throw ModelFailure(message: "out of GPU memory")
            }
            let td = MPSGraphTensorData(buf, shape: [1, 3, NSNumber(value: h), NSNumber(value: w)], dataType: .float32)
            let out = g.run(with: queue, feeds: [x: td], targetTensors: [y], targetOperations: nil)
            guard let r = out[y] else { throw ModelFailure(message: "the model did not run") }
            var v = [Float](repeating: 0, count: 48 * h * w)
            v.withUnsafeMutableBytes { r.mpsndarray().readBytes($0.baseAddress!, strideBytes: nil) }
            return v
        }
    }

    /// rgb: h x w x 3 bytes; -> (4h x 4w x 3) floats in 0..1.  Tiles as tools/texpack did
    /// (the whole picture up to 320 x 320, otherwise 192-texel tiles with 16 of overlap).
    func upscale(_ rgb: [UInt8], _ h: Int, _ w: Int) throws -> [Float] {
        let s = scale
        var out = [Float](repeating: 0, count: h * s * w * s * 3)
        func tile(_ y0: Int, _ y1: Int, _ x0: Int, _ x1: Int, _ ya: Int, _ yb: Int, _ xa: Int, _ xb: Int) throws {
            let th = yb - ya, tw = xb - xa
            var chw = [Float](repeating: 0, count: 3 * th * tw)
            rgb.withUnsafeBufferPointer { src in chw.withUnsafeMutableBufferPointer { dst in
                for c in 0..<3 { for yy in 0..<th { for xx in 0..<tw {
                    dst[(c * th + yy) * tw + xx] = Float(src[((ya + yy) * w + xa + xx) * 3 + c]) / 255
                } } }
            } }
            let r = try run(chw, th, tw)
            // pixel shuffle: out[c][y*4+i][x*4+j] = in[c*16 + i*4 + j][y][x]; keep this tile's own part
            let ow = w * s
            r.withUnsafeBufferPointer { rb in out.withUnsafeMutableBufferPointer { ob in
                let rp = rb.baseAddress!, op = ob.baseAddress!
                for c in 0..<3 { for i in 0..<s { for j in 0..<s {
                    let plane = rp + (c * 16 + i * 4 + j) * th * tw
                    for yy in (y0 - ya)..<(y1 - ya) {
                        let row = plane + yy * tw, orow = op + (((ya + yy) * s + i) * ow) * 3
                        for xx in (x0 - xa)..<(x1 - xa) {
                            orow[((xa + xx) * s + j) * 3 + c] = min(max(row[xx], 0), 1)
                        }
                    }
                } } }
            } }
        }
        if h * w <= 320 * 320 { try tile(0, h, 0, w, 0, h, 0, w); return out }
        let T = 192, O = 16
        for y0 in stride(from: 0, to: h, by: T) {
            for x0 in stride(from: 0, to: w, by: T) {
                let y1 = min(y0 + T, h), x1 = min(x0 + T, w)
                try tile(y0, y1, x0, x1, max(y0 - O, 0), min(y1 + O, h), max(x0 - O, 0), min(x1 + O, w))
            }
        }
        return out
    }
}
