#!/bin/bash
# lan_region_cars.sh -- a LAN race against a car this game folder does not
# have (runtime/regional.c, sub_005f04e0), about 8 minutes.
#
#   NFSU2_DATA=<all four cars> LAN_DATA_2=<one region's data> tests/net/lan_region_cars.sh <outdir> [AS_SENT]
#
# Instance 1 hosts on NFSU2_DATA, a folder with both regions' cars, in the
# Honda Civic (Select Car's fifth car there); instance 2 joins on LAN_DATA_2,
# the European release's data (no CARS\CIVIC, CARS\RSX), in the Focus.  The
# joiner's game decodes the host's Civic and, the files not there, makes it
# a stock Corsa ("[cars] ... is shown as a stock CORSA").  Without that its
# car loader waited for the Civic's packs for good and the race never left
# "Loading" (AS_SENT=1: NFSU2_TEST_RACE_CARS_AS_SENT=1 on the joiner, the
# game's way, for the A/B).  PASS when both reach the results screen and the
# joiner logged the Corsa.
# The main menu's LAN item is called (0x4AEDE0, as mprace.c does) instead of
# tapped to: on a busy Mac the menu took the taps before it was ready.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?usage: tests/net/lan_region_cars.sh <outdir> [AS_SENT]}"; AS_SENT="${2:-0}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
: "${NFSU2_DATA:?set NFSU2_DATA to a game folder with all four regional cars}"
: "${LAN_DATA_2:?set LAN_DATA_2 to a game folder of one region (no CARS/CIVIC)}"
[ -f "$NFSU2_DATA/CARS/CIVIC/GEOMETRY.BIN" ] || { echo "NFSU2_DATA has no CARS/CIVIC"; exit 2; }
[ -f "$LAN_DATA_2/CARS/CIVIC/GEOMETRY.BIN" ] && { echo "LAN_DATA_2 has CARS/CIVIC: nothing to test"; exit 2; }
export NFSU2_DATA
G="$ROOT/tests/net/gen_lan_race.py"
"$PY" "$G" host --name HOSTMAC --car 4 --mode 0 --race-ms 120000 > "$OUT/host.txt" || exit 2
"$PY" "$G" join --name JOINER --car 1 --refresh --race-ms 120000 > "$OUT/join.txt" || exit 2
"$PY" - "$OUT/host.txt" "$OUT/join.txt" <<'EOF' || exit 2
import sys
for p in sys.argv[1:]:
    s = open(p).read()
    old = "+300  tap RIGHT\n+60   tap RIGHT\n+120  tap RETURN\n"
    if old not in s: sys.exit(p + ": the main menu's taps not found")
    open(p, 'w').write(s.replace(old, "+600  call 0x4aede0 0x78f530 0x0c407210 0 0 0\n", 1))
EOF
ex2="NFSU2_DATA=$LAN_DATA_2"; [ "$AS_SENT" = 1 ] && ex2="$ex2 NFSU2_TEST_RACE_CARS_AS_SENT=1"
NFSU2_TIMEOUT="${NFSU2_TIMEOUT:-900}" NET_EXTRA_2="$ex2" \
  "$ROOT/tests/net/vlan_run.sh" "$OUT" --quit-after 1800 -- "$OUT/host.txt" "$OUT/join.txt" > "$OUT/vlan_run.txt" 2>&1
rc=$?
why=""
[ $rc -eq 0 ] || why="$why exit=$rc"
for i in 1 2; do
  LC_ALL=C grep -aq "screen UI_PostRaceResults.fng" "$OUT/i$i/log.txt" || why="$why i$i:no-results"
done
LC_ALL=C grep -aq "is shown as a stock CORSA" "$OUT/i2/log.txt" || why="$why i2:no-corsa"
if [ -z "$why" ]; then echo "PASS lan_region_cars ($OUT)"; exit 0; fi
echo "FAIL lan_region_cars:$why ($OUT)"; exit 1
