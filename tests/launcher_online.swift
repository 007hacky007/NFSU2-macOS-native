// The launcher's free-roam names and player counts without a window: the room
// and crew rules (runtime/names.h, the engine's own name check), the engine's
// room hash, and the counts' address following the server.
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
        assert(OnlineSettings.roomHash("Ostrava Ölwagen") == 1_578_539_130)
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
        print("launcher online: room and crew rules, room hash, counts address and quick chat groups passed")
    }
}
