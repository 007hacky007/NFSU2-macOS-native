import XCTest
@testable import BuilderCore

final class CoreTests: XCTestCase {
    func testBuildBlockedWhileAnyRowRedOrChecking() {
        var s = Dictionary(uniqueKeysWithValues: CheckID.allCases.map { ($0, CheckState.ready("ok")) })
        XCTAssertTrue(canBuild(s))
        s[.gameData] = .automatic("12 files differ"); XCTAssertTrue(canBuild(s))
        s[.gameProgram] = .checking("checking"); XCTAssertFalse(canBuild(s))
        s[.gameProgram] = .blocked("choose"); XCTAssertFalse(canBuild(s))
        s.removeValue(forKey: .diskSpace); s[.gameProgram] = .ready("ok"); XCTAssertFalse(canBuild(s))
    }

    func testMacCheck() {
        XCTAssertTrue(macCheck(isAppleSilicon: true, version: .init(majorVersion: 11, minorVersion: 0, patchVersion: 0)).isReady)
        XCTAssertEqual(macCheck(isAppleSilicon: false, version: .init(majorVersion: 15, minorVersion: 0, patchVersion: 0)),
                       .blocked("NFSU2 needs a Mac with Apple Silicon (M1 or later)"))
        XCTAssertEqual(macCheck(isAppleSilicon: true, version: .init(majorVersion: 10, minorVersion: 16, patchVersion: 0)),
                       .blocked("NFSU2 needs macOS 11 or newer"))
    }

    func testParsePipelineLines() {
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"step":"lift","title":"Translating"}"#), .step(id: "lift", title: "Translating"))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"progress": 0.25}"#), .progress(0.25))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"progress": 1}"#), .progress(1))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"done":"/w/out/personal/NFSU2.app"}"#),
                       .done(app: URL(fileURLWithPath: "/w/out/personal/NFSU2.app")))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"error":"bad"}"#), .error("bad"))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"done":7}"#), .log(#"NFSU2-EVENT {"done":7}"#))
        XCTAssertEqual(parsePipelineLine("NFSU2-EVENT {broken"), .log("NFSU2-EVENT {broken"))
        XCTAssertEqual(parsePipelineLine("plain"), .log("plain"))
    }

    func testProgressAndDisk() {
        XCTAssertEqual(buildSteps.map { $0.id }, ["prepare", "lift", "compile", "link", "package", "sign"])
        XCTAssertEqual(buildSteps.reduce(0) { $0 + $1.weight }, 100)
        XCTAssertEqual(progressFraction(atStart: "prepare"), 0)
        XCTAssertEqual(progressFraction(atStart: "compile"), 0.32, accuracy: 0.001)
        XCTAssertEqual(progressFraction(in: "compile", part: 0.5), 0.48, accuracy: 0.001)
        XCTAssertEqual(progressFraction(in: "sign", part: 2), 1, accuracy: 0.001)
        if case .blocked = diskSpaceCheck(available: requiredBuildBytes - 1) {} else { XCTFail() }
        if case .ready = diskSpaceCheck(available: requiredBuildBytes) {} else { XCTFail() }
        XCTAssertEqual(diskSpaceCheck(available: 4_000_000_000, required: 5_000_000_000), .blocked("Only 4.0 GB free, 5.0 GB needed"))
        XCTAssertEqual(diskSpaceCheck(available: 1_000_000_000, required: 2_000_000_000, disk: "USB"),
                       .blocked("Only 1.0 GB free on USB, 2.0 GB needed"))
        XCTAssertEqual(gameBundleID, "org.nfsu2.nativeport")
    }

    /// The game data costs space only where it cannot be cloned.
    func testSpaceNeedsCountTheGameOnlyWhereItCannotBeCloned() {
        let game: Int64 = 1_800_000_000
        // A folder (or an older NFSU2.app) on the workspace volume, the app to the same volume: clones only.
        XCTAssertEqual(spaceNeeds(gameBytes: game, discs: false, source: 1, workspace: 1, destination: 1), [1: requiredBuildBytes])
        // Discs are unpacked into the workspace.
        XCTAssertEqual(spaceNeeds(gameBytes: game, discs: true, source: 1, workspace: 1, destination: 1), [1: requiredBuildBytes + game])
        // A folder on another disk is copied into the workspace.
        XCTAssertEqual(spaceNeeds(gameBytes: game, discs: false, source: 2, workspace: 1, destination: 1), [1: requiredBuildBytes + game])
        // A destination on another disk gets a copy of the whole app.
        XCTAssertEqual(spaceNeeds(gameBytes: game, discs: false, source: 1, workspace: 1, destination: 3),
                       [1: requiredBuildBytes, 3: game + appBytes])
        XCTAssertEqual(spaceNeeds(gameBytes: game, discs: false, source: 3, workspace: 1, destination: 3),
                       [1: requiredBuildBytes + game, 3: game + appBytes])
    }
}
