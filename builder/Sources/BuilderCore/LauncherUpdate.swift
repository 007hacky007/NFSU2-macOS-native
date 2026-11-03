import Foundation

/// An update started by NFSU2.app's launcher (launcher/Updater.swift): it opens this Builder
/// from the downloaded disk image with `-LauncherUpdate <status file>`, and the Builder makes
/// and installs the new NFSU2.app with no one pressing its buttons. The status file is how the
/// launcher follows it (its progress bar); the Builder writes it each time what it does changes.
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
        /// Stopped: `message` says why, the Builder's window has the details.
        case failed
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
}

/// The checklist row that keeps an unattended update from building, once every check has
/// finished: none is still checking, and a row is red. nil while it may still turn ready.
public func updateBlocker(_ states: [CheckID: CheckState]) -> (CheckID, String)? {
    for id in CheckID.allCases {
        if case .checking? = states[id] { return nil }
    }
    for id in CheckID.allCases {
        if case let .blocked(message)? = states[id] { return (id, message) }
    }
    return nil
}
