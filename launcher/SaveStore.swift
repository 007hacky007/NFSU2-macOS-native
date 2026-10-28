import Foundation
import Darwin

struct SaveProfile: Identifiable {
    let name: String
    let modified: Date
    let bytes: Int
    var id: String { name }
    static func checksum(_ bytes: Data) -> UInt32 {
        guard bytes.count >= 4 else { return 0 }
        var crc: UInt32 = ~((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
        for byte in bytes.dropFirst(4) {
            let top = crc >> 24
            var t = top << 24
            for _ in 0..<8 { t = t & 0x80000000 != 0 ? (t << 1) ^ 0x04c11db7 : t << 1 }
            crc = (crc << 8 | UInt32(byte)) ^ t
        }
        return ~crc
    }
    static func validate(_ data: Data, name: String) throws {
        guard data.count == 54966, data.prefix(4) == Data("20CM".utf8), data.u32(4) == 54966,
              data.u32(8) == 8, data.u32(12) == 54930, data.u32(28) == 0x10d, data.u32(32) == 54930,
              (1...7).contains(name.utf8.count), name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
              String(bytes: data[53797..<53829].prefix(while: { $0 != 0 }), encoding: .ascii)?.lowercased() == name.lowercased(),
              data.u32(16) == checksum(Data(data[28..<36])), data.u32(20) == checksum(Data(data[36...])),
              data.u32(24) == checksum(Data(data[..<24])) else {
            throw SaveError("Profile \(name) is incomplete, damaged or from an unsupported game version.")
        }
        // An unknown car type crashes the unmodified game when its garage loads.
        let cars = "PEUGOT FOCUS COROLLA 240SX MIATA CIVIC PEUGOT106 CORSA HUMMER NAVIGATOR ESCALADE TIBURON SENTRA CELICA IS300 SUPRA GOLF A3 RSX ECLIPSE TT RX8 350Z G35 3000GT GTO MUSTANGGT SKYLINE LANCEREVO8 RX7 IMPREZAWRX".split(separator: " ")
        let hashes = Set(cars.map { $0.utf8.reduce(UInt32.max) { ($0 &* 33) &+ UInt32($1) } })
        for i in 0..<48 {
            let car = data.u32(36 + i * 24 + 20)
            guard car == UInt32.max || car < 31 else { throw SaveError("Profile \(name) contains unsupported mod cars.") }
        }
        for (offset, count, stride) in [(1156,20,1072),(22596,5,2034),(32770,6,1076)] {
            for i in 0..<count {
                let hash = data.u32(36 + offset + i * stride + 28)
                guard hash == 0 || hashes.contains(hash) else { throw SaveError("Profile \(name) contains unsupported mod cars.") }
            }
        }
    }
}

struct SaveStore {
    let saves: URL
    let registry: URL
    var backups: URL { saves.deletingLastPathComponent().appendingPathComponent("NFSU2 Save Backups", isDirectory: true) }
    private let fm = FileManager.default
    static let profileRoot = "NFS Underground 2"

    static func profileName(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 3, parts[0].lowercased() == profileRoot.lowercased(), parts[1].lowercased() == parts[2].lowercased(),
              !parts[1].contains(" ") else { return nil }
        return String(parts[1])
    }
    static func isProfilePath(_ path: String) -> Bool {
        path.split(separator: "/").first?.lowercased() == profileRoot.lowercased()
    }
    private func safeExisting(_ url: URL) throws {
        var current = url
        while current.path != "/" {
            if let attrs = try? fm.attributesOfItem(atPath: current.path), attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw SaveError("Save paths must not contain symbolic links.")
            }
            current.deleteLastPathComponent()
        }
    }
    func snapshot() throws -> [SaveEntry] {
        try safeExisting(saves); try safeExisting(registry)
        var entries = [SaveEntry](), total = 0
        if fm.fileExists(atPath: saves.path) {
            var walkError: Error?
            guard let walker = fm.enumerator(at: saves, includingPropertiesForKeys: [.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey], errorHandler: { _, error in walkError = error; return false }) else { throw SaveError("Cannot read the save folder.") }
            for case let url as URL in walker {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey])
                guard values.isSymbolicLink != true else { throw SaveError("Save folder contains a symbolic link.") }
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else { throw SaveError("Save folder contains a special file.") }
                let path = String(url.path.dropFirst(saves.path.count + 1))
                if path == "autotest-script.txt" { continue }
                total += values.fileSize ?? 0
                guard (values.fileSize ?? Int.max) <= SaveArchive.maxEntry, total <= SaveArchive.maxTotal, entries.count < SaveArchive.maxEntries else { throw SaveError("Save folder exceeds backup limits.") }
                entries.append(SaveEntry(path: path, data: try Data(contentsOf: url), modified: values.contentModificationDate ?? Date()))
            }
            if let error = walkError { throw error }
        }
        if fm.fileExists(atPath: registry.path) {
            let size = try registry.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= SaveArchive.maxEntry else { throw SaveError("Registry file is too large.") }
            entries.removeAll { $0.path == "registry.txt" }
            entries.append(SaveEntry(path: "registry.txt", data: try Data(contentsOf: registry)))
        }
        try SaveArchive.validatePaths(entries)
        return entries.sorted { $0.path < $1.path }
    }
    func profiles() throws -> [SaveProfile] {
        try snapshot().compactMap { entry in
            guard let name = Self.profileName(entry.path) else { return nil }
            return SaveProfile(name: name, modified: entry.modified, bytes: entry.data.count)
        }.sorted { $0.modified > $1.modified }
    }
    func backup(label: String = "backup") throws -> URL {
        try keepArchive(SaveArchive.encode(snapshot()), label: label)
    }
    func keepArchive(_ data: Data, label: String) throws -> URL {
        try safeExisting(backups)
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backups.appendingPathComponent("\(label)-\(date)-\(UUID().uuidString.prefix(8)).zip")
        try data.write(to: url, options: .atomic)
        return url
    }
    func export(to url: URL) throws { try SaveArchive.encode(snapshot()).write(to: url, options: .atomic) }
    static func readArchive(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey])
        guard size.isRegularFile == true, (size.fileSize ?? Int.max) <= SaveArchive.maxTotal + (8 << 20) else { throw SaveError("Choose a ZIP archive smaller than 264 MiB.") }
        return try Data(contentsOf: url)
    }
    static func validated(_ data: Data) throws -> [SaveEntry] {
        let entries = try SaveArchive.decode(data)
        var profiles = Set<String>()
        for e in entries {
            if let name = profileName(e.path) { try SaveProfile.validate(e.data, name: name); profiles.insert(name.lowercased()) }
        }
        guard !profiles.isEmpty else { throw SaveError("The archive contains no valid NFS Underground 2 profiles.") }
        for e in entries where isProfilePath(e.path) {
            let parts = e.path.split(separator: "/")
            guard parts.count >= 3 else { throw SaveError("The archive contains an incomplete profile folder.") }
            let owner = String(parts[1]).components(separatedBy: " ").first!.lowercased()
            guard parts.count >= 3, profiles.contains(owner) else { throw SaveError("The archive contains an incomplete profile folder.") }
        }
        return entries
    }
    func restore(_ data: Data, gameRunning: () -> Bool, cloud: Bool = false) throws {
        guard !gameRunning() else { throw SaveError("Quit the game before importing or restoring saves.") }
        let imported = try Self.validated(data)
        let previous = try snapshot()
        let names = Set(imported.compactMap { Self.profileName($0.path)?.lowercased() })
        let fullBackup = !cloud && imported.contains { $0.path == "registry.txt" || $0.path == "settings.ini" }
        var next = fullBackup ? [] : previous.filter { entry in
            if cloud { return !Self.isProfilePath(entry.path) || entry.path.split(separator: "/").dropFirst().first?.contains(" ") == true }
            let p = entry.path.split(separator: "/")
            return p.count < 2 || p[0].lowercased() != Self.profileRoot.lowercased() || !names.contains(p[1].lowercased())
        }
        for e in imported {
            next.removeAll { $0.path.lowercased() == e.path.lowercased() }; next.append(e)
        }
        try SaveArchive.validatePaths(next)
        let parent = saves.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let space = try fm.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber
        let needed = previous.reduce(0) { $0 + $1.data.count } + next.reduce(0) { $0 + $1.data.count } + (16 << 20)
        guard let free = space?.uint64Value, free >= UInt64(needed) else { throw SaveError("Not enough free disk space to stage and back up this restore.") }
        let stage = parent.appendingPathComponent(".save-stage-\(UUID().uuidString)", isDirectory: true)
        let regStage = registry.deletingLastPathComponent().appendingPathComponent(".registry-stage-\(UUID().uuidString)")
        var removeStage = true
        defer { if removeStage { try? fm.removeItem(at: stage) }; try? fm.removeItem(at: regStage) }
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        for e in next where e.path != "registry.txt" {
            let url = stage.appendingPathComponent(e.path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try e.data.write(to: url)
            try fm.setAttributes([.modificationDate:e.modified], ofItemAtPath: url.path)
        }
        let restoreRegistry = !cloud && imported.contains { $0.path == "registry.txt" }
        if restoreRegistry, let reg = next.first(where: { $0.path == "registry.txt" }) { try reg.data.write(to: regStage) }
        guard !gameRunning() else { throw SaveError("The game started during restore. Saves were not changed.") }
        _ = try backup(label: "before-restore")
        guard !gameRunning() else { throw SaveError("The game started during restore. Saves were not changed.") }
        try safeExisting(saves); try safeExisting(registry)
        let existed = fm.fileExists(atPath: saves.path)
        if existed {
            guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, saves.path, UInt32(RENAME_SWAP)) == 0 else { throw SaveError("Could not atomically replace the save folder.") }
        } else { try fm.moveItem(at: stage, to: saves) }
        if restoreRegistry && rename(regStage.path, registry.path) != 0 {
            if existed {
                guard renameatx_np(AT_FDCWD, stage.path, AT_FDCWD, saves.path, UInt32(RENAME_SWAP)) == 0 else {
                    removeStage = false
                    throw SaveError("Registry restore and rollback failed. Your previous save folder is kept beside the saves as \(stage.lastPathComponent). Restore the before-restore ZIP from the backups folder before playing.")
                }
            } else {
                do { try fm.moveItem(at: saves, to: stage) }
                catch { throw SaveError("Registry restore and rollback failed. The imported folder was kept. Restore the before-restore ZIP from the backups folder before playing.") }
            }
            throw SaveError("Registry restore failed. Previous saves and the pre-restore backup were kept.")
        }
    }
}
