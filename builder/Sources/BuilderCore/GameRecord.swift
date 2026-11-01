import Foundation

/// The record pack.sh --embed writes next to the game inside an app
/// (Contents/Resources/game-files.tsv): every regular file under Contents/Resources/Game with
/// its size and SHA-256. An update reuses the game of an app only when the tree still matches it.
public struct GameRecord: Equatable {
    public static let fileName = "game-files.tsv"
    /// The first line: the format and its version.
    public static let header = "# nfsu2-game-files 1"

    public struct Entry: Equatable {
        public let size: Int
        public let sha256: String
    }

    /// Relative path under Game -> its size and SHA-256.
    public let files: [String: Entry]

    /// Parses the record: the header line, then `path<TAB>size<TAB>sha256` lines (\\ \t \n \r
    /// in a path stand for a backslash, tab, newline and carriage return). Nil when anything
    /// does not fit, a path comes twice included.
    public init?(text: String) {
        var lines = text.components(separatedBy: "\n")
        guard lines.first == Self.header, lines.last == "" else { return nil }
        lines.removeFirst()
        lines.removeLast()
        var files: [String: Entry] = [:]
        for line in lines {
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 3, let path = Self.unescape(fields[0]), !path.isEmpty, !path.hasPrefix("/"),
                  !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  let size = Int(fields[1]), size >= 0, String(size) == fields[1],
                  fields[2].count == 64, fields[2].allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }),
                  files[path] == nil else { return nil }
            files[path] = Entry(size: size, sha256: fields[2])
        }
        self.files = files
    }

    static func unescape(_ field: String) -> String? {
        var out = ""
        var escaped = false
        for c in field {
            if escaped {
                switch c {
                case "\\": out.append("\\")
                case "t": out.append("\t")
                case "n": out.append("\n")
                case "r": out.append("\r")
                default: return nil
                }
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return escaped ? nil : out
    }
}

/// Whether the game inside an app is still the complete copy it was built from.
public enum EmbeddedGameVerdict: Equatable {
    /// Every recorded file is there unchanged and nothing else is: path -> SHA-256 (already
    /// computed, so the release comparison does not hash the files again).
    case intact([String: String])
    /// No record: an app made by NFSU2 Builder 1.0.0, which left part of the game copy out.
    case noRecord
    /// The tree differs from the record (`count` files; nil when the record itself is
    /// unreadable). `details` names them, for Copy details.
    case changed(count: Int?, details: [String])
}

/// Compares the game folder inside an app (Contents/Resources/Game) with the record next to
/// it. Only reads; hashes the files in parallel (about 1.7 GB for a full game).
public func verifyEmbeddedGame(_ game: URL) -> EmbeddedGameVerdict {
    let fm = FileManager.default
    let recordURL = game.deletingLastPathComponent().appendingPathComponent(GameRecord.fileName)
    guard fm.fileExists(atPath: recordURL.path) else { return .noRecord }
    guard let data = try? Data(contentsOf: recordURL), let text = String(data: data, encoding: .utf8),
          let record = GameRecord(text: text) else {
        return .changed(count: nil, details: ["The record \(GameRecord.fileName) cannot be read"])
    }
    let attributes = try? fm.attributesOfItem(atPath: game.path)
    guard attributes?[.type] as? FileAttributeType == .typeDirectory, let walker = fm.enumerator(atPath: game.path) else {
        return .changed(count: nil, details: ["Contents/Resources/Game is not a folder"])
    }
    var present: [String: Int] = [:]
    var added: [String] = []
    while let path = walker.nextObject() as? String {
        let type = walker.fileAttributes?[.type] as? FileAttributeType
        if type == .typeDirectory { continue }
        if type == .typeRegular, let size = (walker.fileAttributes?[.size] as? NSNumber)?.intValue {
            if record.files[path] != nil {
                present[path] = size
                continue
            }
            // Finder's own files: the build drops them too, so the new app is the same without them.
            if (path as NSString).lastPathComponent == ".DS_Store" { continue }
        }
        added.append(path)
    }
    let missing = record.files.keys.filter { present[$0] == nil }
    var resized: [String] = []
    var toHash: [String] = []
    for (path, size) in present {
        if record.files[path]?.size == size { toHash.append(path) } else { resized.append(path) }
    }
    var hashes = [String?](repeating: nil, count: toHash.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: toHash.count) { index in
        let sha = try? sha256Hex(of: game.appendingPathComponent(toHash[index]))
        lock.lock()
        hashes[index] = sha
        lock.unlock()
    }
    var verified: [String: String] = [:]
    var differing = resized
    for (index, path) in toHash.enumerated() {
        if let sha = hashes[index], sha == record.files[path]?.sha256 { verified[path] = sha } else { differing.append(path) }
    }
    let count = missing.count + added.count + differing.count
    guard count == 0 else {
        let details = differing.sorted().map { "Changed in the app: \($0)" } + missing.sorted().map { "Missing from the app: \($0)" }
            + added.sorted().map { "Added to the app: \($0)" }
        return .changed(count: count, details: details)
    }
    return .intact(verified)
}
