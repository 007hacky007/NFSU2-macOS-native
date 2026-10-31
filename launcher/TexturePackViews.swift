// The Texture Packs window (TexturePacks.swift): the packs on this Mac, in the order the
// engine uses them; the community's packs to download or import, with a search; and
// Import Texture Pack… for any other pack.
import AppKit
import SwiftUI

enum TexturePackWindow {
    private static var window: NSWindow?
    static let size = NSSize(width: 680, height: 720)
    static func show(store: TexturePackStore, model: LauncherModel) {
        TexturePackCatalog.shared.refresh()              // the list from the repository, once per launch
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        window = make(store: store, model: model)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
    static func make(store: TexturePackStore, model: LauncherModel) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Texture Packs"
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(calibratedRed: 0.067, green: 0.071, blue: 0.082, alpha: 1)
        w.contentView = NSHostingView(rootView: TexturePackManagerView(store: store, model: model))
        return w
    }
}

struct TexturePackManagerView: View {
    @ObservedObject var store: TexturePackStore
    @ObservedObject var model: LauncherModel
    @ObservedObject var catalog = TexturePackCatalog.shared
    @State var search = ""
    @State var category = "all"

    private var available: [CatalogPack] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        return catalog.packs.filter { c in
            guard store.pack(c.id) == nil, category == "all" || c.category == category else { return false }
            let text = (c.name + " " + c.author + " " + c.description + " " + c.kind).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
    private var importing: [String] { store.phase.keys.filter { $0.hasPrefix("import-") }.sorted() }

    var body: some View {
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Texture Packs").font(.system(size: 19, weight: .bold)).foregroundColor(Theme.text)
                        Text("The community's texture mods, drawn in place of the game's own textures. Your game folder stays as it is. With no pack on, the game looks as in the original.")
                            .font(.system(size: 11.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Import Texture Pack…") { store.importPanel(for: nil) }
                            .buttonStyle(PrimaryButtonStyle.Small()).disabled(model.location == nil)
                        Text("Any pack, also one not in the list:\n.tpf, TexWizard, .zip, .7z, .rar or a folder")
                            .font(.system(size: 10)).foregroundColor(Theme.dim).multilineTextAlignment(.trailing)
                            .fixedSize()
                    }
                }
                ScrollView {
                    VStack(spacing: 12) {
                        if !store.installed.isEmpty || !importing.isEmpty {
                            Card("On this Mac · where two change the same texture, the higher one wins") {
                                ForEach(store.installed) { p in InstalledPackRow(store: store, pack: p) }
                                ForEach(importing, id: \.self) { id in BusyLine(text: store.phase[id] ?? "", fraction: nil) }
                            }
                        }
                        ForEach(store.errors.keys.filter { $0.hasPrefix("import-") || $0 == "store" }.sorted(), id: \.self) { k in
                            Text(store.errors[k] ?? "").font(.system(size: 11)).foregroundColor(Theme.bad)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Card("Packs from the community · \(catalog.packs.count) in the list, most popular first") {
                            HStack(spacing: 8) {
                                TextField("Search by name, author or what it changes", text: $search)
                                    .textFieldStyle(RoundedBorderTextFieldStyle()).font(.system(size: 12))
                                Picker("", selection: $category) {
                                    ForEach(CatalogPack.categories, id: \.0) { Text($0.1).tag($0.0) }
                                }.labelsHidden().frame(width: 150)
                            }
                            ForEach(available) { c in
                                CatalogPackRow(store: store, pack: c, canAdd: model.location != nil)
                            }
                            if catalog.packs.isEmpty {
                                Text("The list of packs could not be read. Import Texture Pack… still takes any pack.")
                                    .font(.system(size: 11)).foregroundColor(Theme.bad)
                            } else if available.isEmpty {
                                Text(search.isEmpty && category == "all" ? "Every pack of the list is on this Mac."
                                     : "No pack in the list matches. Import Texture Pack… takes any other.")
                                    .font(.system(size: 11)).foregroundColor(Theme.dim)
                            }
                        }
                    }
                }
                Text("Download: the release tested with this port, from the author's page (checked by SHA-256). Details: the pack's page on its site. The Upscaled HUD switch comes after these packs. Cmd-T in the game shows the original textures.")
                    .font(.system(size: 10.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .frame(width: TexturePackWindow.size.width, height: TexturePackWindow.size.height)
    }
}

struct BusyLine: View {
    let text: String
    let fraction: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.system(size: 11)).foregroundColor(Theme.dim)
            if let f = fraction { ProgressView(value: f).accentColor(Theme.accent) }
            else { ProgressView().progressViewStyle(LinearProgressViewStyle()).accentColor(Theme.accent) }
        }
    }
}

struct InstalledPackRow: View {
    @ObservedObject var store: TexturePackStore
    let pack: InstalledPack
    var body: some View {
        let i = store.installed.firstIndex(of: pack) ?? 0
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name + (pack.author.isEmpty ? "" : "  ·  " + pack.author))
                    .font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.text)
                Text("\(pack.textures) textures · \(formatBytes(pack.bytes)) · \(pack.source)")
                    .font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = store.phase[pack.id] { BusyLine(text: p, fraction: store.fraction[pack.id]) }
                if let e = store.errors[pack.id] {
                    Text(e).font(.system(size: 11)).foregroundColor(Theme.bad).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Button("↑") { store.move(pack.id, by: -1) }.buttonStyle(SecondaryButtonStyle()).disabled(i == 0)
                .help("Higher: its textures win over the packs below")
            Button("↓") { store.move(pack.id, by: 1) }.buttonStyle(SecondaryButtonStyle())
                .disabled(i == store.installed.count - 1)
            Button("Remove") { confirmRemove() }.buttonStyle(SecondaryButtonStyle())
            Toggle("", isOn: Binding(get: { pack.enabled }, set: { store.setEnabled(pack.id, $0) }))
                .labelsHidden().toggleStyle(SwitchToggleStyle())
        }
    }
    private func confirmRemove() {
        let a = NSAlert()
        a.messageText = "Remove \(pack.name)?"
        a.informativeText = "The pack made from it (\(formatBytes(pack.bytes))) is deleted from this Mac. You can download or import it again."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.remove(pack.id) }
    }
}

struct CatalogPackRow: View {
    @ObservedObject var store: TexturePackStore
    let pack: CatalogPack
    let canAdd: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name).font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.text)
                    Text("by \(pack.author) · \(pack.kind)" + (pack.size > 0 ? " · \(formatBytes(pack.size))" : ""))
                        .font(.system(size: 11)).foregroundColor(Theme.dim)
                    Text(pack.description).font(.system(size: 11)).foregroundColor(Theme.text.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if store.phase[pack.id] == nil {
                    Button("Details") { NSWorkspace.shared.open(pack.page) }.buttonStyle(SecondaryButtonStyle())
                        .help("Opens the pack's page: " + pack.page.absoluteString)
                    if pack.download != nil {
                        Button("Download") { store.download(pack) }.buttonStyle(PrimaryButtonStyle.Small())
                            .disabled(!canAdd || store.busy)
                    } else {
                        Button("Import Downloaded File…") { store.importPanel(for: pack) }.buttonStyle(SecondaryButtonStyle())
                            .disabled(!canAdd)
                            .help("Choose the file you downloaded from the pack's page")
                    }
                }
            }
            if let n = pack.note {
                Text(n).font(.system(size: 10.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            if let p = store.phase[pack.id] { BusyLine(text: p, fraction: store.fraction[pack.id]) }
            if let e = store.errors[pack.id] {
                Text(e).font(.system(size: 11)).foregroundColor(Theme.bad).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

extension PrimaryButtonStyle {
    /// The accent button at the size of the secondary ones.
    struct Small: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }
        private struct Label: View {
            let configuration: Configuration
            @Environment(\.isEnabled) var enabled
            var body: some View {
                configuration.label
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.black.opacity(enabled ? 0.88 : 0.45))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(enabled ? Theme.accent.opacity(configuration.isPressed ? 0.72 : 1) : Color.white.opacity(0.15)))
            }
        }
    }
}

/// The launcher's row: one line, and the button that opens the window.
struct TexturePacksRow: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var store: TexturePackStore
    private var text: String {
        let on = store.installed.filter { $0.enabled }
        if on.isEmpty { return "Community texture mods for roads, sky and menus. None on: the original game." }
        return "On: " + on.map { $0.name }.joined(separator: ", ")
    }
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Texture packs").font(.system(size: 12.5)).foregroundColor(Theme.text)
                Text(text).font(.system(size: 11)).foregroundColor(Theme.dim).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button("Manage…") { TexturePackWindow.show(store: store, model: model) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }
}
