import Foundation

public let defaultDestination = URL(fileURLWithPath: "/Applications")

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
        return .ready(directory.path)
    }
    return .blocked("Choose a folder you can write to")
}

/// Copies `built` next to the final location, then swaps it in so the old app survives any failure.
public func installApp(_ built: URL, into directory: URL, isRunning: () -> Bool) throws -> URL {
    if isRunning() { throw InstallError(message: "Quit NFSU2 first, then try again.") }
    let fm = FileManager.default
    let target = directory.appendingPathComponent("NFSU2.app")
    let staging = directory.appendingPathComponent(".NFSU2.app.installing")
    do {
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.copyItem(at: built, to: staging)
        try removeQuarantine(at: staging)
        var final = target
        if fm.fileExists(atPath: target.path) {
            final = try fm.replaceItemAt(target, withItemAt: staging) ?? target
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        guard fm.fileExists(atPath: final.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallError(message: "The installed app is incomplete.")
        }
        return final
    } catch {
        try? fm.removeItem(at: staging)
        throw InstallError(
            message: "Could not install NFSU2 into \(directory.lastPathComponent). Choose another folder and try again.",
            details: String(describing: error))
    }
}

/// Where the Builder makes a game folder when the player's copy cannot be used as it is.
public let defaultGameFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games/NFSU2")

/// The game folder location is fine when it does not exist yet (its nearest existing parent
/// is writable), is empty, or was made by the Builder before (it is then replaced).
public func gameFolderCheck(_ folder: URL) -> CheckState {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: folder.path, isDirectory: &isDir) {
        guard isDir.boolValue else { return .blocked("\(folder.path) is a file. Choose another place for the game folder.") }
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let ours = names.contains(".nfsu2-builder.json")
        guard ours || names.allSatisfy({ $0.hasPrefix(".") }) else {
            return .blocked("\(abbreviated(folder)) already has files in it. Choose another place for the game folder.")
        }
        guard fm.isWritableFile(atPath: folder.deletingLastPathComponent().path) else {
            return .blocked("Choose a game folder location you can write to")
        }
        return .ready(abbreviated(folder))
    }
    var parent = folder.deletingLastPathComponent()
    while !fm.fileExists(atPath: parent.path) && parent.path != "/" { parent = parent.deletingLastPathComponent() }
    guard fm.isWritableFile(atPath: parent.path) else { return .blocked("Choose a game folder location you can write to") }
    return .ready(abbreviated(folder))
}

/// A path with the home folder written as ~.
public func abbreviated(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}
