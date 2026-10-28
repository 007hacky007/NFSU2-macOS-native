#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
clang -O1 -Wall -Wno-unused-function -Iruntime -Wl,-dead_strip tests/framerate_unit.c -o "$temp_dir/framerate"
env -u NFSU2_CUTSCENES_60 NFSU2_FPS=120 "$temp_dir/framerate" 120 30
NFSU2_CUTSCENES_60=0 NFSU2_FPS=120 "$temp_dir/framerate" 120 30
NFSU2_CUTSCENES_60=1 NFSU2_FPS=120 "$temp_dir/framerate" 120 60
NFSU2_CUTSCENES_60=1 NFSU2_FPS=240 "$temp_dir/framerate" 240 60
NFSU2_CUTSCENES_60=1 NFSU2_FPS=60 "$temp_dir/framerate" 60 60
NFSU2_CUTSCENES_60=1 NFSU2_FPS=30 "$temp_dir/framerate" 30 30
