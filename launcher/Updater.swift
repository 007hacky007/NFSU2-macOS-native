// Update: the notice's button for a newer NFSU2 Builder (UpdateCheck.swift) updates this app
// with no one pressing anything in the Builder, and the launcher shows it all in one progress
// bar.  Play waits until it is done.
//
//   1. download NFSU2-Builder.dmg from the release, and its .sha256; the image must match it
//   2. mount it (hidden, read-only, in a temporary folder) and check it holds NFSU2 Builder of
//      that version
//   3. run that Builder in the background, with no window, as
//      NFSU2Builder -LauncherUpdate <status file> -destination <this app's folder> -gameData '("<this app>")'
//      It sets up its tools and builds from the game inside this app; each line it prints is
//      JSON: where it is (the bar and the step), or a line of its log
//      (builder/Sources/BuilderCore/LauncherUpdate.swift)
//   4. built, it waits for NFSU2 to quit (an app it replaces must not run): the launcher quits,
//      the Builder installs the new NFSU2.app, opens it and quits
//   5. the new launcher finds the update in its preferences (Prefs.updateRun): once the Builder
//      has quit it unmounts the image, deletes the download and says the update is done
//
// When the Builder's checklist has a red row it cannot see to by itself (only the build tools
// it installs on its own: the command line tools, the game, the disk space are the player's),
// it stops and says which; the launcher lists them and offers to open the Builder's window
// from the image, where the player sees the checklist and finishes the update by hand.
// A failed step says which and why, in the Builder's words, with Copy Log.
//
// Quitting the launcher during 3 leaves the Builder to finish: it installs and opens NFSU2 by
// itself, and a launcher opened meanwhile follows it again (its status file).  Cancel and
// Close end with the image unmounted and the download deleted.
import AppKit
import CryptoKit

final class Updater {
    static let builderID = "org.nfsu2.builder"
    static let builderName = "NFSU2 Builder.app"

    /// What the overlay shows (Views.swift UpdateOverlay).
    struct Run: Equatable {
        var version: String
        var text: String
        var fraction: Double = 0
        var detail: String? = nil
        /// Why it stopped, in plain words.
        var failure: String? = nil
        /// The Builder's red rows, one "Row: what it says" a line: only the player can see to them.
        var needsBuilder: String? = nil
        /// Finished by hand in the Builder's window.
        var inBuilder = false
        /// Updated: the overlay says so until OK.
        var finished = false
        var canCancel = false
        /// The Builder printed a log: Copy Log.
        var hasLog = false
        /// The image is still mounted: Open NFSU2 Builder.
        var canOpenBuilder = false
    }

    /// The overlay's state; nil: no update.  Set on the main queue.
    var onChange: (Run?) -> Void = { _ in }
    private(set) var run: Run? { didSet { if run != oldValue { onChange(run) } } }
    /// Quits the launcher so the Builder can replace the app (tests: something else).
    var quit: () -> Void = { NSApp.terminate(nil) }
    /// The Builder version this app was made with, to tell a finished update from one that was not.
    var stamp: () -> String? = { UpdateCheck.stamp(of: Paths.bundle) }

    private let defaults: UserDefaults
    private var session: URLSession?
    private var progress: NSKeyValueObservation?
    private var timer: Timer?
    private var quitting = false
    private var cancelled = false
    private var builder: Builder?
    private var app: URL = Paths.bundle
    private var lineBuffer = ""
    /// OK pressed on Updated while the Builder's window still runs: its quitting is not news.
    private var acknowledged = false
    /// The Builder's log, for Copy Log (the last lines; a build prints a few thousand).
    private(set) var log: [String] = []

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// An update in progress, kept across the launcher quitting for the install.
    struct Record: Equatable {
        var version: String
        var folder: URL           // the download, the mount point and the status file
        var pid: pid_t = 0        // the Builder, once it runs
        var window = false        // that Builder is its window (finished by hand)
        var mount: URL { folder.appendingPathComponent("mount") }
        var image: URL { folder.appendingPathComponent("NFSU2-Builder.dmg") }
        var status: URL { folder.appendingPathComponent("status.json") }
        var builder: URL { mount.appendingPathComponent(Updater.builderName) }

        var dictionary: [String: Any] { ["version": version, "folder": folder.path, "pid": Int(pid), "window": window] }
        init(version: String, folder: URL, pid: pid_t = 0, window: Bool = false) {
            (self.version, self.folder, self.pid, self.window) = (version, folder, pid, window)
        }
        init?(_ d: [String: Any]?) {
            guard let d = d, let v = d["version"] as? String, let f = d["folder"] as? String, !f.isEmpty else { return nil }
            self.init(version: v, folder: URL(fileURLWithPath: f), pid: pid_t((d["pid"] as? Int) ?? 0), window: (d["window"] as? Bool) ?? false)
        }
    }

    private var record: Record? {
        get { Record(defaults.dictionary(forKey: Prefs.updateRun)) }
        set { if let r = newValue { defaults.set(r.dictionary, forKey: Prefs.updateRun) } else { defaults.removeObject(forKey: Prefs.updateRun) } }
    }

    /// The launcher must not play by itself on opening (NFSU2_SKIP_LAUNCHER).
    var pending: Bool { record != nil }

    /// The Builder: run by this launcher in the background, its window, or one an earlier
    /// launcher started (known by its process id).
    private struct Builder {
        var process: Process? = nil
        var app: NSRunningApplication? = nil
        var pid: pid_t
        var alive: Bool {
            if let p = process { return p.isRunning }
            if let a = app { return !a.isTerminated }
            return Updater.isBuilder(pid)
        }
        func stop() {
            if let p = process { p.terminate() } else if let a = app { a.terminate() } else { kill(pid, SIGTERM) }
        }
    }

    /// A running NFSU2 Builder from an update's image (a process id can be another program's later).
    static func isBuilder(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        return String(cString: path).contains("/mount/\(builderName)/")
    }

    // MARK: the Builder's progress, as one bar

    /// Where each part of the update ends on the bar: the download is quick, the build is most of it.
    static func fraction(state: String, part: Double) -> Double {
        let p = max(0, min(1, part))
        switch state {
        case "download": return 0.10 * p
        case "open": return 0.11
        case "preparing": return 0.12
        case "tools": return 0.15
        case "building": return 0.18 + 0.77 * p
        case "waiting", "installing": return 0.96
        case "done": return 0.98
        default: return 0
        }
    }

    /// The first word of a `shasum -a 256` line, when it is a SHA-256.
    static func checksum(in text: String) -> String? {
        guard let word = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first else { return nil }
        let hex = word.lowercased()
        return hex.count == 64 && hex.allSatisfy({ $0.isHexDigit }) ? hex : nil
    }

    /// The arguments the Builder is run with (BuilderModel.swift reads -destination and
    /// -gameData; -LauncherUpdate makes it the background update, LauncherUpdateCLI.swift).
    static func builderArguments(app: URL, status: URL?) -> [String] {
        let quoted = "\"" + app.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return (status.map { ["-LauncherUpdate", $0.path] } ?? []) + ["-destination", app.deletingLastPathComponent().path, "-gameData", "(\(quoted))"]
    }

    /// What the Builder gets of the launcher's environment: only what any program needs (none
    /// of the NFSU2_ variables the launcher may have been started with).
    static func builderEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        env.filter { ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "SHELL"].contains($0.key) }
    }

    // MARK: start

    /// Update pressed.  `app` is this NFSU2.app, replaced in its folder.
    func start(_ release: UpdateCheck.Release, app: URL = Paths.bundle) {
        guard run == nil, record == nil else { return }
        guard let image = release.download, let sum = release.checksum else { return }
        (cancelled, quitting, acknowledged, log, self.app) = (false, false, false, [], app)
        if !NSRunningApplication.runningApplications(withBundleIdentifier: Self.builderID).isEmpty {
            run = Run(version: release.version, text: "", failure: "NFSU2 Builder is open. Quit it, then click Update again.")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NFSU2-Update-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            run = Run(version: release.version, text: "", failure: "The update could not be downloaded: \(error.localizedDescription)")
            return
        }
        let rec = Record(version: release.version, folder: folder)
        record = rec
        run = Run(version: release.version, text: "Downloading NFSU2 Builder \(release.version)", canCancel: true)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": UpdateCheck.userAgent]
        let session = URLSession(configuration: config)
        self.session = session
        session.dataTask(with: sum) { [weak self] data, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 200) == 200
            let digest = ok ? data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Self.checksum(in:)) : nil
            DispatchQueue.main.async {
                guard let self = self, !self.cancelled else { return }
                guard let digest = digest else { return self.fail("The update could not be downloaded. Check your internet connection and try again.") }
                self.download(image, digest: digest, record: rec, session: session)
            }
        }.resume()
    }

    private func download(_ url: URL, digest: String, record rec: Record, session: URLSession) {
        let task = session.downloadTask(with: url) { [weak self] file, response, error in
            // the file goes when this returns: move it first
            var saved = false
            if let file = file, error == nil, ((response as? HTTPURLResponse)?.statusCode ?? 200) == 200 {
                saved = (try? FileManager.default.moveItem(at: file, to: rec.image)) != nil
            }
            DispatchQueue.main.async {
                guard let self = self, !self.cancelled else { return }
                self.progress = nil
                guard saved else { return self.fail("The update could not be downloaded. Check your internet connection and try again.") }
                self.open(rec, digest: digest)
            }
        }
        progress = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let (done, total) = (task.countOfBytesReceived, task.countOfBytesExpectedToReceive)
            DispatchQueue.main.async {
                guard let self = self, var r = self.run, r.failure == nil, r.text.hasPrefix("Downloading") else { return }
                r.fraction = Self.fraction(state: "download", part: p.fractionCompleted)
                r.detail = total > 0 ? "\(formatBytes(done)) of \(formatBytes(total))" : nil
                self.run = r
            }
        }
        task.resume()
    }

    /// Checks the image, mounts it and runs the Builder in it (the slow parts off the main queue).
    private func open(_ rec: Record, digest: String) {
        update(text: "Checking the download", fraction: Self.fraction(state: "open", part: 0), detail: nil)
        let version = rec.version
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () throws -> URL in
                guard (try? Self.sha256(of: rec.image)) == digest else { throw UpdateError("The download did not match its checksum, so it was not used. Try again later.") }
                let attach = Self.hdiutil(["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", rec.mount.path, rec.image.path])
                guard attach.status == 0 else { throw UpdateError("The download could not be opened: \(attach.output)") }
                let info = NSDictionary(contentsOf: rec.builder.appendingPathComponent("Contents/Info.plist"))
                guard info?["CFBundleIdentifier"] as? String == Self.builderID,
                      info?["CFBundleShortVersionString"] as? String == version,
                      let exe = info?["CFBundleExecutable"] as? String
                else { throw UpdateError("The download does not hold NFSU2 Builder \(version).") }
                return rec.builder.appendingPathComponent("Contents/MacOS/\(exe)")
            }.mapError { $0 as? UpdateError ?? UpdateError($0.localizedDescription) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.cancelled { self.run = nil; return self.cleanUp(rec) }
                switch result {
                case let .failure(e): self.fail(e.message)
                case let .success(exe): self.runInBackground(exe, record: rec)
                }
            }
        }
    }

    /// Step 3: the Builder with no window; its output is the bar, the step and the log.
    private func runInBackground(_ exe: URL, record rec: Record) {
        update(text: "Starting NFSU2 Builder \(rec.version)", fraction: Self.fraction(state: "open", part: 0), detail: nil)
        let p = Process()
        p.executableURL = exe
        p.arguments = Self.builderArguments(app: app, status: rec.status)
        p.environment = Self.builderEnvironment()
        p.currentDirectoryURL = rec.folder
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            DispatchQueue.main.async { self?.received(data) }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                out.fileHandleForReading.readabilityHandler = nil
                self?.received(out.fileHandleForReading.readDataToEndOfFile())
                self?.ended(status, record: rec)
            }
        }
        do { try p.run() } catch {
            return fail("NFSU2 Builder could not be started: \(error.localizedDescription)")
        }
        var r = rec
        r.pid = p.processIdentifier
        record = r
        builder = Builder(process: p, pid: r.pid)
        run?.canCancel = true
    }

    private func received(_ data: Data) {
        guard !data.isEmpty else { return }
        lineBuffer += String(decoding: data, as: UTF8.self)
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<nl])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
            handle(line: line)
        }
    }

    /// One line the Builder printed: its log, or where it is.
    func handle(line: String) {
        guard !line.isEmpty else { return }
        guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return addLog(line) }
        if let l = o["log"] as? String { return addLog(l) }
        guard let state = o["state"] as? String else { return addLog(line) }
        apply(state: state, fraction: (o["fraction"] as? Double) ?? 0, text: (o["text"] as? String) ?? "", message: o["message"] as? String)
    }

    private func addLog(_ line: String) {
        log.append(line)
        if log.count > 4000 { log.removeFirst(log.count - 3000) }
        if run?.hasLog == false { run?.hasLog = true }
    }

    private func apply(state: String, fraction: Double, text: String, message: String?) {
        guard var r = run, r.failure == nil, r.needsBuilder == nil, !r.finished else { return }
        r.canCancel = !cancelled
        switch state {
        case "failed":
            r.failure = message ?? "NFSU2 Builder stopped."
            r.canCancel = false
        case "needsBuilder":
            r.needsBuilder = message ?? ""
            r.canCancel = false
        case "waiting", "installing":
            r.text = "Installing the new NFSU2.app. NFSU2 opens again by itself."
            r.fraction = Self.fraction(state: "waiting", part: 0)
            r.detail = nil
            r.canCancel = false
            if !quitting {
                quitting = true
                run = r
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.quit() }
            }
        case "done":
            r.text = "Finishing the update"
            r.fraction = Self.fraction(state: "done", part: 0)
            r.canCancel = false
        default:
            r.text = state == "building" ? "Building: \(text)" : text
            r.fraction = max(r.fraction, Self.fraction(state: state, part: fraction))
            r.detail = state == "building" ? "NFSU2 Builder \(r.version) is making the new app; this takes a few minutes." : nil
        }
        if cancelled { r.text = "Stopping the update" }
        run = r
    }

    /// The background Builder has exited.
    private func ended(_ status: Int32, record rec: Record) {
        builder = nil
        guard var r = run else { return cleanUp(rec) }
        if cancelled { run = nil; return cleanUp(rec) }
        if r.finished { return }
        if status == 0 && !quitting { return finish(rec) }
        if r.failure == nil && r.needsBuilder == nil {
            r.failure = "NFSU2 Builder stopped unexpectedly (exit status \(status))."
        }
        // the image stays mounted for Open NFSU2 Builder until Close
        r.canCancel = false
        r.canOpenBuilder = FileManager.default.fileExists(atPath: rec.builder.path)
        var kept = rec
        kept.pid = 0
        record = kept
        run = r
    }

    // MARK: following a Builder this launcher did not start (or its window)

    /// On opening: an update this launcher (or the one before it) started.
    func resume() {
        guard let rec = record, run == nil else { return }
        // quit while downloading: the Builder never got it
        guard rec.pid != 0, Self.isBuilder(rec.pid) else { return finish(rec) }
        builder = Builder(pid: rec.pid)
        if rec.window {
            if stamp() == rec.version {
                run = Run(version: rec.version, text: "", fraction: 1, finished: true)
            } else {
                run = Run(version: rec.version, text: "", inBuilder: true)
            }
        } else {
            run = Run(version: rec.version, text: "Finishing the update", fraction: Self.fraction(state: "done", part: 0), canCancel: true)
        }
        watch(rec)
    }

    /// Twice a second: whether the Builder still runs and, in the background, its status file.
    private func watch(_ rec: Record) {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick(rec) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick(rec)
    }

    private func tick(_ rec: Record) {
        guard let b = builder, b.alive else {
            timer?.invalidate(); timer = nil
            builder = nil
            if cancelled { run = nil; cleanUp(rec) } else { finish(rec) }
            return
        }
        if !rec.window, let data = try? Data(contentsOf: rec.status), let line = String(data: data, encoding: .utf8) {
            handle(line: line)
        }
    }

    /// The Builder has quit: the image goes, and the overlay says how it ended.
    private func finish(_ rec: Record) {
        let status = (try? Data(contentsOf: rec.status)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let done = status?["state"] as? String == "done" || stamp() == rec.version
        let shown = run
        cleanUp(rec)
        if acknowledged || shown?.finished == true { return }     // Updated was shown (and maybe OK pressed)
        if shown == nil && !done && rec.pid == 0 { return }       // quit while downloading: nothing was changed
        run = done ? Run(version: rec.version, text: "", fraction: 1, finished: true)
            : Run(version: rec.version, text: "", failure: "The update to NFSU2 Builder \(rec.version) did not finish. This app is unchanged.")
    }

    // MARK: the overlay's buttons

    func cancel() {
        guard let r = run, r.canCancel || r.inBuilder else { return }
        cancelled = true
        session?.invalidateAndCancel()
        session = nil
        progress = nil
        if let b = builder {
            run?.text = "Stopping the update"
            run?.canCancel = false
            b.stop()             // the Builder stops its build and quits; ended() or tick() cleans up
        } else if let rec = record, rec.pid == 0 {
            // still downloading or checking; open() cleans up a mount it makes after this
            cleanUp(rec)
            run = nil
        }
    }

    /// The Builder's window, from the image, with the checklist: the player finishes the update there.
    func openBuilder() {
        guard let rec = record, FileManager.default.fileExists(atPath: rec.builder.path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = Self.builderArguments(app: app, status: nil)
        config.environment = Self.builderEnvironment()
        config.activates = true
        config.createsNewApplicationInstance = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: rec.builder, configuration: config) { [weak self] running, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let running = running, error == nil else {
                    self.run?.failure = "NFSU2 Builder could not be opened: \(error?.localizedDescription ?? "unknown error")"
                    return
                }
                var r = rec
                (r.pid, r.window) = (running.processIdentifier, true)
                self.record = r
                self.builder = Builder(app: running, pid: r.pid)
                self.cancelled = false
                self.run = Run(version: r.version, text: "", inBuilder: true, hasLog: !self.log.isEmpty)
                self.watch(r)
            }
        }
    }

    /// Finishing by hand: the Builder's window to the front.
    func showBuilder() {
        builder?.app?.unhide()
        builder?.app?.activate(options: [.activateIgnoringOtherApps])
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
    }

    /// OK or Close.  After an update by hand the Builder's window stays (it may still be
    /// deleting its temporary files): the image goes when it quits.
    func close() {
        if let b = builder, b.alive {
            if run?.finished == true { acknowledged = true; run = nil; return }
            cancelled = true
            run?.text = "Closing NFSU2 Builder"
            b.stop()
            return               // ended() or tick() sees it quit and cleans up
        }
        if let rec = record { cleanUp(rec) }
        run = nil
    }

    // MARK: helpers

    private func update(text: String, fraction: Double, detail: String?) {
        guard var r = run else { return }
        (r.text, r.fraction, r.detail) = (text, fraction, detail)
        run = r
    }

    private func fail(_ message: String) {
        session?.invalidateAndCancel()
        session = nil
        progress = nil
        if builder == nil, let rec = record { cleanUp(rec) }
        guard var r = run else { return }
        r.failure = message
        r.canCancel = false
        run = r
    }

    /// Unmounts the image (once the Builder in it has quit) and deletes the download.
    private func cleanUp(_ rec: Record) {
        if record?.folder == rec.folder { record = nil }
        DispatchQueue.global(qos: .utility).async {
            if FileManager.default.fileExists(atPath: rec.builder.path),
               Self.hdiutil(["detach", rec.mount.path]).status != 0 {
                Thread.sleep(forTimeInterval: 1)
                _ = Self.hdiutil(["detach", "-force", rec.mount.path])
            }
            try? FileManager.default.removeItem(at: rec.folder)
        }
    }

    struct UpdateError: Error { let message: String; init(_ m: String) { message = m } }

    static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        var sha = SHA256()
        while true {
            let chunk = h.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hdiutil(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}
