// Files from a public MEGA folder link (mega.nz/folder/<handle>#<key>), the way
// MEGA's own web client gets them: the folder's node list from its API, each
// node's key and name decrypted with the folder key (AES-128), the file fetched
// from the URL the API hands out and decrypted with AES-128-CTR.  For the
// Multi 13 languages mod, whose author publishes it there (LanguagePacks.swift).
// The caller checks every file against a pinned SHA-256 afterwards.
import Foundation
import CommonCrypto

enum Mega {
    struct Failure: Error { let message: String }
    struct Node { let handle: String; let name: String; let size: Int64; let key: [UInt8]; let iv: [UInt8] }

    static func b64url(_ s: String) -> [UInt8]? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t).map { [UInt8]($0) }
    }

    static func aes(_ op: Int, ecb: Bool, key: [UInt8], _ data: [UInt8]) -> [UInt8]? {
        let cap = data.count + 16
        var out = [UInt8](repeating: 0, count: cap)
        var moved = 0
        let iv = [UInt8](repeating: 0, count: 16)
        let st = CCCrypt(CCOperation(op), CCAlgorithm(kCCAlgorithmAES), CCOptions(ecb ? kCCOptionECBMode : 0),
                         key, key.count, ecb ? nil : iv, data, data.count, &out, cap, &moved)
        return st == kCCSuccess ? Array(out[0..<moved]) : nil
    }

    static func api(_ folder: String, _ body: String) throws -> Any {
        var req = URLRequest(url: URL(string: "https://g.api.mega.co.nz/cs?id=\(Int.random(in: 1...999_999))&n=\(folder)")!)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.timeoutInterval = 30
        let done = DispatchSemaphore(value: 0)
        var data: Data?, failure: Error?
        URLSession(configuration: .ephemeral).dataTask(with: req) { d, _, e in data = d; failure = e; done.signal() }.resume()
        done.wait()
        guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) else {
            throw Failure(message: "MEGA did not answer (\(failure?.localizedDescription ?? "no data"))")
        }
        if let code = j as? Int { throw Failure(message: "MEGA refused the request (error \(code))") }
        if let a = j as? [Any], let code = a.first as? Int { throw Failure(message: "MEGA refused the request (error \(code))") }
        return j
    }

    /// The files of a public folder link.
    static func list(_ link: String) throws -> (folder: String, files: [Node]) {
        guard let r = link.range(of: "/folder/") else { throw Failure(message: "not a MEGA folder link") }
        let parts = link[r.upperBound...].split(separator: "#").map(String.init)
        guard parts.count == 2, let fkey = b64url(parts[1]), fkey.count == 16 else { throw Failure(message: "not a MEGA folder link") }
        let folder = parts[0]
        let j = try api(folder, #"[{"a":"f","c":1,"ca":1,"r":1}]"#)
        guard let nodes = ((j as? [Any])?.first as? [String: Any])?["f"] as? [[String: Any]] else {
            throw Failure(message: "the MEGA folder is not there any more")
        }
        var files: [Node] = []
        for n in nodes where (n["t"] as? Int) == 0 {
            guard let h = n["h"] as? String, let k = (n["k"] as? String)?.split(separator: ":").last,
                  let ek = b64url(String(k)), let raw = aes(kCCDecrypt, ecb: true, key: fkey, ek), raw.count == 32,
                  let a = (n["a"] as? String).flatMap(b64url) else { continue }
            let key = (0..<16).map { raw[$0] ^ raw[$0 + 16] }
            guard let attr = aes(kCCDecrypt, ecb: false, key: key, a),
                  let s = String(bytes: attr, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
                  s.hasPrefix("MEGA{"), let js = try? JSONSerialization.jsonObject(with: Data(s.dropFirst(4).utf8)) as? [String: Any],
                  let name = js["n"] as? String else { continue }
            let size = (n["s"] as? NSNumber)?.int64Value ?? 0
            files.append(Node(handle: h, name: name, size: size, key: key, iv: Array(raw[16..<24]) + [UInt8](repeating: 0, count: 8)))
        }
        return (folder, files)
    }

    /// One file, decrypted into `to` (progress: bytes so far).  Call it off the main thread.
    static func download(_ node: Node, folder: String, to dest: URL, progress: @escaping (Int64) -> Void) throws {
        let j = try api(folder, #"[{"a":"g","g":1,"n":"\#(node.handle)"}]"#)
        guard let u = ((j as? [Any])?.first as? [String: Any])?["g"] as? String, let url = URL(string: u) else {
            throw Failure(message: "MEGA gave no download for \(node.name) (its daily transfer limit may be reached; try again later)")
        }
        let enc = try UHUDPack.Downloader(progress: progress, host: "mega.nz", hint: "use Import…").fetch(url)
        defer { try? FileManager.default.removeItem(at: enc) }
        var cr: CCCryptorRef?
        guard CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                      CCPadding(ccNoPadding), node.iv, node.key, 16, nil, 0, 0,
                                      CCModeOptions(kCCModeOptionCTR_BE), &cr) == kCCSuccess, let c = cr else {
            throw Failure(message: "AES is not available")
        }
        defer { CCCryptorRelease(c) }
        let inp = try FileHandle(forReadingFrom: enc)
        defer { inp.closeFile() }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let out = try FileHandle(forWritingTo: dest)
        defer { out.closeFile() }
        var buf = [UInt8](repeating: 0, count: 1 << 20)
        while true {
            let d = inp.readData(ofLength: 1 << 20)
            if d.isEmpty { break }
            var moved = 0
            let st = d.withUnsafeBytes { s in CCCryptorUpdate(c, s.baseAddress, d.count, &buf, buf.count, &moved) }
            guard st == kCCSuccess else { throw Failure(message: "\(node.name) could not be decrypted") }
            out.write(Data(buf[0..<moved]))
        }
    }
}
