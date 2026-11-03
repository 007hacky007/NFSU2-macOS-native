# Tests

## Unit level (no game files)

`tests/run_suite.sh` runs every unit-level suite below, each building into a
temporary folder, and prints one PASS/FAIL line per suite and a summary
(`RESULT: all passed`, exit 0). `UNITS="net_harness roam_unit" tests/run_suite.sh`
runs a few. Suites that need a Metal device or `swiftc` say SKIP without one.
Network tests stay on loopback or AF_UNIX, inside `tests/net/loopback-only.sb`.

| Suite | What it guards |
|---|---|
| `hle_unit`, `windows_waits`, `watchdog_unit`, `heap_stress` | Win32 HLE answers, waits and handles, the stall watchdog, the guest heap |
| `framerate` | frame-rate choices (runtime/framerate.c) |
| `names_unit` | names that read as a slur (runtime/names.h): the live server's made-up ways round the lists refused, the other words with those letters not |
| `hiddenraces_unit` | the career's hidden races on the map (runtime/hiddenraces.c), off and on |
| `carspot_unit` | the career's kept spot: one that is no place on the map becomes the new career's start (runtime/carspot.c) |
| `uniques_unit` | the unique visual parts for every car after Caleb (runtime/uniques.c), off and on |
| `keyboard_unit`, `gamepad_harness` | DirectInput keyboard and key names; GameController and the synthetic pad |
| `horn_unit`, `radio_native` | horns, the music folder |
| `racenet_unit` | network races: the joiners' car states straight to each other, the corrections' fade |
| `native_scene`, `photo_gallery` | photo mode and drift panels, the Screenshots window |
| `headlights_native` | other cars' headlights: modes, the pool, the Metal shaders (EU and NA) |
| `shader_ps20` | ps_2_0 shader translation, original and HD |
| `save_paths` | where saves go, the old folder's move, NFSU2_SAVEDIR |
| `texture_unit`, `texture_packs` | texture pack reading, drawing, the launcher's builder |
| `game_folder_tools` | tools/writewatch.c and tools/manifest.py (the game-folder proof's tools) |
| `net_harness` | the Winsock / Netbios HLE and NetTick (244 checks with the virtual LAN hub tools/vlanhub.py), the native WebSocket relay fixtures (tests/net/native) |
| `roam_unit` | the free-roam core (370 checks: rooms changed while playing, friends marked by the hub among them) and a loopback stand-in friend (roam_fakepeer, roam_recv) |
| `native_controls`, `launcher_online` | Game Tools, its room and friends, and quick chat; the launcher's online settings |
| `launcher_roam`, `friends_api` | the later free-roam options, invite links; the launcher's Friends against a stand-in for /friends on 127.0.0.1 |
| `netstats_unit` | the Online statistics panel: its text, the /players address and answer, the fetch against a stand-in on 127.0.0.1 |
| `ff_unit`, `rumble_unit` | force feedback effects and the controller's motors |
| `discord_unit`, `launcher_settings`, `vault` | Discord presence (mock IPC), launcher settings, cloud saves |
| `save_manager`, `display_options`, `language_packs` | launcher models |
| `picture_tone` | Exposure and White Level (runtime/picture.m): the settings, the pass on the GPU against its curve |

## Game level

These run the game invisibly and silently (NOFOCUS=2, NFSU2_MUTE=1), one game
at a time, with a private HOME, so the player's settings and saves are never
touched. `NFSU2_DATA` is the game folder or its SPEED2.EXE. For the North
American SPEED2.EXE use its engine (`out/nfsu2_na_boot`; for
`tools/autorun.sh` and `tests/run_suite.sh --game`: `NFSU2_BIN=nfsu2_na_boot`).

**The scenario runner** (runtime/autotest.c) plays a script in step with the
game's frames: keys (DirectInput and window messages, or real NSEvents
through runtime/keyboard_mac.m), the synthetic game pad, waits for a screen or
a memory value, checks (`expect`), frame dumps, and the test-only career aids
of runtime/career.c (the career bot, jumps to shops and races, the game's own
autopilot). Its header lists every command. Scripts are in `tests/scripts/`;
their game addresses are European and mapped on the North American build
through `runtime/autotest_addrs.h`, which `tools/script_addrs.py` writes (run it
after adding an address to a script; link.sh maps the entries). The keyboard
and pad scenarios of `tests/input/*.seq` use the same runner through
`NFSU2_INPUT_SEQ`.

```sh
tools/autorun.sh <out> NFSU2_DATA=<game> NFSU2_INPUT_SCRIPT=$PWD/tests/scripts/quickrace.txt   # one run
tests/run_suite.sh --game <out> [scenario...]          # the scenario list in run_suite.sh
tests/input/suite.sh <engine> <SPEED2.EXE> <work>      # keyboard and pad
tests/game_folder_untouched.sh <engine> <SPEED2.EXE> <work>   # the game folder stays as it was
tests/display_runtime.sh, tests/photo_drift.sh, tests/shop_music.sh   # see their headers
tests/discord_suite.sh <out> [eu|na|both] [race gamequit latekill malformed absent]   # a mock Discord
tests/net/loop_run.sh, tests/net/vlan_run.sh, tests/net/lan_race.sh   # LAN play between instances
tests/roam/plan.sh <out> 900 roam_loader_overlap.txt 47600 8 tests/roam/plan_loader.sh   # free roam: friends' car loads during part-animation reads (roamfix.c)
tests/roam/plan.sh <out> 900 roam_carpool.txt 47600 8 tests/roam/plan_loader.sh NFSU2_ROAM_CARPOOL_KB=24000   # free roam: friends' cars in a small car pool (roamfix.c)
tests/roam/plan.sh ...                                 # other plans with stand-in friends (tests/roam/plan_*.sh)
```

A scenario fails on a fault, a time limit, an unresolved indirect call, a
failed `expect`, a wait that timed out, a script line the runner refused, a
blocked network attempt, or a missing marker. Logs and dumps stay in
`<out>/<name>/`.

Scripts that start from a career save (garage_*, shop_*, tune_graph,
career_cover*, career_lot_badstock, dyno_units, career_outrun) need
`NFSU2_SAVE_SEED=<a save folder>`; their headers say which stage.

`lan_cycle` leaves LAN hosting and hosts again (`lan_host_short.txt`);
`lan_srvcycle` starts and stops server.dll six times through the game's own
glue and checks that every cycle ends the server's threads before the unload
and leaves no socket, host fd or TLS index behind. `tests/run_suite.sh --game
<out> lan_cycles` (opt-in) hosts and leaves four times through the menus.

Some scripts need a variable of the feature they test (their headers say
which): NFSU2_PHOTO=1 (photo_mode, native_photo, native_headlights),
NFSU2_DRIFT=1 (native_drift), TEXKEY=T (kb_app_shortcuts), NFSU2_HORN=1 (the
horn ones).  The pad scripts take the synthetic controller; with a real one
connected to the Mac, run them with NFSU2_PAD_FAKE=PLUG=1 so the real one does
not take over.
