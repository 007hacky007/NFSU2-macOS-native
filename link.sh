#!/bin/bash
# Compile the runtime and link the binaries (the shards must already be compiled)
#
# TWO SEPARATE BUILDS are produced; the lifted shards are SHARED, only the runtime differs:
#   out/nfsu2_boot     original  -- the game's own look, a faithful port
#   out/nfsu2_hd_boot  HD        -- graphics improvements (runtime/enhance.*,
#                                   NFS_ENHANCED=1).  See GRAPHICS_RESEARCH.md
#   out/nfsu2_all      test suite (with the original runtime)
#
#   ./link.sh          both
#   ./link.sh orig     original only
#   ./link.sh hd       HD only
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
MCPU="${MCPU:-apple-m1}"; MINOS="${MINOS:-11.0}"   # see build.sh
OPT="${OPT:--O3 -mcpu=$MCPU -mmacosx-version-min=$MINOS -fno-strict-aliasing}"   # see build.sh
LDOPT="${LDOPT} -mmacosx-version-min=$MINOS"
WHICH="${1:-both}"
# Version tracking: the VERSION file at the repository root (v1 archive: arsiv/v1/).
# The runtime prints it at startup and in PERFLOG meta.txt, pack.sh puts it in the
# bundle's version info.
VERSION="$(tr -cd '0-9' < "$ROOT/VERSION" 2>/dev/null)"; VERSION="${VERSION:-0}"
case "$WHICH" in both|orig|hd) ;; *) echo "usage: ./link.sh [orig|hd]"; exit 1 ;; esac

CSRC="mem dispatch genexec win32 win32_ext com debug res fileio overrides d3dx_hle vsemu enhance perflog"
MSRC="metal audio bundle"
FW="-lm -framework Cocoa -framework Metal -framework QuartzCore -framework ImageIO -framework CoreGraphics -framework CoreServices -framework AudioToolbox"
SHARDS="out/obj/shard_*.o out/obj/fntab.o out/obj/stubs.o"

# $1 = object directory, $2 = NFS_ENHANCED value.  Files are compiled in parallel.
build_rt(){
  local od="$1" enh="$2" pids="" f
  mkdir -p "$od"
  for f in $CSRC; do
    [ -f "runtime/$f.c" ] || continue
    clang $OPT -DNFS_ENHANCED=$enh -DNFS_VERSION=$VERSION -Iruntime -Igen/all -c -o "$od/$f.o" "runtime/$f.c" & pids="$pids $!"
  done
  for f in $MSRC; do
    clang $OPT -DNFS_ENHANCED=$enh -DNFS_VERSION=$VERSION -fobjc-arc -Iruntime -Igen/all -c -o "$od/$f.o" "runtime/$f.m" & pids="$pids $!"
  done
  clang $OPT -Iruntime -Igen/all -c -o "$od/impargs.o" gen/all/impargs.c & pids="$pids $!"
  clang $OPT -DNFS_ENHANCED=$enh -Iruntime -Igen/all -c -o "$od/boot.o" tests/boot.c & pids="$pids $!"
  for p in $pids; do wait "$p" || { echo "compile error ($od)"; return 1; }; done
}
rt_objs(){ local od="$1" f o=""
  for f in $CSRC $MSRC impargs; do [ -f "$od/$f.o" ] && o="$o $od/$f.o"; done
  echo "$o"; }

if [ "$WHICH" != hd ]; then
  build_rt out/obj 0
  rm -f out/obj/enhance.o            # not part of the original build
  RT="$(rt_objs out/obj)"
  clang $OPT -Iruntime -Igen/all -c -o out/obj/main.o tests/main_all.c
  clang ${LDOPT} -o out/nfsu2_boot $SHARDS $RT out/obj/boot.o $FW
  clang ${LDOPT} -o out/nfsu2_all  $SHARDS $RT out/obj/main.o $FW
  echo "link OK: original (out/nfsu2_boot)"
fi
if [ "$WHICH" != orig ]; then
  build_rt out/obj_hd 1
  RT="$(rt_objs out/obj_hd)"
  clang ${LDOPT} -o out/nfsu2_hd_boot $SHARDS $RT out/obj_hd/boot.o $FW
  echo "link OK: HD (out/nfsu2_hd_boot)"
fi

# ISA semantic tests
# DON'T PASS SILENTLY if the generator fails.  The error used to be swallowed:
# while isatest.py crashed for weeks the old gen/isatest.c got compiled and said
# "439 passed", i.e. the tests never exercised the current lifter.  Now the stale
# binary is deleted so ./run.sh test fails visibly.
if "$ROOT/.venv/bin/python" "$ROOT/tools/isatest.py" >/dev/null \
   && clang -O1 -Wno-unused-label -Iruntime -o out/isatest gen/isatest.c runtime/mem.c -lm; then
  :
else
  rm -f out/isatest
  echo "WARNING: ISA tests could not be generated/compiled -- out/isatest deleted" >&2
fi
