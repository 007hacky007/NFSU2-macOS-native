import Foundation

@main
struct RuntimeOptionsTests {
    static func main() throws {
        let env = try LaunchSettings.environment(inherited: ["NFSU2_LANGUAGE": "bad", "NFSU2_FPS": "999", "NFSU2_MUSIC_FOLDER": "/stale", "NFSU2_RADIO": "1"],
            online: false, server: "", name: "", textures: "original", pack: nil,
            data: "/game", saves: "/saves", registry: "/registry")
        assert(env["NFSU2_LANGUAGE"] == "english")
        assert(env["NFSU2_FPS"] == "auto")
        assert(env["NFSU2_RADIO"] == "0" && env["NFSU2_MUSIC_FOLDER"] == nil)
        assert(env["NFSU2_RENDER"] == "backing", "default render scale must override inherited settings")
        let legacy = Data(#"{"language":"french","frameRate":"60","controller":"hotplug","stickDeadzone":0.12,"triggerDeadzone":0.04,"customMusic":true,"musicFolder":"/fixture/music"}"#.utf8)
        let migrated = try JSONDecoder().decode(RuntimeOptions.self, from: legacy)
        assert(migrated.language == "french" && migrated.customMusic && migrated.musicFolder == "/fixture/music")
        assert(migrated.resolutionScale == "backing" && migrated.hud == "wide" && migrated.subtitles)
        let missing = try JSONDecoder().decode(RuntimeOptions.self, from: Data("{}".utf8))
        assert(missing == RuntimeOptions())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = RuntimeOptions()
        options.language = "french"; options.frameRate = "60"; options.controller = "hotplug"
        options.stickDeadzone = 0.12; options.triggerDeadzone = 0.04
        options.customMusic = true; options.musicFolder = directory.path
        let chosen = try options.environment()
        assert(chosen["NFSU2_LANGUAGE"] == "french" && chosen["NFSU2_FPS"] == "60")
        assert(chosen["NFSU2_PAD"] == "hotplug" && chosen["NFSU2_PAD_DEADZONE"] == "0.12")
        assert(chosen["NFSU2_RADIO"] == "1" && chosen["NFSU2_MUSIC_FOLDER"] == directory.path)
        let decoded = try JSONDecoder().decode(RuntimeOptions.self, from: JSONEncoder().encode(options))
        assert(decoded == options)
        options.resolutionScale = "scale:0.75"; options.hud = "43"; options.subtitles = false
        options.movieFraming = "fill"; options.cutsceneBorders = "off"; options.headlights = "all"
        options.background = "run"; options.roamRoom = " Test Crew "
        let advanced = try LaunchSettings.environment(inherited: ["NFSU2_RENDER": "bad", "NFSU2_ROAM_ROOM": "stale", "NFSU2_SUBTITLES": "1"], online: false, server: "", name: "", textures: "original", pack: nil, data: "/game", saves: "/saves", registry: "/registry", runtime: options)
        assert(advanced["NFSU2_RENDER"] == "scale:0.75" && advanced["NFSU2_HUD"] == "43")
        assert(advanced["NFSU2_SUBTITLES"] == "0" && advanced["NFSU2_MOVIE"] == "fill")
        assert(advanced["NFSU2_CUTSCENE_BORDERS"] == "off" && advanced["NFSU2_HEADLIGHTS"] == "all")
        assert(advanced["NFSU2_BACKGROUND"] == "run" && advanced["NFSU2_ROAM_ROOM"] == "Test Crew")
        let advancedDecoded = try JSONDecoder().decode(RuntimeOptions.self, from: JSONEncoder().encode(options))
        assert(advancedDecoded == options)
        for key in ["resolutionScale", "hud", "movieFraming", "cutsceneBorders", "headlights", "background", "roamRoom"] {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as! [String: Any]
            json[key] = key == "roamRoom" ? "bad\nroom" : "unsupported"
            let invalid = try JSONDecoder().decode(RuntimeOptions.self, from: JSONSerialization.data(withJSONObject: json))
            do { _ = try invalid.environment(); assertionFailure("accepted invalid \(key)") } catch {}
        }
        for room in [String(repeating: "a", count: 64), "røøm"] {
            var invalid = options; invalid.roamRoom = room
            do { _ = try invalid.environment(); assertionFailure("invalid room") } catch {}
        }
        var bad = options; bad.frameRate = "999"
        do { _ = try bad.environment(); assertionFailure("unsupported frame rate") } catch {}
        bad = options; bad.language = "unknown"
        do { _ = try bad.environment(); assertionFailure("unsupported language") } catch {}
        bad = options; bad.stickDeadzone = .nan
        do { _ = try bad.environment(); assertionFailure("non-finite deadzone") } catch {}
        bad = options; bad.triggerDeadzone = -0.01
        do { _ = try bad.environment(); assertionFailure("negative deadzone") } catch {}
        bad = options; bad.musicFolder = "relative"
        do { _ = try bad.environment(); assertionFailure("relative music path") } catch {}
        bad = options; bad.musicFolder = directory.appendingPathComponent("missing").path
        do { _ = try bad.environment(); assertionFailure("missing music folder") } catch {}
        assert(RuntimeOptions.installedLanguages(in: nil) == ["english"])
        let base = directory.appendingPathComponent("Languages")
        let pack = directory.appendingPathComponent("Langpacks/POLISH/LANGUAGES")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data().write(to: base.appendingPathComponent("French.BIN"))
        try Data().write(to: pack.appendingPathComponent("English.bin"))
        let languages = RuntimeOptions.installedLanguages(in: directory)
        assert(languages.contains("french") && languages.contains("polish"))
        assert(!languages.contains("russian") && !languages.contains("german"))
        puts("PASS default runtime choices clear stale launch variables")
    }
}
