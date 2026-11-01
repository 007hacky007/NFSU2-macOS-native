import BuilderCore
import SwiftUI

/// "Which copy works?": the two accepted SPEED2.EXE files with size and SHA-256, and where the
/// game data can come from.
struct SupportedCopiesView: View {
    @ObservedObject var model: BuilderModel

    static let summary = "The build needs one of these two SPEED2.EXE files, both v1.2 without the CD check. "
        + "The disc version and EA's official v1.2 patch are copy-protected and cannot be used."
    static let dataNote = "The game data can come from the discs of either region, or from an installed game "
        + "folder: either SPEED2.EXE works with either region's data."

    static var plainText: String {
        ([summary] + KnownProgram.supported.map { "- \($0.name): \(grouped($0.size)) bytes, SHA-256 \($0.sha256)" }
            + [dataNote]).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which copy works?").font(.title2).fontWeight(.semibold)
            Text(Self.summary).fixedSize(horizontal: false, vertical: true)
            ForEach(KnownProgram.supported, id: \.sha256) { program in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(program.name): \(grouped(program.size)) bytes")
                    Text(program.sha256)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 12)
            }
            Text(Self.dataNote)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Copy") { copyToPasteboard(Self.plainText) }
                Button("Close") { model.showingSupported = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

func grouped(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}
