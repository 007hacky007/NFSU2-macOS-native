#!/bin/sh
# Exposure and White Level (runtime/picture.m, the launcher's Display card) without the
# game: the settings as NFSU2_EXPOSURE and NFSU2_WHITE_LEVEL give them, and the pass over
# a row of grey levels on the GPU against the curve (tests/picture_tone.m; SKIP without
# a Metal device).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -g -fobjc-arc -Wall -Iruntime runtime/picture.m tests/picture_tone.m -framework Foundation -framework Metal -o "$tmp/picture_tone"
#                    stops  percent  mult      white
"$tmp/picture_tone"  ""     ""       1         1          # the original game: no pass
"$tmp/picture_tone"  "0"    "100"    1         1
"$tmp/picture_tone"  "-0.3" ""       0.812252  1
"$tmp/picture_tone"  ""     "70"     1         0.70
"$tmp/picture_tone"  "-0.3" "70"     0.812252  0.70
"$tmp/picture_tone"  "+1.0" "40"     2         0.40
"$tmp/picture_tone"  "-1"   "100"    0.5       1
"$tmp/picture_tone"  "5"    "10"     2         0.40       # out of range: clamped
"$tmp/picture_tone"  "0.04" "98"     1         1          # under half a step: as drawn
echo "picture_tone: all passed"
