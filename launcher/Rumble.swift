// The Controls tab's Rumble card: the game's force-feedback effects on the
// controller's motors (runtime/dinput_ff.c, runtime/rumble.m), passed to the
// engine in LauncherModel.play():
//   rumble          NFSU2_FF=1 / 0
//   rumbleCrashes   NFSU2_FF_JOLT=1 / 0
//   rumbleStrength  NFSU2_FF_STRENGTH=<percent>
// On a PC the game plays its effects on a force-feedback pad; on a pad without
// force feedback (an Xbox pad there) it plays none.  Off is that: no rumble.
import SwiftUI

struct RumbleCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Rumble") {
            SettingRow(title: "Rumble",
                       description: "The controller vibrates with the game's own force-feedback effects, as a force-feedback pad does on a PC: a light rumble from the road and the engine while you drive. Needs a controller with motors (Xbox, DualShock 4, DualSense). Off: as in the original game on a pad without force feedback.",
                       isOn: $model.rumble)
            Group {
                SettingRow(title: "Rumble on crashes",
                           description: "Also a jolt on hits, crashes and hard landings, as the console versions do. Off: as in the original game.",
                           isOn: $model.rumbleCrashes)
                SettingRow(title: "Rumble strength", description: "100 %: as strong as the game asks for.") {
                    HStack(spacing: 8) {
                        Slider(value: $model.rumbleStrength, in: 0.1...1, step: 0.05).frame(width: 150)
                        Text("\(Int((model.rumbleStrength * 100).rounded())) %")
                            .font(.system(size: 11.5).monospacedDigit()).foregroundColor(Theme.dim)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .disabled(!model.rumble).opacity(model.rumble ? 1 : 0.5)
        }
        .disabled(!model.controller).opacity(model.controller ? 1 : 0.5)
    }
}

extension LauncherModel {
    static let rumbleEnv = ["NFSU2_FF", "NFSU2_FF_JOLT", "NFSU2_FF_STRENGTH"]
    /// play(): our rumble variables, unless one was set by hand.  Ours are
    /// overwritten on every Play, so a change takes effect without restarting.
    func setRumbleEnv(_ env: [String: String]) {
        guard setRumble || LauncherModel.rumbleEnv.allSatisfy({ env[$0] == nil }) else { return }
        setenv("NFSU2_FF", controller && rumble ? "1" : "0", 1)
        setenv("NFSU2_FF_JOLT", rumbleCrashes ? "1" : "0", 1)
        setenv("NFSU2_FF_STRENGTH", String(Int((rumbleStrength * 100).rounded())), 1)
        setRumble = true
    }
}
