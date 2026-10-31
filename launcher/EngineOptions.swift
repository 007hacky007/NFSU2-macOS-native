// Engine options of the "engine fixes" work (runtime/regseed.c, framerate.c):
// the graphics the game starts with on the first launch, and how network
// races keep time.  Each one's original-game value is in Prefs.originalGame.
import SwiftUI

/// Graphics tab: the highest graphics settings on the first launch
/// (NFSU2_SEED_REGISTRY=1).
struct FirstLaunchCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("First launch") {
            SettingRow(title: "Highest graphics on first launch",
                       description: "With no saved settings yet, the game starts with every graphics option at its highest instead of running its own hardware check. Saved settings are kept. Off: as in the original game.",
                       isOn: $model.seedRegistry)
        }
    }
}

/// Online tab: network race timing (NFSU2_LAN_TIMING).
struct NetTimingCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Network races") {
            SettingRow(title: "Race timing",
                       description: "As on a PC: the game's own clocks at your frame rate, at most 120, as an unmodified PC runs a LAN race. Exact: the frame-rate fixes stay on.") {
                Picker("", selection: $model.lanTiming) {
                    Text("As on a PC (original)").tag("pc")
                    Text("Exact").tag("exact")
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}
