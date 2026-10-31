// How many play on the server now, before joining: the server's /players
// (th0mk's nfsu2-web server: the players, those in Online mode and in free
// roam, whether it is full and how many wait for a place; with a free-roam
// room or crews, how many are in each).  Asked only when Check Player Counts
// is pressed: the launcher makes no request of its own.  The address follows
// the server's (wss://host/lan -> https://host/players) until set by hand.
import SwiftUI

struct PlayerCounts: Decodable {
    let players: Int
    let online: Int?
    let roam: Int?
    let full: Bool?
    let queue: Int?
    let roamBusy: Bool?
    let room: Int?
    let crews: [Int]?

    /// The counts' address for a server address: the same host, https (http
    /// for a ws:// server on this Mac), /players; "" for no valid server.
    static func address(for server: String) -> String {
        guard OnlineSettings.validServer(server), var c = URLComponents(string: server) else { return "" }
        c.scheme = c.scheme == "wss" ? "https" : "http"
        c.path = "/players"; c.query = nil; c.fragment = nil
        return c.string ?? ""
    }
    /// https://, or http:// to this Mac only; with ?room= and ?crews= (the
    /// engine's hashes of the free-roam settings) when there are any.
    static func endpoint(_ text: String, room: String, crews: String) -> URL? {
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }),
              var c = URLComponents(string: text), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.fragment == nil,
              c.port == nil || (1...65535).contains(c.port!),
              c.scheme == "https" || (c.scheme == "http" && OnlineSettings.isLoopback(host)) else { return nil }
        var q = c.queryItems ?? []
        let r = OnlineSettings.roomHash(room)
        if r != 0 { q.append(URLQueryItem(name: "room", value: String(r))) }
        let h = crews.split(separator: ",").map { OnlineSettings.roomHash(String($0)) }.filter { $0 != 0 }.prefix(4)
        if !h.isEmpty { q.append(URLQueryItem(name: "crews", value: h.map(String.init).joined(separator: ","))) }
        c.queryItems = q.isEmpty ? nil : q
        return c.url
    }

    var valid: Bool { ([players] + [online, roam, queue, room].compactMap { $0 } + (crews ?? [])).allSatisfy { $0 >= 0 } }
    /// One line for the player; room and crews: the settings asked about.
    func summary(room: String, crews: [String]) -> String {
        if players == 0 { return "On this server now: nobody is playing." }
        var parts = ["\(players) player\(players == 1 ? "" : "s")"]
        if let o = online { parts.append("\(o) in Online mode") }
        if let r = roam { parts.append("\(r) in free roam") }
        var line = "On this server now: " + parts.joined(separator: ", ") + "."
        if let n = self.room, !room.isEmpty { line += " Room \"\(room)\": \(n) in free roam." }
        if let c = self.crews, !c.isEmpty {
            line += " Crews: " + zip(crews, c).map { "\($0.0) \($0.1)" }.joined(separator: ", ") + "."
        }
        if full == true {
            let q = queue ?? 0
            line += q > 0 ? " The server is full; \(q) waiting for a place." : " The server is full."
        }
        if roamBusy == true { line += " Free roam is busy: fewer cars shown." }
        return line
    }
}

/// Redirects are not followed: the counts come from the address shown.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class PlayerCountsCheck: ObservableObject {
    @Published var loading = false
    @Published var result: String? = nil
    @Published var error: String? = nil
    private var generation = 0
    private var task: URLSessionDataTask?

    func clear() {
        generation += 1
        task?.cancel(); task = nil
        loading = false; result = nil; error = nil
    }

    func check(_ address: String, room: String, crews: String) {
        clear()
        guard let url = PlayerCounts.endpoint(address, room: room, crews: crews) else {
            error = "Use an https:// address for the player counts (http:// only for a server on this Mac)."
            return
        }
        let names = crews.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let roomName = room.trimmingCharacters(in: .whitespaces)
        loading = true
        let mine = generation
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        task = session.dataTask(with: url) { data, response, err in
            var line: String?, failure: String?
            if let err = err { failure = err.localizedDescription }
            else if let r = response as? HTTPURLResponse, r.statusCode == 200, let d = data, d.count <= 64_000,
                    let c = try? JSONDecoder().decode(PlayerCounts.self, from: d), c.valid {
                line = c.summary(room: roomName, crews: names)
            } else { failure = "The server did not answer with player counts." }
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async {
                guard self.generation == mine else { return }
                self.loading = false; self.task = nil
                self.result = line; self.error = failure
            }
        }
        task?.resume()
    }
}

/// The Player counts row of the Multiplayer card.
struct PlayerCountsRow: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var counts: PlayerCountsCheck
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Player counts").font(.system(size: 12.5)).foregroundColor(Theme.text).frame(width: 84, alignment: .leading)
                TextField("https://server/players", text: $model.countsURL).textFieldStyle(RoundedBorderTextFieldStyle())
                Button(counts.loading ? "Checking…" : "Check Player Counts") {
                    counts.check(model.countsURL, room: model.freeRoam == .off ? "" : model.roamRoom,
                                 crews: model.freeRoam == .off ? "" : model.roamCrew)
                }
                .buttonStyle(SecondaryButtonStyle()).disabled(counts.loading)
            }
            Text("How many play on the server now, and in your room and crews. Asked only when you press the button.")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if let r = counts.result {
                Text(r).font(.system(size: 11)).foregroundColor(Theme.accent).fixedSize(horizontal: false, vertical: true)
            }
            if let e = counts.error {
                Text(e).font(.system(size: 11)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
