import XCTest
@testable import BuilderCore

final class DestinationTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "plist".write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try marker.write(to: url.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
    }

    private func marker(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8)
    }

    func testInstallReplacesExistingApp() throws {
        let dest = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try makeApp(at: dest.appendingPathComponent("NFSU2.app"), marker: "old")
        let built = root.appendingPathComponent("built/NFSU2.app")
        try makeApp(at: built, marker: "new")
        let result = try installApp(built, into: dest, isRunning: { false })
        XCTAssertEqual(result.lastPathComponent, "NFSU2.app")
        XCTAssertEqual(try marker(result), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".NFSU2.app.installing").path))
    }

    func testFreshInstallAndStaleStagingCleaned() throws {
        let dest = root.appendingPathComponent("dest")
        try makeApp(at: dest.appendingPathComponent(".NFSU2.app.installing"), marker: "stale")
        let built = root.appendingPathComponent("built/NFSU2.app")
        try makeApp(at: built, marker: "new")
        let result = try installApp(built, into: dest, isRunning: { false })
        XCTAssertEqual(try marker(result), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".NFSU2.app.installing").path))
    }

    func testRunningGameIsNotReplaced() throws {
        let dest = root.appendingPathComponent("dest")
        try makeApp(at: dest.appendingPathComponent("NFSU2.app"), marker: "old")
        let built = root.appendingPathComponent("built/NFSU2.app")
        try makeApp(at: built, marker: "new")
        XCTAssertThrowsError(try installApp(built, into: dest, isRunning: { true })) { error in
            XCTAssertEqual(error.localizedDescription, "Quit NFSU2 first, then try again.")
        }
        XCTAssertEqual(try marker(dest.appendingPathComponent("NFSU2.app")), "old")
    }

    func testFailedCopyKeepsOldApp() throws {
        let dest = root.appendingPathComponent("dest")
        try makeApp(at: dest.appendingPathComponent("NFSU2.app"), marker: "old")
        let missing = root.appendingPathComponent("nope/NFSU2.app")
        XCTAssertThrowsError(try installApp(missing, into: dest, isRunning: { false }))
        XCTAssertEqual(try marker(dest.appendingPathComponent("NFSU2.app")), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".NFSU2.app.installing").path))
    }

    func testStagingFailureGivesPlainErrorAndKeepsOldApp() throws {
        let dest = root.appendingPathComponent("dest")
        try makeApp(at: dest.appendingPathComponent("NFSU2.app"), marker: "old")
        let built = root.appendingPathComponent("built/NFSU2.app")
        try makeApp(at: built, marker: "new")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dest.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path) }
        XCTAssertThrowsError(try installApp(built, into: dest, isRunning: { false })) { error in
            XCTAssertEqual(error.localizedDescription, "Could not install NFSU2 into dest. Choose another folder and try again.")
        }
        XCTAssertEqual(try marker(dest.appendingPathComponent("NFSU2.app")), "old")
    }

    private func makeEmbeddedApp(at url: URL, marker: String, version: String? = nil) throws {
        try makeApp(at: url, marker: marker)
        let info: NSDictionary = version.map { ["CFBundleIdentifier": "org.nfsu2.nativeport", builderVersionKey: $0] }
            ?? ["CFBundleIdentifier": "org.nfsu2.nativeport"]
        XCTAssertTrue(info.write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true))
        let game = url.appendingPathComponent("Contents/Resources/Game")
        try FileManager.default.createDirectory(at: game.appendingPathComponent("GLOBAL"), withIntermediateDirectories: true)
        try "exe \(marker)".write(to: game.appendingPathComponent("SPEED2.EXE"), atomically: true, encoding: .utf8)
        try "data \(marker)".write(to: game.appendingPathComponent("GLOBAL/GLOBALB.LZC"), atomically: true, encoding: .utf8)
    }

    private func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Installing clears quarantine from what the build made, never from the game data copied
    /// from the player's own copy (a Mac program hidden in a download keeps macOS's check).
    func testInstallKeepsQuarantineOnTheGameData() throws {
        let dest = root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let built = root.appendingPathComponent("built/NFSU2.app")
        try makeEmbeddedApp(at: built, marker: "new")
        let data = built.appendingPathComponent("Contents/Resources/Game/GLOBAL/GLOBALB.LZC")
        let made = built.appendingPathComponent("Contents/marker")
        for file in [data, made] {
            XCTAssertEqual(setxattr(file.path, "com.apple.quarantine", "0081;00000000;Test;", 19, 0, XATTR_NOFOLLOW), 0)
        }
        let result = try installApp(built, into: dest, isRunning: { false })
        XCTAssertTrue(hasQuarantine(result.appendingPathComponent("Contents/Resources/Game/GLOBAL/GLOBALB.LZC")))
        XCTAssertFalse(hasQuarantine(result.appendingPathComponent("Contents/marker")))
        XCTAssertFalse(hasQuarantine(result))
    }

    private func gameData(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/Resources/Game/GLOBAL/GLOBALB.LZC"), encoding: .utf8)
    }

    /// The update path: the new app (with the game cloned from the old one) is moved next to
    /// the old app on the same volume and swapped in; the build in the workspace is used up.
    func testUpdateSwapsInTheCompleteNewAppAndUsesUpTheBuild() throws {
        let dest = root.appendingPathComponent("Applications")
        let old = dest.appendingPathComponent("NFSU2.app")
        try makeEmbeddedApp(at: old, marker: "old", version: "1.0.0")
        let built = root.appendingPathComponent("workspace/out/personal/NFSU2.app")
        try makeEmbeddedApp(at: built, marker: "new", version: "1.1.0")
        let result = try installApp(built, into: dest, isRunning: { false })
        XCTAssertEqual(try marker(result), "new")
        XCTAssertEqual(try gameData(result), "data new")
        XCTAssertEqual(InstalledApp(result)?.builderVersion, "1.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: built.path), "the build was moved, not copied")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path), ["NFSU2.app"])
    }

    /// Never the old app's data before the new app is complete: an incomplete build fails before
    /// the swap, the old app and its game stay as they were, and the build goes back for another try.
    func testIncompleteBuildKeepsTheOldAppAndItsGame() throws {
        let dest = root.appendingPathComponent("Applications")
        let old = dest.appendingPathComponent("NFSU2.app")
        try makeEmbeddedApp(at: old, marker: "old", version: "1.0.0")
        let built = root.appendingPathComponent("workspace/out/personal/NFSU2.app")
        try makeEmbeddedApp(at: built, marker: "new")
        try FileManager.default.removeItem(at: built.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try installApp(built, into: dest, isRunning: { false }))
        XCTAssertEqual(try marker(old), "old")
        XCTAssertEqual(try gameData(old), "data old")
        XCTAssertEqual(InstalledApp(old)?.builderVersion, "1.0.0")
        XCTAssertEqual(try marker(built), "new", "the build is back where it was")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dest.path), ["NFSU2.app"])
    }

    func testInstalledAppAndTheBuildButton() throws {
        let dest = root.appendingPathComponent("Applications")
        XCTAssertNil(InstalledApp.find(in: dest))
        XCTAssertEqual(buildButtonTitle(replacing: nil, version: "1.1.0"), "Build NFSU2.app")

        try makeApp(at: dest.appendingPathComponent("NFSU2.app"), marker: "from 1.0.0")   // no version, no game
        let plain = try XCTUnwrap(InstalledApp.find(in: dest))
        XCTAssertNil(plain.builderVersion)
        XCTAssertNil(plain.game)
        XCTAssertEqual(buildButtonTitle(replacing: plain, version: "1.1.0"), "Update NFSU2.app")

        try FileManager.default.removeItem(at: dest.appendingPathComponent("NFSU2.app"))
        try makeEmbeddedApp(at: dest.appendingPathComponent("NFSU2.app"), marker: "a", version: "1.1.0")
        let embedded = try XCTUnwrap(InstalledApp.find(in: dest))
        XCTAssertEqual(embedded.game?.lastPathComponent, "Game")
        XCTAssertEqual(buildButtonTitle(replacing: embedded, version: "1.2.0"), "Update NFSU2.app (1.1.0 -> 1.2.0)")
        XCTAssertEqual(buildButtonTitle(replacing: embedded, version: "1.1.0"), "Update NFSU2.app (1.1.0)")
    }

    func testUnwritableDestinationIsRed() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        XCTAssertEqual(destinationCheck(root), .blocked("Choose a folder you can write to"))
    }

    func testMissingDestinationIsRedAndWritableIsReady() {
        XCTAssertEqual(destinationCheck(root.appendingPathComponent("missing")), .blocked("Choose a folder you can write to"))
        XCTAssertTrue(destinationCheck(root).isReady)
    }
}
