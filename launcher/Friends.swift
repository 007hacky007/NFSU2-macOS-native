// Free roam's friends in the launcher (ported from th0mk's nfsu2-web
// web/src/app/friends.ts FriendsApi and FriendsPanel, MIT).  The server keeps the
// friends lists (EA Messenger's, for claimed names only) and checks everything; the
// launcher shows them under Settings > Online > Friends:
//   list   GET /friends with the keyphrase's token (Bearer, as /names takes it): the
//          player's claimed name, its friends and where each one plays (free roam
//          and its room, the Online lobby, offline), the requests that wait for its
//          answer, its own that wait, and the friends' messages that waited (gone
//          from the server once read: shown here so none is lost).
//   act    POST /friends {"op": accept | decline | remove | ask, "name"}: answer a
//          request, remove a friend or take a request back, ask a player by name.
// The token is the one NameClaims.swift remembers, and goes only to the server it
// was remembered for (NameClaimModel.claimToken); never to another origin, never
// into the environment.  Nothing is asked before the player opens the list
// (Refresh), and then once a minute while Settings shows it.
// In the game (runtime/native_controls.m) two cars touching front bumpers for
// 3 s offer a request, and friends are marked in free roam; NFSU2_ROAM_FRIENDS=0
// (the switch below off) turns that off.
import AppKit
import SwiftUI

/// A friend as the server places it: where it plays ("roam" free roam, "online" the Online lobby, "" neither) and
/// its room's name in free roam ("" everyone's; nil: not in free roam, or its game did not say).
struct Friend: Equatable {
    let name: String
    let place: String
    let room: String?
}
struct FriendMail: Equatable {
    let from: String
    let body: String
}
/// The server's lists (nil me: no claimed name, so no friends); done: what the last change did.
struct FriendLists: Equatable {
    var me: String?
    var friends: [Friend] = []
    var asks: [String] = []
    var sent: [String] = []
    var mail: [FriendMail] = []
    var done: String?
}

enum FriendsAPI {
    /// /friends on the server's own address (https; http for a ws:// server on this Mac); nil: no valid server.
    static func endpoint(for server: String) -> URL? {
        guard OnlineSettings.validServer(server), var c = URLComponents(string: server) else { return nil }
        c.scheme = c.scheme == "wss" ? "https" : "http"
        c.path = "/friends"; c.query = nil; c.fragment = nil
        return c.url
    }
    /// An answer read leniently (friends.ts friendsOf): what is not of the right kind is left out.
    static func parse(_ data: Data) -> FriendLists? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func names(_ v: Any?) -> [String] { ((v as? [Any]) ?? []).compactMap { $0 as? String }.filter { $0.count <= 64 } }
        var l = FriendLists()
        l.me = j["me"] as? String
        l.friends = ((j["friends"] as? [Any]) ?? []).compactMap { f in
            guard let d = f as? [String: Any], let n = d["name"] as? String, n.count <= 64 else { return nil }
            let w = d["where"] as? String
            return Friend(name: n, place: w == "roam" || w == "online" ? w! : "", room: d["room"] as? String)
        }
        l.asks = names(j["asks"]); l.sent = names(j["sent"])
        l.mail = ((j["mail"] as? [Any]) ?? []).compactMap { m in
            guard let d = m as? [String: Any], let f = d["from"] as? String, let b = d["body"] as? String else { return nil }
            return FriendMail(from: f, body: String(b.prefix(500)))
        }
        l.done = j["done"] as? String
        return l
    }
    enum Failure: Error, Equatable { case keyphrase, none, http(Int), unreadable }
    /// The lists (op nil: GET), or the lists after a change (POST).
    static func call(_ url: URL, token: String, op: String? = nil, name: String = "") throws -> FriendLists {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.httpShouldHandleCookies = false
        r.setValue("NFSU2-Launcher", forHTTPHeaderField: "User-Agent")
        r.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let op = op {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["op": op, "name": String(name.prefix(64))])
        }
        let (response, data) = try VaultRequest(limit: 256 << 10).run(r)
        switch response.statusCode {
        case 200: guard let l = parse(data) else { throw Failure.unreadable }; return l
        case 401: throw Failure.keyphrase
        case 404: throw Failure.none
        default: throw Failure.http(response.statusCode)
        }
    }
    /// What a done means, as the player reads it.
    static func doneText(_ done: String?, name: String) -> (String, Bool) {
        switch done ?? "" {
        case "asked": return ("Friend request sent to \(name).", false)
        case "friends": return ("You and \(name) are friends.", false)
        case "claim": return ("\(name) has no claimed name, so can't add friends yet.", true)
        case "self": return ("That's your own name.", true)
        case "name": return ("Not a player's name.", true)
        case "full": return ("A friends list is full (50 at most).", true)
        case "rate": return ("Wait a moment.", true)
        case "": return ("Not sent: try again in a moment.", true)
        default: return ("Done.", false)
        }
    }
    /// Where a friend plays, after its name.
    static func placeText(_ f: Friend) -> String {
        if f.place == "roam" {
            guard let r = f.room else { return "free roam" }
            return r.isEmpty ? "free roam, no room" : "free roam, room \(r)"
        }
        return f.place == "online" ? "Online lobby" : "offline"
    }
}

/// The Friends card's state: asked only while Settings shows it.
final class FriendsModel: ObservableObject {
    @Published private(set) var lists: FriendLists?
    @Published private(set) var busy = false
    @Published var note: (text: String, bad: Bool)?
    /// the messages that waited, read from the server (gone there): kept for this run of the launcher
    @Published private(set) var mail: [FriendMail] = []
    private var asked = 0
    private var timer: Timer?

    func refresh(server: String, token: String?) {
        guard let url = FriendsAPI.endpoint(for: server), let t = token else { lists = nil; return }
        run(url: url, token: t, op: nil, name: "")
    }
    func act(_ op: String, name: String, server: String, token: String?) {
        guard let url = FriendsAPI.endpoint(for: server), let t = token, !name.isEmpty else { return }
        run(url: url, token: t, op: op, name: name)
    }
    private func run(url: URL, token: String, op: String?, name: String) {
        asked += 1; let mine = asked
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try FriendsAPI.call(url, token: token, op: op, name: name) }
            DispatchQueue.main.async {
                guard mine == self.asked else { return }
                self.busy = false
                switch r {
                case .success(let l):
                    self.lists = l; self.mail += l.mail
                    if op == "ask" {
                        let shown = (l.sent + l.friends.map(\.name)).first { $0.lowercased() == name.lowercased() } ?? name
                        let (text, bad) = FriendsAPI.doneText(l.done, name: shown); self.note = (text, bad)
                    } else if op != nil { self.note = nil }
                case .failure(FriendsAPI.Failure.keyphrase): self.lists = nil; self.note = ("The server does not know your keyphrase: claim your name above.", true)
                case .failure(FriendsAPI.Failure.none): self.lists = nil; self.note = ("This server keeps no friends lists.", true)
                case .failure(let e): self.note = ((e as? FriendsAPI.Failure).map { _ in "The server did not answer. Try again later." } ?? e.localizedDescription, true)
                }
            }
        }
    }
    /// once a minute while the card shows
    func start(_ tick: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in tick() }
    }
    func stop() { timer?.invalidate(); timer = nil }
}

/// Settings > Online: Friends.
struct FriendsCard: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var friends: FriendsModel
    @State private var typed = ""
    private var token: String? { model.names.claimToken(server: model.server) }
    var body: some View {
        Card("Friends") {
            SettingRow(title: "Friends in free roam",
                       description: "Touch front bumpers with another player for 3 s and press F to ask them; friends' names and arrows show in a pale lime at any distance, and Game Tools says when one is in free roam. Both of you need a claimed name. Off: as in the original game.",
                       isOn: $model.roamFriends)
                .disabled(!model.online || model.freeRoam == .off).opacity(model.online && model.freeRoam != .off ? 1 : 0.5)
            if !model.online {
                Text("Turn on Play online to see your friends.").font(.system(size: 11)).foregroundColor(Theme.dim)
            } else if token == nil {
                Text("Claim your name (Player name, above) to add friends.").font(.system(size: 11)).foregroundColor(Theme.dim)
            } else {
                list
            }
        }
        .onAppear { if model.online && token != nil { refresh(); friends.start { refresh() } } }
        .onDisappear { friends.stop() }
    }
    private func refresh() { friends.refresh(server: model.server, token: token) }
    private func act(_ op: String, _ name: String) { friends.act(op, name: name, server: model.server, token: token) }
    private func row(_ name: String, _ state: String, dim: Bool = false, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 12.5)).foregroundColor(dim ? Theme.dim : Theme.text)
            Text(state).font(.system(size: 11)).foregroundColor(Theme.dim)
            Spacer(minLength: 8)
            actions()
        }
    }
    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let l = friends.lists {
                if l.me == nil {
                    Text("Claim your name (Player name, above) to add friends.").font(.system(size: 11)).foregroundColor(Theme.dim)
                } else {
                    ForEach(l.asks, id: \.self) { n in
                        row(n, "wants to be friends") {
                            Button("Accept") { act("accept", n) }
                            Button("Decline") { act("decline", n) }
                        }
                    }
                    ForEach(l.friends.sorted { order($0) < order($1) }, id: \.name) { f in
                        row(f.name, FriendsAPI.placeText(f), dim: f.place.isEmpty) {
                            if f.place == "roam", let r = f.room {
                                Button("Join") { join(r) }
                            }
                            Button("Remove") { if confirm(f.name) { act("remove", f.name) } }
                        }
                    }
                    ForEach(l.sent, id: \.self) { n in
                        row(n, "request sent", dim: true) { Button("Take back") { act("remove", n) } }
                    }
                    if l.friends.isEmpty && l.asks.isEmpty && l.sent.isEmpty {
                        Text("No friends yet: touch front bumpers in free roam for 3 s, or ask a player by name.").font(.system(size: 11)).foregroundColor(Theme.dim)
                    }
                }
            }
            ForEach(Array(friends.mail.enumerated()), id: \.offset) { _, m in
                Text("Message from \(m.from): \(m.body)").font(.system(size: 11)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField("Add a player by name", text: $typed).textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Ask") { let n = typed.trimmingCharacters(in: .whitespaces); act("ask", n); typed = "" }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Refresh") { refresh() }
            }
            .disabled(friends.busy)
            if let n = friends.note {
                Text(n.text).font(.system(size: 11)).foregroundColor(n.bad ? .orange : Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func order(_ f: Friend) -> Int { f.place == "roam" ? 0 : f.place == "online" ? 1 : 2 }
    private func join(_ room: String) {
        model.roamRoom = room
        if model.freeRoam == .off { model.freeRoam = .solid }
        let text = (room.isEmpty ? "Room: everyone. " : "Room: \(room). ") + "A game already running changes room in Game Tools (Cmd+Shift+M)."
        friends.note = (text, false)
    }
    private func confirm(_ name: String) -> Bool {
        let a = NSAlert()
        a.messageText = "Remove \(name)?"
        a.informativeText = "You are friends no more, on both lists."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}
