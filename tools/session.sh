#!/bin/bash
# Real game session recording (while the user plays).
#
#   ./tools/session.sh            normal build
#   ./tools/session.sh hd         HD build
#
# The game starts with recording on (PERFLOG); play normally, quit the game when
# done.  At the same time powermetrics writes CPU/GPU watts once a second (the
# admin password is asked once; without it only the in-game recording is taken).
# Recording: ~/nfs_sessions/<date>[_hd]   Analysis: python3 tools/session_report.py <dir>
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HD=0
for a in "$@"; do case "$a" in hd) HD=1 ;; *) echo "unknown: $a"; exit 1 ;; esac; done
# the recording directory is tagged with the version: always clear which version was played
VERSION="$(tr -cd '0-9' < "$ROOT/VERSION" 2>/dev/null)"; VERSION="${VERSION:-0}"
NAME="NFSU2"; SUF="_v$VERSION"; PK=""
[ $HD = 1 ] && { NAME="$NAME HD"; SUF="${SUF}_hd"; PK="$PK --hd"; }
NAME="$NAME.app"
APP="$ROOT/out/personal/$NAME"; [ -d "$APP" ] || APP="$ROOT/out/kisisel/$NAME"; [ -d "$APP" ] || APP="$ROOT/out/$NAME"
[ -d "$APP" ] || { echo "no app: $APP  (run ./pack.sh --embed$PK first)"; exit 1; }
DIR="$HOME/nfs_sessions/$(date +%Y%m%d_%H%M%S)$SUF"
mkdir -p "$DIR"
echo "app       : $APP"
echo "recording : $DIR"

PM=0; KA=0
echo "admin password for powermetrics (CPU/GPU watt measurement):"
if sudo -v; then
  sudo powermetrics --samplers cpu_power,gpu_power,thermal -i 1000 -o "$DIR/power.txt" >/dev/null 2>&1 &
  PM=1
  ( while sleep 50; do sudo -n -v 2>/dev/null || exit 0; done ) & KA=$!
else
  echo "warning: no password given, no powermetrics; in-game recording only"
fi

# Temperature / fan (no sudo needed): so the "86 degrees" the user sees is measured directly
SMC="$ROOT/out/smcread"; SM=0
[ "$SMC" -nt "$ROOT/tools/smcread.c" ] || clang -O1 -framework IOKit -o "$SMC" "$ROOT/tools/smcread.c" 2>/dev/null
if [ -x "$SMC" ]; then "$SMC" -k 1000 "$DIR/temperature.csv" & SM=$!; fi

echo
echo "starting the game: play normally (~5 min), quit the game when done."
# Battery / power mode: some performance drops come from the system, not the game
# (2026-10-18: after waking from sleep at 4% battery and plugging in, CPU+GPU were throttled).
{ date; pmset -g batt; pmset -g | grep -i lowpowermode; } > "$DIR/battery_start.txt" 2>&1
# DLINK=2: writes the real display refresh rate to the game's log every 5 s
open -W -n "$APP" --env PERFLOG="$DIR" --env DLINK=2 --stderr "$DIR/game.log"
{ date; pmset -g batt; pmset -g | grep -i lowpowermode; } > "$DIR/battery_end.txt" 2>&1
LG=nfsu2; [ $HD = 1 ] && LG="$LG-hd"
cp "$HOME/Library/Logs/NFSU2/$LG.log" "$DIR/game_full.log" 2>/dev/null

[ $SM != 0 ] && kill $SM 2>/dev/null
if [ $PM = 1 ]; then
  sudo -n pkill -INT -f "powermetrics.*$DIR" 2>/dev/null || sudo pkill -INT -f "powermetrics.*$DIR"
  [ $KA != 0 ] && kill $KA 2>/dev/null
fi
sleep 1
echo
echo "recording done: $DIR ($(du -sh "$DIR" | cut -f1))"
echo "You can tell Claude this directory."
