#!/bin/sh
# The network tests without the game, all on loopback or AF_UNIX:
#   - tests/net_harness.c: the Winsock / Netbios HLE (runtime/winsock.c,
#     net_vlan.c) against Windows behaviour, inside the loopback-only sandbox
#     profile (tests/net/loopback-only.sb), alone and with tools/vlanhub.py
#     (the virtual LAN checks);
#   - tests/net/native/relay.c: the relay backend (runtime/net_relay.c) on a
#     mailbox of its own (no socket at all);
#   - tests/net/native/loopback.py: the native WebSocket transport
#     (runtime/net_native.m) against a relay fixture on 127.0.0.1, sandboxed;
#   - tests/net/native/switch.c, only with NFSU2_DONOR_SERVER=<nfsu2-server
#     binary> (nfsu2-web's web/server-rs, built locally): guest TCP through the
#     transport logs in to that server's Online lobby on 127.0.0.1, sandboxed.
# About a minute.  Prints "RESULT: all passed" and exits 0 when every part passes.
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
SBX="/usr/bin/sandbox-exec -f $ROOT/tests/net/loopback-only.sb"
[ -x /usr/bin/sandbox-exec ] || { echo "no /usr/bin/sandbox-exec: the network tests only run sandboxed"; exit 1; }
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
T=$(mktemp -d)
SP=""
trap '[ -n "$SP" ] && kill $SP 2>/dev/null; rm -rf "$T"' EXIT HUP INT TERM
fail=0
part(){ if [ "$1" = 0 ]; then echo "PASS  $2"; else echo "FAIL  $2"; fail=1; fi; }

CF="-O1 -g -Iruntime"
clang $CF -fobjc-arc -c runtime/net_native.m -o "$T/net_native.o" &&
clang $CF -o "$T/net_harness" tests/net_harness.c runtime/winsock.c runtime/net_vlan.c runtime/net_relay.c \
      runtime/mem.c "$T/net_native.o" -framework Foundation &&
clang $CF -o "$T/relay" tests/net/native/relay.c runtime/net_relay.c &&
clang $CF -fobjc-arc -o "$T/switch" tests/net/native/switch.c runtime/net_relay.c runtime/net_native.m \
      -framework Foundation || { echo "build failed"; exit 1; }

echo "== Winsock HLE harness (loopback)"
(cd "$T" && $SBX ./net_harness > harness.txt 2>&1); r=$?
tail -1 "$T/harness.txt"; grep -a "^  FAIL" "$T/harness.txt"
part $r "net_harness (loopback)"

echo "== Winsock HLE harness (loopback and the virtual LAN hub)"
(cd "$T" && $SBX ./net_harness --vlan-hub "$PY" "$ROOT/tools/vlanhub.py" > harness_vlan.txt 2>&1); r=$?
tail -1 "$T/harness_vlan.txt"; grep -a "^  FAIL" "$T/harness_vlan.txt"
grep -aq "^vlan: skipped" "$T/harness_vlan.txt" && r=1
part $r "net_harness --vlan-hub"

echo "== relay backend"
"$T/relay"; part $? "tests/net/native/relay.c"

echo "== native WebSocket transport"
$SBX /usr/bin/python3 -I tests/net/native/loopback.py > "$T/loopback.txt" 2>&1; r=$?
grep -a "^Loopback\|Error\|assert" "$T/loopback.txt"
part $r "tests/net/native/loopback.py"

if [ -n "${NFSU2_DONOR_SERVER:-}" ]; then
  echo "== Online lobby of a local donor server"
  mkdir -p "$T/srv/data" "$T/srv/dist" "$T/srv/state"; : > "$T/srv/data/SPEED2.EXE"; : > "$T/srv/game.wasm"
  P=$(/usr/bin/python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  $SBX "$NFSU2_DONOR_SERVER" --data "$T/srv/data" --dist "$T/srv/dist" --wasm "$T/srv/game.wasm" \
      --state "$T/srv/state" --http-port "$P" --online on --roam-hub off --vault-gb 0.01 > "$T/srv/log.txt" 2>&1 &
  SP=$!
  /usr/bin/python3 -I -c '
import sys, time, urllib.request, urllib.error
for _ in range(100):
    try: urllib.request.urlopen("http://localhost:%s/" % sys.argv[1], timeout=0.2); sys.exit(0)
    except urllib.error.HTTPError: sys.exit(0)
    except Exception: time.sleep(0.1)
sys.exit(1)' "$P" || echo "the donor server did not start ($T/srv/log.txt)"
  $SBX "$T/switch" "ws://127.0.0.1:$P/lan" 2>"$T/switch.txt"; r=$?
  [ $r = 0 ] || tail -5 "$T/switch.txt"
  kill $SP 2>/dev/null; wait $SP 2>/dev/null; SP=""
  part $r "tests/net/native/switch.c (donor server)"
else
  echo "SKIP  tests/net/native/switch.c (set NFSU2_DONOR_SERVER to a local nfsu2-server binary)"
fi

echo
if [ $fail = 0 ]; then echo "RESULT: all passed"; else echo "RESULT: SOME FAILED"; fi
exit $fail
