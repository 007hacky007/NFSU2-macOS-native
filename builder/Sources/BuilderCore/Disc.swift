import Foundation

/// Reads the files of an ISO 9660 / Joliet disc image: a 2048-byte-sector .iso or a raw
/// MODE1/2352 .bin (the format of a .cue's track). Read only; the image is never written.
/// The same job as tools/disc.py, which tools/install_from_discs.py uses to unpack the discs.
public final class DiscImage {
    public struct Entry {
        /// Path on the disc, "/" between folders, as the disc spells it.
        public let path: String
        public let extent: Int
        public let size: Int
    }

    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public let url: URL
    private let fd: Int32
    private let stride: Int
    private let offset: Int
    private let sectors: Int
    private var root = Data()
    private var joliet = false

    /// `url` is an .iso or .bin image; a .cue is resolved to its .bin with `cueImage` first.
    public init(_ url: URL) throws {
        self.url = url
        fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            throw Failure(message: "Could not open \(url.lastPathComponent)")
        }
        var info = stat()
        let size = fstat(fd, &info) == 0 ? Int(info.st_size) : 0
        let sync = Data([0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00])
        if Self.pread(fd, at: 16 * 2352, count: 12) == sync {
            (stride, offset) = (2352, 16)
        } else {
            (stride, offset) = (2048, 0)
        }
        sectors = size / stride
        guard size >= 17 * 2048 else {
            throw Failure(message: "\(url.lastPathComponent) is not a complete disc image")
        }
        var found: Data?
        for lba in 16..<min(sectors, 80) {
            let descriptor = try read(extent: lba, size: 2048)
            guard descriptor.count == 2048, descriptor[1...5] == Data("CD001".utf8) else {
                throw Failure(message: "\(url.lastPathComponent) is not a CD image (no ISO 9660 volume)")
            }
            let kind = descriptor[0]
            if kind == 255 { break }
            let isJoliet = kind == 2 && [Data("%/@".utf8), Data("%/C".utf8), Data("%/E".utf8)].contains(descriptor[88..<91])
            if (kind == 1 && found == nil) || isJoliet {
                found = descriptor[156..<190]
                joliet = isJoliet
            }
        }
        guard let rootRecord = found else {
            throw Failure(message: "\(url.lastPathComponent) is not a CD image (no ISO 9660 volume)")
        }
        root = rootRecord
    }

    deinit { close(fd) }

    /// Positioned read, safe from several threads at once.
    private static func pread(_ fd: Int32, at position: Int, count: Int) -> Data {
        var data = Data(count: count)
        var done = 0
        data.withUnsafeMutableBytes { buffer in
            while done < count {
                let n = Darwin.pread(fd, buffer.baseAddress! + done, count - done, off_t(position + done))
                if n <= 0 { break }
                done += n
            }
        }
        return data.prefix(done)
    }

    /// Reads `size` bytes of user data starting at sector `extent`.
    public func read(extent: Int, size: Int) throws -> Data {
        let count = (size + 2047) / 2048
        guard extent >= 0, size >= 0, extent + count <= sectors else {
            throw Failure(message: "\(url.lastPathComponent) is truncated")
        }
        let raw = Self.pread(fd, at: extent * stride, count: count * stride)
        guard raw.count == count * stride else { throw Failure(message: "\(url.lastPathComponent) is truncated") }
        if stride == 2048 { return raw.prefix(size) }
        var data = Data(capacity: count * 2048)
        raw.withUnsafeBytes { bytes in
            for i in 0..<count {
                let start = i * stride + offset
                data.append(contentsOf: bytes[start..<start + 2048])
            }
        }
        return data.prefix(size)
    }

    /// Reads `length` bytes at byte `position` of a file that starts at sector `extent`.
    public func read(extent: Int, at position: Int, length: Int) throws -> Data {
        let first = position / 2048
        let skip = position % 2048
        let data = try read(extent: extent + first, size: skip + length)
        return data.subdata(in: data.startIndex + skip..<data.startIndex + min(data.count, skip + length))
    }

    /// Streams a file's bytes in chunks.
    public func stream(_ entry: Entry, chunk: Int = 1 << 20, _ body: (Data) -> Void) throws {
        var left = entry.size, extent = entry.extent
        while left > 0 {
            let size = min(left, chunk)
            body(try read(extent: extent, size: size))
            extent += (size + 2047) / 2048
            left -= size
        }
    }

    private static func location(_ record: Data) -> (extent: Int, size: Int) {
        let b = [UInt8](record)
        let extent = Int(b[2]) | Int(b[3]) << 8 | Int(b[4]) << 16 | Int(b[5]) << 24
        let size = Int(b[10]) | Int(b[11]) << 8 | Int(b[12]) << 16 | Int(b[13]) << 24
        return (extent, size)
    }

    /// Every file on the disc.
    public func entries() throws -> [Entry] {
        var result: [Entry] = []
        var seen = Set<Int>()
        func walk(_ record: Data, _ parent: String, _ depth: Int) throws {
            guard depth <= 32 else { throw Failure(message: "\(url.lastPathComponent): folders nested too deep") }
            let (extent, size) = Self.location(record)
            guard seen.insert(extent).inserted else { return }
            let data = [UInt8](try read(extent: extent, size: size))
            var at = 0
            while at < data.count {
                let length = Int(data[at])
                if length == 0 {
                    at = (at / 2048 + 1) * 2048
                    continue
                }
                guard length >= 34, at + length <= data.count else {
                    throw Failure(message: "\(url.lastPathComponent): damaged folder record")
                }
                let child = Data(data[at..<at + length])
                at += length
                let nameLength = Int(child[32])
                guard nameLength > 0, 33 + nameLength <= length else { continue }
                let ident = child[33..<33 + nameLength]
                if ident == Data([0]) || ident == Data([1]) { continue }
                var name = (joliet ? String(data: ident, encoding: .utf16BigEndian) : String(data: ident, encoding: .ascii)) ?? ""
                if let semicolon = name.lastIndex(of: ";") { name = String(name[..<semicolon]) }
                if !joliet, name.hasSuffix(".") { name.removeLast() }
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { continue }
                let path = parent.isEmpty ? name : parent + "/" + name
                if child[25] & 2 != 0 {
                    try walk(child, path, depth + 1)
                } else {
                    let loc = Self.location(child)
                    result.append(Entry(path: path, extent: loc.extent, size: loc.size))
                }
            }
        }
        try walk(root, "", 0)
        return result
    }
}

/// The image a .cue names on its FILE line (beside the .cue), as tools/install_from_discs.py reads it.
public func cueImage(_ cue: URL) throws -> URL {
    guard let text = (try? String(contentsOf: cue, encoding: .utf8)) ?? (try? String(contentsOf: cue, encoding: .isoLatin1)) else {
        throw DiscImage.Failure(message: "Could not read \(cue.lastPathComponent)")
    }
    for line in text.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.uppercased().hasPrefix("FILE") else { continue }
        var name: String
        if let open = trimmed.firstIndex(of: "\""), let close = trimmed[trimmed.index(after: open)...].firstIndex(of: "\"") {
            name = String(trimmed[trimmed.index(after: open)..<close])
        } else {
            let parts = trimmed.split(separator: " ")
            guard parts.count >= 2 else { break }
            name = String(parts[1])
        }
        name = String(name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? "")
        let image = cue.deletingLastPathComponent().appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: image.path) else {
            throw DiscImage.Failure(message: "\(cue.lastPathComponent) names \(name), which is not next to it")
        }
        return image
    }
    throw DiscImage.Failure(message: "\(cue.lastPathComponent) names no disc image")
}
