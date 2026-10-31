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

    func testUnwritableDestinationIsRed() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        XCTAssertEqual(destinationCheck(root), .blocked("Choose a folder you can write to"))
    }

    func testMissingDestinationIsRedAndWritableIsReady() {
        XCTAssertEqual(destinationCheck(root.appendingPathComponent("missing")), .blocked("Choose a folder you can write to"))
        XCTAssertTrue(destinationCheck(root).isReady)
    }
}
