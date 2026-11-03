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
//   embedded       a game inside the app: language packs are made outside the bundle,
//                  the engine is told where (NFSU2_LANGPACKS), nothing in the bundle changes
//   updates        Check for updates (UpdateCheck.swift): version order, every two hours,
//                  also while the launcher stays open, off
//                  makes no request, the notice and Not now (a fake fetcher, no network)
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
        let launched = ["NFSU2_UNIQUES", "HUDPOS", "NFSU2_PAD", "NFSU2_PAD_DEADZONE", "NFSU2_FPS", "NFSU2_DISCORD", "NFSU2_DISCORD_LARGE_IMAGE",
                        "NFSU2_ALL_CARS", "BOOTMOVIES", "NFSU2_HEADLIGHTS", "NFSU2_GARAGE", "NFSU2_CUTSCENES_60", "NFSU2_CUTSCENE_BORDERS",
                        "NFSU2_LAN_TIMING", "NFSU2_SEED_REGISTRY", "NFSU2_LANGUAGE", "NFSU2_NET", "NFSU2_ONLINE", "NFSU2_SERVER_URL",
                        "NFSU2_ROAM", "NFSU2_HORN", "NFSU2_TEXPACKS", "NFSU2_REFLECTIONS", "TINT", "NFSU2_DATA", "NFSU2_ENGINE", "MTL_HUD_ENABLED",
                        "NFSU2_LANGPACKS", "NFSU2_NET_STATS", "NFSU2_NEW_PROFILE_NAME", "NFSU2_SHOW_HIDDEN_RACES", "NFSU2_EXPOSURE", "NFSU2_WHITE_LEVEL"]
        for k in launched { unsetenv(k) }

        // defaults
        var m = LauncherModel()
        check(m.engine == .original && !m.wideHUD && m.fpsCounter == 0 && m.frameRate == "auto", "defaults: original engine, HUD in 4:3, no counter, frame rate auto")
        check(!m.metalHUD, "defaults: no Metal performance overlay")
        check(m.allCars && m.garage && m.intro == "skippable" && m.headlights == "players" && m.cutsceneBars, "defaults: both releases' cars, 10-car garage, skippable intro, players' headlights, cutscene bars")
        check(!m.discord && m.discordImage.isEmpty && !m.online && m.server == OnlineSettings.defaultServer && m.freeRoam == .off && m.horn == .off,
              "defaults: no Discord, no picture, offline, default server, no free roam, no horn")
        check(!m.netStats, "defaults: no Online statistics panel")
        check(!m.hiddenRaces, "defaults: hidden races hidden, as in the original game")
        check(!m.uniques, "defaults: unique parts only for the car that won them, as in the original game")
        check(m.exposure == "0" && m.whiteLevel == "100", "defaults: exposure 0 and white level 100 %, the game's picture")
        check(m.controller && abs(m.stickDeadzone - 0.10) < 1e-9 && m.music == "game" && m.lanTiming == "pc" && !m.seedRegistry && m.reflections == .original,
              "defaults: controller on, dead zone 0.10, game music, PC LAN timing, no registry seed, original reflections")
        check(m.picture.allSatisfy { $0 == 0 }, "defaults: every picture option as on PC")

        // persistence
        m.frameRate = "60"; m.fpsCounter = 2; m.discord = true; m.discordImage = "https://example.com/car.png"
        m.headlights = "all"; m.intro = "off"; m.horn = .klaxon; m.freeRoam = .ghost; m.lanTiming = "exact"; m.stickDeadzone = 0.2
        m.picture = [1, 1, 1, 2]; m.reflections = .sharp; m.wideHUD = true; m.garage = false; m.netStats = true
        m.hiddenRaces = true; m.exposure = "-0.3"; m.whiteLevel = "70"
        m = LauncherModel()
        check(m.exposure == "-0.3" && m.whiteLevel == "70", "persistence: exposure and white level")
        check(m.hiddenRaces, "persistence: Show hidden races")
        check(m.netStats, "persistence: Online statistics")
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
        m.metalHUD = true; m.netStats = true
        m.play()
        // no engine is next to the test: play() falls back from one engine to the other as it does
        check(spawned.map { $0.hasSuffix("/Contents/MacOS/nfsu2-engine") || $0.hasSuffix("/Contents/MacOS/nfsu2-engine-hd") } == true,
              "play: an engine is started (\((spawned ?? "none").split(separator: "/").last ?? ""))")
        check(env("NFSU2_DATA") == exe.path && env("NFSU2_LANGUAGE") == "english", "play: the game's SPEED2.EXE and its language")
        check(env("HUDPOS") == "1" && env("NFSU2_FPS") == "60" && env("NFSU2_DISCORD") == "1" && env("NFSU2_DISCORD_LARGE_IMAGE") == "my_car",
              "play: HUD, frame rate, Discord and its picture")
        check(env("NFSU2_CUTSCENE_BORDERS") == "off" && env("BOOTMOVIES") == "off" && env("NFSU2_ALL_CARS") == "0" && env("NFSU2_GARAGE") == "off",
              "play: cutscene bars, intro, original cars and garage")
        check(env("MTL_HUD_ENABLED") == "1", "play: the Metal performance overlay")
        check(env("NFSU2_SHOW_HIDDEN_RACES") == nil, "play: hidden races off, no NFSU2_SHOW_HIDDEN_RACES")
        check(env("NFSU2_EXPOSURE") == nil && env("NFSU2_WHITE_LEVEL") == nil, "play: the game's picture, no exposure or white level")
        check(["1", "hotplug"].contains(env("NFSU2_PAD") ?? "") && env("NFSU2_PAD_DEADZONE") == "0.15" && env("NFSU2_HEADLIGHTS") == "off", "play: controller, dead zone, headlights")
        check(env("NFSU2_NET") == nil && env("NFSU2_SERVER_URL") == nil && env("NFSU2_ROAM") == nil, "play: offline sets no network variable")
        check(env("NFSU2_NET_STATS") == nil, "play: offline, no Online statistics even with the switch on")
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
        m.discord = false; m.discordImage = "my_car"; m.metalHUD = false; m.hiddenRaces = true; m.play()
        check(env("NFSU2_SHOW_HIDDEN_RACES") == "1", "play: Show hidden races (NFSU2_SHOW_HIDDEN_RACES=1)")
        m.hiddenRaces = false
        for k in launched { unsetenv(k) }
        m.play()
        check(env("NFSU2_UNIQUES") == nil, "play: unique parts off, no variable")
        for k in launched { unsetenv(k) }
        m.uniques = true; m.play()
        check(env("NFSU2_UNIQUES") == "1", "play: unique parts for every car (NFSU2_UNIQUES=1)")
        m.uniques = false
        for k in launched { unsetenv(k) }
        m.exposure = "+0.5"; m.whiteLevel = "80"; m.play()
        check(env("NFSU2_EXPOSURE") == "+0.5" && env("NFSU2_WHITE_LEVEL") == "80", "play: exposure and white level")
        m.exposure = "0"; m.whiteLevel = "100"
        check(env("NFSU2_DISCORD") == nil && env("NFSU2_DISCORD_LARGE_IMAGE") == nil, "Discord off: no Discord variable, picture or not")
        check(env("MTL_HUD_ENABLED") == nil, "Metal performance overlay off: no MTL_HUD_ENABLED")
        for k in launched { unsetenv(k) }
        m.online = true; m.playerName = "Driver_1"; m.server = "ws://127.0.0.1:8080/lan"; m.freeRoam = .solid; m.horn = .dual
        check(m.onlineError == nil, "online: a valid local server and name")
        m.play()
        check(env("NFSU2_NET") == "online" && env("NFSU2_SERVER_URL") == "ws://127.0.0.1:8080/lan" && env("NFSU2_ROAM") == "1" && env("NFSU2_HORN") == "dual",
              "online: network, server, free roam, horn")
        check(env("NFSU2_NET_STATS") == "1", "online: the Online statistics panel (NFSU2_NET_STATS=1)")
        for k in launched { unsetenv(k) }
        m.netStats = false; m.play()
        check(env("NFSU2_NET") == "online" && env("NFSU2_NET_STATS") == nil, "online: Online statistics off, no NFSU2_NET_STATS")
        m.netStats = true
        m.playerName = "x"; check(m.onlineError != nil, "online: a name that is too short is caught before Play")
        m.playerName = "Driver_1"; m.server = "ws://example.com/lan"; check(m.onlineError != nil, "online: ws:// to another machine is caught before Play")
        m.server = OnlineSettings.defaultServer; m.online = false
        // a first profile's name box starts with the Player name (NFSU2_NEW_PROFILE_NAME, runtime/gamefix.c)
        check(OnlineSettings.newProfileName("Alex_the_Great") == "Alexthe" && OnlineSettings.newProfileName("Driver_1") == "Driver1",
              "first profile: the Player name's letters and digits, 7 at most")
        check(["", "__-", "Player", "NAME", "name"].allSatisfy { OnlineSettings.newProfileName($0).isEmpty },
              "first profile: no name, NAME or Player give none")
        let saveDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nfsu2-saves-\(getpid())")
        try? FileManager.default.removeItem(at: saveDir)
        setenv("NFSU2_SAVEDIR", saveDir.path, 1)
        for k in launched { unsetenv(k) }
        m.playerName = "Alex_the_Great"; m.play()
        check(env("NFSU2_NEW_PROFILE_NAME") == "Alexthe", "first profile: no save folder, the Player name is passed")
        let prof = saveDir.appendingPathComponent("NFS Underground 2/ALEX")
        try? FileManager.default.createDirectory(at: prof, withIntermediateDirectories: true)
        try? Data(count: 16).write(to: prof.appendingPathComponent("ALEX"))
        m.play()
        check(env("NFSU2_NEW_PROFILE_NAME") == nil, "first profile: a profile there, none passed (none left from the last Play)")
        try? FileManager.default.removeItem(at: prof)
        m.playerName = "Player"; m.play()
        check(env("NFSU2_NEW_PROFILE_NAME") == nil, "first profile: the Player name Player is not passed")
        setenv("NFSU2_NEW_PROFILE_NAME", "HAND", 1); m.playerName = "Driver_1"; m.play()
        check(env("NFSU2_NEW_PROFILE_NAME") == "HAND", "first profile: one set by hand wins")
        unsetenv("NFSU2_SAVEDIR"); try? FileManager.default.removeItem(at: saveDir)
        for k in launched { unsetenv(k) }
        LauncherModel.testSpawn = nil

        // Restore Original Game: every option of Prefs.originalGame, and it is kept
        m.engine = .hd; m.wideHUD = true; m.fpsCounter = 1; m.frameRate = "uncapped"; m.cutscenes60 = true; m.cutsceneBars = false
        m.headlights = "all"; m.reflections = .sharpest; m.reflectSky = true; m.reflectLights = true; m.reflectDetail = true
        m.picture = PictureOptions.all.map { $0.choices.count - 1 }; m.online = true; m.freeRoam = .ghost; m.hearCars = true
        m.horn = .train; m.allCars = true; m.garage = true; m.intro = "skippable"; m.discord = true; m.discordImage = "x"
        m.uhud = true; m.music = "folder"; m.seedRegistry = true; m.lanTiming = "exact"; m.netStats = true; m.hiddenRaces = true; m.uniques = true
        m.exposure = "-1.0"; m.whiteLevel = "40"
        let changed = Prefs.originalGame.filter { !$0.isSet(m) }.count
        check(!m.isOriginalGame && changed >= 20, "original game: \(changed) of \(Prefs.originalGame.count) options changed")
        m.restoreOriginalGame()
        check(m.isOriginalGame && Prefs.originalGame.allSatisfy { $0.isSet(m) }, "original game: Restore sets all \(Prefs.originalGame.count) options")
        check(!m.netStats && !LauncherModel().netStats, "original game: Online statistics off, and kept off")
        check(!m.hiddenRaces, "original game: hidden races hidden")
        check(!m.uniques, "original game: unique parts for the car that won them")
        check(m.exposure == "0" && m.whiteLevel == "100", "original game: exposure 0, white level 100 %")
        check(LauncherModel().isOriginalGame, "original game: still so at the next start")

        // embedded: a game inside the app; its language packs go outside the bundle
        let fm = FileManager.default
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nfsu2-embedded-\(getpid())/NFSU2.app")
        let inside = bundle.appendingPathComponent("Contents/Resources/Game")
        try? fm.createDirectory(at: inside.appendingPathComponent("LANGUAGES"), withIntermediateDirectories: true)
        try? Data("exe".utf8).write(to: inside.appendingPathComponent("SPEED2.EXE"))
        try? Data("english".utf8).write(to: inside.appendingPathComponent("LANGUAGES/English.bin"))
        func listing(_ u: URL) -> [String] {
            ((fm.enumerator(atPath: u.path)?.allObjects as? [String]) ?? []).sorted()
        }
        let bundleBefore = listing(bundle)
        let embedded = GameLocation(exe: inside.appendingPathComponent("SPEED2.EXE"), embedded: true)
        check(Paths.outsideLanguagePacks.path.hasSuffix("/Library/Application Support/NFSU2/LanguagePacks"),
              "embedded: language packs go to Application Support, not into the app")
        Paths.testLanguagePacks = bundle.deletingLastPathComponent().appendingPathComponent("Application Support/NFSU2/LanguagePacks")
        let outside = Paths.languagePacks(for: embedded)
        check(outside == Paths.testLanguagePacks && !outside.path.hasPrefix(bundle.path), "embedded: an embedded game's packs are the outside ones")
        check(Paths.languagePacks(for: GameLocation(exe: exe, embedded: false)).path == exe.deletingLastPathComponent().appendingPathComponent("LANGPACKS").path,
              "embedded: a game folder keeps its own LANGPACKS")
        let pack = LanguagePacks.Pack(game: embedded.folder, lang: "french", packs: outside)
        do { try pack.add(Data("french".utf8), "LANGUAGES/French.bin"); pack.finish() } catch { check(false, "embedded: pack written (\(error))") }
        check(fm.fileExists(atPath: outside.appendingPathComponent("french/LANGUAGES/French.bin").path), "embedded: the pack is made outside the app")
        check(listing(bundle) == bundleBefore, "embedded: nothing in the app changed (\(listing(bundle).count) entries)")
        m = LauncherModel()
        LauncherModel.testSpawn = { _ in }
        m.game = .ready(embedded)
        check(m.languages.contains("french"), "embedded: the outside pack's language is offered")
        m.play()
        check(env("NFSU2_LANGPACKS") == outside.path, "embedded: play hands the engine the outside packs (NFSU2_LANGPACKS)")
        m.game = .ready(GameLocation(exe: exe, embedded: false))
        m.play()
        check(env("NFSU2_LANGPACKS") == nil, "embedded: a game folder's Play leaves no NFSU2_LANGPACKS behind")
        LauncherModel.testSpawn = nil
        try? fm.removeItem(at: bundle.deletingLastPathComponent())

        // updates: Check for updates, with a fake fetcher
        check(UpdateCheck.isNewer("1.10.0", than: "1.9.2") && UpdateCheck.isNewer("v2", than: "1.99")
              && UpdateCheck.isNewer("1.0.1", than: "1.0") && !UpdateCheck.isNewer("1.0", than: "1.0.0")
              && !UpdateCheck.isNewer("1.2.0", than: "1.10.0") && !UpdateCheck.isNewer("1.1.0", than: "1.1.0"),
              "updates: versions compare number by number")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        check(UpdateCheck.isDue(last: nil, now: t0) && !UpdateCheck.isDue(last: t0, now: t0.addingTimeInterval(2 * 3600 - 60))
              && UpdateCheck.isDue(last: t0, now: t0.addingTimeInterval(2 * 3600)) && UpdateCheck.isDue(last: t0.addingTimeInterval(60), now: t0),
              "updates: every two hours")
        func release(_ v: String) -> Data {
            Data(#"{"tag_name":"v\#(v)","html_url":"https://github.com/007hacky007/NFSU2-macOS-native/releases/tag/v\#(v)","assets":[{"name":"NFSU2-Builder.dmg","browser_download_url":"https://github.com/007hacky007/NFSU2-macOS-native/releases/download/v\#(v)/NFSU2-Builder.dmg"},{"name":"NFSU2-Builder.dmg.sha256","browser_download_url":"https://example.com/x"}]}"#.utf8)
        }
        let parsed = UpdateCheck.parse(release("1.1.0"))
        check(parsed?.version == "1.1.0" && parsed?.download?.lastPathComponent == "NFSU2-Builder.dmg"
              && parsed?.page.absoluteString.hasSuffix("/tag/v1.1.0") == true, "updates: the release, its page and its disk image")
        check(UpdateCheck.parse(Data("{}".utf8)) == nil && UpdateCheck.parse(Data("not json".utf8)) == nil, "updates: a broken answer is ignored")
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        try? fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = (["NFSBuilderVersion": "1.0.0"] as NSDictionary).write(to: plist, atomically: true)
        check(UpdateCheck.stamp(of: bundle) == "1.0.0" && UpdateCheck.stamp(of: bundle.deletingLastPathComponent()) == nil,
              "updates: the Builder stamp in Info.plist (none: no stamp)")
        try? fm.removeItem(at: bundle.deletingLastPathComponent())
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        for k in [Prefs.updateLastCheck, Prefs.updateLatest, Prefs.updateDismissed] { d.removeObject(forKey: k) }
        m = LauncherModel()
        check(m.checkUpdates, "updates: Check for updates is on by default")
        var requests: [URL] = [], answer = release("1.1.0")
        m.fetchRelease = { url, done in requests.append(url); done(answer) }
        m.builderStamp = nil
        m.checkForUpdates(now: t0); settle()
        check(requests.isEmpty && m.updateNotice == nil, "updates: no stamp, no request")
        m.builderStamp = "1.0.0"
        m.checkForUpdates(now: t0); settle()
        check(requests == [UpdateCheck.releasesAPI] && m.updateNotice?.version == "1.1.0", "updates: a newer Builder shows the notice")
        m.checkForUpdates(now: t0.addingTimeInterval(3600)); settle()
        check(requests.count == 1 && m.updateNotice?.version == "1.1.0", "updates: one request in two hours, the notice stays")
        let next = LauncherModel()
        next.builderStamp = "1.0.0"
        next.fetchRelease = { url, done in requests.append(url); done(nil) }
        next.checkForUpdates(now: t0.addingTimeInterval(5400)); settle()
        check(requests.count == 1 && next.updateNotice?.version == "1.1.0", "updates: the next start shows the notice without asking again")
        m.dismissUpdate()
        check(m.updateNotice == nil, "updates: Not now hides it")
        m.checkForUpdates(now: t0.addingTimeInterval(25 * 3600)); settle()
        check(requests.count == 2 && m.updateNotice == nil, "updates: hidden while no newer one is out")
        answer = release("1.2.0")
        m.checkForUpdates(now: t0.addingTimeInterval(50 * 3600)); settle()
        check(requests.count == 3 && m.updateNotice?.version == "1.2.0", "updates: a newer one than the dismissed shows again")
        m.builderStamp = "1.2.0"; m.checkForUpdates(now: t0.addingTimeInterval(51 * 3600)); settle()
        check(m.updateNotice == nil, "updates: none once this app is that version")
        m.builderStamp = "1.0.0"
        d.removeObject(forKey: Prefs.updateLastCheck)
        m.checkUpdates = false; settle()
        m.checkForUpdates(now: t0.addingTimeInterval(80 * 3600)); settle()
        check(requests.count == 3 && m.updateNotice == nil, "updates: off makes no request and shows nothing")
        check(!LauncherModel().checkUpdates, "updates: off is kept")
        m.restoreOriginalGame()
        check(!m.checkUpdates, "updates: not a game option, Restore Original Game leaves it")
        m.fetchRelease = { url, done in requests.append(url); done(nil) }
        m.checkUpdates = true; settle()
        check(requests.count == 4 && m.updateNotice?.version == "1.2.0", "updates: on again asks; a failed answer changes nothing")
        // Check Now: asks at once, even right after a check, and says what it found
        m.checkForUpdatesNow(now: t0.addingTimeInterval(80 * 3600)); settle()
        check(requests.count == 5 && !m.updateChecking && m.updateStatus?.contains("could not be reached") == true
              && m.updateNotice?.version == "1.2.0", "updates: Check Now asks at once; a failed answer is said and changes nothing")
        m.fetchRelease = { url, done in requests.append(url); done(answer) }
        m.dismissUpdate()
        m.checkForUpdatesNow(now: t0.addingTimeInterval(80 * 3600)); settle()
        check(requests.count == 6 && m.updateNotice?.version == "1.2.0" && m.updateStatus?.contains("1.2.0 is available") == true,
              "updates: Check Now brings back a notice hidden with Not now")
        m.builderStamp = "1.2.0"
        m.checkForUpdatesNow(now: t0.addingTimeInterval(80 * 3600)); settle()
        check(requests.count == 7 && m.updateNotice == nil && m.updateStatus?.hasPrefix("Up to date") == true,
              "updates: Check Now says when this app is the newest")
        m.builderStamp = "1.0.0"; m.checkUpdates = false; settle()
        check(m.updateNotice == nil, "updates: off hides a notice Check Now found")
        let asked = requests.count
        m.checkForUpdatesNow(now: t0.addingTimeInterval(81 * 3600)); settle()
        check(requests.count == asked + 1 && m.updateNotice?.version == "1.2.0", "updates: Check Now works with the regular check off")
        m.builderStamp = nil
        m.checkForUpdatesNow(now: t0.addingTimeInterval(82 * 3600)); settle()
        check(requests.count == asked + 1, "updates: Check Now makes no request for an app no Builder made")
        m.builderStamp = "1.0.0"
        // a launcher left open asks again once two hours have passed, and not before
        m.checkUpdates = true; settle()
        let open = requests.count
        m.keepCheckingForUpdates(every: 0.02)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        check(requests.count == open, "updates: a launcher left open does not ask before two hours")
        d.set(Date().addingTimeInterval(-2 * 3600).timeIntervalSince1970, forKey: Prefs.updateLastCheck)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        check(requests.count == open + 1, "updates: a launcher left open asks once two hours have passed")
        m.keepCheckingForUpdates(every: 3600)

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
