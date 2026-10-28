# Photo mode, drift HUD, launcher settings and multiplayer polish

Implement roadmap items 1, 2, 4 and 5 together on native-photo-drift-polish, based on main at 1d1f3c3. The previous branch passed its core, launcher, controls, radio, save, vault and local networking checks before the fast-forward merge. Work remains local unless publication is requested.

## Photo mode and gallery

Adapt the imported photo.c protocol to native AppKit/Metal. In supported offline driving views, offer orbit/free camera, movement, zoom, tilt, reset, capture and exit. Use a native menu/shortcut and the existing pause-menu integration where available. Consume photo input before it reaches driving controls; clear held input on exit, focus loss and controller disconnect. Keep the donor restriction against freezing network races. PNG capture must read the rendered Metal frame asynchronously, outside the guest lock, to a unique file under Application Support/NFSU2/Screenshots. Add a native gallery with thumbnails, preview, reveal/export and confirmed deletion, without writing to game data. Screenshot failure must preserve gameplay and existing files.

## Drift HUD

Expose the existing drift.c status to a native overlay in free roam, including live points, multiplier/next-level progress, best and total, with banked/lost feedback. Hide it when inactive, in menus or in photo mode. Publish bounded snapshots from the guest; AppKit reads them on the main thread. Keep the game's drift physics/scoring unchanged.

## Launcher settings

Extend the current RuntimeOptions model and cards with resolution scale (50/75/100/150/200%), wide/original HUD, subtitles, movie framing (fit/fill/stretch), cutscene bars, other cars' headlights (players/all/off), background pause/run and a free-roam room name. Use existing runtime environment variables, clear stale inherited values and preserve saved older options through explicit Codable defaults. Validate every option before launch. Room names follow donor validation; a named room filters players and is not private. Empty means everyone. Native launcher text stays English in this batch; game language support stays unchanged.

## Multiplayer polish

Keep the existing Game Tools and network protocols. Add four configurable quick-chat groups with four donor phrase IDs each, keyboard and controller selection that does not leak selected keys/stick input into driving, and transient bubbles positioned over nearby cars through roam_plat_say_marks. Preserve the complete phrase picker. Hide overlays in photo mode and menus, expire messages and avoid stale bubbles on disconnect. Room selection applies on next launch through the launcher. No private-room claim or automatic service connection.

## Constraints and verification

- Apple Silicon/macOS 11 deployment target; existing C/Objective-C/Swift, system libraries, Original and HD engines.
- Existing saves, music, UHUD, online configuration and read-only game data remain supported.
- No assets/generated guest code, personal data or AI attribution committed. ASCII hyphens in documentation; brief commits with the authorized public pseudonym.
- No public relay/vault connections or user-save mutations during verification. Use synthetic fixtures, isolated directories and loopback.
- Focused behavior tests before new nontrivial logic; production build/package, existing regression suites, UI inspection and isolated real-game photo/drift checks.
- Root stages and commits working stages. Native adapters never dispatch synchronously to the main thread while holding guest/session locks.
