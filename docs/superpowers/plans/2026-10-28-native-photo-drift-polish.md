# Native photo, drift and multiplayer polish implementation plan

**Goal:** Complete roadmap items 1, 2, 4 and 5 on one new branch.

**Architecture:** Reuse imported photo/drift/game protocols with native UI/input/capture adapters. Extend current Swift settings and Game Tools. Keep guest state publication bounded and rendering/UI on their existing threads.

**Tech stack:** C, Objective-C/AppKit/Metal, Swift/SwiftUI, existing shell and game-script verification.

**Spec:** ../specs/2026-10-28-native-photo-drift-polish-design.md

## Global constraints

macOS 11; both engines; system libraries; read-only game data; no public-service tests or user-save changes; no publication without authorization; ASCII documentation hyphens; root owns staging/commits.

## Tasks and interfaces

- [x] 1. Native scene adapter: create runtime/native_scene.h/.m and bounded status bridge as needed; adapt photo_input and drift status. Own Metal event-loop/capture wiring, photo UI and launcher/PhotoGallery.swift. Expose native_scene_attach(window, menu), native_scene_pump(), native_scene_guest_frame(), native_scene_handle_event(event), and PhotoGalleryWindow.show(folder: URL). Wire multiplayer event handling through native_controls_handle_event(event), which consumes only its own active selection. Add focused input/state/capture/gallery tests, then isolated game checks. Root integrates Present call/build and launcher gallery button.
- [x] 2. Multiplayer adapter: extend native_controls.h/.m and roam_bsd.c for configurable 4x4 groups, keyboard/controller selection and positional chat bubbles. Expose int native_controls_handle_event(NSEvent*) for Metal; existing attach/pump/guest_frame lifecycle remains. Coordinate photo visibility through native_scene_active() (weak standalone fallback). Do not edit metal.m or Swift. Add donor-ID/layout, timeout, key suppression, controller release and bounded positional-state tests.
- [x] 3. Launcher settings: root extends RuntimeOptions.swift/RuntimeViews.swift and Model.swift/Views.swift. Add backward-compatible decoding and environment validation for render/HUD/subtitles/framing/bars/headlights/background/room; add meaningful migration/invalid-value/override tests. Integrate gallery button. Commit working settings.
- [x] 4. Review integrated diff, repair findings with regressions, compile/link both engines, build app, verify signatures, run core/native/launcher/save/network regressions and isolated game/UI checks. Document exact limitations in README and this plan; commit final verification.

## Review focus

- Photo controls and quick chat must release swallowed input across focus/visibility/controller changes.
- Screenshot capture and gallery deletion may not overwrite unrelated files or follow unsafe paths.
- Native overlays must track resized/full-screen windows and never block game input when inactive.
- New saved-option decoding must preserve old language/controller/music choices and reject invalid settings.
- Main-thread UI work must not wait on a guest holding a runtime lock; all producer snapshots are bounded.

## Progress

- Roadmap committed as 1d1f3c3 and previous branch fast-forwarded into local main after fresh checks.
- Single feature branch native-photo-drift-polish created from that main.
- Existing generated objects and local game fixtures reused in place; no additional worktree needed for the requested single-branch workflow.


## Completed stages

- `fe812c7`: expanded launcher display/gameplay settings and old-options decoding.
- `18fdb89`: preserved UTF-8 room names within the donor byte limit.
- `1832b13`: screenshot gallery and launcher access.
- `7892f5d`: exact shared room-name rejection before launch; package/test builds import runtime/names.h and watch its timestamp.
- `3ab1430`: native photo/drift/chat overlays, input adapters, PNG capture and native headlight CPU/Metal shader path.

## Verification results

All game runs used their own save, registry, support and screenshot directories; no public relay/vault or user saves were used. The previous branch passed fresh tests before its fast-forward into local main. Main remains at that merge while this branch contains the new work.

| Check | Result |
|---|---|
| `./run.sh test` | 610 ISA, 65 function/runtime, 287 roam, 240 Winsock checks passed |
| `tests/runtime_options.sh`, `tests/launcher_settings.sh` | Saved older JSON choices preserved, defaults/UTF-8 room limits/rejected room names and inherited environment overrides passed |
| `tests/photo_gallery.sh` | Valid PNG listing/preview/export/delete passed; symlinks, hardlinks, oversized/corrupt files, stale selections and replaced folders rejected |
| `tests/native_scene.sh` | ASan/UBSan snapshots, focus/key release/controller quarantine/reconnect, drift feedback, actual asynchronous GPU PNG and AppKit overlay visibility/resize checks passed |
| `tests/native_controls.sh` | ASan/UBSan state/UI actions plus grouped key/pad input, timeout, offline/photo suppression, bounded bubbles and disconnect cleanup passed |
| `tests/headlights_native.sh` | Car selection/exclusions/nearest eight, immutable frame pools, Original/HD actual GPU pixels, projector transform/falloff and off/unrelated-shader preservation passed |
| `tests/save_manager.sh` | Existing backup/import/restore regressions passed |
| `tests/net/native/loopback.py` | Native relay/resume/queue/two-client/idle/burst/exit fixtures passed |
| `./link.sh`, `./pack.sh` | Both engines and complete launcher built with macOS 11 targets; local bundle contains both engines |

Real packaged game scenarios:

- `out/native-photo-smoke`: 51 seconds, exit 0. F12 entered photo mode, debug camera and frozen world/clock assertions passed, actual PNG saved, Escape restored drive camera and advancing clock. Captured PNG inspected.
- `out/native-drift-smoke`: HD engine, 82 seconds, exit 0. New synthetic career reached free roam; X enabled and then disabled the existing drift handling, both memory assertions passed.
- `out/native-headlight-fixed-smoke`: 54 seconds, exit 0. Frozen world/camera verified. All selected three AI-car projectors. Relative to Off, only a bounded road region changed (mean RGB difference 0.036553); Self diagnostic difference 0.621770. Switching Off again was pixel-identical to the original Off capture. The initial scenario requested photo mode before the race intro finished; its freeze assertion failed, so the scenario was corrected to wait until driving and rerun.

UI snapshots inspected: synthetic gallery at out/tmp/photo-gallery-preview/photo-gallery.png, photo/drift at /private/tmp/nfsu2-scene-overlay.png and its .photo.png companion, chat editor/overlay at /private/tmp/nfsu2-polish-groups.png and /private/tmp/nfsu2-polish-overlay.png. Tests use synthetic names/media and do not publish captures.

Review found that format-only room validation could silently join Everyone when the runtime rejected the name. A failing regression reproduced it; launcher now calls the runtime's exact C validator before launch. Scoped re-review confirmed the fix and the package cache now tracks that shared header. No remaining review blockers.

Limitations: no physical controller tests, public-server play, full browser/native multiplayer race, long career session or minimum-OS execution. Chat bubbles/shortcuts were tested with synthetic positional/input fixtures and loopback transport, not a live two-player visual session. PNGs omit native control overlays by design. No push or publication of the merged main/new branch was requested in this turn.
