import Foundation

struct GameLanguage: Identifiable, Equatable {
    let id: String
    let name: String
    let file: String
}

struct RuntimeOptions: Codable, Equatable {
    var language = "english"
    var frameRate = "auto"
    var cutscenes60 = false
    var controller = "on"
    var stickDeadzone = 0.08
    var triggerDeadzone = 0.02
    var customMusic = false
    var musicFolder = ""
    var resolutionScale = "backing"
    var hud = "wide"
    var subtitles = true
    var movieFraming = "fit"
    var cutsceneBorders = "full"
    var headlights = "players"
    var background = "pause"
    var roamRoom = ""

    init() {}
    private enum CodingKeys: String, CodingKey {
        case language, frameRate, cutscenes60, controller, stickDeadzone, triggerDeadzone, customMusic, musicFolder
        case resolutionScale, hud, subtitles, movieFraming, cutsceneBorders, headlights, background, roamRoom
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? language
        frameRate = try c.decodeIfPresent(String.self, forKey: .frameRate) ?? frameRate
        cutscenes60 = try c.decodeIfPresent(Bool.self, forKey: .cutscenes60) ?? cutscenes60
        controller = try c.decodeIfPresent(String.self, forKey: .controller) ?? controller
        stickDeadzone = try c.decodeIfPresent(Double.self, forKey: .stickDeadzone) ?? stickDeadzone
        triggerDeadzone = try c.decodeIfPresent(Double.self, forKey: .triggerDeadzone) ?? triggerDeadzone
        customMusic = try c.decodeIfPresent(Bool.self, forKey: .customMusic) ?? customMusic
        musicFolder = try c.decodeIfPresent(String.self, forKey: .musicFolder) ?? musicFolder
        resolutionScale = try c.decodeIfPresent(String.self, forKey: .resolutionScale) ?? resolutionScale
        hud = try c.decodeIfPresent(String.self, forKey: .hud) ?? hud
        subtitles = try c.decodeIfPresent(Bool.self, forKey: .subtitles) ?? subtitles
        movieFraming = try c.decodeIfPresent(String.self, forKey: .movieFraming) ?? movieFraming
        cutsceneBorders = try c.decodeIfPresent(String.self, forKey: .cutsceneBorders) ?? cutsceneBorders
        headlights = try c.decodeIfPresent(String.self, forKey: .headlights) ?? headlights
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? background
        roamRoom = try c.decodeIfPresent(String.self, forKey: .roamRoom) ?? roamRoom
    }

    static let frameRates = ["auto", "30", "60", "120", "240"]
    static let controllers = ["on", "off", "hotplug"]
    static let resolutionScales = ["scale:0.5", "scale:0.75", "backing", "scale:1.5", "scale:2"]
    static let environmentKeys = ["NFSU2_LANGUAGE", "NFSU2_FPS", "NFSU2_CUTSCENES_60", "NFSU2_PAD", "NFSU2_PAD_DEADZONE", "NFSU2_PAD_TRIGGER_DEADZONE", "NFSU2_RADIO", "NFSU2_MUSIC_FOLDER", "NFSU2_RENDER", "NFSU2_HUD", "NFSU2_SUBTITLES", "NFSU2_MOVIE", "NFSU2_CUTSCENE_BORDERS", "NFSU2_HEADLIGHTS", "NFSU2_BACKGROUND", "NFSU2_ROAM_ROOM"]
    static let languages: [GameLanguage] = [
        .init(id: "english", name: "English", file: "english.bin"),
        .init(id: "french", name: "French", file: "french.bin"),
        .init(id: "german", name: "German", file: "german.bin"),
        .init(id: "italian", name: "Italian", file: "italian.bin"),
        .init(id: "spanish", name: "Spanish", file: "spanish.bin"),
        .init(id: "dutch", name: "Dutch", file: "dutch.bin"),
        .init(id: "swedish", name: "Swedish", file: "swedish.bin"),
        .init(id: "danish", name: "Danish", file: "danish.bin"),
        .init(id: "korean", name: "Korean", file: "korean.bin"),
        .init(id: "chinese", name: "Traditional Chinese", file: "chinese.bin"),
        .init(id: "japanese", name: "Japanese", file: "japanese.bin"),
        .init(id: "russian", name: "Russian", file: "english.bin"),
        .init(id: "thai", name: "Thai", file: "thailand.bin"),
        .init(id: "portuguese", name: "Brazilian Portuguese", file: "english.bin"),
        .init(id: "polish", name: "Polish", file: "english.bin"),
        .init(id: "turkish", name: "Turkish", file: "english.bin")
    ]

    private static func child(_ name: String, in folder: URL) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func installedLanguages(in game: URL?) -> Set<String> {
        var found: Set<String> = ["english"]
        guard let game = game else { return found }
        let base = child("LANGUAGES", in: game)
        let packs = child("LANGPACKS", in: game)
        let packOnly: Set<String> = ["russian", "portuguese", "polish", "turkish"]
        for language in languages where language.id != "english" {
            let retail = !packOnly.contains(language.id) && base.flatMap { child(language.file, in: $0) } != nil
            let pack = packs.flatMap { child(language.id, in: $0) }.flatMap { child("LANGUAGES", in: $0) }
            if retail || pack.flatMap({ child(language.file, in: $0) }) != nil { found.insert(language.id) }
        }
        return found
    }

    func environment() throws -> [String: String] {
        guard Self.languages.contains(where: { $0.id == language }), Self.frameRates.contains(frameRate), Self.controllers.contains(controller),
              stickDeadzone.isFinite, triggerDeadzone.isFinite,
              (0...0.5).contains(stickDeadzone), (0...0.5).contains(triggerDeadzone) else {
            throw SettingsError("Choose a supported language, frame rate and controller setting. Dead zones must be between 0 and 50%.")
        }
        guard Self.resolutionScales.contains(resolutionScale), ["wide", "43"].contains(hud),
              ["fit", "fill", "stretch"].contains(movieFraming), ["full", "off"].contains(cutsceneBorders),
              ["players", "all", "off"].contains(headlights), ["pause", "run"].contains(background) else {
            throw SettingsError("Choose a supported resolution scale, HUD, movie, headlight and background setting.")
        }
        guard roamRoom.utf8.count <= 63, roamRoom.utf8.allSatisfy({ $0 >= 32 && $0 != 127 }) else {
            throw SettingsError("Use a shorter room name without control characters (63 UTF-8 bytes maximum), or leave it empty for everyone.")
        }
        guard roamRoom.withCString({ name_blocked($0) == 0 }) else {
            throw SettingsError("Choose another room name. The multiplayer name rules reject this one.")
        }
        var env = ["NFSU2_LANGUAGE": language, "NFSU2_FPS": frameRate, "NFSU2_CUTSCENES_60": cutscenes60 ? "1" : "0", "NFSU2_PAD": controller,
                   "NFSU2_PAD_DEADZONE": String(stickDeadzone), "NFSU2_PAD_TRIGGER_DEADZONE": String(triggerDeadzone),
                   "NFSU2_RADIO": customMusic ? "1" : "0", "NFSU2_RENDER": resolutionScale,
                   "NFSU2_HUD": hud, "NFSU2_SUBTITLES": subtitles ? "1" : "0", "NFSU2_MOVIE": movieFraming,
                   "NFSU2_CUTSCENE_BORDERS": cutsceneBorders, "NFSU2_HEADLIGHTS": headlights,
                   "NFSU2_BACKGROUND": background, "NFSU2_ROAM_ROOM": roamRoom.trimmingCharacters(in: .whitespaces)]
        if customMusic {
            var directory: ObjCBool = false
            guard musicFolder.hasPrefix("/"), FileManager.default.fileExists(atPath: musicFolder, isDirectory: &directory), directory.boolValue else {
                throw SettingsError("Choose an available music folder, or use the game soundtrack.")
            }
            env["NFSU2_MUSIC_FOLDER"] = musicFolder
        }
        return env
    }
}
