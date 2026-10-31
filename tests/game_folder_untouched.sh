#!/bin/bash
# tests/game_folder_untouched.sh <engine> <SPEED2.EXE> <work dir>
# The game folder is read-only for the port: a run that makes a profile and
# saves it, presses F12 (the game's own screenshot request), opens the
# options, races and quits with Cmd-Q (tests/scripts/app_rw_probe.txt) leaves
# every file and folder in it as it was.  Two proofs:
#   - tools/writewatch.c interposed into the engine logs every attempt to
#     write below the folder (open for writing, mkdir, rename, unlink, chmod,
#     setxattr ...), from any code in the process: there must be none;
#   - tools/manifest.py before and after (contents, sizes, times, modes,
#     extended attributes, entries added or removed): the same.
# European or North American (engine out/nfsu2_boot or out/nfsu2_na_boot and
# its SPEED2.EXE).  Hashing the folder takes a while (5 GB twice).
BIN="$1"; EXE="$2"; WK="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$BIN" ] && [ -f "$EXE" ] && [ -n "$WK" ] || { echo "usage: $0 <engine> <SPEED2.EXE> <work dir>"; exit 2; }
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
GAME="$(cd "$(dirname "$EXE")" && pwd)"
rm -rf "$WK"; mkdir -p "$WK"; WK="$(cd "$WK" && pwd)"
FAILED=0
check(){ if [ "$2" = 1 ]; then printf "  PASS  %s\n" "$1"; else printf "  FAIL  %s  (%s)\n" "$1" "$3"; FAILED=1; fi; }
clang -dynamiclib -O2 -o "$WK/writewatch.dylib" "$ROOT/tools/writewatch.c" || exit 1
echo "== manifest of $GAME"
"$PY" -I "$ROOT/tools/manifest.py" "$GAME" "$WK/before.tsv" || exit 1
"$ROOT/tools/autorun.sh" "$WK/run" NFSU2_DATA="$EXE" NFSU2_BIN="$(basename "$BIN")" ALARM=300 NFSU2_FNG_LOG=1 \
    NFSU2_INPUT_SCRIPT="$ROOT/tests/scripts/app_rw_probe.txt" \
    WRITEWATCH_DIR="$GAME" WRITEWATCH_LOG="$WK/writewatch.txt" DYLD_INSERT_LIBRARIES="$WK/writewatch.dylib"
"$PY" -I "$ROOT/tools/manifest.py" "$GAME" "$WK/after.tsv" || exit 1
L="$WK/run/log.txt"
check "the run reached the race" "$(grep -a -q 'waitmem \[0x008654a4\]==6 satisfied' "$L" && echo 1 || echo 0)" "no race"
check "the profile was saved (outside the game folder)" "$(ls "$WK/run/save" 2>/dev/null | grep -q . && echo 1 || echo 0)" "nothing in the save folder"
check "Cmd-Q ended the game" "$(grep -a -q 'autotest close' "$L" && ! grep -a -q 'still running 1200 frames after close' "$L" && echo 1 || echo 0)" "still running after close"
n=$(grep -a -o 'writewatch: [0-9]* write attempts below' "$WK/writewatch.txt" 2>/dev/null | grep -o '[0-9]*' | head -1)
check "writewatch was in the process" "$([ -n "$n" ] && echo 1 || echo 0)" "no writewatch summary in $WK/writewatch.txt"
check "no write attempt below the game folder" "$([ "${n:-x}" = 0 ] && echo 1 || echo 0)" "$(grep -a '^WRITE' "$WK/writewatch.txt" 2>/dev/null | head -3 | tr '\n' ' ')"
"$PY" -I "$ROOT/tools/manifest.py" --diff "$WK/before.tsv" "$WK/after.tsv" > "$WK/diff.txt" 2>&1; d=$?
check "the folder's manifest is unchanged ($(wc -l < "$WK/before.tsv" | tr -d ' ') entries)" "$([ $d = 0 ] && echo 1 || echo 0)" "$(head -3 "$WK/diff.txt" | tr '\n' ' ')"
echo
if [ $FAILED = 0 ]; then echo "RESULT: all passed"; else echo "RESULT: SOME FAILED"; fi
exit $FAILED
