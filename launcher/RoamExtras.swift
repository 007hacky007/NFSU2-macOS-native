// Settings > Online: the options of free roam with other players that came after
// its first version (ported from th0mk's nfsu2-web, MIT): the engine's own default
// is on for each, so the launcher only passes the ones turned off.
//   tuners  NFSU2_ROAM_TUNERS=0: the game's outrun tuners stay away while other
//           players' cars are about (runtime/roam_game.c em_update).  On: they
//           come as in the original game.
//   map     NFSU2_ROAM_MAP_FILTER=0: no Players and Players' races rows in the world
//           map's legend (roam_game.c wmf_*), every marker shown, as in the original game.
import SwiftUI

enum RoamExtras {
    /// first start: everything on, as in nfsu2-web
    static let defaults: [String: Any] = [Prefs.roamTuners: true, Prefs.roamMapFilter: true]

    /// What play() hands the engine for these options (with free roam on): only the ones that are off.
    static func environment(tuners: Bool, mapFilter: Bool) -> [(String, String)] {
        var e: [(String, String)] = []
        if !tuners { e.append(("NFSU2_ROAM_TUNERS", "0")) }
        if !mapFilter { e.append(("NFSU2_ROAM_MAP_FILTER", "0")) }
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
        }
        .disabled(model.freeRoam == .off).opacity(model.freeRoam == .off ? 0.5 : 1)
    }
}
