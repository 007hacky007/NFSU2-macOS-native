// Quick chat with other players, in free roam and in races between players: the
// launcher's switch and the editor of its four groups (the engine's
// runtime/native_controls.m, roam_game.c and racehorn.c do the rest).
import SwiftUI

enum QuickChat {
    /* th0mk's nfsu2-web's phrases (web/src/app/phrases.ts, MIT), in its order:
     * a phrase's number is what goes on the wire, so this list (and the same
     * one in runtime/native_controls.m) is only ever added to at the end */
    static let phrases: [String] = [
        "Hey!", "Nice car!", "Thanks!", "Bye!",
        "Yes", "No", "Sorry!", "lol",
        "Follow me!", "Wait up!", "Let's go!", "Nice!",
        "Race?", "Join my race!", "gg", "One more?",
        "Yo!", "Hi all!", "Welcome!", "Welcome back!",
        "Long time no see!", "Good luck!", "Have fun!", "Gotta go!",
        "See you around!", "Good night!", "brb", "Back!",
        "Sure!", "Maybe", "Okay", "Nope",
        "One sec", "On my way!", "Can't right now", "Same",
        "True", "What?", "Where?", "Here!",
        "haha", "ty", "np", "No worries!",
        "My bad!", "All good!", "Didn't see you!", "Lag, sorry!",
        "Thanks for waiting!", "Thanks for the race!", "Clean build!", "Love the vinyl!",
        "Love the colour!", "Sick rims!", "Nice kit!", "Sleeper!",
        "What's under the hood?", "Nice drift!", "Nice line!", "Smooth!",
        "Nice save!", "Great driving!", "You're fast!", "Respect.",
        "Nice driving!", "What a save!", "Let's cruise!", "Convoy!",
        "Lead the way!", "I'll lead!", "This way!", "Turn around!",
        "Slow down!", "Speed up!", "Shortcut here!", "Jump here!",
        "Watch out!", "Traffic!", "Behind you!", "Lost you!",
        "Where are you?", "Check the map!", "Pull over!", "Send it!",
        "Car meet?", "Meet here!", "Park up!", "Line up!",
        "Photo time!", "Hold still!", "Show your build!", "Going to the shop",
        "Going to the garage", "Join my crew?", "Meet at City Core?", "Meet at Beacon Hill?",
        "Meet at Jackson Heights?", "Meet at Coal Harbor?", "Meet at the airport?", "Outrun?",
        "Sprint?", "Circuit?", "Drag race?", "Drift battle?",
        "Street X?", "You're on!", "Ready?", "Ready!",
        "Not ready!", "Wait for everyone!", "Close one!", "So close!",
        "Good race!", "Run it back?", "Best of three?", "You got me!",
        "Too fast for me!", "I'm out", "Wow!", "Whoa!",
        "No way!", "Yes!", "Let's gooo!", "Nooo!",
        "Oops!", "Ouch!", "Oof", "Yikes!",
        "Whew!", "omg", "What a jump!", "Huge air!",
        "Clean!", "Unreal!", "Calculated.", "Classic.",
        "Did you see that?", "W", "Let him cook", "I'm cooked",
        "skill issue", "ratio", "I'm stuck!", "Help?",
        "Lag!", "AFK a sec", "Out of nitrous", "Tuning tips?",
        "Which car is that?", "New here!", "First time?", "On my phone!",
    ]
    static let defaultGroups = ["Greetings", "Replies", "Driving", "Racing"]
    static let defaultPhrases = Array(0..<16)

    /* a group's name: 1-24 printable ASCII characters, no comma (the engine's
     * list is comma-separated) */
    static func validGroup(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return (1...24).contains(t.utf8.count) && t.utf8.allSatisfy { (32...126).contains($0) && $0 != 44 }
    }
    static func groups(_ saved: [String]?) -> [String] {
        guard let g = saved, g.count == 4, g.allSatisfy(validGroup) else { return defaultGroups }
        return g.map { $0.trimmingCharacters(in: .whitespaces) }
    }
    static func phraseIDs(_ saved: [Int]?) -> [Int] {
        guard let p = saved, p.count == 16, p.allSatisfy({ (0..<phrases.count).contains($0) }) else { return defaultPhrases }
        return p
    }
}

/// The groups being edited (kept by the model: the editor is made again with
/// every redraw of the window).
final class QuickChatDraft: ObservableObject {
    @Published var names = QuickChat.defaultGroups
    @Published var ids = QuickChat.defaultPhrases
}

extension LauncherModel {
    func editQuickChat() {
        quickChatDraft.names = quickChatGroups; quickChatDraft.ids = quickChatPhrases
        editingQuickChat = true
    }
}

/// The Quick chat row of the Multiplayer card.
struct QuickChatRow: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Quick chat").font(.system(size: 12.5)).foregroundColor(Theme.text)
                Text("Press 1-4 twice, or flick the right stick twice, to say a phrase: over your car in free roam, and in a chat on the left in races with other players. Game Tools in the game: Cmd+Shift+M. Off: as in the original game.")
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Quick chat groups…") { model.editQuickChat() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.quickChat)
            Toggle("", isOn: $model.quickChat).labelsHidden().toggleStyle(SwitchToggleStyle())
        }
    }
}

/// The groups: four names, each with four phrases, over the Settings window
/// (as a job's progress is).  The engine's Game Tools panel changes the same
/// groups while the game runs.
struct QuickChatEditor: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var draft: QuickChatDraft

    private func phrasePicker(_ slot: Int) -> some View {
        Picker("", selection: Binding(get: { draft.ids[slot] }, set: { draft.ids[slot] = $0 })) {
            ForEach(0..<QuickChat.phrases.count, id: \.self) { k in Text("\(k + 1). \(QuickChat.phrases[k])").tag(k) }
        }
        .labelsHidden().frame(width: 172)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick chat groups").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                Text("While driving in free roam, 1-4 opens a group and 1-4 again says its phrase. On a controller flick the right stick: up, right, down, left.")
                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(0..<4, id: \.self) { g in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("\(g + 1)").font(.system(size: 12.5, weight: .semibold)).foregroundColor(Theme.text).frame(width: 12)
                            TextField("Group name", text: Binding(get: { draft.names[g] }, set: { draft.names[g] = $0 }))
                                .textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 110)
                            phrasePicker(g * 4); phrasePicker(g * 4 + 1)
                        }
                        HStack(spacing: 6) {
                            Spacer().frame(width: 128)
                            phrasePicker(g * 4 + 2); phrasePicker(g * 4 + 3)
                        }
                    }
                }
                if !draft.names.allSatisfy(QuickChat.validGroup) {
                    Text("A group's name: 1-24 letters, numbers or signs, no comma.").font(.system(size: 11)).foregroundColor(.orange)
                }
                HStack {
                    Button("Defaults") { draft.names = QuickChat.defaultGroups; draft.ids = QuickChat.defaultPhrases }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Cancel") { model.editingQuickChat = false }.buttonStyle(SecondaryButtonStyle())
                    Button("Save") {
                        model.quickChatGroups = draft.names.map { $0.trimmingCharacters(in: .whitespaces) }
                        model.quickChatPhrases = draft.ids
                        model.editingQuickChat = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!draft.names.allSatisfy(QuickChat.validGroup))
                }
            }
            .padding(16)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.11, green: 0.115, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        }
    }
}
