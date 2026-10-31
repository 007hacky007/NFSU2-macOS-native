"""LREGS: the guest's general registers and arithmetic flags as C locals of
each lifted function, stored to the CPU struct only where something else can
see them (tools/lift.py runs this on every function it lifts when LREGS=1).

The lifter's C reads and writes c->eax, c->zf, ... directly.  The CPU struct
outlives the function, so clang has to make every one of those stores: a flag
that only the next branch reads is still materialised and stored (cmp, cset,
str on arm64), and a register written in a loop is stored on every pass.
With LREGS the function keeps them in locals (_r_eax ... _r_of; cpu.h's RG_()
names them in the shared macros: PUSH32, POP32, FLAGS_*, SETZSP_M, CC_*,
FCOMI, FTOL2_INL) and the struct is brought up to date at the points where
code outside the function can read or write it:
  - a direct call: the registers before it (the flags too when the callee
    reads flags at entry, FLAGABI's entry table), both reloaded after it;
  - an indirect call (dispatch_indirect followed by more code): the registers
    before it (with FLAGABI an indirect callee reads no flags: the ABI the
    FLAGABI lift already relies on; without a table the flags too), both
    reloaded after it;
  - a tail jump (dispatch_indirect(c, ...); return;): registers and flags;
  - a return: the registers (the flags too in a function that returns flags,
    FLAGABI's returning set, and the callees of tools/retpast.txt);
  - the runtime helpers that take the CPU: cpuid_shim (registers),
    guest_hook and unsupported_insn (everything).  pushfd and popfd work on
    the locals (LR_EFLAGS_GET / LR_EFLAGS_SET).
Only what may have changed since the struct was last in step is stored: a
forward dataflow over the function's blocks (labels and gotos, the xpatch
resume labels too) tracks the registers written since the entry or the last
call on any path; the others hold the struct's value already.  A reload that
nothing reads is removed by clang.  So every point where other code can look
sees the same values as before; in between, nothing else runs on this guest
thread, and other threads only see its CPU while it is inside such a call
(the guest lock).  Without a FLAGABI table every call and every return also
stores the flags.

The transform works on the lift's own C, before genall.py's MEMARG rewrite
(which renames the calls and the header; both forms are matched here).
WATCH=1 instrumentation (WCHK) is not supported with it.

Ported from th0mk's nfsu2-web tools/lregs.py (MIT).
"""
import re

GPR = ('eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi')
FLG = ('cf', 'pf', 'af', 'zf', 'sf', 'of')
GBIT = {r: 1 << i for i, r in enumerate(GPR)}
GMASK = 0xff
FBIT = 0x100                      # any of the six flags

_FIELD = re.compile(r'\bc->(eax|ecx|edx|ebx|esp|ebp|esi|edi|cf|pf|af|zf|sf|of)\b')
_HDR = re.compile(r'^void sub_([0-9a-f]{8})(?:_orig)?\(CPU \*(?:restrict )?c\) ?\{')
# the points where the struct must be in step, and what each needs (the first
# pattern that matches at a position wins: a tail jump before an indirect call)
_SITES = [('tail',  re.compile(r'\bdispatch_indirect\(c, [^;]*?\); return;')),
          ('call',  re.compile(r'\bsub_([0-9a-f]{8})\(c\);')),
          ('icall', re.compile(r'\bdispatch_indirect\(c, [^;]*?\);')),
          ('cpuid', re.compile(r'\bcpuid_shim\(c\);')),
          ('all',   re.compile(r'\bguest_hook\(c, [^;]*?\);')),
          ('all',   re.compile(r'\bunsupported_insn\(c, ?0x[0-9a-f]+u, ?"[^"]*"\);')),
          ('ret',   re.compile(r'\breturn;'))]
_EFGET = re.compile(r'\beflags_get\(c\)')
_EFSET = re.compile(r'\beflags_set\(c, ?([^;]*?)\);')
# writes: assignment and compound assignment, ++/--, the stack and flag macros
_WRITE = re.compile(r'\b_r_([a-z]{2,3})\s*(?:[-+*/%&|^]|<<|>>)?=(?!=)')
_INCDEC = re.compile(r'(?:\b_r_([a-z]{2,3})\s*(?:\+\+|--))|(?:(?:\+\+|--)\s*_r_([a-z]{2,3})\b)')
_ESPW = re.compile(r'\b(?:PUSH32|POP32)\(')
_FLAGW = re.compile(r'\b(?:FLAGS_[A-Z]+_M|FLAGS_[A-Z]+|SETZSP_M|SETZSP|FCOMI|LR_EFLAGS_SET)\(')
# cpu.h FTOL2_INL (the CRT's _ftol2 in place, lift option FTOL2INL): eax, ecx, edx, esp and flags
_FTOL2W = re.compile(r'\bFTOL2_INL\(')
_LABEL = re.compile(r'\b((?:L|XR)_[0-9a-f]{8}):;')
_GOTO = re.compile(r'\bgoto ((?:L|XR)_[0-9a-f]{8});')


def transform(code, live_in=None, flags_out=None):
    """One lifted function (optional comment lines, the header, the body, the
    closing brace) -> its LREGS form.  live_in: entry -> flags read at entry,
    flags_out: the functions that return flags (FLAGABI); None: every callee
    reads and every function returns them."""
    lines = code.split('\n')
    m = None
    for hi, ln in enumerate(lines):
        m = _HDR.match(ln)
        if m: break
    if not m: return code
    ret_f = flags_out is None or int(m.group(1), 16) in flags_out
    head = '\n'.join(lines[:hi]) + ('\n' if hi else '')
    brace = lines[hi].index('{')
    sig = lines[hi][:brace + 1]
    body = lines[hi][brace + 1:] + ('\n' + '\n'.join(lines[hi + 1:]) if hi + 1 < len(lines) else '')
    end = body.rstrip().rfind('}')                # the function's closing brace
    tail, body = body[end:], body[:end]
    body = _FIELD.sub(r'_r_\1', body)
    body = _EFGET.sub('LR_EFLAGS_GET()', body)
    body = _EFSET.sub(lambda mm: f'LR_EFLAGS_SET({mm.group(1)});', body)

    # braces opened by an if / else / switch / case / loop statement (the
    # xpatch blocks span lines: 'if (g_xpatch[k]) {' ... 'goto L_x;' ... '}')
    brace_ev = []; stack = []; i = 0; n = len(body)
    while i < n:
        ch = body[i]
        if body.startswith('/*', i): i = body.find('*/', i + 2) + 2; continue
        if ch == '"':
            i += 1
            while i < n and body[i] != '"': i += 2 if body[i] == '\\' else 1
            i += 1; continue
        if ch == '{':
            k = max(body.rfind(x, 0, i) for x in (';', '{', '}', '\n', ':'))
            st = body[k + 1:i].strip()
            stack.append(bool(re.match(r'(?:if|else|switch|case|for|while|do)\b', st)))
            brace_ev.append((i, sum(stack)))
        elif ch == '}':
            if stack: stack.pop()
            brace_ev.append((i, sum(stack)))
        i += 1
    brace_pos = [p for p, _ in brace_ev]
    import bisect
    def cond_at(pos):
        """a goto / return / tail jump at pos is conditional when its statement
        starts with if or a switch case, or it is inside a block such a
        statement opened"""
        t = body[body.rfind('\n', 0, pos) + 1:pos].lstrip()
        if t.startswith('if') or t.startswith('case'): return True
        k = bisect.bisect_left(brace_pos, pos) - 1
        return k >= 0 and brace_ev[k][1] > 0
    found = []                                    # (start, end, kind, match)
    for kind, rx in _SITES:
        for mm in rx.finditer(body): found.append((mm.start(), mm.end(), kind, mm))
    found.sort(key=lambda x: (x[0], -x[1]))
    sites = []; last_end = -1
    for st in found:                              # overlapping matches: the earlier, longer one
        if st[0] < last_end: continue
        sites.append(st); last_end = st[1]
    unc = [not cond_at(a) for (a, _b, _k, _m) in sites]
    ev = [(a, 2, 'site', i) for i, (a, _b, _k, _m) in enumerate(sites)]
    ev += [(mm.start(), 0, 'label', mm.group(1)) for mm in _LABEL.finditer(body)]
    for mm in _WRITE.finditer(body):
        r = mm.group(1)
        if r in GBIT: ev.append((mm.start(), 1, 'w', GBIT[r]))
        elif r in FLG: ev.append((mm.start(), 1, 'w', FBIT))
    ev += [(mm.start(), 1, 'w', GBIT[g]) for mm in _INCDEC.finditer(body) for g in mm.groups() if g in GBIT]
    ev += [(mm.start(), 1, 'w', FBIT) for mm in _INCDEC.finditer(body) for g in mm.groups() if g in FLG]
    ev += [(mm.start(), 1, 'w', GBIT['esp']) for mm in _ESPW.finditer(body)]
    ev += [(mm.start(), 1, 'w', FBIT) for mm in _FLAGW.finditer(body)]
    ev += [(mm.start(), 1, 'w', GBIT['eax'] | GBIT['ecx'] | GBIT['edx'] | GBIT['esp'] | FBIT) for mm in _FTOL2W.finditer(body)]
    ev += [(mm.start(), 3, 'goto', (mm.group(1), not cond_at(mm.start()))) for mm in _GOTO.finditer(body)]
    ev.sort(key=lambda e: (e[0], e[1]))

    # forward dataflow: what may differ from the struct (None: no path gets here).
    # Monotone over a finite lattice (9 bits per label), so it settles.
    IN = {}; at = [0] * len(sites); cur = 0
    while True:
        changed = False; cur = 0
        for _p, _o, kind, arg in ev:
            if kind == 'label':
                if cur is not None:
                    v = IN.get(arg, 0) | cur
                    if IN.get(arg) != v: IN[arg] = v; changed = True
                cur = IN.get(arg)
            elif cur is None: continue
            elif kind == 'w': cur |= arg
            elif kind == 'goto':
                t, u = arg
                v = IN.get(t, 0) | cur
                if IN.get(t) != v: IN[t] = v; changed = True
                if u: cur = None
            else:
                at[arg] = cur
                k = sites[arg][2]
                if k in ('call', 'icall', 'all'): cur = 0          # stored, then reloaded
                elif k == 'cpuid': cur &= ~GMASK
                elif unc[arg]: cur = None                           # ret, tail
        if not changed: break

    def store(mask, flags):
        g = [f'c->{r} = _r_{r};' for r in GPR if mask & GBIT[r]]
        f = [f'c->{x} = _r_{x};' for x in FLG] if flags and mask & FBIT else []
        return ' '.join(g + f)
    out = []; last = 0
    for i, (a, b, kind, mm) in enumerate(sites):
        d = at[i] or 0
        if kind == 'call':
            st = store(d, live_in is None or live_in.get(int(mm.group(1), 16), 0))
            rep = f'{body[a:b]} LR_FG; LR_FF;'
        elif kind == 'icall': st = store(d, live_in is None); rep = f'{body[a:b]} LR_FG; LR_FF;'
        elif kind == 'cpuid': st = store(d, False); rep = f'{body[a:b]} LR_FG;'
        elif kind == 'all':   st = store(d, True);  rep = f'{body[a:b]} LR_FG; LR_FF;'
        elif kind == 'ret':   st = store(d, ret_f); rep = 'return;'
        else:                 st = store(d, True);  rep = body[a:b]            # tail
        out += [body[last:a], '{ ', st + ' ' if st else '', rep, ' }']; last = b
    out.append(body[last:])
    body = ''.join(out)
    # a body that ends without a return (the lift-error stubs) stores on the way out
    fall = store(cur or 0, ret_f) if cur is not None else ''
    return head + sig + ' LR_ENTER;' + body + (' ' + fall if fall else '') + ' ' + tail.lstrip()

SHARD_DEFINE = '#define NFSU2_LREGS 1\n'
