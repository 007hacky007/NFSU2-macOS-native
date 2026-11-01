// The Settings window: the launcher's options, on tabs.  The main window
// (Views.swift) stays small and only has what a player needs before Play.
//
// Adding an option:
//   1. Game.swift: a Prefs key, and the value that gives the original game in
//      Prefs.originalGame (Restore Original Game walks that list).
//   2. Model.swift: a @Published property (read in init, saved in didSet) and its
//      setenv(..., 0) in play(), so a variable set by hand still wins.
//   3. Here: a SettingRow in its tab's view, inside a Card:
//          SettingRow(title: "Frame-rate counter",
//                     description: "Frames per second in a corner. Off: as in the original game.",
//                     isOn: $model.fpsCounter)
//      Other controls go in the closure: SettingRow(title: ..., description: ...) { Picker(...) }.
//      A switch's description ends with "Off: as in the original game."; a picker
//      labels the choice that gives the original game "(original)".
//      A Card holds any views, so it can also end with its own buttons:
//          Card("Data mods") { SettingRow(...) ...; HStack { Spacer(); Button("Add File…") { ... } } }
// A tab with no rows is hidden: list it in SettingsTab.shown and give it a view in
// SettingsView.page when its first row lands.
import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case graphics, picture, controls, online, game, mods, more

    /// The tabs that have rows, in this order.
    static let shown: [SettingsTab] = [.graphics, .picture, .controls, .online, .game, .mods, .more]

    var title: String { rawValue.capitalized }
    var icon: String {          // SF Symbols available on macOS 11
        switch self {
        case .graphics: return "display"
        case .picture: return "camera.filters"
        case .controls: return "gamecontroller"
        case .online: return "network"
        case .game: return "car"
        case .mods: return "puzzlepiece"
        case .more: return "ellipsis.circle"
        }
    }
}

/// One option: title, dim description, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control
    init(title: String, description: String = "", @ViewBuilder control: () -> Control) {
        self.title = title; self.description = description; self.control = control()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5)).foregroundColor(Theme.text)
                if !description.isEmpty {
                    Text(description).font(.system(size: 11)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

struct SettingSwitch: View {
    @Binding var isOn: Bool
    var body: some View { Toggle("", isOn: $isOn).labelsHidden().toggleStyle(SwitchToggleStyle()) }
}

extension SettingRow where Control == SettingSwitch {
    /// A switch.
    init(title: String, description: String = "", isOn: Binding<Bool>) {
        self.init(title: title, description: description) { SettingSwitch(isOn: isOn) }
    }
}

// MARK: tabs

struct GraphicsSettings: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.canChooseEngine {
                Card("Engine") {
                    Picker("", selection: $model.engine) {
                        Text("Original").tag(LauncherModel.Engine.original)
                        Text("HD").tag(LauncherModel.Engine.hd)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .fixedSize()
                    Text(model.engine == .hd
                         ? "Anti-aliasing and ray-traced reflections on top of the game's own look. The Mac works harder and gets warmer."
                         : "The game exactly as it looked on PC. Uses the least power.")
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Card("HUD") {
                SettingRow(title: "HUD at the screen edges",
                           description: "On wide screens the minimap moves to the left and the gauges to the right. Off: the HUD stays in the 4:3 middle.",
                           isOn: $model.wideHUD)
                SettingRow(title: "Frame-rate counter", description: "Cmd-N switches while playing. Off: as in the original game.") {
                    Picker("", selection: $model.fpsCounter) {
                        Text("Off").tag(0)
                        Text("On").tag(1)
                        Text("Detailed").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle()).labelsHidden().fixedSize()
                }
                SettingRow(title: "Metal performance overlay",
                           description: "Apple's Metal HUD in the corner: frame rate, frame times, GPU time and memory. For checking performance. Off: as in the original game.",
                           isOn: $model.metalHUD)
            }
            FrameRateCard(model: model)
            DisplayCard(model: model)
            Card("Lights") {
                SettingRow(title: "Other cars' headlights",
                           description: "Light the road as yours do. Players: the other players' cars in network races; All cars: AI racers and traffic too.") {
                    Picker("", selection: $model.headlights) {
                        Text("Players").tag("players")
                        Text("All cars").tag("all")
                        Text("Off (original)").tag("off")
                    }
                    .labelsHidden().fixedSize()
                }
            }
            ReflectionsCard(model: model)
            FirstLaunchCard(model: model)
        }
    }
}

/// Resolution scale, movies, the background (DisplayOptions.swift).
struct DisplayCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Display") {
            SettingRow(title: "Resolution scale",
                       description: "With the game's own Screen resolution: draws this share of the window's pixels. Lower is faster, higher is sharper.") {
                Picker("", selection: $model.resolutionScale) {
                    ForEach(DisplayOptions.scales, id: \.self) { Text(DisplayOptions.scaleLabel($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            SettingRow(title: "Movie framing",
                       description: "How the movies fill a wide window. Fit keeps black bars at the sides, Fill crops the top and bottom.") {
                Picker("", selection: $model.movieFraming) {
                    ForEach(DisplayOptions.framings, id: \.self) { Text(DisplayOptions.framingLabel($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            SettingRow(title: "Movie subtitles",
                       description: "The story's and the tutorials' lines under the movies, in languages whose text has them. English needs the English subtitles pack (Mods tab). Off: as in the original game.",
                       isOn: $model.subtitles)
            SettingRow(title: "While another app is active",
                       description: "The game pauses like on Windows, or keeps running. LAN and online sessions always keep running so you stay connected.") {
                Picker("", selection: $model.background) {
                    ForEach(DisplayOptions.backgrounds, id: \.self) { Text(DisplayOptions.backgroundLabel($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}

struct PictureSettings: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { PictureCard(model: model) }
    }
}

struct ControlsSettings: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { ControllerCard(model: model); RumbleCard(model: model) }
    }
}

struct OnlineSettingsTab: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { MultiplayerCard(model: model); NetTimingCard(model: model) }
    }
}

struct GameSettings: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card("Career") {
                if model.hasAllRegionCars {
                    SettingRow(title: "Both releases' cars",
                               description: "The Corsa, Peugeot 106, Civic and RSX all for sale and in races. Off: as in the original game.",
                               isOn: $model.allCars)
                }
                SettingRow(title: "10-car garage and Trade Car",
                           description: "Career slots 6-10, and trading a car in for 80% of what it cost. A save made while off loses the cars in slots 6-10. Off: as in the original game.",
                           isOn: $model.garage)
                SettingRow(title: "Show hidden races",
                           description: "The career's 33 hidden races on the map and the radar like the others, and up to 8 races of each kind on the map at once, as MaxHwoy's Show Hidden Races Mod. Off: as in the original game, a hidden race shows only when you drive near it.",
                           isOn: $model.hiddenRaces)
            }
            Card("Start") {
                SettingRow(title: "Intro movies", description: "The logos and the opening movie. Skippable: a key or pad button skips each.") {
                    Picker("", selection: $model.intro) {
                        Text("Skippable").tag("skippable")
                        Text("Off").tag("off")
                        Text("Original").tag("original")
                    }
                    .pickerStyle(SegmentedPickerStyle()).labelsHidden().fixedSize()
                }
                SettingRow(title: "Show in Discord",
                           description: "Your Discord status shows the game and the race you are in. Only with the Discord app on this Mac. Off: as in the original game.",
                           isOn: $model.discord)
                DiscordImageRow(model: model)
            }
            MusicCard(model: model)
            PhotoDriftCard(model: model)
        }
    }
}

struct ModsSettings: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card("Textures") {
                UHUDRow(model: model)
                TexturePacksRow(model: model, store: model.packs)
            }
            ModsCard(model: model)
            LanguagePacksCard(model: model, store: model.langPacks)
        }
    }
}

struct MoreSettings: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                SettingRow(title: "Check for updates",
                           description: model.builderStamp == nil
                               ? "This app was not made by NFSU2 Builder, so it is updated by building it again."
                               : "Once a day the launcher asks GitHub whether a newer NFSU2 Builder is out; the new Builder updates this app. Off: no network request.",
                           isOn: $model.checkUpdates)
                    .disabled(model.builderStamp == nil)
                SettingRow(title: "Portable copy",
                           description: model.location?.embedded == true
                               ? "This app already has the game inside and can be moved anywhere. Make Copy makes another one, with your language packs, for another Mac or a USB drive. Movies and language packs can be left out to make it smaller."
                               : "One app with the game inside, for another Mac or a USB drive. Movies and language packs can be left out to make it smaller.") {
                    Button("Make Copy…") { model.makePortable() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!model.isReady)
                }
                SettingRow(title: "Graphics settings in the game",
                           description: "The game picks them for this Mac again on its next start, as on its first one. Career saves are not affected.") {
                    Button("Reset…") { model.resetGraphics() }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}

// MARK: window

/// The selected tab.  An ObservableObject rather than @State: with the command line
/// tools' Swift 6.4 compiler @State is a macro whose plugin isn't there (pack.sh).
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab
    init(_ tab: SettingsTab) { self.tab = tab }
}

struct SettingsView: View {
    static var size = CGSize(width: 560, height: 470)   // taller only for a snapshot (main.swift)
    @ObservedObject var model: LauncherModel
    @ObservedObject private var selection: SettingsSelection
    private var tab: SettingsTab { selection.tab }

    init(model: LauncherModel, tab: SettingsTab = SettingsTab.shown[0]) {
        self.model = model
        self.selection = SettingsSelection(tab)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .graphics: GraphicsSettings(model: model)
        case .picture: PictureSettings(model: model)
        case .controls: ControlsSettings(model: model)
        case .online: OnlineSettingsTab(model: model)
        case .game: GameSettings(model: model)
        case .mods: ModsSettings(model: model)
        case .more: MoreSettings(model: model)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.shown, id: \.self) { t in
                Button(action: { selection.tab = t }) {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17))
                            .frame(height: 22)
                        Text(t.title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(t == tab ? Theme.accent : Theme.dim)
                    .frame(minWidth: 66).padding(.vertical, 6).padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(t == tab ? 0.08 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                tabBar.padding(.top, 2).padding(.bottom, 10)
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
                ScrollView {
                    page.padding(.horizontal, 22).padding(.vertical, 14)
                }
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
                HStack(alignment: .center) {
                    if let n = model.notice {
                        Text(n).font(.system(size: 11)).foregroundColor(Theme.accent)
                    } else if model.isOriginalGame {
                        Text("Every option is as in the original game.")
                            .font(.system(size: 11)).foregroundColor(Theme.dim)
                    }
                    Spacer(minLength: 8)
                    Button("Restore Original Game…") { model.confirmRestoreOriginalGame() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.isOriginalGame)
                        .help("Every option back to the value that gives the original, unmodified game.")
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
            }
            if let j = model.job { JobOverlay(model: model, job: j) }
            if model.editingQuickChat { QuickChatEditor(model: model, draft: model.quickChatDraft) }   // QuickChat.swift
        }
        .frame(width: SettingsView.size.width, height: SettingsView.size.height)
    }
}

/// The Settings window: same look as the main window, a fixed size; a tab
/// taller than the window scrolls.
func makeSettingsWindow(model: LauncherModel, tab: SettingsTab) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                     styleMask: [.titled, .closable, .miniaturizable],
                     backing: .buffered, defer: false)
    w.titlebarAppearsTransparent = true
    w.title = "Settings"
    w.isMovableByWindowBackground = true
    w.isReleasedWhenClosed = false
    w.appearance = NSAppearance(named: .darkAqua)
    w.backgroundColor = NSColor(calibratedRed: 0.067, green: 0.071, blue: 0.082, alpha: 1)
    w.contentView = NSHostingView(rootView: SettingsView(model: model, tab: tab))
    w.center()
    return w
}
