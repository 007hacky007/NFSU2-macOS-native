#!/bin/bash
# tests/horn_unit.sh: the unit tests of runtime/horn.c, racehorn.c and carsfx.c
# (tests/horn_unit.c), each built on its own and run.  NFSU2_DATA=<SPEED2.EXE>
# also tries the game's own sound files.
cd "$(dirname "$0")/.." || exit 1
OUT=${TMPDIR:-/tmp}/nfsu2_horn_unit.$$
mkdir -p "$OUT" || exit 1
rc=0
for t in HORN RACEHORN CARSFX; do
    clang -std=gnu11 -O1 -g -Wall -Wextra -Wno-unused-function -Wno-unused-parameter -fsanitize=address,undefined \
          -Iruntime -DT_$t -o "$OUT/$t" tests/horn_unit.c -lpthread || { echo "horn_unit: $t does not build"; rc=1; continue; }
    ASAN_OPTIONS=detect_leaks=0 "$OUT/$t" || rc=1
done
rm -rf "$OUT"
exit $rc
