#!/bin/bash
# tests/ff_unit.sh: runtime/dinput_ff.c (the force-feedback effects and their
# mix into two motor levels) without the game (tests/ff_unit.c).
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/nfsu2_ff_unit.$$
mkdir -p "$OUT" || exit 1
trap 'rm -rf "$OUT"' EXIT
clang -std=gnu11 -O1 -g -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -Iruntime \
      -o "$OUT/ff" tests/ff_unit.c runtime/dinput_ff.c || { echo "ff_unit: does not build"; exit 1; }
ASAN_OPTIONS=detect_leaks=0 "$OUT/ff"
