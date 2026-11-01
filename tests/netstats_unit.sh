#!/bin/sh
# The Online statistics panel (runtime/netstats.m, netstats_core.c), no game:
#   1. tests/netstats_unit.c: the /players address for the server's address,
#      the /players answer and the panel's text (address and undefined-behaviour
#      sanitizers);
#   2. tests/netstats_fetch.py: the fetch against a stand-in /players on
#      127.0.0.1, inside the loopback-only sandbox profile.
# About 20 s.  Prints "RESULT: all passed" and exits 0 when both pass.
set -u
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
fail=0
part(){ if [ "$1" = 0 ]; then echo "PASS  $2"; else echo "FAIL  $2"; fail=1; fi; }

echo "== netstats_unit"
clang -O1 -g -Wall -Wextra -fsanitize=address,undefined -Iruntime -o "$T/netstats_unit" tests/netstats_unit.c runtime/netstats_core.c \
  || { echo "build failed"; exit 1; }
"$T/netstats_unit" > "$T/unit.txt" 2>&1; r=$?
grep -a "^FAIL" "$T/unit.txt"; tail -1 "$T/unit.txt"
part $r "tests/netstats_unit.c"

echo "== /players fetch (stand-in on 127.0.0.1)"
SBX=""; [ -x /usr/bin/sandbox-exec ] && SBX="/usr/bin/sandbox-exec -f $(pwd)/tests/net/loopback-only.sb"
$SBX /usr/bin/python3 -I tests/netstats_fetch.py; r=$?
part $r "tests/netstats_fetch.py"

echo
if [ $fail = 0 ]; then echo "RESULT: all passed"; else echo "RESULT: SOME FAILED"; fi
exit $fail
