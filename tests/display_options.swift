// tests/display_options.swift: the Display card's options (launcher/DisplayOptions.swift).
// After the old fork's tests/runtime_options.swift (its Display and gameplay part).
import Foundation

@main
struct DisplayOptionsTests {
    static var fails = 0
    static func check(_ ok: Bool, _ what: String) {
        print((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { fails += 1 }
    }
    static func main() {
        let original = DisplayOptions.environment(scale: DisplayOptions.originalScale, framing: DisplayOptions.originalFraming,
                                                  subtitles: false, background: DisplayOptions.originalBackground)
        check(original.isEmpty, "the original game's values set no variable")
        let all = DisplayOptions.environment(scale: "0.75", framing: "fill", subtitles: true, background: "run")
        check(all == ["NFSU2_RENDER": "scale:0.75", "NFSU2_MOVIE": "fill", "NFSU2_SUBTITLES": "1", "NFSU2_BACKGROUND": "run"],
              "every choice reaches the engine (\(all))")
        check(DisplayOptions.environment(scale: "2", framing: "stretch", subtitles: false, background: "pause")
              == ["NFSU2_RENDER": "scale:2", "NFSU2_MOVIE": "stretch"], "200% and stretch")
        let bad = DisplayOptions.environment(scale: "3", framing: "zoom", subtitles: false, background: "sleep")
        check(bad.isEmpty, "unsupported values are not passed on")
        check(DisplayOptions.pick(nil, DisplayOptions.scales, "1") == "1", "a missing saved value is the original")
        check(DisplayOptions.pick("9", DisplayOptions.scales, "1") == "1", "an unknown saved value is the original")
        check(DisplayOptions.pick("1.5", DisplayOptions.scales, "1") == "1.5", "a saved value is kept")
        check(DisplayOptions.scales.map(DisplayOptions.scaleLabel) == ["50%", "75%", "100% (original)", "150%", "200%"],
              "scale labels mark the original")
        check(DisplayOptions.framingLabel("fit").hasSuffix("(original)") && DisplayOptions.backgroundLabel("pause").hasSuffix("(original)"),
              "framing and background mark the original")
        // Exposure and White Level (runtime/picture.m: NFSU2_EXPOSURE -1 .. +1 stops, NFSU2_WHITE_LEVEL 40 .. 100 %)
        check(DisplayOptions.exposures.count == 21 && DisplayOptions.exposures.first == "-1.0" && DisplayOptions.exposures.last == "+1.0"
              && DisplayOptions.exposures[10] == "0" && DisplayOptions.exposures.contains("-0.3"), "exposure: -1.0 .. +1.0 in steps of 0.1")
        check(DisplayOptions.whiteLevels == ["40", "45", "50", "55", "60", "65", "70", "75", "80", "85", "90", "95", "100"],
              "white level: 40 .. 100 % in steps of 5")
        check(DisplayOptions.exposureLabel("0") == "0 (original)" && DisplayOptions.whiteLevelLabel("100") == "100% (original)"
              && DisplayOptions.exposureLabel("-0.3") == "-0.3 (darker)" && DisplayOptions.whiteLevelLabel("70") == "70%",
              "exposure and white level mark the original")
        let tone = DisplayOptions.environment(scale: "1", framing: "fit", subtitles: false, background: "pause", exposure: "-0.3", whiteLevel: "70")
        check(tone == ["NFSU2_EXPOSURE": "-0.3", "NFSU2_WHITE_LEVEL": "70"], "exposure and white level reach the engine (\(tone))")
        check(DisplayOptions.environment(scale: "1", framing: "fit", subtitles: false, background: "pause", exposure: "0", whiteLevel: "100").isEmpty,
              "exposure 0 and white level 100 % set no variable")
        check(DisplayOptions.environment(scale: "1", framing: "fit", subtitles: false, background: "pause", exposure: "-2.0", whiteLevel: "30").isEmpty,
              "an exposure or white level out of range is not passed on")
        for v in DisplayOptions.exposures { let f = Double(v)!; check(f >= -1 && f <= 1, "exposure \(v) within the engine's range") }
        // the engine accepts what the launcher sends (runtime/display.c: scale:<f>, f 0.25 .. 2)
        for s in DisplayOptions.scales { let f = Double(s)!; check(f >= 0.25 && f <= 2, "scale \(s) within the engine's range") }
        exit(fails == 0 ? 0 : 1)
    }
}
