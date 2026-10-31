#!/bin/bash
# tests/texture_unit.sh -- the texture packs' runtime without the game: the NTXP reader
# (tests/texpack_unit.c) and runtime/texrep.m with a real Metal device
# (tests/texrep_native_unit.m: NTXP packs, the DDS pack whole and stacked, sharing,
# release, parts, collected textures, and a GPU memory budget run of its own).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_texunit.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fails=0
clang -Wall -I"$ROOT/runtime" "$ROOT/tests/texpack_unit.c" "$ROOT/runtime/texpack.c" -lz -o "$T/texpack_unit" \
    || { echo "FAIL  texpack_unit build"; exit 1; }
TMPDIR="$T" "$T/texpack_unit" || fails=$((fails+1))
clang -Wall -fobjc-arc -I"$ROOT/runtime" "$ROOT/tests/texrep_native_unit.m" "$ROOT/runtime/texpack.c" -lz \
    -framework Cocoa -framework Metal -o "$T/texrep_native" || { echo "FAIL  texrep_native_unit build"; exit 1; }
for mode in "" --budget; do
    out="$(TMPDIR="$T" "$T/texrep_native" $mode 2>&1)"; rc=$?
    echo "$out" | grep -E "^(PASS|SKIP)"
    if [ $rc -ne 0 ] && [ $rc -ne 77 ]; then echo "FAIL  texrep_native $mode (exit $rc)"; echo "$out" | tail -5; fails=$((fails+1)); fi
done
[ $fails -eq 0 ] && echo "RESULT: all passed" || { echo "RESULT: $fails failed"; exit 1; }
