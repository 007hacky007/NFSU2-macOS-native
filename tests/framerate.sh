#!/bin/sh
# Frame-rate choices (runtime/framerate.c) without the game: tests/framerate_unit.c.
# Each line: the environment, then the expected rate in a race and in a cutscene
# (the unit test's screen is 120 Hz unless NFSU2_DISPLAY_HZ says otherwise).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -Wall -Wno-unused-function -Iruntime -Wl,-dead_strip tests/framerate_unit.c -o "$tmp/framerate_unit"
run(){ want="$1 $2"; shift 2
       env -u NFSU2_FPS -u NFSU2_CUTSCENES_60 -u NFSU2_DISPLAY_HZ -u PACE60 -u NFSU2_HFR_FIX -u NFSU2_LAN_TIMING "$@" "$tmp/framerate_unit" $want; }
# NFSU2_FPS=uncapped, and network races (NFSU2_LAN_TIMING): the rate and whether
# the ticks/timer fixes stay on
runx(){ args="$1"; shift; env -u NFSU2_FPS -u NFSU2_CUTSCENES_60 -u NFSU2_DISPLAY_HZ -u PACE60 -u NFSU2_HFR_FIX -u NFSU2_LAN_TIMING "$@" "$tmp/framerate_unit" $args; }
run 120 30 NFSU2_X=0
run 120 30 NFSU2_FPS=120
run 120 30 NFSU2_FPS=120 NFSU2_CUTSCENES_60=0
run 120 60 NFSU2_FPS=120 NFSU2_CUTSCENES_60=1
run 240 60 NFSU2_FPS=240 NFSU2_CUTSCENES_60=1
run 240 30 NFSU2_FPS=240
run 60 60 NFSU2_FPS=60 NFSU2_CUTSCENES_60=1
run 60 30 NFSU2_FPS=60
run 30 30 NFSU2_FPS=30 NFSU2_CUTSCENES_60=1
run 60 30 NFSU2_FPS=auto NFSU2_DISPLAY_HZ=60
run 120 30 NFSU2_FPS=auto NFSU2_DISPLAY_HZ=144
run 240 60 NFSU2_DISPLAY_HZ=240 NFSU2_CUTSCENES_60=1
run 30 30 NFSU2_DISPLAY_HZ=30
run 60 30 PACE60=1
run 120 30 NFSU2_FPS=off
runx uncapped NFSU2_FPS=uncapped
runx "net 120 0" NFSU2_FPS=240
runx "net 120 0" NFSU2_FPS=120
runx "net 240 1" NFSU2_FPS=240 NFSU2_LAN_TIMING=exact
runx "net 60 0" NFSU2_FPS=60
# the slot's wait after Present, before the game reads the pads (runtime/framerate.c hfr_after_present).
# These sleep in real time: a shared CI machine can overshoot a sleep by several frames (seen: 4 slots
# missed at 60 fps), so a run gets three tries; a pacing bug fails all three.
tries(){ for t in 1 2 3; do if runx "$@"; then return 0; fi; echo "  (try $t of 3 failed)"; done; return 1; }
tries "present 60"
tries "present 120"
tries "present 60" NFSU2_PACE_AT=frame
# replays above 60 fps: WorldTimer from the game's own clock (runtime/framerate.c, sub_0057a0f0)
runx "replay 120"
runx "replay 240"
runx "replay 144"
echo "framerate: all passed"
