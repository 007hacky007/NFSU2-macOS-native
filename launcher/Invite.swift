// Invite links to a free-roam room or crew (ported from th0mk's nfsu2-web
// web/src/app/invite.ts, MIT): the server's start page with the room or crew after
// its '#', https://nfsu2.xyz/#room=Blue%20Room or #crew=Night%20Owls&room=<the
// sender's room> (crew-mates meet only within one room).  The same links the
// browser game copies and opens, so players on a Mac and in a browser invite each
// other.  Nothing changes before the player says Join (Paste Invite Link asks);
// Join also turns free roam with other players on where it was off, and says so.
// The names stay in the address's fragment, which a browser never sends: the
// server never sees them.  In a running game, Game Tools' Room changes the room
// at once (runtime/native_controls.m, roam_game.c room_follow).
import AppKit
import SwiftUI

/// What a link joins: a room, a crew, or a crew in a room ("" with a crew: in no room, everyone's).
struct Invite: Equatable {
    var room: String?
    var crew: String?
}

enum InviteLinks {
    /// Unicode's blanks (each one a blank to the room hash) and the invisible characters it leaves out
    static func isBlank(_ u: Unicode.Scalar) -> Bool {
        let c = u.value
        return u.properties.isWhitespace || c == 0xA0 || c == 0x1680 || (0x2000...0x200A).contains(c) || c == 0x2028 ||
            c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000
    }
    static func isInvisible(_ u: Unicode.Scalar) -> Bool {
        let c = u.value
        return c == 0xAD || (0x200B...0x200D).contains(c) || c == 0x2060 || c == 0xFEFF
    }
    /// A typed or linked name as the settings keep it: composed (NFC), its blanks single spaces, the invisible
    /// characters out, trimmed.
    static func tidy(_ s: String) -> String {
        var out = String.UnicodeScalarView(), gap = false
        for u in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            if isInvisible(u) { continue }
            if isBlank(u) { gap = !out.isEmpty; continue }
            if gap { out.append(" ") }
            gap = false
            out.append(u)
        }
        return String(out)
    }
    /// A typed room: nil when it can be joined, else why not.  settings.ini reads a # or ; after a blank as a
    /// comment, which would cut the name short there, so a name has none; else the Room box's own check.
    static func roomError(_ typed: String) -> String? {
        let name = tidy(typed)
        if OnlineSettings.roomHash(name) == 0 { return nil }
        if name.hasPrefix("#") || name.hasPrefix(";") || name.contains(" #") || name.contains(" ;") || name.contains("\t#") || name.contains("\t;") {
            return "No # or ; after a space in a room name."
        }
        return OnlineSettings.roomError(name)
    }
    /// Whether a link's names can be joined: each as the Room and Crew boxes check a typed one; nil: it can.
    static func error(_ inv: Invite) -> String? {
        if let r = inv.room, let e = roomError(r) { return e }
        if let c = inv.crew, let e = OnlineSettings.crewError(c) { return e }
        if let c = inv.crew, c.contains(",") { return "Crew: one crew in a link." }
        return nil
    }

    /// The invite in a link (a whole address, or just what follows its '#'): its names tidied; nil for none (no
    /// room or crew, a name that does not decode, or a room of blanks alone).
    static func read(_ text: String) -> Invite? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = t.firstIndex(of: "#") else { return nil }
        var inv = Invite()
        for part in t[t.index(after: hash)...].split(separator: "&", omittingEmptySubsequences: false) {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq], raw = part[part.index(after: eq)...].replacingOccurrences(of: "+", with: " ")
            guard key == "room" || key == "crew" else { continue }
            guard let v = raw.removingPercentEncoding else { return nil }
            if key == "room" { inv.room = tidy(v) } else { inv.crew = tidy(v) }
        }
        if inv.crew?.isEmpty == true { inv.crew = nil }
        if inv.room == "" && inv.crew == nil { inv.room = nil }
        return (inv.room?.isEmpty == false || inv.crew != nil) ? inv : nil
    }
    /// The host a link names ("" for a bare fragment)
    static func host(of text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = t.contains("://") ? t : "https://" + t
        guard !t.hasPrefix("#"), let c = URLComponents(string: full), let h = c.host else { return "" }
        return h.lowercased()
    }

    /// A name in a link: letters, digits, - _ ~ and the visible characters past ASCII as they are (a chat shows
    /// them so), every other as %XX of its UTF-8: blanks, the URL's own signs, and the . , ) ! a chat would cut
    /// off a link's end.
    static func encode(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            let c = u.value
            let plain = (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c) || (0x30...0x39).contains(c) || u == "_" || u == "~" || u == "-"
            if plain || (c >= 0xA0 && !isBlank(u) && !isInvisible(u)) { out.unicodeScalars.append(u); continue }
            for b in String(u).utf8 { out += String(format: "%%%02X", b) }
        }
        return out
    }
    /// The start page's address of a server (wss://host/lan -> https://host; ws:// on this Mac -> http://);
    /// nil for no valid server.
    static func origin(server: String) -> String? {
        guard OnlineSettings.validServer(server), var c = URLComponents(string: server) else { return nil }
        c.scheme = c.scheme == "wss" ? "https" : "http"
        c.path = ""; c.query = nil; c.fragment = nil
        return c.url?.absoluteString
    }
    /// The link to that page that joins inv: the crew first, then the room (a crew's with an empty room too: its
    /// friend leaves a room of their own to meet the sender in everyone's).
    static func link(origin: String, _ inv: Invite) -> String {
        var p: [String] = []
        if let c = inv.crew, !c.isEmpty { p.append("crew=" + encode(c)) }
        if let r = inv.room, !r.isEmpty || (inv.crew?.isEmpty == false) { p.append("room=" + encode(r)) }
        return origin + "/#" + p.joined(separator: "&")
    }

    /// Joins inv in the launcher's settings (after the player said Join): the room, the crew added to the crews
    /// (the first of a full list stays), free roam with other players turned on where it was off.  What changed,
    /// as the player reads it.
    @discardableResult
    static func apply(_ inv: Invite, to model: LauncherModel) -> [String] {
        var said: [String] = []
        if let r = inv.room {
            model.roamRoom = r
            said.append(r.isEmpty ? "Room: everyone (no room)." : "Room: \(r).")
        }
        if let c = inv.crew {
            var crews = model.roamCrew.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if crews.contains(where: { OnlineSettings.roomHash($0) == OnlineSettings.roomHash(c) }) {
                said.append("You are in crew \(c) already.")
            } else if crews.count >= 4 {
                said.append("You are in four crews already: leave one in Settings to join \(c).")
            } else {
                crews.append(c); model.roamCrew = crews.joined(separator: ", ")
                said.append("Crew \(c) added.")
            }
        }
        if !model.online { model.online = true; said.append("Play online turned on.") }
        if model.freeRoam == .off { model.freeRoam = .solid; said.append("Free roam with other players turned on (solid cars).") }
        return said
    }
}

/// Under Room and Crew (Views.swift MultiplayerCard): paste an invite link, copy one.
struct InviteRow: View {
    @ObservedObject var model: LauncherModel
    @State private var note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Paste Invite Link\u{2026}") { paste() }
                if let o = InviteLinks.origin(server: model.server) {
                    Menu("Copy Invite Link") {
                        let room = model.roamRoom.trimmingCharacters(in: .whitespaces)
                        Button(room.isEmpty ? "Room: everyone" : "Room \(room)") { copy(InviteLinks.link(origin: o, Invite(room: room, crew: nil)), what: "room") }
                            .disabled(room.isEmpty)
                        ForEach(crews, id: \.self) { c in
                            Button("Crew \(c)") { copy(InviteLinks.link(origin: o, Invite(room: room, crew: c)), what: "crew") }
                        }
                    }
                    .fixedSize()
                }
            }
            if let n = note {
                Text(n).font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var crews: [String] {
        model.roamCrew.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func copy(_ link: String, what: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string)
        note = "Copied the \(what)'s invite link: \(link)"
    }
    /// The link on the clipboard (or typed), asked about, then joined.
    private func paste() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://nfsu2.xyz/#room=..."
        if let s = NSPasteboard.general.string(forType: .string), InviteLinks.read(s) != nil { field.stringValue = s }
        let a = NSAlert()
        a.messageText = "Join from an invite link"
        a.informativeText = "Paste a link another player copied (from this launcher or the browser game). Nothing changes before you say Join."
        a.accessoryView = field
        a.addButton(withTitle: "Continue"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let inv = InviteLinks.read(field.stringValue) else { note = "That is no invite link (it has no #room= or #crew=)."; return }
        if let e = InviteLinks.error(inv) { note = e; return }
        let what = [inv.crew.map { "crew \($0)" }, inv.room.map { $0.isEmpty ? "everyone's room" : "room \($0)" }].compactMap { $0 }.joined(separator: " in ")
        let q = NSAlert()
        q.messageText = "Join \(what)?"
        var info = "Free roam shows you the players of that room only."
        let host = InviteLinks.host(of: field.stringValue), mine = URLComponents(string: model.server)?.host?.lowercased() ?? ""
        if !host.isEmpty && host != mine { info += " The link is for \(host); you play on \(mine.isEmpty ? "no server" : mine)." }
        q.informativeText = info
        q.addButton(withTitle: "Join"); q.addButton(withTitle: "Cancel")
        guard q.runModal() == .alertFirstButtonReturn else { return }
        note = InviteLinks.apply(inv, to: model).joined(separator: " ") + " A game already running changes room in Game Tools (Cmd+Shift+M)."
    }
}
