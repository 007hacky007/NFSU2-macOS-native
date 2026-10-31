#!/usr/bin/env python3
"""Pick the functions to inline (genall.py INLINE_LIST, tools/inline_hot.txt)
from a call-count profile.

Every guest function call costs a native call (prologue, return) and the
register stores and reloads around it (with LREGS).  Inlining removes that,
but every call site gets its own copy, so the pick is the most calls per byte
of copies: a function qualifies when it is called often (>= --min calls in
the profile), is at most --max x86 instructions, has direct call sites
(indirect calls cannot be inlined) and nothing genall.py refuses (run-time
helpers, hooks, recursion, overrides); then the best calls / (call sites x
body size) go in until the copies reach --budget bytes of C.

The profile: a COVERAGE=1 lift (COVERAGE=1 tools/gen_v2.sh <SPEED2.EXE>, then
./build.sh && ./link.sh), run through a race with COVREPORT=<file>; the file
holds "<address> <calls>" for every function that ran (runtime/debug.c
cov_report).  "<calls>  sub_<address>" lines (a log's most-called list) are
read too.  Addresses are those of the build that ran; tools/inline_hot.txt
holds European ones.

    tools/inline_pick.py <profile> <gen dir> [--min N] [--max N] [--budget BYTES] > tools/inline_hot.txt

Ported from th0mk's nfsu2-web tools/inline_pick.py (MIT).
"""
import re, sys, os, glob, argparse, collections

ap = argparse.ArgumentParser()
ap.add_argument('log'); ap.add_argument('gen')
ap.add_argument('--min', type=int, default=30000, help='calls in the profile (default 30000)')
ap.add_argument('--max', type=int, default=400, help='x86 instructions (default 400)')
ap.add_argument('--budget', type=int, default=1 << 20, help='bytes of C for the copies (default 1 MB)')
o = ap.parse_args()

log = open(o.log, errors='replace').read()
counts = {int(m.group(1), 16): int(m.group(2)) for m in re.finditer(r'^([0-9a-f]{8}) (\d+)\s*$', log, re.M)}
counts.update({int(m.group(2), 16): int(m.group(1)) for m in re.finditer(r'^\s+(\d+)\s+sub_([0-9a-f]{8})\s*$', log, re.M)})
if not counts: sys.exit('no "<address> <calls>" or "<calls>  sub_<address>" lines in the profile (COVREPORT)')

hdr = re.compile(r'^/\* ===== sub_([0-9a-f]{8})  \((\d+) instructions, (\d+) blocks\) ===== \*/')
fdef = re.compile(r'^void sub_([0-9a-f]{8})(_orig)?(?:_m)?\(CPU')
deny = ('unsupported_insn', 'cpuid_shim', 'guest_hook', 'rdtsc_shim', 'cov_hit')
info, sites = {}, collections.Counter()
for f in sorted(glob.glob(os.path.join(o.gen, 'shard_*.c'))):
    text = open(f).read()
    for m in re.finditer(r'\bsub_([0-9a-f]{8})(?:_m)?\(c(?:, _mb)?\);', text): sites[int(m.group(1), 16)] += 1
    for part in re.split(r'(?m)^(?=/\* ===== sub_)', text):
        m = hdr.match(part)
        if not m: continue
        a = int(m.group(1), 16); d = fdef.search(part.split('\n', 2)[1] if '\n' in part else '')
        body = part.split('{', 1)[1] if '{' in part else ''
        info[a] = dict(n=int(m.group(2)), size=len(part), orig=bool(d and d.group(2)),
                       ok=not any(x in body for x in deny) and not re.search(rf'\bsub_{a:08x}(?:_m)?\(c', body))

cand = []
for a, n in counts.items():
    i = info.get(a)
    if not i or not i['ok'] or i['orig'] or n < o.min or i['n'] > o.max or not sites[a]: continue
    cand.append((n / (sites[a] * i['size']), a, n, sites[a], i['n'], sites[a] * i['size']))
cand.sort(reverse=True)
pick, used, calls = [], 0, 0
for _, a, n, s, ins, g in cand:
    if used + g > o.budget: continue
    pick.append((a, n, s, ins)); used += g; calls += n
pick.sort()
tot = sum(counts.values())
print(f"# genall.py INLINE_LIST (tools/gen_v2.sh INLINE_LIST=1): {len(pick)} functions inlined at their direct")
print(f"# call sites, picked by tools/inline_pick.py from a race's call counts: {calls} of {tot} calls")
print(f"# ({100 * calls / tot:.1f} %) in the profile, {used / 1048576:.1f} MB of C in copies.  address  # calls  call sites  x86 instructions")
for a, n, s, ins in pick: print(f"{a:08x}  # {n} {s} {ins}")
print(f"inline_pick: {len(pick)} functions, {calls} of {tot} calls ({100 * calls / tot:.1f} %), {used / 1048576:.1f} MB of copies", file=sys.stderr)
