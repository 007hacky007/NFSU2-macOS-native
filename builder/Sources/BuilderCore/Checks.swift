import Foundation

public enum CheckID: CaseIterable {
    case mac, commandLineTools, buildTools, gameData, gameProgram, destination, diskSpace
}

/// Grey (checking), green (ready), amber (handled or informational, not blocking), red (blocked).
public enum CheckState: Equatable {
    case checking(String)
    case ready(String)
    case automatic(String)
    case blocked(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}

public func canBuild(_ states: [CheckID: CheckState]) -> Bool {
    CheckID.allCases.allSatisfy { id in
        switch states[id] {
        case .ready?, .automatic?: return true
        default: return false
        }
    }
}

public func macCheck(isAppleSilicon: Bool, version: OperatingSystemVersion) -> CheckState {
    guard isAppleSilicon else {
        return .blocked("NFSU2 needs a Mac with Apple Silicon (M1 or later)")
    }
    guard version.majorVersion >= 11 else {
        return .blocked("NFSU2 needs macOS 11 or newer")
    }
    return .ready("Apple Silicon, macOS \(version.majorVersion).\(version.minorVersion)")
}

/// Free space the build needs on the workspace volume: the private Python, the build tools,
/// the translated code and the compiled engines (measured on a European build: 0.63 GB, the
/// built NFSU2.app without the game 89 MB), with room to spare.
public let requiredBuildBytes: Int64 = 1_500_000_000
/// The app around the game: launcher and engines (89 MB), with room to spare.
public let appBytes: Int64 = 150_000_000

/// Bytes each volume needs for a build that puts `gameBytes` of game data inside the app.
/// APFS clones cost nothing: a game folder (or an older NFSU2.app) on the workspace volume is
/// cloned into the app, and the app moved to a destination on the same volume. What cannot be
/// cloned is counted: the game data copied or unpacked (discs) into the workspace, and the
/// whole app copied to a destination on another volume.
public func spaceNeeds(gameBytes: Int64, discs: Bool, source: UInt64?, workspace: UInt64, destination: UInt64?) -> [UInt64: Int64] {
    var needs: [UInt64: Int64] = [workspace: requiredBuildBytes]
    if discs || source != workspace { needs[workspace, default: 0] += gameBytes }
    if let destination = destination, destination != workspace {
        needs[destination, default: 0] += gameBytes + appBytes
    }
    return needs
}

public func diskSpaceCheck(available: Int64, required: Int64 = requiredBuildBytes, disk: String? = nil) -> CheckState {
    let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1_000_000_000) }
    if available >= required {
        return .ready("\(gb(available)) free")
    }
    let on = disk.map { " on \($0)" } ?? ""
    return .blocked("Only \(gb(available)) free\(on), \(gb(required)) needed")
}
