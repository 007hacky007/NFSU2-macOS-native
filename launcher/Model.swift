// Launcher state and actions: find/check the game, start the engine, the tools.
import AppKit
import Darwin

final class LauncherModel: ObservableObject {
    enum Engine: String { case original, hd }
    enum Reflections: String { case original, sharp, sharpest }
    enum FreeRoam: String { case off, solid, ghost }
    /// Horns between players (runtime/horn.c): the raw value is the engine's
    /// NFSU2_HORN name.  The PC game has no horn: off.
    enum Horn: String, CaseIterable {
        case off, dual, single, truck, train, klaxon, cucaracha, clown, trombone
        var label: String {
            switch self {
            case .off: return "Off (original)"
            case .dual: return "Dual"
            case .single: return "Single"
            case .truck: return "Truck"
            case .train: return "Train"
            case .klaxon: return "Klaxon"
            case .cucaracha: return "La Cucaracha"
            case .clown: return "Clown"
            case .trombone: return "Sad trombone"
            }
        }
    }

    struct Job {
        var phase: String
        var done: Int64 = 0
        var total: Int64 = 0
        var result: URL? = nil
        var error: String? = nil
        var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    }

    @Published var game: GameState = .searching {
        didSet {
            languages = Languages.installed(for: location)
            if location != nil && !languages.contains(language) { language = "english" }
        }
    }
    @Published var languages = ["english"]          // installed in the found game folder
    @Published var language: String { didSet { defaults.set(language, forKey: Prefs.language) } }
    @Published var engine: Engine { didSet { defaults.set(engine.rawValue, forKey: Prefs.engine); engineForced = false } }
    private var engineForced = false     // NFSU2_ENGINE: this start only, not saved
    @Published var fullscreen: Bool { didSet { defaults.set(fullscreen, forKey: Prefs.fullscreen) } }
    @Published var fpsCounter: Int { didSet { defaults.set(fpsCounter, forKey: Prefs.fpsCounter) } }
    @Published var metalHUD: Bool { didSet { defaults.set(metalHUD, forKey: Prefs.metalHUD) } }
    @Published var headlights: String { didSet { defaults.set(headlights, forKey: Prefs.headlights) } }
    @Published var showAtStartup: Bool { didSet { defaults.set(showAtStartup, forKey: Prefs.showAtStartup) } }
    @Published var wideHUD: Bool { didSet { defaults.set(wideHUD, forKey: Prefs.wideHUD) } }
    private var setHUDPOS = false        // HUDPOS was set by us (not by the caller)
    private var setLangPacks = false     // NFSU2_LANGPACKS was set by us
    @Published var allCars: Bool { didSet { defaults.set(allCars, forKey: Prefs.allCars) } }
    /// Settings › Check for updates (UpdateCheck.swift); off: no request, no notice.
    @Published var checkUpdates: Bool {
        didSet { defaults.set(checkUpdates, forKey: Prefs.checkUpdates); checkForUpdates() }
    }
    /// A newer NFSU2 Builder than the one that made this app: the main window's notice.
    @Published var updateNotice: UpdateCheck.Release?
    /// The Builder version this app was made with (nil: not made by a Builder, no check).
    var builderStamp: String? = UpdateCheck.stamp(of: Paths.bundle)
    /// How the latest release is asked for (tests put a fake one here).
    var fetchRelease: (URL, @escaping (Data?) -> Void) -> Void = UpdateCheck.fetch
    @Published var intro: String { didSet { defaults.set(intro, forKey: Prefs.intro) } }
    @Published var discord: Bool { didSet { defaults.set(discord, forKey: Prefs.discord) } }
    @Published var garage: Bool { didSet { defaults.set(garage, forKey: Prefs.garage) } }
    @Published var photoMode: Bool { didSet { defaults.set(photoMode, forKey: Prefs.photoMode) } }
    @Published var driftMode: Bool { didSet { defaults.set(driftMode, forKey: Prefs.driftMode) } }
    @Published var uhud: Bool { didSet { defaults.set(uhud, forKey: Prefs.uhud) } }
    @Published var uhudBusy = false
    @Published var uhudPhase = ""
    @Published var uhudError: String? = nil
    @Published var hasUHUDPack = false
    @Published var reflections: Reflections { didSet { defaults.set(reflections.rawValue, forKey: Prefs.reflections) } }
    @Published var reflectSky: Bool { didSet { defaults.set(reflectSky, forKey: Prefs.reflectSky) } }
    @Published var reflectLights: Bool { didSet { defaults.set(reflectLights, forKey: Prefs.reflectLights) } }
    @Published var reflectDetail: Bool { didSet { defaults.set(reflectDetail, forKey: Prefs.reflectDetail) } }
    /// PictureOptions.all[i] -> chosen index (0 = the original game).
    @Published var picture: [Int] { didSet { savePicture() } }
    let packs = TexturePackStore()       // Texture Packs (TexturePacks.swift)
    let upscaled = UpscaleStore()        // the upscaled texture pack (UpscaleStore.swift)
    @Published var upscaledTextures: Bool { didSet { defaults.set(upscaledTextures, forKey: Prefs.upscaled) } }
    let langPacks = LanguagePackStore()  // Settings › Mods › Languages (LanguagePackViews.swift)
    private var setTexpacks = false      // NFSU2_TEXPACKS was set by us
    @Published var frameRate: String { didSet { defaults.set(frameRate, forKey: Prefs.frameRate) } }
    @Published var cutscenes60: Bool { didSet { defaults.set(cutscenes60, forKey: Prefs.cutscenes60) } }
    @Published var cutsceneBars: Bool { didSet { defaults.set(cutsceneBars, forKey: Prefs.cutsceneBars) } }
    @Published var music: String { didSet { defaults.set(music, forKey: Prefs.music) } }             // Music.swift
    @Published var musicFolder: String { didSet { defaults.set(musicFolder, forKey: Prefs.musicFolder) } }
    // The Display card (DisplayOptions.swift)
    @Published var resolutionScale: String { didSet { defaults.set(resolutionScale, forKey: Prefs.resolutionScale) } }
    @Published var movieFraming: String { didSet { defaults.set(movieFraming, forKey: Prefs.movieFraming) } }
    @Published var subtitles: Bool { didSet { defaults.set(subtitles, forKey: Prefs.subtitles) } }
    @Published var background: String { didSet { defaults.set(background, forKey: Prefs.background) } }
    /// NFSU2_FPS values; the labels are in FrameRateCard.
    static let frameRates = ["auto", "30", "60", "120", "240", "uncapped"]
    @Published var seedRegistry: Bool { didSet { defaults.set(seedRegistry, forKey: Prefs.seedRegistry) } }   // EngineOptions.swift
    @Published var lanTiming: String { didSet { defaults.set(lanTiming, forKey: Prefs.lanTiming) } }
    @Published var discordImage: String { didSet { defaults.set(discordImage, forKey: Prefs.discordImage) } }   // DiscordImage.swift
    @Published var online: Bool { didSet { defaults.set(online, forKey: Prefs.online); recheckName() } }
    @Published var server: String {
        didSet {
            defaults.set(server, forKey: Prefs.server)
            // the player counts' address follows the server until it is set by hand
            if countsURL == PlayerCounts.address(for: oldValue) { countsURL = PlayerCounts.address(for: server) }
            counts.clear(); recheckName()
        }
    }
    @Published var countsURL: String { didSet { defaults.set(countsURL, forKey: Prefs.countsURL); counts.clear() } }
    let counts = PlayerCountsCheck()     // Check Player Counts (PlayerCounts.swift): nothing asked until pressed
    @Published var netStats: Bool { didSet { defaults.set(netStats, forKey: Prefs.netStats) } }   // Online statistics in the game
    @Published var playerName: String { didSet { defaults.set(playerName, forKey: Prefs.playerName); recheckName() } }
    /// Claimed names (NameClaims.swift): the name checked while Settings shows it and before Play
    lazy var names = NameClaimModel(defaults: defaults)
    func recheckName() { names.schedule(name: playerName, server: server, online: online) }
    @Published var freeRoam: FreeRoam { didSet { defaults.set(freeRoam.rawValue, forKey: Prefs.freeRoam) } }
    @Published var roamRoom: String { didSet { defaults.set(roamRoom, forKey: Prefs.roamRoom) } }
    @Published var roamCrew: String { didSet { defaults.set(roamCrew, forKey: Prefs.roamCrew) } }
    @Published var quickChat: Bool { didSet { defaults.set(quickChat, forKey: Prefs.quickChat) } }       // QuickChat.swift
    @Published var quickChatGroups: [String] { didSet { defaults.set(quickChatGroups, forKey: Prefs.quickChatGroups) } }
    @Published var quickChatPhrases: [Int] { didSet { defaults.set(quickChatPhrases, forKey: Prefs.quickChatPhrases) } }
    @Published var editingQuickChat = false
    let quickChatDraft = QuickChatDraft()
    @Published var horn: Horn { didSet { defaults.set(horn.rawValue, forKey: Prefs.horn) } }
    @Published var hearCars: Bool { didSet { defaults.set(hearCars, forKey: Prefs.hearCars) } }
    @Published var roamTuners: Bool { didSet { defaults.set(roamTuners, forKey: Prefs.roamTuners) } }   // RoamExtras.swift
    @Published var roamMapFilter: Bool { didSet { defaults.set(roamMapFilter, forKey: Prefs.roamMapFilter) } }
    var onlineError: String? {
        guard online else { return nil }
        if let e = OnlineSettings.error(server: server, name: playerName) { return e }
        if freeRoam != .off, let e = OnlineSettings.roomError(roamRoom) ?? OnlineSettings.crewError(roamCrew) { return e }
        return nil
    }
    @Published var controller: Bool { didSet { defaults.set(controller, forKey: Prefs.controller) } }
    @Published var stickDeadzone: Double { didSet { defaults.set(stickDeadzone, forKey: Prefs.stickDeadzone) } }
    @Published var padHotplug: Bool { didSet { defaults.set(padHotplug, forKey: Prefs.padHotplug) } }
    @Published var triggerDeadzone: Double { didSet { defaults.set(triggerDeadzone, forKey: Prefs.triggerDeadzone) } }
    @Published var triggerClick: Bool { didSet { defaults.set(triggerClick, forKey: Prefs.triggerClick) } }
    @Published var padMenuKeys: Bool { didSet { defaults.set(padMenuKeys, forKey: Prefs.padMenuKeys) } }
    @Published var padBackground: Bool { didSet { defaults.set(padBackground, forKey: Prefs.padBackground) } }
    private var setPad = false           // the NFSU2_PAD* variables were set by us
    @Published var rumble: Bool { didSet { defaults.set(rumble, forKey: Prefs.rumble) } }
    @Published var rumbleCrashes: Bool { didSet { defaults.set(rumbleCrashes, forKey: Prefs.rumbleCrashes) } }
    @Published var rumbleStrength: Double { didSet { defaults.set(rumbleStrength, forKey: Prefs.rumbleStrength) } }
    var setRumble = false                // the NFSU2_FF* variables were set by us (Rumble.swift)
    private static let padEnv = ["NFSU2_PAD", "NFSU2_PAD_DEADZONE", "NFSU2_PAD_TRIGGER_DEADZONE",
                                 "NFSU2_PAD_TRIGGER_CLICK", "NFSU2_PAD_FE_KEYS", "NFSU2_PAD_BACKGROUND"]
    @Published var job: Job? = nil
    @Published var notice: String? = nil
    // Data mods (DataMods.swift): which are turned on, what each one's row says while
    // it is being fetched or failed, and the overlay build in progress.
    @Published var modsOn: Set<String> { didSet { defaults.set(Array(modsOn).sorted(), forKey: Prefs.dataMods) } }
    @Published var modNote: [String: String] = [:]
    @Published var modBusy: Set<String> = []
    @Published var modsApplying: String? = nil
    @Published private(set) var modsHave: Set<String> = []
    let modStore: URL
    private var modsPending = false, playAfterMods = false

    private let defaults = UserDefaults.standard
    /// tests/launcher_settings.swift: play() hands the engine's path here instead of starting it.
    static var testSpawn: ((String) -> Void)?
    private var builder: PortableBuilder?
    private var engineWatch: DispatchSourceProcess?
    var isPlaying: Bool { engineWatch != nil }
    var isCopying: Bool { builder != nil }
    private var quitWhenCopyStops = false

    /// Engines for the found SPEED2.EXE (European ones until it is known).
    func hasEngine(_ e: Engine) -> Bool {
        FileManager.default.isExecutableFile(atPath: Paths.engine(location?.build, hd: e == .hd).path)
    }
    var canChooseEngine: Bool { hasEngine(.original) && hasEngine(.hd) }

    init() {
        let fm = FileManager.default
        let hasOriginal = fm.isExecutableFile(atPath: Paths.engine(nil, hd: false).path)
        let hasHD = fm.isExecutableFile(atPath: Paths.engine(nil, hd: true).path)
        defaults.register(defaults: [Prefs.checkUpdates: true, Prefs.showAtStartup: true, Prefs.allCars: true, Prefs.garage: true, Prefs.cutsceneBars: true, Prefs.controller: true, Prefs.stickDeadzone: 0.10, Prefs.triggerDeadzone: 0.02, Prefs.triggerClick: true, Prefs.padMenuKeys: true, Prefs.rumbleStrength: 1.0])
        var e = Engine(rawValue: defaults.string(forKey: Prefs.engine) ?? "") ?? .original
        if let env = ProcessInfo.processInfo.environment["NFSU2_ENGINE"], let f = Engine(rawValue: env) { e = f }
        if e == .hd && !hasHD { e = .original }
        if e == .original && !hasOriginal && hasHD { e = .hd }
        engine = e
        engineForced = ProcessInfo.processInfo.environment["NFSU2_ENGINE"] != nil
        language = defaults.string(forKey: Prefs.language) ?? "english"
        fullscreen = defaults.bool(forKey: Prefs.fullscreen)
        fpsCounter = min(max(defaults.integer(forKey: Prefs.fpsCounter), 0), 2)
        metalHUD = defaults.bool(forKey: Prefs.metalHUD)
        headlights = defaults.string(forKey: Prefs.headlights) ?? "players"
        showAtStartup = defaults.bool(forKey: Prefs.showAtStartup)
        wideHUD = defaults.bool(forKey: Prefs.wideHUD)
        allCars = defaults.bool(forKey: Prefs.allCars)
        checkUpdates = defaults.bool(forKey: Prefs.checkUpdates)
        intro = defaults.string(forKey: Prefs.intro) ?? "skippable"
        discord = defaults.bool(forKey: Prefs.discord)
        garage = defaults.bool(forKey: Prefs.garage)
        photoMode = defaults.bool(forKey: Prefs.photoMode)
        driftMode = defaults.bool(forKey: Prefs.driftMode)
        uhud = defaults.bool(forKey: Prefs.uhud)
        upscaledTextures = defaults.bool(forKey: Prefs.upscaled)
        hasUHUDPack = FileManager.default.fileExists(atPath: Paths.uhudPack.path)
        modsOn = Set(defaults.stringArray(forKey: Prefs.dataMods) ?? [])
        let st = ProcessInfo.processInfo.environment["NFSU2_MODS_STORE"] ?? ""
        modStore = st.isEmpty ? DataMods.defaultStore : URL(fileURLWithPath: st)
        reflections = Reflections(rawValue: defaults.string(forKey: Prefs.reflections) ?? "") ?? .original
        reflectSky = defaults.bool(forKey: Prefs.reflectSky)
        reflectLights = defaults.bool(forKey: Prefs.reflectLights)
        reflectDetail = defaults.bool(forKey: Prefs.reflectDetail)
        let d = UserDefaults.standard
        picture = PictureOptions.all.map { o in min(max(d.integer(forKey: o.key), 0), o.choices.count - 1) }
        let fr = defaults.string(forKey: Prefs.frameRate) ?? "auto"
        frameRate = LauncherModel.frameRates.contains(fr) ? fr : "auto"
        cutscenes60 = defaults.bool(forKey: Prefs.cutscenes60)
        seedRegistry = defaults.bool(forKey: Prefs.seedRegistry)
        lanTiming = defaults.string(forKey: Prefs.lanTiming) == "exact" ? "exact" : "pc"
        let di = defaults.string(forKey: Prefs.discordImage) ?? ""
        discordImage = DiscordImage.valid(di) ? di : ""
        cutsceneBars = defaults.bool(forKey: Prefs.cutsceneBars)
        music = defaults.string(forKey: Prefs.music) == "folder" ? "folder" : "game"
        musicFolder = defaults.string(forKey: Prefs.musicFolder) ?? ""
        resolutionScale = DisplayOptions.pick(defaults.string(forKey: Prefs.resolutionScale), DisplayOptions.scales, DisplayOptions.originalScale)
        movieFraming = DisplayOptions.pick(defaults.string(forKey: Prefs.movieFraming), DisplayOptions.framings, DisplayOptions.originalFraming)
        subtitles = defaults.bool(forKey: Prefs.subtitles)
        background = DisplayOptions.pick(defaults.string(forKey: Prefs.background), DisplayOptions.backgrounds, DisplayOptions.originalBackground)
        online = defaults.bool(forKey: Prefs.online)
        let savedServer = defaults.string(forKey: Prefs.server) ?? OnlineSettings.defaultServer
        server = savedServer
        countsURL = defaults.string(forKey: Prefs.countsURL) ?? PlayerCounts.address(for: savedServer)
        netStats = defaults.bool(forKey: Prefs.netStats)
        playerName = defaults.string(forKey: Prefs.playerName) ?? ""
        freeRoam = FreeRoam(rawValue: defaults.string(forKey: Prefs.freeRoam) ?? "") ?? .off
        roamRoom = defaults.string(forKey: Prefs.roamRoom) ?? ""
        roamCrew = defaults.string(forKey: Prefs.roamCrew) ?? ""
        quickChat = defaults.bool(forKey: Prefs.quickChat)
        quickChatGroups = QuickChat.groups(defaults.stringArray(forKey: Prefs.quickChatGroups))
        quickChatPhrases = QuickChat.phraseIDs(defaults.array(forKey: Prefs.quickChatPhrases) as? [Int])
        horn = Horn(rawValue: defaults.string(forKey: Prefs.horn) ?? "") ?? .off
        hearCars = defaults.bool(forKey: Prefs.hearCars)
        defaults.register(defaults: RoamExtras.defaults)
        roamTuners = defaults.bool(forKey: Prefs.roamTuners)
        roamMapFilter = defaults.bool(forKey: Prefs.roamMapFilter)
        controller = defaults.bool(forKey: Prefs.controller)
        stickDeadzone = min(0.5, max(0, defaults.double(forKey: Prefs.stickDeadzone)))
        padHotplug = defaults.bool(forKey: Prefs.padHotplug)
        triggerDeadzone = min(0.5, max(0, defaults.double(forKey: Prefs.triggerDeadzone)))
        triggerClick = defaults.bool(forKey: Prefs.triggerClick)
        padMenuKeys = defaults.bool(forKey: Prefs.padMenuKeys)
        padBackground = defaults.bool(forKey: Prefs.padBackground)
        rumble = defaults.bool(forKey: Prefs.rumble)
        rumbleCrashes = defaults.bool(forKey: Prefs.rumbleCrashes)
        rumbleStrength = min(1, max(0.1, defaults.double(forKey: Prefs.rumbleStrength)))
        packs.game = { [weak self] in self?.location?.folder }
        refreshMods()
    }

    private func savePicture() {
        for (o, i) in zip(PictureOptions.all, picture) { defaults.set(i, forKey: o.key) }
    }

    var location: GameLocation? {
        switch game {
        case .ready(let l), .unsupported(let l, _): return l
        default: return nil
        }
    }
    var hasAllRegionCars: Bool { Locator.hasAllRegionCars(location?.folder) }
    var isReady: Bool { if case .ready = game { return true }; return false }

    /// Synchronous: used once at startup, before deciding whether to show the window.
    func refreshNow() {
        game = Locator.locate().map(Locator.check) ?? .notFound
    }

    func refresh() {
        game = .searching
        DispatchQueue.global(qos: .userInitiated).async {
            let s = Locator.locate().map(Locator.check) ?? .notFound
            DispatchQueue.main.async { self.game = s }
        }
    }

    // MARK: game folder

    func chooseFolder() {
        // The game inside this app is the one it plays; there is no folder to change.
        if location?.embedded == true { return }
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Choose the Need for Speed Underground 2 folder (the one with SPEED2.EXE in it)."
        guard p.runModal() == .OK, let dir = p.url else { return }
        guard let exe = Locator.find(under: dir) else {
            alert("There is no SPEED2.EXE in this folder",
                  "Choose the folder where the game is installed. It contains SPEED2.EXE and folders such as CARS, TRACKS and SOUND.")
            return
        }
        defaults.set(exe.deletingLastPathComponent().path, forKey: Prefs.gameFolder)
        game = .searching
        DispatchQueue.global(qos: .userInitiated).async {
            let s = Locator.check(GameLocation(exe: exe, embedded: false))
            DispatchQueue.main.async { self.game = s }
        }
    }

    func revealGame() {
        guard let l = location else { return }
        NSWorkspace.shared.activateFileViewerSelecting([l.embedded ? Paths.bundle : l.exe])
    }

    // MARK: play

    func play() {
        guard case .ready(let loc) = game else { return }
        if let err = onlineError { alert("Online play is not set up", err); return }
        // a name another player claimed: asked about once (NameClaims.swift); not in the settings tests
        if online && LauncherModel.testSpawn == nil {
            switch names.gate(name: playerName, server: server, retry: { [weak self] in self?.play() }) {
            case .wait, .cancel: return
            case .rename(let alt): playerName = alt
            case .play: break
            }
        }
        let env = ProcessInfo.processInfo.environment
        // Data mods: their files must be built for this game folder first.
        let mods = activeMods
        if modsApplying != nil || (!mods.isEmpty && !DataMods.isBuilt(mods, game: loc.folder, store: modStore)) {
            playAfterMods = true
            if modsApplying == nil { applyMods() }
            return
        }
        if !mods.isEmpty { setenv("NFSU2_MODS", DataMods.overlay(modStore).path, 0) }
        let fromEnv = !(env["NFSU2_DATA"] ?? "").isEmpty      // a one-off override: don't remember it
        if !loc.embedded && !fromEnv { defaults.set(loc.folder.path, forKey: Prefs.gameFolder) }
        if !engineForced { defaults.set(engine.rawValue, forKey: Prefs.engine) }
        defaults.synchronize()
        if !fromEnv { setenv("NFSU2_DATA", loc.exe.path, 1) }
        // The language packs of a game inside the app are outside it (Paths.languagePacks).
        if loc.embedded { setenv("NFSU2_LANGPACKS", Paths.outsideLanguagePacks.path, 1); setLangPacks = true }
        else if setLangPacks { unsetenv("NFSU2_LANGPACKS"); setLangPacks = false }
        // HUD at the screen edges (engine: metal.m HUD ANCHORING).  A HUDPOS given by
        // the caller wins; otherwise it follows the switch.
        if setHUDPOS || env["HUDPOS"] == nil {
            if wideHUD { setenv("HUDPOS", "1", 1); setHUDPOS = true }
            else if setHUDPOS { unsetenv("HUDPOS"); setHUDPOS = false }
        }
        if !allCars { setenv("NFSU2_ALL_CARS", "0", 0) }          // one set by hand wins
        if intro != "skippable" { setenv("BOOTMOVIES", intro, 0) }       // one set by hand wins
        if headlights != "players" { setenv("NFSU2_HEADLIGHTS", headlights, 0) }   // one set by hand wins
        if discord { setenv("NFSU2_DISCORD", "1", 0) }          // one set by hand wins
        if discord && !discordImage.isEmpty && DiscordImage.valid(discordImage) { setenv("NFSU2_DISCORD_LARGE_IMAGE", discordImage, 0) }
        if !garage { setenv("NFSU2_GARAGE", "off", 0) }           // one set by hand wins
        if photoMode { setenv("NFSU2_PHOTO", "1", 0) }          // photo.c, native_scene.m; one set by hand wins
        if driftMode { setenv("NFSU2_DRIFT", "1", 0) }          // drift.c; one set by hand wins
        // Apple's Metal Performance HUD, drawn by macOS over the game's window (no engine
        // code).  The launcher quits with the game, so it never sticks to a later start.
        if metalHUD { setenv("MTL_HUD_ENABLED", "1", 0) }       // one set by hand wins
        // Texture Packs that are on, highest first (engine: runtime/texrep.m).  One given by
        // the caller wins; otherwise it follows the list.
        if setTexpacks || env["NFSU2_TEXPACKS"] == nil {
            let on = packs.enabledPaths
            if !on.isEmpty { setenv("NFSU2_TEXPACKS", on.joined(separator: ":"), 1); setTexpacks = true }
            else if setTexpacks { unsetenv("NFSU2_TEXPACKS"); setTexpacks = false }
        }
        upscaled.environment(on: upscaledTextures)       // the upscaled texture pack (texrep.m)
        if uhud && hasUHUDPack {
            setenv("NFSU2_UHUD", "on", 0)
            setenv("NFSU2_UHUD_PACK", Paths.uhudPack.path, 0)
        }
        // Reflections (engine: reflect.c).  A variable given by the caller wins.
        if reflections != .original { setenv("NFSU2_REFLECTIONS", reflections.rawValue, 0) }
        if reflectSky { setenv("NFSU2_REFLECT_SKY", "1", 0) }
        if reflectLights { setenv("NFSU2_REFLECT_LIGHTS", "1", 0) }
        if reflectDetail { setenv("NFSU2_REFLECT_DETAIL", "1", 0) }
        // Picture options: a variable set by hand still wins (overwrite 0).
        for (o, i) in zip(PictureOptions.all, picture) where i > 0 {
            setenv(o.env, o.choices[i].value, 0)
        }
        // Frame rate and cutscenes (engine: runtime/framerate.c, wsfov.c).  A variable
        // set by hand still wins (overwrite 0); the defaults need none.
        if frameRate != "auto" { setenv("NFSU2_FPS", frameRate, 0) }
        if cutscenes60 { setenv("NFSU2_CUTSCENES_60", "1", 0) }
        if !cutsceneBars { setenv("NFSU2_CUTSCENE_BORDERS", "off", 0) }
        applyMusic()                // a music folder through EA Trax (Music.swift)
        if seedRegistry { setenv("NFSU2_SEED_REGISTRY", "1", 0) }        // runtime/regseed.c
        if lanTiming != "pc" { setenv("NFSU2_LAN_TIMING", lanTiming, 0) }   // framerate.c
        // Resolution scale, movies and the background (runtime/display.c, language.c,
        // lifecycle.c); the original game's values set nothing.
        for (k, v) in DisplayOptions.environment(scale: resolutionScale, framing: movieFraming,
                                                 subtitles: subtitles, background: background) {
            setenv(k, v, 0)
        }
        // Online: the game's LAN and Online modes through the server (runtime/
        // net_relay.c, net_native.m).  Off: LAN on this Mac's network.  Values
        // set by hand in the environment win.
        if online {
            setenv("NFSU2_NET", "online", 0)
            setenv("NFSU2_ONLINE", "1", 0)
            setenv("NFSU2_SERVER_URL", server, 0)
            setenv("NFSU2_ROAM_NAME", playerName, 0)
            setenv("NFSU2_NET_NAME", playerName, 0)
            // Online statistics in a corner of the game (runtime/netstats.m): the connection, the
            // round trip and the server's player counts.  Off: no panel, as in the original game.
            if netStats { setenv("NFSU2_NET_STATS", "1", 0) }
        }
        // Free roam with other players, through the same server (runtime/roam.c,
        // roam_game.c).  Off: free roam as in the original game.
        if online && freeRoam != .off {
            setenv("NFSU2_ROAM", "1", 0)
            setenv("NFSU2_ROAM_COLLIDE", freeRoam == .solid ? "1" : "0", 0)
            setenv("NFSU2_ROAM_DISCOVERY", "0", 0)
            let room = roamRoom.trimmingCharacters(in: .whitespaces)
            let crew = roamCrew.trimmingCharacters(in: .whitespaces)
            if !room.isEmpty { setenv("NFSU2_ROAM_ROOM", room, 0) }
            if !crew.isEmpty { setenv("NFSU2_ROAM_CREW", crew, 0) }
            // the crews' colours as Game Tools picked them (runtime/native_controls.m)
            if !crew.isEmpty, let rgb = defaults.string(forKey: Prefs.roamCrewColours), OnlineSettings.validColours(rgb) {
                setenv("NFSU2_ROAM_CREW_RGB", rgb, 0)
            }
            // Quick chat (runtime/native_controls.m, roam_game.c say_*).  Off: 1-4 and
            // the right stick do what they do in the original game.
            if quickChat {
                setenv("NFSU2_ROAM_SAY", "1", 0)
                setenv("NFSU2_QUICKCHAT_GROUPS", quickChatGroups.joined(separator: ","), 0)
                setenv("NFSU2_QUICKCHAT_PHRASES", quickChatPhrases.map(String.init).joined(separator: ","), 0)
            }
            // The other players' engines, nitrous and hydraulics (runtime/carsfx.c).
            // Off: their cars sound as the game alone sounds them.
            if hearCars { setenv("NFSU2_ROAM_CARSFX", "1", 0) }
            // Later free-roam options (RoamExtras.swift): on in the engine unless set to 0.
            for (k, v) in RoamExtras.environment(tuners: roamTuners, mapFilter: roamMapFilter) { setenv(k, v, 0) }
        }
        // Horns between players in free roam and Online races (runtime/horn.c,
        // racehorn.c).  Off: no horn, as in the original game.
        if online && horn != .off { setenv("NFSU2_HORN", horn.rawValue, 0) }
        // Controller settings (Controller.swift); NFSU2_PAD* set by hand still win.  Ours
        // are overwritten on every Play, so a change takes effect without restarting.
        if setPad || LauncherModel.padEnv.allSatisfy({ env[$0] == nil }) {
            setenv("NFSU2_PAD", !controller ? "0" : padHotplug ? "hotplug" : "1", 1)
            setenv("NFSU2_PAD_DEADZONE", String(format: "%.2f", stickDeadzone), 1)
            setenv("NFSU2_PAD_TRIGGER_DEADZONE", String(format: "%.2f", triggerDeadzone), 1)
            setenv("NFSU2_PAD_TRIGGER_CLICK", triggerClick ? "0.97" : "off", 1)
            setenv("NFSU2_PAD_FE_KEYS", padMenuKeys ? "1" : "0", 1)
            setenv("NFSU2_PAD_BACKGROUND", padBackground ? "1" : "0", 1)
            setPad = true
        }
        setRumbleEnv(env)                       // Rumble.swift
        var e = engine
        if !hasEngine(e) { e = (e == .hd) ? .original : .hd }
        let path = Paths.engine(loc.build, hd: e == .hd).path
        setenv("NFSU2_LANGUAGE", language, 0)      // NFSU2_LANGUAGE set by hand still wins
        if let t = LauncherModel.testSpawn { t(path); return }      // tests/launcher_settings.swift: no engine
        // A child process, not exec(): macOS attributes the child's file access to
        // this launcher (the "responsible" process), so folder permissions the
        // player granted here (Downloads, Documents...) are not asked for again.
        // The claimed name's token (NameClaims.swift): through a pipe the engine reads once at start
        // (runtime/net_native.m), never in the environment or on the command line; written and its
        // write end closed before the engine starts.
        var claimFD: Int32 = -1
        unsetenv("NFSU2_CLAIM_FD")
        if online && names.playsWithClaim(server: server), let token = names.claimToken(server: server) {
            var fds: [Int32] = [-1, -1]
            if pipe(&fds) == 0 {
                let bytes = Array((token + "\n").utf8)
                let written = bytes.withUnsafeBytes { write(fds[1], $0.baseAddress, $0.count) }
                close(fds[1])
                if written == bytes.count { claimFD = fds[0]; setenv("NFSU2_CLAIM_FD", String(fds[0]), 1) } else { close(fds[0]) }
            }
        }
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        let rc = posix_spawn(&pid, path, nil, nil, &argv, environ)
        free(argv[0])
        if claimFD >= 0 { close(claimFD); unsetenv("NFSU2_CLAIM_FD") }
        guard rc == 0 else {
            alert("The game could not be started", "\(path)\n\n\(String(cString: strerror(rc)))")
            return
        }
        // When the engine ends, end with its exit status.  (Watch first: isPlaying
        // must be true before the window goes away.)
        let src = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        src.setEventHandler {
            var st: Int32 = 0
            waitpid(pid, &st, 0)
            let code = (st & 0x7f) == 0 ? (st >> 8) & 0xff : 128 + (st & 0x7f)
            exit(code)
        }
        src.resume()
        engineWatch = src
        // Step aside: no window, no Dock icon of our own; the engine has its own.
        for w in NSApp.windows { w.orderOut(nil) }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: data mods

    var activeMods: [DataMods.Mod] { DataMods.catalog.filter { modsOn.contains($0.id) && modsHave.contains($0.id) } }

    func refreshMods() {
        modsHave = Set(DataMods.catalog.filter { DataMods.source($0, modStore) != nil }.map { $0.id })
    }

    func setMod(_ m: DataMods.Mod, _ on: Bool) {
        if on { modsOn.insert(m.id) } else { modsOn.remove(m.id) }
        applyMods()
    }

    /// Download: from the mod's page, checked against the tested release; then turned on.
    func downloadMod(_ m: DataMods.Mod) {
        modBusy.insert(m.id)
        modNote[m.id] = "Downloading…"
        let store = modStore
        DispatchQueue.global(qos: .userInitiated).async {
            var err: String? = nil
            do {
                try DataMods.download(m, store: store) { n in
                    DispatchQueue.main.async {
                        self.modNote[m.id] = "Downloading… \(formatBytes(n)) of \(formatBytes(m.size))"
                    }
                }
            } catch let e as DataMods.Failure { err = e.message } catch { err = error.localizedDescription }
            DispatchQueue.main.async { self.modAdded(m, err) }
        }
    }

    /// Add File...: a copy of the mod the player already has (the archive or its folder).
    func importMod(_ m: DataMods.Mod) {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Add"
        p.message = "Choose the \(m.name) archive from nfsmods.xyz (or the folder it was extracted to)."
        guard p.runModal() == .OK, let u = p.url else { return }
        addModFile(m, u)
    }

    func addModFile(_ m: DataMods.Mod, _ u: URL) {
        modBusy.insert(m.id)
        modNote[m.id] = "Adding…"
        let store = modStore, game = location?.folder ?? URL(fileURLWithPath: "/")
        DispatchQueue.global(qos: .userInitiated).async {
            var err: String? = nil
            do { try DataMods.importCopy(u, as: m, game: game, store: store) }
            catch let e as DataMods.Failure { err = e.message } catch { err = error.localizedDescription }
            DispatchQueue.main.async { self.modAdded(m, err) }
        }
    }

    private func modAdded(_ m: DataMods.Mod, _ err: String?) {
        modBusy.remove(m.id)
        refreshMods()
        if let e = err { modNote[m.id] = e } else { modNote[m.id] = nil; modsOn.insert(m.id); applyMods() }
        if ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil {
            print(err.map { "mod \(m.id) FAILED: \($0)" } ?? "mod \(m.id) added")
            if err != nil { exit(1) }
        }
    }

    func removeMod(_ m: DataMods.Mod) {
        DataMods.remove(m, store: modStore)
        modNote[m.id] = nil
        modsOn.remove(m.id)
        refreshMods()
        applyMods()
    }

    func openModPage(_ m: DataMods.Mod) { NSWorkspace.shared.open(m.page) }

    /// (Re)builds the mod files for the turned-on mods, off the main thread.
    func applyMods() {
        guard let folder = location?.folder else { return }
        if modsApplying != nil { modsPending = true; return }
        let mods = activeMods, store = modStore
        if !mods.isEmpty && DataMods.isBuilt(mods, game: folder, store: store) { modsDone(nil); return }
        modsApplying = mods.isEmpty ? "Removing the mod files…" : "Applying mods…"
        DispatchQueue.global(qos: .userInitiated).async {
            var err: String? = nil
            do {
                try DataMods.build(mods, game: folder, store: store) { s in
                    DispatchQueue.main.async { self.modsApplying = s }
                }
            } catch let e as DataMods.Failure { err = e.message } catch { err = error.localizedDescription }
            DispatchQueue.main.async { self.modsDone(err) }
        }
    }

    private func modsDone(_ err: String?) {
        modsApplying = nil
        if let e = err {
            // the mod that failed is turned off again, with the reason in its row
            if let m = activeMods.first(where: { e.hasPrefix($0.name + ":") }) {
                modsOn.remove(m.id); modNote[m.id] = e
            } else { notice = "The mods could not be applied: \(e)" }
            playAfterMods = false
        }
        if modsPending { modsPending = false; applyMods(); return }
        if ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"]?.hasPrefix("mods") == true {
            print(err.map { "mods FAILED: \($0)" } ?? "mods applied: \(activeMods.map { $0.id }.joined(separator: ","))")
            exit(err == nil ? 0 : 1)
        }
        if playAfterMods && err == nil { playAfterMods = false; play() }
    }

    // MARK: tools

    func manageSaves() {
        SaveManagerWindow.show(saves: Paths.saves, registry: Paths.registry, server: server,
            gameRunning: { [weak self] in self?.isPlaying ?? true })
    }

    func showScreenshots() { PhotoGalleryWindow.show(folder: Paths.screenshots) }

    func openLogs() {
        try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Paths.logs)
    }

    func reportProblem() {
        NSWorkspace.shared.open(URL(string: "https://github.com/TalhaMudo/NFSU2Recomp/issues")!)
    }

    func resetGraphics() {
        let a = NSAlert()
        a.messageText = "Reset the graphics settings?"
        a.informativeText = "The next time it starts, the game picks graphics settings for this Mac again, as on its first start. Career saves are not affected."
        a.addButton(withTitle: "Reset")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try Registry.resetGraphics(); notice = "Graphics settings reset." }
        catch { alert("Could not reset the settings", error.localizedDescription) }
    }

    // MARK: UHUD

    /// Downloads the mod from nfsmods.xyz and makes the pack (the Download button).
    func downloadUHUD() {
        guard let loc = location else { return }
        makeUHUD(mod: nil, game: loc.folder)
    }

    /// The pack from the mod's archive (or its extracted folder), made in Application Support.
    func addUHUD() {
        guard let loc = location else { return }
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Add"
        p.message = "Choose the Upscaled HUD mod as downloaded from nfsmods.xyz (NFSU2UHUD11192022a.7z), or the folder it was extracted to. Your game folder stays as it is."
        p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let mod = p.url else { return }
        makeUHUD(mod: mod, game: loc.folder)
    }

    /// The pack from the mod's archive or folder, or (mod nil) from a download.
    func makeUHUD(mod: URL?, game: URL, to dest: URL = Paths.uhudPack) {
        uhudBusy = true
        uhudError = nil
        uhudPhase = mod == nil ? "Downloading the mod from nfsmods.xyz…" : "Making the pack from the mod…"
        DispatchQueue.global(qos: .userInitiated).async {
            var res: UHUDPack.Summary? = nil, err: String? = nil
            do {
                if let m = mod { res = try UHUDPack.make(mod: m, game: game, to: dest) }
                else {
                    res = try UHUDPack.download(game: game, to: dest) { got in
                        let text = got >= UHUDPack.archiveSize ? "Making the pack from the mod…"
                            : "Downloading the mod from nfsmods.xyz… \(formatBytes(got)) of \(formatBytes(UHUDPack.archiveSize))"
                        DispatchQueue.main.async { self.uhudPhase = text }
                    }
                }
            }
            catch let e as UHUDPack.Failure { err = e.message }
            catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                self.uhudBusy = false
                self.uhudError = err
                self.hasUHUDPack = FileManager.default.fileExists(atPath: Paths.uhudPack.path)
                if res != nil && dest == Paths.uhudPack { self.uhud = true }
                if ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil {
                    if let r = res {
                        print("uhud pack: \(r.textures) textures (\(r.shared) more share one), \(r.bytes) bytes -> \(dest.path)")
                        if !r.skipped.isEmpty { print("  skipped \(r.skipped.count): " + r.skipped.prefix(8).joined(separator: ", ")) }
                        exit(0)
                    }
                    print("uhud pack FAILED: \(err ?? "?")"); exit(1)
                }
            }
        }
    }

    /// Every option as in the original game (Prefs.originalGame)?
    var isOriginalGame: Bool { Prefs.originalGame.allSatisfy { $0.isSet(self) } }

    /// Settings › Restore Original Game.  Each option saves itself as it is set.
    func restoreOriginalGame() {
        for o in Prefs.originalGame { o.restore(self) }
    }

    func confirmRestoreOriginalGame() {
        let a = NSAlert()
        a.messageText = "Restore the original game?"
        a.informativeText = "Every option in Settings goes back to the value that gives the original, unmodified game. Full screen, the game folder, the game's own settings and career saves are not changed."
        a.addButton(withTitle: "Restore")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        restoreOriginalGame()
        notice = "Every option is back as in the original game."
    }

    // MARK: updates (UpdateCheck.swift)

    /// At most once a day, in the background, when on and the app has a Builder stamp; the
    /// newest release seen is kept, so the notice stays between the checks.
    func checkForUpdates(now: Date = Date()) {
        refreshUpdateNotice()
        guard checkUpdates, builderStamp != nil else { return }
        let last = (defaults.object(forKey: Prefs.updateLastCheck) as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        guard UpdateCheck.isDue(last: last, now: now) else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Prefs.updateLastCheck)
        fetchRelease(UpdateCheck.releasesAPI) { [weak self] data in
            let release = data.flatMap(UpdateCheck.parse)
            DispatchQueue.main.async {
                guard let self = self, let r = release else { return }
                self.defaults.set(["version": r.version, "page": r.page.absoluteString,
                                   "download": r.download?.absoluteString ?? ""], forKey: Prefs.updateLatest)
                self.refreshUpdateNotice()
            }
        }
    }

    private func refreshUpdateNotice() {
        guard checkUpdates, let stamp = builderStamp,
              let latest = defaults.dictionary(forKey: Prefs.updateLatest) as? [String: String],
              let version = latest["version"], let page = latest["page"].flatMap(URL.init(string:)),
              UpdateCheck.isNewer(version, than: stamp),
              defaults.string(forKey: Prefs.updateDismissed).map({ UpdateCheck.isNewer(version, than: $0) }) ?? true
        else { if updateNotice != nil { updateNotice = nil }; return }
        let release = UpdateCheck.Release(version: version, page: page,
                                          download: latest["download"].flatMap { $0.isEmpty ? nil : URL(string: $0) })
        if updateNotice != release { updateNotice = release }
    }

    /// Not now: hidden until a newer version than this one is out.
    func dismissUpdate() {
        guard let r = updateNotice else { return }
        defaults.set(r.version, forKey: Prefs.updateDismissed)
        refreshUpdateNotice()
    }

    func openUpdatePage() { if let r = updateNotice { NSWorkspace.shared.open(r.page) } }
    /// The disk image in the browser: a normal download the browser marks as such.
    func downloadUpdate() { if let r = updateNotice { NSWorkspace.shared.open(r.download ?? r.page) } }

    // MARK: portable copy

    func makePortable() {
        guard case .ready(let loc) = game else { return }
        let p = NSSavePanel()
        p.title = "Make a Portable Copy"
        p.message = "A copy of this app with the game files inside. It runs on its own, without the separate game folder. It contains the game, so keep it for yourself."
        p.prompt = "Make Copy"
        p.nameFieldStringValue = "NFSU2 Portable.app"
        p.canCreateDirectories = true
        p.isExtensionHidden = false
        p.directoryURL = FileManager.default.isWritableFile(atPath: "/Applications")
            ? URL(fileURLWithPath: "/Applications")
            : FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        // A checkbox for each optional folder the game has, all on: a full copy unless unticked.
        var boxes: [(String, NSButton)] = []
        let packs = loc.embedded ? Paths.outsideLanguagePacks : nil
        for (x, size) in PortableBuilder.extras(in: loc.folder, languagePacks: packs) {
            let b = NSButton(checkboxWithTitle: "Include " + x.title + " ("
                             + ByteCountFormatter.string(fromByteCount: size, countStyle: .file) + ")",
                             target: nil, action: nil)
            b.toolTip = "Without: " + x.without + "."
            b.state = .on
            b.sizeToFit()
            boxes.append((x.folder, b))
        }
        if !boxes.isEmpty {
            let h = boxes.reduce(CGFloat(16)) { $0 + $1.1.frame.height + 6 }
            let w = boxes.map { $0.1.frame.width }.max()! + 40
            let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            var y = h - 8
            for (_, b) in boxes {
                y -= b.frame.height
                b.setFrameOrigin(NSPoint(x: 20, y: y))
                y -= 6
                v.addSubview(b)
            }
            p.accessoryView = v
        }
        guard p.runModal() == .OK, var dest = p.url else { return }
        if dest.pathExtension.lowercased() != "app" { dest.appendPathExtension("app") }
        if dest.standardizedFileURL == Paths.bundle.standardizedFileURL {
            alert("Choose another name", "The copy can't replace the app that is running.")
            return
        }
        startPortable(from: loc.folder, to: dest, leaveOut: Set(boxes.filter { $0.1.state == .off }.map { $0.0 }),
                      languagePacks: packs)
    }

    func startPortable(from game: URL, to dest: URL, leaveOut: Set<String> = [], languagePacks: URL? = nil) {
        let b = PortableBuilder(sourceApp: Paths.bundle, gameFolder: game, destination: dest, leaveOut: leaveOut,
                                languagePacks: languagePacks)
        builder = b
        job = Job(phase: "Starting…")
        DispatchQueue.global(qos: .userInitiated).async {
            var res: URL? = nil, err: String? = nil
            do {
                res = try b.build { pr in
                    DispatchQueue.main.async {
                        guard self.job?.result == nil, self.job?.error == nil else { return }
                        self.job = Job(phase: pr.phase, done: pr.done, total: pr.total)
                    }
                }
            } catch PortableBuilder.Failure.cancelled {
                err = nil
            } catch PortableBuilder.Failure.noSpace(let need, let free) {
                err = "Not enough free space: \(formatBytes(need)) needed, \(formatBytes(free)) free."
            } catch PortableBuilder.Failure.step(let s) {
                err = s
            } catch {
                err = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.builder = nil
                if self.quitWhenCopyStops { NSApp.reply(toApplicationShouldTerminate: true); return }
                if res == nil && err == nil { self.job = nil; return }    // cancelled
                var j = self.job ?? Job(phase: "")
                j.result = res; j.error = err
                if res != nil { j.done = j.total }
                self.job = j
                if let r = res, ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil {
                    print("portable copy: \(r.path)"); NSApp.terminate(nil)
                }
                if let e = err, ProcessInfo.processInfo.environment["NFSU2_LAUNCHER_TEST"] != nil {
                    print("portable copy FAILED: \(e)"); exit(1)
                }
            }
        }
    }

    func cancelPortable() { builder?.cancel() }

    /// Quitting while a copy is being made: stop it (the half-made copy is
    /// removed) and quit once the copy thread has cleaned up.
    func shouldTerminate() -> NSApplication.TerminateReply {
        guard isCopying else { return .terminateNow }
        let a = NSAlert()
        a.messageText = "A portable copy is being made"
        a.informativeText = "Quitting stops it; the unfinished copy is removed."
        a.addButton(withTitle: "Keep Copying")
        a.addButton(withTitle: "Stop and Quit")
        guard a.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        quitWhenCopyStops = true
        builder?.cancel()
        return .terminateLater
    }
    func closeJob() { job = nil }
    func revealResult() {
        if let r = job?.result { NSWorkspace.shared.activateFileViewerSelecting([r]) }
        job = nil
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
