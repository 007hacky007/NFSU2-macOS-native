// Cloud saves: what goes into the cloud, as the browser game sends it.  The save
// folder without the F12 screenshots, the DVD and magazine covers (1 MiB each,
// they stay on the Mac that took them), the game's graphics options
// (registry.txt), the LAN server's file (gamefile.bin) and a test's input
// script; a settings.ini without the device's own lines (resolution, frame rate,
// controller and the like: a phone's would slow a Mac down and the other way
// round).  What comes back is checked as an imported backup is (SaveStore
// validated: valid profiles, their folders and covers only).
// Ported from th0mk's nfsu2-web web/src/app/vault.ts (MIT).
import Foundation

enum VaultPayload {
    static let deviceKeys: Set<String> = Set("seed_registry fullscreen native_resolution resolution render max_pixels fps_counter fps hfr_fixes gamepad rumble gamepad_deadzone gamepad_trigger_deadzone gamepad_trigger_click gamepad_menu_keys roam_max_cars lan_adapter_id lan_host_name audio_latency ui_textures NFSU2_SEED_REGISTRY NFSFULL NFSNATIVE NFSRES NFSU2_RENDER NFSMAXPIX NFSU2_FPS_COUNTER NFSU2_FPS NFSU2_HFR_FIX NFSU2_PAD NFSU2_FF NFSU2_PAD_DEADZONE NFSU2_PAD_TRIGGER_DEADZONE NFSU2_PAD_TRIGGER_CLICK NFSU2_PAD_FE_KEYS NFSU2_ROAM_MAX_CARS NFSU2_NET_MAC NFSU2_NET_NAME NFSU2_AUDIO_LATENCY NFSU2_UI_TEXTURES".lowercased().split(separator: " ").map(String.init))
    static func deviceLine(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.hasPrefix("#"), !text.hasPrefix(";"), !text.hasPrefix("["), let equal = text.firstIndex(of: "=") else { return false }
        return deviceKeys.contains(text[..<equal].trimmingCharacters(in: .whitespaces).lowercased())
    }
    static func keeps(_ entry: SaveEntry) -> Bool {
        let path = entry.path, lower = path.lowercased(), parts = path.split(separator: "/")
        if ["registry.txt", "gamefile.bin", "autotest-script.txt"].contains(lower) { return false }
        if parts.count == 1 && ["tga", "bmp", "png", "jpg", "jpeg"].contains((lower as NSString).pathExtension) { return false }
        if parts.count >= 3 && parts[0].lowercased() == SaveStore.profileRoot.lowercased() &&
            (parts[1].range(of: " (DVD|Magazine) [0-9]+$", options: [.regularExpression, .caseInsensitive]) != nil || SaveProfile.isCover(entry.data)) { return false }
        return true
    }
    static func filtered(_ entries: [SaveEntry]) -> [SaveEntry] {
        entries.filter(keeps).map { e in
            guard e.path.lowercased() == "settings.ini" else { return e }
            let lines = String(decoding: e.data, as: UTF8.self).components(separatedBy: "\n").filter { !deviceLine($0) }
            return SaveEntry(path: "settings.ini", data: Data(lines.joined(separator: "\n").utf8), modified: e.modified)
        }
    }
    /// A checked cloud version as a ZIP for SaveStore.restore(cloud: true): its
    /// profiles and their folders; never the cloud's registry.txt (this Mac's
    /// graphics options stay).
    static func restorable(_ checked: [SaveEntry]) throws -> Data {
        try SaveArchive.encode(checked.filter { $0.path.lowercased() != "registry.txt" })
    }
}
