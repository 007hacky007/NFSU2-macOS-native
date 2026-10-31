#!/bin/bash
# One scripted test run of the game (runtime/autotest.c).
#   tools/autorun.sh <outdir> [VAR=value ...]
# Runs out/${NFSU2_BIN:-nfsu2_boot} (nfsu2_na_boot for the North American
# SPEED2.EXE) in a window that never shows or takes the focus (NOFOCUS=2),
# silent, against $NFSU2_DATA (the game folder or its SPEED2.EXE).  The
# VAR=value arguments are exported first, so they count like the environment
# for everything below (NFSU2_INPUT_SCRIPT, NFSU2_SAVE_SEED, NFSU2_BIN ...).
# Everything goes to <outdir>: log.txt (stdout+stderr), frame dumps (DUMPDIR),
# home/ (the run's own HOME: ~/.nfsu2_registry, ~/Library; copied from
# $NFSU2_REGFILE_SEED if given), save/ (NFSU2_SAVEDIR; NFSU2_SAVE_SEED=<dir>
# copies an existing save tree in first).
# Network: off unless the test selects NFSU2_NET=loopback or vlan:<hub>, or
# NFSU2_ROAM=1; a test run can never use the real network (NFSU2_NET_HARNESS=1
# makes the Winsock HLE refuse it, NFSU2_ROAM_HARNESS=1 keeps free roam on
# loopback, runtime/nettest.h), and a run with any network mode is wrapped in
# the loopback-only sandbox profile tests/net/loopback-only.sb (NFSU2_SANDBOX=0
# skips the wrapper; a caller already inside it sets NFSU2_SANDBOXED=1).
# Ported from th0mk's nfsu2-web tools/autorun.sh (MIT).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: tools/autorun.sh <outdir> [VAR=value ...]}"; shift
for kv in "$@"; do export "$kv"; done
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
DATA="${NFSU2_DATA:-$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2}"
EXE="$DATA"; [ -d "$DATA" ] && EXE="$DATA/SPEED2.EXE"
[ -f "$EXE" ] || { echo "autorun: no SPEED2.EXE at $DATA (NFSU2_DATA)"; exit 2; }
BIN="$ROOT/out/${NFSU2_BIN:-nfsu2_boot}"
[ -x "$BIN" ] || { echo "autorun: no $BIN (./build.sh && ./link.sh)"; exit 2; }
# the run's own home: settings (~/.nfsu2_registry), logs and Application Support
# are never the player's
export HOME="$OUT/home"
mkdir -p "$HOME/Library/Logs/NFSU2"
[ -n "$NFSU2_REGFILE_SEED" ] && [ ! -f "$HOME/.nfsu2_registry" ] && cp "$NFSU2_REGFILE_SEED" "$HOME/.nfsu2_registry"
export FIXMAT="${FIXMAT:-1}" FIXMAT_MODE="${FIXMAT_MODE:-3}" NOMOVIES="${NOMOVIES:-1}"
export SNDSYNC="${SNDSYNC:-1}" GPUVS="${GPUVS:-1}" FSFAKE="${FSFAKE:-300}"
export WINDOW="${WINDOW-1}" NOFOCUS="${NOFOCUS-2}" ALARM="${ALARM:-120}"
# Discord presence is OFF in test runs: the real Discord app may be running on
# this Mac and must never see a test.  A test that wants it sets
# NFSU2_DISCORD=1 together with NFSU2_DISCORD_IPC=<mock socket>
# (tools/mock_discord.py); without the override path it stays off.
export NFSU2_DISCORD="${NFSU2_DISCORD:-0}"
if [ "$NFSU2_DISCORD" != 0 ] && [ -z "$NFSU2_DISCORD_IPC" ]; then
  echo "autorun: NFSU2_DISCORD on without NFSU2_DISCORD_IPC (a mock socket); forcing it off" >&2
  export NFSU2_DISCORD=0
fi
# silent (the mixer still runs, audio.m); NFSU2_MUTE=0 to listen
export NFSU2_MUTE="${NFSU2_MUTE:-1}"
# windowed, whatever the player last chose with Cmd-F
export NFSFULL="${NFSFULL:-0}"
export DUMPDIR="${DUMPDIR:-$OUT}"
export NFSU2_SAVEDIR="${NFSU2_SAVEDIR:-$OUT/save}"
mkdir -p "$NFSU2_SAVEDIR"
[ -n "$NFSU2_SAVE_SEED" ] && cp -R "$NFSU2_SAVE_SEED"/. "$NFSU2_SAVEDIR"/
# Network: LAN play (winsock.c) and free-roam multiplayer (roam_bsd.c).  A
# test run is always the harness for both: LAN off unless the test selects
# loopback or the virtual LAN, never the real LAN; free roam on loopback only,
# no LAN discovery.  Any networked run is inside the loopback-only sandbox
# profile (IP beyond 127.0.0.1 refused by the kernel; AF_UNIX, the vlan hub,
# allowed).
export NFSU2_NET="${NFSU2_NET:-off}"
export NFSU2_NET_HARNESS=1 NFSU2_ROAM_HARNESS=1
SBX=()
if { [ "$NFSU2_NET" != off ] || [ "${NFSU2_ROAM:-0}" != 0 ]; } && [ "${NFSU2_SANDBOX:-1}" != 0 ] \
   && [ "${NFSU2_SANDBOXED:-0}" != 1 ] && [ -x /usr/bin/sandbox-exec ]; then
  SBX=(/usr/bin/sandbox-exec -f "$ROOT/tests/net/loopback-only.sb")
fi
# SIP drops DYLD_* variables when sandbox-exec (a system binary) starts, so
# an interposer such as tools/writewatch.c (DYLD_INSERT_LIBRARIES=... as a
# VAR=value argument) reaches the game through env, inside the sandbox
[ ${#SBX[@]} -gt 0 ] && [ -n "${DYLD_INSERT_LIBRARIES:-}" ] && SBX+=(/usr/bin/env "DYLD_INSERT_LIBRARIES=$DYLD_INSERT_LIBRARIES")
cd "$OUT"
start=$(date +%s)
"${SBX[@]}" "$BIN" "$EXE" > "$OUT/log.txt" 2>&1
rc=$?
echo "exit=$rc wall=$(( $(date +%s) - start ))s log=$OUT/log.txt"
exit $rc
