#!/bin/bash
# The free-roam multiplayer core without the game (about 15 s):
#   1. tests/roam_unit.c: the protocol's byte layout, the session state
#      machine, interpolation, the loopback guard, a fuzzer (287 checks;
#      in-process fake network, no socket);
#   2. on 127.0.0.1 inside tests/net/loopback-only.sb: a stand-in friend
#      (tests/roam_fakepeer.c) driving a circle and a viewer peer
#      (tests/roam_recv.c) that joins it and shows its car through the real
#      sockets (runtime/roam_bsd.c).
#   tests/roam_unit.sh [fuzz-iterations]
# ROAM_TEST_PORT moves the two loopback ports (default 47410, 47411).
# Exit status 0 when every check passes.
set -u
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'kill $FPID 2>/dev/null; rm -rf "$T"' EXIT HUP INT TERM
FPID=""
CF="-O1 -g -ffp-contract=off -Iruntime"
clang -O1 -fobjc-arc -Iruntime -c runtime/net_native.m -o "$T/net_native.o" || exit 1
# roam_unit with the address and undefined-behaviour sanitizers; the two
# socket tools as the game builds the core (no fused multiply-add)
clang $CF -fsanitize=address,undefined -o "$T/roam_unit" tests/roam_unit.c runtime/roam_core.c runtime/roam_bsd.c \
  "$T/net_native.o" -framework Foundation || exit 1
for t in roam_fakepeer roam_recv; do
  clang $CF -o "$T/$t" "tests/$t.c" runtime/roam_core.c runtime/roam_bsd.c "$T/net_native.o" -framework Foundation || exit 1
done
SB=(); [ -x /usr/bin/sandbox-exec ] && SB=(/usr/bin/sandbox-exec -f tests/net/loopback-only.sb)
FAILED=0
pass(){ printf "  PASS  %s\n" "$1"; }
fail(){ printf "  FAIL  %s\n" "$1"; FAILED=1; }

echo "== roam_unit"
"${SB[@]}" "$T/roam_unit" ${1:+"$1"} > "$T/unit.txt" 2>&1; rc=$?
grep -a "FAIL" "$T/unit.txt"
tail -1 "$T/unit.txt"
if [ $rc -eq 0 ] && grep -aq "roam_unit: [0-9]* passed, 0 failed" "$T/unit.txt"; then pass "roam_unit"; else fail "roam_unit (exit $rc)"; fi

echo "== stand-in friend and viewer on loopback"
P1="${ROAM_TEST_PORT:-47410}"; P2=$((P1 + 1))
"${SB[@]}" "$T/roam_fakepeer" --port "$P2" --peer "127.0.0.1:$P1" --name Carol --stock PEUGOT \
    --circle 100,200,24,30,20 --seconds 7 > "$T/fake.txt" 2>&1 & FPID=$!
"${SB[@]}" "$T/roam_recv" "$P1" "$P2" 6 > "$T/recv.txt" 2> "$T/recv_err.txt"
wait $FPID; frc=$?; FPID=""
tail -n 2 "$T/recv.txt"
[ $frc -eq 0 ] && pass "the stand-in ran and left (exit 0)" || fail "the stand-in exited with $frc"
grep -aq "JOIN" "$T/fake.txt" && pass "the stand-in saw the viewer join" || fail "the stand-in saw no join"
grep -aq "^\[recv\] event 1 .*Carol" "$T/recv_err.txt" && pass "the viewer saw the stand-in join" || fail "the viewer saw no join"
# the car is shown every second (interpolated or extrapolated frames), it
# moves, and it never jumps: no clock re-sync, no correction over 5 m
n=$(awk '/interp/ {for (i = 1; i < NF; i++){ if ($i == "interp") a = $(i + 1); if ($i == "extrap") b = $(i + 1) }
                    if (a + b >= 30) k++} END{print k+0}' "$T/recv.txt")
[ "$n" -ge 3 ] && pass "the viewer shows the car ($n reports with 30 frames or more)" || fail "the viewer shows the car too rarely ($n reports)"
m=$(awk '/shown/ {for (i = 1; i <= NF; i++) if ($i == "shown") s = $(i + 1)} END{print (s + 0 > 5) ? 1 : 0}' "$T/recv.txt")
[ "$m" = 1 ] && pass "the shown car moves" || fail "the shown car does not move"
j=$(grep -a -c -E "re-syncs \+[1-9]|snaps>5m \+[1-9]" "$T/recv.txt")
[ "$j" = 0 ] && pass "no re-sync and no correction over 5 m" || fail "$j report(s) with a re-sync or a big correction"
if grep -aq "BLOCKED" "$T/fake.txt" "$T/recv_err.txt"; then fail "a loopback peer was BLOCKED"
else pass "no packet refused on loopback"; fi
echo
if [ $FAILED = 0 ]; then echo "RESULT: all passed"; else
  echo "--- fake"; tail -n 20 "$T/fake.txt"; echo "--- recv"; tail -n 20 "$T/recv.txt"; tail -n 20 "$T/recv_err.txt"
  echo "RESULT: SOME FAILED"; fi
exit $FAILED
