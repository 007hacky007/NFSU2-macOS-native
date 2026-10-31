// The launcher's main window and the look it shares with Settings (Settings.swift).
// SwiftUI as available on macOS 11 (the app's minimum).
import SwiftUI

enum Theme {
    static let background = Color(red: 0.067, green: 0.071, blue: 0.082)
    static let card = Color.white.opacity(0.045)
    static let cardBorder = Color.white.opacity(0.08)
    static let accent = Color(red: 0.62, green: 0.87, blue: 0.27)      // the game's menu green
    static let warn = Color(red: 1.0, green: 0.68, blue: 0.24)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.36)
    static let text = Color.white.opacity(0.92)
    static let dim = Color.white.opacity(0.55)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledLabel(configuration: configuration) }
    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.black.opacity(enabled ? 0.88 : 0.45))
                .padding(.horizontal, 30).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(enabled ? Theme.accent.opacity(configuration.isPressed ? 0.72 : 1)
                                  : Color.white.opacity(0.15)))
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledLabel(configuration: configuration) }
    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text.opacity(enabled ? 1 : 0.4))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.09)))
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String = "", @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold)).foregroundColor(Theme.dim)
                    .tracking(0.8)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct GameCard: View {
    @ObservedObject var model: LauncherModel

    private var status: (Color, String, String) {
        switch model.game {
        case .searching:
            return (Theme.dim, "Looking for the game…", "")
        case .notFound:
            return (Theme.warn, "Game files not found",
                    "Choose the folder where Need for Speed Underground 2 is installed (the folder with SPEED2.EXE in it). Your own copy of the PC game is needed.")
        case .ready(let l):
            return (Theme.accent, l.embedded ? "Ready · the game is inside this app" : "Ready · \(l.build?.name ?? "supported version")",
                    l.embedded ? "This is a portable copy: it needs no separate game folder." : l.folder.path)
        case .unsupported(let l, let size):
            if let b = l.build {
                return (Theme.bad, "No engine for this version in this app",
                        "\(l.folder.path) has the \(b.name) SPEED2.EXE, but this copy of the app has no engine for it. Use a release that includes it.")
            }
            return (Theme.bad, "This SPEED2.EXE is a different version",
                    "Found \(formatBytes(Int64(size))) at \(l.folder.path). The port runs the European v1.2 (4,788,224 bytes) and North American v1.2 (4,800,512 bytes) SPEED2.EXE without the CD check; other versions, such as the US disc one, would crash.")
        }
    }

    var body: some View {
        Card("Game files") {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(status.0).frame(width: 9, height: 9).padding(.top, 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.1).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                    if !status.2.isEmpty {
                        Text(status.2).font(.system(size: 11)).foregroundColor(Theme.dim)
                            .lineLimit(3).truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 8) {
                if model.location?.embedded != true {
                    Button(model.location == nil ? "Choose Folder…" : "Change Folder…") { model.chooseFolder() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if model.location != nil {
                    Button("Show in Finder") { model.revealGame() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if model.languages.count > 1 {
                HStack(alignment: .center) {
                    Text("Language").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Spacer(minLength: 8)
                    Picker("", selection: $model.language) {
                        ForEach(model.languages, id: \.self) { id in
                            Text(Languages.all.first { $0.id == id }?.name ?? id).tag(id)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
    }
}

/// LunicAura106's Upscaled HUD: added once from the mod's download, then a switch.
struct UHUDRow: View {
    @ObservedObject var model: LauncherModel
    private var text: String {
        if model.uhudBusy { return model.uhudPhase }
        if model.hasUHUDPack {
            return "LunicAura106's Upscaled HUD mod: menus, HUD, fonts and icons drawn at four times the detail. Cmd-T switches while playing. Off: as in the original game."
        }
        return "LunicAura106's Upscaled HUD mod draws the menus, HUD, fonts and icons at four times the detail. Download gets it from nfsmods.xyz (2.8 MB) and sets it up; your game folder stays as it is."
    }
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sharper menus and HUD").font(.system(size: 12.5)).foregroundColor(Theme.text)
                Text(text).font(.system(size: 11)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if let e = model.uhudError {
                    Text(e).font(.system(size: 11)).foregroundColor(Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if model.hasUHUDPack && !model.uhudBusy {
                Toggle("", isOn: $model.uhud).labelsHidden().toggleStyle(SwitchToggleStyle())
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Download") { model.downloadUHUD() }.buttonStyle(SecondaryButtonStyle())
                        .disabled(model.location == nil || model.uhudBusy)
                    Button("Add File…") { model.addUHUD() }.buttonStyle(SecondaryButtonStyle())
                        .disabled(model.location == nil || model.uhudBusy)
                }
            }
        }
    }
}

struct ModsCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Mods") {
            ForEach(DataMods.catalog, id: \.id) { m in ModRow(model: model, mod: m) }
            if let s = model.modsApplying {
                Text(s).font(.system(size: 11)).foregroundColor(Theme.accent)
            }
        }
    }
}

/// One data mod: Download / Add File... until it is here, then a switch (off: the game's own files).
struct ModRow: View {
    @ObservedObject var model: LauncherModel
    let mod: DataMods.Mod
    var body: some View {
        let have = model.modsHave.contains(mod.id), busy = model.modBusy.contains(mod.id)
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(mod.name).font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("by \(mod.author)").font(.system(size: 11)).foregroundColor(Theme.dim)
                }
                Text(model.modNote[mod.id] ?? (have ? mod.summary + " Off: as in the original game."
                                                    : mod.summary + " \(formatBytes(mod.size)) from nfsmods.xyz."))
                    .font(.system(size: 11))
                    .foregroundColor(model.modNote[mod.id] != nil && !busy ? Theme.warn : Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if have {
                Toggle("", isOn: Binding(get: { model.modsOn.contains(mod.id) }, set: { model.setMod(mod, $0) }))
                    .labelsHidden().toggleStyle(SwitchToggleStyle())
            } else {
                Button("Download") { model.downloadMod(mod) }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
                Button("Add File…") { model.importMod(mod) }.buttonStyle(SecondaryButtonStyle()).disabled(busy)
            }
        }
        .contextMenu {
            Button("Open the Mod's Page") { model.openModPage(mod) }
            if have { Button("Remove \(mod.name)") { model.removeMod(mod) } }
        }
    }
}

struct SwitchRow: View {
    let title: String
    let text: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5)).foregroundColor(Theme.text)
                Text(text).font(.system(size: 11)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(SwitchToggleStyle())
        }
    }
}

struct ReflectionsCard: View {
    @ObservedObject var model: LauncherModel
    private var hdEngine: Bool { model.engine == .hd }
    var body: some View {
        Card("Reflections") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("Sharpness").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Spacer(minLength: 8)
                    Picker("", selection: $model.reflections) {
                        Text("Normal (original)").tag(LauncherModel.Reflections.original)
                        Text("Sharp").tag(LauncherModel.Reflections.sharp)
                        Text("Sharpest").tag(LauncherModel.Reflections.sharpest)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .fixedSize()
                    .disabled(hdEngine)
                }
                Text(hdEngine
                     ? "The HD engine always draws them at least as sharp as Sharpest."
                     : "The wet road, the mirror and the car paint. Sharper ones cost a little GPU time.")
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SwitchRow(title: "Sky in reflections",
                      text: "The sky shows in the wet road and in the mirror of the bumper and hood views. Off: as in the original game.",
                      isOn: $model.reflectSky)
            SwitchRow(title: "Car lights in reflections",
                      text: "The cars' lights glow brightly in the wet road. Off: as in the original game.",
                      isOn: $model.reflectLights)
            SwitchRow(title: "More detail in reflections",
                      text: "Buildings and cars keep their full detail, and the car paint reflects the far city. Off: as in the original game.",
                      isOn: $model.reflectDetail)
        }
    }
}

struct PictureCard: View {
    @ObservedObject var model: LauncherModel
    private func row(_ i: Int) -> some View {
        let o = PictureOptions.all[i]
        return VStack(alignment: .leading, spacing: 3) {
            Text(o.title).font(.system(size: 12)).foregroundColor(Theme.text)
            Picker("", selection: $model.picture[i]) {
                ForEach(0..<o.choices.count, id: \.self) { k in Text(o.choices[k].label).tag(k) }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        Card("Picture") {
            let n = PictureOptions.all.count
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<(n + 1) / 2, id: \.self) { r in
                    HStack(spacing: 18) {
                        row(2 * r)
                        if 2 * r + 1 < n { row(2 * r + 1) } else { Spacer().frame(maxWidth: .infinity) }
                    }
                }
            }
            Text("(original) is the game as it was on PC.")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
        }
    }
}

struct FrameRateCard: View {
    @ObservedObject var model: LauncherModel
    private func label(_ v: String) -> String {
        switch v {
        case "auto": return "Auto (follow the screen)"
        case "120": return "120 FPS (original)"
        default: return "\(v) FPS"
        }
    }
    var body: some View {
        Card("Frame rate") {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Frame rate").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("Speed, physics, smoke and the NOS trail stay as at 60 at any rate. The original game runs at up to 120.")
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Picker("", selection: $model.frameRate) {
                    ForEach(LauncherModel.frameRates, id: \.self) { Text(label($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("60 FPS cutscenes").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("Race intros and other in-game scenes at 60 instead of 30 frames a second. Off: as in the original game.")
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $model.cutscenes60).labelsHidden().toggleStyle(SwitchToggleStyle())
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cutscene black bars").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("Bars at the top and bottom of race intros and in-game scenes. Off shows the whole picture. On: as in the original game.")
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $model.cutsceneBars).labelsHidden().toggleStyle(SwitchToggleStyle())
            }
        }
    }
}

struct MultiplayerCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Multiplayer") {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Play online").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("LAN and the Online menu go through the server. Off: LAN on this Mac's network.")
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $model.online).labelsHidden().toggleStyle(SwitchToggleStyle())
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Server").font(.system(size: 12.5)).foregroundColor(Theme.text).frame(width: 84, alignment: .leading)
                    TextField(OnlineSettings.defaultServer, text: $model.server).textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack(spacing: 10) {
                    Text("Player name").font(.system(size: 12.5)).foregroundColor(Theme.text).frame(width: 84, alignment: .leading)
                    TextField("3-15 letters or numbers", text: $model.playerName).textFieldStyle(RoundedBorderTextFieldStyle())
                }
                if let err = model.onlineError {
                    Text(err).font(.system(size: 11)).foregroundColor(.orange)
                }
            }
            .disabled(!model.online).opacity(model.online ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Free roam with other players").font(.system(size: 12.5)).foregroundColor(Theme.text)
                        Text("See the other players' cars in career free roam and race them from the race markers. Ghost cars drive through yours.")
                            .font(.system(size: 11)).foregroundColor(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Picker("", selection: $model.freeRoam) {
                        Text("Off (original)").tag(LauncherModel.FreeRoam.off)
                        Text("Solid cars").tag(LauncherModel.FreeRoam.solid)
                        Text("Ghost cars").tag(LauncherModel.FreeRoam.ghost)
                    }
                    .labelsHidden().fixedSize()
                }
                HStack(spacing: 10) {
                    Text("Room").font(.system(size: 12.5)).foregroundColor(Theme.text).frame(width: 84, alignment: .leading)
                    TextField("Everyone", text: $model.roamRoom).textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("Crew").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    TextField("None", text: $model.roamCrew).textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .disabled(model.freeRoam == .off).opacity(model.freeRoam == .off ? 0.5 : 1)
                Text("Room: only players in the same room see each other. Crew: your crew's names and arrows in its colour, at any distance.")
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(model.freeRoam == .off ? 0.5 : 1)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hear other players' cars").font(.system(size: 12.5)).foregroundColor(Theme.text)
                        Text("Their engines, nitrous and hydraulics in free roam, from their cars. Off: as in the original game.")
                            .font(.system(size: 11)).foregroundColor(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $model.hearCars).labelsHidden().toggleStyle(SwitchToggleStyle())
                }
                .disabled(model.freeRoam == .off).opacity(model.freeRoam == .off ? 0.5 : 1)
            }
            .disabled(!model.online).opacity(model.online ? 1 : 0.5)
                    Text("Horn").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("Press N to honk at the other players in free roam and Online races. The PC game has no horn: Off (original).")
                Picker("", selection: $model.horn) {
                    ForEach(LauncherModel.Horn.allCases, id: \.self) { h in Text(h.label).tag(h) }
                .labelsHidden().fixedSize()
            .disabled(!model.online).opacity(model.online ? 1 : 0.5)
        }
    }
}

struct ControllerCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Controller") {
                    Text("Use a game controller").font(.system(size: 12.5)).foregroundColor(Theme.text)
                    Text("Xbox, PlayStation or MFi. Connect it before Play; buttons are set in the game's Controls menu.")
                Toggle("", isOn: $model.controller).labelsHidden().toggleStyle(SwitchToggleStyle())
            }
            HStack(alignment: .center, spacing: 10) {
                Text("Stick dead zone").font(.system(size: 12.5)).foregroundColor(Theme.text)
                Slider(value: $model.stickDeadzone, in: 0...0.5, step: 0.01)
                Text("\(Int((model.stickDeadzone * 100).rounded())) %")
                    .font(.system(size: 11.5).monospacedDigit()).foregroundColor(Theme.dim)
                    .frame(width: 40, alignment: .trailing)
            }
            .disabled(!model.controller).opacity(model.controller ? 1 : 0.5)
        }
    }
}

struct JobOverlay: View {
    @ObservedObject var model: LauncherModel
    let job: LauncherModel.Job
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(alignment: .leading, spacing: 12) {
                if let r = job.result {
                    Text("Portable copy ready").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Text("“\(r.deletingPathExtension().lastPathComponent)” has the game inside and runs on its own; you can copy it to another Mac. Saves stay on each Mac, in Application Support › NFSU2 Saves.")
                        .font(.system(size: 12)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Close") { model.closeJob() }.buttonStyle(SecondaryButtonStyle())
                        Button("Show in Finder") { model.revealResult() }.buttonStyle(PrimaryButtonStyle())
                    }
                } else if let e = job.error {
                    Text("The copy could not be made").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Text(e).font(.system(size: 12)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack { Spacer(); Button("Close") { model.closeJob() }.buttonStyle(SecondaryButtonStyle()) }
                } else {
                    Text("Making a portable copy").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Text(job.phase).font(.system(size: 12)).foregroundColor(Theme.dim)
                    ProgressView(value: job.fraction).accentColor(Theme.accent)
                    HStack {
                        Text(job.total > 0 ? "\(formatBytes(job.done)) of \(formatBytes(job.total))" : " ")
                            .font(.system(size: 11)).foregroundColor(Theme.dim)
                        Spacer()
                        Button("Cancel") { model.cancelPortable() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.11, green: 0.115, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        }
    }
}

/// The main window: kept small and of a fixed size; options live in Settings
/// (Settings.swift).  Only what a player needs before Play stays here.
struct LauncherView: View {
    static let size = CGSize(width: 560, height: 430)
    @ObservedObject var model: LauncherModel
    let openSettings: () -> Void

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let b = (info["CFBundleVersion"] as? String) ?? ""
        return "Native macOS port · version \(v)" + (b.isEmpty ? "" : " (\(b))")
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Need for Speed Underground 2")
                            .font(.system(size: 21, weight: .bold)).foregroundColor(Theme.text)
                        HStack(alignment: .lastTextBaseline) {
                            Text(versionText).font(.system(size: 11.5)).foregroundColor(Theme.dim)
                            Spacer(minLength: 8)
                            Button("Report a Problem") { model.reportProblem() }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(.bottom, 4)

                GameCard(model: model)
                Card {
                    SettingRow(title: "Start in full screen",
                               description: "Cmd-F switches while playing. Resolution: in the game, Options › Display.",
                               isOn: $model.fullscreen)
                }
                // Windows on the left (a new one, e.g. Texture Packs…, gets a button
                // after Settings…), folders on the right.
                HStack(spacing: 8) {
                    Button("Settings…") { openSettings() }.buttonStyle(SecondaryButtonStyle())
                    Spacer(minLength: 0)
                    Button("Saves…") { model.manageSaves() }.buttonStyle(SecondaryButtonStyle())
                    Button("Logs") { model.openLogs() }.buttonStyle(SecondaryButtonStyle())
                }

                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Show this window when the app opens", isOn: $model.showAtStartup)
                            .toggleStyle(CheckboxToggleStyle())
                            .font(.system(size: 12)).foregroundColor(Theme.text)
                        Text("When off, hold ⌥ Option while opening the app to see it again.")
                            .font(.system(size: 10.5)).foregroundColor(Theme.dim)
                    }
                    Spacer()
                    Button("Play") { model.play() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.isReady || model.job != nil)
                }
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 18)
            if let j = model.job { JobOverlay(model: model, job: j) }
        }
        .frame(width: LauncherView.size.width, height: LauncherView.size.height)
    }
}
