// Finding and checking the game files, and the small settings the launcher owns.
//
// The search order is the same as the engine's (runtime/bundle.m, app_find_game):
// data inside the bundle, the folder chosen before, next to the app, its parent
// folder, a few usual places in the home folder.  The engine gets the exact
// SPEED2.EXE the launcher checked through NFSU2_DATA.
import Foundation
import CryptoKit

enum SupportedExe {
    static let size: UInt64 = 4_788_224
    static let sha256 = "8f6a9ae2c4cfa01181d2fd755d99c6f4b7103f60273908ea1de1e719dfe2a297"
    static let names = ["SPEED2.EXE", "speed2.exe", "Speed2.exe"]
}

struct GameLocation: Equatable {
    let exe: URL
    let embedded: Bool
    var folder: URL { exe.deletingLastPathComponent() }
}

enum GameState: Equatable {
    case searching
    case notFound
    case ready(GameLocation)
    case unsupported(GameLocation, UInt64)    // exe size in bytes
}

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var bundle: URL { Bundle.main.bundleURL }
    static var resources: URL { bundle.appendingPathComponent("Contents/Resources") }
    static var embeddedGame: URL { resources.appendingPathComponent("Game") }
    static var macOS: URL { bundle.appendingPathComponent("Contents/MacOS") }
    static var saves: URL { home.appendingPathComponent("Library/Application Support/NFSU2 Saves") }
    static var logs: URL { home.appendingPathComponent("Library/Logs/NFSU2") }
    static var registry: URL { home.appendingPathComponent(".nfsu2_registry") }
}

enum Prefs {
    // Shared with the engine (same bundle id, same defaults domain).
    static let gameFolder = "OyunDizini"          // name kept for existing installs
    static let fullscreen = "NFSUFullScreen"
    // Launcher only.
    static let engine = "LauncherEngine"           // "original" | "hd"
    static let showAtStartup = "LauncherShowAtStartup"
}

enum Locator {
    static func exeIn(_ dir: URL) -> URL? {
        for n in SupportedExe.names {
            let u = dir.appendingPathComponent(n)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue { return u }
        }
        return nil
    }

    /// The folder itself or up to two levels below it ("...Clean Edition/Need for Speed Underground 2").
    static func find(under dir: URL, depth: Int = 2) -> URL? {
        if let e = exeIn(dir) { return e }
        guard depth > 0,
              let kids = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]) else { return nil }
        for k in kids.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let v = try? k.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard v?.isDirectory == true, v?.isPackage != true else { continue }
            if let e = find(under: k, depth: depth - 1) { return e }
        }
        return nil
    }

    static func locate() -> GameLocation? {
        if let env = ProcessInfo.processInfo.environment["NFSU2_DATA"], !env.isEmpty {
            let u = URL(fileURLWithPath: env)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) {
                if !isDir.boolValue { return GameLocation(exe: u, embedded: false) }
                if let e = find(under: u) { return GameLocation(exe: e, embedded: false) }
            }
        }
        if let e = find(under: Paths.embeddedGame) { return GameLocation(exe: e, embedded: true) }
        if let saved = UserDefaults.standard.string(forKey: Prefs.gameFolder),
           let e = find(under: URL(fileURLWithPath: saved)) { return GameLocation(exe: e, embedded: false) }
        let besideApp = Paths.bundle.deletingLastPathComponent()
        for d in [besideApp, besideApp.deletingLastPathComponent()] {
            if let e = find(under: d) { return GameLocation(exe: e, embedded: false) }
        }
        for rel in ["Library/Application Support/NFSU2",
                    "Documents/Need for Speed Underground 2",
                    "Downloads/Need for Speed Underground 2",
                    "Desktop/Need for Speed Underground 2"] {
            if let e = find(under: Paths.home.appendingPathComponent(rel)) {
                return GameLocation(exe: e, embedded: false)
            }
        }
        return nil
    }

    static func fileSize(_ u: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// true when this is the one SPEED2.EXE the port was built from.
    static func isSupported(_ exe: URL) -> Bool {
        if ProcessInfo.processInfo.environment["NFSU2_ANY_EXE"] == "1" { return true }
        guard fileSize(exe) == SupportedExe.size,
              let data = try? Data(contentsOf: exe, options: .mappedIfSafe) else { return false }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return hex == SupportedExe.sha256
    }

    static func check(_ loc: GameLocation) -> GameState {
        isSupported(loc.exe) ? .ready(loc) : .unsupported(loc, fileSize(loc.exe))
    }
}

enum Registry {
    /// Forget the saved graphics settings so the game picks settings for this Mac
    /// again on its next start (its own first-run detection).  Saves untouched.
    static func resetGraphics() throws {
        let u = Paths.registry
        guard let text = try? String(contentsOf: u, encoding: .utf8) else { return }
        let kept = text.split(separator: "\n", omittingEmptySubsequences: true).filter { line in
            !(line.hasPrefix("d g_") || line.hasPrefix("s g_") || line.hasPrefix("d NotFirstTime="))
        }
        try (kept.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
    }
}

func formatBytes(_ n: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: n)
}
