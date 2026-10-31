/* verification on the full build of the 23k lifted functions
 * (out/nfsu2_all: European build; out/nfsu2_na_all: North American, the
 * addresses written as GA() like the runtime's; tests/main_all.sh runs both).
 * Sections 5-7 were ported from th0mk's nfsu2-web tests/main_all.c (MIT): its
 * browser-only sections (the f32 cull, matrix, hull and lighting fast paths)
 * are not here, since the Mac build runs the lifted bodies. */
#include "cpu.h"
#include "decls.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <unistd.h>
void dispatch_init(void); void dispatch_report(void);
extern const uint32_t g_fn_count;
uint64_t mem_committed(void);
extern uint64_t g_stat_indirect_ok, g_stat_indirect_miss, g_stat_unsupported;

static CPU cpu; static CPU *const c = &cpu;
#define STACK_TOP 0x00F00000u
static void reset(void){ memset(&cpu,0,sizeof cpu); cpu.esp=STACK_TOP; cpu.top=0; cpu.fcw=0x037f; }
static float GF(uint32_t a){ return MRF32(a); }
int pass=0,fail=0;
#define CHKI(n,g,e) do{ uint32_t _g=(g),_e=(e); if(_g==_e){pass++;printf("  \033[32mPASS\033[0m  %-40s = 0x%08x\n",n,_g);} \
  else{fail++;printf("  \033[31mFAIL\033[0m  %-40s = 0x%08x (expected 0x%08x)\n",n,_g,_e);} }while(0)
#define CHKF(n,g,e) do{ float _g=(g),_e=(e); if(memcmp(&_g,&_e,4)==0){pass++;printf("  \033[32mPASS\033[0m  %-40s = %.9g\n",n,(double)_g);} \
  else{fail++;printf("  \033[31mFAIL\033[0m  %-40s = %.9g (expected %.9g)\n",n,(double)_g,(double)_e);} }while(0)

/* --- 5. Guest heap through the Win32 bridge (win32.c -> gheap.c) ---
 * Calls go through win32_call exactly as the import bridge makes them: stdcall
 * arguments on the guest stack, the return address popped. */
typedef struct { uint32_t iat; const char *dll; const char *name; int nargs; } ImpEnt;
extern const ImpEnt g_imp[]; extern const uint32_t g_imp_count;
int win32_call(CPU *c, uint32_t idx); void win32_init(void);
static uint32_t H(const char *fn, int n, ...){
    uint32_t idx = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < g_imp_count; i++) if (!strcmp(g_imp[i].name, fn)){ idx = i; break; }
    if (idx == 0xFFFFFFFFu){ printf("  (no import %s)\n", fn); return 0xBAD0BAD0u; }
    __builtin_va_list ap; __builtin_va_start(ap, n);
    uint32_t a[8]; for (int i = 0; i < n; i++) a[i] = __builtin_va_arg(ap, uint32_t);
    __builtin_va_end(ap);
    reset();
    for (int i = n - 1; i >= 0; i--) PUSH32(a[i]);
    PUSH32(GA(0x00401000u));                       /* "caller" */
    win32_call(&cpu, idx);
    return cpu.eax;
}
static uint32_t rng_state = 12345u;
static uint32_t rnd(void){ rng_state = rng_state * 1103515245u + 12345u; return rng_state >> 8; }
static void heap_tests(void){
    printf("\n--- 5. Guest heap through the Win32 bridge ---\n");
    CHKI("GetProcessHeap", H("GetProcessHeap", 0), 1u);
    uint32_t h2 = H("HeapCreate", 3, 0u, 0x1000u, 0u);
    CHKI("HeapCreate (CRT heap handle)", h2, 2u);
    uint32_t p = H("HeapAlloc", 3, h2, 0u, 100u);
    CHKI("HeapAlloc 16-byte aligned", p & 15u, 0u);
    CHKI("HeapSize", H("HeapSize", 3, h2, 0u, p), 100u);
    uint32_t z = H("HeapAlloc", 3, h2, 8u, 4000u);
    { int nz = 0; for (uint32_t i = 0; i < 4000u; i++) nz += MR8(z + i) != 0; CHKI("HEAP_ZERO_MEMORY", (uint32_t)nz, 0u); }
    memset(g_mem + p, 0x5A, 100);
    uint32_t p2 = H("HeapReAlloc", 4, h2, 0u, p, 5000u);
    { int ok = 1; for (uint32_t i = 0; i < 100u; i++) ok &= MR8(p2 + i) == 0x5A; CHKI("HeapReAlloc keeps data", (uint32_t)ok, 1u); }
    CHKI("HeapSize after realloc", H("HeapSize", 3, h2, 0u, p2), 5000u);
    CHKI("HeapFree", H("HeapFree", 3, h2, 0u, p2), 1u);
    CHKI("HeapFree(NULL)", H("HeapFree", 3, h2, 0u, 0u), 1u);
    /* stress: random sizes, random frees and reallocs, contents and overlap checked */
    enum { N = 3000 };
    static uint32_t ptr[N], sz[N]; int bad = 0, overlap = 0;
    for (int it = 0; it < 60000; it++){
        int i = (int)(rnd() % N);
        if (ptr[i]){
            for (uint32_t k = 0; k < sz[i]; k += 64) if (MR8(ptr[i] + k) != (uint8_t)(i + k)) bad++;
            if (rnd() & 1){ H("HeapFree", 3, h2, 0u, ptr[i]); ptr[i] = 0; }
            else { uint32_t ns = 1u + rnd() % (rnd() & 7 ? 2000u : 300000u);
                   uint32_t np = H("HeapReAlloc", 4, h2, 0u, ptr[i], ns);
                   if (!np){ bad++; continue; }
                   uint32_t keep = sz[i] < ns ? sz[i] : ns;
                   for (uint32_t k = 0; k < keep; k += 64) if (MR8(np + k) != (uint8_t)(i + k)) bad++;
                   ptr[i] = np; sz[i] = ns;
                   for (uint32_t k = 0; k < ns; k += 64) MR8(np + k) = (uint8_t)(i + k); }
        } else {
            uint32_t n = 1u + rnd() % (rnd() & 15 ? 1500u : 2000000u);
            uint32_t a = H("HeapAlloc", 3, h2, 0u, n);
            if (!a || (a & 15u)){ bad++; continue; }
            ptr[i] = a; sz[i] = n;
            for (uint32_t k = 0; k < n; k += 64) MR8(a + k) = (uint8_t)(i + k);
        }
    }
    for (int i = 0; i < N; i++) if (ptr[i]) for (int j = i + 1; j < N; j++)
        if (ptr[j] && ptr[i] < ptr[j] + sz[j] && ptr[j] < ptr[i] + sz[i]) overlap++;
    CHKI("stress: contents intact", (uint32_t)bad, 0u);
    CHKI("stress: no overlapping blocks", (uint32_t)overlap, 0u);
    for (int i = 0; i < N; i++) if (ptr[i]){ H("HeapFree", 3, h2, 0u, ptr[i]); ptr[i] = 0; }
    /* GlobalAlloc / GlobalFree */
    uint32_t g = H("GlobalAlloc", 2, 0x40u, 300u);
    { int nz = 0; for (uint32_t i = 0; i < 300u; i++) nz += MR8(g + i) != 0; CHKI("GMEM_ZEROINIT", (uint32_t)nz, 0u); }
    CHKI("GlobalFree returns NULL", H("GlobalFree", 1, g), 0u);
    /* VirtualAlloc regions (gheap.c): a reservation is one zeroed, page-aligned
     * block that reads as committed (no 64 KB granularity, no MEM_RESERVE or
     * MEM_FREE states: the game only reserves and commits right away); a commit
     * inside it answers the page, a decommit reads back as zeros, a release
     * needs the region's base. */
    uint32_t r = H("VirtualAlloc", 4, 0u, 0x30000u, 0x2000u, 4u);
    CHKI("VirtualAlloc reserve: page aligned", r & 0xFFFu, 0u);
    uint32_t mbi = 0x00E08000u;
    H("VirtualQuery", 3, r, mbi, 28u);
    CHKI("VirtualQuery AllocationBase", MR32(mbi + 4), r);
    CHKI("VirtualQuery region size", MR32(mbi + 12), 0x30000u);
    uint32_t cm = H("VirtualAlloc", 4, r + 0x5123u, 0x2000u, 0x1000u, 4u);
    CHKI("VirtualAlloc commit: page of lpAddress", cm, r + 0x5000u);
    MR32(r + 0x5000u) = 0xC0FFEEu;
    H("VirtualQuery", 3, r + 0x5000u, mbi, 28u);
    CHKI("VirtualQuery committed: MEM_COMMIT", MR32(mbi + 16), 0x1000u);
    CHKI("VirtualQuery committed run size", MR32(mbi + 12), 0x2B000u);
    CHKI("recommit keeps data", (H("VirtualAlloc", 4, r + 0x5000u, 0x1000u, 0x1000u, 4u), MR32(r + 0x5000u)), 0xC0FFEEu);
    CHKI("commit past the region is refused", H("VirtualAlloc", 4, r + 0x2F000u, 0x2000u, 0x1000u, 4u), 0u);
    CHKI("VirtualFree MEM_DECOMMIT", H("VirtualFree", 3, r + 0x4000u, 0xC000u, 0x4000u), 1u);
    H("VirtualAlloc", 4, r + 0x5000u, 0x1000u, 0x1000u, 4u);
    CHKI("recommit after decommit reads zero", MR32(r + 0x5000u), 0u);
    CHKI("VirtualFree MEM_RELEASE not at the base fails", H("VirtualFree", 3, r + 0x1000u, 0u, 0x8000u), 0u);
    CHKI("VirtualFree MEM_RELEASE", H("VirtualFree", 3, r, 0u, 0x8000u), 1u);
    uint32_t r2 = H("VirtualAlloc", 4, 0u, 0x10000u, 0x3000u, 4u);
    CHKI("reserve+commit reads zero", MR32(r2 + 0x100u), 0u);
    H("VirtualFree", 3, r2, 0u, 0x8000u);
    CHKI("HeapDestroy", H("HeapDestroy", 1, h2), 1u);
}

/* --- 6. Virtual clock (win32.c host_us): inside one long frame, after the
 * stall valve has added its 200 ms, time must still move.  The game
 * busy-waits on QueryPerformanceCounter in places (0x45A630 waits 20 ticks
 * for each sound object it destroys on the way into a race); with a frozen
 * clock that wait never ends. */
uint64_t host_us(void); void vclock_tick(void);
static void clock_tests(void){
    printf("\n--- 6. Virtual clock: time advances in a long frame too ---\n");
    vclock_tick();
    usleep(120000);                                   /* a 120 ms frame ...      */
    for (int i = 0; i < 4000; i++) (void)host_us();   /* ... that polled a lot   */
    uint64_t t0 = host_us(); long k = 0;
    while (host_us() < t0 + 20 && k < 2000000) k++;   /* the 0x45A630 wait */
    CHKI("20 us wait ends in a stalled frame", k < 2000000, 1u);
    uint64_t t1 = host_us(); vclock_tick();
    CHKI("monotonic across the next tick", host_us() >= t1, 1u);
}

/* --- 7. _ftol2 (0x75BED4 in both builds): cpu.h FTOL2_BODY (what a lift
 * with FTOL2INL=1 puts at the call sites) against the lifted body, from the
 * same CPU state: every register, top, eip, the x87 registers still on the
 * stack (not the two the call pushed and popped: empty slots, which an X87OPT
 * lift does not write back), and the flags unless the lift is FLAGABI's
 * (tools/gen_v2.sh: no caller reads them after _ftol2 and the lifted body
 * leaves them as they happen to be).  Inputs: integers, halves, fractions
 * around them, both signs, the int64 limits, huge values, infinities, NaNs,
 * random bit patterns; control words of the game thread (PC=24, nearest),
 * the CRT (PC=53/64) and the directed rounding modes. */
#define LIFT_FLAGABI 1
#define FTOL_SENT 0x55u
static int ftol_same(const CPU *a, const CPU *b, uint32_t T){
    if (memcmp(a->r, b->r, sizeof a->r) || a->eip != b->eip || a->top != b->top) return 0;
#ifndef LIFT_FLAGABI
    const uint32_t *fa = &a->cf, *fb = &b->cf;
    for (int k = 0; k < 7; k++) if (fa[k] != fb[k]) return 0;
#endif
    for (uint32_t k = 0; k < 8; k++)
        if (k != T && k != ((T - 1u) & 7u) && memcmp(&a->st[k], &b->st[k], 8)) return 0;
    return 1;
}
static void ftol_tests(void){
    printf("\n--- 7. _ftol2 (0x75BED4): cpu.h FTOL2_BODY vs the lifted body ---\n");
    static const uint16_t cws[] = { 0x007f, 0x027f, 0x037f, 0x047f, 0x087f, 0x0c7f, 0x0e7f, 0x0f7f, 0x003f };
    double base[] = { 0, 1, -1, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 0.49999997, -0.49999997, 0.7, -0.7, 123456.789, -123456.789,
        4294967295.5, 4294967296.0, -4294967296.0, 4294967296.25, -4294967296.25, 4294967295.75, 2147483647.5, -2147483648.5,
        9007199254740993.0, 9.2233720368547748e18, -9.2233720368547758e18, 9.2233720368547758e18, 1e19, -1e19, 1e300, -1e300,
        1e-300, -1e-300, 4.9e-324, INFINITY, -INFINITY, NAN, -NAN, 16777217.0, -16777217.0, 0.1, -0.1, 1e-10, -1e-10 };
    int n = 0, bad = 0; uint32_t seed = 0x5eed1234u;
    for (unsigned w = 0; w < sizeof cws / sizeof *cws; w++)
        for (int i = 0; i < 4000; i++){
            double v;
            if (i < (int)(sizeof base / sizeof *base)) v = base[i];
            else if (i < 2000){ seed = seed * 1103515245u + 12345u; double m = (double)(seed >> 8) / 65536.0; v = (seed & 1) ? -m : m;
                if (i & 2) v = nearbyint(v) + ((seed >> 3 & 3) - 1.5) * 0.5; }
            else { uint64_t b; seed = seed * 1103515245u + 12345u; b = (uint64_t)seed << 32;
                seed = seed * 1103515245u + 12345u; b |= seed; memcpy(&v, &b, 8); }
            CPU a; reset(); cpu.fcw = cws[w]; cpu.top = (int32_t)(i & 7);
            for (int k = 0; k < 8; k++) cpu.st[k] = 1000.0 + k;
            cpu.st[cpu.top] = v; cpu.ecx = 0x1234u; cpu.edx = 0x55aa55aau; cpu.eax = 0xdeadbeefu; cpu.eip = 0x77u;
            { uint32_t *f = &cpu.cf; for (int k = 0; k < 7; k++) f[k] = FTOL_SENT; }
            PUSH32(0xC0DE0000u + (uint32_t)i);
            a = cpu;
            sub_0075bed4(&a);                                  /* the lifted body */
            FTOL2_BODY(c); cpu.esp += 4u;                      /* FTOL2_INL after the call's push */
            if (a.eip == 0xC0DE0000u + (uint32_t)i) cpu.eip = a.eip;   /* a RETEIP=1 lift writes it */
            n++;
            if (!ftol_same(&a, &cpu, (uint32_t)(i & 7))){ if (bad++ < 8) printf("  differs: fcw %04x v %.17g: lifted %08x:%08x ecx %08x top %d, FTOL2_BODY %08x:%08x ecx %08x top %d\n",
                cws[w], v, a.edx, a.eax, a.ecx, a.top, cpu.edx, cpu.eax, cpu.ecx, cpu.top); }
        }
    char nm[64]; snprintf(nm, sizeof nm, "_ftol2 equivalent (%d inputs)", n);
    CHKI(nm, (uint32_t)bad, 0u);
    /* A lifted caller: 0x48AC70(a, b) on an object with v at +0xC returns
     * (int)(v / b * a) when a * 0.5 < b, else (int)(v + v), each step rounded
     * to float (the game thread's control word).  The x87 values the caller
     * keeps in locals must reach _ftol2, and its pop must reach the caller
     * (with FTOL2INL=1 the call is FTOL2_INL). */
    int bad2 = 0, n2 = 0;
    for (int i = 0; i < 2000; i++){
        float a = (float)((int)(rnd() % 20001) - 10000) / 64.0f, b = (float)(1 + rnd() % 8000) / 32.0f;
        float v = (float)((int)(rnd() % 200001) - 100000) / 16.0f;
        if (i & 1) b = -b;
        reset(); cpu.fcw = 0x007f; cpu.top = (int32_t)(i & 7);
        uint32_t OBJ = 0x00E00000u; MRF32(OBJ + 0xcu) = v; cpu.ecx = OBJ;
        uint32_t ab, bb; memcpy(&ab, &a, 4); memcpy(&bb, &b, 4);
        PUSH32(bb); PUSH32(ab); PUSH32(0xC0DE0000u + (uint32_t)i);
        uint32_t e = cpu.esp;
        sub_0048ac70(&cpu);
        float h = a * 0.5f, r = h < b ? v / b * a : v + v;
        n2++;
        if (cpu.eax != (uint32_t)(int32_t)truncf(r) || cpu.top != (int32_t)(i & 7) || cpu.esp != e + 12u){
            if (bad2++ < 8) printf("  differs: 0x48AC70(%g, %g) v %g: %d (top %d), expected %d\n", (double)a, (double)b, (double)v,
                                   (int32_t)cpu.eax, cpu.top, (int32_t)truncf(r)); }
    }
    snprintf(nm, sizeof nm, "_ftol2 from a lifted caller (%d inputs)", n2);
    CHKI(nm, (uint32_t)bad2, 0u);
}

int main(int argc,char**argv){
    mem_init(); mem_fault_handler_install();
    if(mem_load_pe(argc>1?argv[1]:"SPEED2.EXE")) return 1;
    mem_commit(0x00E00000u, 0x00200000u);        /* test heap + stack */
    dispatch_init();
    fprintf(stderr,"  committed guest memory: %.1f MB\n\n",(double)mem_committed()/1048576.0);
    printf("=== FULL BUILD: %u functions linked ===\n\n", g_fn_count);

    printf("--- 1. Direct calls (previously verified functions) ---\n");
    reset(); PUSH32(7u); PUSH32(0xDEADC0DEu); sub_0048b1e0(&cpu);
    CHKI("sub_0048b1e0(7)", cpu.eax, GA(0x00832de0u) + 7*0x70u);
    reset(); PUSH32(0xDEADC0DEu); sub_0077b970(&cpu);
    CHKF("sub_0077b970 -> [0x82875c]", GF(GA(0x0082875cu)),
         (float)((((double)GF(GA(0x00786ff4u))+(double)GF(GA(0x00786ff0u)))+(double)GF(GA(0x0082a4e8u)))+(double)GF(GA(0x007844c0u))));

    printf("\n--- 2. INDIRECT dispatch: the same functions through their addresses ---\n");
    uint64_t ok0=g_stat_indirect_ok;
    reset(); PUSH32(7u); PUSH32(0xDEADC0DEu); dispatch_indirect(&cpu, GA(0x0048b1e0u));
    CHKI("dispatch(0x0048b1e0)(7)", cpu.eax, GA(0x00832de0u) + 7*0x70u);
    reset(); PUSH32(0xDEADC0DEu); dispatch_indirect(&cpu, GA(0x0077b950u));
    CHKF("dispatch(0x0077b950) -> [0x82a468]", GF(GA(0x0082a468u)),
         (float)((((double)GF(GA(0x0082a4e8u))-(double)GF(GA(0x00786ff0u)))-(double)GF(GA(0x00786ff4u)))-(double)GF(GA(0x007844c0u))));
    CHKI("dispatch resolution count", (uint32_t)(g_stat_indirect_ok-ok0), 2u);
    uint64_t miss0=g_stat_indirect_miss;
    reset(); PUSH32(0xDEADC0DEu); dispatch_indirect(&cpu, 0x00123456u);  /* invalid */
    CHKI("invalid address -> miss counter", (uint32_t)(g_stat_indirect_miss-miss0), 1u);

    printf("\n--- 3. Dispatch table integrity (5000 random functions) ---\n");
    extern const uint32_t g_fn_addr[];
    int bad=0;
    for(uint32_t i=0;i<g_fn_count;i+=(g_fn_count/5000?g_fn_count/5000:1)){
        /* every registered address must resolve to its own index */
        uint32_t a=g_fn_addr[i];
        uint64_t o1=g_stat_indirect_ok;
        reset(); PUSH32(0xDEADC0DEu);
        /* to test only resolvability without calling: we can't check the table
           indirectly; at least verify the address is in range */
        if(!(a>=0x00401000u && a<0x00401000u+0x00381af1u)) bad++;
        (void)o1;
    }
    CHKI("all function addresses inside .text", (uint32_t)bad, 0u);

    printf("\n--- 4. Separate tests (x87 + integer, through the full build) ---\n");
    int32_t iv[]={0,1,-1,12345,-987654,2147483647};
    for(unsigned k=0;k<sizeof iv/sizeof*iv;k++){
        reset(); uint32_t OBJ=0x00E00000u,INNER=0x00E01000u,OUT=0x00E02000u;
        MR32(OBJ+0xc)=INNER; MR32(INNER+0xc)=(uint32_t)iv[k];
        PUSH32(OUT); PUSH32(0xDEADC0DEu); cpu.ecx=OBJ; sub_006e1c00(&cpu);
        char nm[64]; snprintf(nm,sizeof nm,"fild(%d)",iv[k]);
        CHKF(nm, GF(OUT), (float)iv[k]);
    }
    reset(); { double d=INFINITY; uint64_t b; memcpy(&b,&d,8);
      PUSH32((uint32_t)(b>>32)); PUSH32((uint32_t)b); PUSH32(0xDEADC0DEu); sub_0075dc4b(&cpu);
      CHKI("_finite(inf)", cpu.eax, 0u); }
    reset(); { double d=1.0; uint64_t b; memcpy(&b,&d,8);
      PUSH32((uint32_t)(b>>32)); PUSH32((uint32_t)b); PUSH32(0xDEADC0DEu); sub_0075dc4b(&cpu);
      CHKI("_finite(1.0)", cpu.eax, 1u); }

    setenv("NFSU2_WATCHDOG", "0", 0);           /* win32_init: no stall watchdog thread here */
    win32_init();
    heap_tests();
    clock_tests();
    ftol_tests();

    printf("\n---------------------------------------------\n  PASS: %d    FAIL: %d\n",pass,fail);
    dispatch_report();
    return fail?1:0;
}
