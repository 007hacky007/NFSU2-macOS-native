#!/usr/bin/env python3
"""Translate all 23k functions to C, split them into shards, generate the function table."""
import sys, os, struct, collections, time, multiprocessing as mp
sys.path.insert(0,'tools')
import pefile
from capstone import *
from capstone.x86 import *
from lift import Lifter, Unsupported, XPatchError, _lregs
import xpatch

EXE = sys.argv[1]
NSHARD = int(sys.argv[2]) if len(sys.argv)>2 else 128
# Second guest modules (server.dll, tools/prepare_module.py): RELOCS = the
# module's fixup slots, SEEDS = extra entry points (exports), SYMPFX = prefix
# of the generated tables (g_<pfx>fn_count/addr/ptr), so a module's fntab.c
# links next to the exe's.  Defaults reproduce the exe's output unchanged.
RELOCS = os.environ.get('RELOCS', 'out/relocs.txt')
SEEDS = os.environ.get('SEEDS', '')
SYMPFX = os.environ.get('SYMPFX', '')
# GENOUT: output directory (default gen/all); COMMENTS=1: every x86 instruction is
# written as a comment (same code; for instruction-level profiling, see tools/lift_profile.py)
OUT = os.environ.get('GENOUT', 'gen/all')
os.makedirs(OUT, exist_ok=True)

# ---------- Phase 1: closed function set ----------
def discover_all():
    L=Lifter(EXE); pe=pefile.PE(EXE); IB=pe.OPTIONAL_HEADER.ImageBase
    EP=IB+pe.OPTIONAL_HEADER.AddressOfEntryPoint
    def rd32(a):
        for nm,va,vs,d in L.secs:
            if va<=a<va+len(d)-3: return struct.unpack_from('<I',d,a-va)[0]
    funcs={EP}
    fixed=set()                                  # direct call targets (JTSWITCH keeps them)
    relref=collections.defaultdict(list)         # address -> the relocated slots that hold it
    if SEEDS:
        funcs |= {a for a in (int(x,16) for x in open(SEEDS) if x.strip()) if L.in_text(a)}
    for a in (int(x,16) for x in open(RELOCS)):
        v=rd32(a)
        if v is not None and L.in_text(v): funcs.add(v); relref[v].append(a)
    md=L.md; cov=bytearray(L.TSZ); q=collections.deque(funcs); seen=set(funcs)
    while q:
        va=q.popleft()
        while True:
            if not L.in_text(va): break
            off=va-L.TVA
            if off>=L.TSZ or cov[off]: break
            try: i=next(md.disasm(L.TDATA[off:off+16],va))
            except StopIteration: break
            for k in range(i.size):
                if off+k<L.TSZ: cov[off+k]=1
            m=i.mnemonic; o=i.operands[0] if i.operands else None
            if m=='call':
                if o is not None and o.type==X86_OP_IMM and L.in_text(o.imm):
                    fixed.add(o.imm)
                    if o.imm not in seen: seen.add(o.imm); funcs.add(o.imm); q.append(o.imm)
                va=i.address+i.size; continue
            if m=='jmp':
                if o is not None and o.type==X86_OP_IMM: va=o.imm; continue
                break
            if m.startswith('j'):
                if o is not None and o.type==X86_OP_IMM and o.imm not in seen:
                    seen.add(o.imm); q.append(o.imm)
                va=i.address+i.size; continue
            if m in ('ret','retf','int3','hlt','ud2'): break
            va=i.address+i.size
    return sorted(funcs), fixed, relref

# JTSWITCH=1 (tools/lift.py): a switch's jump table is lifted as a C switch
# inside its function, so a case that only the table reaches is a block of that
# function, not a function of its own.  Such entries leave the function list;
# a table some function's lift still leaves to the dispatcher keeps its targets
# as functions (and the closure below lifts any it needs).
# (After th0mk's nfsu2-web tools/genall.py, MIT.)
def _jt_left(L, blocks):
    """tables of the 'jmp [r*4 + table]'s in blocks that L's last lift left to the dispatcher"""
    left = []
    for ins in blocks.values():
        if not ins: continue
        i = ins[-1]
        if i.mnemonic == 'jmp' and i.operands and i.operands[0].type == X86_OP_MEM and i.address not in L.jtab:
            m = i.operands[0].mem
            if m.index and m.scale == 4 and not m.base: left.append(m.disp & 0xffffffff)
    return left
def _jt_tables(a):
    """(tables the lift turns into switches, tables it leaves to the dispatcher)"""
    try:
        blocks, _ = _L.discover(a)
    except Exception:
        return [], []
    return [(d, tuple(ents)) for (_r, d, ents) in _L.jtab.values()], _jt_left(_L, blocks)
def drop_table_targets(funcs, fixed, relref):
    tabs = set(); left = set()
    with mp.Pool(mp.cpu_count(), initializer=_init) as pool:
        for sw, lf in pool.imap_unordered(_jt_tables, funcs, chunksize=64): tabs.update(sw); left.update(lf)
    tabs = {d: ents for d, ents in tabs if d not in left}
    slots = set()
    for d, ents in tabs.items(): slots.update(range(d, d + 4 * len(ents), 4))
    drop = {v for v in funcs if v not in fixed and v not in OVERRIDES and relref.get(v) and all(a in slots for a in relref[v])}
    print(f"  [jtswitch] {len(tabs)} jump tables; {len(drop)} entries reached only through them are not functions")
    return [v for v in funcs if v not in drop], tabs

# ---------- Phase 2: parallel generation ----------
_L=None
# INLINE=<n>: "leaf" functions that make no calls and have at most n x86
# instructions are put into every shard as static inline (always_inline) copies,
# direct calls are redirected to them.  The fixed cost per call (saving entry/exit
# registers, writing c-> fields to memory and reading them back) is as large as
# the work itself for leaf calls.  The original sub_X definitions stay as they are
# (fntab, indirect calls).
INLINE_MAX = int(os.environ.get('INLINE','0') or 0)
_INL = {}
import re as _re
_INL_CALL = _re.compile(r'\bsub_([0-9a-f]{8})\(c\)')
_INL_YASAK = ('dispatch_indirect', 'unsupported_insn', 'cpuid_shim', 'guest_hook', 'rdtsc_shim', 'cov_hit')
# INLINE_LIST=<file>: these functions (hex addresses, '#' comments; European
# addresses in tools/inline_hot.txt, mapped by tools/gen_v2.sh for the North
# American build) are inlined at their direct call sites whatever their size,
# unless the lift refuses: a run-time helper, a hook, a trap, recursion, an
# override.  The pick: tools/inline_pick.py from a race's call counts.
# (After th0mk's nfsu2-web tools/genall.py, MIT.)
INLINE_LIST = set()
if os.environ.get('INLINE_LIST'):
    INLINE_LIST = {int(x, 16) for ln in open(os.environ['INLINE_LIST']) for x in ln.split('#')[0].replace(',', ' ').split()}
_INL_LIST_DENY = ('unsupported_insn', 'cpuid_shim', 'guest_hook', 'rdtsc_shim', 'cov_hit')
OVERRIDES = {int(x,16) for x in os.environ.get('OVERRIDE','').replace('0x','').split(',') if x.strip()}

# MEMARG=1: the guest memory base as a PARAMETER.  Every lifted function becomes
#   void sub_X_m(CPU *restrict c, uint8_t *restrict _mb)
# lifted code calls each other through the _m version, the g_mem macros go to _mb.
# The externally visible void sub_X(CPU*) stays as a thin wrapper (fntab, indirect
# calls, runtime -> lift calls, overrides don't change).
# Why: g_mem is a pointer read from memory and c is "escaped" because it is passed
# to calls; the compiler has to reread the c-> fields (and with
# -fno-strict-aliasing g_mem itself) after every write to guest memory.  Two
# separate noalias parameters definitely don't alias in LLVM (no escape analysis
# needed).
# For correctness this output must be compiled with -fno-strict-aliasing: lifted
# code accesses the same guest address with different types (MR32 write, MRF32 read).
MEMARG = os.environ.get('MEMARG','') == '1'
# LREGS=1 (tools/lregs.py, applied by lift.py): registers and flags in locals;
# the shards define NFSU2_LREGS for cpu.h's RG_() macros.
LREGS = os.environ.get('LREGS', '') == '1'
_MA_HDR = _re.compile(r'void sub_([0-9a-f]{8})(_orig)?\(CPU \*(?:restrict )?c\) ?\{')
def _memarg(code):
    h = _MA_HDR.search(code)
    if not h: return code
    name = f"sub_{h.group(1)}{h.group(2) or ''}"
    body = _INL_CALL.sub(lambda m: f"sub_{m.group(1)}_m(c, _mb)", code[h.end():])
    return (code[:h.start()] + f"void {name}_m(CPU *restrict c, uint8_t *restrict _mb) {{" + body
            + f"\nvoid {name}(CPU *c) {{ {name}_m(c, _gm()); }}\n")
_MA_PRO = ('static inline uint8_t *_gm(void){ return g_mem; }\n'
           '#define g_mem _mb\n')
_INL_CALL_M = _re.compile(r'\bsub_([0-9a-f]{8})_m\(c, _mb\)')
def _inl_def(x):
    """the always_inline copy of function x for a shard; with MEMARG it takes _mb
    too, and its own calls go to the _m versions"""
    code = _INL[x]
    h = _MA_HDR.search(code)
    if not h: return ''
    body = code[h.end():]
    if MEMARG:
        body = _INL_CALL.sub(lambda m: f"sub_{m.group(1)}_m(c, _mb)", body)
        sig = f"static inline __attribute__((always_inline)) void inl_{x:08x}(CPU *restrict c, uint8_t *restrict _mb) {{"
    else:
        sig = f"static inline __attribute__((always_inline)) void inl_{x:08x}(CPU *restrict c) {{"
    return code[:h.start()] + sig + body

def _init(inl=None):
    global _L, _INL
    if inl: _INL = inl
    hooks = [int(x,16) for x in os.environ.get('HOOKS','').replace('0x','').split(',') if x.strip()]
    watch = os.environ.get('WATCH','') == '1'
    cov   = os.environ.get('COVERAGE','') == '1'
    _L = Lifter(EXE, comments=os.environ.get('COMMENTS','') == '1', trap=True, hooks=hooks, watch=watch)
    _L.cov = cov
    _L.xp = xpatch.load(os.environ.get('XPATCH'))   # LOCAL PATCH: run-time switchable patches

def _inlprobe(a):
    """leaf + small + not overridden -> (address, code) or (address, None)"""
    if a in OVERRIDES: return a, None
    _L.traps = 0
    try:
        code, tg = _L.lift(a)
    except Exception:
        return a, None
    if a in INLINE_LIST:
        body = code.split('{', 1)[1]
        if any(y in code for y in _INL_LIST_DENY) or _L.traps or f"sub_{a:08x}(c)" in body: return a, None
        return a, code
    m = _re.search(r'\((\d+) instructions,', code)
    if not m or int(m.group(1)) > INLINE_MAX: return a, None
    if _INL_CALL.search(code.split('{', 1)[1]) or any(y in code for y in _INL_YASAK): return a, None
    if _L.traps: return a, None
    return a, code

def _shard(args):
    idx, addrs = args
    L=_L; parts=[]; defined=[]; refs=set(); traps=0; trunc=0; kinds=collections.Counter(); used=set(); left=set()
    for a in addrs:
        L.traps=0; L.truncated=0
        try:
            code,tg = L.lift(a)
        except XPatchError:
            raise
        except Exception as e:
            fb = f"void sub_{a:08x}(CPU *c){{ unsupported_insn(c,0x{a:x}u,\"lift-error\"); POP32(c->eip); }}"
            if LREGS: fb = _lregs().transform(fb)
            parts.append(_memarg(fb) if MEMARG else fb)
            defined.append(a); kinds[f"<lift:{type(e).__name__}>"]+=1; continue
        if a in OVERRIDES:
            code = code.replace(f"void sub_{a:08x}(CPU *restrict c) {{",
                                f"void sub_{a:08x}_orig(CPU *restrict c) {{")
        if MEMARG:
            code = _memarg(code)
        if _INL:
            hdr, body = code.split('{', 1)
            rx = _INL_CALL_M if MEMARG else _INL_CALL
            body = rx.sub(lambda m: (used.add(int(m.group(1), 16)) or f"inl_{m.group(1)}({'c, _mb' if MEMARG else 'c'})")
                          if int(m.group(1), 16) in _INL else m.group(0), body)
            code = hdr + '{' + body
        left.update(_jt_left(L, L.last_blocks))
        parts.append(code); defined.append(a)
        refs |= {t for t in tg if L.in_text(t)}
        traps += L.traps; trunc += L.truncated
        kinds.update(L.trap_kinds); L.trap_kinds.clear()
    path=f"{OUT}/shard_{idx:04d}.c"
    with open(path,'w') as f:
        f.write((_lregs().SHARD_DEFINE if LREGS else '') + '#include "cpu.h"\n#include "decls.h"\n#include <math.h>\n\n')
        if MEMARG: f.write(_MA_PRO + '\n')
        for x in sorted(used): f.write(_inl_def(x) + "\n")
        f.write("\n".join(parts))
        f.write("\n")
    return idx, defined, sorted(refs), traps, trunc, dict(kinds), os.path.getsize(path), sorted(L.xp_hits), sorted(left)

if __name__=='__main__':
    t0=time.time()
    print("Phase 1: discovering the function set...")
    funcs, _fixed, _relref = discover_all()
    print(f"  {len(funcs)} functions  ({time.time()-t0:.0f}s)")
    jt_tabs = {}
    if os.environ.get('JTSWITCH', '') == '1': funcs, jt_tabs = drop_table_targets(funcs, _fixed, _relref)

    # a previous run's extra shards (LIFT_MISSING) and stubs must not outlive it
    import glob as _glob
    for _p in _glob.glob(f"{OUT}/shard_*.c"):
        if int(os.path.basename(_p)[6:10]) >= NSHARD: os.remove(_p)
    if os.path.exists(f"{OUT}/stubs.c"): os.remove(f"{OUT}/stubs.c")
    chunks=[(i, funcs[i::NSHARD]) for i in range(NSHARD)]
    hk=os.environ.get('HOOKS',''); wt=os.environ.get('WATCH','')
    if OVERRIDES: print(f"  [override: {[hex(a) for a in sorted(OVERRIDES)]}]")
    print(f"\nFaz 2: {NSHARD} shard, {mp.cpu_count()} cores..."
          + (f"  [hook: {hk}]" if hk else "")
          + ("  [COVERAGE measurement]" if os.environ.get('COVERAGE','')=='1' else "") + ("  [WATCHPOINT instrumentation]" if wt=='1' else ""))
    t1=time.time()
    inl = {}
    if INLINE_MAX or INLINE_LIST:
        with mp.Pool(mp.cpu_count(), initializer=_init) as pool:
            for a, code in pool.imap_unordered(_inlprobe, funcs if INLINE_MAX else [f for f in funcs if f in INLINE_LIST], chunksize=64):
                if code: inl[a] = code
        print(f"  [inline: {len(inl)} functions: {len(INLINE_LIST & set(inl))} of the {len(INLINE_LIST)} in INLINE_LIST"
              + (f", leaf functions <= {INLINE_MAX} instructions" if INLINE_MAX else "") + f"]  ({time.time()-t1:.0f}s)")
    defined=set(); refs=set(); traps=0; trunc=0; kinds=collections.Counter(); bytes_=0
    with mp.Pool(mp.cpu_count(), initializer=_init, initargs=(inl,)) as pool:
        xhits=set(); jt_left=set()
        for n,(idx,d,r,tp,tr,kk,sz,xh,lf) in enumerate(pool.imap_unordered(_shard, chunks)):
            defined |= set(d); refs |= set(r); traps+=tp; trunc+=tr; xhits |= set(xh); jt_left |= set(lf)
            kinds.update(kk); bytes_+=sz
            if (n+1)%16==0: print(f"  {n+1}/{NSHARD} shard  ({time.time()-t1:.0f}s)")
    print(f"  generation done ({time.time()-t1:.0f}s)")

    # LIFT_MISSING=1: call targets in .text that discovery missed (its linear scan
    # can stop on bytes an earlier, misaligned scan already covered) are lifted
    # too, in extra shards, instead of becoming "stub" traps.  Repeated until no
    # new target appears.  tools/gen_v2.sh turns it on (NOCLOSURE=1: off).  With
    # JTSWITCH the targets of jump tables a lift left to the dispatcher count too.
    jt_need = lambda: {t for d in jt_left if d in jt_tabs for t in jt_tabs[d]}
    if os.environ.get('LIFT_MISSING') == '1' or jt_tabs:
        _init(inl); extra = NSHARD
        while True:
            more = sorted(a for a in (refs | jt_need()) - defined if _L.in_text(a))
            if not more: break
            if extra >= NSHARD + 64: raise SystemExit("lift-missing: no end after 64 extra shards")
            idx, d, r, tp, tr, kk, sz, xh, lf = _shard((extra, more)); xhits |= set(xh); jt_left |= set(lf)
            print(f"  [lift-missing] shard_{extra:04d}: {', '.join(hex(a) for a in more)}")
            defined |= set(d); refs |= set(r); traps += tp; trunc += tr; kinds.update(kk); bytes_ += sz
            extra += 1
    # LOCAL PATCH: xpatch header + a check that every site was found in some function
    spec = xpatch.load(os.environ.get('XPATCH'))
    with open(f"{OUT}/xpatch.h",'w') as f:
        f.write(spec.header() if spec else "#pragma once\n#define XP_COUNT 0\n#define XPV_COUNT 0\n"
                "static const char *const xp_names[] = { 0 };\nstatic const char *const xpv_names[] = { 0 };\n")
    if spec:
        hit_names = {n for n, a in xhits}
        lost = [n for n in spec.names if n not in hit_names]
        print(f"  [xpatch: {len(spec.names)} switches, {len(xhits)} sites lifted]")
        for n, a in sorted(xhits, key=lambda t: t[1]): print(f"    {a:#x}  {n}")
        if lost: raise SystemExit(f"xpatch: no site found for {lost}")
    missing = sorted((refs | jt_need()) - defined)
    print(f"\n  defined: {len(defined)}   referenced: {len(refs)}   MISSING: {len(missing)}")
    if missing or (MEMARG and OVERRIDES):
        with open(f"{OUT}/stubs.c",'w') as f:
            f.write('#include "cpu.h"\n#include "decls.h"\n\n')
            for a in missing:
                f.write(f"void sub_{a:08x}(CPU *c){{ unsupported_insn(c,0x{a:x}u,\"stub\"); POP32(c->eip); }}\n")
            if MEMARG:   # lifted code calls everyone through _m: a bridge for the missing ones and overrides
                for a in sorted(set(missing) | OVERRIDES):
                    f.write(f"void sub_{a:08x}_m(CPU *restrict c, uint8_t *restrict _mb){{ (void)_mb; sub_{a:08x}(c); }}\n")
        print(f"  -> stubs.c ({len(missing)} stub)")

    allf = sorted(defined | set(missing))
    with open(f"{OUT}/decls.h",'w') as f:
        f.write("#ifndef DECLS_H\n#define DECLS_H\n#include \"cpu.h\"\n")
        f.write("void dispatch_indirect(CPU*,uint32_t);\nvoid unsupported_insn(CPU*,uint32_t,const char*);\n")
        f.write("void cpuid_shim(CPU*);\nuint64_t rdtsc_shim(void);\n")
        f.write("extern unsigned char g_xpatch[];\nextern unsigned int g_xpval[];\n")   # LOCAL PATCH: xpatch
        for a in allf: f.write(f"void sub_{a:08x}(CPU*);\n")
        for a in sorted(OVERRIDES): f.write(f"void sub_{a:08x}_orig(CPU*);\n")
        if MEMARG:
            for a in allf: f.write(f"void sub_{a:08x}_m(CPU *restrict, uint8_t *restrict);\n")
            for a in sorted(OVERRIDES): f.write(f"void sub_{a:08x}_orig_m(CPU *restrict, uint8_t *restrict);\n")
        f.write("#endif\n")
    with open(f"{OUT}/fntab.c",'w') as f:
        f.write('#include "cpu.h"\n#include "decls.h"\ntypedef void(*guest_fn)(CPU*);\n')
        f.write(f"const uint32_t g_{SYMPFX}fn_count = {len(allf)};\n")
        f.write(f"const uint32_t g_{SYMPFX}fn_addr[] = {{\n")
        for i in range(0,len(allf),8): f.write("  "+",".join(f"0x{a:08x}u" for a in allf[i:i+8])+",\n")
        f.write(f"}};\nconst guest_fn g_{SYMPFX}fn_ptr[] = {{\n")
        for i in range(0,len(allf),4): f.write("  "+",".join(f"sub_{a:08x}" for a in allf[i:i+4])+",\n")
        f.write("};\n")
    print(f"\n=== URETIM OZETI ({time.time()-t0:.0f}s) ===")
    print(f"  functions        : {len(allf)}")
    print(f"  C source size    : {bytes_/1048576:.1f} MB ({NSHARD} shard)")
    print(f"  traps (unsupported instruction) : {traps}")
    print(f"  truncated branch targets        : {trunc}")
    print("\n  most common trap reasons:")
    for k,v in collections.Counter(kinds).most_common(12): print(f"    {k:16s} {v}")
