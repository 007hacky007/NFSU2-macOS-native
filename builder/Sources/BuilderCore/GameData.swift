import CryptoKit
import Foundation

/// What the player chose as game data, and what the Builder found in it.
public struct GameDataReport: Equatable {
    /// A game folder, the two discs, or an NFSU2.app with the game inside (an update).
    public enum Kind: Equatable { case folder, discs, app }

    public let kind: Kind
    /// The game folder (for an app its Contents/Resources/Game), or the disc images / disc
    /// folders in the order the build unpacks them.
    public let sources: [URL]
    /// Red: what is missing for the build or the first start.
    public let blocking: String?
    /// Amber: worth knowing, never blocking.
    public let notes: [String]
    /// The known release this copy matches best.
    public let release: String?
    /// The SPEED2.EXE in the data, when there is one.
    public let program: ProgramVerdict?
    public let server: String?
    /// For Copy details: the files that differ or are missing.
    public let details: [String]
    /// The size of the game data as it goes into the app (unpacked, for discs).
    public var bytes: Int64 = 0
    /// A game folder the current NFSU2.app plays from (an app built without the game inside).
    public var fromCurrentApp = false

    /// The data has a supported SPEED2.EXE, so it is the game program too.
    public var providesProgram: Bool { program?.isSupported == true }

    public var state: CheckState {
        if let blocking = blocking { return .blocked(blocking) }
        if !notes.isEmpty { return .automatic(notes.joined(separator: " ")) }
        let what = kind == .discs ? "Disc data" : kind == .app ? "Uses the game inside your current NFSU2.app"
            : fromCurrentApp ? "The game folder your current NFSU2.app plays from" : "Game folder"
        return .ready(release.map { "\(what), matches the \($0) release" } ?? what)
    }

    /// The text behind Copy details.
    public var detailsText: String {
        ([state.message] + sources.map { "Source: \($0.path)" } + details).joined(separator: "\n")
    }
}

extension CheckState {
    public var message: String {
        switch self {
        case let .checking(text), let .ready(text), let .automatic(text), let .blocked(text): return text
        }
    }
}

/// Windows-only extras the port never uses, which Builder 1.0.0 left out of NFSU2.app (later
/// Builders embed them). Their absence is not "missing", so an app made by 1.0.0 checks as complete.
/// `path` is relative to the game folder, lowercased.
public func leftOutOfTheApp(_ path: String) -> Bool {
    path == "safemode.bat" || path == "dinput8.dll" || path.hasPrefix("scripts/")
}

public enum GameDataMessages {
    public static let chooseOne = "Choose one game folder, or the two disc images (.iso, .cue or disc folders) together."
    public static let bothDiscs = "These are the files of one disc only. Choose both disc images together."
    public static let appWithoutGame = "This app has no game inside it. Choose your game folder, or the two disc images."
    public static func coreMissing(_ missing: [String]) -> String {
        let first = missing.prefix(2).joined(separator: ", ")
        let more = missing.count > 2 ? " and \(missing.count - 2) more" : ""
        return "This is not a complete NFSU2 game copy: \(first)\(more) missing. Choose the folder that holds SPEED2.EXE and the GLOBAL, CARS and TRACKS folders, or the two disc images."
    }
    public static func differs(differ: Int, missing: Int) -> String {
        var parts: [String] = []
        if differ > 0 { parts.append("\(grouped(differ)) \(differ == 1 ? "file that differs" : "files that differ") from the releases we know") }
        if missing > 0 { parts.append("\(grouped(missing)) \(missing == 1 ? "file" : "files") of the release missing") }
        return "This copy has \(parts.joined(separator: " and ")) (another language, a repack or mods). It should work; if something looks wrong, report it with Copy details."
    }
    public static let serverMissing = "There is no server.dll, so LAN hosting may not work."
    public static let serverUnknown = "This server.dll is not a version we know, so LAN hosting may not work."
}

/// One game file as it ends up in the game folder.
struct DataFile {
    let path: String
    let size: Int
    /// From a zip directory: compared instead of SHA-256.
    let crc32: UInt32?
    let sha256: () throws -> String
    let header: () -> Data?
}

/// Top-level disc entries that belong to the installer or the copy protection (as
/// tools/install_from_discs.py skips them).
let discSkipTop: Set<String> = ["autorun", "autorun.exe", "autorun.inf", "autorungui.dll", "bin.dat",
                                "common_filelist.txt", "compressed.zip", "directx", "eauninstall.exe",
                                "rungame.exe", "setup.exe", "support"]
let discSkipExtensions = [".tmp", ".016", ".256"]

public struct GameDataChecker {
    public let manifest: ReleaseManifest
    public let programs: [KnownProgram]
    public let servers: [KnownServer]

    public init(manifest: ReleaseManifest, programs: [KnownProgram] = KnownProgram.all, servers: [KnownServer] = KnownServer.all) {
        (self.manifest, self.programs, self.servers) = (manifest, programs, servers)
    }

    public static func isDiscImage(_ url: URL) -> Bool {
        ["iso", "cue", "bin"].contains(url.pathExtension.lowercased())
    }

    static func isDiscFolder(_ url: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.contains { $0.lowercased() == "compressed.zip" }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    /// The input as the build will read it: one game folder (looking up to two folders down for
    /// SPEED2.EXE when the chosen one is a parent), the game folder inside one NFSU2.app, or
    /// one or two discs with a .cue's .bin dropped when both were chosen. Nil when the choice
    /// cannot be a game copy.
    public static func classify(_ urls: [URL]) -> (GameDataReport.Kind, [URL])? {
        var urls = urls.map { $0.standardizedFileURL }
        if urls.count == 1, urls[0].pathExtension.lowercased() == "app", isDirectory(urls[0]) {
            return (.app, [urls[0].appendingPathComponent("Contents/Resources/Game")])
        }
        let cues = urls.filter { $0.pathExtension.lowercased() == "cue" }
        let cueImages = Set(cues.compactMap { try? cueImage($0).standardizedFileURL.path })
        urls.removeAll { $0.pathExtension.lowercased() == "bin" && cueImages.contains($0.path) }
        if urls.count == 1, isDirectory(urls[0]), !isDiscFolder(urls[0]) {
            return (.folder, [gameFolder(under: urls[0])])
        }
        guard (1...2).contains(urls.count), urls.allSatisfy({ isDiscImage($0) || (isDirectory($0) && isDiscFolder($0)) }) else {
            return nil
        }
        return (.discs, urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
    }

    static func gameFolder(under folder: URL) -> URL {
        func hasExe(_ dir: URL) -> Bool {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).contains { $0.lowercased() == "speed2.exe" }
        }
        if hasExe(folder) { return folder }
        var level = [folder]
        for _ in 0..<2 {
            let next = level.flatMap { dir -> [URL] in
                ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                    .filter(isDirectory)
            }
            let found = next.filter(hasExe)
            if found.count == 1 { return found[0] }
            level = next
        }
        return folder
    }

    public func check(_ urls: [URL]) -> GameDataReport {
        guard let (kind, sources) = Self.classify(urls) else {
            return GameDataReport(kind: .folder, sources: urls, blocking: GameDataMessages.chooseOne, notes: [], release: nil,
                                  program: nil, server: nil, details: [])
        }
        if kind == .app && !Self.isDirectory(sources[0]) {
            return GameDataReport(kind: kind, sources: sources, blocking: GameDataMessages.appWithoutGame, notes: [],
                                  release: nil, program: nil, server: nil, details: [])
        }
        do {
            let files = kind == .discs ? try discFiles(sources) : try folderFiles(sources[0])
            var report = compare(files, kind: kind, sources: sources)
            report.bytes = files.reduce(Int64(0)) { $0 + Int64($1.size) }
            return report
        } catch {
            return GameDataReport(kind: kind, sources: sources, blocking: error.localizedDescription, notes: [], release: nil,
                                  program: nil, server: nil, details: [])
        }
    }

    // MARK: - Reading

    func folderFiles(_ folder: URL) throws -> [DataFile] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles]) else {
            throw DiscImage.Failure(message: "Could not read \(folder.lastPathComponent)")
        }
        let base = folder.resolvingSymlinksInPath().path
        var files: [DataFile] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            let full = url.resolvingSymlinksInPath().path
            guard full.hasPrefix(base + "/") else { continue }
            let path = String(full.dropFirst(base.count + 1))
            files.append(DataFile(path: path, size: size, crc32: nil,
                                  sha256: { try sha256Hex(of: url) },
                                  header: { try? FileHandle(forReadingFrom: url).readData(ofLength: 4096) }))
        }
        return files
    }

    func discFiles(_ discs: [URL]) throws -> [DataFile] {
        var byPath: [String: DataFile] = [:]
        for disc in discs {
            for file in try discContents(disc) { byPath[file.path.lowercased()] = file }
        }
        return Array(byPath.values)
    }

    /// The files one disc puts in the game folder, the way tools/install_from_discs.py unpacks it.
    func discContents(_ disc: URL) throws -> [DataFile] {
        var out: [DataFile] = []
        func add(_ path: String, _ name: String) -> String? {
            let top = path.split(separator: "/").first.map(String.init) ?? path
            let low = top.lowercased()
            if low.hasPrefix(".") || discSkipTop.contains(low) || discSkipExtensions.contains(where: { low.hasSuffix($0) }) { return nil }
            return path.contains("/") ? path : (low == "speed2.exe" ? "SPEED2.EXE" : path)
        }
        if Self.isDirectory(disc) {
            guard let walker = FileManager.default.enumerator(at: disc, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
                throw DiscImage.Failure(message: "Could not read \(disc.lastPathComponent)")
            }
            let base = disc.resolvingSymlinksInPath().path
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
                let rel = String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
                if rel.lowercased() == "compressed.zip" {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { handle.closeFile() }
                    out += try zipFiles(size: size) { position, length in
                        handle.seek(toFileOffset: UInt64(position))
                        return handle.readData(ofLength: length)
                    }
                    continue
                }
                guard let path = add(rel, url.lastPathComponent) else { continue }
                out.append(DataFile(path: path, size: size, crc32: nil, sha256: { try sha256Hex(of: url) },
                                    header: { try? FileHandle(forReadingFrom: url).readData(ofLength: 4096) }))
            }
            return out
        }
        let imageURL = disc.pathExtension.lowercased() == "cue" ? try cueImage(disc) : disc
        let image = try DiscImage(imageURL)
        for entry in try image.entries() {
            if entry.path.lowercased() == "compressed.zip" {
                out += try zipFiles(size: entry.size) { position, length in
                    try image.read(extent: entry.extent, at: position, length: length)
                }
                continue
            }
            guard let path = add(entry.path, entry.path) else { continue }
            out.append(DataFile(path: path, size: entry.size, crc32: nil, sha256: {
                var hasher = SHA256()
                try image.stream(entry) { hasher.update(data: $0) }
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }, header: { try? image.read(extent: entry.extent, size: min(entry.size, 4096)) }))
        }
        return out
    }

    func zipFiles(size: Int, read: (Int, Int) throws -> Data) throws -> [DataFile] {
        try ZipDirectory.members(size: size, read: read).filter { !$0.isDirectory && !$0.path.isEmpty }.map { member in
            DataFile(path: member.path, size: member.size, crc32: member.crc32,
                     sha256: { throw DiscImage.Failure(message: "not hashed") }, header: { nil })
        }
    }

    // MARK: - Comparing

    func compare(_ files: [DataFile], kind: GameDataReport.Kind, sources: [URL]) -> GameDataReport {
        let present = Dictionary(files.map { ($0.path.lowercased(), $0) }, uniquingKeysWith: { _, last in last })
        let missingCore = manifest.corePaths.filter { present[$0.lowercased()] == nil }
        if !missingCore.isEmpty {
            let message = kind == .discs && sources.count == 1 ? GameDataMessages.bothDiscs : GameDataMessages.coreMissing(missingCore)
            return GameDataReport(kind: kind, sources: sources, blocking: message, notes: [], release: nil, program: nil,
                                  server: nil, details: missingCore.map { "Missing: \($0)" })
        }

        var program: ProgramVerdict?
        if let exe = present["speed2.exe"] {
            let sha = exe.crc32 == nil ? try? exe.sha256() : nil
            program = programVerdict(size: exe.size, sha256: sha, crc32: exe.crc32, header: exe.header(), known: programs)
        }
        var server: String?
        var notes: [String] = []
        if let dll = present["server.dll"] {
            let sha = dll.crc32 == nil ? try? dll.sha256() : nil
            server = servers.first { known in
                known.size == dll.size && (sha.map { $0 == known.sha256 } ?? (dll.crc32 == known.crc32))
            }?.name
            if server == nil { notes.append(GameDataMessages.serverUnknown) }
        } else {
            notes.append(GameDataMessages.serverMissing)
        }

        // Hash only what the releases know, in parallel.
        let candidates = files.filter { file in
            let key = file.path.lowercased()
            return key != "speed2.exe" && key != "server.dll" && manifest.files[key]?.contains { $0.size == file.size } == true
        }
        var matches = [Set<String>?](repeating: nil, count: candidates.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let file = candidates[index]
            let known = manifest.files[file.path.lowercased()] ?? []
            let match: ReleaseManifest.File?
            if let crc = file.crc32 {
                match = known.first { $0.size == file.size && $0.crc32 == crc }
            } else if let sha = try? file.sha256() {
                match = known.first { $0.size == file.size && $0.sha256 == sha }
            } else {
                match = nil
            }
            lock.lock()
            matches[index] = match?.releases
            lock.unlock()
        }
        var differing = Set(files.compactMap { file -> String? in
            let key = file.path.lowercased()
            guard key != "speed2.exe", key != "server.dll", manifest.files[key] != nil else { return nil }
            return key
        })
        var counts: [String: Int] = [:]
        for (index, file) in candidates.enumerated() {
            guard let releases = matches[index] else { continue }
            differing.remove(file.path.lowercased())
            for release in releases { counts[release, default: 0] += 1 }
        }
        let best = manifest.releases.max { (counts[$0.id] ?? 0, -indexOf($0)) < (counts[$1.id] ?? 0, -indexOf($1)) }
        var missing: [String] = []
        if let best = best {
            for (key, entries) in manifest.files where present[key] == nil && !leftOutOfTheApp(key)
                && entries.contains(where: { $0.releases.contains(best.id) }) {
                missing.append(entries[0].path)
            }
        }
        if !differing.isEmpty || !missing.isEmpty {
            notes.insert(GameDataMessages.differs(differ: differing.count, missing: missing.count), at: 0)
        }
        let differingPaths = differing.map { present[$0]?.path ?? $0 }.sorted()
        let details = differingPaths.map { "Differs: \($0)" } + missing.sorted().map { "Missing: \($0)" }
            + [program.map { "SPEED2.EXE: \(describe($0))" } ?? "SPEED2.EXE: none", "server.dll: \(server ?? "none or unknown")"]
        return GameDataReport(kind: kind, sources: sources, blocking: nil, notes: notes,
                              release: (counts[best?.id ?? ""] ?? 0) > 0 ? best?.name : nil,
                              program: program, server: server, details: details)
    }

    private func indexOf(_ release: ReleaseManifest.Release) -> Int {
        manifest.releases.firstIndex(of: release) ?? 0
    }

    private func describe(_ verdict: ProgramVerdict) -> String {
        switch verdict {
        case let .supported(_, name): return name
        case let .refused(message): return message
        }
    }
}

/// SHA-256 of a file, read in 4 MB pieces.
func sha256Hex(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { handle.closeFile() }
    var hasher = SHA256()
    while true {
        let chunk = handle.readData(ofLength: 4 << 20)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
