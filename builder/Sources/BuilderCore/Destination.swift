import Foundation

public let defaultDestination = URL(fileURLWithPath: "/Applications")

/// The Info.plist key pack.sh writes the Builder's version under (BUILDER_VERSION).
public let builderVersionKey = "NFSBuilderVersion"

public struct InstallError: LocalizedError {
    public let message: String
    /// Underlying error text, for the log.
    public var details: String? = nil
    public var errorDescription: String? { message }
}

public func destinationCheck(_ directory: URL) -> CheckState {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir)
    if exists, isDir.boolValue, FileManager.default.isWritableFile(atPath: directory.path) {
        return .ready("NFSU2.app goes to \(abbreviated(directory))")
    }
    return .blocked("Choose a folder you can write to")
}

/// An NFSU2.app that is already there: the one an update replaces.
public struct InstalledApp: Equatable {
    public let url: URL
    /// The Builder version that made it, when it was made by a Builder that records it.
    public let builderVersion: String?
    /// Its Contents/Resources/Game, when the game is inside it (it can be the game data source).
    public let game: URL?

    public init?(_ url: URL) {
        let fm = FileManager.default
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard fm.fileExists(atPath: plist.path) else { return nil }
        self.url = url
        builderVersion = (NSDictionary(contentsOf: plist)?[builderVersionKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let game = url.appendingPathComponent("Contents/Resources/Game")
        let names = (try? fm.contentsOfDirectory(atPath: game.path)) ?? []
        self.game = names.contains { $0.lowercased() == "speed2.exe" } ? game : nil
    }

    /// The NFSU2.app in `directory`, if there is one.
    public static func find(in directory: URL) -> InstalledApp? {
        InstalledApp(directory.appendingPathComponent("NFSU2.app"))
    }
}

/// The build button: "Build NFSU2.app", or "Update NFSU2.app" when one is replaced, with the
/// versions when the old app recorded the Builder that made it.
public func buildButtonTitle(replacing existing: InstalledApp?, version: String) -> String {
    guard let existing = existing else { return "Build NFSU2.app" }
    guard let old = existing.builderVersion else { return "Update NFSU2.app" }
    return old == version ? "Update NFSU2.app (\(version))" : "Update NFSU2.app (\(old) -> \(version))"
}

/// The volume a path is on (that of its nearest existing folder), for comparing two paths.
public func volumeID(_ url: URL) -> UInt64? {
    var path = url.standardizedFileURL
    while !FileManager.default.fileExists(atPath: path.path) && path.path != "/" { path.deleteLastPathComponent() }
    var info = stat()
    guard stat(path.path, &info) == 0 else { return nil }
    return UInt64(UInt32(bitPattern: info.st_dev))
}

/// Puts `built` (with the game inside it) into `directory` as NFSU2.app. The new app is made
/// complete next to the final location first (moved there when on the same volume, which is
/// instant; copied otherwise) and only then swapped in, so an old app, and the game data in it,
/// survives any failure. `built` is used up: moved, or deleted after a copy. On a failure it is
/// put back, for another try.
public func installApp(_ built: URL, into directory: URL, isRunning: () -> Bool) throws -> URL {
    if isRunning() { throw InstallError(message: "Quit NFSU2 first, then try again.") }
    let fm = FileManager.default
    let target = directory.appendingPathComponent("NFSU2.app")
    let staging = directory.appendingPathComponent(".NFSU2.app.installing")
    var moved = false
    do {
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        if let a = volumeID(built), fm.fileExists(atPath: built.path), a == volumeID(directory) {
            try fm.moveItem(at: built, to: staging)
            moved = true
        } else {
            try fm.copyItem(at: built, to: staging)
        }
        try removeQuarantine(at: staging)
        guard fm.fileExists(atPath: staging.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallError(message: "The built app is incomplete.")
        }
        var final = target
        if fm.fileExists(atPath: target.path) {
            final = try fm.replaceItemAt(target, withItemAt: staging) ?? target
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        guard fm.fileExists(atPath: final.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallError(message: "The installed app is incomplete.")
        }
        if !moved { try? fm.removeItem(at: built) }
        return final
    } catch {
        if moved, fm.fileExists(atPath: staging.path), !fm.fileExists(atPath: built.path) {
            try? fm.moveItem(at: staging, to: built)
        }
        try? fm.removeItem(at: staging)
        throw InstallError(
            message: "Could not install NFSU2 into \(directory.lastPathComponent). Choose another folder and try again.",
            details: String(describing: error))
    }
}

/// A path with the home folder written as ~.
public func abbreviated(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}
