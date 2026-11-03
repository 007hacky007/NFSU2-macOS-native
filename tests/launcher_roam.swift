// The launcher's later free-roam options (launcher/RoamExtras.swift), with no window and
// no engine (tests/launcher_roam.sh):
//   defaults       on at a first start, as in nfsu2-web
//   environment    with free roam on, only an option turned off reaches the engine (as 0);
//                  offline or with free roam off, none
//   original game  Restore Original Game sets each one's value in the original game
import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "PASS " : "FAIL ") + what)
    if !ok { failures += 1 }
}
func env(_ k: String) -> String? { getenv(k).map { String(cString: $0) } }

@main struct LauncherRoamTests {
    static let vars = ["NFSU2_ROAM", "NFSU2_NET", "NFSU2_ROAM_TUNERS", "NFSU2_ROAM_MAP_FILTER", "NFSU2_ROAM_AI_GREY", "NFSU2_ROAM_FRIENDS",
                        "NFSU2_ROAM_COLLIDE", "NFSU2_ROAM_MAX_CARS"]
    static func clear() { for k in vars { unsetenv(k) } }
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        clear()

        // defaults
        var m = LauncherModel()
        check(m.roamTuners, "defaults: the game's tuners come with other players about")
        check(m.roamMapFilter, "defaults: the world map legend's Players rows")
        check(m.roamAIGrey, "defaults: the game's challengers grey on the maps")
        check(m.roamFriends, "defaults: friends in free roam")
        check(m.roamCars == 32, "defaults: 32 players' cars shown")

        // environment
        let exe = URL(fileURLWithPath: "/nonexistent/Need for Speed Underground 2/SPEED2.EXE")
        LauncherModel.testSpawn = { _ in }
        m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.online = true; m.playerName = "Driver_1"; m.server = "ws://127.0.0.1:8080/lan"; m.freeRoam = .solid
        m.play()
        check(env("NFSU2_ROAM") == "1" && env("NFSU2_ROAM_TUNERS") == nil && env("NFSU2_ROAM_MAP_FILTER") == nil && env("NFSU2_ROAM_AI_GREY") == nil && env("NFSU2_ROAM_FRIENDS") == nil, "play: everything on, nothing more for the engine")
        clear()
        m.roamTuners = false
        m.play()
        check(env("NFSU2_ROAM_TUNERS") == "0" && env("NFSU2_ROAM_MAP_FILTER") == nil, "play: tuners off (NFSU2_ROAM_TUNERS=0)")
        clear()
        m.roamMapFilter = false
        m.play()
        check(env("NFSU2_ROAM_MAP_FILTER") == "0", "play: the legend's rows off (NFSU2_ROAM_MAP_FILTER=0)")
        clear()
        m.roamAIGrey = false
        m.play()
        check(env("NFSU2_ROAM_AI_GREY") == "0", "play: the challengers in the game's colour (NFSU2_ROAM_AI_GREY=0)")
        clear()
        m.roamFriends = false
        m.play()
        check(env("NFSU2_ROAM_FRIENDS") == "0", "play: friends off (NFSU2_ROAM_FRIENDS=0)")
        clear()
        // collisions and the cars shown
        check(env("NFSU2_ROAM_COLLIDE") == nil && env("NFSU2_ROAM_MAX_CARS") == nil, "play: (cleared)")
        m.freeRoam = .solid; m.play()
        check(env("NFSU2_ROAM_COLLIDE") == "1" && env("NFSU2_ROAM_MAX_CARS") == "32", "play: solid cars (NFSU2_ROAM_COLLIDE=1), 32 cars shown")
        clear()
        m.freeRoam = .ghost; m.roamCars = 48; m.play()
        check(env("NFSU2_ROAM_COLLIDE") == "0" && env("NFSU2_ROAM_MAX_CARS") == "48", "play: ghost cars (=0), 48 cars shown")
        clear()
        m.freeRoam = .everything; m.roamCars = 16; m.play()
        check(env("NFSU2_ROAM_COLLIDE") == "none" && env("NFSU2_ROAM_MAX_CARS") == "16", "play: everything a ghost (=none), 16 cars shown")
        clear()
        m = LauncherModel()
        check(m.freeRoam == .everything && m.roamCars == 16, "persistence: everything a ghost and 16 cars kept")
        UserDefaults.standard.set(33, forKey: Prefs.roamCars)
        check(LauncherModel().roamCars == 32 && RoamExtras.cars(40) == 40 && RoamExtras.cars(0) == 32, "persistence: a stored count that is no choice is 32")
        m.roamCars = 32
        m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.online = true; m.playerName = "Driver_1"; m.server = "ws://127.0.0.1:8080/lan"
        m.freeRoam = .off; m.play()
        check(env("NFSU2_ROAM") == nil && env("NFSU2_ROAM_TUNERS") == nil, "play: free roam off, none of them")
        clear()
        m = LauncherModel()
        check(!m.roamTuners, "persistence: tuners off kept")

        // Restore Original Game
        m.restoreOriginalGame()
        check(m.roamTuners, "original game: the tuners come, as in the original game")
        check(!m.roamMapFilter, "original game: no rows of ours in the world map's legend")
        check(!m.roamAIGrey, "original game: the challengers in the game's orange")
        check(!m.roamFriends, "original game: no friends in free roam")
        LauncherModel.testSpawn = nil

        // invite links (Invite.swift): nfsu2-web's own vectors (web/test/invite.test.mjs)
        let o = "https://nfsu2.xyz"
        check(InviteLinks.link(origin: o, Invite(room: "Blue Room")) == "https://nfsu2.xyz/#room=Blue%20Room"
              && InviteLinks.link(origin: o, Invite(room: "Blue Room", crew: "Night Owls")) == "https://nfsu2.xyz/#crew=Night%20Owls&room=Blue%20Room"
              && InviteLinks.link(origin: o, Invite(room: "", crew: "Night Owls")) == "https://nfsu2.xyz/#crew=Night%20Owls&room="
              && InviteLinks.link(origin: o, Invite(room: nil, crew: "Night Owls")) == "https://nfsu2.xyz/#crew=Night%20Owls",
              "invite: a room's link, a crew's with the sender's room (or none)")
        check(InviteLinks.link(origin: o, Invite(room: "\u{41a}\u{43e}\u{43c}\u{43d}\u{430}\u{442}\u{430}")) == "https://nfsu2.xyz/#room=\u{41a}\u{43e}\u{43c}\u{43d}\u{430}\u{442}\u{430}"
              && InviteLinks.link(origin: o, Invite(room: "A&B=C#1?")) == "https://nfsu2.xyz/#room=A%26B%3DC%231%3F"
              && InviteLinks.link(origin: o, Invite(room: "Team (2).")) == "https://nfsu2.xyz/#room=Team%20%282%29%2E"
              && InviteLinks.link(origin: o, Invite(room: "100%!")) == "https://nfsu2.xyz/#room=100%25%21"
              && InviteLinks.link(origin: o, Invite(room: "a\u{a0}b")) == "https://nfsu2.xyz/#room=a%C2%A0b",
              "invite: letters past ASCII as they are, the URL's signs and blanks coded")
        let back: [Invite] = [Invite(room: "Blue Room"), Invite(room: "Blue Room", crew: "Night Owls"), Invite(room: "", crew: "Night Owls"),
                              Invite(room: nil, crew: "Night Owls"), Invite(room: "A&B=C#1?"), Invite(room: "Team (2)."), Invite(room: "100%!"),
                              Invite(room: "\u{141}\u{d3}D\u{179} \u{d7}2", crew: "zo\u{eb}")]
        check(back.allSatisfy { InviteLinks.read(InviteLinks.link(origin: o, $0)) == $0 }, "invite: its own links read back")
        check(InviteLinks.read("#room=%20%20Blue%C2%A0%C2%A0Room%E2%80%8B%20") == Invite(room: "Blue Room")
              && InviteLinks.read("#room=Cafe%CC%81") == Invite(room: "Caf\u{e9}")
              && InviteLinks.read("#room=Blue+Room") == Invite(room: "Blue Room")
              && InviteLinks.read("  nfsu2.xyz/#x=1&room=Red&other\n") == Invite(room: "Red"),
              "invite: blanks tidied, invisible characters out, composed, + as a space, other parts left alone")
        check(["", "#", "#top", "#room=", "#room=%E2%80%8B", "#room=%E0%A4", "https://nfsu2.xyz/"].allSatisfy { InviteLinks.read($0) == nil },
              "invite: no invite in another fragment, an empty or invisible room, bytes that are not UTF-8")
        check(InviteLinks.roomError("Team#2") == nil && ["Team #2", "Team ;2", "#2", ";x"].allSatisfy { InviteLinks.roomError($0) != nil }
              && InviteLinks.roomError(String(repeating: "x", count: 64)) != nil
              && InviteLinks.roomError(String(repeating: "\u{44f}", count: 31)) == nil && InviteLinks.roomError(String(repeating: "\u{44f}", count: 32)) != nil,
              "invite: the Room box's checks (no # or ; after a space, 63 bytes)")
        check(InviteLinks.error(Invite(room: "Blue Room", crew: "Night Owls")) == nil && InviteLinks.error(Invite(room: "", crew: "Night Owls")) == nil
              && InviteLinks.error(Invite(room: nil, crew: "a, b")) != nil && InviteLinks.error(Invite(room: nil, crew: String(repeating: "x", count: 25))) != nil
              && InviteLinks.error(Invite(room: "1488")) != nil,
              "invite: the crew box's checks, one crew a link, names the rules turn down")
        check(InviteLinks.origin(server: "wss://nfsu2.xyz/lan") == "https://nfsu2.xyz" && InviteLinks.origin(server: "ws://127.0.0.1:8080/lan") == "http://127.0.0.1:8080"
              && InviteLinks.origin(server: "ws://example.com/lan") == nil, "invite: the start page's address follows the server")
        check(InviteLinks.host(of: "https://NFSU2.xyz/#room=a") == "nfsu2.xyz" && InviteLinks.host(of: "#room=a") == "", "invite: the host a link names")
        // joined: the room, the crew added (once, four at most), free roam on where it was off
        m = LauncherModel(); m.online = true; m.freeRoam = .off; m.roamRoom = ""; m.roamCrew = "Blue Room"
        var said = InviteLinks.apply(Invite(room: "Red", crew: "night owls"), to: m)
        check(m.roamRoom == "Red" && m.roamCrew == "Blue Room, night owls" && m.freeRoam == .solid && said.count == 3,
              "invite: Join sets the room, adds the crew, turns free roam on (\(said.joined(separator: " ")))")
        said = InviteLinks.apply(Invite(room: "", crew: "NIGHT OWLS"), to: m)
        check(m.roamRoom == "" && m.roamCrew == "Blue Room, night owls" && said.contains { $0.contains("already") }, "invite: a crew already in, everyone's room")
        m.roamCrew = "a, b, c, d"
        said = InviteLinks.apply(Invite(room: nil, crew: "e"), to: m)
        check(m.roamCrew == "a, b, c, d" && said.contains { $0.contains("four crews") }, "invite: four crews already: the list stays")
        m.roamCrew = ""; m.roamRoom = ""

        print(failures == 0 ? "launcher roam: all passed" : "launcher roam: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
