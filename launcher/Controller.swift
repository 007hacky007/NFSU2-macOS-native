// The Controls tab's Controller card: the game pad options of runtime/gamepad.m and
// runtime/dinput_pad.c, passed to the engine in LauncherModel.play():
//   controller      NFSU2_PAD=1 / 0          padHotplug      NFSU2_PAD=hotplug
//   stickDeadzone   NFSU2_PAD_DEADZONE       triggerDeadzone NFSU2_PAD_TRIGGER_DEADZONE
//   triggerClick    NFSU2_PAD_TRIGGER_CLICK=0.97 / off
//   padMenuKeys     NFSU2_PAD_FE_KEYS=1 / 0  padBackground   NFSU2_PAD_BACKGROUND=1 / 0
import SwiftUI

struct ControllerCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Controller") {
            SettingRow(title: "Use a game controller",
                       description: "Xbox, PlayStation or MFi. Buttons are set in the game's Controls menu, and kept between sessions.",
                       isOn: $model.controller)
            Group {
                SettingRow(title: "When it is unplugged",
                           description: "Kept: the game keeps it, centred, until it is back, with its bindings. Removed: the game lets it go, as on a PC, and finds it again when it is plugged back in.") {
                    Picker("", selection: $model.padHotplug) {
                        Text("Kept").tag(false)
                        Text("Removed (original)").tag(true)
                    }
                    .labelsHidden().fixedSize()
                }
                DeadZoneRow(title: "Stick dead zone", value: $model.stickDeadzone)
                DeadZoneRow(title: "Trigger dead zone", value: $model.triggerDeadzone)
                SettingRow(title: "Trigger buttons at full pull",
                           description: "A trigger pulled all the way also presses a button you can bind, as a PlayStation pad's does on a PC. Off: as in the original game.",
                           isOn: $model.triggerClick)
                SettingRow(title: "Pad buttons as menu keys",
                           description: "A, B and View also work as Enter, Escape and Q in the menus, so the profile name and the quit prompt take the pad. Off: as in the original game.",
                           isOn: $model.padMenuKeys)
                SettingRow(title: "Read it in the background",
                           description: "The controller still drives the game while another app is in front. Off: as in the original game.",
                           isOn: $model.padBackground)
            }
            .disabled(!model.controller).opacity(model.controller ? 1 : 0.5)
        }
    }
}

/// A dead zone, 0 to 50 % of the travel.
private struct DeadZoneRow: View {
    let title: String
    @Binding var value: Double
    var body: some View {
        SettingRow(title: title, description: "How far it moves before it counts. 0 %: as in the original game.") {
            HStack(spacing: 8) {
                Slider(value: $value, in: 0...0.5, step: 0.01).frame(width: 150)
                Text("\(Int((value * 100).rounded())) %")
                    .font(.system(size: 11.5).monospacedDigit()).foregroundColor(Theme.dim)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
