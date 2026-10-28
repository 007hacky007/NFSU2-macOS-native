import AppKit
import SwiftUI

final class SaveManagerModel: ObservableObject {
    let store: SaveStore
    let gameRunning: () -> Bool
    @Published var profiles: [SaveProfile] = []
    @Published var status = ""
    init(saves: URL, registry: URL, gameRunning: @escaping () -> Bool) {
        store = SaveStore(saves: saves, registry: registry); self.gameRunning = gameRunning
        refresh()
    }
    func refresh() { perform { self.profiles = try self.store.profiles() } }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { status = error.localizedDescription }
    }
    func backup() {
        guard !gameRunning() else { status = "Quit the game before making a consistent backup."; return }
        perform { let url = try store.backup(); status = "Backup saved: \(url.lastPathComponent)" }
    }
    func export() {
        guard !gameRunning() else { status = "Quit the game before exporting saves."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "nfsu2-saves.zip"; panel.allowedFileTypes = ["zip"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try store.export(to: url); status = "Exported \(profiles.count) profiles." }
    }
    func restore() {
        guard !gameRunning() else { status = "Quit the game before importing or restoring saves."; return }
        let panel = NSOpenPanel(); panel.allowedFileTypes = ["zip"]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let data = try SaveStore.readArchive(url), entries = try SaveStore.validated(data)
            let names = entries.compactMap { SaveStore.profileName($0.path) }.sorted().joined(separator: ", ")
            let alert = NSAlert(); alert.messageText = "Import saves?"
            alert.informativeText = "Profiles: \(names)\n\nA full backup replaces the save folder. A profile archive adds or replaces matching profiles. Your current saves are backed up first."
            alert.addButton(withTitle: "Import"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try store.restore(data, gameRunning: gameRunning)
            refresh(); status = "Saves imported. A pre-restore ZIP is in the backups folder."
        }
    }
    func revealBackups() { perform { try FileManager.default.createDirectory(at: store.backups, withIntermediateDirectories: true); NSWorkspace.shared.open(store.backups) } }
}

struct SaveManagerView: View {
    @ObservedObject var model: SaveManagerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Saved careers").font(.title2)
            Text("Local backups and ZIP imports stay on this Mac.").foregroundColor(.secondary)
            List(model.profiles) { p in
                HStack {
                    Text(p.name).font(.headline)
                    Spacer()
                    Text(p.modified, style: .date).foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(p.bytes), countStyle: .file)).foregroundColor(.secondary)
                }
            }.frame(minHeight: 140)
            HStack {
                Button("Refresh", action: model.refresh)
                Button("Back up", action: model.backup)
                Button("Export ZIP...", action: model.export)
                Button("Import / Restore...", action: model.restore)
                Button("Backups folder", action: model.revealBackups)
            }
            Text(model.status.isEmpty ? "Quit the game before backing up or replacing saves." : model.status)
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(minWidth: 640, minHeight: 330)
    }
}

enum SaveManagerWindow {
    private static var window: NSWindow?
    static func show(saves: URL, registry: URL, serverURL: String, gameRunning: @escaping () -> Bool) {
        if let existing = window, existing.isVisible { existing.makeKeyAndOrderFront(nil); return }
        let model = SaveManagerModel(saves: saves, registry: registry, gameRunning: gameRunning)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 380), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
        window.title = "NFSU2 Saves"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SaveManagerView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
    }
}
