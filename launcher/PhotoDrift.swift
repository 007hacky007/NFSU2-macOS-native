// Settings > Game: photo mode (runtime/photo.c, native_scene.m), drift mode in free roam
// (runtime/drift.c) and the Screenshots window (PhotoGallery.swift).
import SwiftUI

/// Settings > Game: photo mode, drift mode in free roam, and the Screenshots window.
struct PhotoDriftCard: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        Card("Photo and drift") {
            SettingRow(title: "Photo mode",
                       description: "F12 or the pause menu stops the world and frees the camera to take a picture; F12 elsewhere saves a screenshot. Off: as in the original game.",
                       isOn: $model.photoMode)
            SettingRow(title: "Drift mode in free roam",
                       description: "X while driving in free roam switches to the game's drift handling, drift camera and scoring, with a points panel. Off: as in the original game.",
                       isOn: $model.driftMode)
            SettingRow(title: "Screenshots",
                       description: "The pictures you saved, with preview, export and delete.") {
                Button("Screenshots\u{2026}") { model.showScreenshots() }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
