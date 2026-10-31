#!/bin/bash
# Game-level Discord Rich Presence scenarios (runtime/discord.c), on the European
# and the North American build.
#   tests/discord_suite.sh <outdir> [eu|na|both] [race gamequit latekill malformed absent]
#
# Every run talks to tools/mock_discord.py through NFSU2_DISCORD_IPC=<socket in a
# private temp dir>, never to the Discord app; TMPDIR and XDG_RUNTIME_DIR point at
# that dir too, HOME at a private one (the game's registry).  One game at a time.
# The game is driven with AUTOSEQ (the keys of tools/check.sh's Quick Race) and
# ends with QUITFRAMES (a clean quit).  Scenarios:
#   race       menus -> loading -> Circuit (grid, laps) -> pause -> race -> clean
#              quit: presence texts in order, timers, racer count, the large
#              image (NFSU2_DISCORD_LARGE_IMAGE) on every presence, clear + CLOSE
#   gamequit   the main menu's own Quit Game (q, Left, Enter: ExitProcess): the
#              presence is cleared and the connection closed
#   latekill   Discord absent at start, appears mid-race (connects); then killed
#              mid-race (game unaffected) and started again (reconnects)
#   malformed  Discord answers garbage, never READY, is slow, errors, closes at
#              once, then behaves: no hang, no crash, presence shown in the end
#   absent     Discord never there: baseline frame pacing for the same race
# Needs out/nfsu2_boot (EU) and out/nfsu2_na_boot (NA); the games from
# NFSU2_EU_EXE / NFSU2_NA_EXE (defaults: the folders next to this checkout).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: tests/discord_suite.sh <outdir> [eu|na|both] [scenario...]}"; shift
BUILDS="both"; case "${1:-}" in eu|na|both) BUILDS="$1"; shift ;; esac
[ "$BUILDS" = both ] && BUILDS="eu na"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
SCEN="${*:-race gamequit latekill malformed absent}"
EU_EXE="${NFSU2_EU_EXE:-$ROOT/../NFSU2-EU-game/SPEED2.EXE}"
NA_EXE="${NFSU2_NA_EXE:-$ROOT/Need for Speed Underground 2 - Clean Edition/Need for Speed Underground 2/SPEED2.EXE}"
SOCKDIR="$(mktemp -d /tmp/nfsu2-dsuite.XXXXXX)"            # short: sun_path < 104 bytes
MOCK="/usr/bin/python3 -I $ROOT/tools/mock_discord.py"
# tools/check.sh's Quick Race: Enter through the menus, accelerate from 4700
SEQ="1000:0x1C,1350:0x1C,1700:0x1C,2050:0x1C,2400:0x1C,2750:0x1C,3100:0x1C,3700:0x1C,4000:0x1C,4700:0xC8:5000"
MPID=""; GPID=""
cleanup(){ [ -n "$MPID" ] && kill "$MPID" 2>/dev/null; [ -n "$GPID" ] && kill "$GPID" 2>/dev/null; rm -rf "$SOCKDIR"; }
trap cleanup EXIT

now(){ /usr/bin/python3 -c 'import time; print("%.3f" % time.time())'; }
ev(){ echo "$(now) $*" >> "$D/events.txt"; echo "  [$(date +%T)] $*"; }
mock_start(){   # mode
  $MOCK "$SOCK" --log "$D/frames.jsonl" --mode "$1" --ping 5 > /dev/null 2>&1 &
  MPID=$!
  for _ in $(seq 100); do [ -S "$SOCK" ] && break; sleep 0.05; done
  ev "mock $1 started"
}
mock_kill(){    # signal
  [ -n "$MPID" ] && kill "-$1" "$MPID" 2>/dev/null && wait "$MPID" 2>/dev/null
  MPID=""; rm -f "$SOCK"; ev "mock killed ($1)"
}
game_start(){   # seq quitframes [VAR=val...]
  local seq="$1" q="$2"; shift 2
  mkdir -p "$D/home" "$D/saves"
  env -i HOME="$D/home" PATH="$PATH" TMPDIR="$SOCKDIR" XDG_RUNTIME_DIR="$SOCKDIR" \
    FIXMAT=1 FIXMAT_MODE=3 NOMOVIES=1 SNDSYNC=1 GPUVS=1 WINDOW=1 ALARM=0 NOFOCUS=2 NOSOUND=1 NFSFULL=0 \
    MOUSEAT=5,5 FSFAKE=300 NFSU2_SAVEDIR="$D/saves" AUTOSEQ="$seq" QUITFRAMES="$q" \
    NFSU2_DISCORD=1 NFSU2_DISCORD_IPC="$SOCK" NFSU2_DISCORD_LOG=1 "$@" \
    "$BIN" "$EXE" > "$D/log.txt" 2>&1 < /dev/null &
  GPID=$!
  ev "game started"
}
game_wait(){ wait "$GPID"; local rc=$?; GPID=""; ev "game exited ($rc)"; return $rc; }
wait_until(){   # file regex timeout_s: a line matching in the file (or the game ended)
  local t=0
  while [ $t -lt $(( $3 * 10 )) ]; do
    LC_ALL=C grep -aqE "$2" "$1" 2>/dev/null && return 0
    [ -n "$GPID" ] && ! kill -0 "$GPID" 2>/dev/null && return 1
    sleep 0.1; t=$((t + 1))
  done
  return 1
}
wait_count(){   # regex count timeout_s  (mock log)
  local t=0
  while [ $t -lt $(( $3 * 10 )) ]; do
    [ "$(grep -cE "$1" "$D/frames.jsonl" 2>/dev/null)" -ge "$2" ] && return 0
    [ -n "$GPID" ] && ! kill -0 "$GPID" 2>/dev/null && return 1
    sleep 0.1; t=$((t + 1))
  done
  return 1
}
check(){        # case
  /usr/bin/python3 -I "$ROOT/tests/discord_check.py" "$1" "$D/frames.jsonl" "$D/log.txt" "$D/events.txt" > "$D/check.txt" 2>&1
  local rc=$?
  grep -v "^INFO   t=" "$D/check.txt" | sed 's/^/  /'
  return $rc
}

pass=0; fail=0
for b in $BUILDS; do
  if [ "$b" = na ]; then BIN="$ROOT/out/nfsu2_na_boot"; EXE="$NA_EXE"; else BIN="$ROOT/out/nfsu2_boot"; EXE="$EU_EXE"; fi
  [ -x "$BIN" ] && [ -f "$EXE" ] || { echo "== $b: $BIN or $EXE missing"; fail=$((fail+1)); continue; }
  for name in $SCEN; do
    D="$OUT/$b/$name"; rm -rf "$D"; mkdir -p "$D"; : > "$D/events.txt"; : > "$D/frames.jsonl"
    SOCK="$SOCKDIR/$b-$name.sock"
    echo "== $b $name"
    ok=1
    case "$name" in
    race)
      mock_start normal
      game_start "$SEQ,5600:0x01,6000:0x01" 7400 NFSU2_DISCORD_LARGE_IMAGE=https://example.com/nfsu2.png   # Esc: pause, Esc: on again
      game_wait || ok=0
      sleep 0.5; mock_kill TERM ;;
    gamequit)
      mock_start normal
      # main menu: q (typed: the front end reads it as a character), Left ("Quit Game"), Enter
      game_start "1000:0x1C,1350:0x1C,2450:0xCB,2600:0x1C" 4000 AUTOTEXT=2300:q
      game_wait
      ev "quit"
      sleep 0.5; mock_kill TERM ;;
    latekill)
      game_start "$SEQ" 10500
      wait_until "$D/log.txt" '\[discord\] state: Circuit' 240 || ok=0
      ev "race"
      sleep 8
      mock_start normal                                      # Discord appears mid-race
      wait_until "$D/frames.jsonl" '"state": "Lap ' 40 || { ok=0; echo "  no race presence after Discord appeared"; }
      ev "race presence shown"
      sleep 10
      mock_kill KILL                                         # Discord dies mid-race
      sleep 15
      mock_start normal                                      # ... and comes back
      wait_count '"dir": "in", "op": 0' 2 40 || { ok=0; echo "  no reconnection"; }
      ev "reconnected"
      game_wait || ok=0
      sleep 0.5; mock_kill TERM ;;
    malformed)
      game_start "$SEQ" 12500
      raced=0
      for m in garbage noready slow close error; do
        mock_start "$m"
        for _ in $(seq 20); do
          sleep 1
          [ $raced -eq 0 ] && LC_ALL=C grep -aq '\[discord\] state: Circuit' "$D/log.txt" 2>/dev/null && { raced=1; ev "race"; }
        done
        mock_kill KILL
      done
      mock_start normal
      wait_until "$D/frames.jsonl" '"details": "Circuit' 60 || { ok=0; echo "  no presence once Discord behaved"; }
      ev "race presence shown"
      game_wait || ok=0
      sleep 0.5; mock_kill TERM ;;
    absent)
      game_start "$SEQ" 7400
      wait_until "$D/log.txt" '\[discord\] state: Circuit' 240 || ok=0
      ev "race"
      game_wait || ok=0 ;;
    *) echo "unknown scenario $name"; ok=0 ;;
    esac
    check "$name" || ok=0
    if [ $ok -eq 1 ]; then pass=$((pass+1)); echo "PASS $b $name"; else fail=$((fail+1)); echo "FAIL $b $name"; fi
  done
done
echo "discord suite: $pass passed, $fail failed  ($OUT)"
[ $fail -eq 0 ]
