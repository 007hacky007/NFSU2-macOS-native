# Native controls, radio and saves implementation plan

**Goal:** Add the four requested native features on branch native-controls-radio-saves and commit each working stage.

**Architecture:** Reuse donor runtime contracts and cloud formats. Independent native adapters expose multiplayer and radio, Swift helpers implement save management and encrypted sync, and the existing launcher owns settings and launch environment.

**Tech stack:** C/Objective-C, AppKit/Metal, Swift/SwiftUI, Foundation/AudioToolbox/CryptoKit/CommonCrypto, existing Python/shell verification.

**Spec:** ../specs/2026-10-28-native-controls-radio-saves-design.md

## Global constraints

macOS 11; NA-only; system APIs before dependencies; game data read-only; established saves preserved; cloud and multiplayer opt-in; no public-service test connections; no commits containing assets, generated game code, private identities or AI attribution; no push; standard hyphens in new documents.

## Tasks and ownership

- [ ] 1. Multiplayer adapter: new runtime native controls files and the roam_bsd callbacks. Test lobby/chat decoding, crew/hash updates, ghost toggle and guest/main-thread handoff. Root integrates Metal/menu/window hooks; commit working adapter and controls.
- [ ] 2. Custom music adapter: new runtime native radio files, radio.c native backend selection and focused tests. Reuse protocol rings, decode/resample local music, expose metadata and safe playlist lifecycle. Root integrates build/launcher controls; commit working playback.
- [ ] 3. Save management and sync: new Swift save/archive/vault models/views and tests. Validate safe backup/restore and browser-compatible crypto/protocol. Root integrates launcher access and game-running guards. Commit local saves first, then opt-in cloud functionality.
- [ ] 4. Launcher language/frame-rate/controller/music/settings UI and environment validation. Add meaningful helper tests, integrate the three independent adapters, build/package and commit working settings.
- [ ] 5. Review the integrated branch, fix defects with focused regressions, run native/launcher/network suites and local game/media/cloud checks, inspect UI snapshots, update README and commit verification/documentation.

## Review focus

- Disk-full/invalid ZIP/restore conflicts must preserve the previous career and a usable backup.
- Cloud keyphrases must not enter logs/preferences; stale, empty or competing versions require explicit handling.
- UI callbacks may not call guest code or hold a session lock while dispatching synchronously to the main thread.
- Music pause/switch/end/disconnect must not race ring buffers or leak workers; supported files must decode at the game's rate.
- Launcher choices must override stale inherited variables without leaking offline names or enabling network services.

## Progress

Initial state: clean main at e4aae47; origin uses SSH; repository author/committer identity is the public pseudonym. Existing native source, generated objects, game data and previous local test artifacts are available. Implementation stays on the requested new branch; root owns staging and local commits to avoid shared-index races.
