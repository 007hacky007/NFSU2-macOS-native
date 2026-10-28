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
