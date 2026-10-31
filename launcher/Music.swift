// Music: the game's own soundtrack, or a folder of the player's music played
// through EA Trax (engine: runtime/radio.c and radio_native.m, NFSU2_RADIO=1 and
// NFSU2_MUSIC_FOLDER).  The card is on the Game tab of the Settings window.
import AppKit
import SwiftUI

extension LauncherModel {
    var musicFolderExists: Bool {
        var dir: ObjCBool = false
        return musicFolder.hasPrefix("/") && FileManager.default.fileExists(atPath: musicFolder, isDirectory: &dir) && dir.boolValue
    }

    /// The picker: "Music folder" with no folder yet asks for one; cancelled, the
    /// game's soundtrack stays.
    func pickMusic(_ source: String) {
        if source == "folder" && !musicFolderExists && !chooseMusicFolder() { music = "game"; return }
        music = source
    }

    @discardableResult
    func chooseMusicFolder() -> Bool {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Choose a folder of music to play through EA Trax instead of the game's soundtrack."
        if musicFolderExists { p.directoryURL = URL(fileURLWithPath: musicFolder) }
        guard p.runModal() == .OK, let dir = p.url else { return false }
        musicFolder = dir.path
        music = "folder"
        return true
    }

    /// For play(): the engine's variables; ones set by hand still win.
    func applyMusic() {
        guard music == "folder" && musicFolderExists else { return }
        setenv("NFSU2_RADIO", "1", 0)
        setenv("NFSU2_MUSIC_FOLDER", musicFolder, 0)
    }
}

struct MusicCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Music") {
            SettingRow(title: "EA Trax plays", description: detail) {
                Picker("", selection: Binding(get: { model.music }, set: { model.pickMusic($0) })) {
                    Text("Game soundtrack (original)").tag("game")
                    Text("Music folder").tag("folder")
                }
                .labelsHidden().fixedSize()
            }
            HStack(alignment: .center, spacing: 12) {
                Text(model.musicFolder.isEmpty ? "No folder chosen" : model.musicFolder)
                    .font(.system(size: 11.5)).foregroundColor(Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Button(model.musicFolder.isEmpty ? "Choose Folder..." : "Change Folder...") { model.chooseMusicFolder() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var detail: String {
        if model.music == "game" { return "The game's own songs, as in the original game." }
        if !model.musicFolderExists { return "This folder is not there, so the game plays its own songs. Choose another folder." }
        return "Your local files (WAV, MP3, AAC/M4A, FLAC...) with their artist and title on the plaque. Music volume and pause still apply; files that do not play are skipped. In the game: app menu > Music."
    }
}
