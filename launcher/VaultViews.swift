// Cloud saves: the section at the bottom of the save window (SaveViews.swift).
// Off until the player links a keyphrase, and even then nothing happens by
// itself: every transfer is a button (Check cloud, Send local, Download cloud,
// Keep both copies), and a send or download is asked about first.  No automatic
// upload or sync.  The vault is /vault on the game server of Settings, Online
// (VaultAPI.defaultEndpoint), editable before linking.  The keyphrase stays in
// memory only while it is typed (once linked only its keys are), unless the player
// ticks "Remember in Keychain".
// Format and transfers: VaultCrypto.swift, VaultPayload.swift, VaultAPI.swift.
// The choices follow th0mk's nfsu2-web web/src/app/vault-ui.ts (MIT).
import AppKit
import SwiftUI

final class VaultModel: ObservableObject {
    static let offText = "Your careers stay on this Mac; nothing is sent until you link a keyphrase and choose to send."
    let saves: SaveManagerModel
    @Published var endpoint: String
    @Published var phrase = ""
    @Published var remember = false
    @Published var setup = false                // the link form is open
    @Published var busy = false
    @Published var linked = false
    @Published var checked = false
    @Published var status = VaultModel.offText
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
    private func api() throws -> (VaultAPI, VaultKeys) {
        guard let keys = keys else { throw SaveError("Link a keyphrase first.") }
        return (VaultAPI(endpoint: try VaultAPI.endpoint(endpoint), token: keys.token), keys)
    }
    private func idleGame() throws {
        guard !saves.gameRunning() else { throw SaveError("Quit the game before checking or transferring cloud saves.") }
    }
    private func attempt(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
    private func forgetRemote() { checked = false; remote = nil; remoteZip = nil; remoteNames = [] }

    func generate() { attempt { phrase = try VaultCrypto.newPhrase(); status = "Copy the new keyphrase and keep it safe before linking. Anyone with it can open these saves." } }
    func copyPhrase() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(phrase, forType: .string); status = "Keyphrase copied. Keep it private; it cannot be recovered if lost." }
    func recall() { attempt { let saved = try VaultKeychain.recall(); phrase = saved.phrase; endpoint = saved.endpoint; remember = true; status = "Keychain link loaded. Click Link keyphrase to use it." } }
    func cancelSetup() { setup = false; phrase = ""; status = Self.offText }
    func link() {
        attempt {
            let normalized = try VaultCrypto.normalize(phrase), endpoint = try VaultAPI.endpoint(self.endpoint).absoluteString
            let remember = self.remember
            work({ try VaultCrypto.keys(normalized) }) { keys in
                if remember { try VaultKeychain.remember(phrase: normalized, endpoint: endpoint) }
                // the keys are all a linked window needs: the keyphrase itself is not kept
                self.keys = keys; self.phrase = ""; self.endpoint = endpoint
                self.linked = true; self.setup = false; self.forgetRemote()
                self.status = "Linked on this Mac. Nothing has been sent. Check cloud to see its version."
            }
        }
    }
    func unlink() {
        attempt {
            try VaultKeychain.forget()
            keys = nil; phrase = ""; linked = false; remember = false; forgetRemote()
            status = "Unlinked and removed from Keychain. Local and cloud saves were kept."
        }
    }
    func check() {
        attempt {
            try idleGame(); let (api, keys) = try api()
            forgetRemote()
            work({ () throws -> (VaultDownload?, Data?, [String]) in
                guard let download = try api.get() else { return (nil, nil, []) }
                let zip = try VaultCrypto.unpack(download.box, keys: keys)
                let entries = try SaveArchive.decode(zip)
                // a version with profiles must pass the same checks as an imported backup
                let names = entries.contains { SaveStore.profileName($0.path) != nil }
                    ? try SaveStore.validated(zip).entries.compactMap { SaveStore.profileName($0.path) } : []
                return (download, zip, names)
            }) { download, zip, names in
                self.remote = download; self.remoteZip = zip; self.remoteNames = names.sorted(); self.checked = true
                if let download = download {
                    let time = DateFormatter.localizedString(from: download.remote.saved, dateStyle: .medium, timeStyle: .short)
                    self.status = names.isEmpty ? "The cloud version has no profiles. It cannot replace your local careers."
                        : "Cloud saved \(time): \(names.sorted().joined(separator: ", ")). Choose which copy to keep."
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
            let (api, keys) = try api(), entries = VaultPayload.filtered(try saves.store.snapshot())
            let names = entries.compactMap { SaveStore.profileName($0.path) }
            guard !names.isEmpty else { throw SaveError("An empty local save folder cannot overwrite the cloud.") }
            _ = try SaveStore.validated(SaveArchive.encode(entries))
            guard confirm("Use this Mac's careers in the cloud?",
                          "Send: \(names.sorted().joined(separator: ", "))\n\nCloud: \(remoteNames.isEmpty ? "No profiles" : remoteNames.joined(separator: ", "))\n\nThe current cloud copy is kept in your backups folder before it is replaced.",
                          action: "Send local") else { return }
            let revision = remote?.remote.revision
            if let zip = remoteZip { _ = try saves.store.keepArchive(zip, label: "cloud-before-send") }
            forgetRemote()
            work({ try api.put(VaultCrypto.pack(entries, keys: keys), revision: revision) }) { _ in
                self.status = "Local careers sent. Check cloud again before another transfer."
            }
        }
    }
    func download() {
        attempt {
            try idleGame(); guard checked, let expected = remote, !remoteNames.isEmpty else { throw SaveError("Check a cloud version containing profiles first.") }
            guard confirm("Use the cloud careers on this Mac?",
                          "Cloud: \(remoteNames.joined(separator: ", "))\n\nThis replaces this Mac's careers, even if the cloud is older. Your current saves are backed up first. The game's settings and the covers stay on this Mac.",
                          action: "Download cloud") else { return }
            let (api, keys) = try api()
            forgetRemote()
            work({ () throws -> Data in
                guard let latest = try api.get(), latest.remote.revision == expected.remote.revision else { throw VaultConflict() }
                return try VaultCrypto.unpack(latest.box, keys: keys)
            }) { zip in
                try self.idleGame()
                let checked = try SaveStore.validated(zip).entries
                try self.saves.store.restore(VaultPayload.restorable(checked), gameRunning: self.saves.gameRunning, cloud: true)
                self.saves.refresh(); self.status = "Cloud careers downloaded. Your previous saves are in the backups folder."
            }
        }
    }
    func keepBoth() {
        attempt {
            guard checked, let zip = remoteZip else { throw SaveError("Check the cloud version first.") }
            let url = try saves.store.keepArchive(zip, label: "cloud-copy")
            status = "Cloud copy saved in the backups folder (\(url.lastPathComponent)). This Mac's careers were kept."
        }
    }

    /// NFSU2_LAUNCHER_STATE=saves-cloud (main.swift): linked and checked, for the snapshot.
    func fakeChecked(_ names: [String]) {
        linked = true; checked = true; remoteNames = names
        status = "Cloud saved 31 Oct 2026 at 18:20: \(names.joined(separator: ", ")). Choose which copy to keep."
    }
}

struct VaultView: View {
    @ObservedObject var model: VaultModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Encrypted cloud saves").font(.headline)
                Text(model.linked ? "Linked" : "Off").font(.callout).foregroundColor(model.linked ? .green : .secondary)
                Spacer()
                if !model.linked && !model.setup { Button("Set Up...") { model.setup = true } }
            }
            if model.setup && !model.linked {
                Text("Your saves are encrypted on this Mac with an eight-word keyphrase; the server never sees them. The same keyphrase opens them in the browser game.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Vault").frame(width: 72, alignment: .leading)
                    TextField("https://.../vault", text: $model.endpoint).accessibilityLabel("Cloud vault URL")
                }
                HStack {
                    Text("Keyphrase").frame(width: 72, alignment: .leading)
                    SecureField("Eight-word keyphrase", text: $model.phrase).accessibilityLabel("Cloud keyphrase")
                }
                HStack {
                    Button("New Keyphrase", action: model.generate)
                    Button("Copy", action: model.copyPhrase).disabled(model.phrase.isEmpty)
                    Button("From Keychain", action: model.recall)
                    Toggle("Remember in Keychain", isOn: $model.remember)
                    Spacer()
                    Button("Cancel", action: model.cancelSetup)
                    Button("Link Keyphrase", action: model.link).disabled(model.phrase.isEmpty)
                }
            } else if model.linked {
                Text("Vault: \(model.endpoint)").font(.callout).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                HStack {
                    Button("Check Cloud", action: model.check)
                    Button("Send Local...", action: model.send).disabled(!model.checked)
                    Button("Download Cloud...", action: model.download).disabled(!model.checked || model.remoteNames.isEmpty)
                    Button("Keep Both Copies", action: model.keepBoth).disabled(!model.checked || model.remoteNames.isEmpty)
                    Spacer()
                    Button("Unlink", action: model.unlink)
                }
            }
            HStack(spacing: 6) {
                if model.busy { ProgressView().scaleEffect(0.6).frame(width: 16, height: 16) }
                Text(model.status).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.disabled(model.busy)
    }
}
