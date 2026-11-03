// Settings > Online: the options of free roam with other players that came after
// its first version (ported from th0mk's nfsu2-web, MIT): the engine's own default
// is on for each, so the launcher only passes the ones turned off.
//   tuners  NFSU2_ROAM_TUNERS=0: the game's outrun tuners stay away while other
//           players' cars are about (runtime/roam_game.c em_update).  On: they
//           come as in the original game.
//   map     NFSU2_ROAM_MAP_FILTER=0: no Players and Players' races rows in the world
//           map's legend (roam_game.c wmf_*), every marker shown, as in the original game.
//   friends NFSU2_ROAM_FRIENDS=0: no friend requests by front bumpers, friends not
//           marked, no notices (Friends.swift, runtime/native_controls.m).
//   grey    NFSU2_ROAM_AI_GREY=0: the game's outrun challengers keep the game's orange on
//           the minimap and the world map (roam_game.c arrow_colours, ai_map_open).
//   cars    NFSU2_ROAM_MAX_CARS: how many other players' cars free roam shows near you,
//           16 to 48 (32 by default); the server links the game with as many players
//           (roam_core.h core version 10).
// And the collisions of Free roam with other players (Views.swift):
//   NFSU2_ROAM_COLLIDE 1 solid cars, 0 ghost cars, none everything a ghost: the game's
//   traffic and tuners pass through too (roam_game.c ghost_pair), not a tuner you race.
import SwiftUI

enum RoamExtras {
    /// first start: everything on, as in nfsu2-web
    static let defaults: [String: Any] = [Prefs.roamTuners: true, Prefs.roamMapFilter: true, Prefs.roamAIGrey: true, Prefs.roamFriends: true,
                                          Prefs.roamCars: defaultCars]

    /// Players' cars shown: the choices, and the engine's own default.
    static let carChoices = [16, 24, 32, 40, 48]
    static let defaultCars = 32
    /// a stored value, or the default when it is none of the choices
    static func cars(_ n: Int) -> Int { carChoices.contains(n) ? n : defaultCars }

    /// NFSU2_ROAM_COLLIDE for a Free roam choice (free roam on).
    static func collide(_ f: LauncherModel.FreeRoam) -> String {
        switch f {
        case .solid, .off: return "1"
        case .ghost: return "0"
        case .everything: return "none"
        }
    }

    /// What play() hands the engine for these options (with free roam on): only the ones that are off.
    static func environment(tuners: Bool, mapFilter: Bool, aiGrey: Bool, friends: Bool) -> [(String, String)] {
        var e: [(String, String)] = []
        if !tuners { e.append(("NFSU2_ROAM_TUNERS", "0")) }
        if !mapFilter { e.append(("NFSU2_ROAM_MAP_FILTER", "0")) }
        if !aiGrey { e.append(("NFSU2_ROAM_AI_GREY", "0")) }
        if !friends { e.append(("NFSU2_ROAM_FRIENDS", "0")) }
        return e
    }
}

/// The rows under Free roam with other players (Views.swift MultiplayerCard).
struct RoamExtrasRows: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(title: "Outrun tuners with other players",
                       description: "The game's tuners challenge you to outruns with other players around, so their unique parts can be won online too. On: as in the original game, where they always come. Off: they stay away while another player's car is in your world.",
                       isOn: $model.roamTuners)
            SettingRow(title: "Players in the world map's legend",
                       description: "Two rows more in the legend, Players and Players' races: pick one and press Enter to leave the other players' markers or their race lobbies off the map. Off: as in the original game.",
                       isOn: $model.roamMapFilter)
            SettingRow(title: "Players' cars shown",
                       description: "How many other players' cars free roam draws near you, the nearest first; the world map shows every player of your room. More cars need a faster Mac.") {
                Picker("", selection: $model.roamCars) {
                    ForEach(RoamExtras.carChoices, id: \.self) { n in Text("\(n)").tag(n) }
                }
                .labelsHidden().fixedSize()
            }
            SettingRow(title: "Tuners grey on the maps",
                       description: "The game's own outrun challengers in grey on the minimap and the world map, so you can tell them from players, who keep the orange. Off: as in the original game.",
                       isOn: $model.roamAIGrey)
        }
        .disabled(model.freeRoam == .off).opacity(model.freeRoam == .off ? 0.5 : 1)
    }
}
