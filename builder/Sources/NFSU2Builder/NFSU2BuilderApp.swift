import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BuilderModel()
    private var terminateSignal: DispatchSourceSignal?
    private var snapshotWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when started with `swift run`, where there is no app bundle to say so.
        NSApp.setActivationPolicy(.regular)
        // An update for the launcher works out of sight; the launcher shows its progress.
        if model.launcherUpdate == nil { NSApp.activate(ignoringOtherApps: true) }
        // The pipeline runs in its own process group, so a plain SIGTERM to the Builder would
        // orphan it; route the signal through the normal quit path instead. terminate(_:) is
        // started from the run loop, not from inside a main-queue block: while it waits for the
        // pipeline to exit, the runner's main-queue callbacks must still be able to run.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [self] in RunLoop.main.perform { self.quit() } }
        source.resume()
        terminateSignal = source
        // Quit Apple Events (logout, restart, `osascript ... quit`) take the same path as Cmd-Q.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEQuitApplication))
        model.start()
        if let folder = UserDefaults.standard.string(forKey: "SnapshotFolder") { startSnapshots(URL(fileURLWithPath: folder)) }
    }

    /// For release testing (`--args -SnapshotFolder <dir>`): a PNG of the window's content each
    /// time what it shows changes. A copy of the content is drawn in a window kept off screen (as
    /// the launcher's NFSU2_LAUNCHER_SNAPSHOT does), which needs no screen recording permission.
    private func startSnapshots(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: RootView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderBack(nil)
        snapshotWindow = window
        var last = "", count = 0, pending = ""
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [model] _ in
            var key = "\(model.phaseName) \(model.states)"
            if case let .building(step, fraction, _) = model.phase { key = "building \(step) \(Int(fraction * 10))" }
            // Wait one tick after a change so the off-screen copy has been laid out and drawn.
            guard key != last else { return }
            guard key == pending else { pending = key; return }
            let fit = host.fittingSize
            window.setContentSize(NSSize(width: 560, height: max(470, fit.height)))
            host.layoutSubtreeIfNeeded()
            host.display()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            last = key
            count += 1
            let name = String(format: "%03d-%@.png", count, model.phaseName)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
        }
    }

    /// NSApp.terminate returns without quitting while a sheet is attached, so close any sheet first.
    func quit() {
        model.showingSupported = false
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        RunLoop.main.perform { NSApp.terminate(nil) }
    }

    @objc private func handleQuit(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        quit()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Closing the window or quitting during a build first stops the pipeline and waits for it to exit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasRunningWork else { return .terminateNow }
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        model.stopAll(then: reply)
        // PipelineRunner escalates to SIGKILL after 5 s; never hang the quit beyond that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: reply)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopAll(then: {})
    }
}

@main
struct NFSU2BuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("NFSU2 Builder") {
            RootView(model: delegate.model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button("Quit NFSU2 Builder") { delegate.quit() }.keyboardShortcut("q")
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        Group {
            switch model.phase {
            case .checklist:
                ChecklistView(model: model)
            case let .building(stepID, fraction, log):
                BuildView(model: model, stepID: stepID, fraction: fraction, log: log)
            case let .finished(app):
                ResultView(model: model, outcome: .success(app))
            case let .failed(step, message, log):
                ResultView(model: model, outcome: .failure(step: step, message: message, log: log))
            case .quitToInstall:
                ResultView(model: model, outcome: .quitToInstall)
            }
        }
        .alert(isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Alert(title: Text(model.notice ?? ""))
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 470, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .background(GrowWindowToFit(content: "\(model.states)\(model.dataDetails ?? "")\(model.phaseName)"))
    }
}

/// Fits the window to its content: as wide as the checklist, and taller when the content no
/// longer fits, for example when a checklist message wraps after a check finishes; SwiftUI
/// does not resize a window that is already open. `content` only changes when the layout may
/// have, which makes SwiftUI call the update.
struct GrowWindowToFit: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, let root = window.contentView else { return }
            let fit = root.fittingSize
            let current = window.contentRect(forFrameRect: window.frame)
            let width = fit.width > 100 ? fit.width : current.width
            let height = max(current.height, fit.height)
            guard abs(width - current.width) > 0.5 || height - current.height > 0.5 else { return }
            let target = NSRect(x: current.minX, y: current.maxY - height, width: width, height: height)
            window.setFrame(window.frameRect(forContentRect: target), display: true, animate: true)
        }
    }
}
