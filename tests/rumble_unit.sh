#!/bin/bash
# tests/rumble_unit.sh: runtime/rumble.m (the controller's motors) with fake
# haptic engines, no controller needed (tests/rumble_unit.m).
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/nfsu2_rumble_unit.$$
mkdir -p "$OUT" || exit 1
trap 'rm -rf "$OUT"' EXIT
clang -fobjc-arc -O1 -g -Wall -fsanitize=address,undefined -Iruntime -o "$OUT/rumble" tests/rumble_unit.m runtime/rumble.m runtime/gamepad.m \
      -framework Foundation -framework AppKit -framework GameController -framework CoreHaptics || { echo "rumble_unit: does not build"; exit 1; }
rc=0
env -u NFSU2_FF_STRENGTH ASAN_OPTIONS=detect_leaks=0 "$OUT/rumble" || rc=1
NFSU2_FF_STRENGTH=50 ASAN_OPTIONS=detect_leaks=0 "$OUT/rumble" strength || rc=1
exit $rc
