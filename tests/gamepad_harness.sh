#!/bin/bash
# tests/gamepad_harness.sh: runtime/gamepad.m against GameController.framework
# without a physical controller (tests/gamepad_harness.m), and the synthetic pad.
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/nfsu2_gamepad_harness.$$
mkdir -p "$OUT" || exit 1
trap 'rm -rf "$OUT"' EXIT
clang -fobjc-arc -O1 -Wall -Iruntime -o "$OUT/harness" tests/gamepad_harness.m runtime/gamepad.m \
      -framework Foundation -framework AppKit -framework GameController || { echo "gamepad_harness: does not build"; exit 1; }
rc=0
env -u NFSU2_PAD_FAKE -u NFSU2_PAD_SEQ -u NFSU2_PAD_BACKGROUND "$OUT/harness" || rc=1
env -u NFSU2_PAD_SEQ -u NFSU2_PAD_BACKGROUND NFSU2_PAD_FAKE="X=0.5;Y=-1;B0=1;SQUARE=1;RT=0.6;Z=0.4;POV=9000" "$OUT/harness" synth || rc=1
exit $rc
