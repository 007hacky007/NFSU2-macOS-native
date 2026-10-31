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
/// the translated code and the compiled engines (measured: about 2.1 GB), with room to spare.
public let requiredBuildBytes: Int64 = 3_000_000_000
/// A game folder unpacked from the discs (about 1.7 GB) when it goes on the same volume.
public let gameFolderBytes: Int64 = 2_000_000_000

public func diskSpaceCheck(available: Int64, required: Int64 = requiredBuildBytes) -> CheckState {
    let gb = { (b: Int64) in String(format: "%.1f GB", Double(b) / 1_000_000_000) }
    if available >= required {
        return .ready("\(gb(available)) free")
    }
    return .blocked("Only \(gb(available)) free, \(gb(required)) needed")
}
