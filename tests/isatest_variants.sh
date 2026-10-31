#!/bin/bash
# The ISA tests (tools/isatest.py) lifted with every lifter option that changes
# the C: the default (X87PC=1), X87OPT, X87PC=0, RETEIP=0, JTSWITCH, LREGS and
# their mixes; FUZZ=<n> also runs n random instructions of the differential
# test (tools/fuzzisa.py: real x86 under Rosetta against the lift) plain and
# with LREGS.  Exit code 0 when every variant passes.
#   tests/isatest_variants.sh            FUZZ=3000 tests/isatest_variants.sh
set -u
cd "$(dirname "$0")/.."
PY=.venv/bin/python
W="$(mktemp -d "${TMPDIR:-/tmp}/isavar.XXXXXX")"
trap 'rm -rf "$W"' EXIT
fail=0
for v in "" "X87OPT=1" "X87PC=0" "RETEIP=0" "JTSWITCH=1" "LREGS=1" "LREGS=1 X87PC=0" \
         "LREGS=1 JTSWITCH=1" "X87OPT=1 RETEIP=0 LREGS=1 JTSWITCH=1"; do
  n=$(echo "v $v" | tr ' =' '__')
  if env $v ISATEST_OUT="$W/$n.c" $PY tools/isatest.py > "$W/$n.gen" 2>&1 \
     && clang -O1 -Wno-unused-label -Iruntime -o "$W/$n" "$W/$n.c" runtime/mem.c -lm 2> "$W/$n.cc"; then
    r=$("$W/$n" | grep -a "ISA tests" | sed 's/\x1b\[[0-9;]*m//g')
    "$W/$n" > /dev/null || { fail=1; "$W/$n" | grep -a FAIL; }
  else
    r="could not be generated or compiled"; fail=1; cat "$W/$n.gen" "$W/$n.cc" | head -20
  fi
  printf "  %-40s %s\n" "${v:-(default)}" "$r"
done
if [ -n "${FUZZ:-}" ]; then
  for v in "" "LREGS=1"; do
    r=$(env $v FUZZDIR="$W/fuzz" $PY tools/fuzzisa.py "$FUZZ" "${SEED:-12345}" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "checked:|MATCH|DIFFER|differ|NO CASE" | tr '\n' ' ')
    case "$r" in *"ALL RESULTS MATCHED"*) ;; *) fail=1 ;; esac
    printf "  fuzz %-35s %s\n" "${v:-(default)}" "$r"
  done
fi
[ $fail = 0 ] && echo "RESULT: all variants passed" || echo "RESULT: SOME FAILED"
exit $fail
