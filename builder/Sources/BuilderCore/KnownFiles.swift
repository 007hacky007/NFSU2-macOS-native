import Foundation

public enum Region: String, Equatable {
    case eu, na
}

/// A SPEED2.EXE the Builder recognises: the two it can build from, and the ones it explains.
public struct KnownProgram: Equatable {
    public enum Kind: Equatable {
        case supported(Region)
        /// The retail disc executable (SafeDisc).
        case disc
        /// SPEED2.EXE as EA's official v1.2 patch leaves it (still SafeDisc).
        case officialPatch
    }

    public let name: String
    public let size: Int
    public let sha256: String
    public let crc32: UInt32?
    public let kind: Kind

    public init(name: String, size: Int, sha256: String, crc32: UInt32?, kind: Kind) {
        (self.name, self.size, self.sha256, self.crc32, self.kind) = (name, size, sha256, crc32, kind)
    }

    /// The same two files as tools/gen_v2.sh and the launcher (launcher/Game.swift) accept.
    public static let supported = [
        KnownProgram(name: "European v1.2, no CD check", size: 4_788_224,
                     sha256: "8f6a9ae2c4cfa01181d2fd755d99c6f4b7103f60273908ea1de1e719dfe2a297", crc32: 0x4CDF_CFCD,
                     kind: .supported(.eu)),
        KnownProgram(name: "North American v1.2, no CD check", size: 4_800_512,
                     sha256: "f9dd86c054878ce6276beb07c1fd61874f7a1e4bf1f241b084c65b73e24168a7", crc32: 0xEC6B_0419,
                     kind: .supported(.na)),
    ]

    public static let all = supported + [
        KnownProgram(name: "European v1.0 disc", size: 5_987_980,
                     sha256: "bf94f3664398bf33eb91bcecaba627893ffd20bb64d813c6e5b2b9f3062cd3ac", crc32: 0x8D99_9C0F, kind: .disc),
        KnownProgram(name: "US v1.0 disc", size: 5_987_981,
                     sha256: "2cbd698fee8338a13d1891bc17d27e6641b4b9dd40580de818594b9140222899", crc32: nil, kind: .disc),
        KnownProgram(name: "European v1.2, EA's official patch", size: 5_987_979,
                     sha256: "7442cb462d043c2780ba80a7b84cb548320b4c8b36256993c5e6c28d4290f422", crc32: 0x3958_56D1,
                     kind: .officialPatch),
    ]
}

public enum ProgramVerdict: Equatable {
    case supported(Region, name: String)
    case refused(String)

    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }
}

public enum ProgramMessages {
    public static let needed = "The build needs v1.2 without the CD check."
    public static let disc = "This is the copy-protected disc version. " + needed
    public static let officialPatch = "This is EA's official v1.2 patch, which keeps the disc's copy protection. " + needed
    public static let protected = "This SPEED2.EXE is copy-protected. " + needed
    public static let notProgram = "This is not a Windows program. Choose SPEED2.EXE, or an archive (zip, rar or 7z) that holds it."
    public static func unknown(_ size: Int) -> String {
        "This SPEED2.EXE (\(grouped(size)) bytes) is not one of the two supported versions. " + needed
    }
}

/// `sha256` when the bytes could be hashed, otherwise `crc32` (from a zip's directory).
/// `header` is the start of the file (4 KB), used to tell a copy-protected build.
public func programVerdict(size: Int, sha256: String?, crc32: UInt32?, header: Data?,
                           known: [KnownProgram] = KnownProgram.all) -> ProgramVerdict {
    let match = known.first { program in
        guard program.size == size else { return false }
        if let sha256 = sha256 { return program.sha256 == sha256.lowercased() }
        if let crc32 = crc32, let expected = program.crc32 { return expected == crc32 }
        return false
    }
    switch match?.kind {
    case let .supported(region)?: return .supported(region, name: match!.name)
    case .disc?: return .refused(ProgramMessages.disc)
    case .officialPatch?: return .refused(ProgramMessages.officialPatch)
    case nil: break
    }
    if let header = header {
        guard let sections = peSections(header) else { return .refused(ProgramMessages.notProgram) }
        if sections.contains(where: { $0.hasPrefix("stxt") }) { return .refused(ProgramMessages.protected) }
    }
    return .refused(ProgramMessages.unknown(size))
}

/// Section names of a PE file from its first bytes, or nil when it is not one.
func peSections(_ header: Data) -> [String]? {
    let b = [UInt8](header)
    guard b.count >= 64, b[0] == 0x4D, b[1] == 0x5A else { return nil }
    let pe = Int(b[0x3C]) | Int(b[0x3D]) << 8 | Int(b[0x3E]) << 16 | Int(b[0x3F]) << 24
    guard pe > 0, pe + 24 <= b.count, b[pe] == 0x50, b[pe + 1] == 0x45, b[pe + 2] == 0, b[pe + 3] == 0 else { return nil }
    let count = Int(b[pe + 6]) | Int(b[pe + 7]) << 8
    let optional = Int(b[pe + 20]) | Int(b[pe + 21]) << 8
    var names: [String] = []
    var at = pe + 24 + optional
    for _ in 0..<count where at + 40 <= b.count {
        let raw = b[at..<at + 8].prefix { $0 != 0 }
        names.append(String(decoding: raw, as: UTF8.self))
        at += 40
    }
    return names
}

/// server.dll, EA's LAN server: both versions work.
public struct KnownServer: Equatable {
    public let name: String
    public let size: Int
    public let sha256: String
    public let crc32: UInt32

    public static let all = [
        KnownServer(name: "v1.0", size: 286_720, sha256: "3ba66b7401857d4b74d118b1cb2dba5833f3978f6e2da9500465ac8db354a24d", crc32: 0x5228_21DC),
        KnownServer(name: "v1.2", size: 286_720, sha256: "a5f50324adeabedca748449965e5e0f409b0cfce065cd0ffb7975d06d55ba9e4", crc32: 0x589F_4CA3),
    ]
}

/// The game files of the known releases (tools/known_releases.tsv, written by
/// tools/release_manifest.py): path, size, SHA-256 and CRC-32 per release, and which files
/// the game opens when it starts (the core files, checked by name).
public struct ReleaseManifest {
    public struct Release: Equatable {
        public let id: String
        public let name: String
    }

    public struct File: Equatable {
        public let path: String
        public let size: Int
        public let sha256: String
        public let crc32: UInt32
        public let releases: Set<String>
        public let core: Bool
    }

    public let releases: [Release]
    /// By lower-case path; a path can have one entry per distinct content.
    public let files: [String: [File]]

    public var corePaths: [String] {
        files.values.compactMap { $0.first(where: { $0.core })?.path }.sorted()
    }

    public init(text: String) throws {
        var releases: [Release] = []
        var files: [String: [File]] = [:]
        for (number, line) in text.components(separatedBy: "\n").enumerated() where !line.isEmpty && !line.hasPrefix("#") {
            let fields = line.components(separatedBy: "\t")
            switch fields.first {
            case "release" where fields.count >= 3:
                releases.append(Release(id: fields[1], name: fields[2]))
            case "file" where fields.count >= 7:
                guard let size = Int(fields[2]), let crc = UInt32(fields[4], radix: 16) else {
                    throw DiscImage.Failure(message: "known_releases.tsv line \(number + 1) is damaged")
                }
                let file = File(path: fields[1], size: size, sha256: fields[3], crc32: crc,
                                releases: Set(fields[5].split(separator: ",").map(String.init)), core: fields[6] == "1")
                files[fields[1].lowercased(), default: []].append(file)
            default:
                throw DiscImage.Failure(message: "known_releases.tsv line \(number + 1) is damaged")
            }
        }
        self.releases = releases
        self.files = files
    }

    public static func load(_ url: URL) throws -> ReleaseManifest {
        try ReleaseManifest(text: String(contentsOf: url, encoding: .utf8))
    }
}

func grouped(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}
