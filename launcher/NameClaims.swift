// Claimed names (th0mk's nfsu2-web server, /names; ported from its web/src/app/
// claim.ts and claim-ui.ts, MIT).  A player claims the name it plays under with its
// keyphrase, the one that keeps its cloud saves (VaultCrypto.swift), and while the
// claim holds the server keeps the name for it: anyone else playing under that name
// gets no links in free roam, shows on no map and gets another name in the Online
// lobby.
//   check  GET /names?name=...&alt=... (the token as a Bearer when a keyphrase is
//          remembered): free, yours, old, taken, default, blocked or invalid.  Asked
//          while Settings shows the name (Play online on) and before Play; nothing
//          else is asked.
//   claim  POST /names {"name","captcha"} with the token.  The server takes a claim
//          only from a keyphrase with cloud saves: asked first, the careers are sent
//          once (encrypted here, VaultAPI), then the claim.  Cloudflare Turnstile's
//          check (a WKWebView on the server's address) only when the server asks.
//   play   the token goes to the game through a pipe (NFSU2_CLAIM_FD), never the
//          environment or the command line; the game's hello to the server names
//          it ("claim", runtime/net_native.m), so the claimed name is its own there.
// The keyphrase is the cloud saves' Keychain link (VaultKeychain): one keyphrase
// holds the name and the saves, as in the browser.
import AppKit
import CryptoKit
import SwiftUI
import WebKit

enum NameState: String, Decodable { case free, yours, old, taken, `default`, blocked, invalid }

struct NameMine: Decodable, Equatable {
    let name: String
    let until: Double
    let next: Double
}
struct NameAlt: Decodable, Equatable {
    let name: String?
    let state: NameState
}
/// What a name is to this player (GET /names).
struct NameInfo: Decodable, Equatable {
    let name: String?
    let state: NameState
    let until: Double?
    let alt: NameAlt?
    let mine: NameMine?
    /// Cloudflare Turnstile's site key: a claim needs its check
    let captcha: String?
}
enum NameClaimResult: Equatable {
    case claimed(NameMine)
    /// the server's reason ("taken", "soon", "keyphrase", ...), and for "soon" when the next change may be
    case refused(String, next: Double?)
}

enum NameClaims {
    /// The Online form of a name (runtime/online.c clean(), the server's nfsu2-claims clean()): letters, digits,
    /// - and _, any other run of characters one _ (none at either end), cut to 15; padded with _ to 3.  nil: none.
    static func onlineName(_ s: String) -> String? {
        var out = "", gap = false
        for ch in s {
            if out.count >= 15 { break }
            guard ch.isASCII, ch.isLetter || ch.isNumber || ch == "_" || ch == "-" else { gap = true; continue }
            if gap && !out.isEmpty && out.count < 14 { out += "_" }
            gap = false
            out.append(ch)
        }
        if out.isEmpty { return nil }
        while out.count < 3 { out += "_" }
        return out
    }
    /// The name with four digits in place of its end, the same ones for one seed (this Mac's) and name: what to
    /// play under when another player claimed the name.  "Player" with the digits when the shortened name reads as
    /// a slur (runtime/names.h, the server's lists).
    static func digits(for name: String, seed: String) -> String {
        let base = onlineName(name) ?? "Player"
        let h = Array(SHA256.hash(data: Data("\(seed)\n\(base.lowercased())".utf8)))
        let n = UInt32(h[0]) << 24 | UInt32(h[1]) << 16 | UInt32(h[2]) << 8 | UInt32(h[3])
        let d = String(n % 9000 + 1000)
        let cut = String(base.prefix(11)) + d
        return name_blocked(cut) != 0 ? "Player" + d : cut
    }
    /// The names' address for a server address: the same host, https (http for a ws:// server on this Mac),
    /// /names; nil for no valid server.
    static func endpoint(for server: String) -> URL? {
        guard OnlineSettings.validServer(server), var c = URLComponents(string: server) else { return nil }
        c.scheme = c.scheme == "wss" ? "https" : "http"
        c.path = "/names"; c.query = nil; c.fragment = nil
        return c.url
    }
    /// A token as the server takes it: 43 characters of base64url.
    static func validToken(_ t: String) -> Bool {
        t.utf8.count == 43 && t.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    private static func request(_ url: URL, method: String, token: String?, body: Data? = nil) throws -> (HTTPURLResponse, Data) {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.httpMethod = method; r.httpBody = body; r.httpShouldHandleCookies = false
        r.setValue("NFSU2-Launcher", forHTTPHeaderField: "User-Agent")
        r.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let t = token, validToken(t) { r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        return try VaultRequest(limit: 16 << 10).run(r)
    }
    /// What `name` (and `alt`) is to the keyphrase of `token` (none: to anyone); nil: a server without claims.
    static func check(_ endpoint: URL, name: String, alt: String?, token: String?) throws -> NameInfo? {
        guard var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw SaveError("Invalid name check address.") }
        c.queryItems = [URLQueryItem(name: "name", value: name)] + (alt.map { [URLQueryItem(name: "alt", value: $0)] } ?? [])
        guard let url = c.url else { throw SaveError("Invalid name check address.") }
        let (response, data) = try request(url, method: "GET", token: token)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw SaveError("The server did not answer the name check (HTTP \(response.statusCode)).") }
        do { return try JSONDecoder().decode(NameInfo.self, from: data) }
        catch { throw SaveError("The server's name check answer could not be read.") }
    }
    /// The keyphrase of `token` claims `name`, with Turnstile's answer when the server asks for its check.
    static func claim(_ endpoint: URL, name: String, captcha: String?, token: String) throws -> NameClaimResult {
        var body: [String: String] = ["name": name]
        if let c = captcha { body["captcha"] = c }
        let (response, data) = try request(endpoint, method: "POST", token: token, body: try JSONSerialization.data(withJSONObject: body))
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if response.statusCode == 200, let m = j["mine"] as? [String: Any], let n = m["name"] as? String,
           let until = m["until"] as? Double, let next = m["next"] as? Double {
            return .claimed(NameMine(name: n, until: until, next: next))
        }
        if response.statusCode == 429 && j["error"] == nil { return .refused("busy", next: nil) }
        return .refused(j["error"] as? String ?? "net", next: j["next"] as? Double)
    }

    static func day(_ ms: Double) -> String {
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: ms / 1000), dateStyle: .medium, timeStyle: .none)
    }
    /// A refused claim, as the player reads it.
    static func refusal(_ error: String, next: Double?, name: String) -> String {
        switch error {
        case "taken": return "Another player claimed \(name) just now."
        case "soon": return "A keyphrase can change its name once a week." + (next.map { " The next change is possible on \(day($0))." } ?? "")
        case "busy": return "Too many claims from this network today. Try again tomorrow."
        case "default": return "\(name) is the game's default and can't be claimed. Pick your own."
        case "blocked": return "The server does not allow this name."
        case "invalid": return "This name can't be claimed."
        case "captcha": return "Cloudflare's check did not pass. Try again."
        case "captcha-down": return "Cloudflare's check is not answering. Try again later."
        case "keyphrase": return "The server has no cloud saves for this keyphrase."
        case "full": return "The server can't take more claims right now."
        default: return "The server did not take the claim. Try again later."
        }
    }
}

/// The name row under Settings, Online's Player name: the check, Claim, and the digits name to switch to.
final class NameClaimModel: ObservableObject {
    enum Tone { case info, good, bad }
    @Published private(set) var info: NameInfo?
    /// the name and server `info` is about
    @Published private(set) var about: (name: String, server: String)?
    @Published private(set) var busy = false
    @Published private(set) var note: (text: String, tone: Tone)?
    /// the server keeps no claims (it answered 404): no row
    @Published private(set) var noClaims = false
    private let defaults: UserDefaults
    private var pending: DispatchWorkItem?
    private var asked = 0
    private var checkedAt = Date.distantPast
    /// the remembered keyphrase's token, once made (nil: none remembered, or not looked for yet)
    private var token: String?
    private var tokenLooked = false
    /// "Play anyway" for a name another player claimed, this run of the launcher
    private var acknowledged = Set<String>()
    var keyphraseSource: () throws -> String? = { (try? VaultKeychain.recall())?.phrase }

    static let seedKey = "LauncherNameSeed"
    static let claimKey = "LauncherNameClaim"   // true: the game plays with the remembered keyphrase's claim
    init(defaults: UserDefaults) { self.defaults = defaults }

    /// this Mac's seed for the digits name (one random value, kept)
    var seed: String {
        if let s = defaults.string(forKey: Self.seedKey), !s.isEmpty { return s }
        let s = UUID().uuidString; defaults.set(s, forKey: Self.seedKey); return s
    }
    func digits(for name: String) -> String { NameClaims.digits(for: name, seed: seed) }
    var playsWithClaim: Bool { defaults.bool(forKey: Self.claimKey) }

    /// The remembered keyphrase's token (the Keychain link of cloud saves); nil: none.  Made once per launcher run.
    func claimToken() -> String? {
        if tokenLooked { return token }
        tokenLooked = true
        guard let phrase = try? keyphraseSource(), let keys = try? VaultCrypto.keys(phrase) else { return nil }
        token = keys.token; return token
    }
    func forgetToken() { token = nil; tokenLooked = false }

    /// The name as Settings shows it changed (or the row appeared): checked after a pause in typing.
    func schedule(name: String, server: String, online: Bool) {
        pending?.cancel()
        guard online, OnlineSettings.validName(name), NameClaims.endpoint(for: server) != nil else {
            asked += 1; info = nil; about = nil; note = nil; busy = false; return
        }
        if let a = about, a.name == name, a.server == server, Date().timeIntervalSince(checkedAt) < 60 { return }
        let w = DispatchWorkItem { [weak self] in self?.check(name: name, server: server) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
    }

    /// Ask the server now; `then` gets the answer (nil: none) on the main queue.
    func check(name: String, server: String, then: ((NameInfo?) -> Void)? = nil) {
        guard let url = NameClaims.endpoint(for: server), OnlineSettings.validName(name) else { then?(nil); return }
        asked += 1; let mine = asked
        busy = true; note = nil
        let alt = digits(for: name)
        DispatchQueue.global(qos: .userInitiated).async {
            let token = self.claimToken()
            let result = Result { try NameClaims.check(url, name: name, alt: alt, token: token) }
            DispatchQueue.main.async {
                guard mine == self.asked else { then?(nil); return }
                self.busy = false
                switch result {
                case .success(let info):
                    self.noClaims = info == nil
                    self.info = info; self.about = (name, server); self.checkedAt = Date()
                    if let i = info, i.state == .yours || i.state == .old, token != nil { self.defaults.set(true, forKey: Self.claimKey) }
                case .failure(let e):
                    self.info = nil; self.about = nil
                    self.note = (e.localizedDescription, .bad)
                }
                then?(self.info)
            }
        }
    }

    /// The row's text for the current answer.
    func line(for name: String) -> (text: String, tone: Tone)? {
        if let n = note { return n }
        guard let i = info, about?.name == name else { return busy ? ("Checking the name on the server...", .info) : nil }
        let alt = digits(for: name)
        switch i.state {
        case .yours:
            return ("Claimed with your keyphrase" + (i.until.map { " until \(NameClaims.day($0))" } ?? "") + ". Nobody else can play as \(name).", .good)
        case .old:
            return ("Your keyphrase's earlier name, still yours" + (i.until.map { " until \(NameClaims.day($0))" } ?? "") + (i.mine.map { ". It now holds \($0.name)." } ?? "."), .good)
        case .free:
            return ("Not claimed: anyone can play as \(name). Claim it to keep it; your keyphrase holds the name and your cloud saves.", .info)
        case .taken:
            return ("Another player claimed \(name). Under it, free roam shows you to nobody and the Online lobby renames you. Use \(alt), pick another name, or claim it here if the keyphrase is yours.", .bad)
        case .default:
            return ("\(name) is the game's default and can't be claimed. Pick your own, or use \(alt).", .bad)
        case .blocked:
            return ("The server does not allow this name. Pick another one.", .bad)
        case .invalid:
            return ("The server does not take this name. Use 3-15 letters, numbers, _ or -.", .bad)
        }
    }
    /// A name another player holds: Settings offers the digits, Play asks.
    func claimedByOther(_ name: String) -> Bool {
        guard let i = info, about?.name == name else { return false }
        return i.state == .taken || i.state == .default
    }
    func canClaim(_ name: String) -> Bool {
        guard let i = info, about?.name == name else { return false }
        return i.state == .free || i.state == .taken || i.state == .old
    }

    // MARK: Play

    enum Gate { case play, wait, cancel, rename(String) }
    /// Before Play: the name checked (a fresh answer is reused), and one another player claimed asked about.
    /// .wait: the check is under way and `retry` runs once it answered.
    func gate(name: String, server: String, retry: @escaping () -> Void) -> Gate {
        guard OnlineSettings.validName(name), NameClaims.endpoint(for: server) != nil, !noClaims else { return .play }
        if acknowledged.contains(name.lowercased()) { return .play }
        guard let a = about, a.name == name, a.server == server, Date().timeIntervalSince(checkedAt) < 60 else {
            check(name: name, server: server) { info in
                // no answer: play as before; an answer: back through the gate
                if info == nil { self.acknowledged.insert(name.lowercased()) }
                retry()
            }
            return .wait
        }
        guard claimedByOther(name) else { return .play }
        let alt = digits(for: name)
        let a2 = NSAlert()
        a2.messageText = info?.state == .default ? "\(name) is the game's default name" : "Another player claimed \(name)"
        a2.informativeText = "The server keeps this name for the player who claimed it. Under it, free roam shows you to nobody and the Online lobby gives you another name.\n\nPlay as \(alt) instead? Settings keeps the change."
        a2.addButton(withTitle: "Use \(alt)")
        a2.addButton(withTitle: "Play as \(name)")
        a2.addButton(withTitle: "Cancel")
        switch a2.runModal() {
        case .alertFirstButtonReturn: return .rename(alt)
        case .alertSecondButtonReturn: acknowledged.insert(name.lowercased()); return .play
        default: return .cancel
        }
    }

    // MARK: Claim

    /// Claim `name` with the remembered keyphrase (asked for, or made, when there is none): Turnstile when the
    /// server asks for it, the saves sent once when the cloud has none for the keyphrase (asked first).
    func claim(name: String, server: String) {
        guard let url = NameClaims.endpoint(for: server), OnlineSettings.validName(name), !busy else { return }
        var token = claimToken()
        if token == nil {
            guard let phrase = askKeyphrase(server: server) else { return }
            do { token = try VaultCrypto.keys(phrase).token; self.token = token; tokenLooked = true }
            catch { note = (error.localizedDescription, .bad); return }
        }
        guard let t = token else { return }
        busy = true; note = ("Claiming \(name)...", .info)
        DispatchQueue.global(qos: .userInitiated).async {
            let first = Result { try NameClaims.check(url, name: name, alt: nil, token: t) }
            DispatchQueue.main.async {
                guard case .success(let info?) = first else {
                    self.busy = false
                    if case .failure(let e) = first { self.note = (e.localizedDescription, .bad) } else { self.note = ("This server keeps no claimed names.", .bad) }
                    return
                }
                if info.state == .yours { self.done(name: name, server: server, text: "\(name) is already yours."); return }
                if [.taken, .default, .blocked, .invalid].contains(info.state) {
                    self.busy = false; self.note = (NameClaims.refusal(info.state == .taken ? "taken" : info.state.rawValue, next: nil, name: name), .bad); return
                }
                guard let key = info.captcha else {
                    self.post(url: url, name: name, server: server, token: t, captcha: nil, sentSaves: false); return
                }
                self.note = ("A quick check that you're human...", .info)
                TurnstileCheck.start(siteKey: key, page: url) { answer in
                    guard let answer = answer else {
                        self.busy = false; self.note = ("The claim needs Cloudflare's check, which did not finish.", .bad); return
                    }
                    self.post(url: url, name: name, server: server, token: t, captcha: answer, sentSaves: false)
                }
            }
        }
    }
    private func post(url: URL, name: String, server: String, token: String, captcha: String?, sentSaves: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try NameClaims.claim(url, name: name, captcha: captcha, token: token) }
            DispatchQueue.main.async {
                switch r {
                case .failure(let e): self.busy = false; self.note = (e.localizedDescription, .bad)
                case .success(.claimed(let mine)): self.done(name: name, server: server, text: "\(mine.name) is yours. Your keyphrase keeps it.")
                case .success(.refused("keyphrase", _)) where !sentSaves:
                    guard self.confirmSend(name: name) else { self.busy = false; self.note = ("Not claimed. The server takes a claim only from a keyphrase with cloud saves.", .info); return }
                    self.note = ("Sending your saves...", .info)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let sent = Result { try self.sendSaves(server: server) }
                        DispatchQueue.main.async {
                            if case .failure(let e) = sent { self.busy = false; self.note = (e.localizedDescription, .bad); return }
                            self.post(url: url, name: name, server: server, token: token, captcha: captcha, sentSaves: true)
                        }
                    }
                case .success(.refused(let e, let next)): self.busy = false; self.note = (NameClaims.refusal(e, next: next, name: name), .bad)
                }
            }
        }
    }
    private func done(name: String, server: String, text: String) {
        busy = false; defaults.set(true, forKey: Self.claimKey)
        about = nil
        check(name: name, server: server) { _ in self.note = (text, .good) }
    }
    /// The careers, encrypted on this Mac, as the cloud's first version for the keyphrase (VaultModel's send).
    private func sendSaves(server: String) throws {
        guard let phrase = try keyphraseSource() else { throw SaveError("No keyphrase is remembered.") }
        let keys = try VaultCrypto.keys(phrase)
        let api = VaultAPI(endpoint: try VaultAPI.endpoint(VaultAPI.defaultEndpoint(server: server)), token: keys.token)
        let entries = VaultPayload.filtered(try SaveStore(saves: Paths.saves, registry: Paths.registry).snapshot())
        _ = try api.put(VaultCrypto.pack(entries, keys: keys), revision: nil)
    }
    private func confirmSend(name: String) -> Bool {
        let a = NSAlert()
        a.messageText = "Send your saves to the cloud to claim \(name)?"
        a.informativeText = "The server takes a claim only from a keyphrase that has cloud saves. This sends this Mac's careers once, encrypted here with your keyphrase (the server can't read them), then claims the name. The Saves window's Cloud saves section uses the same keyphrase."
        a.addButton(withTitle: "Send and claim"); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// The keyphrase to claim with: one typed in (the cloud saves' eight words) or a new one, remembered in Keychain
    /// so every Play can name the claim.  nil: cancelled.
    private func askKeyphrase(server: String) -> String? {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "Eight-word keyphrase"
        while true {
            let a = NSAlert()
            a.messageText = "Claim with a keyphrase"
            a.informativeText = "The keyphrase holds your name and your cloud saves, the same eight words as in the browser game. It is remembered in Keychain so the game can show the server the name is yours. Enter yours, or make a new one."
            a.accessoryView = field
            a.addButton(withTitle: "Use this keyphrase"); a.addButton(withTitle: "New keyphrase"); a.addButton(withTitle: "Cancel")
            a.window.initialFirstResponder = field
            switch a.runModal() {
            case .alertFirstButtonReturn:
                do {
                    let phrase = try VaultCrypto.normalize(field.stringValue)
                    try VaultKeychain.remember(phrase: phrase, endpoint: VaultAPI.defaultEndpoint(server: server))
                    return phrase
                } catch { let e = NSAlert(); e.messageText = error.localizedDescription; e.runModal() }
            case .alertSecondButtonReturn:
                guard let phrase = try? VaultCrypto.newPhrase() else { return nil }
                let s = NSAlert()
                s.messageText = "Your new keyphrase"
                s.informativeText = "\(phrase)\n\nKeep it safe: it cannot be recovered, and anyone with it holds your name and can open your cloud saves. It is copied to the clipboard."
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(phrase, forType: .string)
                s.addButton(withTitle: "I saved it"); s.addButton(withTitle: "Cancel")
                guard s.runModal() == .alertFirstButtonReturn else { return nil }
                do { try VaultKeychain.remember(phrase: phrase, endpoint: VaultAPI.defaultEndpoint(server: server)); return phrase }
                catch { note = (error.localizedDescription, .bad); return nil }
            default: return nil
            }
        }
    }
}

/// Cloudflare Turnstile's widget for a claim, in a small window: the page is given the server's own address (the
/// site key works there only) and hands the widget's answer back to `done` (nil: failed, closed or 2 minutes
/// passed).  Asynchronous: the page draws and calls back only while the main queue is free, so nothing waits for it.
final class TurnstileCheck: NSObject, WKScriptMessageHandler, NSWindowDelegate {
    private static var open = Set<TurnstileCheck>()        // alive until it answered
    private var window: NSWindow?
    private var controller: WKUserContentController?
    private var timer: Timer?
    private var done: ((String?) -> Void)?
    static func start(siteKey: String, page: URL, done: @escaping (String?) -> Void) {
        guard siteKey.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
              var c = URLComponents(url: page, resolvingAgainstBaseURL: false) else { done(nil); return }
        c.path = "/"; c.query = nil
        guard let base = c.url else { done(nil); return }
        let check = TurnstileCheck(); check.done = done; open.insert(check)
        check.show(siteKey: siteKey, base: base)
    }
    private func show(siteKey: String, base: URL) {
        let controller = WKUserContentController()
        controller.add(self, name: "turnstile"); self.controller = controller
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 360, height: 150), configuration: config)
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;height:100%;background:#1e1e1e;display:flex;align-items:center;justify-content:center}</style>
        <script>
        function post(m){window.webkit.messageHandlers.turnstile.postMessage(m)}
        function go(){try{turnstile.render('#w',{sitekey:'\(siteKey)',action:'claim',theme:'dark',
          callback:function(t){post({ok:t})},'error-callback':function(){post({err:1})},'expired-callback':function(){post({err:1})}})}catch(e){post({err:1})}}
        </script>
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" onload="go()" onerror="post({err:1})" async defer></script>
        </head><body><div id="w"></div></body></html>
        """
        web.loadHTMLString(html, baseURL: base)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "A quick check that you're human"; w.contentView = web; w.isReleasedWhenClosed = false; w.delegate = self
        w.center(); window = w
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in self?.finish(nil) }
    }
    private func finish(_ value: String?) {
        guard let done = done else { return }
        self.done = nil
        timer?.invalidate(); timer = nil
        controller?.removeScriptMessageHandler(forName: "turnstile"); controller = nil
        window?.delegate = nil; window?.orderOut(nil); window = nil
        Self.open.remove(self)
        done(value)
    }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any]
        if let t = body?["ok"] as? String, !t.isEmpty, t.utf8.count <= 4096 { finish(t) } else { finish(nil) }
    }
    func windowWillClose(_ notification: Notification) { finish(nil) }
}

/// The row under Player name (Views.swift MultiplayerCard).
struct NameClaimRow: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var names: NameClaimModel
    var body: some View {
        let name = model.playerName
        VStack(alignment: .leading, spacing: 4) {       // always there, so onAppear runs before the first answer
          if !names.noClaims, let line = names.line(for: name) {
                Text(line.text).font(.system(size: 11))
                    .foregroundColor(line.tone == .bad ? .orange : line.tone == .good ? .green : Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if names.claimedByOther(name) {
                        Button("Use \(names.digits(for: name))") { model.playerName = names.digits(for: name) }
                    }
                    if names.canClaim(name) {
                        Button("Claim \(name)") { names.claim(name: name, server: model.server) }
                    }
                    if names.info == nil && !names.busy {
                        Button("Check again") { names.check(name: name, server: model.server) }
                    }
                }
                .disabled(names.busy)
          }
        }
    }
}
