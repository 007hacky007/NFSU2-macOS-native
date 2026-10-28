#!/bin/bash
# Scripted integrity checks with isolated saves and registry files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
case "${1:-both}" in
  both) BUILDS="orig hd" ;;
  orig|hd) BUILDS="$1" ;;
  *) echo "usage: tools/check.sh [orig|hd]"; exit 2 ;;
esac
DATA="${NFSU2_DATA:-$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2}"
[ ! -f "$DATA" ] || DATA="$(dirname "$DATA")"
for build in $BUILDS; do
  BIN=nfsu2_boot
  [ "$build" != hd ] || BIN=nfsu2_hd_boot
  NFSU2_DATA="$DATA" NFSU2_BIN="$BIN" "$ROOT/tests/run_suite.sh" "$ROOT/out/integrity/$build" quickrace
done
