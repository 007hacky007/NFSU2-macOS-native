// NFSU2 launcher: the app's main executable.
//
// Contents/MacOS/NFSU2              this launcher
// Contents/MacOS/nfsu2-engine       the port (original look)
// Contents/MacOS/nfsu2-engine-hd    the port, HD build (optional)
//
// It finds and checks the game, offers the few choices a player needs, then
// starts the engine as a child process, steps out of the Dock and quits when the
// engine ends (with its exit status).  If the window is turned
// off and the game is ready it starts the engine right away (hold Option to see
// the window anyway).
//
// Environment (scripts and tests):
//   NFSU2_SKIP_LAUNCHER=1        start the engine without showing the window
//   NFSU2_ENGINE=original|hd     engine choice for this start
//   NFSU2_LAUNCHER_SNAPSHOT=x.png  draw the window into a PNG and quit (never shown)
//   NFSU2_LAUNCHER_STATE=ready|notfound|unsupported|embedded|copying|done|uhud|uhud-busy|texpacks|texpacks-window|texpacks-busy
//                                fake state for the snapshot (uhud: ready, with a UHUD pack added;
//                                uhud-busy: downloading it; texpacks: two texture packs, one on;
//                                texpacks-window: the Texture Packs window with them; texpacks-busy:
//                                the same, one downloading)
//   NFSU2_LAUNCHER_TEST=portable:<game folder>:<destination.app>   build a portable copy, quit
//   NFSU2_LAUNCHER_TEST=uhud:<mod .7z or folder>:<game folder>:<pack>   make a UHUD pack, quit
//   NFSU2_LAUNCHER_TEST=uhud-download:<game folder>:<pack>   download the mod and make the pack, quit
//   NFSU2_LAUNCHER_TEST=texpack:<mod>:<game folder>:<pack>   make a texture pack (TexturePackBuilder.swift), quit
//   NFSU2_LAUNCHER_TEST=texpack-download:<catalog id>:<game folder>:<store>   Download as the button
//                                does (list fetched as the window does), into <store> instead of
//                                Application Support/NFSU2/TexturePacks, quit
//   NFSU2_LAUNCHER_TEST=texpack-catalog:<store>   load and fetch the texture pack list, say which one is used
//   NFSU2_LAUNCHER_TEST=texpack-import:<catalog id or ->:<mod>:<game folder>:<store>   Import… the same way
//   NFSU2_LAUNCHER_TEST=play     window off screen, press Play after a second (tests the
//                                normal path: window open -> Play -> engine)
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = LauncherModel()
    var window: NSWindow?
    let env = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ note: Notification) {
        model.refreshNow()

        if let t = env["NFSU2_LAUNCHER_TEST"], t.hasPrefix("portable:") {
            let parts = t.dropFirst("portable:".count).split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { print("bad NFSU2_LAUNCHER_TEST"); exit(2) }
            model.startPortable(from: URL(fileURLWithPath: parts[0]), to: URL(fileURLWithPath: parts[1]))
            return
        }

        if let t = env["NFSU2_LAUNCHER_TEST"], t.hasPrefix("texpack") {
            let parts = t.split(separator: ":", maxSplits: 4).map(String.init)
            let finish: (Bool) -> Void = { ok in
                if !ok { print("texture pack FAILED: \(self.model.packs.errors.values.joined(separator: "; "))") }
                else { print("installed: " + self.model.packs.installed.map { "\($0.id) on=\($0.enabled)" }.joined(separator: ", "))
                       print("NFSU2_TEXPACKS=" + self.model.packs.enabledPaths.joined(separator: ":")) }
                exit(ok ? 0 : 1)
            }
            switch (parts.first, parts.count) {
            case ("texpack", 4):
                DispatchQueue.global().async {
                    do {
                        let s = try PackBuilder.build(mod: URL(fileURLWithPath: parts[1]), game: URL(fileURLWithPath: parts[2]),
                                                      to: URL(fileURLWithPath: parts[3])) { print($0) }
                        print("texture pack: \(s.textures) textures (\(s.texmod) TexMod, \(s.named) by name, \(s.content) by content), \(s.bytes) bytes")
                        print("  from: " + s.sources.joined(separator: ", "))
                        if !s.skipped.isEmpty { print("  skipped \(s.skipped.count): " + s.skipped.prefix(8).joined(separator: "; ")) }
                        exit(0)
                    } catch { print("texture pack FAILED: \((error as? UHUDPack.Failure)?.message ?? error.localizedDescription)"); exit(1) }
                }
            case ("texpack-download", 4):
                TexturePackStore.testDir = URL(fileURLWithPath: parts[3]); model.packs.load()
                model.packs.game = { URL(fileURLWithPath: parts[2]) }
                TexturePackCatalog.shared.refresh { _ in        // the list as the window has it
                    guard let c = TexturePackCatalog.pack(parts[1]) else { print("no catalog pack \(parts[1])"); exit(2) }
                    self.model.packs.download(c, done: finish)
                }
            case ("texpack-catalog", 2):
                TexturePackStore.testDir = URL(fileURLWithPath: parts[1])
                let cat = TexturePackCatalog.shared
                print("before: \(cat.source) \(cat.updated), \(cat.packs.count) packs")
                cat.refresh { src in
                    print("list: \(src) \(cat.updated), \(cat.packs.count) packs, \(cat.packs.filter { $0.download != nil }.count) with Download")
                    exit(0)
                }
            case ("texpack-import", 5):
                TexturePackStore.testDir = URL(fileURLWithPath: parts[4]); model.packs.load()
                model.packs.game = { URL(fileURLWithPath: parts[3]) }
                model.packs.importMod(URL(fileURLWithPath: parts[2]), for: TexturePackCatalog.pack(parts[1]), done: finish)
            default: print("bad NFSU2_LAUNCHER_TEST"); exit(2)
            }
            return
        }
        if let t = env["NFSU2_LAUNCHER_TEST"], t.hasPrefix("uhud-download:") {
            let parts = t.dropFirst("uhud-download:".count).split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { print("bad NFSU2_LAUNCHER_TEST"); exit(2) }
            model.makeUHUD(mod: nil, game: URL(fileURLWithPath: parts[0]), to: URL(fileURLWithPath: parts[1]))
            return
        }
        if let t = env["NFSU2_LAUNCHER_TEST"], t.hasPrefix("uhud:") {
            let parts = t.dropFirst("uhud:".count).split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { print("bad NFSU2_LAUNCHER_TEST"); exit(2) }
            model.makeUHUD(mod: URL(fileURLWithPath: parts[0]), game: URL(fileURLWithPath: parts[1]),
                           to: URL(fileURLWithPath: parts[2]))
            return
        }

        let snapshot = env["NFSU2_LAUNCHER_SNAPSHOT"]
        let option = NSEvent.modifierFlags.contains(.option)
        if snapshot == nil, model.isReady, !option,
           env["NFSU2_SKIP_LAUNCHER"] == "1" || !model.showAtStartup {
            model.play()
            if model.isPlaying { return }      // the engine runs; nothing to show
        }

        if let s = env["NFSU2_LAUNCHER_STATE"] { fakeState(s) }
        buildMenu()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 726),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Need for Speed Underground 2"
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(calibratedRed: 0.067, green: 0.071, blue: 0.082, alpha: 1)
        w.contentView = NSHostingView(rootView: LauncherView(model: model))
        if ["texpacks-window", "texpacks-busy"].contains(env["NFSU2_LAUNCHER_STATE"] ?? "") {
            let tw = TexturePackWindow.make(store: model.packs, model: model)
            w.setContentSize(TexturePackWindow.size); w.contentView = tw.contentView
        }
        w.center()
        w.delegate = self
        window = w

        if env["NFSU2_LAUNCHER_TEST"] == "play" {
            w.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            w.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.model.play() }
            return
        }
        if let path = snapshot {
            w.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            w.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
            return
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Not while the engine runs: hiding the window on Play would otherwise quit us,
    // and open -W / session.sh would stop waiting for the game.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { !model.isPlaying }
    // Closing the window while a copy is being made goes through the quit question.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isCopying { NSApp.terminate(nil); return false }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.shouldTerminate()
    }

    private func fakeState(_ s: String) {
        let exe = URL(fileURLWithPath: "/Users/player/Games/Need for Speed Underground 2/SPEED2.EXE")
        switch s {
        case "ready": model.game = .ready(GameLocation(exe: exe, embedded: false))
        case "notfound": model.game = .notFound
        case "unsupported": model.game = .unsupported(GameLocation(exe: exe, embedded: false), 4_800_512)
        case "embedded": model.game = .ready(GameLocation(exe: exe, embedded: true))
        case "uhud":
            model.game = .ready(GameLocation(exe: exe, embedded: false))
            model.hasUHUDPack = true
        case "uhud-busy":
            model.game = .ready(GameLocation(exe: exe, embedded: false))
            model.uhudBusy = true
            model.uhudPhase = "Downloading the mod from nfsmods.xyz… 1.2 MB of 2.8 MB"
        case "texpacks", "texpacks-window", "texpacks-busy":
            model.game = .ready(GameLocation(exe: exe, embedded: false))
            model.packs.fake([
                InstalledPack(id: "remastered-ug2", name: "Remastered Underground 2", author: "instanity", file: "remastered-ug2.ntxp",
                              enabled: true, textures: 522, bytes: 293_563_248, source: "Imported from underground2rem10.zip"),
                InstalledPack(id: "retextured", name: "RETextured v2.0", author: "Dragozool", file: "retextured.ntxp",
                              enabled: false, textures: 205, bytes: 191_036_416, source: "Imported from nfsu2retex20.zip"),
            ])
            if s == "texpacks-busy" {
                model.packs.phase["scout-ui"] = "Downloading from nfsmods.xyz… 4.6 MB of 11.7 MB"
                model.packs.fraction["scout-ui"] = 0.4
            }
        case "copying":
            model.job = LauncherModel.Job(phase: "Copying the game files…", done: 612_000_000, total: 1_430_000_000)
        case "done":
            var j = LauncherModel.Job(phase: "", done: 1, total: 1)
            j.result = URL(fileURLWithPath: "/Applications/NFSU2 Portable.app")
            model.job = j
        default: break
        }
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About NFSU2", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide NFSU2", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit NFSU2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
