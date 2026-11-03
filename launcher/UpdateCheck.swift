// Settings › Check for updates: every two hours the launcher asks GitHub whether a newer
// NFSU2 Builder is out, and the main window says so (when it opens, and while it stays
// open).  New features come only from a
// new Builder, which updates this app with the game inside it in one click.
//
// Only for an app made by NFSU2 Builder: its Info.plist has NFSBuilderVersion (pack.sh
// BUILDER_VERSION).  One GET of the latest release, with "NFSU2-Launcher" as the
// User-Agent and nothing else that identifies the player, in the background, 5 s at
// most; any failure is silent.  Download opens the disk image's address in the
// browser, so it is a normal browser download: the launcher itself never downloads
// or runs anything.  Off: no request at all.
import Foundation

enum UpdateCheck {
    static let releasesAPI = URL(string: "https://api.github.com/repos/007hacky007/NFSU2-macOS-native/releases/latest")!
    static let userAgent = "NFSU2-Launcher"
    static let asset = "NFSU2-Builder.dmg"
    static let interval: TimeInterval = 2 * 60 * 60
    static let stampKey = "NFSBuilderVersion"

    struct Release: Equatable {
        let version: String
        let page: URL            // the release's page: What's new
        let download: URL?       // the disk image: Download
    }

    /// The Builder version this app was made with, if a Builder made it.
    static func stamp(of bundle: URL) -> String? {
        let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return (info?[stampKey] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// "1.10.0" > "1.9.2": numbers compared one by one, a missing one counts as 0; a leading
    /// "v" is ignored, and anything after a number (as in "1.2.0-beta") is not part of it.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let s = v.hasPrefix("v") || v.hasPrefix("V") ? String(v.dropFirst()) : v
            return s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// A check is due when none was made, or the last one is two hours old (or in the future: the clock moved).
    static func isDue(last: Date?, now: Date) -> Bool {
        guard let last = last else { return true }
        return now.timeIntervalSince(last) >= interval || last > now
    }

    /// The release from GitHub's answer: tag_name, html_url, and the disk image among the assets.
    static func parse(_ data: Data) -> Release? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = obj["tag_name"] as? String, !tag.isEmpty,
              let pageText = obj["html_url"] as? String, let page = URL(string: pageText), page.scheme == "https"
        else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        guard version.first?.isNumber == true else { return nil }
        let assets = obj["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String) == asset }
            .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
        return Release(version: version, page: page, download: dmg?.scheme == "https" ? dmg : nil)
    }

    /// One request, nothing stored (no cookies, no cache).  Calls back with the body of a 200 answer, or nil.
    static func fetch(_ url: URL, done: @escaping (Data?) -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: config)
        session.dataTask(with: request) { data, response, _ in
            done((response as? HTTPURLResponse)?.statusCode == 200 ? data : nil)
            session.finishTasksAndInvalidate()
        }.resume()
    }
}
