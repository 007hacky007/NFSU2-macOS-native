# Remaining web-version features

Compared the local nfsu2-web source at cc3b3df with NFSU2Recomp at b4cb8b8 on 2026-10-28. Effort estimates come from source inspection; hardware-dependent work still needs device testing.

| # | Addition | Remaining native work | Effort | Selection |
|---|---|---|---|---|
| 1 | Photo mode and screenshot gallery | Native orbit/free camera controls, zoom/tilt, PNG capture and gallery. Game-side photo code is imported. | Medium | Next batch |
| 2 | Free-roam drift HUD | Current drift points, multiplier, best and total. Existing drift handling needs its native score panel. | Small-medium | Next batch |
| 3 | Controller rumble | Connect the shared force-feedback mixer to native controller vibration. | Medium; hardware testing | Backlog |
| 4 | More launcher settings | Resolution scale, HUD placement, subtitles, movie framing, cutscene bars, other cars' headlights and background behavior. Runtime settings mostly exist. | Small-medium | Next batch |
| 5 | Multiplayer polish | Room selection, customizable quick-chat groups, controller shortcuts and chat bubbles above nearby cars. | Medium | Next batch |
| 6 | More career tools | Profile rename, save-mode selection, direct PC profile import and explicit handling of editor-modified checksums. Current manager imports validated ZIPs. | Medium | Backlog |
| 7 | Privacy-safe diagnostic export | Export logs with paths, player names and network addresses redacted. Current launcher opens the logs folder. | Small-medium | Backlog |
| 8 | Steering wheel support | Wheel/pedal calibration, per-device mappings and shifter modes. Native currently handles standard gamepads. | Large; physical wheel needed | Backlog |

Items 1, 2, 4 and 5 are authorized as one feature branch after merging the completed native-controls-radio-saves branch into main. Items 3, 6, 7 and 8 remain suggestions.
