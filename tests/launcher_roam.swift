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
    static let vars = ["NFSU2_ROAM", "NFSU2_NET", "NFSU2_ROAM_TUNERS", "NFSU2_ROAM_MAP_FILTER", "NFSU2_ROAM_AI_GREY"]
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

        // environment
        let exe = URL(fileURLWithPath: "/nonexistent/Need for Speed Underground 2/SPEED2.EXE")
        LauncherModel.testSpawn = { _ in }
        m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.online = true; m.playerName = "Driver_1"; m.server = "ws://127.0.0.1:8080/lan"; m.freeRoam = .solid
        m.play()
        check(env("NFSU2_ROAM") == "1" && env("NFSU2_ROAM_TUNERS") == nil && env("NFSU2_ROAM_MAP_FILTER") == nil && env("NFSU2_ROAM_AI_GREY") == nil, "play: everything on, nothing more for the engine")
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
        LauncherModel.testSpawn = nil

        print(failures == 0 ? "launcher roam: all passed" : "launcher roam: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
