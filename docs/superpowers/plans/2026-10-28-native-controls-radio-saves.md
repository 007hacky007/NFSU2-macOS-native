# Native controls, radio and saves implementation plan

**Goal:** Add the four requested native features on branch native-controls-radio-saves and commit each working stage.

**Architecture:** Reuse donor runtime contracts and cloud formats. Independent native adapters expose multiplayer and radio, Swift helpers implement save management and encrypted sync, and the existing launcher owns settings and launch environment.

**Tech stack:** C/Objective-C, AppKit/Metal, Swift/SwiftUI, Foundation/AudioToolbox/CryptoKit/CommonCrypto, existing Python/shell verification.

**Spec:** ../specs/2026-10-28-native-controls-radio-saves-design.md

## Global constraints

macOS 11; NA-only; system APIs before dependencies; game data read-only; established saves preserved; cloud and multiplayer opt-in; no public-service test connections; no commits containing assets, generated game code, private identities or AI attribution; no push; standard hyphens in new documents.

## Tasks and ownership

- [x] 1. Multiplayer adapter: new runtime native controls files and the roam_bsd callbacks. Test lobby/chat decoding, crew/hash updates, ghost toggle and guest/main-thread handoff. Root integrates Metal/menu/window hooks; commit working adapter and controls.
- [x] 2. Custom music adapter: new runtime native radio files, radio.c native backend selection and focused tests. Reuse protocol rings, decode/resample local music, expose metadata and safe playlist lifecycle. Root integrates build/launcher controls; commit working playback.
- [x] 3. Save management and sync: new Swift save/archive/vault models/views and tests. Validate safe backup/restore and browser-compatible crypto/protocol. Root integrates launcher access and game-running guards. Commit local saves first, then opt-in cloud functionality.
- [x] 4. Launcher language/frame-rate/controller/music/settings UI and environment validation. Add meaningful helper tests, integrate the three independent adapters, build/package and commit working settings.
- [x] 5. Review the integrated branch, fix defects with focused regressions, run native/launcher/network suites and local game/media/cloud checks, inspect UI snapshots, update README and commit verification/documentation.

## Review focus

- Disk-full/invalid ZIP/restore conflicts must preserve the previous career and a usable backup.
- Cloud keyphrases must not enter logs/preferences; stale, empty or competing versions require explicit handling.
- UI callbacks may not call guest code or hold a session lock while dispatching synchronously to the main thread.
- Music pause/switch/end/disconnect must not race ring buffers or leak workers; supported files must decode at the game's rate.
- Launcher choices must override stale inherited variables without leaking offline names or enabling network services.

## Progress

Initial state: clean main at e4aae47; origin uses SSH; repository author/committer identity is the public pseudonym. Existing native source, generated objects, game data and previous local test artifacts are available. Implementation stays on the requested new branch; root owns staging and local commits to avoid shared-index races.

Working commits:

- `587bb94` records this plan and the agreed scope.
- `440bb33` adds validated launcher language, frame-rate, controller and music choices.
- `b881f30` adds local save listing, ZIP backup/import/export and staged restore.
- `a81754f` adds AppKit Game Tools, multiplayer callbacks and native folder music.
- `5cd6681` adds browser-compatible cloud exchange and reviewed restore safety fixes.

## Verification results

All results below use synthetic media/profiles, isolated game save/registry/support directories or read-only copies of a generated smoke career. No player saves were uploaded and no public relay/vault was contacted.

| Check | Result |
|---|---|
| `./run.sh test` | 610 ISA, 65 function/runtime, 287 roam and 240 Winsock checks passed |
| `tests/runtime_options.sh`, `tests/launcher_settings.sh` | Defaults, persistence, installed packs, invalid values and inherited-environment clearing passed |
| `tests/native_controls.sh` | Sanitized state/JSON/crew/phrase/queue tests, AppKit button actions and strong production callback overrides passed |
| `tests/radio_native.sh` | System decoder/ring and guest mixer integration passed; 58 donor mixer scenarios passed |
| Native radio extra checks | AddressSanitizer and macOS 11 strict compilation passed; synthetic MP3/AAC/FLAC decoded through system codecs |
| `tests/save_manager.sh` | ZIP/profile validation, traversal/collision/symlink limits, running-game guards, merge/full restore and post-swap registry-failure rollback passed |
| `tests/vault.sh` | Native and Node WebCrypto key derivation/token/AES-GCM/raw-deflate match; device payload filtering passed |
| `tests/vault_local.py` | Local Rust donor 404/create/get/update, stale ETag conflicts, native-to-browser-to-native ZIP exchange, redirect refusal and response-size limits passed |
| `tests/net/native/loopback.py` | Relay, resume, queue, two-client, idle, burst and exit fixtures passed |
| `./link.sh`, `./pack.sh` | Both engines and the complete Swift launcher built for macOS 11; ad-hoc bundle produced in `out/NFSU2.app` |

The native radio game run (`out/new-radio-smoke`) entered a quick race, changed tracks in the menus, switched to driving music and exited 0 after 61 seconds. Sound output was muted; the decoder/mixer integration tests verify PCM, gains, resampling, pause/resume, next-track and soundtrack restoration.

`out/new-tools-smoke` exercised Cmd+Shift+M twice in the real game and exited 0. Command shortcuts stayed out of guest keyboard input. The packaged HD run in `out/new-hd-runtime-smoke` loaded the French language overlay, reported a 60 FPS content rate and exited 0; its bundle log is under `support/Logs`.

UI inspection used `out/new-launcher.png`, `/private/tmp/native-controls.png` and `out/tmp/save-manager-preview/save-manager.png`. The save preview contains a synthetic TEST career and performs no network or Keychain calls. The launcher settings, native crew colour pickers, music controls and cloud opt-in actions were readable.

Review reproduced and fixed a mixed-case save-root validation bypass on case-insensitive filesystems. It also added a regression for failure after the save directory swap and preserved the original staged folder if rollback itself fails. Radio guest calls release the producer mutex; a regression verifies the previous lock-inversion path would fail.

Not exercised: public services, full browser-to-native multiplayer races, physical controller input, audible playback, real Keychain prompts/persistence, long career sessions, actual disk exhaustion, or simultaneous restore-and-rollback filesystem failure. macOS 11 deployment targets compile here; execution was on the current host OS. The earlier local two-native-client Online race is recorded in the online/UHUD plan. This branch has not been pushed.
