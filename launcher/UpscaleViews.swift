// The upscaled texture pack's card in the Texture Packs window (UpscaleStore.swift):
// Build (from the player's own game files; the model is fetched the first time),
// Stop, Delete, the switch (off: the original game), which parts, the GPU memory,
// the size and collecting textures while playing.
import AppKit
import SwiftUI

struct UpscaledPackCard: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var store: UpscaleStore

    private var status: String {
        if let i = store.info {
            return "\(i.textures) textures · \(formatBytes(i.bytes)) · \(i.scale)x · made \(i.built)"
        }
        return "Not made yet. Build makes it from your game files on this Mac (a few minutes; nothing leaves your Mac)."
            + (store.hasModel ? "" : " The first time it downloads the upscaling model (9 MB, CC0) from its author's GitHub.")
    }

    var body: some View {
        Card("Upscaled textures · made from your game files") {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sharper roads, buildings, signs, cars and garage")
                        .font(.system(size: 12.5, weight: .medium)).foregroundColor(Theme.text)
                    Text("The game's own textures 4x larger with Kim2091's PBRify Upscaler (SPAN, CC0), kept to their colours. Off: as in the original game.")
                        .font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    Text(status).font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if store.busy {
                    Button("Stop") { store.cancel() }.buttonStyle(SecondaryButtonStyle())
                } else {
                    if store.info != nil || store.hasModel {
                        Button("Delete") { confirmDelete() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Button(store.info == nil ? "Build" : "Build Again") { build() }
                        .buttonStyle(PrimaryButtonStyle.Small()).disabled(model.location == nil)
                        .help("Makes the pack from your game files; textures already made are kept")
                }
                Toggle("", isOn: $model.upscaledTextures).labelsHidden().toggleStyle(SwitchToggleStyle())
                    .disabled(store.info == nil)
            }
            if let p = store.phase { BusyLine(text: p, fraction: store.fraction) }
            if let e = store.error {
                Text(e).font(.system(size: 11)).foregroundColor(Theme.bad).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 6) {
                Text("Use for").font(.system(size: 11)).foregroundColor(Theme.dim)
                ForEach(UpscalePack.parts.filter { $0 != "other" }, id: \.self) { p in
                    PartChip(title: UpscalePack.partNames[p] ?? p, on: store.parts.contains(p)) {
                        if store.parts.contains(p) { store.parts.remove(p) } else { store.parts.insert(p) }
                    }
                }
            }
            HStack(alignment: .center, spacing: 14) {
                HStack(spacing: 4) {
                    Text("GPU memory").font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize()
                    Picker("", selection: $store.budget) {
                        ForEach(UpscaleStore.budgets, id: \.self) { b in
                            Text(b == 0 ? "Automatic, " + String(format: "%.1f GB", Double(UpscaleStore.autoBudget) / 1024) : "\(b / 1024) GB").tag(b)
                        }
                    }.labelsHidden().frame(width: 150)
                    .help("Upscaled textures beyond it stay the game's own; the textures of a race need well under 1 GB")
                }
                HStack(spacing: 4) {
                    Text("Size").font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize()
                    Picker("", selection: $store.scale) {
                        Text("Automatic (\(UpscaleBuilder.autoScale)x)").tag(0)
                        Text("2x").tag(2)
                        Text("4x").tag(4)
                    }.labelsHidden().frame(width: 130).disabled(store.busy)
                    .help("4x needs about 1.2 GB on disk and more GPU memory; Build again after a change")
                }
                Spacer()
                Button("Import Model…") { store.importModelPanel() }.buttonStyle(SecondaryButtonStyle())
                    .disabled(store.busy)
                    .help("A copy of \(UpscalePack.modelFile) you downloaded from \(UpscalePack.modelPage.absoluteString)")
            }
            Toggle(isOn: $store.collect) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Collect textures while playing").font(.system(size: 12)).foregroundColor(Theme.text)
                    Text("The game keeps a copy of the textures it loads that Build cannot read from the files (menus, cars), for the next Build. Off: as in the original game.")
                        .font(.system(size: 10.5)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }.toggleStyle(SwitchToggleStyle())
        }
    }

    private func build() {
        guard let loc = model.location else { return }
        store.build(game: loc.folder) { ok in if ok && !model.upscaledTextures { model.upscaledTextures = true } }
    }
    private func confirmDelete() {
        let a = NSAlert()
        a.messageText = "Delete the upscaled textures?"
        a.informativeText = "The pack" + (store.info.map { " (\(formatBytes($0.bytes)))" } ?? "")
            + ", the textures collected while playing and the model are deleted from this Mac. Build makes them again."
        a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.delete(); model.upscaledTextures = false }
    }
}

private struct PartChip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10.5, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Color.black.opacity(0.85) : Theme.dim)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Theme.accent : Color.white.opacity(0.08)))
        }.buttonStyle(PlainButtonStyle())
    }
}
