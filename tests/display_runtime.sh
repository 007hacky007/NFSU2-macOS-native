#!/bin/bash
# tests/display_runtime.sh -- the engine's display and lifecycle options on the real
# game (runtime/display.c, language.c, lifecycle.c), in the spirit of the old fork's
# tests/scripts/ws_boot_movies.txt: the boot movies with NFSU2_MOVIE=fit|fill|stretch
# (a frame's left edge black only with fit), the PSA's subtitles with
# NFSU2_SUBTITLES=1 (needs LANGPACKS/english, the launcher's English subtitles pack),
# the Screen row at NFSU2_RENDER=scale:0.5, and a background pause (BLURFAKE) and a
# quit through the game's own shutdown (QUITFAKE) in a Quick Race.
#
#   NFSU2_DATA=<game folder or SPEED2.EXE> tests/display_runtime.sh [<engine binary>]
#
# Invisible and silent like tools/check.sh; settings restored after each run.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/out/nfsu2_boot}"
EXE="${NFSU2_DATA:?NFSU2_DATA: the game folder or SPEED2.EXE}"; [ -d "$EXE" ] && EXE="$EXE/SPEED2.EXE"
T="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_display.XXXXXX")"
REG="$HOME/.nfsu2_registry"; [ -f "$REG" ] && cp "$REG" "$T/registry.backup"
restore(){ if [ -f "$T/registry.backup" ]; then cp "$T/registry.backup" "$REG"; else rm -f "$REG"; fi; }
trap 'restore; rm -rf "$T"' EXIT
cat > "$T/edge.swift" <<'SWIFT'
import Foundation
import ImageIO
// edge <png>: mean brightness (0-255) of the leftmost 4% of the picture's middle rows
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
var sum = 0, n = 0
for y in (h / 4)..<(h * 3 / 4) { for x in 0..<max(1, w / 25) { let o = (y * w + x) * 4; sum += Int(px[o]) + Int(px[o + 1]) + Int(px[o + 2]); n += 3 } }
print(sum / max(n, 1))
SWIFT
swiftc -O -o "$T/edge" "$T/edge.swift" || { echo "FAIL: swiftc"; exit 1; }
fails=0
check(){ if [ "$2" = 1 ]; then echo "  PASS  $1  $3"; else echo "  FAIL  $1  $3"; fails=$((fails+1)); fi; }
run(){   # $1 name, then VAR=value...; SEED: the registry the run starts with
  local name="$1"; shift
  mkdir -p "$T/$name/saves"
  printf "${SEED:-d NotFirstTime=1\\n}" > "$REG"
  env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" FIXMAT=1 FIXMAT_MODE=3 SNDSYNC=1 GPUVS=1 WINDOW=1 \
    ALARM=0 NOFOCUS=2 NOSOUND=1 NFSFULL=0 MOUSEAT=5,5 FSFAKE=300 NFSU2_SAVEDIR="$T/$name/saves" DUMPDIR="$T/$name" "$@" \
    "$BIN" "$EXE" > "$T/$name.log" 2>&1
  restore
}
for m in fit fill stretch; do
  run "$m" NFSU2_MOVIE=$m NFSU2_LANGUAGE=english NFSU2_SUBTITLES=1 QUITFRAMES=1600 DUMPFRAME=250,1500
  e=$("$T/edge" "$T/$m/nfsu2_frame_0250.png" 2>/dev/null || echo -1)
  if [ $m = fit ]; then check "movie $m: black bars at the sides" "$([ "$e" -ge 0 ] && [ "$e" -lt 6 ] && echo 1 || echo 0)" "edge $e"
  else check "movie $m: picture to the edge" "$([ "$e" -ge 6 ] && echo 1 || echo 0)" "edge $e"
       check "movie $m: quads reframed" "$(grep -a -q "display: movie quad" "$T/$m.log" && echo 1 || echo 0)" ""; fi
  check "movie $m: subtitles for the PSA" "$(grep -a -q "this movie gets its subtitles" "$T/$m.log" && echo 1 || echo 0)" ""
done
SEED='d NotFirstTime=1\nd g_RacingResolution=3\n'
run scale NOMOVIES=1 NFSU2_RENDER=scale:0.5 QUITFRAMES=200
rs=$(grep -a -m1 "menu row 4 ->" "$T/scale.log" | sed -E 's/.*-> ([0-9]+)x.*/\1/')
run full NOMOVIES=1 QUITFRAMES=200
SEED=
rf=$(grep -a -m1 "menu row 4 ->" "$T/full.log" | sed -E 's/.*-> ([0-9]+)x.*/\1/')
check "resolution scale 50%: the Screen row at half the width" "$([ -n "$rs" ] && [ -n "$rf" ] && [ $((rs * 2)) -ge $((rf - 4)) ] && [ $((rs * 2)) -le $((rf + 4)) ] && echo 1 || echo 0)" "$rs of $rf"
run life NOMOVIES=1 NFSRES=1920x1080 AUTOSEQ=1000:0x1C,1350:0x1C,1750:0x1C,1950:0x1C,2150:0x1C,2350:0x1C,2550:0x1C,2750:0x1C,2950:0x1C \
    BLURFAKE=4400:2000 QUITFAKE=5000 QUITFRAMES=9000
check "background: the game told it is inactive and paused" "$(grep -a -q "told it is inactive" "$T/life.log" && grep -a -q "resumes after" "$T/life.log" && echo 1 || echo 0)" \
      "$(grep -a -o 'resumes after.*' "$T/life.log" | head -1)"
check "quit: WM_CLOSE, the game's own ExitProcess" "$(grep -a -q "WM_CLOSE to the game" "$T/life.log" && grep -a -q "the game exited (code 0) after the quit request" "$T/life.log" && echo 1 || echo 0)" ""
[ $fails = 0 ] && echo "RESULT: all passed" || echo "RESULT: $fails failed"
exit $fails
