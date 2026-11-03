// Update: the notice's button for a newer NFSU2 Builder (UpdateCheck.swift) updates this app
// with no one pressing anything in the Builder, and the launcher shows it all in one progress
// bar.  Play waits until it is done.
//
//   1. download NFSU2-Builder.dmg from the release, and its .sha256; the image must match it
//   2. mount it (hidden, read-only, in a temporary folder) and check it holds NFSU2 Builder of
//      that version
//   3. open that Builder, hidden, with -LauncherUpdate <status file>, -destination (the folder
//      this app is in) and -gameData (this app: the game inside it goes into the new one).  The
//      Builder sets up its tools and builds; twice a second its status file says where it is
//      (builder/Sources/BuilderCore/LauncherUpdate.swift)
//   4. built, it waits for NFSU2 to quit (an app it replaces must not run): the launcher quits,
//      the Builder installs the new NFSU2.app, opens it and quits
//   5. the new launcher finds the update in its preferences (Prefs.updateRun): once the Builder
//      has quit it unmounts the image, deletes the download and says the update is done
//
// Quitting the launcher during 3 leaves the Builder to finish: it installs and opens NFSU2 by
// itself, and a launcher opened meanwhile shows the progress again.  Cancel and a failure end
// with the image unmounted and the download deleted; a failure keeps the Builder (hidden, with
// its log) until Close.
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
        /// Why it stopped; the overlay offers Show Details while the Builder still runs.
        var failure: String? = nil
        /// Updated: the overlay says so until OK.
        var finished = false
        var canCancel = false
        var builderRunning = false
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
    private var builder: NSRunningApplication?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// An update in progress, kept across the launcher quitting for the install.
    struct Record: Equatable {
        var version: String
        var folder: URL           // the download, the mount point and the status file
        var pid: pid_t = 0        // the Builder, once it runs
        var mount: URL { folder.appendingPathComponent("mount") }
        var image: URL { folder.appendingPathComponent("NFSU2-Builder.dmg") }
        var status: URL { folder.appendingPathComponent("status.json") }

        var dictionary: [String: Any] { ["version": version, "folder": folder.path, "pid": Int(pid)] }
        init(version: String, folder: URL, pid: pid_t = 0) { (self.version, self.folder, self.pid) = (version, folder, pid) }
        init?(_ d: [String: Any]?) {
            guard let d = d, let v = d["version"] as? String, let f = d["folder"] as? String, !f.isEmpty else { return nil }
            self.init(version: v, folder: URL(fileURLWithPath: f), pid: pid_t((d["pid"] as? Int) ?? 0))
        }
    }

    private var record: Record? {
        get { Record(defaults.dictionary(forKey: Prefs.updateRun)) }
        set { if let r = newValue { defaults.set(r.dictionary, forKey: Prefs.updateRun) } else { defaults.removeObject(forKey: Prefs.updateRun) } }
    }

    /// An update is going on, or waits for its end to be seen: no Play.
    var busy: Bool { run != nil }
    /// The launcher must not play by itself on opening (Show this window when the app opens off).
    var pending: Bool { record != nil }

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

    /// The arguments the Builder is opened with (builder/Sources/NFSU2Builder/BuilderModel.swift).
    static func builderArguments(app: URL, status: URL) -> [String] {
        let quoted = "\"" + app.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return ["-LauncherUpdate", status.path, "-destination", app.deletingLastPathComponent().path, "-gameData", "(\(quoted))"]
    }

    // MARK: start

    /// Update pressed.  `app` is this NFSU2.app, replaced in its folder.
    func start(_ release: UpdateCheck.Release, app: URL = Paths.bundle) {
        guard run == nil else { return }
        guard let image = release.download, let sum = release.checksum else { return }
        cancelled = false
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
                self.download(image, digest: digest, record: rec, app: app, session: session)
            }
        }.resume()
    }

    private func download(_ url: URL, digest: String, record rec: Record, app: URL, session: URLSession) {
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
                self.open(rec, digest: digest, app: app)
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

    /// Checks the image, mounts it and opens the Builder in it (the slow parts off the main queue).
    private func open(_ rec: Record, digest: String, app: URL) {
        update(text: "Checking the download", fraction: Self.fraction(state: "open", part: 0), detail: nil)
        let version = rec.version
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () throws -> URL in
                guard (try? Self.sha256(of: rec.image)) == digest else { throw UpdateError("The download did not match its checksum, so it was not used. Try again later.") }
                let attach = Self.hdiutil(["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", rec.mount.path, rec.image.path])
                guard attach.status == 0 else { throw UpdateError("The download could not be opened: \(attach.output)") }
                let builder = rec.mount.appendingPathComponent(Self.builderName)
                let info = NSDictionary(contentsOf: builder.appendingPathComponent("Contents/Info.plist"))
                guard info?["CFBundleIdentifier"] as? String == Self.builderID,
                      info?["CFBundleShortVersionString"] as? String == version
                else { throw UpdateError("The download does not hold NFSU2 Builder \(version).") }
                return builder
            }.mapError { $0 as? UpdateError ?? UpdateError($0.localizedDescription) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.cancelled { return self.cleanUp(rec) }
                switch result {
                case let .failure(e): self.fail(e.message)
                case let .success(builder): self.launch(builder, record: rec, app: app)
                }
            }
        }
    }

    private func launch(_ builder: URL, record rec: Record, app: URL) {
        update(text: "Opening NFSU2 Builder \(rec.version)", fraction: Self.fraction(state: "open", part: 0), detail: nil)
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = Self.builderArguments(app: app, status: rec.status)
        config.activates = false
        config.hides = true
        config.createsNewApplicationInstance = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: builder, configuration: config) { [weak self] running, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let running = running, error == nil else {
                    return self.fail("NFSU2 Builder could not be opened: \(error?.localizedDescription ?? "unknown error")")
                }
                var r = rec
                r.pid = running.processIdentifier
                self.record = r
                self.builder = running
                if self.cancelled { running.terminate() }
                self.watch(r)
            }
        }
    }

    // MARK: following the Builder

    /// On opening: an update this launcher (or the one before it) started.
    func resume() {
        guard let rec = record, run == nil else { return }
        // quit while downloading: the Builder never got it
        if rec.pid == 0 { return cleanUp(rec) }
        if let b = NSRunningApplication(processIdentifier: rec.pid), b.bundleIdentifier == Self.builderID, !b.isTerminated {
            builder = b
            run = Run(version: rec.version, text: "Finishing the update", fraction: Self.fraction(state: "done", part: 0))
            watch(rec)
        } else {
            finish(rec)
        }
    }

    private func watch(_ rec: Record) {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick(rec) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick(rec)
    }

    private func status(_ rec: Record) -> (state: String, fraction: Double, text: String, message: String?)? {
        guard let data = try? Data(contentsOf: rec.status),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let state = o["state"] as? String
        else { return nil }
        return (state, (o["fraction"] as? Double) ?? 0, (o["text"] as? String) ?? "", o["message"] as? String)
    }

    private func tick(_ rec: Record) {
        let alive = builder.map { !$0.isTerminated } ?? false
        let s = status(rec)
        guard alive else {
            timer?.invalidate(); timer = nil
            builder = nil
            if cancelled || run?.failure != nil {
                cleanUp(rec)
                if cancelled { run = nil } else { run?.builderRunning = false }
            } else {
                finish(rec)
            }
            return
        }
        guard var r = run, r.failure == nil else { return }
        r.builderRunning = true
        r.canCancel = !cancelled
        switch s?.state {
        case "failed"?:
            r.failure = (s?.message).map { "The update stopped. \($0)" } ?? "The update stopped."
            r.canCancel = false
        case "waiting"?, "installing"?:
            r.text = "Installing the new NFSU2.app. NFSU2 opens again by itself."
            r.fraction = Self.fraction(state: "waiting", part: 0)
            r.detail = nil
            r.canCancel = false
            if !quitting {
                quitting = true
                run = r
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.quit() }
            }
        case "done"?:
            r.text = "Finishing the update"
            r.fraction = Self.fraction(state: "done", part: 0)
            r.canCancel = false
        case let state?:
            r.text = state == "building" ? "Building: \(s?.text ?? "")" : (s?.text ?? "")
            r.fraction = max(r.fraction, Self.fraction(state: state, part: s?.fraction ?? 0))
            r.detail = state == "building" ? "NFSU2 Builder \(rec.version) is making the new app; this takes a few minutes." : nil
        case nil:
            r.text = "Opening NFSU2 Builder \(rec.version)"
        }
        if cancelled { r.text = "Stopping the update" }
        run = r
    }

    /// The Builder has quit: the image goes, and the overlay says how it ended.
    private func finish(_ rec: Record) {
        let done = status(rec)?.state == "done" || stamp() == rec.version
        cleanUp(rec)
        run = done ? Run(version: rec.version, text: "", fraction: 1, finished: true)
            : Run(version: rec.version, text: "", failure: "The update to NFSU2 Builder \(rec.version) did not finish. This app is unchanged.")
    }

    // MARK: the overlay's buttons

    func cancel() {
        guard let r = run, r.canCancel else { return }
        cancelled = true
        session?.invalidateAndCancel()
        session = nil
        progress = nil
        if let b = builder {
            run?.text = "Stopping the update"
            run?.canCancel = false
            b.terminate()        // the Builder stops its build and quits; tick() cleans up
        } else if let rec = record, rec.pid == 0 {
            // still downloading or checking; open() cleans up a mount it makes after this
            cleanUp(rec)
            run = nil
        }
    }

    /// A failure's Show Details: the Builder's window, with the log.
    func showBuilder() {
        builder?.unhide()
        builder?.activate(options: [.activateIgnoringOtherApps])
    }

    /// OK or Close: a Builder still open (after a failure) quits; the image is unmounted.
    func close() {
        if let b = builder, !b.isTerminated {
            cancelled = true
            run?.text = "Closing NFSU2 Builder"
            b.terminate()
            return               // tick() sees it quit and cleans up
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
        record = nil
        DispatchQueue.global(qos: .utility).async {
            if FileManager.default.fileExists(atPath: rec.mount.appendingPathComponent(Self.builderName).path),
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
