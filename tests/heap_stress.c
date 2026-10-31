/* heap_stress.c -- runtime/gheap.c on its own: concurrency, realloc and zero
 * semantics, VirtualAlloc regions, fragmentation, and NFSU2_HEAPCHECK against
 * planted bugs.
 *
 *   tests/heap_stress.sh               (builds it with ASan/UBSan and runs it)
 *   heap_stress                        all checks; exit 0 when they pass
 *   heap_stress hc <case>              one planted bug under NFSU2_HEAPCHECK=1
 *
 * The planted-bug cases run in child processes of the same binary: a double
 * free, a free of something that is no block, a one-byte overrun, a write
 * after free (caught when the block leaves the quarantine, and in the exit
 * sweep for one still in it), and per-site live bytes in the report.
 * Adapted from th0mk's nfsu2-web tests/heap_stress.c (MIT), which tested its
 * own heap.c. */
#include "cpu.h"
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

extern char **environ;
uint32_t gheap_alloc(uint32_t n, int zero);
int      gheap_free(uint32_t u, const char *who);
uint32_t gheap_realloc(uint32_t o, uint32_t n, int zero, int in_place_only);
uint32_t gheap_size(uint32_t u);
uint32_t gheap_top_used(void);
void     gheap_report(void);
uint32_t gheap_va_alloc(uint32_t addr, uint32_t size, uint32_t type, uint32_t prot);
int      gheap_va_free(uint32_t addr, uint32_t size, uint32_t type);
uint32_t gheap_va_query(uint32_t addr, uint32_t mbi, uint32_t len);
int      gheap_va_protect(uint32_t addr, uint32_t size, uint32_t prot, uint32_t pold);
extern uint32_t g_gheap_site;

/* ---- gheap.c's links into the rest of the runtime ------------------------ */
uint8_t *g_mem;
uint8_t  g_cbits[1u << 15] = {0};
void mem_commit(uint32_t a, uint32_t n){
    for (uint32_t pg = a >> 14, last = (a + n - 1u) >> 14; n && pg <= last; pg++) g_cbits[pg >> 3] |= (uint8_t)(1u << (pg & 7));
}
long metal_frames(void){ return 0; }
void com_gbuf_fmt(char *s, size_t n){ snprintf(s, n, "-"); }

static int fails = 0;
#define CHK(name, cond) do{ if (cond) printf("  ok    %s\n", name); else { printf("  FAIL  %s\n", name); fails++; } }while(0)
static uint32_t rnd32(uint32_t *s){ *s = *s * 1103515245u + 12345u; return *s >> 7; }

/* ---- 1. host threads allocating at the same time ------------------------- */
enum { NT = 8, NB = 400 };
typedef struct { int id; uint32_t p[NB], n[NB]; int k[NB]; long ops, bad, zbad, nullr; } TS;
static TS g_ts[NT];
static void fill(uint32_t p, uint32_t n, int id, int k){ for (uint32_t i = 0; i < n; i += 7) MR8(p + i) = (uint8_t)(id * 31 + k + i); }
static int intact(uint32_t p, uint32_t n, int id, int k){
    for (uint32_t i = 0; i < n; i += 7) if (MR8(p + i) != (uint8_t)(id * 31 + k + i)) return 0;
    return 1;
}
static int zeroed(uint32_t p, uint32_t from, uint32_t to){ for (uint32_t i = from; i < to; i++) if (MR8(p + i)) return 0; return 1; }
static void *worker(void *arg){
    TS *t = arg; uint32_t seed = 0x1234u + (uint32_t)t->id * 7919u;
    for (int r = 0; r < 20000; r++){
        int i = (int)(rnd32(&seed) % NB);
        if (t->p[i]){
            if (!intact(t->p[i], t->n[i], t->id, t->k[i])) t->bad++;
            if (rnd32(&seed) & 1){ gheap_free(t->p[i], "HeapFree"); t->p[i] = 0; }
            else {                                               /* realloc, keeps the prefix */
                uint32_t nn = 1u + rnd32(&seed) % ((rnd32(&seed) & 15) ? 600u : 70000u);
                uint32_t q = gheap_realloc(t->p[i], nn, 1, 0);
                if (!q){ t->nullr++; continue; }
                uint32_t keep = t->n[i] < nn ? t->n[i] : nn;
                for (uint32_t z = 0; z < keep; z += 7) if (MR8(q + z) != (uint8_t)(t->id * 31 + t->k[i] + z)) { t->bad++; break; }
                if (nn > t->n[i] && !zeroed(q, t->n[i], nn)) t->zbad++;
                t->p[i] = q; t->n[i] = nn; t->k[i]++; fill(q, nn, t->id, t->k[i]);
            }
        } else {
            uint32_t nn = 1u + rnd32(&seed) % ((rnd32(&seed) & 15) ? 600u : 70000u);
            int z = (int)(rnd32(&seed) & 1);
            uint32_t q = gheap_alloc(nn, z);
            if (!q){ t->nullr++; continue; }
            if (z && !zeroed(q, 0, nn)) t->zbad++;
            t->p[i] = q; t->n[i] = nn; t->k[i] = r & 255; fill(q, nn, t->id, t->k[i]);
        }
        t->ops++;
    }
    return 0;
}
static int cmpu(const void *a, const void *b){ const uint32_t *x = a, *y = b; return x[0] < y[0] ? -1 : x[0] > y[0]; }
static void threads(void){
    printf("threads: %d host threads, 20000 operations each\n", NT);
    pthread_t th[NT];
    for (int i = 0; i < NT; i++){ g_ts[i].id = i + 1; pthread_create(&th[i], 0, worker, &g_ts[i]); }
    for (int i = 0; i < NT; i++) pthread_join(th[i], 0);
    long bad = 0, zbad = 0, nul = 0, ops = 0;
    static uint32_t live[NT * NB][2]; int nl = 0;
    for (int i = 0; i < NT; i++){
        bad += g_ts[i].bad; zbad += g_ts[i].zbad; nul += g_ts[i].nullr; ops += g_ts[i].ops;
        for (int j = 0; j < NB; j++) if (g_ts[i].p[j]){
            if (!intact(g_ts[i].p[j], g_ts[i].n[j], g_ts[i].id, g_ts[i].k[j])) bad++;
            if (gheap_size(g_ts[i].p[j]) != g_ts[i].n[j]) bad++;
            live[nl][0] = g_ts[i].p[j]; live[nl][1] = g_ts[i].n[j]; nl++; }
    }
    qsort(live, (size_t)nl, sizeof live[0], cmpu);
    int overlap = 0;
    for (int i = 1; i < nl; i++) if (live[i-1][0] + live[i-1][1] > live[i][0]) overlap++;
    printf("        %ld operations, %d live blocks\n", ops, nl);
    CHK("no block lost its contents (contents, HeapSize)", bad == 0);
    CHK("zeroed allocations and realloc growth read as zeros", zbad == 0);
    CHK("no allocation failed", nul == 0);
    CHK("no two live blocks overlap", overlap == 0);
    for (int i = 0; i < NT; i++) for (int j = 0; j < NB; j++) if (g_ts[i].p[j]){ gheap_free(g_ts[i].p[j], "HeapFree"); g_ts[i].p[j] = 0; }
}

/* ---- 2. realloc and zero semantics ---------------------------------------- */
static void realloc_zero(void){
    printf("realloc: growth, shrinking, in place only\n");
    uint32_t p = gheap_alloc(100, 0);
    for (uint32_t i = 0; i < 100; i++) MR8(p + i) = (uint8_t)i;
    uint32_t q = gheap_realloc(p, 5000, 1, 0), ok = q != 0;
    for (uint32_t i = 0; i < 100 && ok; i++) ok = MR8(q + i) == (uint8_t)i;
    CHK("grown: the old bytes kept", ok);
    CHK("grown with HEAP_ZERO_MEMORY: the new bytes are zero", q && zeroed(q, 100, 5000));
    uint32_t r = gheap_realloc(q, 50, 0, 0);
    CHK("shrunk in place: same block, size 50", r == q && gheap_size(r) == 50);
    uint32_t big = gheap_alloc(64, 0), blk = gheap_alloc(64, 0);
    uint32_t s = gheap_realloc(big, 1u << 20, 0, 1);
    CHK("HEAP_REALLOC_IN_PLACE_ONLY with a block after it fails and leaves the block", s == 0 && gheap_size(big) == 64);
    gheap_free(r, "HeapFree"); gheap_free(big, "HeapFree"); gheap_free(blk, "HeapFree");
    CHK("a zero size is a valid block", gheap_alloc(0, 0) != 0);
}

/* ---- 3. VirtualAlloc regions ---------------------------------------------- */
static void virtual(void){
    printf("VirtualAlloc: reserve, commit inside, decommit, query, protect, release\n");
    uint32_t top0 = gheap_top_used();
    (void)top0;
    uint32_t base = gheap_va_alloc(0, 0x100000u, 0x2000u, 4u);                /* MEM_RESERVE, 1 MB */
    CHK("a reservation is page aligned and zeroed", base && !(base & 0xFFFu) && zeroed(base, 0, 0x100000u));
    uint32_t c1 = gheap_va_alloc(base, 0x3000u, 0x1000u, 4u), c2 = gheap_va_alloc(base + 0x5123u, 0x2000u, 0x1000u, 4u);
    CHK("MEM_COMMIT inside the region gives its own address (page base)", c1 == base && c2 == base + 0x5000u);
    CHK("MEM_COMMIT past the region's end is refused", gheap_va_alloc(base + 0xFF000u, 0x2000u, 0x1000u, 4u) == 0);
    memset(g_mem + base, 0xAB, 0x6000u);
    gheap_va_free(base + 0x1000u, 0x1000u, 0x4000u);                            /* MEM_DECOMMIT one page */
    CHK("a decommitted page reads as zeros, its neighbours keep their bytes",
        zeroed(base + 0x1000u, 0, 0x1000u) && MR8(base) == 0xAB && MR8(base + 0x2000u) == 0xAB);
    uint32_t mbi = gheap_alloc(28, 1);
    uint32_t qn = gheap_va_query(base + 0x2345u, mbi, 28);
    CHK("VirtualQuery: the region, committed, private",
        qn == 28 && MR32(mbi) == base + 0x2000u && MR32(mbi + 4) == base && MR32(mbi + 12) == 0x100000u - 0x2000u
        && MR32(mbi + 16) == 0x1000u && MR32(mbi + 24) == 0x20000u);
    uint32_t old = gheap_alloc(4, 1);
    int pr = gheap_va_protect(base, 0x1000u, 0x40u, old), pr2 = gheap_va_protect(base, 0x1000u, 0x04u, old);
    CHK("VirtualProtect answers the region's protection before the change", pr && pr2 && MR32(old) == 0x40u);
    CHK("MEM_RELEASE needs the region's base", gheap_va_free(base + 0x1000u, 0, 0x8000u) == 0);
    CHK("MEM_RELEASE of the base frees it", gheap_va_free(base, 0, 0x8000u) == 1);
    gheap_va_query(base, mbi, 28);
    CHK("a released region is not one any more", MR32(mbi + 4) != base || MR32(mbi + 16) != 0x1000u);
    /* the allocator pattern of D3DX 0x671cdb: reserve, commit, commit more, release; 300 times */
    uint32_t top1 = gheap_top_used();
    for (int i = 0; i < 300; i++){
        uint32_t b = gheap_va_alloc(0, 0x40000u, 0x2000u, 4u);
        gheap_va_alloc(b, 0x1000u, 0x1000u, 4u);
        gheap_va_alloc(b + 0x1000u, 0x10000u, 0x1000u, 4u);
        gheap_va_alloc(b + 0x11000u, 0x20000u, 0x1000u, 4u);
        gheap_va_free(b, 0, 0x8000u);
    }
    uint32_t top2 = gheap_top_used();
    printf("        arena top %u KB -> %u KB -> %u KB after 300 reserve/commit/release cycles\n", top0 >> 10, top1 >> 10, top2 >> 10);
    CHK("reserve/commit/release cycles do not grow the arena (commits took new blocks before)", (int64_t)top2 - (int64_t)top1 < 0x100000);
    gheap_free(mbi, "HeapFree"); gheap_free(old, "HeapFree");
}

/* ---- 4. fragmentation ------------------------------------------------------ */
static void fragmentation(void){
    printf("fragmentation: free every other block, allocate again\n");
    enum { N = 4000 };
    static uint32_t p[N];
    uint32_t seed = 99;
    for (int i = 0; i < N; i++) p[i] = gheap_alloc(16u + rnd32(&seed) % 9000u, 0);
    uint32_t top1 = gheap_top_used();
    for (int round = 0; round < 6; round++){
        for (int i = round & 1; i < N; i += 2){ gheap_free(p[i], "HeapFree"); p[i] = 0; }
        for (int i = round & 1; i < N; i += 2) p[i] = gheap_alloc(16u + rnd32(&seed) % 9000u, 0);
    }
    uint32_t top2 = gheap_top_used();
    printf("        arena top %u KB -> %u KB over 6 rounds\n", top1 >> 10, top2 >> 10);
    CHK("freed space is reused (top grows by less than half)", (int64_t)top2 - (int64_t)top1 < (int64_t)(top1 / 2u));
    for (int i = 0; i < N; i++) if (p[i]) gheap_free(p[i], "HeapFree");
}

/* ---- 5. planted bugs, NFSU2_HEAPCHECK=1 ------------------------------------ */
static void planted(const char *what){
    g_gheap_site = 0x00456789u;
    if (!strcmp(what, "double")){ uint32_t p = gheap_alloc(40, 0); gheap_free(p, "HeapFree"); gheap_free(p, "HeapFree"); }
    else if (!strcmp(what, "invalid")){ uint32_t p = gheap_alloc(40, 0); gheap_free(p + 16u, "HeapFree"); gheap_free(0x12345670u, "HeapFree"); }
    else if (!strcmp(what, "overrun")){ uint32_t p = gheap_alloc(40, 0); MR8(p + 40u) = 1; gheap_free(p, "HeapFree"); }
    else if (!strcmp(what, "uaf")){                     /* written after free: the exit sweep sees it */
        uint32_t p = gheap_alloc(64, 0); gheap_free(p, "HeapFree"); MR32(p + 8u) = 0x11111111u; }
    else if (!strcmp(what, "uafq")){                    /* ... and the quarantine's exit, once it has passed through */
        setenv("NFSU2_HEAP_QUAR_MB", "1", 1);
        uint32_t p = gheap_alloc(64, 0); gheap_free(p, "HeapFree"); MR32(p + 8u) = 0x11111111u;
        for (int i = 0; i < 24; i++){ uint32_t q = gheap_alloc(100000, 0); gheap_free(q, "HeapFree"); } }
    else if (!strcmp(what, "sites")){                   /* per-site live bytes */
        g_gheap_site = 0x00600123u; for (int i = 0; i < 10; i++) gheap_alloc(10000, 0);
        g_gheap_site = 0x00700456u; gheap_alloc(500, 0); }
    gheap_report();
}
static int run_child(const char *self, const char *what, char *out, size_t n){
    char tmpl[] = "/tmp/heap_stress.XXXXXX"; int fd = mkstemp(tmpl);
    if (fd < 0) return -1;
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fd, 2); posix_spawn_file_actions_adddup2(&fa, fd, 1);
    char *argv[] = { (char *)self, "hc", (char *)what, 0 };
    char *env[] = { "NFSU2_HEAPCHECK=1", "NFSU2_HEAPLOG=0", "ASAN_OPTIONS=detect_leaks=0", 0 };
    pid_t pid; int st = -1;
    if (posix_spawn(&pid, self, &fa, 0, argv, env) == 0) waitpid(pid, &st, 0);
    posix_spawn_file_actions_destroy(&fa);
    ssize_t k = pread(fd, out, n - 1, 0); out[k > 0 ? k : 0] = 0;
    close(fd); unlink(tmpl);
    return st;
}
static void heapcheck(const char *self){
    printf("NFSU2_HEAPCHECK=1 against planted bugs (child processes)\n");
    static char o[65536];
    run_child(self, "double", o, sizeof o);
    CHK("a double free is reported and ignored", strstr(o, "double free, ignored") && strstr(o, "1 double / 0 bad"));
    run_child(self, "invalid", o, sizeof o);
    CHK("frees of an interior pointer and of no block are reported", strstr(o, "not a heap block") && strstr(o, "0 double / 2 bad"));
    run_child(self, "overrun", o, sizeof o);
    CHK("a one-byte overrun is reported with the code that made the block",
        strstr(o, "written past its end at +40") && strstr(o, "made by 0x00456789") && strstr(o, "1 overruns"));
    run_child(self, "uaf", o, sizeof o);
    CHK("a write after free is found by the exit sweep", strstr(o, "written after free (exit sweep)") && strstr(o, "= 0x11111111"));
    run_child(self, "uafq", o, sizeof o);
    CHK("a write after free is found when the block leaves the quarantine", strstr(o, "written after free: block") && strstr(o, "= 0x11111111"));
    run_child(self, "sites", o, sizeof o);
    CHK("live bytes by site: the largest first", strstr(o, "0x00600123        97 KB in     10 blocks") && strstr(o, "0x00700456"));
    if (fails) fputs(o, stdout);
}

int main(int argc, char **argv){
    g_mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
    if (g_mem == MAP_FAILED){ printf("FAIL: no guest memory\n"); return 1; }
    if (argc == 3 && !strcmp(argv[1], "hc")){ planted(argv[2]); return 0; }
    setenv("NFSU2_HEAPLOG", "0", 1);
    setenv("NFSU2_HEAP_QUAR_MB", "0", 1);              /* freed blocks reused at once: the arena top tells */
    threads();
    realloc_zero();
    virtual();
    fragmentation();
    heapcheck(argv[0]);
    printf(fails ? "heap stress: %d FAILED\n" : "heap stress: all passed\n", fails);
    return fails != 0;
}
