#!/bin/bash
# tests/input/run.sh <engine> <SPEED2.EXE> <scenario.seq> <home> <log> [VAR=value...]
# One silent game run (as tools/check.sh runs it) driven by a scenario of
# runtime/inputseq.m (NFSU2_INPUT_SEQ, one step per line, '#' comments).  HOME
# is the given folder (its .nfsu2_registry is the game's settings and the
# keyboard user maps) and saves go to <home>/saves, so a second scenario can
# go on from the first.  Shots (the scenario's "shot") land in
# <home>/Library/Logs/NFSU2.
BIN="$1"; EXE="$2"; SEQF="$3"; H="$4"; LOG="$5"; shift 5
mkdir -p "$H/saves" "$H/Library/Logs/NFSU2"
SEQ=$(grep -v '^[[:space:]]*#' "$SEQF" | sed 's/[[:space:]]*#.*//' | grep -v '^[[:space:]]*$' | paste -sd, -)
env -i HOME="$H" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
  FIXMAT=1 FIXMAT_MODE=3 NOMOVIES=1 SNDSYNC=1 GPUVS=1 WINDOW=1 ALARM=0 NOFOCUS=2 NOSOUND=1 NFSFULL=0 \
  MOUSEAT=5,5 FSFAKE=300 NFSRES=1280x720 NFSU2_SAVEDIR="$H/saves" NFSU2_INPUT_SEQ="$SEQ" "$@" \
  "$BIN" "$EXE" > "$LOG" 2>&1
