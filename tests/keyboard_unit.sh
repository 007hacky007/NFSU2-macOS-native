#!/bin/bash
# tests/keyboard_unit.sh: runtime/keyboard.c and runtime/dikeys.c without the
# game (tests/keyboard_unit.c).
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/nfsu2_keyboard_unit.$$
mkdir -p "$OUT" || exit 1
trap 'rm -rf "$OUT"' EXIT
clang -std=gnu11 -O1 -g -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -Iruntime \
      -o "$OUT/kbd" tests/keyboard_unit.c runtime/keyboard.c runtime/dikeys.c -lpthread || { echo "keyboard_unit: does not build"; exit 1; }
ASAN_OPTIONS=detect_leaks=0 "$OUT/kbd"
