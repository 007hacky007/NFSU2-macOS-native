#!/bin/bash
# Generate the v2 lifted code: SPEED2.EXE -> gen/all (then ./build.sh && ./link.sh)
#
#   tools/gen_v2.sh <SPEED2.EXE>                  generates into gen/all
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
OUT="${GENOUT:-gen/all}"

# The OVERRIDE list must MATCH runtime/overrides.c + runtime/d3dx_hle.c
# (see PROJECT.md "Commands", D3DX_HLE.md "Regeneration").
OVR=60fab0,61e390,61f130,5c7ed0,50d510,65ae35,6623ea,66aa3f,66ace2,6691b1,669296,664a2f,663a42,688e89,663275,662edc,660a52,668e0d,664792,66ac27,65addb,65acf5,66d13a,66d303,66d7e9,66e8a9,66f501,66ca38,65ab24,67193e,66056c,65cf44,640c12,668cd0,65ccd8

"$PY" tools/reloc2.py "$EXE"                    # -> out/relocs.txt
"$PY" tools/flagabi.py "$EXE" out/flagabi.json  # inter-function flag liveness (~30 s)
OVERRIDE=$OVR GENOUT="$OUT" FLAGABI=out/flagabi.json X87OPT=1 RETEIP=0 MEMARG=1 \
  "$PY" tools/genall.py "$EXE" 128
# argcount.py always writes gen/all/impargs.c; run it only for the real generation
if [ "$OUT" = gen/all ]; then "$PY" tools/argcount.py "$EXE"; fi
echo "v2 generated: $OUT"
