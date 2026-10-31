# Fork feature tracker

What the old fork (NA-only, main at 2c92742, runtime from th0mk's nfsu2-web cc3b3df) has, and where each piece stands on this branch, which is TalhaMudo/NFSU2Recomp main (0b6896e) plus our own work.
Nothing is dropped silently: an item leaves PORT only when it is merged here, and SKIP? items wait for a decision.

Status key:
- DONE: ported and merged here (the note names the merge).
- UPSTREAM: upstream/main already does it (narrower versions are flagged).
- BRANCH: one of our PR branches covers it (gaps noted).
- PORT: only in the old fork; needs porting.
- SKIP?: plausibly not wanted natively; listed so you can decide.
- SKIP: decided not to port (the reason is in the row). Decided 2026-10-31: browser-only bits, dev/test tooling and the advanced settings.ini stay out; controller rumble is ported.

Cross-cutting notes that apply to every PORT row with runtime code:
- **NA addresses only.** The old fork hard-codes SPEED2.EXE v1.2 NA addresses (overrides `sub_00xxxxxx`, `HOOK_SITE(0x...)`, guest globals). Upstream uses European addresses as canonical, maps them with `GA()` / `runtime/build_na.h` (`tools/addrmap.py`), and has `OVR`/`OVR_NA` and `HOOKS` lists in `tools/gen_v2.sh`. Each PORT runtime item needs its EU equivalents found and its hooks/overrides added to both lists. The PR branches already did this for what they cover.
- The old fork derives the override and hook lists from the runtime sources (`gen.sh` + `tools/genstamp.sh`). Upstream lists them by hand in `tools/gen_v2.sh`, so each port must add its entries there.
- fork-next already carries `2081e96` (MMX conversions re-added after reverting lifter-missing-insns), `60c03ae` (frame pacer owns upstream's high-FPS tick/smoke/trail fixes), `536f632` (server.dll lifted without xpatch sites) and `c2b118e` (intro choice through BOOTMOVIES).
- Some branches exist with no commits beyond d2eaaa3: `photo-mode`, `drift-mode`, `music-folder`, `display-options`. `quick-chat` points at the same commit as `free-roam` (no chat code). `hud-modes` has one commit (`27e1111`, Full width HUD mode). Nothing in those branches covers the rows below unless a row says so.

## Engine / compiler

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Lifter: fsincos, fxam, fcmov, xlat, stmxcsr/MXCSR | Game code that uses these instructions runs correctly instead of trapping | UPSTREAM | upstream 88d67a2; branch lifter-missing-insns | MMX conversions (cvtpi2pd, cvtps2pi, cvttps2pi, cvtpd2pi, cvttpd2pi) are missing upstream. fork-next 2081e96 re-adds them. |
| Lifter: MMX conversions | Same, for the MMX/SSE conversion instructions | BRANCH | lifter-missing-insns; fork-next 2081e96 | Done in fork-next. |
| x87: two NaN operands give the larger significand | Bit-exact FPU results | UPSTREAM | upstream 88d67a2; branch x87-nan | - |
| x87 precision control (X87PC, round to control word precision, PC=24 like Windows) | Physics and timing math matches the PC game | BRANCH | x87-precision (5cdf0fd) | Old fork has X87PC=1 by default in gen.sh. Check that upstream's gen_v2.sh turns it on. |
| SSE2 packs, unpacks and shifts on all 128 bits | Correct SSE2 results | BRANCH | lifter-sse2-128 (cd083e9) | - |
| Return with a callee that returns past its caller (tools/retpast.txt) | No wrong control flow or crashes in those call chains | BRANCH | lifter-retpast (65e50a4) | - |
| LREGS: register-local lifting (tools/lregs.py, LREGS=1) | Possible speed-up: registers and flags kept in C locals | PORT | old tools/lregs.py (169), tools/lift.py, tools/genall.py, runtime/cpu.h RG_ macros, tools/isatest.py | Optional; off by default; the old fork claims no measured gain. About 400 lines. Must be rebased onto upstream's v2 lifter (FLAGABI/X87OPT/MEMARG). |
| X87OPT in-block x87 register allocation | Speed | UPSTREAM | upstream tools/lift.py, gen_v2.sh (on by default in v2) | Upstream turns it on by default; in the old fork it is optional. |
| JTSWITCH (jump tables lifted as switch) | Speed (fewer dispatcher tail calls) | PORT | old tools/lift.py, tools/genall.py, gen.sh | Optional; not on by default in the old fork. |
| INLINE / INLINE_LIST hot leaf inlining (tools/inline_hot.txt, tools/inline_pick.py) | Speed | PORT | old tools/genall.py, tools/inline_pick.py, tools/inline_hot.txt (EU list needed) | Optional. The hot list holds NA addresses. |
| FTOL2INL (CRT _ftol2 inlined) | Speed (the hottest lifted function) | PORT | old tools/lift.py, runtime/cpu.h FTOL2_INL | Optional. |
| NOCLOSURE / generated-closure handling in genall | Lifter robustness (missing callees pulled in) | PORT | old tools/genall.py | Small; check against upstream LIFT_MISSING. |
| Override and hook lists derived from the runtime sources (gen.sh + tools/genstamp.sh, gen/all/stamp.txt) | A built game never lacks an override or hook (no list drift) | PORT | old gen.sh, tools/genstamp.sh | Build tooling. Upstream keeps hand-written OVR/OVR_NA/HOOKS in tools/gen_v2.sh. |
| Content-hash object cache in build.sh (FULL=1 forces) | Faster rebuilds for developers | SKIP | old build.sh | Developer convenience only. |
| Guest heap: TLSF heaps, VA manager (VirtualAlloc reserve/commit/decommit/release, VirtualQuery, VirtualProtect), real HeapCreate heaps, NFSU2_HEAPCHECK canaries/stats | Long careers do not run out of memory; heap corruption is caught | DONE | upstream gheap.c + #7 733a3e4 (free lists, coalescing, quarantine, buffer heap reuse); old runtime/heap.c (1008) | Upstream is narrower: one bump-style arena with free lists. It has no VA region manager, VirtualQuery or VirtualProtect, and HeapCreate returns a fixed handle. It has no HEAPCHECK trailer canaries or per-site stats, and no heap_stress test. Port heap.c only if long-session problems show up. Done in fbcb7db (fp/engine): measured (upstream does not leak in races), then VA regions with commit/decommit/release, VirtualQuery, VirtualProtect and NFSU2_HEAPCHECK added to gheap.c; real HeapCreate heaps not needed (one CRT heap). |
| server.dll heaps (modheap.c) | Hosting LAN games many times does not exhaust memory | BRANCH | lan-play (runtime/modheap.c) | - |
| Second guest module loader (server.dll lifted at 0x00A00000, SHA-256 pinned) | LAN hosting through EA's own server works | BRANCH | lan-play (module.c, module.h, tools/prepare_module.py, gen_v2.sh); fork-next 536f632 | module.c has 64 more lines in the old fork. The extras are host start/stop cycle tests and srvoracle hooks. |
| Waits: semaphore counts, mutex ownership, INFINITE/long waits, wait-all | No hangs or early wake-ups in threads | UPSTREAM | upstream #14 981a260, #7; old c47f2c3 | tests/windows_waits.sh is only in the old fork (see Tools/tests). |
| Thread stacks recycled, TerminateThread really ends a thread | Long sessions keep their stack slots | UPSTREAM | upstream #7 | Old fork also has NFSU2_THREAD_EXIT=windows (opt-in real exit codes). See the HLE refinements row. |
| Kernel object table reuse (obj_reclaim, closed handles reused) | Handles do not run out in very long sessions | DONE | old runtime/win32_ext.c (obj_reclaim, g_free), tests/objtable_unit.c | Small-medium. Check upstream's object table size and leak behaviour first. Done in fbcb7db (fp/engine): handle reuse, TEB recycling, ended threads' CPUs unregistered. |
| Fair GIL: ticket lock + 2 ms keep window (NFSU2_GIL_KEEP_MS) | Loader and sound threads are not starved: fewer hitches and stalls | DONE | old runtime/win32_ext.c (gil_acquire, ticket_*), runtime/web/ticketlock.h (82) | Medium, with risk (core scheduling). Measured: loader waits went from p99 262 ms to near the old hand-over. Done in fbcb7db (fp/engine) as an option (NFSU2_GIL=ticket, NFSU2_GIL_KEEP_MS): measured mixed results, so the mutex stays the default. |
| guest_noyield: music event tick keeps the GIL | Fixes music staying silent after entering a shop | DONE | old overrides.c sub_0073b900 + win32_ext.c guest_noyield | Small. NA 0x73b900 -> EU address needed. Listed under Audio as well. Done in 3491b42 (fp/music); the bug does not show with fork-next's plain mutex, it matters with a fair GIL. |
| Precise pacer sleep with halving (NFSU2_PACE_HALVE, NFSU2_PACE_SPIN) | Steadier frame pacing | BRANCH | frame-rate (framerate.c); old win32_ext.c sleep_precise_ns | The halving and probe logic in win32_ext.c are not in preview-old. Upstream has a simpler sleep_precise. fp/engine: the halving/spin pacer was wasm-only in the old fork; nothing to port. Uncapped mode, LAN timing and the online frame-cap fix are done (fbcb7db). |
| Stall watchdog (NFSU2_WATCHDOG, per-thread state report) | A hang can be diagnosed from the log | DONE | old runtime/watchdog.c (156), win32.c hooks, bundle.m key, tests/watchdog_unit.c | Small. Upstream's "watchdog" is only the system-shortcut re-enabler. Done in fbcb7db (fp/engine): on by default (15 s), log only. |
| Lifecycle: Cmd-Q/close/Dock quit as WM_CLOSE through the game's own shutdown, a second request or a grace timeout (NFSU2_QUIT_GRACE) forces exit, waits for save files still being written | Quitting never cuts a save in half | PORT | old runtime/lifecycle.c (248), metal.m delegate | Upstream sets g_should_quit and ends the draw loop (no WM_CLOSE, no write drain). Medium. Same work as the display-options "Cmd-Q as WM_CLOSE" item. |
| Lifecycle: WM_ACTIVATE/ACTIVATEAPP/KILLFOCUS on Cmd-Tab; background pause or run (NFSU2_BACKGROUND) | The game pauses when you switch apps (or keeps running for online races) | PORT | old runtime/lifecycle.c, gamepad.m NFSU2_PAD_BACKGROUND, launcher RuntimeOptions "While another app is active" | Upstream only sends activation at window creation. |
| JDLZ native decompressor (sub_00574670) | Faster loading | DONE | old overrides.c (~60 lines), NFSU2_JDLZ_VERIFY | Small. NA address. Done in fbcb7db (fp/engine) (EU 0x574680). |
| Car part lookup memo (sub_0061b980) | Faster car/part screens and loads | DONE | old overrides.c (~50 lines), NFSU2_PARTMEMO | Small. NA address. Done in fbcb7db (fp/engine) (EU 0x61b990). |
| D3DX effect Stage 9 (pass applied again with nothing changed is skipped) + shared-texture refcount fix in effects | Less CPU per frame; no use-after-free on Reset | DONE | old runtime/d3dx_hle.c (Stage 9, NFSU2_COMFREE section) | Upstream d3dx_hle.c has stages 0-4. Small-medium. Done in fbcb7db (fp/engine): Stage 9 skip with verify mode; the refcount fix already existed upstream (com_tex_ref_skipped). |
| COM object lifetime: every object (incl. Lock buffers, Metal textures) destroyed on last Release | Lower memory in long sessions | UPSTREAM | upstream #7 (VB/IB/texture buffers freed on last Release, 65536 texture ids) | Upstream is narrower: buffer data only, not every interface's object. Old: com.c CH_REF section + metal.m texture lifetime. |
| Save-overlay lookup cache (fileio.c overlay_cannot_have) | Saves ~1.5 ms per missing-file lookup (no 120 Hz slot misses) | DONE | old runtime/fileio.c | Small perf item. Upstream has the write root itself. Done in fbcb7db (fp/engine). |
| Win32/COM HLE refinements: GetTimeZoneInformation with DST dates, wsprintf formats, IsProcessorFeaturePresent real answers, RaiseException stops loudly, optional Windows thread-exit semantics | Correctness and clearer crash reports | DONE | old runtime/win32.c, win32_ext.c | Small each. Upstream fills the time zone Bias only, answers 1 to every IsProcessorFeaturePresent and returns silently from RaiseException. Done in fbcb7db (fp/engine) (hlefix.c), plus GetDiskFreeSpace(Ex)A, Paint calls, thread priority and an atomic registry save. |
| rdtsc/QPC tied to a 3 GHz clock; CPU MHz registry value | The first run detects the right graphics level; movies do not spin | UPSTREAM | upstream dispatch.c rdtsc_shim, c0806af, win32_ext.c repair | - |
| GPU reported as GeForce 6800 | The game picks its full effect path | UPSTREAM | upstream com.c (0x10DE/0x0040) | Old fork adds NFSU2_GPU_VENDOR/DEVICE overrides (test only). |
| Dispatch: direct function table, generated-code execution (genexec) | Speed; game-generated x86 runs | UPSTREAM | upstream dispatch.c, genexec.c, xpatch.c (#9) | Equivalent. |
| wasm-only native fast paths (_ftol2, shadow hull qsort, shrot, mmul, xform/frustum cull) | Speed in the browser only; the Mac keeps the lifted bodies | SKIP | old overrides.c `#ifdef __wasm__` blocks | Browser-only. |
| Web build plumbing (runtime/web/*.h, compat headers, WGSL shader paths, NFSU2_GUEST_OBJ/MEMCHECK/STACKPROBE) | None natively | SKIP | old runtime/web/* | Some headers are native dependencies of PORT items: radio_proto.h (music folder), ticketlock.h (fair GIL), status_proto.h/host_abi.h (photo/drift status), photo_icon.h. lan-play already brought lan_vfd.h/net_proto.h. |
| Licence notice of nfsu2-web packaged in the app (third_party/nfsu2-web-LICENSE) | Legal compliance for MIT code | SKIP | old third_party/nfsu2-web-LICENSE, pack.sh line 97 | Decided: nfsu2-web (MIT) is credited in the README and in the ported files' headers; no licence file is added. |

## Graphics / display

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Hor+ FOV in the game's projection setup (culling matches the screen) | No edge pop-in on wide screens | UPSTREAM | upstream wsfov.c (1287e46 #6) | - |
| HUD markers over world positions placed for wide screens | Markers line up with cars and places | UPSTREAM | upstream wsfov.c (0x4ec35c) | - |
| HUD placement: wide (edge-anchored) or original 4:3 | HUD at the screen edges on wide displays | UPSTREAM | upstream 67bcbbd/f6d410c (HUDPOS, launcher "HUD at the screen edges"); branch hud-modes 27e1111 (Full width) | Different mechanism: upstream groups HUD draws; the old fork used WidescreenFix .dat hook sites (radar blips, stop sign, FEng traversal). Same player result. |
| Cutscene letterbox bars across the full width / bars off | No 4:3 gap beside bars; optional no bars | UPSTREAM | upstream com.c HUDWIDE (full-width bars), highfps.c borders (DisableCutsceneBorders via ini); branch frame-rate (NFSU2_CUTSCENE_BORDERS in wsfov.c + launcher) | Old: widescreen.c NFSU2_CUTSCENE_BORDERS full/off. |
| Lens rain drops keep their 4:3 shape | Rain drops not stretched on wide screens | PORT | old widescreen.c HOOK_SITE 0x5c7ce9 | Small. NA address. |
| Rain/overcast full-screen tint quads cover the whole screen (sub_005c7140) | No untinted strips at the sides in rain | PORT | old widescreen.c fill override | Small. NA address. |
| FMV framing: fit (pillarbox) / fill / stretch | Movies shown the way you like on wide screens | PORT | old widescreen.c HOOK_SITE 0x536a32, launcher "Movie framing" | Small. Part of "display options". |
| Resolution scale 50/75/100/150/200% (NFSU2_RENDER backing/panel/scale:f) | Trade sharpness for speed, or supersample | PORT | old widescreen.c ws_render_factor, com.c res_pick, metal.m, launcher "Resolution scale" | Small-medium. Upstream has NFSRES/NFSNATIVE/NFSMAXPIX only. |
| Graphics options in the normal engine (NFSU2_GRAPHICS original/enhanced/custom, MSAA, high-res mirror, 16x AF) | Better image without the HD engine | UPSTREAM | upstream HD engine (enhance.c, HD_MSAA/HD_MIRROR); branches visual-options, hd-reflections add more | Upstream is narrower: these exist only in the HD build and only as HD_* variables, with no choice per option in the Original engine. In the old fork they were reachable only through settings.ini, not the launcher. Probably fine to drop. |
| ps_2_0 texture coordinates from interpolants, colour saturate | Correct pixel shading | UPSTREAM | upstream fc09c02, vsemu.c | tests/shader_ps20.c is only in the old fork. |
| Magazine and DVD cover photo read back from the GPU | Covers are not black | UPSTREAM | upstream 43200c7 | The old fork had its own version (com.c "cover shoot"). Covered. |
| Car shadow lifted off the tyres | No shadow edge inside the wheels | UPSTREAM | upstream 3391943; branch car-shadow | - |
| Other cars' headlights light the road (players/all/off), native Metal shader path | Night driving with friends and AI looks right | BRANCH | other-headlights (headlights.c, metal.m, vsemu.c, launcher) | tests/headlights_* are only in the old fork. |
| On-screen FPS counter (off/on/detailed, Cmd-N) | See frame rate, frame times, GPU time | BRANCH | fps-counter | The menu title in the branch is Turkish ("Kare Hizini Goster"); the old fork has "Show Frame Rate". |
| UHUD (LunicAura106's Upscaled HUD) .pak with original guest dimensions | Sharp menus and HUD | BRANCH | uhud (one-click download/build, UHUDPack.swift), texture-packs (generic NTXP import) | Better than old: no manual tools/texpacks.py step. |
| DDS replacement packs + AI upscaled texture pack (tools/texpack: scan, upscale with PBRify SPAN, back-project, BC encode, stacked mips, categories, GPU budget, texture dump) | Sharper world/car/sign textures from your own files | PORT | old runtime/texrep.m DDS path (NFSU2_TEXTURES/TEXPACK/TEXPARTS/TEXBUDGET/TEXDUMP), runtime/xxhash.h, tools/texpack/* (968-line builder, hashed venv, model download) | Large. Settings.ini only in the old fork (no launcher control). texture-packs' texrep.m (339 lines) handles TexMod/TexWizard/NTXP, not this. Per the player-ease rule the launcher would have to build the pack itself (0.8 GB PyTorch venv), so this may be better left out. |
| English app menu titles (Hide, Minimise, Full Screen, Quit) | Readable menu for English players | PORT | old metal.m app menu | Tiny. Upstream menus are Turkish ("Gizle", "Kucult", "Tam Ekran", "NFSU2'den Cik"). |
| Frame dumps (NFSU2_DUMP_FRAMES/DIR/SCALE) for scripted runs | None (test aid) | SKIP | old metal.m, autotest.c | Test tooling; only needed with the scripted scenarios. |
| Phone touch button sizing (menusize.c, NFSU2_MENU_SCALE) | Bigger help-bar buttons on phones | SKIP | old runtime/menusize.c | Browser/phone only. |

## Input

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Mac keyboard as Windows delivers it: layout-aware VK codes, WM_CHAR in cp1252, dead keys (WM_DEADCHAR + composition), Option = Alt (WM_SYSKEYDOWN), Option+key as AltGr, command shortcuts kept out of the game | Typing names and passwords works on every keyboard layout; Alt combos work | PORT | old runtime/keyboard_mac.m (681), keyboard.c (151), kbd.h, metal.m event routing | Upstream has a fixed macOS keycode -> DIK table and simple char push in metal.m. Large: replaces upstream's keyboard path. |
| DirectInput buffered key event ring (presses between polls are not lost) | Quick taps always register | PORT | old runtime/keyboard.c, dinput_kbd.c | Upstream compares key state per poll (g_kb_prev in com.c). |
| Keyboard rebinding on the Controls page works (correct dwOfs per data format, GetObjectInfo, chosen dwObjID honoured) | You can rebind keys in the game's own menu | PORT | old runtime/dinput_kbd.c (479) | Upstream's SetActionMap maps by semantic and ignores the chosen key. tests/scripts/kb_rebind_* guard it. NA addresses in comments only; device code is address-free. |
| Saved keyboard bindings (DIMap.* entries in the registry file, DIDSAM_FORCESAVE) | Rebinds survive restarts | PORT | old dinput_kbd.c + win32_ext.c reg_get/set_str helpers | Depends on the rebinding row. |
| Mac key names on the Controls page (Option, Clear, Help; layout key names via kbdmac_layout_name) | Bindings show the keys you actually press | PORT | old runtime/dikeys.c (47), keyboard_mac.m | Small, depends on dinput_kbd.c. |
| Game controller basic support (GameController -> DirectInput pad, hotplug pick, stick dead zone) | Xbox/PS/MFi pads work | UPSTREAM | upstream gamepad.m (#8 6f109bc), com.c pad device, launcher #16 4359d1a; branch launcher-controller | Narrower than the old fork; see the next rows. |
| Pad: separate trigger axes (Z / Rz) + trigger click buttons 10/11 (NFSU2_PAD_TRIGGER_CLICK), trigger dead zone | Triggers can be bound separately; full-press works like on PC | PORT | old runtime/dinput_pad.c (1138), gamepad.m (235), gamepad.h | Upstream combines LT/RT into one Z axis. Large (replaces the upstream pad device). |
| Pad: stable instance GUID + own entry in the game's profile lookup (sub_005b81b0); bindings persist and survive unplugging; Joypad page binding crash fix (0x4f9340) | Pad bindings are kept between sessions; no crash when editing them | PORT | old dinput_pad.c | NA addresses (0x5b81b0, 0x4f9340 and others). |
| Pad: hotplug mode (NFSU2_PAD=hotplug, real DIERR_INPUTLOST + the game's 32-frame rescan) vs stay-present default | Choose PC-faithful hotplug or never lose the pad | PORT | old dinput_pad.c, launcher Controller picker on/off/hotplug | Upstream launcher has on/off only. |
| Pad: left stick as POV 1 for menus; A/B/View post Enter/Esc/Q in menus (NFSU2_PAD_FE_KEYS) | Menus fully drivable with a pad | PORT | old dinput_pad.c fe_keys | Small within the pad port. |
| Pad: keep reading in background (NFSU2_PAD_BACKGROUND), controller quarantine on focus change | No stuck input after Cmd-Tab | PORT | old gamepad.m, native_scene.m | Part of the pad/lifecycle port. |
| Force feedback mixer (DirectInput effects -> two motor levels) | Rumble (browser only today; Mac gamepad.m has no motor output) | PORT | old dinput_pad.c ff_mix, NFSU2_FF | Decided: port it, and drive the Mac controller's motors natively (GameController haptics), which the old fork never did. Package K. |
| Steering wheel as a driving device | Wheel steering in the browser | SKIP | old dinput_pad.c wheel profile | Browser-only (web/src/input/wheel.ts). Backlog item 8. |
| Tuning graphs: drag the dots with the mouse | ECU/turbo tuning by mouse | UPSTREAM | upstream 44cf882; branch tuning-graph-drag | - |
| Sponsor screens take a click to continue | Career not stuck on the sponsor choice | UPSTREAM | upstream 3391943; branch sponsor-continue | - |
| Lobby dialog click does not also click the game list | Join goes to the selected game | BRANCH | lan-play (lobbyclick.c) | - |

## Audio / music

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| CoreAudio low-latency AudioUnit output, SetFrequency, DuplicateSoundBuffer | Sound with no extra latency | UPSTREAM | upstream audio.m | - |
| Follow default output device changes (headphones, AirPods), rebuild the unit, silent clock fallback | Sound moves to new headphones without restarting | DONE | old runtime/audio.m "default output device changes" section, NFSU2_AUDIO_FAIL_REBUILD | Small-medium. Done in fbcb7db (fp/engine); not tested with a real headphone switch. |
| Sound catch-up window after loads | Sound back in sync within seconds after a load | UPSTREAM | upstream #23 d2eaaa3 (sndlead.c) | - |
| Music stays playing after entering a shop (event tick keeps the GIL) | Fixes music staying silent after shops until restart | DONE | old overrides.c sub_0073b900 + guest_noyield | Small. NA address -> EU. Same row as in Engine. Done in 3491b42 (fp/music), see the Engine row. |
| Positional sound source removal recounts requests (sub_00483e40) | No crash when many cars use every voice and a jump frees them | DONE | old overrides.c sub_00483e40 | Small. Triggered mostly with 32 friends' cars (free roam), but it is a general game bug. NA address. Done in fbcb7db (fp/engine). |
| Local music folder through EA Trax (radio.c + radio_native.m): system decoders, resampling, tags on the plaque, skips unsupported tracks | Play your own music in the game | DONE | old runtime/radio.c (480), radio_native.m (328), radio_native.h, web/radio_proto.h, audio.m mixer hooks, launcher Music folder | Medium (~900 lines). NA addresses in radio.c. Needs the launcher control (Settings window). Done in 3491b42 (fp/music): EU and NA; also fixes swapped left/right channels. |
| Music controls: Pause/Resume, Next, Shuffle, switch back to the game soundtrack (Game Tools, Cmd+Shift+M) | Control your music in game | DONE | old native_controls.m music section, radio_native.m | Depends on the music folder and Game Tools rows. Done in 3491b42 (fp/music) as an app menu; the Game Tools panel section comes with package F. |
| Horns (8 kinds), horn key, horn volume slider in Options > Audio | Honk at other players | BRANCH | player-horns (horn.c, hornmenu.c, racehorn.c) | - |
| Friends' engines, nitrous and hydraulics heard | Hear other players' cars | BRANCH | player-horns (carsfx.c) | - |
| Muted test runs (NFSU2_MUTE) | None (test aid) | SKIP | old audio.m | Test tooling. |
| Smaller music files (tools/musicpack.py, ADPCM -> EALayer3) | Smaller download in the browser | SKIP | old tools/musicpack.py | Web hosting only. |

## Movies

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Native VP6 movie playback | Story movies play | UPSTREAM | upstream c0806af (movies on by default, CPU MHz answer) | - |
| Boot movies skippable / original / off | Skip the logos and the intro | UPSTREAM | upstream cf77de4 (BOOTMOVIES); fork-next c2b118e keeps our launcher choice through BOOTMOVIES; branch skippable-intro | - |
| Movie subtitles (NFSU2_SUBTITLES, language_hook at 0x553a62; shows SUBTITLES/<movie> regardless of region) + English subtitle pack (VileStuff's fixed subtitles via LANGPACKS/english) | Subtitles in movies, also in English | PORT | old runtime/language.c (subtitle part), tools/langpacks.py --subs, launcher "Movie subtitles" | Small runtime part; the pack needs building (see Career/language row). NA address 0x553a62. |
| FMV framing fit/fill/stretch | See Graphics | PORT | old widescreen.c | Listed under Graphics. |
| 60 FPS race intros and cutscenes (NFSU2_CUTSCENES_60) | Smoother cutscenes | BRANCH | frame-rate (framerate.c + launcher); upstream highfps.c intro60 (ini HighFPSCutscenes) | fork-next 60c03ae reconciles the two. |
| Portable copies keep the movies | Movies in a Make Copy app | UPSTREAM | upstream #33 47e1cd3; branch portable-movies | - |
| AV1 movies (movie.c, tools/movies_av1.py) | Smaller movie download in the browser | SKIP | old runtime/movie.c, tools/movies_av1.py | On the Mac the decoder stubs return -1. Browser only. |

## Online / multiplayer

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| LAN play on the real network with Windows semantics (winsock.c, Netbios) | Race PCs and Macs on a LAN | BRANCH | lan-play (winsock.c, winsock.h) | In lan-play, Offline means LAN on the Mac's network; the old fork's offline was NFSU2_NET=off. |
| LAN hosting via EA's server.dll | Host LAN games | BRANCH | lan-play (module.c, modheap.c) | - |
| Online/LAN through the WebSocket relay (net_native.m, net_relay.c), configurable server, explicit player name | Play online with browser and native players | BRANCH | lan-play | - |
| Queue tickets and resume tokens across reconnects; voluntary leave releases the place | Keep your place in a full server | BRANCH | lan-play net_native.m (queue/resume, ticket) | 9 lines differ from the old fork. |
| Player and crew counts check (Check Player Counts, counts URL follows the server host) | See how many are online before joining | PORT | old launcher/Settings.swift (PlayerCounts, countsURL), Model.swift refreshCounts, Views | Small (~80 lines Swift). No network request until pressed. |
| Online menu logs in under the player's name (no EA login screens) | Straight into Online | BRANCH | lan-play (online.c) | - |
| Online lobby Filter actually narrows the list | Filters work | BRANCH | lan-play (olfilter.c) | - |
| Network races: every track, 2 laps default, 6 players, drift from 2 laps | Better online races | BRANCH | lan-play (netrace.c) | - |
| Race link report at the end of a race (racenet.c) | Diagnoses rubber-banding reports | BRANCH | lan-play (racenet.c) | - |
| Test-harness network guard (nettest.h, loopback-only) | Tests never touch the real network | BRANCH | lan-play (nettest.h) | tests/net/loopback-only.sb and run_suite are only in the old fork. |
| Virtual LAN backend + hub (net_vlan.c, tools/vlanhub.py) for several instances on one Mac | None directly (lets several local instances race for tests) | BRANCH | lan-play (net_vlan.c) | tools/vlanhub.py (841) is not in any branch; see Tools/tests. |
| Free roam with other players (roam_core/roam_bsd/roam_game, car looks, interpolation, minimap) | See and drive with friends in career free roam | BRANCH | free-roam | roam_game.c is 1150 lines shorter than the old fork; the rows below cover what is missing. |
| Multiplayer race started from free roam and back (mprace.c, prize to bank, quit fee) | Race friends from race markers | BRANCH | free-roam (mprace.c) | - |
| Free-roam room filter | Only players in your room see you | BRANCH | free-roam (NFSU2_ROAM_ROOM, launcher Room) | Narrower: ASCII, 24 chars. The old fork takes UTF-8 up to 63 bytes and runs the launcher check through the runtime's C name_blocked() (7892f5d, 18fdb89). |
| Crews: up to four named crews with colour pickers | Crew names/arrows in your colours | BRANCH | free-roam (NFSU2_ROAM_CREW/CREW_RGB in runtime, single "Crew" field in launcher) | Gap: the old fork edits 4 crews and colours live in Game Tools (native_controls_set_crews). |
| Solid / ghost cars | Choose to collide or drive through | BRANCH | free-roam (launcher Solid/Ghost) | Gap: the live toggle in Game Tools (solid_follow) is PORT with Game Tools. |
| Slur filter for names and rooms (names.h) | No offensive names shown | BRANCH | free-roam (names.h) | - |
| Game Tools panel (Cmd+Shift+M): free-roam race lobby (Open/Join/Start/Leave), players list, countdown, nearby notices | See and manage the free-roam lobby without the race-marker prompts | PORT | old runtime/native_controls.m (718), native_controls.h, roam_game.c js_*/mp_panel/roam_game_native_leave, roam_bsd.c callbacks, metal.m menu/event hooks | Medium-large. Needs free-roam. NA addresses inside the roam_game additions. |
| Quick chat: 152 donor phrases, solid/ghost and crews in the panel | Talk to nearby players | PORT | old native_controls.m, roam_game.c say_* (say_send/recv/burst/frame/page), roam_core say capability | Needs free-roam. Phrase IDs must match nfsu2-web. |
| Quick chat groups (4 named groups x 4 phrases), keys 1-4 twice or right stick twice, timeout/cancel on focus loss | Fast chat while driving | PORT | old native_controls.m (set_chat_layout, handle_event, filter_pad), tests/native_quickchat_test.m | Needs Game Tools + pad filter. |
| Chat bubbles above nearby cars | See who said what | PORT | old native_controls_say_marks, roam_game.c positions | Needs Game Tools. |
| World map: 1024 FEng nodes per package (shop/event icons kept with many player markers) | Map icons do not vanish with many players | PORT | old overrides.c sub_0050b410 (FE_NODES), roam_host.h RH_FE_NODES=1024 | free-roam has RH_FE_NODES 512 and no override. Small. NA address. |
| Car loader: a read in progress finishes before part animations load (sub_0061c600) | No load hang while friends' cars load | PORT | old overrides.c | Small. NA address. |
| Ride texture references kept when a purge frees nothing (sub_00639f20) | No "memory access out of bounds" crash with friends' cars coming and going | PORT | old overrides.c | Small. NA address. |
| Ride texture list capped at 0x45 (sub_00631e20) | No freeze with decal-heavy friends' cars | PORT | old overrides.c | Small. NA address. |
| Discord Rich Presence (off by default) | Show what you are doing in Discord | BRANCH | discord-presence | Missing NFSU2_DISCORD_LARGE_IMAGE (custom image) option; tests/discord_* and tools/mock_discord.py are only in the old fork. |
| Windows companion plugin interop tooling (roam_asipeer.c, NFSU2FreeRoam.asi under Unicorn, asi_* tests) | None for Mac players | SKIP | old runtime/roam_asipeer.c, tests/asi_*.c, tools/asi_check.py, build_roam_asi.sh, roam_asi_test.sh, roam_x86check.sh, roam_fingerprint.py, roam_modsites.py | Test-only; the plugin source is not in this repo. |
| Free-roam research probes (roam.c) | None | SKIP | old runtime/roam.c (983) | Test-only probes. |
| World map jump table for the server's cheat watch (tools/map_jumps.py) | Server-side anti-cheat data | SKIP | old tools/map_jumps.py | Server tooling. |

## Career / saves

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Save manager: list careers, backup, export ZIP, import/restore with validation and pre-restore ZIP | Safe backups and transfers | UPSTREAM | upstream #15 6903fa5 (SaveArchive/SaveStore/SaveViews); branch launcher-save-manager | SaveArchive.swift is identical. |
| Save paths: NFSU2 Saves, ~/.nfsu2_registry, NFSU2 Kayitlar migration, NFSU2_SAVEDIR/REGFILE overrides | Existing saves keep working | UPSTREAM | upstream bundle.m, fileio.c write root | tests/save_paths.m is only in the old fork. |
| Encrypted cloud saves (Vault): 8-word keyphrase, PBKDF2/AES-GCM browser format, 256 KiB limit, manual check/send/download, keep both, ETag conflicts, optional Keychain | Move careers between Mac and browser | PORT | old launcher/VaultAPI.swift (119), VaultCrypto.swift (89), VaultPayload.swift (34), VaultViews.swift (149), VaultWords.swift (97); tests/vault.sh, vault*.swift/.mjs/.py | Medium (~490 Swift + tests). Depends on SaveStore (upstream) and the server URL (lan-play). Vault URL default /vault on the game server. |
| Garage slots 6-10 and Trade Car (80% refund, text shown right) | Ten-car career garage | BRANCH | garage-slots (includes the 2c92742 "80%" fix) | - |
| Power Units (bhp or kW) | Power in your unit | BRANCH | power-units | - |
| Both regions' cars (Corsa, 106 in NA; Civic/RSX in EU) | More cars | BRANCH | all-region-cars (regional.c) | - |
| Car lot crash fix: invalid stock-car index rebuilt (sub_004df9c0/sub_00516500) | You can open the car lot on damaged profiles | DONE | old overrides.c | Small. NA addresses. Guarded by tests/scripts/career_lot_badstock.txt. Done in fbcb7db (fp/engine). |
| Performance Shop dead-screen fix (sub_00559c90 initialises +0xC0) | Shop does not lock up after Nitrous | DONE | old overrides.c | Small. NA address. Done in fbcb7db (fp/engine) (EU 0x559ca0), reproduced and fixed on EU and NA. |
| Language choice (16 languages, LANGPACKS, Thai/CJK font pool fix) | Play in your language | BRANCH | language-choice (language.c 125 lines vs old 307) | Gaps: movie subtitles (Movies table), the injected own texts table (used by sms.c and the roam race questions; free-roam has its own roam_add_text), and accented-letter handling for Polish/Turkish packs. |
| Language pack builder (tools/langpacks.py: Multi13, PT-BR, PL, TR, English subtitles) | Get the extra languages | PORT | old tools/langpacks.py (386) | Per the player-ease rule the launcher should fetch and build these with pinned SHA-256 instead of a script. Medium. |
| Registry seeded with the highest graphics settings on first launch (app/registry-defaults.txt, NFSU2_SEED_REGISTRY) | Best graphics without the first-run hardware check | DONE | old app/registry-defaults.txt, bundle.m app_seed_registry | Small. Upstream repairs the first-run detection instead (PortSettingsRepaired); decide whether you still want the seed. Done in fbcb7db (fp/engine): off by default (launcher Graphics tab), never fights upstream's first-run repair. |
| Advanced settings file (settings.ini mapped to env with typed validation, template on first run) | Power users can set any option without the launcher | SKIP | old runtime/bundle.m g_keys/k_template (~300 lines) | Upstream and the launcher pass env directly; the Settings window replaces most of it. |
| In-game SMS from us (sms.c, after 2 hours of play) | A message on the game's phone | SKIP | old runtime/sms.c | Triggered by the browser page (IEV_SMS); natively only NFSU2_SMS for tests. |
| Career test aids (career.c bot, race wins, teleports) | None | SKIP | old runtime/career.c (1143), tools/career_report.py, career_segments.sh | Test-only. |

## Launcher

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Engine Original/HD, start full screen, show at startup, Reset Graphics, Logs, Report a Problem | Basic launcher | UPSTREAM | upstream launcher (Views.swift, Game.swift) | - |
| Settings window with tabs | Options in one place | UPSTREAM | upstream #40 0b6896e; branch launcher-settings | New home for every PORT control below. Per the launcher-optional-features rule, each one marks the original-game value. |
| Offline/Online, WebSocket server URL, player name (never from Mac account), validation | Set up online play | BRANCH | lan-play | - |
| Player and crew counts | See Online rows | PORT | old Settings.swift PlayerCounts | Listed under Online. |
| Menus and HUD: Original/UHUD, import a prepared .pak | Sharper UI | BRANCH | uhud, texture-packs | Branch downloads and builds the pack in one click. |
| Language picker with installed-language detection | Choose a language | BRANCH | language-choice | - |
| Frame rate (auto/30/60/120/240) and 60 FPS cutscenes | Choose smoothness | BRANCH | frame-rate | - |
| Controller on/off/hotplug, stick and trigger dead zones | Tune your pad | UPSTREAM | upstream #16 (on/off, stick dead zone); branch launcher-controller | Narrower: hotplug mode and trigger dead zone are PORT (they need the old pad runtime). |
| Music: game soundtrack / music folder chooser | Use your music | DONE | old launcher/RuntimeOptions.swift, RuntimeViews.swift | Needs the music folder runtime. Done in 3491b42 (fp/music): Music card on the Game tab. |
| Display and gameplay: resolution scale, race HUD, movie subtitles, movie framing, cutscene bars, other cars' headlights, while another app is active | One place for display options | PORT | old launcher/RuntimeOptions.swift (126), RuntimeViews.swift (102), tests/runtime_options.* | Partly covered: HUD (upstream), cutscene bars (frame-rate), headlights (other-headlights). Still to port: resolution scale, subtitles, movie framing, background. |
| Free-roam room with UTF-8 and runtime name check | See Online | BRANCH | free-roam | Narrower; see Online row. |
| Screenshots gallery (thumbnails, preview, reveal/export, confirmed delete, symlink/hardlink/oversize rejection) | Browse your photos | PORT | old launcher/PhotoGallery.swift (273), tests/photo_gallery*.swift/.sh | Small-medium. Needs photo mode. |
| Manage Saves | See Career | UPSTREAM | upstream #15 | - |
| Cloud section in the save window | See Career | PORT | old Vault*.swift | Listed under Career. |
| Make Copy keeps movies and server.dll | Portable app works fully | UPSTREAM | upstream #33 (movies); lan-play 0eb8f12 (server.dll) | Check that an imported UHUD pack outside the game folder is also copied (the old fork copied the game folder only). |
| App icon traced from SPEED2.EXE to vectors | Sharp icon | UPSTREAM | upstream #21 c9e2bc5; branch app-icon-from-exe | - |
| Launcher validation tests (launcher_settings, runtime_options: defaults, persistence, invalid values, stale env cleared) | Fewer broken launches | PORT | old tests/launcher_settings.*, tests/runtime_options.* | Write them against the new Settings model. |

## Photo / drift

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| Photo mode: F12 / Cmd+Shift+P / pause-menu entry, world and race clock stop, HUD hidden, orbit and free camera, FOV, tilt, reset, controller controls | Take screenshots like a photographer | PORT | old runtime/photo.c (522), native_scene.m (307), native_scene.h, metal.m capture hook, web/status_proto.h status slots | Medium-large. NA addresses in photo.c. In multiplayer free roam it uses roam_game's sync clock (optional dependency on free-roam). The pause-menu icon (photo_icon.h) is drawn by the web texrep only; natively it would need an NTXP entry or a plain item. |
| PNG capture (async Metal readback), F12 screenshot in menus and network races without freezing, unique filenames, NFSU2_APPSUPPORT relocation | Save pictures | PORT | old native_scene.m encode_capture/save_bgra | Part of the photo port. |
| Screenshot gallery in the launcher | See Launcher | PORT | old launcher/PhotoGallery.swift | Listed under Launcher. |
| Drift mode in free roam (X toggles the game's drift handling, drift camera, scoring) | Drift anywhere in the city | PORT | old runtime/drift.c (358) | Small-medium. NA addresses (0x89E7D9, 0x890104, overrides 0x56ddd0/0x4c85d0/0x4ac120). No free-roam dependency (career free roam). |
| Drift HUD overlay: points, multiplier and next-level progress, best, total, banked/lost feedback, hidden in photo mode | See your drift score | PORT | old native_scene.m drift snapshot, tests/native_scene_test.m | Needs drift.c and native_scene. |
| Drift fidelity test helpers (drifttest.c NFSU2_FIXED_DT, tools/drift_*.py, tests/checks/driftscore.sh) | None | SKIP | old runtime/drifttest.c, tools/drift_accrual.py, drift_compare.py | Test-only. |

## Tools / tests

| Feature | What it does for the player | Status | Where (files/branch/commit) | Notes (gaps, deps, EU addresses needed) |
|---|---|---|---|---|
| ISA tests (610 checks incl. LREGS/X87PC/JTSWITCH variants) | Guards instruction semantics | PORT | old tools/isatest.py (598 lines vs 525 in preview-old), tools/fuzzisa.py | Port the extra cases that cover branch features (x87-precision, SSE2, retpast). |
| Function/runtime checks (65: heap API, _ftol2, shadow hull, etc.) | Guards lifted code and runtime pieces | PORT | old tests/main_all.c (682 vs 83 upstream) | Some sections test wasm-only paths (skip those). Heap section only if heap.c is ported. |
| Heap stress (concurrency, realloc, VirtualAlloc edges, planted bugs) | Guards memory | DONE | old tests/heap_stress.c | Only useful with heap.c; upstream gheap.c would need its own test. Done in fbcb7db (fp/engine), rewritten against gheap.c. |
| Object table unit test | Guards waits and handles | DONE | old tests/objtable_unit.c, tests/windows_waits.sh | Guards upstream #14 too. Done in fbcb7db (fp/engine). |
| Watchdog unit test | Guards watchdog | DONE | old tests/watchdog_unit.c | With watchdog.c. Done in fbcb7db (fp/engine). |
| Winsock HLE harness (240 checks) + loopback sandbox | Guards LAN/online semantics | PORT | old tests/net_harness.c, tests/net/loopback-only.sb, tests/net/*.sh | lan-play brought the code without tests. |
| Native WebSocket relay fixtures (relay, resume, queue, two-client, idle, burst, exit) | Guards online transport | PORT | old tests/net/native/loopback.py, relay.c, switch.c, transport.m | Should go with lan-play. |
| Free-roam core tests (287 roam checks), fake peer, viewer peer | Guards free-roam protocol | PORT | old tests/roam_unit.c, roam_fakepeer.c, roam_recv.c, tests/roam/*.sh | Should go with free-roam. |
| Free-roam cross-platform x86 oracle / PE self-test / crowd (wasm) | Guards bit-identical Windows plugin interop | SKIP | old tests/roam_x86_oracle.c, roam_selftest.c, roam_pe_selftest.c, roam_crowd.c | Needs Unicorn / Windows build / browser. |
| Differential oracles under Unicorn (oracle.c, net_oracle.c, srvoracle.c) | None (developer verification) | SKIP | old runtime/oracle.c (601), tests/net_oracle.c, srvoracle.c/.sh | Needs a Unicorn build. |
| Scripted scenario runner (autotest.c: NFSU2_INPUT_SCRIPT, QUIT_FRAMES, STATUS_EVERY, FNG_LOG, CAR_TRACE) + tools/autorun.sh, apptest.sh, tests/run_suite.sh + 323 scripts | Guards real behaviour end to end (keyboard rebinds, pad, heap soaks, LAN races, free roam, garage, discord...) | PORT | old runtime/autotest.c (1155), tools/autorun.sh, apptest.sh, tests/run_suite.sh, tests/scripts/*.txt | Large. Scripts hold NA addresses (waitmem etc.) and need EU variants. Upstream has only AUTOSEQ/AUTOKEY hooks. |
| Soak/test generators and analysers (gen_soak.py, gen_lan_race.py, lan_trace.py, roam_compare.py, roam_multi/plan/solo.sh, hfr_compare.py, contact_sheet.py, career_report.py) | None directly | SKIP | old tools/* | Useful only together with autotest.c. |
| Game-folder untouched proof (tools/manifest.py, tools/writewatch.c) | Guards "game data is read-only" | PORT | old tools/manifest.py, tools/writewatch.c | Small, cheap guard. |
| vlanhub.py virtual LAN hub | Lets several local instances race (tests) | PORT | old tools/vlanhub.py (841) | Pairs with lan-play's net_vlan.c; without it that backend has no hub. |
| Native feature tests: gamepad harness, native controls, quick chat, native scene, photo gallery, headlights, radio, texpack, texrep, shader ps20, save paths, discord, vault | Guard the matching features | PORT | old tests/gamepad_harness.m, native_controls*.m/.sh, native_quickchat_test.m, native_scene*.m/.sh, photo_gallery*, headlights_*, radio_*, texpack_unit.c, texrep_native_unit.m, shader_ps20.c, save_paths.m, discord_*, vault* | Port each with its feature. headlights, discord, shader ps20 and save paths guard code already in the new base. |
| Web test seeds and horn preview (tests/web/*, horn_render.c) | None natively | SKIP | old tests/web, tests/horn_render.c | Browser only. |
| Photo icon generator (tools/photoicon.py, photo_icon.svg) | Pause-menu photo icon texture | SKIP | old tools/photoicon.py | Only needed if the photo port draws the icon natively. |

## Not features (for completeness)

- web-parity.md backlog items 3 (controller rumble), 6 (career tools), 7 (diagnostic export) and 8 (steering wheel) were never implemented in the old fork.
- New-base-only features (not in the old fork): data-mods, hd-reflections, visual-options (tint, gamma, edge smoothing, sharpening), Texture Packs catalog, Restore Original Game, upstream xpatch (#9), upstream high-FPS fixes (#10), Cmd+Shift+D Metal frame capture, system shortcut blocking.

## Porting packages

Every PORT row above belongs to one package. Packages are ported on their own branches from this one and merged back; a row changes to DONE (with the commit) when its package lands.

| Package | PORT rows it covers |
|---|---|
| A. Photo and drift | Photo mode, PNG capture and F12 screenshots, screenshot gallery, drift mode, drift HUD overlay, native scene / gallery tests |
| B. Music | Local music folder through EA Trax, launcher music folder chooser, music controls in the app menu, radio tests, music after shops (guest_noyield) |
| C. Display, lifecycle and language | Resolution scale, FMV framing, lens rain drops, rain tint quads, English app menu titles, Cmd-Q as WM_CLOSE with save drain, activation and background pause/run, movie subtitles, language-choice gaps (own texts table, accented letters), language and subtitle packs fetched by the launcher, launcher display options |
| D. Input | Mac keyboard layouts, buffered key events, keyboard rebinding, saved bindings, Mac key names, pad triggers / GUID / bindings / hotplug / menu keys / background, launcher controller hotplug and trigger dead zone, gamepad and keyboard tests |
| E. Engine fixes | Kernel object reuse, fair GIL, stall watchdog, JDLZ decompressor, car part memo, D3DX stage 9 and refcount fix, save-overlay cache, Win32 HLE refinements, audio device changes, positional sound fix, car lot fix, Performance Shop fix, registry seed, guest heap gaps vs gheap.c, frame-rate gaps (uncapped, LAN timing, online frame cap), object table and watchdog tests |
| F. Game Tools and multiplayer extras | Game Tools panel, quick chat and groups, chat bubbles, live solid/ghost and four crews, room names in UTF-8 with the runtime check, world map 1024 nodes, car loader hang, ride texture fixes, player and crew counts, music section of the panel (after B) |
| G. Compiler | LREGS, JTSWITCH, INLINE lists, FTOL2INL, NOCLOSURE, override/hook lists derived from the sources, ISA and function/runtime test additions |
| H. Saves and services | Encrypted cloud saves, Discord custom large image, launcher validation tests |
| I. Test infrastructure | Scripted scenario runner (EU and NA), Winsock harness, relay fixtures, free-roam core tests, vlanhub, game-folder untouched proof, remaining native feature tests |
| K. Controller rumble | Force feedback mixer and native controller motors (after D) |
| J. Texture packs from DDS / AI upscale | DDS replacement packs and the tools/texpack builder, done by the launcher in one click |
