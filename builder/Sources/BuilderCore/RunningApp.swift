import AppKit

/// The bundle id pack.sh gives NFSU2.app.
public let gameBundleID = "org.nfsu2.nativeport"

/// True while NFSU2.app (its launcher or an engine started from it) is running.
public func isGameRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: gameBundleID).isEmpty
}

/// The launcher's game folder setting (launcher/Game.swift, Prefs.gameFolder).
public let launcherGameFolderKey = "OyunDizini"

/// Points NFSU2.app's launcher at `folder`, so its first start goes straight to the launcher
/// window. Returns false when the setting could not be saved.
@discardableResult
public func setLauncherGameFolder(_ folder: URL, domain: String = gameBundleID) -> Bool {
    CFPreferencesSetAppValue(launcherGameFolderKey as CFString, folder.path as CFString, domain as CFString)
    return CFPreferencesAppSynchronize(domain as CFString)
}

public func launcherGameFolder(domain: String = gameBundleID) -> String? {
    CFPreferencesAppSynchronize(domain as CFString)
    return CFPreferencesCopyAppValue(launcherGameFolderKey as CFString, domain as CFString) as? String
}
