import Foundation

struct GameLanguage: Identifiable, Equatable {
    let id: String
    let name: String
    let file: String
}

struct RuntimeOptions: Codable, Equatable {
    var language = "english"
    var frameRate = "auto"
    var controller = "on"
    var stickDeadzone = 0.08
    var triggerDeadzone = 0.02
    var customMusic = false
    var musicFolder = ""

    static let frameRates = ["auto", "30", "60", "120", "240"]
    static let controllers = ["on", "off", "hotplug"]
    static let environmentKeys = ["NFSU2_LANGUAGE", "NFSU2_FPS", "NFSU2_PAD", "NFSU2_PAD_DEADZONE", "NFSU2_PAD_TRIGGER_DEADZONE", "NFSU2_RADIO", "NFSU2_MUSIC_FOLDER"]
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
        var env = ["NFSU2_LANGUAGE": language, "NFSU2_FPS": frameRate, "NFSU2_PAD": controller,
                   "NFSU2_PAD_DEADZONE": String(stickDeadzone), "NFSU2_PAD_TRIGGER_DEADZONE": String(triggerDeadzone),
                   "NFSU2_RADIO": customMusic ? "1" : "0"]
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
