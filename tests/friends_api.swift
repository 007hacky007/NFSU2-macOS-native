// Free roam's friends (launcher/Friends.swift) against tests/friends_api.py's stand-in for
// /friends: argv[1] the server (ws://127.0.0.1:port/lan); argv[2] "off": the server keeps no
// friends lists.
import Foundation

func wait(_ until: () -> Bool) {
    let end = Date().addingTimeInterval(20)
    while !until() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

@main
struct FriendsAPITests {
    static func main() {
        let server = CommandLine.arguments[1]
        let url = FriendsAPI.endpoint(for: server)!
        assert(url.absoluteString.hasSuffix("/friends") && url.scheme == "http")
        assert(FriendsAPI.endpoint(for: "wss://nfsu2.xyz/lan")?.absoluteString == "https://nfsu2.xyz/friends")
        assert(FriendsAPI.endpoint(for: "ws://example.com/lan") == nil)
        let phrase = "nfsu2-xyz-" + Array(VaultWords.words.prefix(8)).joined(separator: "-")
        let token = try! VaultCrypto.keys(phrase).token
        if CommandLine.arguments.count > 2 {
            do { _ = try FriendsAPI.call(url, token: token); assert(false) } catch { assert(error as? FriendsAPI.Failure == FriendsAPI.Failure.none) }
            print("friends api: a server without friends lists answers 404"); return
        }
        // the lists, read leniently (an entry of the wrong kind left out), the messages that waited with them
        var l = try! FriendsAPI.call(url, token: token)
        assert(l.me == "Ann" && l.friends.map(\.name) == ["Bo", "Al", "Cy"] && l.asks == ["Dee"] && l.sent == ["Eve"])
        assert(l.friends[0] == Friend(name: "Bo", place: "roam", room: "Blue Room") && l.friends[1].place == "online" && l.friends[2].place == "")
        assert(FriendsAPI.placeText(l.friends[0]) == "free roam, room Blue Room" && FriendsAPI.placeText(l.friends[1]) == "Online lobby"
               && FriendsAPI.placeText(l.friends[2]) == "offline" && FriendsAPI.placeText(Friend(name: "x", place: "roam", room: "")) == "free roam, no room")
        assert(l.mail == [FriendMail(from: "Bo", body: "hi there")])
        assert(try! FriendsAPI.call(url, token: token).mail.isEmpty)      // gone from the server once read
        // a request by name: one nobody claimed, one claimed (as its claim spells it)
        l = try! FriendsAPI.call(url, token: token, op: "ask", name: "Nobody")
        assert(l.done == "claim" && FriendsAPI.doneText(l.done, name: "Nobody").1)
        l = try! FriendsAPI.call(url, token: token, op: "ask", name: "fay")
        assert(l.done == "asked" && l.sent.contains("Fay_") && FriendsAPI.doneText(l.done, name: "Fay_").0 == "Friend request sent to Fay_.")
        // accept, take back, remove, a request by name to one who asked first
        l = try! FriendsAPI.call(url, token: token, op: "remove", name: "Eve")
        assert(!l.sent.contains("Eve"))
        l = try! FriendsAPI.call(url, token: token, op: "ask", name: "dee")
        assert(l.done == "friends" && l.friends.contains { $0.name == "Dee" } && l.asks.isEmpty)
        l = try! FriendsAPI.call(url, token: token, op: "remove", name: "Cy")
        assert(!l.friends.contains { $0.name == "Cy" })
        // another keyphrase: the server does not know it
        let other = try! VaultCrypto.keys("nfsu2-xyz-" + Array(VaultWords.words.suffix(8)).joined(separator: "-")).token
        do { _ = try FriendsAPI.call(url, token: other); assert(false) } catch { assert(error as? FriendsAPI.Failure == .keyphrase) }
        // the model: the token only for the server it was remembered with
        let defaults = UserDefaults(suiteName: "nfsu2-friends-test-\(getpid())")!
        let names = NameClaimModel(defaults: defaults)
        names.keyphraseSource = { (phrase, VaultAPI.defaultEndpoint(server: server)) }
        let model = FriendsModel()
        model.refresh(server: "wss://elsewhere.example/lan", token: names.claimToken(server: "wss://elsewhere.example/lan"))
        assert(!model.busy && model.lists == nil)                            // nothing asked: no token for that server
        model.refresh(server: server, token: names.claimToken(server: server))
        wait { !model.busy }
        assert(model.lists?.me == "Ann" && model.lists?.friends.contains { $0.name == "Dee" } == true)
        model.act("decline", name: "Nobody", server: server, token: names.claimToken(server: server))
        wait { !model.busy }
        assert(model.note?.bad == true)                                       // (the stand-in refuses it)
        model.act("ask", name: "eve", server: server, token: names.claimToken(server: server))
        wait { !model.busy }
        assert(model.note?.text == "Friend request sent to Eve." && model.note?.bad == false)
        defaults.removePersistentDomain(forName: "nfsu2-friends-test-\(getpid())")
        print("friends api: the launcher's lists, requests and answers passed")
    }
}
