# Native controls, custom music and saves

The user selected the next additions numbered 1, 2, 4 and 5: native multiplayer controls; launcher language/frame-rate/controller settings; custom folder music; and a save manager with backups/import/export followed by optional encrypted cloud sync. Work starts at e4aae47 on a new branch. Commit working stages locally with the existing public pseudonym identity. No push or publication is requested.

## Multiplayer

Use AppKit controls attached to the native game window, accessible from a game menu/keyboard shortcut. Show the shared free-roam lobby state, nearby notices and quick-chat messages. Expose the donor's preset quick-chat phrases, up to four crews with colours, and solid/ghost-car mode. Reuse roam_plat_* contracts and the existing game/relay logic. Change control state through a thread-safe native adapter; UI work runs on the main thread and does not hold the guest/session lock. Game input must not consume text entered into the native panel.

## Launcher settings

Expose installed game languages, supported frame limits (auto, 30, 60, 120, 240), controller enable/hotplug and stick/trigger dead zones. Preserve existing server, UHUD, engine and portable settings. Validate values before constructing the explicit child environment. Map onto existing runtime variables rather than create a second configuration scheme. No language downloads occur automatically.

## Custom music

Offer the game soundtrack or a folder chosen by the player. Decode supported local audio through system audio APIs and feed the existing radio/mixer hooks so the game's volume, pause, song ordering and track plaque still work. Show artist/title metadata when available, resample to the mixer's rate, bound buffering, and skip unsupported or corrupt tracks. Folder playback makes no network requests, and disabling it preserves EA Trax. The launcher passes a selected folder, never a host username or inferred identity. Add native playback controls where practical to the same game tools panel/menu.

## Local saves

Provide a native save manager with profile listing, backup/export and restore/import. Use standard ZIP archives compatible with the donor backup layout. Validate entries and profile structure, refuse traversal/symlinks/oversized archives, stage restores and keep a pre-restore backup. Restore/import is blocked while the game is running. Never change the game folder or remove the last good save after a failed operation. Keep established save/registry paths. Local backup/export does not upload anything.

## Optional encrypted sync

Use the donor vault protocol and keyphrase format so browser/native players can exchange career saves. Use platform cryptography, preserve browser PBKDF2/AES-GCM/wire compatibility and payload filtering. Default the vault endpoint from the selected server with a configurable URL. Linking and sending require explicit controls; no startup upload or linking from player identity. Keep keys/keyphrases in Keychain when remembering them, not source/logs/preferences. Conflict resolution preserves copies and asks which version to use; empty or older remote state must not silently replace local careers. Device settings and LAN records do not overwrite another device's settings. Verify using local fixtures and the local donor server only.

## Constraints and checks

- Apple Silicon/macOS 11, existing SwiftUI/AppKit/Metal runtime; no new third-party runtime dependency without a concrete need.
- Existing NA executable, Original and HD engines, read-only game data and legacy save paths remain supported.
- System TLS validation; insecure endpoints limited to loopback tests. No live game/cloud service tests or user-save uploads.
- Generic synthetic identities/media/profiles for tests. No private data, game assets or generated C committed.
- Focused failing tests before new logic, compile both engines and launcher, run native/launcher/network regressions, exercise UI snapshots and game smoke scenarios. Preserve exact limitations in the final verification record.
