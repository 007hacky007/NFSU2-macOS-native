import XCTest
@testable import BuilderCore

final class RecordingRunner: CommandRunning {
    var calls: [String] = []
    let results: [String: (status: Int32, output: String)]
    init(results: [String: (status: Int32, output: String)]) { self.results = results }
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        calls.append(([executable] + arguments).joined(separator: " "))
        return results[executable] ?? (127, "")
    }
}

final class EnvironmentTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("nfsu2-env-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func testCLTDetectionNeverInvokesShims() {
        let runner = RecordingRunner(results: ["/usr/bin/xcode-select": (0, "/Library/Developer/CommandLineTools\n")])
        let clt = CommandLineTools(runner: runner, fileExists: {
            ["/Library/Developer/CommandLineTools/usr/bin/clang", "/Library/Developer/CommandLineTools/usr/bin/swiftc",
             "/usr/bin/codesign"].contains($0)
        })
        XCTAssertTrue(clt.state().isReady)
        XCTAssertFalse(runner.calls.contains { $0.contains("xcrun") || $0 == "/usr/bin/clang" || $0 == "/usr/bin/swiftc" })
        let missing = CommandLineTools(runner: RecordingRunner(results: ["/usr/bin/xcode-select": (2, "")]), fileExists: { _ in false })
        XCTAssertEqual(missing.state(), .blocked("Needed to compile the game on your Mac, about 2 GB from Apple"))
    }

    func testCLTAcceptsXcodeToolchainAndNeedsCodesign() {
        let runner = RecordingRunner(results: ["/usr/bin/xcode-select": (0, "/Applications/Xcode.app/Contents/Developer\n")])
        let clang = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        let swiftc = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        XCTAssertTrue(CommandLineTools(runner: runner, fileExists: { [clang, swiftc, "/usr/bin/codesign"].contains($0) }).state().isReady)
        if case .blocked = CommandLineTools(runner: runner, fileExists: { [clang, swiftc].contains($0) }).state() {} else { XCTFail("codesign missing") }
        if case .blocked = CommandLineTools(runner: runner, fileExists: { [clang, "/usr/bin/codesign"].contains($0) }).state() {} else { XCTFail("swiftc missing") }
    }

    func testStartInstallRunsXcodeSelect() {
        let runner = RecordingRunner(results: [:])
        CommandLineTools(runner: runner, fileExists: { _ in false }).startInstall()
        XCTAssertEqual(runner.calls, ["/usr/bin/xcode-select --install"])
    }

    func testBuilderPaths() {
        let paths = BuilderPaths(support: URL(fileURLWithPath: "/s"))
        XCTAssertEqual(paths.python.path, "/s/python")
        XCTAssertEqual(paths.pythonExecutable.path, "/s/python/bin/python3")
        XCTAssertEqual(paths.workspace(version: "1.0").path, "/s/1.0")
        XCTAssertEqual(paths.venv.path, "/s/venv")
        XCTAssertEqual(paths.venvPython.path, "/s/venv/bin/python")
    }

    func testStaleOrHalfCopiedWorkspaceIsReplaced() throws {
        let src = tmp.appendingPathComponent("src"), dst = tmp.appendingPathComponent("dst")
        try write("new", to: src.appendingPathComponent("tools/a.py"))
        try write("old", to: dst.appendingPathComponent("tools/a.py"))
        try write("0.9", to: dst.appendingPathComponent(".builder-version"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "new")
        XCTAssertEqual(read(dst.appendingPathComponent(".builder-version")), "1.0")

        // No marker (crash mid-copy) is also replaced.
        try fm.removeItem(at: dst.appendingPathComponent(".builder-version"))
        try write("junk", to: dst.appendingPathComponent("tools/a.py"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "new")

        // Same version with marker: nothing is copied.
        try write("kept", to: dst.appendingPathComponent("tools/a.py"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "kept")
        let siblings = try fm.contentsOfDirectory(atPath: tmp.path).sorted()
        XCTAssertEqual(siblings, ["dst", "src"])
    }

    func testWorkspaceWithOnlyMarkerIsCopiedAgain() throws {
        let src = tmp.appendingPathComponent("src"), dst = tmp.appendingPathComponent("dst")
        try write("new", to: src.appendingPathComponent("tools/a.py"))
        try write("x", to: src.appendingPathComponent("build.sh"))
        try write("1.0", to: dst.appendingPathComponent(".builder-version"))
        try write("x", to: dst.appendingPathComponent("build.sh"))
        try prepareWorkspace(sources: src, destination: dst, version: "1.0")
        XCTAssertEqual(read(dst.appendingPathComponent("tools/a.py")), "new")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: tmp.path).sorted(), ["dst", "src"])
    }

    func testSweepRemovesOnlyLeftovers() throws {
        let paths = BuilderPaths(support: tmp)
        for name in [".trash-1/tools/a.py", ".1.0.tmp-2/build.sh", ".python.tmp-3/python/bin/python3",
                     "python/bin/python3", "1.0/.builder-version"] {
            try write("x", to: tmp.appendingPathComponent(name))
        }
        sweepLeftovers(paths)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: tmp.path).sorted(), ["1.0", "python"])
        XCTAssertEqual(read(paths.pythonExecutable), "x")
    }

    func testOldVersionWorkspacesAreRemoved() throws {
        let paths = BuilderPaths(support: tmp)
        try write("0.9", to: tmp.appendingPathComponent("0.9/.builder-version"))
        try write("x", to: tmp.appendingPathComponent("0.9/tools/a.py"))
        try write("1.0", to: tmp.appendingPathComponent("1.0/.builder-version"))
        try write("x", to: tmp.appendingPathComponent("notes/a.txt"))
        try write("x", to: paths.pythonExecutable)
        removeOldWorkspaces(paths, keeping: "1.0")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: tmp.path).sorted(), ["1.0", "notes", "python"])
    }

    func testMoveToTrashRenamesToHiddenSibling() throws {
        let dir = tmp.appendingPathComponent("1.0")
        try write("x", to: dir.appendingPathComponent("tools/a.py"))
        let trash = try moveToTrash(dir)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
        XCTAssertTrue(trash.lastPathComponent.hasPrefix(".trash-"))
        XCTAssertEqual(trash.deletingLastPathComponent().path, tmp.path)
        XCTAssertEqual(read(trash.appendingPathComponent("tools/a.py")), "x")
    }

    func testWorkspaceCopiesOnlyBundledEntries() throws {
        let src = tmp.appendingPathComponent("repo"), dst = tmp.appendingPathComponent("ws")
        for entry in ["build.sh", "link.sh", "pack.sh", "VERSION", "requirements.txt", "tools/a.py", "runtime/r.c",
                      "launcher/l.swift", "tests/boot.c", "gen/big.bin", "out/o.bin", ".venv/bin/python",
                      "tools/__pycache__/x.pyc", "runtime/__pycache__/y.pyc", "README.md", "docs/d.md"] {
            try write("x", to: src.appendingPathComponent(entry))
        }
        XCTAssertEqual(bundledSourceEntries, ["build.sh", "link.sh", "pack.sh", "run.sh", "VERSION", "requirements.txt",
                                              "tools", "runtime", "launcher", "tests"])
        let value = Array("0081;00000000;Test;".utf8)
        let quarantined = src.appendingPathComponent("tools/a.py")
        XCTAssertEqual(setxattr(quarantined.path, "com.apple.quarantine", value, value.count, 0, 0), 0)
        try prepareWorkspace(sources: src, destination: dst, version: "2")
        errno = 0
        XCTAssertEqual(getxattr(dst.appendingPathComponent("tools/a.py").path, "com.apple.quarantine", nil, 0, 0, 0), -1)
        XCTAssertEqual(errno, ENOATTR)
        let top = try fm.contentsOfDirectory(atPath: dst.path).sorted()
        XCTAssertEqual(top, [".builder-version", "VERSION", "build.sh", "launcher", "link.sh", "pack.sh", "requirements.txt",
                             "runtime", "tests", "tools"])
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("tools/__pycache__").path))
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("runtime/__pycache__").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("tools/a.py").path))
    }

    func testPythonPinLooksSane() {
        XCTAssertTrue(PythonRuntime.url.absoluteString.hasPrefix("https://github.com/astral-sh/python-build-standalone/releases/download/"))
        XCTAssertTrue(PythonRuntime.url.absoluteString.hasSuffix("aarch64-apple-darwin-install_only.tar.gz"))
        XCTAssertEqual(PythonRuntime.sha256.count, 64)
    }

    private func installResult(_ paths: BuilderPaths, sha: String? = nil,
                               download: (URL, @escaping (Result<URL, Error>) -> Void) -> Void) -> Result<Void, Error> {
        var result: Result<Void, Error>?
        let done = expectation(description: "install")
        PythonRuntime.install(paths, sha256: sha ?? PythonRuntime.sha256, download: download) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result!
    }

    func testPythonInstallRejectsBadChecksumAndLeavesNothing() throws {
        let support = tmp.appendingPathComponent("support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let paths = BuilderPaths(support: support)
        let bad = tmp.appendingPathComponent("bad.tgz")
        try write("not python", to: bad)
        let result = installResult(paths) { _, done in done(.success(bad)) }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertTrue("\(error.localizedDescription)".lowercased().contains("checksum"))
        XCTAssertFalse(fm.fileExists(atPath: paths.python.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: support.path), [])
        XCTAssertFalse(PythonRuntime.isInstalled(paths))
    }

    func testPythonInstallReportsDownloadFailure() throws {
        let support = tmp.appendingPathComponent("support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let paths = BuilderPaths(support: support)
        let result = installResult(paths) { _, done in done(.failure(URLError(.notConnectedToInternet))) }
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: support.path), [])
    }

    func testPythonInstallExtractsVerifiedArchive() throws {
        let support = tmp.appendingPathComponent("support")
        let paths = BuilderPaths(support: support)
        let stage = tmp.appendingPathComponent("stage")
        let exe = stage.appendingPathComponent("python/bin/python3")
        try write("#!/bin/sh\n", to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let archive = tmp.appendingPathComponent("py.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", stage.path, "python"]
        try tar.run()
        tar.waitUntilExit()
        let sha = try sha256Hex(of: archive)
        let result = installResult(paths, sha: sha) { _, done in done(.success(archive)) }
        guard case .success = result else { return XCTFail("\(result)") }
        XCTAssertTrue(fm.isExecutableFile(atPath: paths.pythonExecutable.path))
        XCTAssertEqual(read(paths.python.appendingPathComponent(".nfsu2-python-sha256")), sha)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: support.path), ["python"])
    }

    private func fakePython(_ paths: BuilderPaths, marker: String?) throws {
        try write("#!/bin/sh\n", to: paths.pythonExecutable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.pythonExecutable.path)
        if let marker = marker { try write(marker, to: paths.python.appendingPathComponent(".nfsu2-python-sha256")) }
    }

    func testIsInstalledRequiresPinnedMarker() throws {
        let paths = BuilderPaths(support: tmp)
        try fakePython(paths, marker: nil)
        XCTAssertFalse(PythonRuntime.isInstalled(paths))
        try fakePython(paths, marker: "oldpin")
        XCTAssertFalse(PythonRuntime.isInstalled(paths))
        try fakePython(paths, marker: PythonRuntime.sha256)
        XCTAssertTrue(PythonRuntime.isInstalled(paths))
    }

    func testBuildToolsBlockedUntilPythonAndVenvMatch() throws {
        let paths = BuilderPaths(support: tmp)
        let ws = paths.workspace(version: "1")
        let req = ws.appendingPathComponent("requirements.txt")
        try write("numpy\n", to: req)
        try write("", to: paths.venvPython)
        try write(try sha256Hex(of: req) + "\n", to: paths.venv.appendingPathComponent(".build-requirements-sha256"))
        // Venv fine, Python missing.
        XCTAssertEqual(buildToolsCheck(paths: paths, version: "1"), .blocked("A private Python and the lifter's packages, about 32 MB download"))
        try fakePython(paths, marker: PythonRuntime.sha256)
        XCTAssertTrue(buildToolsCheck(paths: paths, version: "1").isReady)
        // Python present, hash mismatch: only the packages are fetched again.
        let packages = CheckState.blocked("Packages need to be set up again (small download)")
        try write("numpy\nscipy\n", to: req)
        XCTAssertEqual(buildToolsCheck(paths: paths, version: "1"), packages)
        // Python present, venv removed (Delete temporary files with the build tools).
        try write("numpy\n", to: req)
        XCTAssertTrue(buildToolsCheck(paths: paths, version: "1").isReady)
        try fm.removeItem(at: paths.venv)
        XCTAssertEqual(buildToolsCheck(paths: paths, version: "1"), packages)
    }

    /// The packages are shared: a workspace links to them, an old one of its own is replaced by
    /// the link, and deleting a workspace (or one of another version) leaves them.
    func testWorkspaceLinksTheSharedVenv() throws {
        let paths = BuilderPaths(support: tmp)
        try write("", to: paths.venvPython)
        let ws = paths.workspace(version: "1.0.5")
        try write("old", to: ws.appendingPathComponent(".venv/bin/python"))
        try linkSharedVenv(paths, workspace: ws)
        let link = ws.appendingPathComponent(".venv")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), paths.venv.path)
        XCTAssertEqual(read(link.appendingPathComponent("bin/python")), "")
        try linkSharedVenv(paths, workspace: ws)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), paths.venv.path, "a right link stays")
        try write("1.0.5", to: ws.appendingPathComponent(".builder-version"))
        removeOldWorkspaces(paths, keeping: "1.0.6")
        XCTAssertFalse(fm.fileExists(atPath: ws.path))
        XCTAssertTrue(fm.fileExists(atPath: paths.venvPython.path), "another version's workspace goes, the packages stay")
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: tmp.path).contains { $0.hasPrefix(".trash-") })
    }

    /// A new private Python sets the packages up again: the old venv was made with the old one.
    func testNewPythonDropsTheVenv() throws {
        let paths = BuilderPaths(support: tmp.appendingPathComponent("support"))
        try write("", to: paths.venvPython)
        let root = tmp.appendingPathComponent("archive")
        try write("#!/bin/sh\n", to: root.appendingPathComponent("python/bin/python3"))
        XCTAssertEqual(chmod(root.appendingPathComponent("python/bin/python3").path, 0o755), 0)
        let archive = tmp.appendingPathComponent("python.tar.gz")
        XCTAssertEqual(SystemCommandRunner().run("/usr/bin/tar", ["-czf", archive.path, "-C", root.path, "python"]).status, 0)
        let digest = try sha256Hex(of: archive)
        let done = expectation(description: "install")
        var outcome: Result<Void, Error>?
        PythonRuntime.install(paths, sha256: digest, download: { _, finish in finish(.success(archive)) },
                              completion: { outcome = $0; done.fulfill() })
        wait(for: [done], timeout: 30)
        XCTAssertNoThrow(try outcome?.get())
        XCTAssertTrue(fm.isExecutableFile(atPath: paths.pythonExecutable.path))
        XCTAssertFalse(fm.fileExists(atPath: paths.venv.path))
    }

    func testLauncherUpdateStatusRoundTrip() throws {
        let file = tmp.appendingPathComponent("status.json")
        XCTAssertNil(LauncherUpdateStatus.read(from: file))
        let status = LauncherUpdateStatus(state: .building, fraction: 0.4, text: "Compile the game")
        try status.write(to: file)
        XCTAssertEqual(LauncherUpdateStatus.read(from: file), status)
        // what launcher/Updater.swift reads
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        XCTAssertEqual(json?["state"] as? String, "building")
        XCTAssertEqual(json?["fraction"] as? Double, 0.4)
        XCTAssertEqual(json?["text"] as? String, "Compile the game")
    }

    func testUpdateBlockerWaitsForEveryCheck() {
        var states = Dictionary(uniqueKeysWithValues: CheckID.allCases.map { ($0, CheckState.ready("ok")) })
        XCTAssertNil(updateBlocker(states))
        states[.diskSpace] = .blocked("Only 0.5 GB free, 1.5 GB needed")
        states[.gameData] = .checking("Checking your game copy...")
        XCTAssertNil(updateBlocker(states), "not while a check runs")
        states[.gameData] = .automatic("fine")
        XCTAssertEqual(updateBlocker(states)?.0, .diskSpace)
        XCTAssertEqual(updateBlocker(states)?.1, "Only 0.5 GB free, 1.5 GB needed")
    }

    func testInstallCompletionArrivesOnMainThread() throws {
        let paths = BuilderPaths(support: tmp.appendingPathComponent("support"))
        let bad = tmp.appendingPathComponent("bad.tgz")
        try write("x", to: bad)
        var onMain: Bool?
        let done = expectation(description: "install")
        PythonRuntime.install(paths, download: { _, finish in
            DispatchQueue.global().async { finish(.success(bad)) }
        }, completion: { _ in
            onMain = Thread.isMainThread
            done.fulfill()
        })
        wait(for: [done], timeout: 30)
        XCTAssertEqual(onMain, true)
    }

    func testRemoveQuarantineRecursive() throws {
        let dir = tmp.appendingPathComponent("q")
        let file = dir.appendingPathComponent("sub/f.txt")
        try write("x", to: file)
        let value = Array("0081;00000000;Test;".utf8)
        for url in [dir, file] {
            XCTAssertEqual(setxattr(url.path, "com.apple.quarantine", value, value.count, 0, 0), 0)
        }
        try removeQuarantine(at: dir)
        for url in [dir, file] {
            errno = 0
            XCTAssertEqual(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
            XCTAssertEqual(errno, ENOATTR)
        }
        // No attribute present: still fine.
        try removeQuarantine(at: dir)
    }

    /// The size on the delete button: what the files really take on disk.
    func testAllocatedSizeAndSizeText() throws {
        let dir = tmp.appendingPathComponent("ws")
        XCTAssertEqual(allocatedSize(of: dir), 0, "a workspace that is not there takes nothing")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("gen"), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: dir.appendingPathComponent("gen/all.c"))
        try Data(count: 1_000).write(to: dir.appendingPathComponent("small"))
        let size = allocatedSize(of: dir)
        XCTAssertGreaterThanOrEqual(size, 3_001_000)
        XCTAssertLessThan(size, 3_200_000)
        XCTAssertEqual(sizeText(612_000_000), "612 MB")
    }
}
