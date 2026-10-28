// Launcher state and actions: find/check the game, start the engine, the tools.
import AppKit
import Darwin

// Counts are fetched only on request. Do not follow a server to another endpoint.
private final class CountsRequestDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class LauncherModel: ObservableObject {
    enum Engine: String { case original, hd }

    struct Job {
        var phase: String
        var done: Int64 = 0
        var total: Int64 = 0
        var result: URL? = nil
        var error: String? = nil
        var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    }

    @Published var game: GameState = .searching
    @Published var engine: Engine { didSet { defaults.set(engine.rawValue, forKey: Prefs.engine); engineForced = false } }
    private var engineForced = false     // NFSU2_ENGINE: this start only, not saved
    @Published var fullscreen: Bool { didSet { defaults.set(fullscreen, forKey: Prefs.fullscreen) } }
    @Published var showAtStartup: Bool { didSet { defaults.set(showAtStartup, forKey: Prefs.showAtStartup) } }
    @Published var job: Job? = nil
    @Published var notice: String? = nil
    @Published var online: Bool { didSet { defaults.set(online, forKey: Prefs.online); clearCounts() } }
    @Published var serverURL: String {
        didSet {
            defaults.set(serverURL, forKey: Prefs.serverURL)
            if countsURL == LaunchSettings.countsURL(for: oldValue) {
                countsURL = LaunchSettings.countsURL(for: serverURL)
            }
            clearCounts()
        }
    }
    @Published var countsURL: String { didSet { defaults.set(countsURL, forKey: Prefs.countsURL); clearCounts() } }
    @Published var playerName: String { didSet { defaults.set(playerName, forKey: Prefs.playerName) } }
    @Published var uiTextures: String { didSet { defaults.set(uiTextures, forKey: Prefs.uiTextures) } }
    @Published var texturePack: String { didSet { defaults.set(texturePack, forKey: Prefs.texturePack) } }
    @Published var counts: String? = nil
    @Published var countsError: String? = nil
    @Published var loadingCounts = false
    @Published var importingTextures = false
    @Published var runtimeOptions: RuntimeOptions {
        didSet { if let data = try? JSONEncoder().encode(runtimeOptions) { defaults.set(data, forKey: Prefs.runtimeOptions) } }
    }

    private let defaults = UserDefaults.standard
    private var builder: PortableBuilder?
    private var engineWatch: DispatchSourceProcess?
    var isPlaying: Bool { engineWatch != nil }
    var isCopying: Bool { builder != nil }
    private var quitWhenCopyStops = false
    private var countsTask: URLSessionDataTask?
    private var countsSession: URLSession?
    private var countsGeneration = 0

    /// Engines for the supported SPEED2.EXE.
    func hasEngine(_ e: Engine) -> Bool {
        FileManager.default.isExecutableFile(atPath: Paths.engine(location?.build, hd: e == .hd).path)
    }
    var canChooseEngine: Bool { hasEngine(.original) && hasEngine(.hd) }

    init() {
        let fm = FileManager.default
        let hasOriginal = fm.isExecutableFile(atPath: Paths.engine(nil, hd: false).path)
        let hasHD = fm.isExecutableFile(atPath: Paths.engine(nil, hd: true).path)
        defaults.register(defaults: [Prefs.showAtStartup: true])
        var e = Engine(rawValue: defaults.string(forKey: Prefs.engine) ?? "") ?? .original
        if let env = ProcessInfo.processInfo.environment["NFSU2_ENGINE"], let f = Engine(rawValue: env) { e = f }
        if e == .hd && !hasHD { e = .original }
        if e == .original && !hasOriginal && hasHD { e = .hd }
        engine = e
        engineForced = ProcessInfo.processInfo.environment["NFSU2_ENGINE"] != nil
        fullscreen = defaults.bool(forKey: Prefs.fullscreen)
        showAtStartup = defaults.bool(forKey: Prefs.showAtStartup)
        online = defaults.bool(forKey: Prefs.online)
        let savedServer = defaults.string(forKey: Prefs.serverURL) ?? LaunchSettings.defaultServer
        serverURL = savedServer
        countsURL = defaults.string(forKey: Prefs.countsURL) ?? LaunchSettings.countsURL(for: savedServer)
        playerName = defaults.string(forKey: Prefs.playerName) ?? ""
        uiTextures = defaults.string(forKey: Prefs.uiTextures) == "uhud" ? "uhud" : "original"
        texturePack = defaults.string(forKey: Prefs.texturePack) ?? ""
        runtimeOptions = defaults.data(forKey: Prefs.runtimeOptions)
            .flatMap { try? JSONDecoder().decode(RuntimeOptions.self, from: $0) } ?? RuntimeOptions()
    }

    var location: GameLocation? {
        switch game {
        case .ready(let l), .unsupported(let l, _): return l
        default: return nil
        }
    }
    var isReady: Bool { if case .ready = game { return true }; return false }
    var onlineError: String? { online ? LaunchSettings.onlineError(server: serverURL, name: playerName) : nil }
    var canPlay: Bool { isReady && onlineError == nil && runtimeError == nil && job == nil && !importingTextures }
    var installedLanguages: Set<String> { RuntimeOptions.installedLanguages(in: location?.folder) }
    var runtimeError: String? {
        do { _ = try runtimeOptions.environment() } catch { return error.localizedDescription }
        if isReady && !installedLanguages.contains(runtimeOptions.language) {
            return "That language is not installed in this game folder. Choose an installed language or add its language pack."
        }
        return nil
    }

    var textureStatus: String {
        if !texturePack.isEmpty {
            return FileManager.default.fileExists(atPath: texturePack)
                ? "Using the imported UHUD pack."
                : "Imported pack missing. Import it again or use the game folder."
        }
        if let folder = location?.folder,
           FileManager.default.fileExists(atPath: folder.appendingPathComponent("TEXPACKS/uhud.pak").path) {
            return "UHUD pack found in the game folder."
        }
        return "Choose a prepared uhud.pak, or place one in the game's TEXPACKS folder. Missing packs use the original textures."
    }

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
        if let error = onlineError { alert("Check the online settings", error); return }
        if let error = runtimeError { alert("Check the game settings", error); return }
        guard !importingTextures else { return }
        let env = ProcessInfo.processInfo.environment
        let fromEnv = !(env["NFSU2_DATA"] ?? "").isEmpty      // a one-off override: don't remember it
        if !loc.embedded && !fromEnv { defaults.set(loc.folder.path, forKey: Prefs.gameFolder) }
        if !engineForced { defaults.set(engine.rawValue, forKey: Prefs.engine) }
        defaults.synchronize()
        let child: [String: String]
        do {
            child = try LaunchSettings.environment(inherited: env, online: online, server: serverURL, name: playerName,
                textures: uiTextures, pack: texturePack.isEmpty ? nil : texturePack,
                data: loc.exe.path, saves: Paths.saves.path, registry: Paths.registry.path, runtime: runtimeOptions)
        } catch { alert("Check the launch settings", error.localizedDescription); return }
        var e = engine
        if !hasEngine(e) { e = (e == .hd) ? .original : .hd }
        let path = Paths.engine(loc.build, hd: e == .hd).path
        // A child process, not exec(): macOS attributes the child's file access to
        // this launcher (the "responsible" process), so folder permissions the
        // player granted here (Downloads, Documents...) are not asked for again.
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        var envp = child.keys.sorted().map { strdup("\($0)=\(child[$0]!)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        let rc = posix_spawn(&pid, path, nil, nil, &argv, &envp)
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

    // MARK: tools

    func showScreenshots() { PhotoGalleryWindow.show(folder: Paths.screenshots) }

    func manageSaves() {
        SaveManagerWindow.show(saves: Paths.saves, registry: Paths.registry,
            serverURL: serverURL, gameRunning: { [weak self] in self?.isPlaying ?? true })
    }

    func chooseMusicFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of music to play instead of the game soundtrack."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        var options = runtimeOptions
        options.musicFolder = folder.path; options.customMusic = true
        runtimeOptions = options
    }

    private func clearCounts() {
        countsGeneration += 1
        countsTask?.cancel(); countsTask = nil
        countsSession?.invalidateAndCancel(); countsSession = nil
        loadingCounts = false; counts = nil; countsError = nil
    }

    func refreshCounts() {
        guard online else { return }
        clearCounts()
        guard let url = LaunchSettings.countsEndpoint(countsURL) else {
            countsError = "Use https:// for player counts, or http:// with a loopback address."
            return
        }
        loadingCounts = true
        let generation = countsGeneration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = ["User-Agent": "NFSU2-Launcher", "Accept": "application/json"]
        let session = URLSession(configuration: config, delegate: CountsRequestDelegate(), delegateQueue: nil)
        countsSession = session
        countsTask = session.dataTask(with: url) { data, response, error in
            var result: String?, failure: String?
            do {
                if let error = error { throw error }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data = data, data.count <= 64_000 else {
                    throw SettingsError("The server did not return player counts.")
                }
                let counts = try JSONDecoder().decode(PlayerCounts.self, from: data)
                guard counts.valid else { throw SettingsError("The server returned invalid player counts.") }
                result = counts.summary
            } catch { failure = error.localizedDescription }
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async {
                guard self.countsGeneration == generation else { return }
                self.loadingCounts = false
                self.counts = result; self.countsError = failure
                self.countsTask = nil; self.countsSession = nil
            }
        }
        countsTask?.resume()
    }

    func importTextures() {
        let panel = NSOpenPanel()
        panel.title = "Import a Prepared UHUD Pack"
        panel.message = "Choose uhud.pak. A private copy is kept in Application Support; your game folder stays unchanged."
        panel.allowedFileTypes = ["pak"]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        importingTextures = true
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do { try TexturePack.install(from: source, to: Paths.importedTextures) }
            catch { failure = error.localizedDescription }
            DispatchQueue.main.async {
                self.importingTextures = false
                if let failure = failure { self.alert("Could not import the texture pack", failure); return }
                self.texturePack = Paths.importedTextures.path
                self.uiTextures = "uhud"
            }
        }
    }

    func openSaves() {
        try? FileManager.default.createDirectory(at: Paths.saves, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Paths.saves)
    }

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
        guard p.runModal() == .OK, var dest = p.url else { return }
        if dest.pathExtension.lowercased() != "app" { dest.appendPathExtension("app") }
        if dest.standardizedFileURL == Paths.bundle.standardizedFileURL {
            alert("Choose another name", "The copy can't replace the app that is running.")
            return
        }
        startPortable(from: loc.folder, to: dest)
    }

    func startPortable(from game: URL, to dest: URL) {
        let b = PortableBuilder(sourceApp: Paths.bundle, gameFolder: game, destination: dest)
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
