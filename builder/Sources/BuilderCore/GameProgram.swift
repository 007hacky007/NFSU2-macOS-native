import Foundation

public enum ProgramChoiceMessages {
    public static let noneInArchive = "There is no SPEED2.EXE in this archive. " + ProgramMessages.needed
    public static let unreadable = "This is not SPEED2.EXE or an archive macOS can open (zip, rar or 7z)."
    public static func inArchive(_ message: String) -> String {
        "The archive holds no supported SPEED2.EXE. " + message
    }
}

/// Whether the Builder reads the game program choice. One picked in this session is checked at
/// once. One saved from an earlier session (often in Documents, where reading it asks macOS for
/// access) waits for the game data check and is only read when the data has no usable
/// SPEED2.EXE of its own, which an update's NFSU2.app has.
public func checksProgramChoice(chosenThisSession: Bool, dataChecking: Bool, dataProvidesProgram: Bool) -> Bool {
    chosenThisSession || !dataChecking && !dataProvidesProgram
}

/// Checks the game program the player chose: SPEED2.EXE itself, or an archive (zip, rar, 7z)
/// that holds it anywhere inside. An archive is unpacked into a private temporary folder and
/// only its .exe files are looked at; nothing from it is run. A supported file is copied to
/// `keep` for the build. The chosen file or archive is only read.
public struct ProgramChecker {
    public let programs: [KnownProgram]
    public let temporaryParent: URL

    public init(programs: [KnownProgram] = KnownProgram.all, temporaryParent: URL = FileManager.default.temporaryDirectory) {
        self.programs = programs
        self.temporaryParent = temporaryParent
    }

    public static func isArchive(_ url: URL) -> Bool {
        ["zip", "rar", "7z"].contains(url.pathExtension.lowercased())
    }

    public func check(_ url: URL, keep: URL) -> ProgramVerdict {
        let fm = FileManager.default
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, !GameDataChecker.isDirectory(url) else {
            return .refused(ProgramChoiceMessages.unreadable)
        }
        let header = (try? FileHandle(forReadingFrom: url))?.readData(ofLength: 4096) ?? Data()
        if header.starts(with: [0x4D, 0x5A]) || !Self.isArchive(url) && url.pathExtension.lowercased() == "exe" {
            let verdict = programVerdict(size: size, sha256: try? sha256Hex(of: url), crc32: nil, header: header, known: programs)
            if verdict.isSupported, !store(url, keep: keep) { return .refused("Could not keep a copy of SPEED2.EXE for the build.") }
            return verdict
        }
        let temp = temporaryParent.appendingPathComponent("nfsu2-program-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        guard (try? fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil,
              unpackExecutables(url, into: temp) else {
            return .refused(ProgramChoiceMessages.unreadable)
        }
        var refusals: [String] = []
        for file in regularFiles(in: temp) {
            guard let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { continue }
            let head = (try? FileHandle(forReadingFrom: file))?.readData(ofLength: 4096)
            let verdict = programVerdict(size: fileSize, sha256: try? sha256Hex(of: file), crc32: nil, header: head, known: programs)
            switch verdict {
            case .supported:
                return store(file, keep: keep) ? verdict : .refused("Could not keep a copy of SPEED2.EXE for the build.")
            case let .refused(message):
                if file.lastPathComponent.lowercased() == "speed2.exe" {
                    refusals.insert(message, at: 0)
                } else if [ProgramMessages.disc, ProgramMessages.officialPatch, ProgramMessages.protected].contains(message) {
                    refusals.append(message)
                }
            }
        }
        if let first = refusals.first { return .refused(ProgramChoiceMessages.inArchive(first)) }
        return .refused(ProgramChoiceMessages.noneInArchive)
    }

    /// Unpacks only the archive's .exe files with macOS's bsdtar (zip, rar 4 and 5, 7z); a RAR
    /// that bsdtar cannot unpack (RAR 7 compression) goes through RarArchive.
    func unpackExecutables(_ archive: URL, into folder: URL) -> Bool {
        let tar = SystemCommandRunner().run("/usr/bin/tar", ["-x", "-f", archive.path, "-C", folder.path,
                                                             "--include", "*.[eE][xX][eE]"])
        if tar.status == 0 { return true }
        // An archive without any .exe makes bsdtar fail ("Not found in archive"); it is still readable.
        if SystemCommandRunner().run("/usr/bin/tar", ["-t", "-f", archive.path]).status == 0 { return true }
        guard archive.pathExtension.lowercased() == "rar",
              let data = try? Data(contentsOf: archive, options: .alwaysMapped) else { return false }
        var handles: [FileHandle] = []
        defer { handles.forEach { $0.closeFile() } }
        do {
            try data.withUnsafeBytes { bytes in
                var index = 0
                try RarArchive.extract(bytes, entries: try RarArchive.list(bytes)) { entry in
                    guard entry.name.lowercased().hasSuffix(".exe"), !entry.encrypted else { return nil }
                    index += 1
                    let name = entry.name.split(separator: "/").last.map(String.init) ?? "program.exe"
                    let target = folder.appendingPathComponent("\(index)").appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard FileManager.default.createFile(atPath: target.path, contents: nil) else { return nil }
                    let handle = try FileHandle(forWritingTo: target)
                    handles.append(handle)
                    return { chunk in handle.write(Data(chunk)) }
                }
            }
            return true
        } catch {
            return false
        }
    }

    private func regularFiles(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter {
            let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
    }

    /// Copies the file to `keep` through a temporary sibling, so a half-written copy never counts.
    private func store(_ file: URL, keep: URL) -> Bool {
        let fm = FileManager.default
        let staging = keep.deletingLastPathComponent().appendingPathComponent(".\(keep.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
            if file.standardizedFileURL == keep.standardizedFileURL { return true }
            try fm.copyItem(at: file, to: staging)
            try removeQuarantine(at: staging)
            if fm.fileExists(atPath: keep.path) { try fm.removeItem(at: keep) }
            try fm.moveItem(at: staging, to: keep)
            return true
        } catch {
            try? fm.removeItem(at: staging)
            return false
        }
    }
}
