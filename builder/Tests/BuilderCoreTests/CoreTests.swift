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
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"done":"/w/out/NFSU2.app","game":"/Users/x/Games/NFSU2"}"#),
                       .done(app: URL(fileURLWithPath: "/w/out/NFSU2.app"), game: URL(fileURLWithPath: "/Users/x/Games/NFSU2")))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"error":"bad"}"#), .error("bad"))
        XCTAssertEqual(parsePipelineLine(#"NFSU2-EVENT {"done":"/w/out/NFSU2.app"}"#), .log(#"NFSU2-EVENT {"done":"/w/out/NFSU2.app"}"#))
        XCTAssertEqual(parsePipelineLine("NFSU2-EVENT {broken"), .log("NFSU2-EVENT {broken"))
        XCTAssertEqual(parsePipelineLine("plain"), .log("plain"))
    }

    func testProgressAndDisk() {
        XCTAssertEqual(buildSteps.map { $0.id }, ["prepare", "lift", "compile", "link", "package", "sign"])
        XCTAssertEqual(buildSteps.reduce(0) { $0 + $1.weight }, 100)
        XCTAssertEqual(progressFraction(atStart: "prepare"), 0)
        XCTAssertEqual(progressFraction(atStart: "compile"), 0.34, accuracy: 0.001)
        XCTAssertEqual(progressFraction(in: "compile", part: 0.5), 0.56, accuracy: 0.001)
        XCTAssertEqual(progressFraction(in: "sign", part: 2), 1, accuracy: 0.001)
        if case .blocked = diskSpaceCheck(available: requiredBuildBytes - 1) {} else { XCTFail() }
        if case .ready = diskSpaceCheck(available: requiredBuildBytes) {} else { XCTFail() }
        XCTAssertEqual(diskSpaceCheck(available: 4_000_000_000, required: 5_000_000_000), .blocked("Only 4.0 GB free, 5.0 GB needed"))
    }

    func testLauncherGameFolderSetting() {
        let domain = "org.nfsu2.builder.test-\(UUID().uuidString)"
        defer {
            CFPreferencesSetAppValue(launcherGameFolderKey as CFString, nil, domain as CFString)
            CFPreferencesAppSynchronize(domain as CFString)
        }
        XCTAssertNil(launcherGameFolder(domain: domain))
        XCTAssertTrue(setLauncherGameFolder(URL(fileURLWithPath: "/Users/x/Games/NFSU2 \"copy\""), domain: domain))
        XCTAssertEqual(launcherGameFolder(domain: domain), "/Users/x/Games/NFSU2 \"copy\"")
        XCTAssertEqual(launcherGameFolderKey, "OyunDizini")
        XCTAssertEqual(gameBundleID, "org.nfsu2.nativeport")
    }
}
