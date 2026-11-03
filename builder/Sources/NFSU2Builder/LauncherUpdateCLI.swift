import Foundation
import BuilderCore

/// `NFSU2Builder -LauncherUpdate <status file> -destination <folder> -gameData '("<NFSU2.app>")'`:
/// the update NFSU2.app's launcher runs (BuilderCore/LauncherUpdate.swift), with no window and
/// no Dock icon. The checklist and the build are the window's (BuilderModel); what it would
/// show goes to standard output as JSON lines instead.
enum LauncherUpdateCLI {
    static func run() -> Never {
        // The launcher quits before the install, closing the other end of the pipe: what is
        // printed after that is lost, and must not end the install.
        signal(SIGPIPE, SIG_IGN)
        setvbuf(stdout, nil, _IOLBF, 0)
        let model = BuilderModel()
        model.onUpdateStatus = { print(launcherUpdateLine($0)) }
        model.onUpdateLog = { print(launcherUpdateLine(log: $0)) }
        model.onUpdateEnd = { code in
            fflush(stdout)
            exit(code)
        }
        // Cancel in the launcher: stop the pipeline (its own process group) and quit.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        var stops: [DispatchSourceSignal] = []
        for sig in [SIGTERM, SIGINT] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { model.stopAll { exit(143) } }
            source.resume()
            stops.append(source)
        }
        model.start()
        model.startLauncherUpdate()
        withExtendedLifetime(stops) { RunLoop.main.run() }
        exit(0)
    }
}
