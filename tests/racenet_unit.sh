#!/bin/bash
# tests/racenet_unit.sh: the unit tests of runtime/racenet.c (tests/racenet_unit.c):
# the joiners' car states straight to each other and the corrections' fade.
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/nfsu2_racenet_unit.$$
mkdir -p "$OUT" || exit 1
clang -std=gnu11 -O1 -g -Wall -Wextra -Wno-unused-function -Wno-unused-parameter -fsanitize=address,undefined \
      -Iruntime -o "$OUT/racenet_unit" tests/racenet_unit.c || { echo "racenet_unit does not build"; rm -rf "$OUT"; exit 1; }
ASAN_OPTIONS=detect_leaks=0 "$OUT/racenet_unit"; rc=$?
rm -rf "$OUT"
exit $rc
