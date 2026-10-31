#!/usr/bin/env python3
"""The override and hook lists of a lift, derived from the runtime sources, so
a built game can never lack an override or a hook (tools/gen_v2.sh, link.sh).

  overrides  every sub_XXXXXXXX_orig the runtime names (runtime/*.c *.m *.h),
             plus the DX_WRAP(..., sub_XXXXXXXX) table of d3dx_hle.c: the
             functions the lift renames to sub_X_orig so the runtime's sub_X
             replaces them
  hooks      every HOOK_SITE(0x...) of the runtime: the instructions before
             which the lifted code calls guest_hook (debug.c)

The sources name European (reference build) addresses.  For the North
American build each one is mapped with out/na/addrmap.json (tools/addrmap.py)
when it is there, else with the committed runtime/build_na.h; an address that
cannot be mapped stops the build.

  genlists.py overrides eu|na     comma list, hex without 0x (genall.py OVERRIDE)
  genlists.py hooks eu|na         comma list, 0x... (genall.py HOOKS)
  genlists.py stamp eu|na         the two lists as gen_v2.sh records them in <gen>/lists.txt
  genlists.py check eu|na <gen>   exit 1 when <gen>/lists.txt lacks an override or a
                                  hook of the sources (link.sh runs it: the lift is
                                  older than the runtime)
  genlists.py lint                exit 1 when a hook function compares ip with a GA()
                                  literal or a HOOK_ name is defined as GA(): such a
                                  site would be missing from the list
"""
import sys, os, re, glob, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMENT_RE = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)
ORIG_RE = re.compile(r'\bsub_([0-9a-f]{8})_orig\b')
DXWRAP_RE = re.compile(r'^DX_WRAP\(\s*[A-Z0-9_]+\s*,\s*sub_([0-9a-f]{8})\s*\)', re.M)
HOOK_RE = re.compile(r'\bHOOK_SITE\(\s*(0x[0-9a-fA-F]+)u?\s*\)')


def sources():
    out = []
    for pat in ('runtime/*.c', 'runtime/*.m', 'runtime/*.h'):
        for p in sorted(glob.glob(os.path.join(ROOT, pat))):
            if os.path.basename(p).startswith('build_'): continue   # generated address headers
            out.append(p)
    return out


def code_of(p):
    # comments out, their line breaks kept (lint's line numbers)
    return COMMENT_RE.sub(lambda m: ' ' + '\n' * m.group(0).count('\n'), open(p, encoding='utf-8', errors='replace').read())


def eu_lists():
    ov, hk = set(), set()
    for p in sources():
        t = code_of(p)
        ov |= {int(m.group(1), 16) for m in ORIG_RE.finditer(t)}
        if os.path.basename(p) == 'd3dx_hle.c':
            ov |= {int(m.group(1), 16) for m in DXWRAP_RE.finditer(t)}
        hk |= {int(m.group(1), 16) for m in HOOK_RE.finditer(t)}
    return ov, hk


class NaMap:
    """EU -> NA: out/na/addrmap.json (what link.sh regenerates build_na.h from), else build_na.h"""
    def __init__(self):
        j = os.path.join(ROOT, 'out/na/addrmap.json')
        self.m = None; self.ga = {}; self.fn = {}
        if os.path.exists(j):
            sys.path.insert(0, os.path.join(ROOT, 'tools'))
            from addrmap import Map
            self.m = Map(j); self.src = 'out/na/addrmap.json'
        else:
            h = open(os.path.join(ROOT, 'runtime/build_na.h')).read()
            for a, b in re.findall(r'#define GA_0x([0-9a-f]+)u 0x([0-9a-f]+)u', h): self.ga[int(a, 16)] = int(b, 16)
            for a, b in re.findall(r'#define sub_([0-9a-f]{8})_orig sub_([0-9a-f]{8})_orig\b', h): self.fn[int(a, 16)] = int(b, 16)
            self.src = 'runtime/build_na.h'

    def function(self, a):
        if self.m: return self.m.fn.get(a) if a in self.m.len else None
        return self.fn.get(a)

    def address(self, a):
        if self.m: return self.m.lookup(a)[0]
        return self.ga.get(a)


def lists(build):
    ov, hk = eu_lists()
    if build == 'eu': return ov, hk
    if build != 'na': sys.exit('build must be eu or na')
    M = NaMap(); bad = []
    ovn, hkn = set(), set()
    for a in sorted(ov):
        b = M.function(a)
        if b is None: bad.append(f'override sub_{a:08x}')
        else: ovn.add(b)
    for a in sorted(hk):
        b = M.address(a)
        if b is None: bad.append(f'hook 0x{a:08x}')
        else: hkn.add(b)
    if bad:
        sys.exit(f'genlists: no North American address in {M.src} for: ' + ', '.join(bad))
    return ovn, hkn


def fmt_ov(s): return ','.join(f'{a:x}' for a in sorted(s))
def fmt_hk(s): return ','.join(f'0x{a:x}' for a in sorted(s))


def parse_stamp(p):
    ov = hk = None
    for ln in open(p):
        k, _, v = ln.strip().partition(' ')
        if k == 'overrides': ov = {int(x, 16) for x in v.split(',') if x}
        if k == 'hooks': hk = {int(x, 16) for x in v.split(',') if x}
    return ov, hk


def lint():
    """hook sites written as GA(): a hook function (int x_hook(CPU *c, uint32_t ip),
    debug.c's guest_hook aside: its sites are debugging aids, lifted only with
    HOOKS=...) comparing ip with GA(...), or a HOOK_ / H_ name defined as GA(...)"""
    bad = []
    fn_re = re.compile(r'^int\s+(\w+_hook)\s*\(\s*CPU\s*\*\s*\w+\s*,\s*uint32_t\s+ip\s*\)\s*\{', re.M)
    cmp_re = re.compile(r'\bcase\s+GA\(|\bip\s*[!=]=\s*GA\(|\bGA\([^)]*\)\s*[!=]=\s*ip\b')
    def_re = re.compile(r'^\s*#\s*define\s+(H_\w+|HOOK_\w+)\s+GA\(', re.M)
    for p in sources():
        t = code_of(p); name = os.path.relpath(p, ROOT)
        for m in def_re.finditer(t):
            bad.append(f'{name}:{t.count(chr(10), 0, m.start()) + 1}: #define {m.group(1)} GA(...): write HOOK_SITE(...)')
        for m in fn_re.finditer(t):
            if m.group(1) == 'guest_hook': continue
            i = m.end(); depth = 1
            while depth and i < len(t):
                depth += {'{': 1, '}': -1}.get(t[i], 0); i += 1
            body = t[m.end():i]
            for k in cmp_re.finditer(body):
                ln = t.count('\n', 0, m.end() + k.start()) + 1
                bad.append(f'{name}:{ln}: {m.group(1)} compares ip with GA(...): write HOOK_SITE(...)')
    if bad:
        print('genlists lint: hook sites that would not be lifted as hooks:\n  ' + '\n  '.join(bad), file=sys.stderr)
        return 1
    return 0


def main():
    a = sys.argv[1:]
    if not a: print(__doc__); sys.exit(2)
    cmd = a[0]
    if cmd == 'lint': sys.exit(lint())
    if len(a) < 2: print(__doc__); sys.exit(2)
    ov, hk = lists(a[1])
    if cmd == 'overrides': print(fmt_ov(ov))
    elif cmd == 'hooks': print(fmt_hk(hk))
    elif cmd == 'stamp':
        print(f'# tools/genlists.py: the overrides and hooks this lift was made with ({a[1]})')
        print(f'overrides {fmt_ov(ov)}')
        print(f'hooks {fmt_hk(hk)}')
    elif cmd == 'check':
        if len(a) < 3: print(__doc__); sys.exit(2)
        p = os.path.join(a[2], 'lists.txt')
        exe = 'the European' if a[1] == 'eu' else 'the North American'
        if not os.path.exists(p):
            sys.exit(f'{a[2]} has no lists.txt: it was lifted without the runtime\'s override and hook lists.\n'
                     f'  Run tools/gen_v2.sh <{exe} SPEED2.EXE> first.')
        gov, ghk = parse_stamp(p)
        msg = []
        if gov != ov:
            if ov - gov: msg.append('overrides missing from the lift: ' + fmt_ov(ov - gov))
            if gov - ov: msg.append('overrides the runtime no longer has: ' + fmt_ov(gov - ov))
        if ghk is None or hk - ghk:
            msg.append('hooks missing from the lift: ' + fmt_hk(hk - (ghk or set())))
        if msg:
            sys.exit(f'{a[2]} is older than the runtime ({"; ".join(msg)}).\n'
                     f'  Run tools/gen_v2.sh <{exe} SPEED2.EXE> again.')
    else:
        print(__doc__); sys.exit(2)


if __name__ == '__main__':
    main()
