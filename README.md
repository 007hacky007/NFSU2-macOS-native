# NFSU2Recomp

Run Need for Speed: Underground 2 natively on Apple Silicon with a Swift launcher, Metal graphics, CoreAudio sound and GameController input. Bring your own PC game files. This repository contains no game assets or generated game code.

The native core is updated from [nfsu2-web](https://github.com/th0mk/nfsu2-web) at `cc3b3df`. Browser and native players use the same relay protocol. This application runs native code; it does not embed the browser game.

## Changes from the original fork

This fork started from [TalhaMudo/NFSU2Recomp](https://github.com/TalhaMudo/NFSU2Recomp) at `b237c9d`. The original project already provided the native Apple Silicon recompiler, Metal renderer, Original/HD engines, Swift launcher, career saves and portable copies. This update keeps those features and integrates the newer NA runtime from nfsu2-web at `cc3b3df`.

| Area | Original fork at `b237c9d` | This fork |
|---|---|---|
| Online play | No network play | Native WebSocket relay for free roam and Online/LAN race traffic, configurable server, queue/resume and player counts |
| Menus and HUD | Original game textures | Optional UHUD `.pak` support through Metal, with validated import and original guest texture dimensions |
| Controllers | Keyboard and mouse | Native GameController input, analog sticks/triggers, hotplug and saved DirectInput bindings |
| Movies | Videos skipped | Native VP6 playback and skippable startup movies |
| Memory | Bump allocation; frees did not reclaim memory | Reusable heaps and virtual-memory management, with stress and corruption checks |
| Display and timing | Widescreen renderer correction and existing frame limiter | Game-side FOV/HUD/cutscene fixes and frame pacing with high-refresh timing corrections |
| Shaders and compiler | Earlier shader translation and instruction handling | Fixed declared `ps_2_0` texture coordinates, updated x87 precision and SSE2 handling, and optional register-local lifting |
| Launcher and portable copies | Engine/full-screen selection and portable export | Adds Offline/Online, explicit player name, server/count URLs and Original/UHUD controls; portable copies retain movies and `server.dll` |
| Executables | EU and NA v1.2 | NA v1.2 only; EU support was intentionally dropped |
| Verification | Earlier ISA/function tests and integrity checks | 610 ISA, 65 function/runtime, 287 free-roam and 240 Winsock checks, plus launcher, UHUD, save-path and local WebSocket tests |

The shared compiler and game/runtime improvements come from nfsu2-web. The native Foundation WebSocket bridge, Metal UHUD integration and Swift launcher controls were added here. Donor copyright and license notices are retained in `third_party/nfsu2-web-LICENSE`.

Two packaged native clients completed a two-lap Online race through a local instance of the donor's Rust server, returned to the lobby and exited cleanly. Original/HD races, UHUD rendering, career startup, VP6 playback and portable packaging were also checked. Public `nfsu2.xyz` connections, browser-to-native races, physical controllers and long career sessions remain untested.

## Requirements

- Apple Silicon Mac with macOS 11 or later.
- North American v1.2 `SPEED2.EXE`: 4,800,512 bytes, SHA-256 `f9dd86c054878ce6276beb07c1fd61874f7a1e4bf1f241b084c65b73e24168a7`.
- Your game's data folders. Keep `MOVIES` for videos and `server.dll` for LAN hosting.
- To build: Xcode command-line tools, Python 3, and the packages in `requirements.txt`.

European executables are no longer supported by these engines.

## Build

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./gen.sh "/path/to/game/SPEED2.EXE"
./build.sh
./link.sh
./pack.sh
```

Open `out/NFSU2.app`, choose the game folder and press Play. Both Original and HD engines are packaged. `tools/gen_v2.sh` remains an alias for the NA generator. Compilation caches objects by content; `FULL=1 ./build.sh` forces compilation.

The compiler includes x87 precision control, corrected SSE2 instructions and return handling, and optional register-local optimization (`LREGS=1 X87OPT=1 ./gen.sh ...`). Generated C, compiled binaries and game files stay under ignored paths.

## UHUD

Select **UHUD** under **Menus and HUD** in the launcher. It reads `TEXPACKS/uhud.pak` in your game folder. Alternatively use **Import UHUD Pack** to install a prepared `.pak` outside the game folder. Selecting Original restores the game's own UI textures.

The pack format is the one produced by `tools/texpacks.py` from LunicAura106's Upscaled HUD mod. A prepared pack is needed; the launcher does not install Windows ASI plugins or change original game files. Missing or rejected packs leave the original textures in use. Existing DDS replacement packs remain supported separately.

## Online play

Choose **Online**, enter a player name and press Play. The name must contain 3-15 ASCII letters, digits, `_` or `-`. The launcher starts with no name selected and never derives one from the Mac account or career profile.

Defaults, both editable in the launcher:

- Game traffic: `wss://nfsu2.xyz/lan`.
- Player and crew counts: `https://nfsu2.xyz/players`.

**Check Player Counts** contacts the selected counts endpoint only when pressed. For a different relay, edit the server URL; the counts URL follows its host until you customize it. Secure WebSocket URLs are accepted; plain WebSocket URLs are limited to loopback for local testing. System TLS certificate validation stays enabled.

The game requests a relay connection when multiplayer needs it. Free roam and the game's Online/LAN traffic share that connection. Queue tickets and resume tokens are retained across reconnects; voluntarily leaving releases the server place. Offline is the default and makes no game-network connection.

The shared multiplayer logic comes from nfsu2-web. Browser overlays such as its quick-chat picker and race-lobby panel are not reproduced as browser UI; the native runtime uses its existing in-game presentation where available.

## Saves and portable copies

- Saves: `~/Library/Application Support/NFSU2 Saves`.
- Registry: `~/.nfsu2_registry`.
- Additional runtime settings and imported packs: `~/Library/Application Support/NFSU2`.
- Logs: `~/Library/Logs/NFSU2`.

Existing saves keep their established path. The older `NFSU2 Kayitlar` folder is migrated when the destination does not yet exist. Explicit `NFSU2_SAVEDIR` and `NFSU2_REGFILE` overrides remain available for tests. Game data is read-only.

**Make Copy** builds a personal portable app with your game files, including movies and `server.dll`. Saves stay outside the app on each Mac. Do not share a portable copy containing the game.

## Verification

```sh
./run.sh test
sh tests/launcher_settings.sh
python3 tests/net/native/loopback.py
```

The native test suite covers instruction semantics, lifted functions, heap/virtual-memory behavior and free-roam/network protocol behavior. Additional focused tests live in `tests/heap_stress.c`, `tests/gamepad_harness.m`, `tests/texpack_unit.c`, `tests/texrep_native_unit.m`, `tests/shader_ps20.c` and `tests/save_paths.m`. GPU tests require a Metal device, and network tests use loopback only.

Scripted game scenarios use isolated saves and registry files through `tools/autorun.sh`. Build and runtime verification results for this upgrade are recorded in `docs/superpowers/plans/2026-10-28-native-online-uhud.md`.

## Source notices

The repository's terms remain in `LICENSE`. The imported nfsu2-web source notice is preserved in `third_party/nfsu2-web-LICENSE` and packaged with the app. UHUD and game assets are supplied separately by the player. Historical engineering notes describe earlier builds and may refer to the retired EU engine.
