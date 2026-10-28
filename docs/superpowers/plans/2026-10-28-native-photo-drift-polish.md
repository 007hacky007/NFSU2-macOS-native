# Native photo, drift and multiplayer polish implementation plan

**Goal:** Complete roadmap items 1, 2, 4 and 5 on one new branch.

**Architecture:** Reuse imported photo/drift/game protocols with native UI/input/capture adapters. Extend current Swift settings and Game Tools. Keep guest state publication bounded and rendering/UI on their existing threads.

**Tech stack:** C, Objective-C/AppKit/Metal, Swift/SwiftUI, existing shell and game-script verification.

**Spec:** ../specs/2026-10-28-native-photo-drift-polish-design.md

## Global constraints

macOS 11; both engines; system libraries; read-only game data; no public-service tests or user-save changes; no publication without authorization; ASCII documentation hyphens; root owns staging/commits.

## Tasks and interfaces

- [ ] 1. Native scene adapter: create runtime/native_scene.h/.m and bounded status bridge as needed; adapt photo_input and drift status. Own Metal event-loop/capture wiring, photo UI and launcher/PhotoGallery.swift. Expose native_scene_attach(window, menu), native_scene_pump(), native_scene_guest_frame(), native_scene_handle_event(event), and PhotoGalleryWindow.show(folder: URL). Wire multiplayer event handling through native_controls_handle_event(event), which consumes only its own active selection. Add focused input/state/capture/gallery tests, then isolated game checks. Root integrates Present call/build and launcher gallery button.
- [ ] 2. Multiplayer adapter: extend native_controls.h/.m and roam_bsd.c for configurable 4x4 groups, keyboard/controller selection and positional chat bubbles. Expose int native_controls_handle_event(NSEvent*) for Metal; existing attach/pump/guest_frame lifecycle remains. Coordinate photo visibility through native_scene_active() (weak standalone fallback). Do not edit metal.m or Swift. Add donor-ID/layout, timeout, key suppression, controller release and bounded positional-state tests.
- [ ] 3. Launcher settings: root extends RuntimeOptions.swift/RuntimeViews.swift and Model.swift/Views.swift. Add backward-compatible decoding and environment validation for render/HUD/subtitles/framing/bars/headlights/background/room; add meaningful migration/invalid-value/override tests. Integrate gallery button. Commit working settings.
- [ ] 4. Review integrated diff, repair findings with regressions, compile/link both engines, build app, verify signatures, run core/native/launcher/save/network regressions and isolated game/UI checks. Document exact limitations in README and this plan; commit final verification.

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
