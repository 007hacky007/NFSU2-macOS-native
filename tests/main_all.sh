#!/bin/bash
# The function and runtime checks (tests/main_all.c) on both builds:
# out/nfsu2_all with the European SPEED2.EXE, out/nfsu2_na_all with the North
# American one (./link.sh and BUILD=na ./link.sh build them).
#   EU_EXE=<SPEED2.EXE> NA_EXE=<SPEED2.EXE> tests/main_all.sh
set -u
cd "$(dirname "$0")/.."
fail=0; ran=0
for b in eu na; do
  if [ $b = eu ]; then BIN=out/nfsu2_all; EXE="${EU_EXE:-}"; else BIN=out/nfsu2_na_all; EXE="${NA_EXE:-}"; fi
  [ -n "$EXE" ] || continue
  [ -x "$BIN" ] || { echo "== $b: $BIN missing (link.sh)"; fail=1; continue; }
  ran=1
  out=$("$BIN" "$EXE" 2>/dev/null); rc=$?
  r=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g')
  echo "$r" | grep -E "FAIL|differs" | grep -v "PASS: " | head -20
  echo "== $b: $(echo "$r" | grep -E "PASS: [0-9]+ +FAIL: [0-9]+" | tr -s ' ') (exit $rc)"
  [ $rc = 0 ] || fail=1
done
[ $ran = 1 ] || { echo "usage: EU_EXE=<SPEED2.EXE> NA_EXE=<SPEED2.EXE> tests/main_all.sh"; exit 2; }
exit $fail
