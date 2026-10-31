// Discord status picture: the large image of the Rich Presence (engine:
// runtime/discord.c, NFSU2_DISCORD_LARGE_IMAGE).  Empty: none, Discord shows
// the application's own icon.  The row is on the Game tab, under "Show in
// Discord", and only does something while that switch is on.
import SwiftUI

enum DiscordImage {
    /// What the engine accepts: an https:// image URL, or an asset key of the
    /// player's own Discord application; printable ASCII, under 300 bytes
    /// (runtime/discord.c refuses anything else).  Empty is valid (no image).
    static func valid(_ text: String) -> Bool {
        if text.isEmpty { return true }
        guard text.utf8.count < 300, text.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return false }
        if text.lowercased().hasPrefix("https://") {
            guard let c = URLComponents(string: text), c.scheme?.lowercased() == "https",
                  let host = c.host, !host.isEmpty, c.user == nil, c.password == nil else { return false }
            return true
        }
        // an asset key: what Discord's developer portal allows in a name
        return text.utf8.count <= 64 && text.utf8.allSatisfy {
            (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 || $0 == 46
        }
    }
}

struct DiscordImageRow: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow(title: "Discord picture",
                       description: "An https:// image link, or an image key of your own Discord app. Empty: Discord's icon for the game.") {
                TextField("https://...", text: $model.discordImage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 190)
            }
            if !DiscordImage.valid(model.discordImage) {
                Text("Use an https:// link or a key of letters, numbers, _ - or . (no spaces).")
                    .font(.system(size: 11)).foregroundColor(Theme.accent)
            }
        }
        .disabled(!model.discord).opacity(model.discord ? 1 : 0.5)
    }
}
