#!/bin/bash
# Generate the v2 lifted code: SPEED2.EXE -> gen/<build> (then ./build.sh && ./link.sh)
#
#   tools/gen_v2.sh <SPEED2.EXE>                  generates into gen/all (European v1.2)
#                                                 or gen/na (North American v1.2),
#                                                 chosen by the file's SHA-256
#   GENOUT=<dir> tools/gen_v2.sh <SPEED2.EXE>     into another directory (for
#                                                 verification; the impargs.c step is skipped)
#
# v2 = v1 (base translator) + FLAGABI + X87OPT + RETEIP=0 + MEMARG=1 and the whole
# build with -fno-strict-aliasing (build.sh / link.sh).  Details and measurements:
# LIFTER_EFFICIENCY.md.  v1 archive: arsiv/v1/.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
EXE="${1:?usage: tools/gen_v2.sh <SPEED2.EXE>}"
PY="$ROOT/.venv/bin/python"

SHA="$(shasum -a 256 "$EXE" | cut -c1-64)"
case "$SHA" in
  8f6a9ae2c4cfa01181d2fd755d99c6f4b7103f60273908ea1de1e719dfe2a297)
    BUILD=eu; DEF=gen/all; WORK=out
    export XPATCH="${XPATCH:-tools/xpatch_eu.txt}" ;;   # tools/xpatch.py
  f9dd86c054878ce6276beb07c1fd61874f7a1e4bf1f241b084c65b73e24168a7)
    BUILD=na; DEF=gen/na; WORK=out/na
    export XPATCH="${XPATCH:-tools/xpatch_na.txt}" ;;   # tools/xpatch.py
  *) echo "unsupported SPEED2.EXE (sha256 $SHA); see README, \"Game versions\""; exit 1 ;;
esac
# The overrides (every sub_X_orig of the runtime, d3dx_hle.c's DX_WRAP table)
# and the hook sites (every HOOK_SITE(0x...) of the runtime) come from the
# runtime sources (tools/genlists.py), in European addresses mapped to the North
# American build, so the lift always matches the runtime; link.sh stops on a
# lift older than the runtime.  HOOKS=0x...,... adds sites (in this build's
# addresses), e.g. debug.c's debugging hooks.
"$PY" tools/genlists.py lint
OVR="$("$PY" tools/genlists.py overrides $BUILD)"
HK="$("$PY" tools/genlists.py hooks $BUILD)"
export HOOKS="$HK${HOOKS:+,$HOOKS}"
echo "overrides: $(echo "$OVR" | tr ',' '\n' | grep -c .), hooks: $(echo "$HK" | tr ',' '\n' | grep -c .)"
# Call targets the discovery missed are lifted too instead of becoming traps
# (genall.py LIFT_MISSING; NOCLOSURE=1 turns it off).
[ "${NOCLOSURE:-}" = 1 ] || export LIFT_MISSING=1
OUT="${GENOUT:-$DEF}"
mkdir -p "$WORK"
export RELOCS="$WORK/relocs.txt"
# x87 precision control (tools/lift.py, cpu.h X87R): on by default, so the game
# thread computes at PC=24 like on Windows; X87PC=0 lifts plain doubles.
export X87PC="${X87PC:-1}"
echo "build: $BUILD -> $OUT"

# Optional lift options, all off by default (measurements: LIFTER_EFFICIENCY.md
# section 7): JTSWITCH=1 switch jump tables as C switches, LREGS=1
# registers and flags in C locals (tools/lregs.py), FTOL2INL=1 the CRT's
# _ftol2 in place (cpu.h FTOL2_INL), INLINE_LIST=1 the hot functions of
# tools/inline_hot.txt inlined at their call sites (European addresses,
# mapped here for the North American build; INLINE_LIST=<file> another list).
export JTSWITCH="${JTSWITCH:-}" LREGS="${LREGS:-}" FTOL2INL="${FTOL2INL:-}"
case "${INLINE_LIST:-}" in
  ""|0) unset INLINE_LIST ;;
  *) IL="$INLINE_LIST"; [ "$IL" = 1 ] && IL=tools/inline_hot.txt
     if [ $BUILD = na ]; then
       mkdir -p "$WORK"
       "$PY" tools/addrmap.py list out/na/addrmap.json "$(grep -oE '^[0-9a-fA-F]{6,8}' "$IL" | paste -sd, -)" | tr ',' '\n' > "$WORK/inline_list.txt"
       IL="$WORK/inline_list.txt"
     fi
     export INLINE_LIST="$IL" ;;
esac
echo "options: X87PC=$X87PC JTSWITCH=${JTSWITCH:-0} LREGS=${LREGS:-0} FTOL2INL=${FTOL2INL:-0} INLINE_LIST=${INLINE_LIST:-0}"

"$PY" tools/reloc2.py "$EXE"                        # -> $RELOCS
"$PY" tools/flagabi.py "$EXE" "$WORK/flagabi.json"  # inter-function flag liveness (~30 s)
OVERRIDE=$OVR GENOUT="$OUT" FLAGABI="$WORK/flagabi.json" X87OPT=1 RETEIP=0 MEMARG=1 \
  "$PY" tools/genall.py "$EXE" 128
# what this lift was made with: link.sh compares the lists with the runtime's
{ "$PY" tools/genlists.py stamp $BUILD
  echo "extra hooks ${HOOKS#$HK}"
  echo "options X87PC=$X87PC JTSWITCH=${JTSWITCH:-0} LREGS=${LREGS:-0} FTOL2INL=${FTOL2INL:-0} INLINE_LIST=${INLINE_LIST:+$(basename "$INLINE_LIST")} NOCLOSURE=${NOCLOSURE:-0}"
} > "$OUT/lists.txt"
# argcount.py writes <GENOUT>/impargs.c; run it only for the real generation
if [ "$OUT" = "$DEF" ]; then GENOUT="$OUT" "$PY" tools/argcount.py "$EXE"; fi
echo "v2 generated: $OUT"

# Second guest module: EA's LAN server, server.dll next to SPEED2.EXE, lifted
# at the fixed guest base 0x00A00000 into gen/server, which both builds link
# (runtime/module.c maps the original file there and checks its SHA-256 against
# the one recorded in gen/server/modinfo.c).  Without server.dll a stub module
# is generated: the build links, and hosting a LAN game reports "unavailable".
if [ "$OUT" = "$DEF" ]; then
  SRV="$(dirname "$EXE")/server.dll"
  mkdir -p gen/server out/server && find gen/server/ -mindepth 1 -delete
  if [ -f "$SRV" ]; then
    "$PY" tools/prepare_module.py "$SRV" 0x00A00000 out/server gen/server srv_
    XPATCH= GENOUT=gen/server RELOCS=out/server/relocs.txt SEEDS=out/server/seeds.txt SYMPFX=srv_ \
      X87OPT=1 RETEIP=0 MEMARG=1 "$PY" tools/genall.py out/server/image.dll 8 > out/server/genall.log
    grep -E "functions  *:|traps \(|MISSING" out/server/genall.log | sed 's/^/  server.dll: /'
    RELOCS=out/server/relocs.txt IMPOUT=gen/server/impargs.c SYMPFX=srv_ STRICT=1 IMPDLL="$SRV" \
      "$PY" tools/argcount.py out/server/image.dll > out/server/argcount.log
    echo "server.dll generated: gen/server"
  else
    printf '#include "module.h"\nconst ModInfo g_srv_modinfo = { "server.dll", "", 0x00a00000u, 0, 0, 0, 0, 0, 0 };\n' > gen/server/modinfo.c
    printf '#include "cpu.h"\ntypedef void(*guest_fn)(CPU*);\nconst uint32_t g_srv_fn_count = 0;\nconst uint32_t g_srv_fn_addr[1] = {0};\nconst guest_fn g_srv_fn_ptr[1] = {0};\n' > gen/server/fntab.c
    printf '#include <stdint.h>\ntypedef struct { uint32_t iat; const char*dll; const char*name; int nargs; } ImpEnt;\nconst uint32_t g_srv_imp_count = 0;\nconst ImpEnt g_srv_imp[1] = {{0}};\n' > gen/server/impargs.c
    echo "no $SRV: stub gen/server (LAN hosting unavailable in this build)"
  fi
fi
