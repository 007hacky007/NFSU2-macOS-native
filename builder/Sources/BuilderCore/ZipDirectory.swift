import Foundation

/// The member list of a zip file (the central directory: names, sizes, CRC-32), read without
/// unpacking anything. The discs keep the game in compressed.zip with Windows backslash names.
public struct ZipMember: Equatable {
    /// "/" between folders, normalised the way tools/install_from_discs.py unpacks it.
    public let path: String
    public let size: Int
    public let crc32: UInt32
    public let isDirectory: Bool
}

public enum ZipDirectory {
    /// `read(position, length)` returns bytes of the zip file of `size` bytes.
    public static func members(size: Int, read: (Int, Int) throws -> Data) throws -> [ZipMember] {
        let failure = DiscImage.Failure(message: "compressed.zip on the disc is damaged")
        let tail = min(size, 65_557)
        let end = [UInt8](try read(size - tail, tail))
        guard end.count == tail else { throw failure }
        var eocd = -1
        var i = end.count - 22
        while i >= 0 {
            if end[i] == 0x50, end[i + 1] == 0x4B, end[i + 2] == 0x05, end[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw failure }
        func u16(_ b: [UInt8], _ p: Int) -> Int { Int(b[p]) | Int(b[p + 1]) << 8 }
        func u32(_ b: [UInt8], _ p: Int) -> Int { u16(b, p) | u16(b, p + 2) << 16 }
        let count = u16(end, eocd + 10)
        let dirSize = u32(end, eocd + 12)
        let dirOffset = u32(end, eocd + 16)
        guard dirOffset + dirSize <= size, count != 0xFFFF else { throw failure }
        let dir = [UInt8](try read(dirOffset, dirSize))
        guard dir.count == dirSize else { throw failure }
        var result: [ZipMember] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= dir.count, u32(dir, p) == 0x0201_4B50 else { throw failure }
            let crc = UInt32(u32(dir, p + 16))
            let length = u32(dir, p + 24)
            let nameLength = u16(dir, p + 28), extra = u16(dir, p + 30), comment = u16(dir, p + 32)
            guard p + 46 + nameLength <= dir.count else { throw failure }
            let raw = Data(dir[(p + 46)..<(p + 46 + nameLength)])
            let name = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? ""
            let isDirectory = name.hasSuffix("/") || name.hasSuffix("\\")
            result.append(ZipMember(path: normalisedZipPath(name), size: length, crc32: crc, isDirectory: isDirectory))
            p += 46 + nameLength + extra + comment
        }
        return result
    }
}

/// Backslashes to "/", "." and empty parts dropped (posixpath.normpath of a relative name).
func normalisedZipPath(_ name: String) -> String {
    var parts: [Substring] = []
    for part in name.replacingOccurrences(of: "\\", with: "/").split(separator: "/") where part != "." {
        if part == "..", !parts.isEmpty { parts.removeLast() } else { parts.append(part) }
    }
    return parts.joined(separator: "/")
}
