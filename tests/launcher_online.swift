// The launcher's free-roam names and player counts without a window: the room
// and crew rules (runtime/names.h, the engine's own name check), the engine's
// room hash, the counts' address following the server, and the claimed names'
// Online form, digits name and address (NameClaims.swift).
// tests/launcher_online.sh builds it with the launcher's sources.
import Foundation

@main
struct LauncherOnlineTests {
    static func main() {
        // rooms: UTF-8 up to 63 bytes, no control characters, not one names.h turns down
        assert(OnlineSettings.roomError("") == nil)
        assert(OnlineSettings.roomError("Ostrava") == nil)
        assert(OnlineSettings.roomError("røøm") == nil)
        assert(OnlineSettings.roomError(String(repeating: "a", count: 63)) == nil)
        assert(OnlineSettings.roomError(String(repeating: "a", count: 64)) != nil)
        assert(OnlineSettings.roomError(String(repeating: "ø", count: 32)) != nil)   // 64 bytes
        assert(OnlineSettings.roomError("tab\there") != nil)
        assert(OnlineSettings.roomError("1488") != nil)
        assert(OnlineSettings.roomError("N4zi crew") != nil)
        // crews: up to four, 24 characters each, no # ; or control characters, none twice
        assert(OnlineSettings.crewError("") == nil)
        assert(OnlineSettings.crewError("Night Owls, Blue Room, Ostrava Ölwagen, X") == nil)
        assert(OnlineSettings.crewError("a,b,c,d,e") != nil)
        assert(OnlineSettings.crewError("Blue Room, blueroom") != nil)
        assert(OnlineSettings.crewError("name#x") != nil)
        assert(OnlineSettings.crewError(String(repeating: "ø", count: 24)) == nil)
        assert(OnlineSettings.crewError(String(repeating: "ø", count: 25)) != nil)
        assert(OnlineSettings.crewError("nazi") != nil)
        // the engine's hash (runtime/roam_core.c rc_room_hash)
        assert(OnlineSettings.roomHash("Blue Room") == 370_129_458)
        assert(OnlineSettings.roomHash("Ostrava Ölwagen") == 808_321_242)
        // the Unicode rule of core 9 (runtime/roam_core.c rc_room_hash; values from the C code)
        assert(OnlineSettings.roomHash("КОМНАТА") == 2_160_928_381 && OnlineSettings.roomHash("комната") == 2_160_928_381)
        assert(OnlineSettings.roomHash("ΚΑΛΗ ΜΈΡΑ") == 1_458_084_362)
        assert(OnlineSettings.roomHash("Ｂｌｕｅ　Ｒｏｏｍ") == 370_129_458)
        assert(OnlineSettings.roomHash("İstanbul") == 1_059_843_399)
        assert(OnlineSettings.roomHash("Łódź") == 3_399_481_215)
        assert(OnlineSettings.roomHash("a\u{00A0}b") == 1_294_271_946)
        assert(OnlineSettings.roomHash("  ") == 0)
        // the counts' address
        assert(PlayerCounts.address(for: "wss://nfsu2.xyz/lan") == "https://nfsu2.xyz/players")
        assert(PlayerCounts.address(for: "ws://127.0.0.1:18093/lan") == "http://127.0.0.1:18093/players")
        assert(PlayerCounts.address(for: "ws://example.com/lan") == "")
        assert(PlayerCounts.endpoint("http://example.com/players", room: "", crews: "") == nil)
        assert(PlayerCounts.endpoint("https://nfsu2.xyz/players", room: "", crews: "")?.absoluteString == "https://nfsu2.xyz/players")
        assert(PlayerCounts.endpoint("https://nfsu2.xyz/players", room: "Blue Room", crews: "Blue Room, ,Night Owls")?.absoluteString
               == "https://nfsu2.xyz/players?room=370129458&crews=370129458,\(OnlineSettings.roomHash("Night Owls"))")
        let json = #"{"players":14,"online":3,"roam":9,"full":false,"queue":0,"roamBusy":false,"room":4,"crews":[2]}"#
        let c = try! JSONDecoder().decode(PlayerCounts.self, from: Data(json.utf8))
        assert(c.valid && c.summary(room: "Ostrava", crews: ["Night Owls"]).contains("Room \"Ostrava\": 4") && c.summary(room: "", crews: []).hasPrefix("On this server now: 14 players"))
        let old = try! JSONDecoder().decode(PlayerCounts.self, from: Data(#"{"players":2,"online":null}"#.utf8))   // an older server
        assert(old.valid && old.summary(room: "x", crews: ["y"]) == "On this server now: 2 players.")
        assert(!(try! JSONDecoder().decode(PlayerCounts.self, from: Data(#"{"players":-1,"online":0}"#.utf8))).valid)
        // the quick chat groups the launcher keeps
        assert(QuickChat.phrases.count == 152 && QuickChat.phrases[57] == "Nice drift!")
        assert(QuickChat.groups(["a", "b"]) == QuickChat.defaultGroups && QuickChat.groups(["a", "b", "c", "d"]) == ["a", "b", "c", "d"])
        assert(QuickChat.phraseIDs(Array(repeating: 152, count: 16)) == QuickChat.defaultPhrases)
        assert(!QuickChat.validGroup("a,b") && QuickChat.validGroup("Racing"))
        // claimed names (NameClaims.swift): the Online form and the digits name as the browser makes them
        // (values from web/src/app/claim.ts onlineName and digitsFor, run with node)
        assert(NameClaims.onlineName("Hacky") == "Hacky")
        assert(NameClaims.onlineName("ab") == "ab_")
        assert(NameClaims.onlineName("a b!c") == "a_b_c")
        assert(NameClaims.onlineName("!!") == nil)
        assert(NameClaims.onlineName("Ölwagen") == "lwagen")
        assert(NameClaims.digits(for: "Hacky", seed: "seed-1") == "Hacky7922")
        assert(NameClaims.digits(for: "Hacky", seed: "seed-2") == "Hacky4916")
        assert(NameClaims.digits(for: "SuperLongName15", seed: "abc") == "SuperLongNa2518")
        assert(NameClaims.digits(for: "NAME", seed: "x") == "NAME5434")
        assert(NameClaims.digits(for: "ab", seed: "x") == "ab_3877")
        assert(NameClaims.digits(for: "a b!c", seed: "x") == "a_b_c2662")
        assert(OnlineSettings.validName(NameClaims.digits(for: "SuperLongName15", seed: "abc")))
        // the names' address follows the server; the token is the vault's (43 characters of base64url)
        assert(NameClaims.endpoint(for: "wss://nfsu2.xyz/lan")?.absoluteString == "https://nfsu2.xyz/names")
        assert(NameClaims.endpoint(for: "ws://127.0.0.1:18093/lan")?.absoluteString == "http://127.0.0.1:18093/names")
        assert(NameClaims.endpoint(for: "ws://example.com/lan") == nil)
        assert(NameClaims.validToken(String(repeating: "aZ0-_", count: 8) + "abc"))
        assert(!NameClaims.validToken(String(repeating: "a", count: 42)))
        assert(!NameClaims.validToken(String(repeating: "a", count: 42) + "="))
        assert(NameClaims.refusal("soon", next: nil, name: "X").contains("once a week"))
        assert(NameClaims.refusal("whatever", next: nil, name: "X").contains("did not take"))
        print("launcher online: room and crew rules, room hash, counts address, quick chat groups and name claims passed")
    }
}
