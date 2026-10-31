// The launcher's settings (launcher/Game.swift Prefs, Model.swift LauncherModel), with
// no window and no engine (tests/launcher_settings.sh):
//   defaults       a first start's values
//   persistence    a value set is there at the next start
//   invalid        a value the launcher never writes (an older or hand-edited
//                  preference) falls back to the default
//   environment    what play() hands the engine: the options as variables, one set
//                  by hand still wins, and the ones the launcher set itself (HUDPOS,
//                  NFSU2_PAD) follow the switch on the next Play (no stale value)
//   original game  Restore Original Game sets every option in Prefs.originalGame
//                  (new options are covered by that list on their own) and it stays
//   validation     server address, player name, Discord picture (rooms and crews:
//                  the online tests)
import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "PASS " : "FAIL ") + what)
    if !ok { failures += 1 }
}
func env(_ k: String) -> String? { getenv(k).map { String(cString: $0) } }

@main struct LauncherSettingsTests {
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        let domain = ProcessInfo.processInfo.processName
        let d = UserDefaults.standard
        d.removePersistentDomain(forName: domain)
        let launched = ["HUDPOS", "NFSU2_PAD", "NFSU2_PAD_DEADZONE", "NFSU2_FPS", "NFSU2_DISCORD", "NFSU2_DISCORD_LARGE_IMAGE",
                        "NFSU2_ALL_CARS", "BOOTMOVIES", "NFSU2_HEADLIGHTS", "NFSU2_GARAGE", "NFSU2_CUTSCENES_60", "NFSU2_CUTSCENE_BORDERS",
                        "NFSU2_LAN_TIMING", "NFSU2_SEED_REGISTRY", "NFSU2_LANGUAGE", "NFSU2_NET", "NFSU2_ONLINE", "NFSU2_SERVER_URL",
                        "NFSU2_ROAM", "NFSU2_HORN", "NFSU2_TEXPACKS", "NFSU2_REFLECTIONS", "TINT", "NFSU2_DATA", "NFSU2_ENGINE"]
        for k in launched { unsetenv(k) }

        // defaults
        var m = LauncherModel()
        check(m.engine == .original && !m.wideHUD && m.fpsCounter == 0 && m.frameRate == "auto", "defaults: original engine, HUD in 4:3, no counter, frame rate auto")
        check(m.allCars && m.garage && m.intro == "skippable" && m.headlights == "players" && m.cutsceneBars, "defaults: both releases' cars, 10-car garage, skippable intro, players' headlights, cutscene bars")
        check(!m.discord && m.discordImage.isEmpty && !m.online && m.server == OnlineSettings.defaultServer && m.freeRoam == .off && m.horn == .off,
              "defaults: no Discord, no picture, offline, default server, no free roam, no horn")
        check(m.controller && abs(m.stickDeadzone - 0.10) < 1e-9 && m.music == "game" && m.lanTiming == "pc" && !m.seedRegistry && m.reflections == .original,
              "defaults: controller on, dead zone 0.10, game music, PC LAN timing, no registry seed, original reflections")
        check(m.picture.allSatisfy { $0 == 0 }, "defaults: every picture option as on PC")

        // persistence
        m.frameRate = "60"; m.fpsCounter = 2; m.discord = true; m.discordImage = "https://example.com/car.png"
        m.headlights = "all"; m.intro = "off"; m.horn = .klaxon; m.freeRoam = .ghost; m.lanTiming = "exact"; m.stickDeadzone = 0.2
        m.picture = [1, 1, 1, 2]; m.reflections = .sharp; m.wideHUD = true; m.garage = false
        m = LauncherModel()
        check(m.frameRate == "60" && m.fpsCounter == 2 && m.discord && m.discordImage == "https://example.com/car.png", "persistence: frame rate, counter, Discord and its picture")
        check(m.headlights == "all" && m.intro == "off" && m.horn == .klaxon && m.freeRoam == .ghost && m.lanTiming == "exact", "persistence: headlights, intro, horn, free roam, LAN timing")
        check(abs(m.stickDeadzone - 0.2) < 1e-9 && m.picture == [1, 1, 1, 2] && m.reflections == .sharp && m.wideHUD && !m.garage, "persistence: dead zone, picture, reflections, HUD, garage")

        // invalid stored values
        d.set("999", forKey: Prefs.frameRate); d.set(7, forKey: Prefs.fpsCounter); d.set(9.0, forKey: Prefs.stickDeadzone)
        d.set("bogus", forKey: Prefs.engine); d.set("x", forKey: Prefs.reflections); d.set("x", forKey: Prefs.freeRoam)
        d.set("x", forKey: Prefs.horn); d.set("x", forKey: Prefs.lanTiming); d.set("x", forKey: Prefs.music)
        d.set("not a picture key!", forKey: Prefs.discordImage); d.set(-3, forKey: PictureOptions.all[0].key); d.set(99, forKey: PictureOptions.all[1].key)
        m = LauncherModel()
        check(m.frameRate == "auto" && m.fpsCounter == 2 && m.stickDeadzone == 0.5, "invalid: frame rate back to auto, counter and dead zone clamped")
        check(m.engine == .original && m.reflections == .original && m.freeRoam == .off && m.horn == .off, "invalid: engine, reflections, free roam, horn back to their defaults")
        check(m.lanTiming == "pc" && m.music == "game" && m.discordImage.isEmpty, "invalid: LAN timing, music, Discord picture back to their defaults")
        check(m.picture[0] == 0 && m.picture[1] == PictureOptions.all[1].choices.count - 1, "invalid: picture choices clamped to their lists")

        // environment handed to the engine
        let exe = URL(fileURLWithPath: "/nonexistent/Need for Speed Underground 2/SPEED2.EXE")
        var spawned: String?
        LauncherModel.testSpawn = { spawned = $0 }
        m = LauncherModel()
        m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.restoreOriginalGame(); m.controller = true; m.stickDeadzone = 0.15
        m.wideHUD = true; m.frameRate = "60"; m.discord = true; m.discordImage = "my_car"; m.cutsceneBars = false; m.intro = "off"
        m.play()
        // no engine is next to the test: play() falls back from one engine to the other as it does
        check(spawned.map { $0.hasSuffix("/Contents/MacOS/nfsu2-engine") || $0.hasSuffix("/Contents/MacOS/nfsu2-engine-hd") } == true,
              "play: an engine is started (\((spawned ?? "none").split(separator: "/").last ?? ""))")
        check(env("NFSU2_DATA") == exe.path && env("NFSU2_LANGUAGE") == "english", "play: the game's SPEED2.EXE and its language")
        check(env("HUDPOS") == "1" && env("NFSU2_FPS") == "60" && env("NFSU2_DISCORD") == "1" && env("NFSU2_DISCORD_LARGE_IMAGE") == "my_car",
              "play: HUD, frame rate, Discord and its picture")
        check(env("NFSU2_CUTSCENE_BORDERS") == "off" && env("BOOTMOVIES") == "off" && env("NFSU2_ALL_CARS") == "0" && env("NFSU2_GARAGE") == "off",
              "play: cutscene bars, intro, original cars and garage")
        check(["1", "hotplug"].contains(env("NFSU2_PAD") ?? "") && env("NFSU2_PAD_DEADZONE") == "0.15" && env("NFSU2_HEADLIGHTS") == "off", "play: controller, dead zone, headlights")
        check(env("NFSU2_NET") == nil && env("NFSU2_SERVER_URL") == nil && env("NFSU2_ROAM") == nil, "play: offline sets no network variable")
        // the next Play after a change: what the launcher set itself follows the switch
        m.wideHUD = false; m.controller = false; m.stickDeadzone = 0.3
        m.play()
        check(env("HUDPOS") == nil, "stale: HUDPOS cleared once the HUD switch is off")
        check(env("NFSU2_PAD") == "0" && env("NFSU2_PAD_DEADZONE") == "0.30", "stale: controller variables follow the switch")
        // a variable set by hand wins over the launcher's
        for k in launched { unsetenv(k) }
        setenv("NFSU2_FPS", "30", 1); setenv("HUDPOS", "0", 1); setenv("NFSU2_DISCORD_LARGE_IMAGE", "hand", 1)
        m = LauncherModel(); m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.frameRate = "240"; m.wideHUD = true; m.discord = true; m.discordImage = "launcher"
        m.play()
        check(env("NFSU2_FPS") == "30" && env("HUDPOS") == "0" && env("NFSU2_DISCORD_LARGE_IMAGE") == "hand", "hand-set variables win over the launcher's")
        for k in launched { unsetenv(k) }
        m.discordImage = "bad picture"; m.play()
        check(env("NFSU2_DISCORD_LARGE_IMAGE") == nil, "an invalid Discord picture is never handed to the engine")
        for k in launched { unsetenv(k) }
        m.discord = false; m.discordImage = "my_car"; m.play()
        check(env("NFSU2_DISCORD") == nil && env("NFSU2_DISCORD_LARGE_IMAGE") == nil, "Discord off: no Discord variable, picture or not")
        for k in launched { unsetenv(k) }
        m.online = true; m.playerName = "Driver_1"; m.server = "ws://127.0.0.1:8080/lan"; m.freeRoam = .solid; m.horn = .dual
        check(m.onlineError == nil, "online: a valid local server and name")
        m.play()
        check(env("NFSU2_NET") == "online" && env("NFSU2_SERVER_URL") == "ws://127.0.0.1:8080/lan" && env("NFSU2_ROAM") == "1" && env("NFSU2_HORN") == "dual",
              "online: network, server, free roam, horn")
        m.playerName = "x"; check(m.onlineError != nil, "online: a name that is too short is caught before Play")
        m.playerName = "Driver_1"; m.server = "ws://example.com/lan"; check(m.onlineError != nil, "online: ws:// to another machine is caught before Play")
        m.server = OnlineSettings.defaultServer; m.online = false
        LauncherModel.testSpawn = nil

        // Restore Original Game: every option of Prefs.originalGame, and it is kept
        m.engine = .hd; m.wideHUD = true; m.fpsCounter = 1; m.frameRate = "uncapped"; m.cutscenes60 = true; m.cutsceneBars = false
        m.headlights = "all"; m.reflections = .sharpest; m.reflectSky = true; m.reflectLights = true; m.reflectDetail = true
        m.picture = PictureOptions.all.map { $0.choices.count - 1 }; m.online = true; m.freeRoam = .ghost; m.hearCars = true
        m.horn = .train; m.allCars = true; m.garage = true; m.intro = "skippable"; m.discord = true; m.discordImage = "x"
        m.uhud = true; m.music = "folder"; m.seedRegistry = true; m.lanTiming = "exact"
        let changed = Prefs.originalGame.filter { !$0.isSet(m) }.count
        check(!m.isOriginalGame && changed >= 20, "original game: \(changed) of \(Prefs.originalGame.count) options changed")
        m.restoreOriginalGame()
        check(m.isOriginalGame && Prefs.originalGame.allSatisfy { $0.isSet(m) }, "original game: Restore sets all \(Prefs.originalGame.count) options")
        check(LauncherModel().isOriginalGame, "original game: still so at the next start")

        // validation
        for ok in ["wss://nfsu2.xyz/lan", "ws://127.0.0.1:8080/lan", "ws://[::1]:8080/lan", "ws://localhost/lan"] { check(OnlineSettings.validServer(ok), "server accepted: \(ok)") }
        for bad in ["ws://example.com/lan", "https://example.com", "wss://user:pass@example.com/lan", "wss://example.com/#secret",
                    "wss://example.com:99999/lan", "wss://example.com/lan\n", "", "ws://127.0.0.1.evil.com/lan"] {
            check(!OnlineSettings.validServer(bad), "server refused: \(bad.debugDescription)")
        }
        check(OnlineSettings.validName("Player_2-ABC"), "player name accepted")
        for bad in ["", "ab", "abcdefghijklmnop", "Player Name", "Ren\u{E9}", "user\n"] { check(!OnlineSettings.validName(bad), "player name refused: \(bad.debugDescription)") }
        for ok in ["", "https://example.com/a.png", "my_car", "car-1.v2"] { check(DiscordImage.valid(ok), "Discord picture accepted: \(ok.debugDescription)") }
        for bad in ["http://example.com/a.png", "https://", "two words", "caf\u{E9}", String(repeating: "a", count: 65),
                    "https://example.com/" + String(repeating: "a", count: 300), "https://u:p@example.com/a.png"] {
            check(!DiscordImage.valid(bad), "Discord picture refused: \(bad.prefix(40).debugDescription)")
        }
        d.removePersistentDomain(forName: domain); d.synchronize()      // (exit() skips defer)
        print(failures == 0 ? "launcher settings: all passed" : "launcher settings: \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
