# Wine comparison measurement (2026-10-03)

A measurement of the native port against the "run the game with Wine" path that
was the project's starting point. Same machine (M1 Pro, macOS 27.0.1, 120 Hz
display), same settings (`~/.nfsu2_registry`: race resolution index 3 = 1280x960,
all effects on), same scene (Quick Race → Circuit → Resort Loop,
`TRACKS/STREAML4RA.BUN`), sound off on both sides. Native and Wine were run in
two **alternating** rounds (N → W → N → W) so that thermal drift is spread
evenly over both sides.

## Result

| | Native port | Wine 11.18 (wined3d, Rosetta) | ratio |
|---|---|---|---|
| Race, +10..60 s | **119.3 / 119.0 fps** (8.34 ms median) | **11.3 / 10.0 fps** (~88–100 ms) | ~11x |
| Race, +60..140 s | 119.8 / 119.3 fps | 14.6 / 12.8 fps (~68–78 ms) | ~8.7x |
| Frame time p99 (race) | 9.4–10.6 ms | drops to 4–5 fps in 10 s windows | |
| 3D menus | 119.5 / 118.7 fps | 45.4 / 45.9 fps | ~2.6x |
| Game process CPU (mid-race) | 151% / 148% | 142% / 144% (all Wine processes 147–151%) | |
| **CPU time per frame** | **~12.6 ms** | **~105 ms** | **~8x** |
| Energy impact (`top` POWER) | 123 / 121 | 116 / 117 | ~8x per frame |
| RSS (game process) | ~575 MB | ~345 MB (+ wineserver) | |
| Launch reliability | 4/4 | 7 of 11 launches produced no frame within 15 s (retried automatically) | |

**The native race sits at the 120 Hz vsync ceiling** (119–120 with `NOVSYNC=1`
too); the real headroom is higher than this table shows, so the ratio is **at
least** 8–11x.

On the Wine side no thread is saturated: the game thread is ~70–77% busy,
`wined3d_cs` (the command thread) ~44–48%. With total CPU at ~1.5 cores, 8x more
CPU is spent per frame; the rest of the time is probably synchronization between
threads and waiting on the GL→Metal driver. This is an inference: the code under
Rosetta was not symbolicated with `sample`.

## What we ran into on the Wine side (the real cost of the Wine path)

1. Homebrew's `wine-stable`/`wine@devel` casks were shut down on 2026-09-01;
   the macOS 27 update had removed Rosetta 2 (reinstalled by hand).
2. Fullscreen 1280x960 is rejected in macdrv (`ChangeDisplaySettings -2`) →
   `CreateDevice` fails → the game crashes with a null read at `0x5D2790`.
   It only opens with the Wine virtual desktop.
3. If the window can't come to the front on the Mac (while the screen is locked
   or the user is in another application), the fullscreen D3D device stays in
   the "lost" state and the game freezes. Because of macOS 14+ cooperative
   activation and the locked screen, it can't be brought to the front
   programmatically.
4. Intermittent crashes at launch (`7BF21239`, a Wine DLL) and silent exits.

## Method and deviations (honesty note)

- Because of the locked screen the Wine runs were done in **windowed mode**. For
  this the ThirteenAG widescreen fix ASI shipped with the game (`dinput8=n,b`)
  was loaded, but every intervention except `WindowedMode=2` was turned off
  (FixHUD/FOV, FPSLimit, SingleCoreAffinity, ConsoleGamma, SkipIntro etc. = 0).
  The native side has no ASI.
- On Wine the menus were entered with a timed `keybd_event` injector
  (`~/wine-olcum/tools/mkinject.py`, clang + a hand-made PE32), on native with
  `AUTOSEQ`. The track is L4RA on both sides; on Wine the car changed from run to
  run (206 / 106), on native it was always the Peugeot 206.
- Native fps: `FPSCSV`, race start = the first continuous frame with more than
  1000 draws, frames with `draws > 400`. Wine fps: `WINEDEBUG=+timestamp,+fps`
  (~1.5 s averages, merged frame-weighted), race start = the first <20 fps report
  after the menus.
- CPU/RSS with `ps` once a second, energy with `top -stats power` every 5 s.
- Raw data and scripts: `~/wine-olcum/` (`ab.sh`, `run_wine.sh`,
  `run_native.sh`, `tools/nstat.py`, `tools/wstat.py`, `tools/summary.py`,
  `n_ab*.csv`, `w_ab*.log`).
