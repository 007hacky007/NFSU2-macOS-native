// Finding and checking the game files, and the small settings the launcher owns.
//
// The search order is the same as the engine's (runtime/bundle.m, app_find_game):
// data inside the bundle, the folder chosen before, next to the app, its parent
// folder, a few usual places in the home folder.  The engine gets the exact
// SPEED2.EXE the launcher checked through NFSU2_DATA.
import Foundation
import CryptoKit

/// A build of SPEED2.EXE the port has an engine for (README "Game versions").
struct ExeBuild: Equatable {
    let name: String
    let size: UInt64
    let sha256: String
    let engineSuffix: String      // Contents/MacOS/nfsu2-engine<suffix>[-hd]
}

enum SupportedExe {
    static let builds = [
        ExeBuild(name: "European v1.2", size: 4_788_224,
                 sha256: "8f6a9ae2c4cfa01181d2fd755d99c6f4b7103f60273908ea1de1e719dfe2a297", engineSuffix: ""),
        ExeBuild(name: "North American v1.2", size: 4_800_512,
                 sha256: "f9dd86c054878ce6276beb07c1fd61874f7a1e4bf1f241b084c65b73e24168a7", engineSuffix: "-na"),
    ]
    static let names = ["SPEED2.EXE", "speed2.exe", "Speed2.exe"]
}

struct GameLocation: Equatable {
    let exe: URL
    let embedded: Bool
    var build: ExeBuild? = nil    // set by Locator.check
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
    /// The UHUD pack the launcher made from the mod (UHUDPack.swift)
    static var uhudPack: URL { home.appendingPathComponent("Library/Application Support/NFSU2/Textures/uhud.pak") }

    /// The engine binary for a build of SPEED2.EXE (nil: the European one).
    static func engine(_ build: ExeBuild?, hd: Bool) -> URL {
        macOS.appendingPathComponent("nfsu2-engine" + (build?.engineSuffix ?? "") + (hd ? "-hd" : ""))
    }
    static func hasEngine(_ build: ExeBuild?) -> Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: engine(build, hd: false).path)
            || fm.isExecutableFile(atPath: engine(build, hd: true).path)
    }
}

enum Prefs {
    // Shared with the engine (same bundle id, same defaults domain).
    static let gameFolder = "OyunDizini"          // name kept for existing installs
    static let fullscreen = "NFSUFullScreen"
    static let fpsCounter = "NFSUFpsCounter"      // 0 off, 1 on, 2 detailed (Cmd-N in the game)
    // Launcher only; passed to the engine as NFSU2_PAD / NFSU2_PAD_DEADZONE.
    static let controller = "LauncherController"
    static let stickDeadzone = "LauncherStickDeadzone"
    // Launcher only.
    static let engine = "LauncherEngine"           // "original" | "hd"
    static let showAtStartup = "LauncherShowAtStartup"
    static let wideHUD = "LauncherWideHUD"         // HUDPOS=1 for the engine
    static let allCars = "LauncherAllCars"         // both releases' cars (off: NFSU2_ALL_CARS=0)
    static let intro = "LauncherIntro"             // BOOTMOVIES: "skippable" | "off" | "original"
    static let language = "LauncherLanguage"      // passed to the engine as NFSU2_LANGUAGE
    static let headlights = "LauncherHeadlights"   // NFSU2_HEADLIGHTS: "players" | "all" | "off"
    static let discord = "LauncherDiscord"         // Discord status on (NFSU2_DISCORD=1)
    static let garage = "LauncherGarage"           // 10 slots and Trade Car (off: NFSU2_GARAGE=off)
    static let uhud = "LauncherUHUD"               // Bool: the UHUD pack's menus and HUD
    static let dataMods = "LauncherDataMods"       // ids of the turned-on data mods (DataMods.swift)
    static let reflections = "LauncherReflections" // NFSU2_REFLECTIONS: "original" | "sharp" | "sharpest"
    static let reflectSky = "LauncherReflectSky"   // NFSU2_REFLECT_SKY=1
    static let reflectLights = "LauncherReflectLights"   // NFSU2_REFLECT_LIGHTS=1
    static let reflectDetail = "LauncherReflectDetail"   // NFSU2_REFLECT_DETAIL=1
    static let frameRate = "LauncherFrameRate"     // NFSU2_FPS: auto | 30 | 60 | 120 | 240
    static let cutscenes60 = "LauncherCutscenes60" // NFSU2_CUTSCENES_60=1
    static let cutsceneBars = "LauncherCutsceneBars" // false: NFSU2_CUTSCENE_BORDERS=off
    static let online = "LauncherOnline"           // LAN and Online through a server
    static let server = "LauncherServer"
    static let playerName = "LauncherPlayerName"
    static let freeRoam = "LauncherFreeRoam"       // "off" | "solid" | "ghost"
    static let roamRoom = "LauncherRoamRoom"
    static let roamCrew = "LauncherRoamCrew"
    static let horn = "LauncherHorn"               // "off" | one of the engine's horns (runtime/horn.c)
    static let hearCars = "LauncherHearCars"       // NFSU2_ROAM_CARSFX=1 for the engine
    static let resolutionScale = "LauncherResolutionScale" // NFSU2_RENDER: DisplayOptions.scales
    static let movieFraming = "LauncherMovieFraming"       // NFSU2_MOVIE: fit | fill | stretch
    static let subtitles = "LauncherMovieSubtitles"        // NFSU2_SUBTITLES=1
    static let background = "LauncherBackground"           // NFSU2_BACKGROUND: pause | run

    /// Each game option with its value in the original, unmodified game: Settings ›
    /// Restore Original Game sets them all.  A new option adds its line here.  (The
    /// game folder, full screen and showAtStartup are not game options.)
    static let originalGame: [OriginalValue] = [
        OriginalValue(\.engine, .original),
        OriginalValue(\.wideHUD, false),
        OriginalValue(\.fpsCounter, 0),
        OriginalValue(\.frameRate, "120"),
        OriginalValue(\.cutscenes60, false),
        OriginalValue(\.cutsceneBars, true),
        OriginalValue(\.headlights, "off"),
        OriginalValue(\.reflections, .original),
        OriginalValue(\.reflectSky, false),
        OriginalValue(\.reflectLights, false),
        OriginalValue(\.reflectDetail, false),
        OriginalValue(\.picture, Array(repeating: 0, count: PictureOptions.all.count)),
        OriginalValue(\.online, false),
        OriginalValue(\.freeRoam, .off),
        OriginalValue(\.hearCars, false),
        OriginalValue(\.horn, .off),
        OriginalValue(\.allCars, false),
        OriginalValue(\.garage, false),
        OriginalValue(\.intro, "original"),
        OriginalValue(\.discord, false),
        OriginalValue(\.uhud, false),
        OriginalValue(\.resolutionScale, DisplayOptions.originalScale),
        OriginalValue(\.movieFraming, DisplayOptions.originalFraming),
        OriginalValue(\.subtitles, false),
        OriginalValue(\.background, DisplayOptions.originalBackground),
    ]
}

/// An option of LauncherModel and the value that gives the original game.
struct OriginalValue {
    let restore: (LauncherModel) -> Void
    let isSet: (LauncherModel) -> Bool
    init<T: Equatable>(_ option: ReferenceWritableKeyPath<LauncherModel, T>, _ value: T) {
        restore = { $0[keyPath: option] = value }
        isSet = { $0[keyPath: option] == value }
    }
}

/// The game's languages (runtime/language.c).  One is offered when the game folder
/// has its LANGUAGES file, or its language pack (LANGPACKS/<id>) has one.
enum Languages {
    static let all: [(id: String, name: String, file: String)] = [
        ("english", "English", "English.bin"), ("french", "French", "French.bin"),
        ("german", "German", "German.bin"), ("italian", "Italian", "Italian.bin"),
        ("spanish", "Spanish", "Spanish.bin"), ("dutch", "Dutch", "Dutch.bin"),
        ("swedish", "Swedish", "Swedish.bin"), ("danish", "Danish", "Danish.bin"),
        ("korean", "Korean", "Korean.bin"), ("chinese", "Traditional Chinese", "Chinese.bin"),
        ("japanese", "Japanese", "Japanese.bin"), ("thai", "Thai", "Thailand.bin"),
        ("russian", "Russian", "English.bin"), ("portuguese", "Brazilian Portuguese", "English.bin"),
        ("polish", "Polish", "English.bin"), ("turkish", "Turkish", "English.bin"),
    ]
    private static let packOnly: Set<String> = ["russian", "portuguese", "polish", "turkish"]

    private static func child(_ name: String, in dir: URL?) -> URL? {
        guard let dir = dir else { return nil }
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func installed(in game: URL?) -> [String] {
        let retail = child("LANGUAGES", in: game)
        let packs = child("LANGPACKS", in: game)
        return all.filter { l in
            l.id == "english"
                || (!packOnly.contains(l.id) && child(l.file, in: retail) != nil)
                || child(l.file, in: child("LANGUAGES", in: child(l.id, in: packs))) != nil
        }.map { $0.id }
    }
}

/// The "Picture" card: optional settings, each passed to the engine as an environment
/// variable (runtime/visual.c, runtime/picture.m).  The first choice of every option
/// is the original game and sets nothing.
struct PictureOption {
    let key: String                  // launcher default: the chosen index
    let title: String
    let env: String
    let choices: [(label: String, value: String)]
}

enum PictureOptions {
    static let all: [PictureOption] = [
        PictureOption(key: "LauncherColourTint", title: "Colour", env: "TINT",
                      choices: [("As on PC (original)", ""), ("Less tint", "less"), ("No tint", "none"), ("Cool", "cool")]),
        PictureOption(key: "LauncherGamma", title: "Gamma", env: "CONSOLEGAMMA",
                      choices: [("As on PC (original)", ""), ("Console", "1")]),
        PictureOption(key: "LauncherEdgeSmoothing", title: "Edge smoothing", env: "EDGEAA",
                      choices: [("Off, as on PC (original)", ""), ("On", "1")]),
        PictureOption(key: "LauncherSharpening", title: "Sharpening", env: "SHARPEN",
                      choices: [("Off, as on PC (original)", ""), ("Low", "50"), ("High", "100")]),
    ]
}

/* Online play goes through a relay server (th0mk's nfsu2-web server, the only
 * one known so far); off, the game's LAN is the Mac's own network. */
enum OnlineSettings {
    static let defaultServer = "wss://nfsu2.xyz/lan"

    static func isLoopback(_ host: String) -> Bool {
        if ["localhost", "::1", "[::1]"].contains(host.lowercased()) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && (UInt($0) ?? 256) <= 255
        }
    }
    /* wss://, or ws:// to this Mac only (a local test server) */
    static func validServer(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }),
              let c = URLComponents(string: text), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.fragment == nil,
              c.port == nil || (1...65535).contains(c.port!) else { return false }
        return c.scheme == "wss" || (c.scheme == "ws" && isLoopback(host))
    }
    /* what the server accepts as a name: 3-15 letters, digits, _ or - */
    static func validName(_ name: String) -> Bool {
        (3...15).contains(name.utf8.count) && name.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
        }
    }
    static func error(server: String, name: String) -> String? {
        if !validServer(server) { return "Use a wss:// server address (ws:// only for a server on this Mac)." }
        if !validName(name) { return "Enter a player name: 3-15 letters, numbers, _ or -." }
        return nil
    }
    /* a free-roam room or crew: up to 24 printable ASCII characters (the game
     * shows no others), empty for none */
    static func validTag(_ text: String) -> Bool {
        text.utf8.count <= 24 && text.utf8.allSatisfy { (32...126).contains($0) }
    }
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

    /// The folder has both releases' cars, CARS/CORSA, PEUGOT106, CIVIC and RSX
    /// (runtime/regional.c), in any case.
    static func hasAllRegionCars(_ folder: URL?) -> Bool {
        func child(_ dir: URL, _ name: String) -> URL? {
            let kids = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return kids.first { $0.caseInsensitiveCompare(name) == .orderedSame }.map { dir.appendingPathComponent($0) }
        }
        guard let f = folder, let cars = child(f, "CARS") else { return false }
        return ["CORSA", "PEUGOT106", "CIVIC", "RSX"].allSatisfy {
            child(cars, $0).flatMap { child($0, "GEOMETRY.BIN") } != nil
        }
    }

    static func fileSize(_ u: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Which supported build this SPEED2.EXE is, if any.
    static func identify(_ exe: URL) -> ExeBuild? {
        let size = fileSize(exe)
        guard SupportedExe.builds.contains(where: { $0.size == size }),
              let data = try? Data(contentsOf: exe, options: .mappedIfSafe) else { return nil }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return SupportedExe.builds.first { $0.sha256 == hex }
    }

    /// Ready when the file is a supported build and this app has its engine.
    static func check(_ loc: GameLocation) -> GameState {
        var l = loc
        l.build = identify(loc.exe)
        if l.build == nil && ProcessInfo.processInfo.environment["NFSU2_ANY_EXE"] == "1" {
            l.build = SupportedExe.builds[0]
        }
        guard let b = l.build, Paths.hasEngine(b) else { return .unsupported(l, fileSize(loc.exe)) }
        return .ready(l)
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
