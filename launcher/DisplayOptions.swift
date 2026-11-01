// The Display card's options (Settings › Graphics): resolution scale, Exposure
// and White Level, how the movies fill a wide window and their subtitles, and
// what the game does while another app is active.  Each one is passed to the
// engine as an environment variable (runtime/display.c, picture.m, language.c,
// lifecycle.c); the original game's value sets nothing.  Foundation only, so tests/display_options.swift can use it.
import Foundation

enum DisplayOptions {
    /// NFSU2_RENDER scale:<f>: the game's "Screen" resolution at this share of the
    /// window's pixels.  "1" is the original 1:1.
    static let scales = ["0.5", "0.75", "1", "1.5", "2"]
    /// NFSU2_MOVIE
    static let framings = ["fit", "fill", "stretch"]
    /// NFSU2_BACKGROUND
    static let backgrounds = ["pause", "run"]

    /// NFSU2_EXPOSURE: the picture times 2^stops, -1 .. +1 in steps of 0.1 (qUINT Lightroom's range)
    static let exposures = (-10...10).map { $0 == 0 ? "0" : String(format: "%+.1f", Double($0) / 10) }
    /// NFSU2_WHITE_LEVEL: the brightest the picture gets, in percent, 40 .. 100 in steps of 5
    static let whiteLevels = stride(from: 40, through: 100, by: 5).map(String.init)

    static let originalScale = "1", originalFraming = "fit", originalBackground = "pause"
    static let originalExposure = "0", originalWhiteLevel = "100"

    static func scaleLabel(_ v: String) -> String {
        let pct = Int(((Double(v) ?? 1) * 100).rounded())
        return v == originalScale ? "100% (original)" : "\(pct)%"
    }
    static func framingLabel(_ v: String) -> String {
        switch v {
        case "fill": return "Fill the screen"
        case "stretch": return "Stretch"
        default: return "Fit (original)"
        }
    }
    static func exposureLabel(_ v: String) -> String {
        v == originalExposure ? "0 (original)" : (Double(v) ?? 0) < 0 ? "\(v) (darker)" : "\(v) (brighter)"
    }
    static func whiteLevelLabel(_ v: String) -> String {
        v == originalWhiteLevel ? "100% (original)" : "\(v)%"
    }
    static func backgroundLabel(_ v: String) -> String {
        v == "run" ? "Keep running" : "Pause (original)"
    }

    /// A saved value, or the original game's when it is missing or not one of ours.
    static func pick(_ saved: String?, _ allowed: [String], _ original: String) -> String {
        guard let v = saved, allowed.contains(v) else { return original }
        return v
    }

    /// The engine's variables for these choices; empty for the original game.
    static func environment(scale: String, framing: String, subtitles: Bool, background: String,
                            exposure: String = originalExposure, whiteLevel: String = originalWhiteLevel) -> [String: String] {
        var env: [String: String] = [:]
        if scale != originalScale && scales.contains(scale) { env["NFSU2_RENDER"] = "scale:" + scale }
        if exposure != originalExposure && exposures.contains(exposure) { env["NFSU2_EXPOSURE"] = exposure }
        if whiteLevel != originalWhiteLevel && whiteLevels.contains(whiteLevel) { env["NFSU2_WHITE_LEVEL"] = whiteLevel }
        if framing != originalFraming && framings.contains(framing) { env["NFSU2_MOVIE"] = framing }
        if subtitles { env["NFSU2_SUBTITLES"] = "1" }
        if background != originalBackground && backgrounds.contains(background) { env["NFSU2_BACKGROUND"] = background }
        return env
    }
}
