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
       env -u NFSU2_FPS -u NFSU2_CUTSCENES_60 -u NFSU2_DISPLAY_HZ -u PACE60 -u NFSU2_HFR_FIX "$@" "$tmp/framerate_unit" $want; }
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
echo "framerate: all passed"
