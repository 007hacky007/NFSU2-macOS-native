import Foundation

/// What tools/make_builder.py bundles from the repository (tests/ only holds the two files link.sh compiles).
public let bundledSourceEntries = ["build.sh", "link.sh", "pack.sh", "run.sh", "VERSION", "requirements.txt", "tools", "runtime", "launcher", "tests"]

public struct BuilderPaths {
    public let support: URL

    public init(support: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NFSU2 Builder")) {
        self.support = support
    }

    public var python: URL { support.appendingPathComponent("python") }
    public var pythonExecutable: URL { python.appendingPathComponent("bin/python3") }
    /// The supported SPEED2.EXE the player chose (or found in an archive), kept for the build.
    public var program: URL { support.appendingPathComponent("program/SPEED2.EXE") }

    public func workspace(version: String) -> URL {
        support.appendingPathComponent(version)
    }

    /// The lifter's packages (a venv of the private Python). Shared by every Builder version and
    /// kept by Remove build files, so they are downloaded again only when requirements.txt or the
    /// private Python changes. Each workspace's .venv is a link to it (linkSharedVenv), which is
    /// where the pipeline scripts look ("$ROOT/.venv/bin/python").
    public var venv: URL { support.appendingPathComponent("venv") }
    public var venvPython: URL { venv.appendingPathComponent("bin/python") }
}

/// Makes `workspace`/.venv a link to the shared venv. A .venv of its own (made by a Builder
/// before 1.0.5, inside the workspace) is deleted; the link is left as it is when it is right.
public func linkSharedVenv(_ paths: BuilderPaths, workspace: URL) throws {
    let fm = FileManager.default
    let link = workspace.appendingPathComponent(".venv")
    if let target = try? fm.destinationOfSymbolicLink(atPath: link.path), target == paths.venv.path { return }
    if (try? link.checkResourceIsReachable()) == true || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
        let trash = try moveToTrash(link)
        try? fm.removeItem(at: trash)
    }
    try fm.createSymbolicLink(at: link, withDestinationURL: paths.venv)
}

private let versionMarker = ".builder-version"

/// Copies the pipeline sources into `destination`. A destination whose marker matches
/// `version` and that holds every bundled entry of `sources` is left alone; anything else is
/// replaced atomically.
public func prepareWorkspace(sources: URL, destination: URL, version: String) throws {
    let fm = FileManager.default
    let marker = destination.appendingPathComponent(versionMarker)
    if let current = try? String(contentsOf: marker, encoding: .utf8), current == version,
       bundledSourceEntries.allSatisfy({ !fm.fileExists(atPath: sources.appendingPathComponent($0).path)
           || fm.fileExists(atPath: destination.appendingPathComponent($0).path) }) {
        return
    }

    let parent = destination.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let temp = parent.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
    do {
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        for entry in bundledSourceEntries {
            let from = sources.appendingPathComponent(entry)
            guard fm.fileExists(atPath: from.path) else { continue }
            try fm.copyItem(at: from, to: temp.appendingPathComponent(entry))
        }
        try removePycache(in: temp)
        try removeQuarantine(at: temp)
        try version.write(to: temp.appendingPathComponent(versionMarker), atomically: true, encoding: .utf8)
        let old = fm.fileExists(atPath: destination.path) ? try moveToTrash(destination) : nil
        try fm.moveItem(at: temp, to: destination)
        if let old = old { try? fm.removeItem(at: old) }
    } catch {
        try? fm.removeItem(at: temp)
        throw error
    }
}

/// Renames `url` to a hidden `.trash-<uuid>` sibling in one atomic step and returns that
/// location. A quit while the caller deletes it then never leaves a half-removed directory
/// under the real name; `sweepLeftovers` deletes the rest on the next start.
public func moveToTrash(_ url: URL) throws -> URL {
    let trash = url.deletingLastPathComponent().appendingPathComponent(".trash-\(UUID().uuidString)")
    try FileManager.default.moveItem(at: url, to: trash)
    return trash
}

/// Deletes what interrupted work left in the support folder: `.trash-*` directories and
/// `.<name>.tmp-*` copies. Called on start, before anything else uses the folder.
public func sweepLeftovers(_ paths: BuilderPaths) {
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: paths.support.path)) ?? []
    where name.hasPrefix(".trash-") || (name.hasPrefix(".") && name.contains(".tmp-")) {
        try? fm.removeItem(at: paths.support.appendingPathComponent(name))
    }
}

private func removePycache(in root: URL) throws {
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
    var found: [URL] = []
    for case let url as URL in walker where url.lastPathComponent == "__pycache__" {
        found.append(url)
        walker.skipDescendants()
    }
    for url in found { try fm.removeItem(at: url) }
}

/// Deletes workspaces of other Builder versions: visible siblings in the support folder whose
/// `.builder-version` marker names a different version. The private Python, the shared venv and
/// directories without a marker are never touched.
public func removeOldWorkspaces(_ paths: BuilderPaths, keeping version: String) {
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: paths.support.path)) ?? []
    where !name.hasPrefix(".") && name != paths.python.lastPathComponent && name != paths.venv.lastPathComponent && name != version {
        let dir = paths.support.appendingPathComponent(name)
        guard let marker = try? String(contentsOf: dir.appendingPathComponent(versionMarker), encoding: .utf8),
              marker != version, let trash = try? moveToTrash(dir) else { continue }
        try? fm.removeItem(at: trash)
    }
}

/// Ready when the private Python is installed and the shared venv was built from the current
/// requirements.txt. Otherwise red: 25 MB of Python plus 7 MB of packages to fetch, or only the
/// packages when Python is already there (a new requirements.txt).
public func buildToolsCheck(paths: BuilderPaths, version: String) -> CheckState {
    let workspace = paths.workspace(version: version)
    guard PythonRuntime.isInstalled(paths) else { return .blocked("A private Python and the lifter's packages, about 32 MB download") }
    guard FileManager.default.fileExists(atPath: paths.venvPython.path),
          let requirements = try? sha256Hex(of: workspace.appendingPathComponent("requirements.txt")),
          let recorded = try? String(contentsOf: paths.venv.appendingPathComponent(".build-requirements-sha256"), encoding: .utf8),
          recorded.trimmingCharacters(in: .whitespacesAndNewlines) == requirements
    else { return .blocked("Packages need to be set up again (small download)") }
    return .ready("Installed")
}

/// The disk space the files under `url` take (allocated, so APFS clones and sparse files count
/// as the space they use). 0 when it is not there.
public func allocatedSize(of url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
    guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
    var total: Int64 = 0
    for case let file as URL in walker {
        guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
        total += Int64(values.totalFileAllocatedSize ?? 0)
    }
    return total
}

/// "612 MB", "1.4 GB": sizes as Finder shows them.
public func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
