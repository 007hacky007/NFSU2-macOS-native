# Native upgrade implementation plan

**Goal:** Upgrade the native game core and expose UHUD and compatible online play through the Mac launcher.

**Architecture:** Import the NA native compiler/runtime as a coordinated baseline. Keep the existing Swift launcher and packaging, and add platform adapters for WebSocket multiplayer and UHUD packs.

**Tech stack:** C, Objective-C/Metal/Foundation, Swift/SwiftUI, Python generation, shell build tooling.

**Spec:** ../specs/2026-10-28-native-online-uhud-design.md

## Constraints

NA executable only; offline default; explicit multiplayer name; no public game-server connections during tests; preserve existing saves/registry; game files read-only; retain MIT notices; no game assets, binaries or generated C in git; ASCII hyphens in new documents.

## Tasks

- [x] 1. Import donor native core, compiler and regression tools; retain launcher and adapt packaging and old save/registry paths. Regenerate from the user's NA executable. Build and run ISA/function, heap and controller checks.
- [x] 2. Add native WebSocket relay transport and bridge free roam plus Winsock virtual networking to the browser protocol. Test URL validation, relay handshake, local traffic and disconnect behavior. Own new networking adapter files; coordinate hooks in existing native files with task 1.
- [x] 3. Add native UHUD .pak reading and Metal replacement support with parser validation and fixture tests. Inspect the supplied game folder for a ready pack or extracted assets. Own texture adapter files and tools/tests; coordinate Metal hooks with task 1.
- [x] 4. Extend Swift launcher with Offline/Online, server URL, explicit player name and Original/UHUD selection/import. NA-only detection, correct engine names, existing portable behavior. Test configuration validation and environment construction; compile launcher.
- [x] 5. Integrate adapters, fix Metal ps_2_0 coordinates, package the app, run scripted native scenarios and local online checks. Review the entire change and resolve defects. Update README with exact supported behavior and verification limits.

## Review focus

- Missing or malformed packs must fall back safely without damaging game files.
- Online mode must never send a local account/profile name implicitly.
- TLS uses system validation; only explicit ws:// loopback is accepted for tests.
- Disconnects and failed relays must wake network waits and avoid stale peers.
- Original save paths and existing launcher portable copies must remain usable.

## Progress

Initial inspection: clean checkout, feature branch native-online-uhud-upgrade created. NA executable SHA-256 matches donor. Xcode/Swift and Python lifter dependencies are available. No pre-existing compiled engine or generated C to baseline-test; original launcher binary exists. Build verification starts from the imported core.

## Verification record

- Native Original and HD binaries built; Swift launcher compiled for arm64 macOS 11. Packaged and ad-hoc signed `out/NFSU2.app`.
- `./run.sh test`: 610 ISA checks, 65 lifted-function/runtime checks, 287 free-roam checks and 240 Winsock checks passed, no failures.
- Register-local/x87-optimized ISA generation: the same 610 checks passed separately. The packaged game uses the native generator's conservative defaults; no performance gain is claimed from optional optimization.
- Heap stress, GameController harness, object-table and watchdog tests passed.
- UHUD parser fixture tests passed under ASan/UBSan; all 574 real-pack entries validated and uploaded to Metal. GPU binding tests cover DDS coexistence, exact-match UHUD precedence, original guest dimensions, mip preservation, sharing, toggle, changed content and release.
- Launcher settings/import tests passed, including atomic preservation of the previous pack on malformed metadata. Save-path regression test passed for terminal fallback, explicit override and legacy-folder migration. Metal ps_2_0 coordinates and color-clamping tests passed.
- Scripted Original quick race and UHUD packaged-app race passed with no traps or unresolved calls. The UHUD run showed 497 replacements with no unreadable entries or budget misses. Captured images were inspected.
- Native VP6 story playback was inspected. A separate new-career test with movie skipping reached gameplay and exited cleanly. Tests use isolated saves/registry files and read-only game data.
- Foundation WebSocket fixture passed URL validation, token and queue-ticket resume, two-client routing, fair 256-frame burst, idle release and normal-exit release. Protocol units passed UDP/TCP/FIN/disconnect and BSD descriptor compatibility.
- Actual donor Rust relay built and tested only on loopback. Native guest TCP authenticated to its Online lobby; the full packaged game entered its lobby. Two packaged native clients created/joined the same Circuit race, exchanged chat and reported two racers.
- Both native clients naturally finished that two-lap Circuit race and reached results (the server recorded 98.64 and 98.12 seconds). Both returned to the lobby and exited 0. Network queues did not overflow, no links reset during the race and no connection timed out. The HD integrity race also passed with no traps or unresolved calls. The local test relay was stopped after verification.
- Portable-copy integration passed. Its bundle signature verifies and contains movies, server.dll and the supplied UHUD pack. Both normal and portable app signatures verify.

## Review decisions

The final review found and resolved four integration defects: voluntary release needed the server's exact close semantics; idle release needed the state-before-demand recheck; outgoing traffic needed completion-driven draining and fairness; imported packs needed the same metadata validation as the runtime. Terminal save fallback and the old folder migration were restored with regression tests. The file layer always protects the game data.

Native and browser clients share game/network logic, but browser overlay controls are not embedded into the native application. Public WSS service interaction, physical controller input and long career sessions have not been tested. Server validation used the real server code on loopback rather than public players.
