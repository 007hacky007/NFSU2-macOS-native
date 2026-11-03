import Foundation

/// An update started by NFSU2.app's launcher (launcher/Updater.swift): it runs this Builder
/// from the downloaded disk image, with no window, as
/// `NFSU2Builder -LauncherUpdate <status file> -destination <folder> -gameData '("<NFSU2.app>")'`
/// and the Builder makes and installs the new NFSU2.app with no one pressing its buttons.
/// Each line it prints is JSON: a status (below) each time what it does changes, or
/// {"log": line} for the build's log. The status file holds the latest status too, for a
/// launcher opened again while the Builder works (the one that started it quits to let it
/// install). Exit 0: installed and opened; 1: failed; 3: needsBuilder; 143: stopped.
public struct LauncherUpdateStatus: Codable, Equatable {
    public enum State: String, Codable {
        /// The checklist: checking the game in the app, the disk space and the rest.
        case preparing
        /// Downloading and setting up the build tools.
        case tools
        /// The build steps; `fraction` is the build's part done.
        case building
        /// Built; installing waits until the launcher (NFSU2.app) has quit.
        case waiting
        /// Replacing NFSU2.app.
        case installing
        /// Installed; the new NFSU2.app is being opened and the Builder quits.
        case done
        /// A step failed: `message` says which and why; the log lines before it have the details.
        case failed
        /// A checklist row stays red and only the player can see to it (the command line tools,
        /// the game, the disk space): `message` has one "Row: what it says" line per row. The
        /// launcher offers to open the Builder's window.
        case needsBuilder
    }

    public var state: State
    public var fraction: Double
    public var text: String
    public var message: String?

    public init(state: State, fraction: Double = 0, text: String = "", message: String? = nil) {
        self.state = state
        self.fraction = fraction
        self.text = text
        self.message = message
    }

    /// Written whole (a temporary file renamed over it), so the launcher never reads half of it.
    public func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> LauncherUpdateStatus? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(LauncherUpdateStatus.self, from: $0) }
    }

    public static func read(line: String) -> LauncherUpdateStatus? {
        try? JSONDecoder().decode(LauncherUpdateStatus.self, from: Data(line.utf8))
    }
}

/// The checklist rows that keep an unattended update from building, once every check has
/// finished: none is still checking, and some are red. nil while they may still turn ready.
public func updateBlockers(_ states: [CheckID: CheckState]) -> [(CheckID, String)]? {
    for id in CheckID.allCases {
        if case .checking? = states[id] { return nil }
    }
    let rows = CheckID.allCases.compactMap { id -> (CheckID, String)? in
        if case let .blocked(message)? = states[id] { return (id, message) }
        return nil
    }
    return rows.isEmpty ? nil : rows
}

/// One line of the update's output: the JSON of `status`, or {"log": line}.
public func launcherUpdateLine(_ status: LauncherUpdateStatus) -> String {
    (try? JSONEncoder().encode(status)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}
public func launcherUpdateLine(log: String) -> String {
    (try? JSONSerialization.data(withJSONObject: ["log": log])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}
