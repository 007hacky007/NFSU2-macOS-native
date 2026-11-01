// Claimed names (launcher/NameClaims.swift) against tests/name_claims.py's stand-in
// for /names: argv[1] the server (ws://127.0.0.1:port/lan), argv[2] "before" (the
// keyphrase has no cloud saves) or "after".
import Foundation

func wait(_ until: () -> Bool) {
    let end = Date().addingTimeInterval(20)
    while !until() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

@main
struct NameClaimsTests {
    static func main() {
        let server = CommandLine.arguments[1], step = CommandLine.arguments[2]
        let url = NameClaims.endpoint(for: server)!
        let phrase = "nfsu2-xyz-" + Array(VaultWords.words.prefix(8)).joined(separator: "-")
        let token = try! VaultCrypto.keys(phrase).token
        // the check: free, taken (another keyphrase's), default, blocked, and the digits name asked with it
        let free = try! NameClaims.check(url, name: "Driver_1", alt: "Driver_17922", token: nil)!
        assert(free.state == .free && free.alt?.state == .free)
        assert(try! NameClaims.check(url, name: "Hacky", alt: nil, token: nil)!.state == .taken)
        assert(try! NameClaims.check(url, name: "Hacky", alt: nil, token: token)!.state == .taken)
        assert(try! NameClaims.check(url, name: "NAME", alt: nil, token: nil)!.state == .default)
        assert(try! NameClaims.check(url, name: "Hitler", alt: nil, token: nil)!.state == .blocked)
        // the model: its seed is kept, the digits follow it, a taken name is offered the digits
        let defaults = UserDefaults(suiteName: "nfsu2-name-claims-test-\(getpid())")!
        let model = NameClaimModel(defaults: defaults)
        model.keyphraseSource = { (phrase, VaultAPI.defaultEndpoint(server: server)) }
        // the token goes only to the server the keyphrase was remembered with
        assert(model.claimToken(server: server) == token)
        assert(model.claimToken(server: "wss://elsewhere.example/lan") == nil)
        assert(NameClaimModel.origin("wss://nfsu2.xyz/lan") == NameClaimModel.origin("https://nfsu2.xyz/vault"))
        assert(NameClaimModel.origin("wss://nfsu2.xyz/lan") != NameClaimModel.origin("wss://nfsu2.xyz:8443/lan"))
        assert(model.seed == model.seed && model.digits(for: "Hacky").hasPrefix("Hacky"))
        var done = false
        model.check(name: "Hacky", server: server) { _ in done = true }
        wait { done }
        assert(model.claimedByOther("Hacky") && model.canClaim("Hacky") && !model.playsWithClaim(server: server))
        assert(model.line(for: "Hacky")!.text.contains(model.digits(for: "Hacky")))
        if step == "before" {
            // a claim from a keyphrase without cloud saves is refused (the launcher asks to send them first)
            assert(try! NameClaims.claim(url, name: "Mine", captcha: nil, token: token) == .refused("keyphrase", next: nil))
            assert(try! NameClaims.claim(url, name: "Hacky", captcha: nil, token: token) == .refused("taken", next: nil))
        } else {
            guard case .claimed(let mine) = try! NameClaims.claim(url, name: "Mine", captcha: nil, token: token) else { fatalError("claim") }
            assert(mine.name == "Mine")
            assert(try! NameClaims.check(url, name: "Mine", alt: nil, token: token)!.state == .yours)
            assert(try! NameClaims.check(url, name: "Mine", alt: nil, token: nil)!.state == .taken)
            // the model sees the name is its keyphrase's: the game plays with the claim from now on
            done = false
            model.check(name: "Mine", server: server) { _ in done = true }
            wait { done }
            assert(model.info?.state == .yours && model.playsWithClaim(server: server) && model.claimToken(server: server) == token)
            assert(!model.playsWithClaim(server: "wss://elsewhere.example/lan"))
            assert(model.line(for: "Mine")!.tone == .good)
        }
        defaults.removePersistentDomain(forName: "nfsu2-name-claims-test-\(getpid())")
        print("name claims (\(step)) passed")
    }
}
