#!/bin/bash
# Music after entering a shop (runtime/radio.c, sub_0073b900): new career -> world -> Car Lot -> 20 s in the
# shop.  Entering the shop starts a new song held paused and unpauses it a moment later; when the unpause was
# lost the song never started: no MusicSFX.mus reads after "status shop_in", silence until a restart (about 2
# runs in 3 before the fix in nfsu2-web, whose GIL hands over in turn; with this build's plain mutex GIL it did
# not happen in 7 runs without the fix).  Good: MusicSFX.mus reads keep coming between "status shop_in" and
# "music_end".
#
#   tests/shop_music.sh [runs] [binary]     (default 3 runs of out/nfsu2_boot)
#
# NFSU2_DATA: SPEED2.EXE (EU or NA; for NA pass out/nfsu2_na_boot).  Silent and invisible like tools/check.sh;
# the profile, the career and ~/.nfsu2_registry are in a temporary HOME.  The menus are walked with AUTOSEQ /
# AUTOTEXT, the rest by tests/shop_music.m (DYLD_INSERT_LIBRARIES).  About 1.5 min a run.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNS="${1:-3}"; BIN="${2:-$ROOT/out/nfsu2_boot}"
EXE="${NFSU2_DATA:-$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2/SPEED2.EXE}"
[ -d "$EXE" ] && EXE="$EXE/SPEED2.EXE"
[ -f "$EXE" ] || { echo "SPEED2.EXE not found: $EXE"; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_shop.XXXXXX")"
clang -O1 -fobjc-arc -dynamiclib -mmacosx-version-min=11.0 -framework Foundation -o "$TMP/shop_music.dylib" "$ROOT/tests/shop_music.m" || exit 2
# Press Enter, a new profile "TEST" (Yes, the name, save it), Career, Start New Career
SEQ="1000:0x1C,1150:0xCB,1180:0x1C,1840:0x1C,2150:0xCB,2210:0x1C,2510:0x1C"
FAILED=0
for i in $(seq 1 "$RUNS"); do
  H="$TMP/home$i"; LOG="$TMP/run$i.log"; mkdir -p "$H/saves"
  env -i HOME="$H" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
    FIXMAT=1 FIXMAT_MODE=3 NOMOVIES=1 SNDSYNC=1 GPUVS=1 WINDOW=1 ALARM=0 NOFOCUS=2 NOSOUND=1 NFSFULL=0 \
    MOUSEAT=5,5 FSFAKE=300 NFSU2_SAVEDIR="$H/saves" GAMELOG=1 READLOG=1 AUTOSEQ="$SEQ" 'AUTOTEXT=1420:\b\b\b\bTEST\n' \
    QUITFRAMES=9000 DYLD_INSERT_LIBRARIES="$TMP/shop_music.dylib" ${SHOP_ENV:-} \
    "$BIN" "$EXE" > "$LOG" 2>&1
  r=$(LC_ALL=C awk '/\[shoptest\].*status shop_in/{on=1} /\[shoptest\].*status music_end/{on=0} on && /\[read\].*MusicSFX\.mus/{n++} END{print n+0}' "$LOG")
  if grep -a -q "status music_end" "$LOG"; then
    if [ "$r" -gt 0 ]; then echo "run $i: PASS  $r MusicSFX.mus reads in the shop"; else echo "run $i: FAIL  no MusicSFX.mus reads in the shop"; FAILED=1; fi
  else
    echo "run $i: did not reach the shop ($(grep -a "\[shoptest\]" "$LOG" | tail -1))"; FAILED=1
  fi
done
echo "logs: $TMP"
exit $FAILED
