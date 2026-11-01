import AppKit

/// The bundle id pack.sh gives NFSU2.app.
public let gameBundleID = "org.nfsu2.nativeport"

/// True while NFSU2.app (its launcher or an engine started from it) is running.
public func isGameRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleID).isEmpty
}
