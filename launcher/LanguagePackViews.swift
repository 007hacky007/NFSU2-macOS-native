// Settings › Mods › Languages: a row per language that needs a pack
// (LanguagePacks.swift).  Download fetches what it needs from its author's page and
// builds LANGPACKS/<language> in the game folder (outside the app when the game is inside
// it, Paths.languagePacks); Import… takes a local copy (an
// archive or the folder it was unpacked to); Open Page shows where the translations
// that cannot be fetched automatically come from.  The language itself is chosen in
// the main window, once its pack is there.
import AppKit
import SwiftUI

final class LanguagePackStore: ObservableObject {
    @Published var busy: String? = nil          // the language being made
    @Published var note: [String: String] = [:]
    @Published var failed: Set<String> = []
    @Published var installed: [String: Int] = [:]   // files in LANGPACKS/<language>

    /// The languages with a pack to make, in the picker's order.
    static var languages: [String] { Languages.all.map { $0.id }.filter { LanguagePacks.way($0) != nil } }

    func refresh(_ loc: GameLocation?) {
        var n: [String: Int] = [:]
        if let loc = loc {
            for l in LanguagePackStore.languages {
                let dir = Paths.languagePacks(for: loc).appendingPathComponent(l)
                let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                    .filter { !UHUDPack.isDirectory($0) }
                if !files.isEmpty { n[l] = files.count }
            }
        }
        installed = n
    }

    func make(_ lang: String, model: LauncherModel, from src: URL?) {
        guard let loc = model.location, busy == nil else { return }
        let game = loc.folder, packs = Paths.languagePacks(for: loc)
        busy = lang
        failed.remove(lang)
        note[lang] = src == nil ? "Downloading…" : "Making the pack…"
        DispatchQueue.global(qos: .userInitiated).async {
            var res: String? = nil, err: String? = nil
            do {
                if let s = src { res = try LanguagePacks.importCopy(lang: lang, src: s, game: game, packs: packs) }
                else {
                    var last = Date.distantPast
                    res = try LanguagePacks.download(lang: lang, game: game, packs: packs) { what, got, total in
                        guard Date().timeIntervalSince(last) > 0.2 || got >= total else { return }
                        last = Date()
                        let text = what == "Building" ? "Making the pack…"
                            : "\(what): \(formatBytes(got)) of \(formatBytes(total))"
                        DispatchQueue.main.async { self.note[lang] = text }
                    }
                }
            } catch let e as LanguagePacks.Failure { err = e.message }
            catch let e as Mega.Failure { err = e.message }
            catch let e as RarArchive.Failure { err = e.message }
            catch let e as InnoSetup.Failure { err = e.message }
            catch let e as Clickteam.Failure { err = e.message }
            catch let e as UHUDPack.Failure { err = e.message }
            catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                self.busy = nil
                if let e = err { self.note[lang] = e; self.failed.insert(lang) }
                else { self.note[lang] = nil; NSLog("language pack: %@", res ?? "") }
                self.refresh(loc)
                model.languages = Languages.installed(for: loc)
            }
        }
    }

    func importCopy(_ lang: String, model: LauncherModel) {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Import"
        p.message = LanguagePackStore.importHint(lang)
        p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let u = p.url else { return }
        make(lang, model: model, from: u)
    }

    static func importHint(_ lang: String) -> String {
        switch lang {
        case "english": return "Choose VileStuff's English Subtitles Fixed mod as downloaded (.7z), or the folder it was unpacked to."
        case "portuguese": return "Choose the Brazilian Portuguese translation as unpacked (its archive's password is on its page), or its archive."
        case "polish": return "Choose the Polish translation's installer (NFSU2PLv1.1US.exe or UK.exe), the folder it is in, or its archive. It is read, never run."
        case "turkish": return "Choose the folder innoextract made from the Turkish translation's nfsu2tr11.exe."
        case "hungarian": return "Choose GameHunter's nfs_underground2.exe as downloaded, or the folder it is in. It is read, never run."
        case "ukrainian": return "Choose \"Need for Speed Underground 2 - Ukrainian.exe\" as downloaded, or the folder it is in. It is read, never run."
        case "czech": return "Choose nfs-underground-2-cz.zip as downloaded from abcgames.cz, the nfsu2cz-v1.1.exe in it, or the folder it is in. It is read, never run."
        default: return "Choose the folder with the Multi 13 languages mod's archives (nfsug2Multi13Core.rar and the dubs), or one of them."
        }
    }

    static func summary(_ lang: String) -> String {
        switch lang {
        case "english": return "VileStuff's English Subtitles Fixed: the movies' lines whole, for Movie subtitles."
        case "portuguese": return "TraduMix and MixMods' translation. Its site needs a browser: download it there, then Import."
        case "polish": return "PLProjekt's translation. Its site needs a browser: download it there, then Import."
        case "turkish": return "muntazam's translation. Its site needs a browser: download it there, then Import."
        case "hungarian": return "GameHunter's translation (L_zooltan): the text, which writes \u{151} and \u{171} as \u{F5} and \u{FB}."
        case "ukrainian": return "Clark X.'s translation (kuli.com.ua): the text, on the Russian pack's fonts."
        case "czech": return "ROXOR's and PIN\u{10E}A & syn's translation (abcgames.cz): the text, which writes \u{10D}, \u{159}, \u{161} as c, r, s."
        default:
            let what = LanguagePacks.dubs[lang] != nil ? (lang == "japanese" || lang == "russian" ? "Text, voices and movies" : "Voices and movies")
                : lang == "chinese" || lang == "thai" ? "The full text and its fonts" : "The EA logo"
            return "\(what) from KyoriAsh's Multi 13 languages mod."
        }
    }
}

struct LanguagePacksCard: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var store: LanguagePackStore

    var body: some View {
        Card("Languages") {
            Text("Packs for the languages the game folder lacks, made from their authors' downloads; your game's own files stay as they are. Choose the language in the main window.")
                .font(.system(size: 11)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LanguagePackStore.languages, id: \.self) { l in row(l) }
        }
        .onAppear { store.refresh(model.location) }
    }

    private func row(_ l: String) -> some View {
        let name = Languages.all.first { $0.id == l }?.name ?? l
        let files = store.installed[l]
        let busy = store.busy == l
        let way = LanguagePacks.way(l)
        let text = store.note[l] ?? (files != nil
            ? "Installed (\(files!) file\(files == 1 ? "" : "s")). " + LanguagePackStore.summary(l)
            : LanguagePackStore.summary(l) + (way == .download ? " \(formatBytes(LanguagePacks.downloadSize(l)))." : ""))
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(l == "english" ? "English subtitles" : name).font(.system(size: 12.5)).foregroundColor(Theme.text)
                Text(text).font(.system(size: 11))
                    .foregroundColor(store.failed.contains(l) ? Theme.warn : Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                if way == .download {
                    Button(files == nil ? "Download" : "Update") { store.make(l, model: model, from: nil) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.location == nil || store.busy != nil)
                } else if let page = LanguagePacks.pages[l] {
                    Button("Open Page") { NSWorkspace.shared.open(page) }.buttonStyle(SecondaryButtonStyle())
                }
                Button("Import…") { store.importCopy(l, model: model) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.location == nil || store.busy != nil)
            }
            .opacity(busy ? 0.5 : 1)
        }
    }
}
