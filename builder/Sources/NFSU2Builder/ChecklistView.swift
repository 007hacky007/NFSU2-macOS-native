import AppKit
import BuilderCore
import SwiftUI
import UniformTypeIdentifiers

struct ChecklistView: View {
    @ObservedObject var model: BuilderModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CheckID.allCases, id: \.self) { id in
                CheckRow(title: id.title, state: model.states[id] ?? .checking("Checking..."), buttons: buttons(for: id))
                if id != CheckID.allCases.last { Divider() }
            }
            Button(action: model.build) {
                Text(model.buildTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.buildEnabled)
            .padding(.top, 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 3)
                .padding(-10)
                .opacity(dropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: drop)
        .sheet(isPresented: $model.showingSupported) { SupportedCopiesView(model: model) }
    }

    private func buttons(for id: CheckID) -> [RowButton] {
        let state = model.states[id]
        switch (id, state) {
        case (.commandLineTools, .blocked?):
            return [RowButton(label: "Install...", action: model.installCommandLineTools)]
        case (.buildTools, .blocked?):
            let install = RowButton(label: "Install", action: model.installBuildTools)
            guard let details = model.setupDetails else { return [install] }
            return [RowButton(label: "Copy details", action: { copyToPasteboard(details) }), install]
        case (.gameData, _):
            let choose = RowButton(label: "Choose...", action: chooseData)
            guard let details = model.dataDetails else { return [choose] }
            return [RowButton(label: "Copy details", action: { copyToPasteboard(details) }), choose]
        case (.gameProgram, _):
            let which = RowButton(label: "Which copy works?", action: { model.showingSupported = true })
            if model.programFromData { return state?.isReady == true ? [] : [which] }
            return [which, RowButton(label: "Choose...", action: chooseProgram)]
        case (.destination, _):
            return [RowButton(label: "Change...", action: chooseDestination)]
        default:
            return []
        }
    }

    private func chooseData() {
        let panel = NSOpenPanel()
        panel.message = "Choose your game folder, both disc images (.iso, .cue or disc folders) at once, or an NFSU2.app with the game inside"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["iso", "bin", "cue"].compactMap { UTType(filenameExtension: $0) } + [.folder, .applicationBundle]
        if let current = model.dataChoice.first { panel.directoryURL = current.deletingLastPathComponent() }
        if panel.runModal() == .OK, !panel.urls.isEmpty { model.setData(panel.urls) }
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.message = "Choose SPEED2.EXE (v1.2 without the CD check), or a zip, rar or 7z archive that holds it"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["exe", "zip", "rar", "7z"].compactMap { UTType(filenameExtension: $0) }
        if let current = model.programChoice { panel.directoryURL = current.deletingLastPathComponent() }
        if panel.runModal() == .OK, let url = panel.url { model.setProgram(url) }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.message = "Choose where to put NFSU2.app"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.destination
        if panel.runModal() == .OK, let url = panel.url { model.setDestination(url) }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard model.phase == .checklist, !providers.isEmpty else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
                if let url = url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { model.choose(urls) }
        return true
    }
}

struct RowButton {
    let label: String
    let action: () -> Void
    let menu: [(String, () -> Void)]

    init(label: String, action: @escaping () -> Void) {
        (self.label, self.action, self.menu) = (label, action, [])
    }

    init(label: String, menu: [(String, () -> Void)]) {
        (self.label, self.action, self.menu) = (label, {}, menu)
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct CheckRow: View {
    let title: String
    let state: CheckState
    let buttons: [RowButton]

    /// Up to two buttons sit beside the message; more go on their own line below it, so the
    /// message keeps the width it needs.
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(BuilderModel.plain(state.message))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if buttons.count > 2 {
                    HStack { buttonViews }.padding(.top, 6)
                }
            }
            Spacer(minLength: 8)
            if buttons.count <= 2 { buttonViews }
        }
        .padding(.vertical, 9)
    }

    private var buttonViews: some View {
        ForEach(buttons, id: \.label) { button in
            if button.menu.isEmpty {
                Button(button.label, action: button.action)
            } else {
                Menu(button.label) {
                    ForEach(button.menu, id: \.0) { item in
                        Button(item.0, action: item.1)
                    }
                }
                .fixedSize()
            }
        }
    }
}

extension CheckID {
    var title: String {
        switch self {
        case .mac: return "Mac"
        case .commandLineTools: return "Xcode command line tools"
        case .buildTools: return "Build tools (Python)"
        case .gameData: return "Game data"
        case .gameProgram: return "Game program (SPEED2.EXE)"
        case .destination: return "Destination"
        case .diskSpace: return "Free disk space"
        }
    }
}

extension CheckState {
    var color: Color {
        switch self {
        case .checking: return Color(NSColor.systemGray)
        case .ready: return Color(NSColor.systemGreen)
        case .automatic: return Color(NSColor.systemOrange)
        case .blocked: return Color(NSColor.systemRed)
        }
    }
}
