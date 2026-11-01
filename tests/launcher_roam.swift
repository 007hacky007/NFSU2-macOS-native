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
    static let vars = ["NFSU2_ROAM", "NFSU2_NET", "NFSU2_ROAM_TUNERS"]
    static func clear() { for k in vars { unsetenv(k) } }
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        clear()

        // defaults
        var m = LauncherModel()
        check(m.roamTuners, "defaults: the game's tuners come with other players about")

        // environment
        let exe = URL(fileURLWithPath: "/nonexistent/Need for Speed Underground 2/SPEED2.EXE")
        LauncherModel.testSpawn = { _ in }
        m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.online = true; m.playerName = "Driver_1"; m.server = "ws://127.0.0.1:8080/lan"; m.freeRoam = .solid
        m.play()
        check(env("NFSU2_ROAM") == "1" && env("NFSU2_ROAM_TUNERS") == nil, "play: everything on, nothing more for the engine")
        clear()
        m.roamTuners = false
        m.play()
        check(env("NFSU2_ROAM_TUNERS") == "0", "play: tuners off (NFSU2_ROAM_TUNERS=0)")
        clear()
        m.freeRoam = .off; m.play()
        check(env("NFSU2_ROAM") == nil && env("NFSU2_ROAM_TUNERS") == nil, "play: free roam off, none of them")
        clear()
        m = LauncherModel()
        check(!m.roamTuners, "persistence: tuners off kept")

        // Restore Original Game
        m.restoreOriginalGame()
        check(m.roamTuners, "original game: the tuners come, as in the original game")
        LauncherModel.testSpawn = nil

        print(failures == 0 ? "launcher roam: all passed" : "launcher roam: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
