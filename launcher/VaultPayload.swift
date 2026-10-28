import Foundation

// The donor's device settings stay with the device. The remaining settings can travel with the career.
enum VaultPayload {
    static let deviceKeys: Set<String> = Set("seed_registry fullscreen native_resolution resolution render max_pixels fps_counter fps hfr_fixes gamepad rumble gamepad_deadzone gamepad_trigger_deadzone gamepad_trigger_click gamepad_menu_keys roam_max_cars lan_adapter_id lan_host_name audio_latency ui_textures NFSU2_SEED_REGISTRY NFSFULL NFSNATIVE NFSRES NFSU2_RENDER NFSMAXPIX NFSU2_FPS_COUNTER NFSU2_FPS NFSU2_HFR_FIX NFSU2_PAD NFSU2_FF NFSU2_PAD_DEADZONE NFSU2_PAD_TRIGGER_DEADZONE NFSU2_PAD_TRIGGER_CLICK NFSU2_PAD_FE_KEYS NFSU2_ROAM_MAX_CARS NFSU2_NET_MAC NFSU2_NET_NAME NFSU2_AUDIO_LATENCY NFSU2_UI_TEXTURES".lowercased().split(separator: " ").map(String.init))
    static func deviceLine(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.hasPrefix("#"), !text.hasPrefix(";"), !text.hasPrefix("["), let equal = text.firstIndex(of: "=") else { return false }
        return deviceKeys.contains(text[..<equal].trimmingCharacters(in: .whitespaces).lowercased())
    }
    static func keeps(_ path: String) -> Bool {
        let lower = path.lowercased(), parts = path.split(separator: "/")
        if ["registry.txt","gamefile.bin","autotest-script.txt"].contains(lower) { return false }
        if parts.count == 1 && ["tga","bmp","png","jpg","jpeg"].contains((lower as NSString).pathExtension) { return false }
        if parts.count >= 3 && parts[0].lowercased() == SaveStore.profileRoot.lowercased() && parts[1].range(of: " (DVD|Magazine) [0-9]+$", options: .regularExpression) != nil { return false }
        return true
    }
    static func filtered(_ entries: [SaveEntry]) -> [SaveEntry] {
        entries.filter { keeps($0.path) }.map { e in
            guard e.path.lowercased() == "settings.ini" else { return e }
            let lines = String(decoding: e.data, as: UTF8.self).components(separatedBy: "\n").filter { !deviceLine($0) }
            return SaveEntry(path: "settings.ini", data: Data(lines.joined(separator: "\n").utf8), modified: e.modified)
        }
    }
    static func restorable(_ entries: [SaveEntry], local: [SaveEntry]) throws -> Data {
        var entries = filtered(entries)
        if let index = entries.firstIndex(where: { $0.path == "settings.ini" }), let mine = local.first(where: { $0.path.lowercased() == "settings.ini" }) {
            let device = String(decoding: mine.data, as: UTF8.self).components(separatedBy: "\n").filter(deviceLine)
            let merged = String(decoding: entries[index].data, as: UTF8.self) + "\n" + device.joined(separator: "\n") + "\n"
            entries[index] = SaveEntry(path: "settings.ini", data: Data(merged.utf8))
        }
        return try SaveArchive.encode(entries)
    }
}
