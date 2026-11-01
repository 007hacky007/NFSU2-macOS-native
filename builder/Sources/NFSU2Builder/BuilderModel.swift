import AppKit
import BuilderCore

/// Owns the checklist state, runs the pipeline commands and drives the build.
final class BuilderModel: ObservableObject {
    enum Phase: Equatable {
        case checklist
        case building(stepID: String, fraction: Double, log: [String])
        case finished(URL)
        case failed(step: String, message: String, log: [String])
        /// The build finished but NFSU2 is running; installing waits until the player quits it.
        case quitToInstall(built: URL)
    }

    @Published private(set) var states: [CheckID: CheckState]
    @Published private(set) var phase: Phase = .checklist
    @Published private(set) var dataChoice: [URL]
    @Published private(set) var programChoice: URL?
    @Published private(set) var destination: URL
    /// The NFSU2.app already in the destination: the build replaces it (an update).
    @Published private(set) var existingApp: InstalledApp? = nil
    /// True once Cancel was pressed or the app started installing, so Cancel can no longer act.
    @Published private(set) var cancelDisabled = false
    @Published private(set) var buildFilesRemoved = false
    /// A plain message shown as an alert over the checklist.
    @Published var notice: String?
    /// Output of the last failed build tools install, for Copy details.
    @Published private(set) var setupDetails: String?
    /// The data check's details (differing or missing files), for Copy details.
    @Published private(set) var dataDetails: String?
    /// Whether the "Which copy works?" sheet is open. Quitting closes it first.
    @Published var showingSupported = false
    /// The game data is the NFSU2.app found in the destination, offered by the Builder
    /// rather than chosen by the player.
    private var dataIsInstalledApp = false

    let paths = BuilderPaths()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
    private let sources = BuilderModel.findSources()
    private let defaults = UserDefaults.standard

    private var live: [ObjectIdentifier: PipelineRunner] = [:]
    private var idleHandlers: [() -> Void] = []
    private var shuttingDown = false
    private var workspaceReady = false
    private var installingTools = false
    private var downloadTask: URLSessionDownloadTask?
    private var downloadProgress: NSKeyValueObservation?
    private var cltTimer: Timer?

    private var dataReport: GameDataReport?
    private var playerChoseData = false
    /// An offered NFSU2.app whose game did not pass the checks: not offered again, and the
    /// empty game row says why.
    private var rejectedApp: URL?
    private var checkedData: [URL]?
    private var dataToken = UUID()
    private var programVerdict: ProgramVerdict?
    private var checkedProgram: URL?
    private var programToken = UUID()

    private var buildRunner: PipelineRunner?
    private var buildLog: [String] = []
    private var buildStep = ""
    private var stepPart = 0.0
    private var buildError: String?
    private var built: URL?
    private var userCancelled = false
    private var flushScheduled = false

    init() {
        states = Dictionary(uniqueKeysWithValues: CheckID.allCases.map { ($0, CheckState.checking("Checking...")) })
        let saved = UserDefaults.standard
        dataChoice = (saved.stringArray(forKey: "gameData") ?? []).map { URL(fileURLWithPath: $0) }
        programChoice = saved.string(forKey: "gameProgram").map { URL(fileURLWithPath: $0) }
        destination = saved.string(forKey: "destination").map { URL(fileURLWithPath: $0) } ?? defaultDestination
        // Game data given on the command line (-gameData, unattended test runs) counts as chosen.
        playerChoseData = saved.volatileDomain(forName: UserDefaults.argumentDomain)["gameData"] != nil
        offerInstalledApp()
    }

    // MARK: - Checklist

    /// Which view is showing, for window sizing.
    var phaseName: String {
        switch phase {
        case .checklist: return "checklist"
        case .building: return "building"
        case .finished: return "finished"
        case .failed: return "failed"
        case .quitToInstall: return "quit"
        }
    }

    var toolsReady: Bool { states[.buildTools]?.isReady == true }
    var buildEnabled: Bool { canBuild(states) }
    var programFromData: Bool { dataReport?.providesProgram == true }
    /// "Build NFSU2.app", or "Update NFSU2.app (1.0.0 -> 1.1.0)" when one is replaced.
    var buildTitle: String { buildButtonTitle(replacing: existingApp, version: version) }

    /// An NFSU2.app with the game inside, in the destination or else in /Applications, is the
    /// game data of an update: its game is checked like any other copy and cloned into the new
    /// app. A choice the player made in this session is kept.
    private func offerInstalledApp() {
        existingApp = InstalledApp.find(in: destination)
        let offered = [destination, defaultDestination].lazy.compactMap { InstalledApp.find(in: $0) }
            .first { $0.game != nil && $0.url != self.rejectedApp }
        if let app = offered, !playerChoseData {
            dataChoice = [app.url]
            dataIsInstalledApp = true
        } else if dataIsInstalledApp {
            dataChoice = (defaults.stringArray(forKey: "gameData") ?? []).map { URL(fileURLWithPath: $0) }
            dataIsInstalledApp = false
        }
    }

    func start() {
        refresh()
        prepare(sweep: true) { [self] _ in refreshBuildTools() }
        if defaults.bool(forKey: "AutoBuild") { startAutoBuild() }
    }

    /// Unattended runs (`open "NFSU2 Builder.app" --args -AutoBuild YES`, used to test a release):
    /// press Install for the build tools and then Build, once each, exactly as a player would,
    /// with the choices saved from an earlier run.
    private func startAutoBuild() {
        var installed = false, built = false
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self = self, self.phase == .checklist, !self.shuttingDown else { return }
            if self.states[.buildTools]?.isBlocked == true, !installed {
                installed = true
                self.installBuildTools()
            } else if self.buildEnabled, !built {
                built = true
                timer.invalidate()
                self.build()
            }
        }
    }

    /// Re-evaluates every row. Expensive checks (the game copy) only run again when their input changed.
    func refresh() {
        guard phase == .checklist, !shuttingDown else { return }
        states[.mac] = macCheck(isAppleSilicon: Self.isAppleSilicon, version: ProcessInfo.processInfo.operatingSystemVersion)
        refreshCommandLineTools()
        refreshBuildTools()
        refreshData()
        refreshProgram()
        refreshPlaces()
    }

    private func refreshBuildTools() {
        if workspaceReady && !installingTools {
            states[.buildTools] = buildToolsCheck(paths: paths, version: version)
        }
    }

    private func refreshCommandLineTools() {
        DispatchQueue.global(qos: .userInitiated).async {
            let state = CommandLineTools().state()
            DispatchQueue.main.async { [self] in
                states[.commandLineTools] = state
                if state.isReady { cltTimer?.invalidate(); cltTimer = nil }
            }
        }
    }

    func installCommandLineTools() {
        DispatchQueue.global(qos: .userInitiated).async { CommandLineTools().startInstall() }
        cltTimer?.invalidate()
        cltTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshCommandLineTools()
        }
    }

    /// The destination is only where NFSU2.app goes; the game goes inside the app.
    private func refreshPlaces() {
        existingApp = InstalledApp.find(in: destination)
        states[.destination] = destinationCheck(destination)
        states[.diskSpace] = diskSpaceState()
    }

    /// The build space on the workspace volume, plus the game data wherever it cannot be cloned
    /// (spaceNeeds): copied from another volume, unpacked from discs, or the finished app
    /// copied to a destination on another volume.
    private func diskSpaceState() -> CheckState {
        func existing(_ start: URL) -> URL {
            var url = start
            while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" { url = url.deletingLastPathComponent() }
            return url
        }
        guard let workspace = volumeID(paths.support) else { return .blocked("Could not read the free space on this disk") }
        let report = dataReport
        let needs = spaceNeeds(gameBytes: report?.bytes ?? 0, discs: report?.kind == .discs,
                               source: report?.sources.first.flatMap(volumeID), workspace: workspace,
                               destination: volumeID(destination))
        var shown: CheckState?
        for (volume, required) in needs.sorted(by: { ($0.key != workspace ? 1 : 0) < ($1.key != workspace ? 1 : 0) }) {
            let place = existing(volume == workspace ? paths.support : destination)
            let values = try? place.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeNameKey])
            guard let available = values?.volumeAvailableCapacityForImportantUsage else {
                return .blocked("Could not read the free space on this disk")
            }
            let state = diskSpaceCheck(available: available, required: required,
                                       disk: volume == workspace ? nil : values?.volumeName)
            if state.isBlocked { return state }
            if shown == nil { shown = state }
        }
        return shown ?? .blocked("Could not read the free space on this disk")
    }

    func setDestination(_ url: URL) {
        destination = url
        defaults.set(url.path, forKey: "destination")
        let before = dataChoice
        offerInstalledApp()
        if dataChoice != before { checkedData = nil; refreshData() }
        refreshPlaces()
    }

    // MARK: - Game data and program

    static func isProgramCandidate(_ url: URL) -> Bool {
        ProgramChecker.isArchive(url) || url.pathExtension.lowercased() == "exe"
    }

    /// Dropped or chosen files: a SPEED2.EXE or an archive goes to the program row, anything else to the data row.
    func choose(_ urls: [URL]) {
        guard phase == .checklist, !urls.isEmpty else { return }
        if urls.count == 1, Self.isProgramCandidate(urls[0]) {
            setProgram(urls[0])
        } else {
            setData(urls)
        }
    }

    func setData(_ urls: [URL]) {
        guard phase == .checklist else { return }
        dataIsInstalledApp = false
        playerChoseData = true
        dataChoice = urls
        defaults.set(urls.map { $0.path }, forKey: "gameData")
        checkedData = nil
        refreshData()
    }

    func setProgram(_ url: URL) {
        guard phase == .checklist else { return }
        programChoice = url
        defaults.set(url.path, forKey: "gameProgram")
        checkedProgram = nil
        refreshProgram()
    }

    private func refreshData() {
        guard !dataChoice.isEmpty else {
            (dataReport, dataDetails) = (nil, nil)
            let note = rejectedApp == nil ? "" : "The game inside your current NFSU2.app is incomplete or changed, so it cannot be used. "
            states[.gameData] = .blocked(note + "Choose your game folder, the two disc images (.iso, .cue or disc folders), or an NFSU2.app with the game inside")
            return updateProgramRow()
        }
        guard checkedData != dataChoice else { return }
        guard let manifestURL = sources?.appendingPathComponent("tools/known_releases.tsv"),
              let manifest = try? ReleaseManifest.load(manifestURL) else {
            states[.gameData] = .blocked("This copy of NFSU2 Builder is incomplete. Download it again.")
            return
        }
        let choice = dataChoice
        checkedData = choice
        let token = UUID()
        dataToken = token
        (dataReport, dataDetails) = (nil, nil)
        states[.gameData] = .checking("Checking your game copy...")
        updateProgramRow()
        DispatchQueue.global(qos: .userInitiated).async {
            let report = GameDataChecker(manifest: manifest).check(choice)
            DispatchQueue.main.async { [self] in
                guard dataToken == token else { return }
                if dataIsInstalledApp, report.blocking != nil || !report.providesProgram {
                    // The game in the current app is missing files or has another SPEED2.EXE:
                    // back to the player's own choice.
                    rejectedApp = choice.first
                    dataIsInstalledApp = false
                    dataChoice = (defaults.stringArray(forKey: "gameData") ?? []).map { URL(fileURLWithPath: $0) }
                    checkedData = nil
                    return refreshData()
                }
                dataReport = report
                states[.gameData] = report.state
                dataDetails = report.blocking == nil && report.notes.isEmpty ? nil : report.detailsText
                updateProgramRow()
                refreshPlaces()
            }
        }
    }

    private func refreshProgram() {
        guard let choice = programChoice else { return updateProgramRow() }
        guard checkedProgram != choice else { return updateProgramRow() }
        checkedProgram = choice
        programVerdict = nil
        let token = UUID()
        programToken = token
        updateProgramRow()
        let keep = paths.program
        DispatchQueue.global(qos: .userInitiated).async {
            let verdict = ProgramChecker().check(choice, keep: keep)
            DispatchQueue.main.async { [self] in
                guard programToken == token else { return }
                programVerdict = verdict
                updateProgramRow()
            }
        }
    }

    private func updateProgramRow() {
        if let found = dataReport?.program, case let .supported(_, name) = found {
            states[.gameProgram] = .ready("Found in your game data: \(name)")
            return
        }
        if programChoice != nil, programVerdict == nil {
            states[.gameProgram] = .checking("Checking \(programChoice?.lastPathComponent ?? "")...")
            return
        }
        switch programVerdict {
        case let .supported(_, name)?:
            states[.gameProgram] = .ready("\(name), from \(programChoice?.lastPathComponent ?? "your file")")
        case let .refused(message)?:
            states[.gameProgram] = .blocked(message)
        case nil:
            if case let .refused(message)? = dataReport?.program {
                states[.gameProgram] = .blocked("The SPEED2.EXE in your game data cannot be used. \(message) Choose that file, or an archive that holds it.")
            } else if dataReport == nil && !dataChoice.isEmpty {
                states[.gameProgram] = .checking("Checked with your game data")
            } else {
                states[.gameProgram] = .blocked("Choose SPEED2.EXE, or an archive (zip, rar or 7z) that holds it")
            }
        }
    }

    // MARK: - Build tools

    /// `sweep` (only on start, when nothing else uses the support folder) first deletes what an
    /// interrupted removal or copy left behind and, once the workspace is ready, old versions.
    private func prepare(sweep: Bool = false, _ completion: @escaping (Bool) -> Void) {
        if workspaceReady { return completion(true) }
        guard let sources = sources else {
            states[.buildTools] = .blocked("This copy of NFSU2 Builder is incomplete. Download it again.")
            return completion(false)
        }
        states[.buildTools] = .checking("Preparing build files...")
        let (paths, version) = (paths, version)
        DispatchQueue.global(qos: .userInitiated).async {
            if sweep { sweepLeftovers(paths) }
            let result = Result {
                try prepareWorkspace(sources: sources, destination: paths.workspace(version: version), version: version)
            }
            if sweep, case .success = result {
                DispatchQueue.global(qos: .utility).async { removeOldWorkspaces(paths, keeping: version) }
            }
            DispatchQueue.main.async { [self] in
                if case let .failure(error) = result {
                    states[.buildTools] = .blocked("Could not copy the build files: \(error.localizedDescription)")
                } else {
                    workspaceReady = true
                }
                completion(workspaceReady)
            }
        }
    }

    func installBuildTools() {
        guard !installingTools, !shuttingDown else { return }
        installingTools = true
        setupDetails = nil
        states[.buildTools] = .checking("Installing...")
        prepare { [self] ready in
            guard ready else { installingTools = false; return }
            if PythonRuntime.isInstalled(paths) { runSetup() } else { downloadPython() }
        }
    }

    private func downloadPython() {
        states[.buildTools] = .checking("Downloading Python...")
        PythonRuntime.install(paths, download: { url, done in
            let task = URLSession.shared.downloadTask(with: url) { file, response, error in
                if let file = file, (response as? HTTPURLResponse)?.statusCode == 200 {
                    done(.success(file))
                } else {
                    done(.failure(error ?? URLError(.badServerResponse)))
                }
            }
            var shown = -1
            downloadProgress = task.progress.observe(\.fractionCompleted) { progress, _ in
                let percent = Int(progress.fractionCompleted * 100)
                guard percent != shown else { return }
                shown = percent
                DispatchQueue.main.async { [self] in
                    guard downloadTask === task else { return }
                    states[.buildTools] = .checking(percent >= 100 ? "Unpacking Python..." : "Downloading Python, \(percent)%")
                }
            }
            downloadTask = task
            task.resume()
        }, completion: { [self] result in
            downloadTask = nil
            downloadProgress = nil
            switch result {
            case .success:
                runSetup()
            case let .failure(error):
                let text = error is URLError ? "Could not download Python. Check your internet connection and try again."
                    : Self.plain(error.localizedDescription)
                toolsFailed(text, details: String(describing: error))
            }
        })
    }

    private func runSetup() {
        states[.buildTools] = .checking("Setting up build tools...")
        var output: [String] = []
        var error: String?
        run(.setup(paths: paths, version: version), onEvent: { event in
            switch event {
            case let .log(line): output.append(line)
            case let .step(_, title): output.append(title)
            case let .error(message):
                error = message
                output.append("Error: \(message)")
            default: break
            }
        }, onExit: { [self] status in
            installingTools = false
            let details = (output + ["Setup exited with status \(status)."]).joined(separator: "\n")
            guard status == 0 else {
                let message = error.map(Self.plain)
                    ?? "Could not set up the build tools. Check your internet connection and try again."
                return toolsFailed(message, details: details)
            }
            refreshBuildTools()
            if !toolsReady { toolsFailed("The build tools are incomplete. Try again.", details: details) }
        })
    }

    private func toolsFailed(_ message: String, details: String? = nil) {
        installingTools = false
        setupDetails = details
        states[.buildTools] = .blocked(message)
    }

    // MARK: - Build

    func build() {
        guard phase == .checklist, buildEnabled, let report = dataReport, !shuttingDown else { return }
        if isGameRunning() {
            notice = "Quit NFSU2 first, then try again."
            return
        }
        var program = paths.program
        if report.providesProgram {
            program = ((try? FileManager.default.contentsOfDirectory(at: report.sources[0], includingPropertiesForKeys: nil)) ?? [])
                .first { $0.lastPathComponent.lowercased() == "speed2.exe" } ?? report.sources[0].appendingPathComponent("SPEED2.EXE")
        }
        let runner = PipelineRunner.build(paths: paths, version: version, program: program, data: report.sources)
        (buildLog, buildStep, stepPart, buildError, built) = ([], "", 0, nil, nil)
        (userCancelled, cancelDisabled) = (false, false)
        phase = .building(stepID: "", fraction: 0, log: [])
        buildRunner = runner
        run(runner, onEvent: { [self] event in
            switch event {
            case let .step(id, title):
                appendLog(title)
                if buildSteps.contains(where: { $0.id == id }) {
                    (buildStep, stepPart) = (id, 0)
                    flushLog()
                }
            case let .progress(part):
                stepPart = part
            case let .log(line): appendLog(line)
            case let .error(message):
                buildError = message
                appendLog("Error: \(message)")
            case let .done(app): built = app
            }
        }, onExit: { [self] status in
            buildRunner = nil
            if status != 0 { appendLog("The build exited with status \(status).") }
            if userCancelled || shuttingDown {
                phase = .checklist
                checkedData = nil
                return refresh()
            }
            if status == 0, buildError == nil, let built = built {
                install(built)
            } else {
                fail(step: buildStepNames[buildStep] ?? "Getting ready",
                     message: buildError ?? "The build stopped unexpectedly.")
            }
        })
    }

    func cancelBuild() {
        guard let runner = buildRunner else { return }
        userCancelled = true
        cancelDisabled = true
        appendLog("Cancelling...")
        runner.cancel()
    }

    /// Retries only the install of an already built app, after the player quit NFSU2.
    func installAgain() {
        guard case let .quitToInstall(built) = phase else { return }
        install(built)
    }

    private func install(_ built: URL) {
        cancelDisabled = true
        if case .quitToInstall = phase {
            guard !isGameRunning() else {
                notice = "NFSU2 is still running. Quit it, then click Install again."
                return
            }
            phase = .building(stepID: buildStep, fraction: 1, log: buildLog)
        } else if isGameRunning() {
            appendLog("NFSU2 is running, so the new build was not installed yet.")
            phase = .quitToInstall(built: built)
            return
        }
        appendLog("Installing NFSU2.app into \(destination.path)")
        flushLog()
        let directory = destination
        DispatchQueue.global(qos: .userInitiated).async {
            // Checked again here in case the game was started since; NSRunningApplication is thread safe.
            // The old app stays as it is until the new one is complete next to it.
            let result = Result { try installApp(built, into: directory, isRunning: isGameRunning) }
            DispatchQueue.main.async { [self] in
                switch result {
                case let .success(app):
                    buildFilesRemoved = false
                    phase = .finished(app)
                case let .failure(error as InstallError) where error.details == nil && isGameRunning():
                    appendLog(error.message)
                    phase = .quitToInstall(built: built)
                case let .failure(error):
                    if let details = (error as? InstallError)?.details { appendLog(details) }
                    fail(step: "Install", message: error.localizedDescription)
                }
            }
        }
    }

    private func fail(step: String, message: String) {
        phase = .failed(step: step, message: Self.plain(message), log: buildLog)
    }

    func tryAgain() {
        phase = .checklist
        checkedData = nil
        checkedProgram = nil
        refresh()
    }

    /// The workspace is renamed aside first, so quitting during the slow delete cannot leave a
    /// marked but incomplete workspace behind; the next start sweeps whatever is left.
    func removeBuildFiles() {
        let workspace = paths.workspace(version: version)
        workspaceReady = false
        if let trash = try? moveToTrash(workspace) {
            DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: trash) }
        }
        buildFilesRemoved = !FileManager.default.fileExists(atPath: workspace.path)
    }

    /// Lines arrive faster than SwiftUI should redraw, so they are published at most four times a second.
    private func appendLog(_ line: String) {
        buildLog.append(line)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in flushLog() }
    }

    private func flushLog() {
        flushScheduled = false
        guard case .building = phase else { return }
        let fraction = buildStep.isEmpty ? 0 : progressFraction(in: buildStep, part: stepPart)
        phase = .building(stepID: buildStep, fraction: fraction, log: buildLog)
    }

    // MARK: - Processes and shutdown

    var hasRunningWork: Bool { !live.isEmpty || downloadTask != nil }

    private func run(_ runner: PipelineRunner, onEvent: @escaping (PipelineEvent) -> Void,
                     onExit: @escaping (Int32) -> Void) {
        guard !shuttingDown else { return }
        let key = ObjectIdentifier(runner)
        live[key] = runner
        do {
            try runner.start(onEvent: onEvent, onExit: { [self] status in
                live[key] = nil
                onExit(status)
                notifyIfIdle()
            })
        } catch {
            live[key] = nil
            DispatchQueue.main.async {
                onEvent(.log(error.localizedDescription))
                onExit(-1)
            }
        }
    }

    /// Cancels every running command and calls `completion` once all of them have exited.
    func stopAll(then completion: @escaping () -> Void) {
        shuttingDown = true
        cltTimer?.invalidate()
        downloadTask?.cancel()
        downloadTask = nil
        idleHandlers.append(completion)
        live.values.forEach { $0.cancel() }
        notifyIfIdle()
    }

    private func notifyIfIdle() {
        guard live.isEmpty, !idleHandlers.isEmpty else { return }
        let handlers = idleHandlers
        idleHandlers = []
        handlers.forEach { $0() }
    }

    // MARK: - Helpers

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    /// The bundled sources. Only outside an app bundle (`swift run`) does it fall back to the
    /// repository the executable was built from.
    private static func findSources() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("BuildSources"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("build.sh").path) {
            return bundled
        }
        guard Bundle.main.bundleURL.pathExtension != "app",
              var url = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("build.sh").path) { return url }
        }
        return nil
    }

    /// Pipeline messages start in lower case; the window shows them as sentences.
    static func plain(_ message: String) -> String {
        message.prefix(1).uppercased() + message.dropFirst()
    }
}
