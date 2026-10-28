import AppKit
import SwiftUI

final class VaultModel: ObservableObject {
    let saves: SaveManagerModel
    @Published var endpoint: String
    @Published var phrase = ""
    @Published var remember = false
    @Published var busy = false
    @Published var linked = false
    @Published var checked = false
    @Published var status = "Cloud saving is off. Linking and every transfer require your action."
    @Published var remoteNames: [String] = []
    private var keys: VaultKeys?
    private var remote: VaultDownload?
    private var remoteZip: Data?
    init(saves: SaveManagerModel, server: String) { self.saves = saves; endpoint = VaultAPI.defaultEndpoint(server: server) }
    private func work<T>(_ action: @escaping () throws -> T, then: @escaping (T) throws -> Void) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try action() }
            DispatchQueue.main.async {
                defer { self.busy = false }
                do { try then(result.get()) } catch { self.status = error.localizedDescription }
            }
        }
    }
    private func api() throws -> VaultAPI {
        guard let keys = keys else { throw SaveError("Link a keyphrase first.") }
        return VaultAPI(endpoint: try VaultAPI.endpoint(endpoint), token: keys.token)
    }
    private func idleGame() throws {
        guard !saves.gameRunning() else { throw SaveError("Quit the game before checking or transferring cloud saves.") }
    }
    private func attempt(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
    func generate() { attempt { phrase = try VaultCrypto.newPhrase(); status = "Copy the new keyphrase and keep it safe before linking. Anyone with it can access these saves." } }
    func copyPhrase() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(phrase, forType: .string); status = "Keyphrase copied. Keep it private; it cannot be recovered if lost." }
    func recall() { attempt { let saved = try VaultKeychain.recall(); phrase = saved.phrase; endpoint = saved.endpoint; remember = true; status = "Keychain link loaded. Click Link keyphrase to use it." } }
    func link() {
        attempt {
            let normalized = try VaultCrypto.normalize(phrase), endpoint = try VaultAPI.endpoint(self.endpoint).absoluteString
            let remember = self.remember
            work({ try VaultCrypto.keys(normalized) }) { keys in
                if remember { try VaultKeychain.remember(phrase: normalized, endpoint: endpoint) }
                self.keys = keys; self.phrase = normalized; self.endpoint = endpoint
                self.linked = true; self.checked = false; self.remote = nil; self.remoteZip = nil; self.remoteNames = []
                self.status = "Linked on this Mac. Nothing has been sent. Check cloud to inspect its version."
            }
        }
    }
    func unlink() { attempt { try VaultKeychain.forget(); keys = nil; phrase = ""; linked = false; checked = false; remote = nil; remoteZip = nil; remoteNames = []; remember = false; status = "Unlinked and removed from Keychain. Local and cloud saves were kept." } }
    func check() {
        attempt {
            try idleGame(); let api = try api(), keys = self.keys!
            checked = false
            work({ () throws -> (VaultDownload?,Data?,[String]) in
                guard let download = try api.get() else { return (nil,nil,[]) }
                let zip = try VaultCrypto.unpack(download.box, keys: keys)
                let entries = try SaveArchive.decode(zip)
                let names = entries.compactMap { SaveStore.profileName($0.path) }
                if !names.isEmpty { _ = try SaveStore.validated(zip) }
                return (download,zip,names)
            }) { download,zip,names in
                self.remote = download; self.remoteZip = zip; self.remoteNames = names.sorted(); self.checked = true
                if let download = download {
                    let time = DateFormatter.localizedString(from: download.remote.saved, dateStyle: .medium, timeStyle: .short)
                    self.status = names.isEmpty ? "The cloud version has no profiles. It cannot replace your local careers." : "Cloud saved \(time): \(names.sorted().joined(separator: ", ")). Choose which copy to keep."
                } else { self.status = "No cloud copy exists for this keyphrase. Send local saves to create one." }
            }
        }
    }
    private func confirm(_ title: String, _ detail: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: action); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func send() {
        attempt {
            try idleGame(); guard checked else { throw SaveError("Check the current cloud version before sending.") }
            let api = try api(), keys = self.keys!, entries = VaultPayload.filtered(try saves.store.snapshot())
            let names = entries.compactMap { SaveStore.profileName($0.path) }
            guard !names.isEmpty else { throw SaveError("An empty local save folder cannot overwrite the cloud.") }
            _ = try SaveStore.validated(SaveArchive.encode(entries))
            guard confirm("Use local careers in the cloud?", "Send: \(names.sorted().joined(separator: ", "))\n\nCloud: \(remoteNames.isEmpty ? "No profiles" : remoteNames.joined(separator: ", "))\n\nThe current cloud copy is kept in your backups folder before it is replaced.", action: "Send local") else { return }
            let revision = remote?.remote.revision
            if let zip = remoteZip { _ = try saves.store.keepArchive(zip, label: "cloud-before-send") }
            checked = false
            work({ try api.put(VaultCrypto.pack(entries, keys: keys), revision: revision) }) { _ in
                self.remote = nil; self.remoteZip = nil; self.remoteNames = []
                self.status = "Local careers sent. Check cloud again before another transfer."
            }
        }
    }
    func download() {
        attempt {
            try idleGame(); guard checked, let expected = remote, !remoteNames.isEmpty else { throw SaveError("Check a cloud version containing profiles first.") }
            guard confirm("Use the cloud careers on this Mac?", "Cloud: \(remoteNames.joined(separator: ", "))\n\nThis replaces local careers, even if the cloud is older. Your current local saves are backed up first. Device settings and local screenshots stay on this Mac.", action: "Download cloud") else { return }
            let api = try api(), keys = self.keys!
            checked = false
            work({ () throws -> Data in
                guard let latest = try api.get(), latest.remote.revision == expected.remote.revision else { throw VaultConflict() }
                return try VaultCrypto.unpack(latest.box, keys: keys)
            }) { zip in
                try self.idleGame()
                let entries = try SaveStore.validated(zip)
                let merged = try VaultPayload.restorable(entries, local: self.saves.store.snapshot())
                try self.saves.store.restore(merged, gameRunning: self.saves.gameRunning, cloud: true)
                self.saves.refresh(); self.status = "Cloud careers downloaded. Previous local saves are in the backups folder."
            }
        }
    }
    func keepBoth() {
        attempt {
            guard checked, let zip = remoteZip else { throw SaveError("Check the cloud version first.") }
            _ = try saves.store.keepArchive(zip, label: "cloud-copy")
            status = "Cloud ZIP saved in the backups folder. Local careers were kept."
        }
    }
}

struct VaultView: View {
    @ObservedObject var model: VaultModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Optional encrypted cloud saves").font(.headline)
            TextField("Vault URL", text: $model.endpoint).disabled(model.linked).accessibilityLabel("Cloud vault URL")
            if !model.linked {
                SecureField("Eight-word keyphrase", text: $model.phrase).accessibilityLabel("Cloud keyphrase")
                HStack {
                    Button("New keyphrase", action: model.generate)
                    Button("Copy keyphrase", action: model.copyPhrase).disabled(model.phrase.isEmpty)
                    Button("Load from Keychain", action: model.recall)
                    Button("Link keyphrase", action: model.link).disabled(model.phrase.isEmpty)
                }
                Toggle("Remember this link in Keychain", isOn: $model.remember)
            } else {
                HStack {
                    Button("Check cloud", action: model.check)
                    Button("Send local", action: model.send).disabled(!model.checked)
                    Button("Download cloud", action: model.download).disabled(!model.checked || model.remoteNames.isEmpty)
                    Button("Keep both copies", action: model.keepBoth).disabled(!model.checked || model.remoteNames.isEmpty)
                    Button("Unlink", action: model.unlink)
                }
            }
            if model.busy { ProgressView().scaleEffect(0.7).frame(height: 18) }
            Text(model.status).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }.disabled(model.busy)
    }
}
