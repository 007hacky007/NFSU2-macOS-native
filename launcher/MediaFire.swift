// Files on MediaFire (www.mediafire.com/file/<key>/<name>/file), the way a browser
// gets them: the file's page names the address of this one download
// (https://download<N>.mediafire.com/<token>/<key>/<name>), as its Download button's
// href, or base64 in the button's data-scrambled-url when the page builds the link
// with JavaScript.  The address is good for a while only, so it is read from the
// page every time.  For RKBDI's regional cars, which nfsmods.xyz links there
// (DataMods.swift).  The caller checks the file against a pinned SHA-256.
import Foundation

enum MediaFire {
    struct Failure: Error { let message: String }

    /// The download address on a file's page (its HTML), or nil.
    static func link(inPage html: String) -> URL? {
        var found = [String]()
        let href = try! NSRegularExpression(pattern: #"href="(https://download[0-9]*\.mediafire\.com/[^"\s]+)""#)
        let scrambled = try! NSRegularExpression(pattern: #"data-scrambled-url="([A-Za-z0-9+/=]+)""#)
        let all = NSRange(html.startIndex..., in: html)
        for m in href.matches(in: html, range: all) {
            if let r = Range(m.range(at: 1), in: html) { found.append(String(html[r])) }
        }
        for m in scrambled.matches(in: html, range: all) {
            if let r = Range(m.range(at: 1), in: html), let d = Data(base64Encoded: String(html[r])),
               let s = String(data: d, encoding: .utf8) { found.append(s) }
        }
        for s in found {
            let t = s.replacingOccurrences(of: "&amp;", with: "&")
            if let u = URL(string: t), isDownloadHost(u) { return u }
        }
        return nil
    }

    /// https and a MediaFire download server, nothing else.
    static func isDownloadHost(_ u: URL) -> Bool {
        guard u.scheme == "https", let h = u.host?.lowercased() else { return false }
        return h.hasPrefix("download") && h.hasSuffix(".mediafire.com")
    }

    /// The file page's current download address (call it off the main thread).
    static func resolve(_ page: URL) throws -> URL {
        guard page.scheme == "https", let h = page.host?.lowercased(), h == "www.mediafire.com" || h == "mediafire.com" else {
            throw Failure(message: "\(page.absoluteString) is not a MediaFire file page.")
        }
        var req = URLRequest(url: page, timeoutInterval: 30)
        // the page as a browser gets it (a client MediaFire does not know gets a page without the link)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let done = DispatchSemaphore(value: 0)
        var body: Data?, status = 0, failure: Error?
        let s = URLSession(configuration: .ephemeral)
        s.dataTask(with: req) { d, r, e in
            body = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0; failure = e
            done.signal()
        }.resume()
        done.wait()
        s.finishTasksAndInvalidate()
        guard status == 200, let d = body else {
            throw Failure(message: "MediaFire did not answer (\(failure?.localizedDescription ?? "HTTP \(status)")). Try again later.")
        }
        guard let u = link(inPage: String(decoding: d, as: UTF8.self)) else {
            throw Failure(message: "MediaFire's page has no download link (the file may be gone, or the page has changed).")
        }
        return u
    }
}
