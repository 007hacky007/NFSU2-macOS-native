import XCTest
import BuilderCore

/// Drives the same BuilderCore calls as the Builder window against a real game copy.
/// Skipped unless NFSU2_E2E_DATA names the game data: a game folder, or disc images joined
/// with ":". NFSU2_E2E_PROGRAM is the SPEED2.EXE (or an archive) when the data has none;
/// NFSU2_E2E_SOURCES an assembled app's Contents/Resources/BuildSources instead of the repo.
/// Downloads the private Python and the packages, so it needs the network. The game copy is
/// only read; a game folder is made in a temporary folder when the data needs one.
final class EndToEndTests: XCTestCase {
    private let fm = FileManager.default
    private let version = "0.0.0-e2e"

    func testFullBuildFromWindowCalls() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dataPaths = env["NFSU2_E2E_DATA"] else {
            throw XCTSkip("set NFSU2_E2E_DATA to run the end-to-end build")
        }
        let data = dataPaths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-e2e-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let paths = BuilderPaths(support: tmp.appendingPathComponent("support"))
        let started = Date()
        func mark(_ what: String) { print("E2E \(String(format: "%7.1f", Date().timeIntervalSince(started))) s: \(what)") }

        let sources = try env["NFSU2_E2E_SOURCES"].map { URL(fileURLWithPath: $0) } ?? repositoryRoot()
        let manifest = try ReleaseManifest.load(sources.appendingPathComponent("tools/known_releases.tsv"))
        let report = GameDataChecker(manifest: manifest).check(data)
        XCTAssertNil(report.blocking, report.detailsText)
        mark("data checked: \(report.state)")
        var program = paths.program
        if report.usableAsIs {
            program = try XCTUnwrap(try fm.contentsOfDirectory(at: report.sources[0], includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.lowercased() == "speed2.exe" })
        } else {
            let choice = try XCTUnwrap(env["NFSU2_E2E_PROGRAM"], "the data has no supported SPEED2.EXE: set NFSU2_E2E_PROGRAM")
            let verdict = ProgramChecker().check(URL(fileURLWithPath: choice), keep: paths.program)
            XCTAssertTrue(verdict.isSupported, "\(verdict)")
            mark("program checked: \(verdict)")
        }
        let game = report.usableAsIs ? report.sources[0] : tmp.appendingPathComponent("Games/NFSU2")

        try prepareWorkspace(sources: sources, destination: paths.workspace(version: version), version: version)
        mark("workspace prepared")

        let installed = expectation(description: "python")
        var installResult: Result<Void, Error>?
        PythonRuntime.install(paths, download: { url, done in
            URLSession.shared.downloadTask(with: url) { file, response, error in
                if let file = file, (response as? HTTPURLResponse)?.statusCode == 200 {
                    done(.success(file))
                } else {
                    done(.failure(error ?? URLError(.badServerResponse)))
                }
            }.resume()
        }, completion: { result in
            installResult = result
            installed.fulfill()
        })
        wait(for: [installed], timeout: 600)
        try XCTUnwrap(installResult).get()
        mark("python installed")

        let setup = try run(.setup(paths: paths, version: version), timeout: 900)
        XCTAssertEqual(setup.status, 0, setup.lines.suffix(30).joined(separator: "\n"))
        XCTAssertEqual(buildToolsCheck(paths: paths, version: version), .ready("Installed"))
        mark("setup done")

        let runner = { PipelineRunner.build(paths: paths, version: self.version, program: program, game: game,
                                            data: report.usableAsIs ? nil : report.sources) }
        // First build: cancel once compiling has started, then nothing from that run may survive.
        let workspace = paths.workspace(version: version).path
        var group: pid_t = 0
        var clangSeen = false
        let cancelled = try run(runner(), timeout: 3600) { event, runner in
            guard case .step(id: "compile", _) = event else { return }
            group = Self.processGroup(matching: { $0.contains(workspace) && $0.contains("builder_cli.py") }) ?? 0
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline && !clangSeen {
                clangSeen = Self.processes(inGroup: group).contains { $0.contains("clang") }
                if !clangSeen { usleep(200_000) }
            }
            mark("compile started (group \(group), clang running: \(clangSeen)), cancelling")
            runner.cancel()
        }
        mark("cancelled build exited with \(cancelled.status)")
        XCTAssertNotEqual(group, 0, "found the build's process group")
        XCTAssertTrue(clangSeen, "clang was running when the build was cancelled")
        XCTAssertNotEqual(cancelled.status, 0)
        let deadline = Date().addingTimeInterval(6)
        var leftovers: [String] = []
        repeat {
            leftovers = Self.pgrep("clang").union(Self.pgrep("builder_cli")).compactMap { pid in
                Self.processGroup(of: pid) == group ? "\(pid)" : nil
            }.sorted()
            if leftovers.isEmpty { break }
            usleep(100_000)
        } while Date() < deadline
        XCTAssertEqual(leftovers, [], "clang or builder_cli processes from the cancelled build survived")
        mark("no clang or builder_cli left from the cancelled run")

        // Second build runs to the end and installs.
        let full = try run(runner(), timeout: 3600)
        XCTAssertEqual(full.status, 0, full.lines.suffix(40).joined(separator: "\n"))
        XCTAssertFalse(full.events.contains { if case .error = $0 { return true } else { return false } })
        let done = full.events.compactMap { event -> (URL, URL)? in
            if case let .done(app, game) = event { return (app, game) }
            return nil
        }
        let built = try XCTUnwrap(done.first)
        XCTAssertEqual(built.1.standardizedFileURL, game.standardizedFileURL)
        let steps = full.events.compactMap { event -> String? in
            if case let .step(id, _) = event { return id }
            return nil
        }
        XCTAssertEqual(steps, buildSteps.map { $0.id })
        mark("full build done, steps \(steps.joined(separator: " ")), \(full.lines.count) lines")

        let destination = tmp.appendingPathComponent("Applications")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let app = try installApp(built.0, into: destination, isRunning: { false })
        XCTAssertEqual(app.lastPathComponent, "NFSU2.app")
        let verify = SystemCommandRunner().run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        XCTAssertEqual(verify.status, 0, verify.output)
        mark("installed and codesign verified: \(app.path)")
    }

    // MARK: - Helpers

    private struct Run {
        var events: [PipelineEvent] = []
        var lines: [String] = []
        var status: Int32 = -1
    }

    private func run(_ runner: PipelineRunner, timeout: TimeInterval,
                     onEvent: ((PipelineEvent, PipelineRunner) -> Void)? = nil) throws -> Run {
        var result = Run()
        let exited = expectation(description: "exit")
        try runner.start(onEvent: { event in
            result.events.append(event)
            switch event {
            case let .log(line): result.lines.append(line)
            case let .step(_, title): result.lines.append(title)
            case let .error(message): result.lines.append("Error: \(message)")
            default: break
            }
            onEvent?(event, runner)
        }, onExit: { status in
            result.status = status
            exited.fulfill()
        })
        wait(for: [exited], timeout: timeout)
        return result
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if fm.fileExists(atPath: url.appendingPathComponent("build.sh").path) { return url }
        }
        throw XCTSkip("repository root not found")
    }

    private static func ps() -> [(pid: pid_t, pgid: pid_t, command: String)] {
        let output = SystemCommandRunner().run("/bin/ps", ["-axww", "-o", "pid=,pgid=,command="]).output
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = pid_t(parts[0]), let pgid = pid_t(parts[1]) else { return nil }
            return (pid, pgid, String(parts[2]))
        }
    }

    private static func processGroup(matching predicate: (String) -> Bool) -> pid_t? {
        ps().first { predicate($0.command) }?.pgid
    }

    private static func processGroup(of pid: pid_t) -> pid_t? {
        ps().first { $0.pid == pid }?.pgid
    }

    private static func processes(inGroup group: pid_t) -> [String] {
        ps().filter { $0.pgid == group }.map(\.command)
    }

    private static func pgrep(_ pattern: String) -> Set<pid_t> {
        let output = SystemCommandRunner().run("/usr/bin/pgrep", ["-f", pattern]).output
        return Set(output.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) })
    }
}
