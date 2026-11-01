import AppKit
import BuilderCore
import SwiftUI

struct ResultView: View {
    enum Outcome {
        case success(URL)
        case failure(step: String, message: String, log: [String])
        case quitToInstall
    }

    @ObservedObject var model: BuilderModel
    let outcome: Outcome

    var body: some View {
        switch outcome {
        case let .success(app): success(app)
        case let .failure(step, message, log): failure(step: step, message: message, log: log)
        case .quitToInstall: quitToInstall
        }
    }

    private var quitToInstall: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(NSColor.systemOrange))
            Text("NFSU2 is running").font(.title).fontWeight(.semibold)
            Text("Quit NFSU2, then click Install again.")
                .foregroundColor(.secondary)
            Button("Install again", action: model.installAgain)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 430)
    }

    private func success(_ app: URL) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Color(NSColor.systemGreen))
            Text("Ready").font(.title).fontWeight(.semibold)
            Text("NFSU2.app is in \(abbreviated(app.deletingLastPathComponent())).")
                .foregroundColor(.secondary)
            Text("The game is inside the app, so you can move it anywhere. Your saves and settings are kept outside the app.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
                Button("Play") { NSWorkspace.shared.open(app) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            Spacer()
            if model.buildFilesRemoved {
                Text("Temporary files deleted\(model.buildFilesBytes.map { ", \(sizeText($0)) freed" } ?? ""). NFSU2.app and your game are unchanged.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 4) {
                    Button("Delete temporary files\(model.buildFilesBytes.map { " (\(sizeText($0)))" } ?? "")",
                           action: model.removeBuildFiles)
                        .controlSize(.small)
                    Text("Deletes \(abbreviated(model.paths.workspace(version: model.version)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Only the Builder's own work files. NFSU2.app, your game copy, saves and settings stay. An update makes them again.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 430)
    }

    private func failure(step: String, message: String, log: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(NSColor.systemRed))
                Text("\(step) failed").font(.title2).fontWeight(.semibold)
            }
            Text(message).fixedSize(horizontal: false, vertical: true)
            Text("Details").font(.headline).padding(.top, 4)
            LogView(lines: log)
            HStack {
                Button("Copy log") { copyToPasteboard(log.joined(separator: "\n")) }
                Spacer()
                Button("Try again", action: model.tryAgain)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
