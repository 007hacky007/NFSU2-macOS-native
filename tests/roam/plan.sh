#!/bin/bash
# One game instance and stand-in friends (tests/roam_fakepeer.c) that join
# and leave on a timed plan, loopback only.  Game-level: needs a built
# engine and a game folder (NFSU2_DATA=<folder with SPEED2.EXE>).
#   tests/roam/plan.sh <outdir> <timeout-s> <script> <baseport> <nfake> <plan.sh|-> [VAR=value ...]
# The game runs through tools/autorun.sh (NOFOCUS=2, NFSU2_TIMEOUT, ALARM,
# the loopback-only sandbox tests/net/loopback-only.sb, NFSU2_ROAM_HARNESS=1)
# on 127.0.0.1:<baseport> with the <nfake> stand-in ports <baseport>+10,
# +11, ... as configured peers; <script> is tests/scripts/<script> or an
# absolute path (an NFSU2_INPUT_SCRIPT) and must log ROAM_INROAM once it is in
# free roam.  Then <plan.sh> (tests/roam/plan_*.sh) is sourced in a
# background shell (bash); it starts stand-ins with
#   fp <k> <roam_fakepeer arguments...>     on port <baseport>+10+k, logging to <outdir>/fake<k>.log
# (each call runs in the foreground: put "( sleep S; fp ... ) &" in the
# plan).  $OUT is the outdir.  ROAM_FAKEPEER=<binary> replaces the stand-in
# built into <outdir>; NFSU2_BIN picks the engine (nfsu2_na_boot for the
# North American SPEED2.EXE).  Only processes started here are ever
# stopped, by PID.  Any "BLOCKED" line (a packet that would have left the
# Mac) fails the run.
# Ported from th0mk's nfsu2-web tools/roam_plan.sh (MIT).
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?usage: tests/roam/plan.sh <outdir> <timeout-s> <script> <baseport> <nfake> <plan.sh|-> [VAR=value ...]}"
TMO="${2:?timeout}"; SCRIPT="${3:?script}"; BASE="${4:?baseport}"; NF="${5:?nfake}"; PLAN="${6:?plan}"; shift 6
[ -f "${NFSU2_DATA:-}/SPEED2.EXE" ] || { echo "tests/roam/plan.sh: set NFSU2_DATA to the game folder"; exit 2; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"; d="$OUT/game"; rm -rf "$d"; mkdir -p "$d"
FP="${ROAM_FAKEPEER:-}"
if [ -z "$FP" ]; then
  FP="$OUT/roam_fakepeer"
  clang -O1 -fobjc-arc -I"$ROOT/runtime" -c "$ROOT/runtime/net_native.m" -o "$OUT/net_native.o" &&
  clang -O2 -ffp-contract=off -I"$ROOT/runtime" -o "$FP" "$ROOT/tests/roam_fakepeer.c" "$ROOT/runtime/roam_core.c" \
    "$ROOT/runtime/roam_bsd.c" "$OUT/net_native.o" -framework Foundation || { echo "tests/roam/plan.sh: cannot build roam_fakepeer"; exit 1; }
fi
[ "$PLAN" = "-" ] || [ "${PLAN#/}" != "$PLAN" ] || PLAN="$(pwd)/$PLAN"
[ "${SCRIPT#/}" != "$SCRIPT" ] || SCRIPT="$ROOT/tests/scripts/$SCRIPT"
peers=""; k=0; while [ "$k" -lt "$NF" ]; do peers="${peers:+$peers,}127.0.0.1:$((BASE + 10 + k))"; k=$((k + 1)); done
env "$@" "$ROOT/tools/autorun.sh" "$d" NOFOCUS=2 NFSU2_TIMEOUT="$TMO" ALARM="$TMO" \
    NFSU2_FNG_LOG=1 NFSU2_STATUS_EVERY=1200 NFSU2_DUMP_SCALE=0.5 \
    NFSU2_ROAM=1 NFSU2_ROAM_PORT="$BASE" NFSU2_ROAM_PEERS="$peers" NFSU2_ROAM_NAME="${ROAM_NAME:-Viewer}" ROAM_PROFILE="${ROAM_PROFILE:-VIEWER}" \
    NFSU2_ROAM_POSELOG="$d/pose.csv" NFSU2_INPUT_SCRIPT="$SCRIPT" "$@" \
    > "$d.run" 2>&1 < /dev/null &
gpid=$!
echo "roam plan: game (autorun pid $gpid) on 127.0.0.1:$BASE, peers $peers, script $SCRIPT"
SB=(); [ -x /usr/bin/sandbox-exec ] && SB=(/usr/bin/sandbox-exec -f "$ROOT/tests/net/loopback-only.sb")
fp(){ local i="$1"; shift
      echo "== $(date +%T) fp$i $*" >> "$OUT/fake$i.log"
      "${SB[@]}" "$FP" --port $((BASE + 10 + i)) --peer "127.0.0.1:$BASE" "$@" >> "$OUT/fake$i.log" 2>&1; }
ppid_plan=""
if [ "$PLAN" != "-" ]; then
  ( while kill -0 "$gpid" 2>/dev/null && ! grep -q 'ROAM_INROAM' "$d/log.txt" 2>/dev/null; do sleep 1; done
    echo "roam plan: game in free roam at $(date +%T)" >> "$OUT/plan.log"
    # shellcheck disable=SC1090
    kill -0 "$gpid" 2>/dev/null && . "$PLAN"
    wait
    echo "roam plan: plan done at $(date +%T)" >> "$OUT/plan.log" ) &
  ppid_plan=$!
fi
deadline=$(( $(date +%s) + TMO + 60 ))
while kill -0 "$gpid" 2>/dev/null; do
  if [ "$(date +%s)" -gt "$deadline" ]; then g=$(pgrep -P "$gpid" | head -1); [ -n "$g" ] && kill "$g"; kill "$gpid"; break; fi
  sleep 2
done
wait "$gpid"; rc=$?
# the plan and the stand-ins it started (only our own PIDs)
killtree(){ local c; for c in $(pgrep -P "$1" 2>/dev/null); do killtree "$c"; done; kill "$1" 2>/dev/null; }
[ -n "$ppid_plan" ] && killtree "$ppid_plan"
wait 2>/dev/null
echo "roam plan: game exit=$rc ($(tail -n 1 "$d.run"))"
# no packet left the Mac: any BLOCKED line is a failure
if grep -l "BLOCKED" "$d/log.txt" "$OUT"/fake*.log >/dev/null 2>&1; then echo "roam plan: BLOCKED lines found"; exit 1; fi
exit $rc
