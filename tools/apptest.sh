#!/bin/bash
# Test run of the packaged app's engine (out/NFSU2.app/Contents/MacOS/
# nfsu2-engine, or NFSU2_ENGINE=nfsu2-engine-na / -hd / -na-hd), as the
# launcher starts it, but with the run's own HOME, so the player's
# ~/.nfsu2_registry, ~/Library/Application Support/NFSU2* and
# ~/Library/Logs/NFSU2 are never touched, and a fully transparent window
# (NOFOCUS=2) that never takes the focus.  Discord presence stays off unless
# NFSU2_DISCORD_IPC names a mock.
#   tools/apptest.sh <rundir> [VAR=value ...]
# <rundir>/home is HOME (the engine's log is home/Library/Logs/NFSU2/nfsu2.log);
# frame dumps go to <rundir>.  The game is NFSU2_DATA (folder or SPEED2.EXE),
# else the one the app finds itself.
# Ported from th0mk's nfsu2-web tools/apptest.sh (MIT).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: tools/apptest.sh <rundir> [VAR=value ...]}"; shift
mkdir -p "$OUT/home"; OUT="$(cd "$OUT" && pwd)"
export NOFOCUS="${NOFOCUS:-2}" NFSU2_TIMEOUT="${NFSU2_TIMEOUT:-120}" DUMPDIR="${DUMPDIR:-$OUT}"
# no network unless the test selects one; never the real network (tools/autorun.sh)
export NFSU2_NET="${NFSU2_NET:-off}"
export NFSU2_MUTE="${NFSU2_MUTE:-1}" NFSFULL="${NFSFULL:-0}"
for kv in "$@"; do export "$kv"; done
export HOME="$OUT/home"
if [ -z "$NFSU2_DISCORD_IPC" ]; then
  [ -n "$NFSU2_DISCORD" ] && [ "$NFSU2_DISCORD" != 0 ] && \
    echo "apptest: NFSU2_DISCORD on without NFSU2_DISCORD_IPC (a mock socket); forcing it off" >&2
  export NFSU2_DISCORD=0
fi
# every app test is the harness for LAN play and free roam (never the real
# network, free roam on loopback only) inside the loopback-only sandbox
export NFSU2_NET_HARNESS=1 NFSU2_ROAM_HARNESS=1
case "$NFSU2_NET" in off|loopback|vlan:*) ;; *) echo "apptest: NFSU2_NET=$NFSU2_NET: test runs use off, loopback or vlan:<hub>" >&2; exit 2 ;; esac
APPBIN="${NFSU2_APP:-$ROOT/out/NFSU2.app}/Contents/MacOS/${NFSU2_ENGINE:-nfsu2-engine}"
[ -x "$APPBIN" ] || { echo "no $APPBIN (./pack.sh)"; exit 1; }
EXE=""
if [ -n "$NFSU2_DATA" ]; then EXE="$NFSU2_DATA"; [ -d "$EXE" ] && EXE="$EXE/SPEED2.EXE"; fi
SBX=()
if [ "${NFSU2_SANDBOX:-1}" != 0 ] && [ "${NFSU2_SANDBOXED:-0}" != 1 ] && [ -x /usr/bin/sandbox-exec ]; then
  SBX=(/usr/bin/sandbox-exec -f "$ROOT/tests/net/loopback-only.sb")
fi
# SIP drops DYLD_* variables when sandbox-exec (a system binary) starts: pass
# an interposer (tools/writewatch.c) through env, inside the sandbox
[ ${#SBX[@]} -gt 0 ] && [ -n "${DYLD_INSERT_LIBRARIES:-}" ] && SBX+=(/usr/bin/env "DYLD_INSERT_LIBRARIES=$DYLD_INSERT_LIBRARIES")
start=$(date +%s)
"${SBX[@]}" "$APPBIN" ${EXE:+"$EXE"} > "$OUT/stdout.txt" 2>&1
rc=$?
echo "exit=$rc wall=$(( $(date +%s) - start ))s log=$OUT/home/Library/Logs/NFSU2/nfsu2.log"
exit $rc
