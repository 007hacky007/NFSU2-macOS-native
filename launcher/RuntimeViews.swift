import SwiftUI

struct RuntimeSettingsCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Game settings") {
            Picker("Language", selection: $model.runtimeOptions.language) {
                ForEach(RuntimeOptions.languages) { language in
                    Text(language.name + (model.installedLanguages.contains(language.id) ? "" : " (not installed)"))
                        .tag(language.id).disabled(!model.installedLanguages.contains(language.id))
                }
            }
            Picker("Frame rate", selection: $model.runtimeOptions.frameRate) {
                ForEach(RuntimeOptions.frameRates, id: \.self) { value in
                    Text(value == "auto" ? "Match display" : "\(value) FPS").tag(value)
                }
            }
            Text("Cutscenes keep the game's own frame limit.")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
            Picker("Controller", selection: $model.runtimeOptions.controller) {
                Text("Enabled").tag("on")
                Text("Disabled").tag("off")
                Text("While connected").tag("hotplug")
            }
            if model.runtimeOptions.controller != "off" {
                HStack {
                    Text("Stick dead zone").frame(width: 125, alignment: .leading)
                    Slider(value: $model.runtimeOptions.stickDeadzone, in: 0...0.5, step: 0.01)
                    Text("\(Int(model.runtimeOptions.stickDeadzone * 100))%").frame(width: 36)
                }
                HStack {
                    Text("Trigger dead zone").frame(width: 125, alignment: .leading)
                    Slider(value: $model.runtimeOptions.triggerDeadzone, in: 0...0.5, step: 0.01)
                    Text("\(Int(model.runtimeOptions.triggerDeadzone * 100))%").frame(width: 36)
                }
                Text("Raise a dead zone if a centred stick or released trigger sends input. Bind buttons in the game's Controls menu.")
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
            }
            if let error = model.runtimeError {
                Text(error).font(.system(size: 11)).foregroundColor(Theme.bad)
            }
        }.font(.system(size: 12))
    }
}

struct MusicCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Music") {
            Picker("", selection: $model.runtimeOptions.customMusic) {
                Text("Game soundtrack").tag(false)
                Text("Music folder").tag(true)
            }.pickerStyle(SegmentedPickerStyle()).labelsHidden()
            HStack {
                Text(model.runtimeOptions.musicFolder.isEmpty ? "Choose a folder to use your own music." : model.runtimeOptions.musicFolder)
                    .font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(2).truncationMode(.middle)
                Spacer()
                Button("Choose Folder...") { model.chooseMusicFolder() }.buttonStyle(SecondaryButtonStyle())
            }
            Text("Local files only. The game's music volume and pause controls still apply. Unsupported tracks are skipped.")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
        }
    }
}
