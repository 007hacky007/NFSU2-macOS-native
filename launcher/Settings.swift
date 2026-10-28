// Foundation-only validation shared by the launcher and its command-line tests.
import Foundation
import Darwin

enum LaunchSettings {
    static let defaultServer = "wss://nfsu2.xyz/lan"
    static let defaultCounts = "https://nfsu2.xyz/players"

    static func isLoopback(_ host: String) -> Bool {
        if ["localhost", "::1", "[::1]"].contains(host.lowercased()) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && (UInt($0) ?? 256) <= 255
        }
    }

    private static func endpoint(_ text: String, secure: String, local: String) -> URL? {
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let c = URLComponents(string: text), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.fragment == nil,
              c.port == nil || (1...65535).contains(c.port!),
              c.scheme == secure || (c.scheme == local && isLoopback(host)) else { return nil }
        return c.url
    }

    static func serverURL(_ text: String) -> URL? { endpoint(text, secure: "wss", local: "ws") }
    static func countsEndpoint(_ text: String) -> URL? { endpoint(text, secure: "https", local: "http") }

    static func countsURL(for server: String) -> String {
        guard serverURL(server) != nil, var c = URLComponents(string: server) else { return "" }
        c.scheme = c.scheme == "wss" ? "https" : "http"
        c.path = "/players"; c.query = nil; c.fragment = nil
        return c.string ?? ""
    }

    static func validPlayerName(_ name: String) -> Bool {
        (3...15).contains(name.utf8.count) && name.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
        }
    }

    static func onlineError(server: String, name: String) -> String? {
        if serverURL(server) == nil { return "Use wss:// for a server, or ws:// with a loopback address for local testing." }
        if !validPlayerName(name) { return "Enter a player name: 3-15 letters, numbers, _ or -." }
        return nil
    }

    static func environment(inherited: [String: String], online: Bool, server: String, name: String,
                            textures: String, pack: String?, data: String, saves: String, registry: String) throws -> [String: String] {
        if online, let error = onlineError(server: server, name: name) { throw SettingsError(error) }
        var env = inherited
        for key in ["NFSU2_SERVER_URL", "NFSU2_ROAM_NAME", "NFSU2_NET_NAME", "NFSU2_UI_TEXPACK"] { env.removeValue(forKey: key) }
        env["NFSU2_DATA"] = data
        env["NFSU2_SAVEDIR"] = saves
        env["NFSU2_REGFILE"] = registry
        env["NFSU2_ONLINE"] = online ? "1" : "0"
        env["NFSU2_ROAM"] = online ? "1" : "0"
        env["NFSU2_ROAM_DISCOVERY"] = "0"
        env["NFSU2_NET"] = online ? "online" : "off"
        if online {
            env["NFSU2_SERVER_URL"] = server
            env["NFSU2_ROAM_NAME"] = name
            env["NFSU2_NET_NAME"] = name
        }
        env["NFSU2_UI_TEXTURES"] = textures == "uhud" ? "uhud" : "original"
        if textures == "uhud", let pack = pack { env["NFSU2_UI_TEXPACK"] = pack }
        return env
    }
}

struct SettingsError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct PlayerCounts: Decodable {
    let players: Int
    let online: Int?
    let roam: Int?
    let full: Bool
    let queue: Int
    let roamBusy: Bool
    let crews: [Int]?

    var valid: Bool { ([players, queue] + [online, roam].compactMap { $0 } + (crews ?? [])).allSatisfy { $0 >= 0 } }
    var summary: String {
        var parts = ["\(players) players"]
        if let online = online { parts.append("\(online) in Online mode") }
        if let roam = roam { parts.append("\(roam) in free roam") }
        if let crews = crews { parts.append("Crews: " + crews.map(String.init).joined(separator: ", ")) }
        if full { parts.append("Server full (\(queue) waiting)") }
        if roamBusy { parts.append("Free roam busy") }
        return parts.joined(separator: " · ")
    }
}

enum TexturePack {
    // Keep these limits and checks aligned with texpack_open in runtime/texpack.c.
    static func validate(_ data: Data) throws {
        func invalid() -> SettingsError { SettingsError("This is not a complete NTXP v1 texture pack. Choose a prepared uhud.pak file.") }
        guard data.count >= 16, UInt64(data.count) <= UInt32.max,
              data.prefix(4) == Data("NTXP".utf8) else { throw invalid() }
        func word(_ offset: Int) -> UInt64 {
            (0..<4).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
        }
        func short(_ offset: Int) -> UInt64 { UInt64(data[offset]) | UInt64(data[offset + 1]) << 8 }
        func levelSize(_ w: UInt64, _ h: UInt64, _ format: UInt64) -> UInt64 {
            switch format {
            case 21, 22: return w * h * 4
            case 0x31545844: return ((w + 3) / 4) * ((h + 3) / 4) * 8
            case 0x33545844, 0x35545844: return ((w + 3) / 4) * ((h + 3) / 4) * 16
            default: return 0
            }
        }
        let count = word(8), tableEnd = 16 + count * 40
        guard word(4) == 1, word(12) == 0, count > 0, count <= 65_536,
              tableEnd <= UInt64(data.count) else { throw invalid() }
        var firstPayload = UInt64(data.count)
        var previousCRC: UInt64 = 0, previousAdler: UInt64 = 0
        for i in 0..<Int(count) {
            let base = 16 + i * 40, offset = word(base + 28), size = word(base + 32)
            let ow = short(base + 8), oh = short(base + 10), originalFormat = word(base + 12)
            let w = short(base + 16), h = short(base + 18), format = word(base + 20), levels = word(base + 24)
            guard ow > 0, oh > 0, ow <= 4096, oh <= 4096, levelSize(ow, oh, originalFormat) > 0,
                  w > 0, h > 0, w <= 16384, h <= 16384, levelSize(w, h, format) > 0,
                  w >= ow, h >= oh, w * oh == h * ow else { throw invalid() }
            var maxLevels: UInt64 = 1, dimension = max(w, h)
            while dimension > 1 { dimension >>= 1; maxLevels += 1 }
            guard levels > 0, levels <= maxLevels else { throw invalid() }
            var needed: UInt64 = 0, mipWidth = w, mipHeight = h
            for _ in 0..<levels {
                needed += levelSize(mipWidth, mipHeight, format)
                mipWidth = max(1, mipWidth / 2); mipHeight = max(1, mipHeight / 2)
            }
            guard size == needed, offset >= tableEnd, offset <= UInt64(data.count),
                  size <= UInt64(data.count) - offset else { throw invalid() }
            let crc = word(base), adler = word(base + 4)
            guard i == 0 || previousCRC < crc || (previousCRC == crc && previousAdler <= adler) else { throw invalid() }
            previousCRC = crc; previousAdler = adler
            firstPayload = min(firstPayload, offset)
        }
        guard firstPayload > tableEnd, firstPayload - tableEnd <= 8 << 20 else { throw invalid() }
        for i in 0..<Int(count) {
            let name = word(16 + i * 40 + 36)
            guard name >= tableEnd, name < firstPayload,
                  data[Int(name)..<Int(min(firstPayload, name + 1024))].contains(0) else { throw invalid() }
        }
    }

    static func install(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".uhud-\(UUID().uuidString).pak")
        defer { try? fm.removeItem(at: temp) }
        try fm.copyItem(at: source, to: temp)
        try validate(Data(contentsOf: temp, options: .mappedIfSafe))
        // Both paths share a directory, so rename atomically preserves any previous good import.
        guard rename(temp.path, destination.path) == 0 else {
            throw SettingsError("Could not install the texture pack: \(String(cString: strerror(errno)))")
        }
    }
}
