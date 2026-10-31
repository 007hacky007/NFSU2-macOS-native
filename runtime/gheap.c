/* Guest heap (HeapAlloc / GlobalAlloc / LocalAlloc / VirtualAlloc).
 *
 * It used to be a bump allocator whose HeapFree did nothing: real play with
 * the u2net mod + HD textures filled the 496 MB arena at ~1 MB/s and a worker
 * thread crashed after ~8 minutes on a failed allocation.  Now freed blocks
 * are reused:
 *   - every block keeps the old 16-byte header (+0 user size, +4 0xA110C8ED),
 *     so HeapSize and the diagnostic block walkers (com.c, overrides.c) work
 *     as before; +8 = block bytes incl. header, +12 = ~(block bytes);
 *   - small blocks (<= 4 KB) go to free lists by size class (16 bytes),
 *     larger ones to an address-sorted extent list that coalesces neighbours
 *     and gives the top of the arena back to the bump pointer;
 *   - a freed block first sits in a QUARANTINE FIFO (32 MB by default) before
 *     it can be reused: the game may still touch memory it just freed, which
 *     was harmless while nothing was reused;
 *   - a free of a block that isn't live (double free, bad pointer, corrupt
 *     header) is logged and ignored (the block just leaks).
 *
 * NFSU2_HEAP_QUAR_MB=<n>  quarantine size (0 = reuse at once)
 * NFSU2_HEAP_FREE=0       old behaviour (frees ignored), for A/B
 * HEAPPOISON=1            fill freed blocks with 0xFEEEFEEE and check the
 *                         pattern when they leave the quarantine
 * NFSU2_HEAPLOG=<s>       a status line every s seconds (default 60, 0 off)
 * NFSU2_HEAPCHECK=1       (test aid) every block gets a 32-byte trailer: a
 *                         canary checked when it is freed or reallocated
 *                         (an overrun is reported with the code that made the
 *                         block), and the call site, for per-site live bytes
 *                         in the report; implies HEAPPOISON.  2 also fills
 *                         new blocks with 0xCD.  NFSU2_HEAPSTAT=1: the
 *                         per-site statistics only.
 *
 * VirtualAlloc regions (gheap_va_*): a reservation is one block of the heap
 * (zeroed, 4 KB aligned) and is remembered, so a later MEM_COMMIT inside it
 * returns that address, as on Windows.  It used to give a new block each
 * time: D3DX's linear allocator (0x671cdb) reserves a region, commits its
 * first pages, and commits more as it grows; every commit took a fresh
 * block the game never used or freed.  MEM_DECOMMIT zeroes the pages (they
 * read as zeros when committed again), MEM_RELEASE frees the region;
 * VirtualQuery describes regions, the image and other guest memory, and
 * VirtualProtect answers with the region's protection (guest memory is
 * always readable and writable here).
 *
 * The heap stress test (tests/heap_stress.c) exercises all of this; its
 * VirtualAlloc, HEAPCHECK and planted-bug cases come from th0mk's nfsu2-web
 * runtime/heap.c and tests/heap_stress.c (MIT).
 */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>

#define GH_BASE  0x10000000u
#define GH_MAX   0x2F000000u
#define HDR      16u
#define SIG_USED 0xA110C8EDu
#define SIG_QUAR 0xF4EEC0DEu      /* freed, in quarantine */
#define SIG_FREE 0xF4EEF4EEu      /* freed, in a free list / extent */
#define SMALL    4096u            /* block bytes incl. header */
#define NCLASS   (SMALL / 16u + 1u)
#define POISON   0xFEEEFEEEu

static pthread_mutex_t g_lk = PTHREAD_MUTEX_INITIALIZER;
static uint32_t g_top = GH_BASE, g_committed_top = GH_BASE;

/* small free lists: host-side stacks of block addresses */
typedef struct { uint32_t *a; uint32_t n, cap; } Stack;
static Stack g_cls[NCLASS];
/* large free extents, sorted by address */
static uint32_t *g_ext_a, *g_ext_s, g_ext_n, g_ext_cap;
/* quarantine ring */
static uint32_t *g_q; static uint32_t g_q_cap, g_q_head, g_q_n;
static uint64_t g_q_bytes, g_q_lim;

static int g_free_on = -1, g_poison, g_check, g_sitestat;
#define TRAIL    32u              /* HEAPCHECK / HEAPSTAT: 16 canary bytes ... site, frame, magic */
#define TR_MAGIC 0x7A11C0DEu
#define CANARY   0xC5u
uint32_t g_gheap_site;            /* the guest code that asked (win32.c: the import's return address) */
static uint64_t st_canary, st_va_reserve, st_va_commit_in, st_va_commit_bytes, st_va_new, st_va_decommit,
                st_va_release, st_va_query, st_va_protect;
static uint64_t st_alloc, st_free, st_reuse, st_fail, st_double, st_bad, st_corrupt,
                st_inplace, st_poison_hit, st_live, st_peak_live, st_peak_top,
                st_free_bytes;

static void cfg(void){
    if (g_free_on >= 0) return;
    const char *e = getenv("NFSU2_HEAP_FREE");
    g_free_on = !(e && *e == '0');
    e = getenv("NFSU2_HEAP_QUAR_MB");
    g_q_lim = (uint64_t)((e && *e) ? strtoul(e, 0, 0) : 32ul) << 20;
    e = getenv("HEAPPOISON");
    g_poison = (e && *e && *e != '0');
    e = getenv("NFSU2_HEAPCHECK");
    g_check = e && *e ? atoi(e) : 0;
    if (g_check) g_poison = 1;
    e = getenv("NFSU2_HEAPSTAT");
    g_sitestat = g_check || (e && *e && *e != '0');
    g_q_cap = 1u << 18;
    g_q = malloc(sizeof *g_q * g_q_cap);
}

static void push(Stack *s, uint32_t v){
    if (s->n == s->cap){ s->cap = s->cap ? s->cap * 2u : 64u; s->a = realloc(s->a, sizeof *s->a * s->cap); }
    s->a[s->n++] = v;
}

static void set_hdr(uint32_t b, uint32_t user, uint32_t sig, uint32_t bytes){
    MR32(b) = user; MR32(b+4) = sig; MR32(b+8) = bytes; MR32(b+12) = ~bytes;
}

/* ---- large extents ---- */
static uint32_t ext_find(uint32_t a){            /* first index with addr >= a */
    uint32_t lo = 0, hi = g_ext_n;
    while (lo < hi){ uint32_t m = (lo + hi) / 2u; if (g_ext_a[m] < a) lo = m + 1u; else hi = m; }
    return lo;
}
static void ext_del(uint32_t i){
    memmove(g_ext_a + i, g_ext_a + i + 1, (g_ext_n - i - 1u) * 4u);
    memmove(g_ext_s + i, g_ext_s + i + 1, (g_ext_n - i - 1u) * 4u);
    g_ext_n--;
}
static void ext_add(uint32_t a, uint32_t s){
    uint32_t i = ext_find(a);
    if (i > 0 && g_ext_a[i-1] + g_ext_s[i-1] == a){          /* merge with the one below */
        i--; a = g_ext_a[i]; s += g_ext_s[i]; ext_del(i);
    }
    if (i < g_ext_n && a + s == g_ext_a[i]){                 /* and the one above */
        s += g_ext_s[i]; ext_del(i);
    }
    if (a + s == g_top){ g_top = a; return; }                /* back to the wilderness */
    if (g_ext_n == g_ext_cap){
        g_ext_cap = g_ext_cap ? g_ext_cap * 2u : 256u;
        g_ext_a = realloc(g_ext_a, 4u * g_ext_cap); g_ext_s = realloc(g_ext_s, 4u * g_ext_cap);
    }
    memmove(g_ext_a + i + 1, g_ext_a + i, (g_ext_n - i) * 4u);
    memmove(g_ext_s + i + 1, g_ext_s + i, (g_ext_n - i) * 4u);
    g_ext_a[i] = a; g_ext_s[i] = s; g_ext_n++;
    set_hdr(a, 0, SIG_FREE, s);
}

/* a block leaves the quarantine (or skips it) and becomes reusable */
static void release(uint32_t b){
    uint32_t bytes = MR32(b+8);
    if (g_poison){
        uint32_t n = MR32(b), bad = 0xFFFFFFFFu;
        for (uint32_t o = 0; o + 4u <= n; o += 4u)
            if (MR32(b + HDR + o) != POISON){ bad = o; break; }
        if (bad != 0xFFFFFFFFu && st_poison_hit++ < 20)
            fprintf(stderr, "  [heap] written after free: block 0x%08x (%u bytes) at +%u = 0x%08x\n",
                    b + HDR, n, bad, MR32(b + HDR + bad));
    }
    st_free_bytes += bytes;
    if (bytes <= SMALL){ set_hdr(b, 0, SIG_FREE, bytes); push(&g_cls[bytes / 16u], b); }
    else { uint32_t t = g_top; ext_add(b, bytes);
           if (g_top != t) st_free_bytes -= t - g_top; }
}

static void quarantine(uint32_t b){
    uint32_t bytes = MR32(b+8);
    MR32(b+4) = SIG_QUAR;
    if (g_poison){ uint32_t n = MR32(b);
                   for (uint32_t o = 0; o + 4u <= n; o += 4u) MR32(b + HDR + o) = POISON; }
    if (!g_q_lim){ release(b); return; }
    g_q[(g_q_head + g_q_n) & (g_q_cap - 1u)] = b; g_q_n++; g_q_bytes += bytes;
    while (g_q_n && (g_q_bytes > g_q_lim || g_q_n == g_q_cap)){
        uint32_t o = g_q[g_q_head]; g_q_head = (g_q_head + 1u) & (g_q_cap - 1u); g_q_n--;
        g_q_bytes -= MR32(o+8);
        release(o);
    }
}

/* the extent with the smallest size >= need (or 0) */
static int take_extent(uint32_t need, uint32_t *out){
    uint32_t best = 0xFFFFFFFFu, bs = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < g_ext_n; i++)
        if (g_ext_s[i] >= need && g_ext_s[i] < bs){ bs = g_ext_s[i]; best = i; if (bs == need) break; }
    if (best == 0xFFFFFFFFu) return 0;
    uint32_t a = g_ext_a[best], rest = bs - need;
    *out = a;
    if (rest > SMALL){ g_ext_a[best] = a + need; g_ext_s[best] = rest; set_hdr(a + need, 0, SIG_FREE, rest); }
    else { ext_del(best);
           if (rest){ set_hdr(a + need, 0, SIG_FREE, rest); push(&g_cls[rest / 16u], a + need); } }
    st_free_bytes -= need;
    return 1;
}

static void heaplog(void);

/* ---- per-site statistics (HEAPCHECK / HEAPSTAT) ---- */
#define SITES 4096u
static struct { uint32_t site; uint64_t live, peak, n, allocs; } g_site[SITES];
static int site_slot(uint32_t site){
    uint32_t h = (site * 0x9E3779B1u) >> 20;
    for (uint32_t i = 0; i < SITES; i++){
        uint32_t j = (h + i) & (SITES - 1u);
        if (g_site[j].site == site) return (int)j;
        if (!g_site[j].site){ g_site[j].site = site; return (int)j; }
    }
    return -1;
}
static void site_note(uint32_t site, int64_t bytes){
    int i = site_slot(site ? site : 1u);
    if (i < 0) return;
    g_site[i].live += (uint64_t)bytes;
    if (bytes > 0){ g_site[i].n++; g_site[i].allocs++; if (g_site[i].live > g_site[i].peak) g_site[i].peak = g_site[i].live; }
    else g_site[i].n--;
}
/* the trailer of block b (bytes incl. header and trailer): canary right after
 * the user bytes, the site, the frame and a magic in the last 16 bytes */
static void trail_set(uint32_t b, uint32_t n, uint32_t bytes, uint32_t site){
    for (uint32_t i = 0; i < 16u; i++) MR8(b + HDR + n + i) = CANARY;
    uint32_t t = b + bytes - 16u;
    long metal_frames(void);
    MR32(t) = site; MR32(t + 4) = (uint32_t)metal_frames(); MR32(t + 8) = n; MR32(t + 12) = TR_MAGIC;
}
static uint32_t trail_site(uint32_t b, uint32_t bytes){
    uint32_t t = b + bytes - 16u;
    return MR32(t + 12) == TR_MAGIC ? MR32(t) : 0u;
}
/* 1 = the canary is intact */
static int trail_check(uint32_t b, const char *who){
    uint32_t n = MR32(b), bytes = MR32(b+8), t = b + bytes - 16u;
    if (MR32(t + 12) != TR_MAGIC || MR32(t + 8) != n){
        if (st_canary++ < 20) fprintf(stderr, "  [heap] %s(0x%08x): trailer gone (block %u bytes): overrun far past the end\n",
                                      who, b + HDR, n);
        return 0;
    }
    for (uint32_t i = 0; i < 16u; i++)
        if (MR8(b + HDR + n + i) != CANARY){
            if (st_canary++ < 20)
                fprintf(stderr, "  [heap] %s(0x%08x): written past its end at +%u (block %u bytes, made by 0x%08x at frame %u)\n",
                        who, b + HDR, n + i, n, MR32(t), MR32(t + 4));
            return 0;
        }
    return 1;
}

uint32_t gheap_alloc(uint32_t n, int zero){
    if (g_free_on < 0){ pthread_mutex_lock(&g_lk); cfg(); pthread_mutex_unlock(&g_lk); }
    uint32_t need = (n + HDR + (g_sitestat ? TRAIL : 0u) + 15u) & ~15u, b = 0;
    if (need < n) { st_fail++; return 0; }
    pthread_mutex_lock(&g_lk);
    cfg();
    if (need <= SMALL && g_cls[need / 16u].n){
        b = g_cls[need / 16u].a[--g_cls[need / 16u].n]; st_free_bytes -= need; st_reuse++;
    } else if (g_ext_n && take_extent(need, &b)){
        st_reuse++;
    } else if (g_top + need <= GH_MAX && g_top + need > g_top){
        b = g_top; g_top += need;
        if (g_top > g_committed_top){
            uint32_t to = (g_top + 0xFFFFu) & ~0xFFFFu;
            if (to > GH_MAX) to = GH_MAX;
            mem_commit(g_committed_top, to - g_committed_top); g_committed_top = to;
        }
        if (g_top > st_peak_top) st_peak_top = g_top;
    } else { st_fail++; pthread_mutex_unlock(&g_lk);
             fprintf(stderr, "  [heap] OUT OF MEMORY: %u bytes (live %llu KB, top 0x%08x)\n",
                     n, (unsigned long long)(st_live >> 10), g_top);
             return 0; }
    set_hdr(b, n, SIG_USED, need);
    st_alloc++; st_live += need; if (st_live > st_peak_live) st_peak_live = st_live;
    if (zero) memset(g_mem + b + HDR, 0, n);
    else if (g_check >= 2) memset(g_mem + b + HDR, 0xCD, n);
    if (g_sitestat){ trail_set(b, n, need, g_gheap_site); site_note(g_gheap_site, (int64_t)n); }
    if ((st_alloc & 4095u) == 0) heaplog();
    pthread_mutex_unlock(&g_lk);
    return b + HDR;
}

static int live_block(uint32_t u){
    if (u < GH_BASE + HDR || u >= g_top || (u & 15u)) return 0;
    return MR32(u - HDR + 4) == SIG_USED;
}

uint32_t gheap_size(uint32_t u){
    if (!u || u < GH_BASE + HDR || u >= GH_MAX || !mem_is_committed(u - HDR + 4)) return 0;
    if (MR32(u - HDR + 4) != SIG_USED) return 0;
    return MR32(u - HDR);
}

/* 1 = freed (or ignored as a no-op), 0 = not a block of ours */
int gheap_free(uint32_t u, const char *who){
    if (!u) return 1;
    pthread_mutex_lock(&g_lk);
    cfg();
    if (!live_block(u)){
        uint32_t sig = (u >= GH_BASE + HDR && u < g_top && !(u & 15u)) ? MR32(u - HDR + 4) : 0;
        int dbl = (sig == SIG_QUAR || sig == SIG_FREE);
        uint64_t k = dbl ? st_double++ : st_bad++;
        if (k < 10) fprintf(stderr, "  [heap] %s(0x%08x): %s, ignored\n", who, u,
                            dbl ? "double free" : "not a heap block");
        pthread_mutex_unlock(&g_lk);
        return 0;
    }
    uint32_t b = u - HDR, bytes = MR32(b+8);
    if (bytes != ~MR32(b+12) || bytes < MR32(b) + HDR || (bytes & 15u) || bytes > g_top - b){
        if (st_corrupt++ < 10) fprintf(stderr, "  [heap] %s(0x%08x): corrupt header (size %u, block %u), leaked\n",
                                       who, u, MR32(b), bytes);
        pthread_mutex_unlock(&g_lk);
        return 1;
    }
    if (g_sitestat){ if (g_check) trail_check(b, who); site_note(trail_site(b, bytes), -(int64_t)MR32(b)); }
    st_free++; st_live -= bytes;
    if (g_free_on) quarantine(b); else MR32(b+4) = SIG_USED;   /* A/B: leak as before */
    pthread_mutex_unlock(&g_lk);
    return 1;
}

/* HeapReAlloc: in place when the block is big enough or ends at the top of
 * the arena; otherwise new block + copy + free of the old one. */
uint32_t gheap_realloc(uint32_t o, uint32_t n, int zero, int in_place_only){
    if (!o) return in_place_only ? 0 : gheap_alloc(n, zero);
    pthread_mutex_lock(&g_lk);
    if (live_block(o)){
        uint32_t b = o - HDR, bytes = MR32(b+8), on = MR32(b);
        uint32_t need = (n + HDR + 15u) & ~15u;
        int ok = need >= n && need <= bytes && !g_sitestat;
        if (!ok && !g_sitestat && need >= n && b + bytes == g_top && b + need <= GH_MAX && b + need > b){
            g_top = b + need;
            if (g_top > g_committed_top){
                uint32_t to = (g_top + 0xFFFFu) & ~0xFFFFu; if (to > GH_MAX) to = GH_MAX;
                mem_commit(g_committed_top, to - g_committed_top); g_committed_top = to; }
            if (g_top > st_peak_top) st_peak_top = g_top;
            st_live += need - bytes; if (st_live > st_peak_live) st_peak_live = st_live;
            set_hdr(b, n, SIG_USED, need); ok = 1;
        }
        if (ok){
            MR32(b) = n;
            if (zero && n > on) memset(g_mem + o + on, 0, n - on);
            st_inplace++;
            pthread_mutex_unlock(&g_lk);
            return o;
        }
        pthread_mutex_unlock(&g_lk);
        if (in_place_only) return 0;
        uint32_t p = gheap_alloc(n, zero);
        if (p){ memcpy(g_mem + p, g_mem + o, on < n ? on : n); gheap_free(o, "HeapReAlloc"); }
        return p;
    }
    pthread_mutex_unlock(&g_lk);
    /* not one of our blocks: old behaviour (copy n bytes, keep the old one) */
    if (in_place_only) return 0;
    uint32_t p = gheap_alloc(n, zero);
    if (p && n && mem_is_committed(o) && mem_is_committed(o + n - 1u)) memcpy(g_mem + p, g_mem + o, n);
    return p;
}

/* ---- VirtualAlloc regions ------------------------------------------------ */
#define VR_MAX   4096
#define MEM_COMMIT_   0x1000u
#define MEM_RESERVE_  0x2000u
#define MEM_DECOMMIT_ 0x4000u
#define MEM_RELEASE_  0x8000u
typedef struct { uint32_t base, size, blk, prot; } VReg;   /* base 4 KB aligned, size a page multiple */
static VReg g_vr[VR_MAX]; static int g_vr_n;              /* sorted by base (under g_lk) */
static int vr_find(uint32_t a){                           /* the region holding a, or -1 */
    int lo = 0, hi = g_vr_n - 1;
    while (lo <= hi){ int m = (lo + hi) / 2;
        if (a < g_vr[m].base) hi = m - 1;
        else if (a - g_vr[m].base >= g_vr[m].size) lo = m + 1;
        else return m; }
    return -1;
}
/* VirtualAlloc(addr, size, type, protect) */
uint32_t gheap_va_alloc(uint32_t addr, uint32_t size, uint32_t type, uint32_t prot){
    if (addr){
        pthread_mutex_lock(&g_lk);
        int i = vr_find(addr);
        if (i >= 0){
            uint32_t pg = addr & ~0xFFFu, end = (addr + size + 0xFFFu) & ~0xFFFu;
            int fits = size && end > pg && end - g_vr[i].base <= g_vr[i].size;
            if (fits && (type & MEM_COMMIT_)){ st_va_commit_in++; st_va_commit_bytes += end - pg; }
            pthread_mutex_unlock(&g_lk);
            if (fits) return (type & (MEM_COMMIT_ | MEM_RESERVE_)) ? pg : 0;
            fprintf(stderr, "  [heap] VirtualAlloc(0x%08x, %u, 0x%x) past its region 0x%08x+%u: refused\n",
                    addr, size, type, g_vr[i].base, g_vr[i].size);
            return 0;
        }
        pthread_mutex_unlock(&g_lk);
        /* an address that is no region of ours: a new region elsewhere, as before */
        static int shown = 0;
        if (shown++ < 4) fprintf(stderr, "  [heap] VirtualAlloc(0x%08x, %u, 0x%x): not a reserved region, a new one instead\n",
                                 addr, size, type);
    }
    uint32_t sz = (size + 0xFFFu) & ~0xFFFu;
    if (!sz || sz < size) return 0;
    uint32_t blk = gheap_alloc(sz + 0x1000u, 1);
    if (!blk) return 0;
    uint32_t base = (blk + 0xFFFu) & ~0xFFFu;
    pthread_mutex_lock(&g_lk);
    if (g_vr_n < VR_MAX){
        int i = 0; while (i < g_vr_n && g_vr[i].base < base) i++;
        memmove(g_vr + i + 1, g_vr + i, (size_t)(g_vr_n - i) * sizeof *g_vr);
        g_vr[i].base = base; g_vr[i].size = sz; g_vr[i].blk = blk; g_vr[i].prot = prot ? prot : 4u; g_vr_n++;
    }
    if (addr) st_va_new++; else st_va_reserve++;
    pthread_mutex_unlock(&g_lk);
    return base;
}
/* VirtualFree(addr, size, type): 1 = done */
int gheap_va_free(uint32_t addr, uint32_t size, uint32_t type){
    pthread_mutex_lock(&g_lk);
    int i = vr_find(addr);
    if (i < 0){
        pthread_mutex_unlock(&g_lk);
        if (type & MEM_RELEASE_) gheap_free(addr, "VirtualFree");     /* not a region: as before */
        return 1;
    }
    if (type & MEM_RELEASE_){
        if (addr != g_vr[i].base){ pthread_mutex_unlock(&g_lk); return 0; }
        uint32_t blk = g_vr[i].blk;
        memmove(g_vr + i, g_vr + i + 1, (size_t)(g_vr_n - i - 1) * sizeof *g_vr); g_vr_n--;
        st_va_release++;
        pthread_mutex_unlock(&g_lk);
        gheap_free(blk, "VirtualFree");
        return 1;
    }
    if (type & MEM_DECOMMIT_){
        uint32_t pg = addr & ~0xFFFu, end = size ? (addr + size + 0xFFFu) & ~0xFFFu : g_vr[i].base + g_vr[i].size;
        if (end > g_vr[i].base + g_vr[i].size) end = g_vr[i].base + g_vr[i].size;
        if (end > pg) memset(g_mem + pg, 0, end - pg);            /* committed again, they read as zeros */
        st_va_decommit++;
    }
    pthread_mutex_unlock(&g_lk);
    return 1;
}
/* VirtualQuery(addr, MEMORY_BASIC_INFORMATION *, length): 28 bytes written */
uint32_t gheap_va_query(uint32_t addr, uint32_t mbi, uint32_t len){
    if (!mbi || len < 28u) return 0;
    uint32_t pg = addr & ~0xFFFu, ab, ap, rs, state, prot, type;
    st_va_query++;
    pthread_mutex_lock(&g_lk);
    int i = vr_find(addr);
    if (i >= 0){
        ab = g_vr[i].base; ap = prot = g_vr[i].prot; rs = g_vr[i].base + g_vr[i].size - pg;
        state = MEM_COMMIT_; type = 0x20000u;                       /* MEM_PRIVATE */
    }
    pthread_mutex_unlock(&g_lk);
    if (i < 0){
        uint32_t img_end = 0x00400000u + (mem_is_committed(0x0040003Cu) && mem_is_committed(MR32(0x0040003Cu) + 0x400050u + 3u)
                                          ? MR32(0x00400000u + MR32(0x0040003Cu) + 0x50u) : 0x00500000u);
        if (pg >= 0x00400000u && pg < img_end){
            ab = 0x00400000u; ap = 0x80u; state = MEM_COMMIT_; type = 0x1000000u;   /* MEM_IMAGE */
            prot = pg < 0x00785000u ? 0x20u : 0x04u;                  /* .text: execute/read, the rest read/write */
            rs = img_end - pg;
        } else if (mem_is_committed(pg)){
            ab = pg & ~0xFFFFu; ap = prot = 0x04u; state = MEM_COMMIT_; type = 0x20000u;
            uint32_t e = pg; while (e - pg < 0x01000000u && e + 0x1000u > e && mem_is_committed(e)) e += 0x1000u;
            rs = e - pg;
        } else {
            ab = 0; ap = 0; prot = 0x01u; state = 0x10000u; type = 0;   /* MEM_FREE, PAGE_NOACCESS */
            uint32_t e = pg; while (e - pg < 0x01000000u && e + 0x1000u > e && !mem_is_committed(e)) e += 0x1000u;
            rs = e - pg;
        }
    }
    mem_commit(mbi, 28u);
    MR32(mbi) = pg; MR32(mbi + 4) = ab; MR32(mbi + 8) = ap; MR32(mbi + 12) = rs;
    MR32(mbi + 16) = state; MR32(mbi + 20) = prot; MR32(mbi + 24) = type;
    return 28u;
}
/* VirtualProtect(addr, size, new, &old): 1; guest memory stays read/write */
int gheap_va_protect(uint32_t addr, uint32_t size, uint32_t prot, uint32_t pold){
    uint32_t old = addr - 0x00400000u < 0x00385000u ? 0x20u : 0x04u;
    pthread_mutex_lock(&g_lk);
    int i = vr_find(addr);
    if (i >= 0){ old = g_vr[i].prot; g_vr[i].prot = prot; }
    st_va_protect++;
    pthread_mutex_unlock(&g_lk);
    if (pold){ mem_commit(pold, 4u); MR32(pold) = old; }
    static int shown = 0;
    if (shown++ < 4) fprintf(stderr, "  [heap] VirtualProtect(0x%08x, %u, 0x%x) -> was 0x%x\n", addr, size, prot, old);
    return 1;
}

uint32_t gheap_top_used(void){ return g_top - GH_BASE; }
uint64_t gheap_failed(void){ return st_fail; }

static void line(const char *tag){
    extern void com_gbuf_fmt(char *s, size_t n);
    char gb[192]; com_gbuf_fmt(gb, sizeof gb);
    fprintf(stderr, "  [heap]%s live %llu KB (peak %llu), arena top %u KB (peak %llu), "
            "free %llu KB (%u extents), quarantine %llu KB; %llu allocs, %llu frees, %llu reused, "
            "%llu realloc in place; %llu double / %llu bad / %llu corrupt frees, %llu failed%s; "
            "buffer heap %s\n", tag,
            (unsigned long long)(st_live >> 10), (unsigned long long)(st_peak_live >> 10),
            (g_top - GH_BASE) >> 10, (unsigned long long)((st_peak_top ? st_peak_top - GH_BASE : 0) >> 10),
            (unsigned long long)(st_free_bytes >> 10), g_ext_n, (unsigned long long)(g_q_bytes >> 10),
            (unsigned long long)st_alloc, (unsigned long long)st_free, (unsigned long long)st_reuse,
            (unsigned long long)st_inplace, (unsigned long long)st_double, (unsigned long long)st_bad,
            (unsigned long long)st_corrupt, (unsigned long long)st_fail,
            g_free_on == 0 ? " (FREE OFF)" : "", gb);
    if (g_poison) fprintf(stderr, "  [heap] poison: %llu blocks written after free\n",
                          (unsigned long long)st_poison_hit);
}

static void heaplog(void){
    static int every = -1; static time_t t0, last;
    if (every < 0){ const char *e = getenv("NFSU2_HEAPLOG"); every = (e && *e) ? atoi(e) : 60;
                    t0 = last = time(0); }
    if (every <= 0) return;
    time_t now = time(0);
    if (now - last < every) return;
    last = now;
    char tag[32]; snprintf(tag, sizeof tag, " t=%lds", (long)(now - t0));
    line(tag);
}

void gheap_report(void){
    pthread_mutex_lock(&g_lk); cfg(); line("");
    if (st_va_reserve || st_va_new || st_va_query || st_va_protect)
        fprintf(stderr, "  [heap] VirtualAlloc: %llu regions reserved (%d held), %llu commits inside one (%llu KB that each took"
                        " a new block before), %llu outside any, %llu decommits, %llu releases; VirtualQuery %llu, VirtualProtect %llu\n",
                (unsigned long long)st_va_reserve, g_vr_n, (unsigned long long)st_va_commit_in,
                (unsigned long long)(st_va_commit_bytes >> 10), (unsigned long long)st_va_new,
                (unsigned long long)st_va_decommit, (unsigned long long)st_va_release,
                (unsigned long long)st_va_query, (unsigned long long)st_va_protect);
    if (g_poison){                       /* the exit sweep: blocks still in the quarantine */
        uint64_t hit = 0;
        for (uint32_t k = 0; k < g_q_n; k++){
            uint32_t b = g_q[(g_q_head + k) & (g_q_cap - 1u)], n = MR32(b);
            for (uint32_t o = 0; o + 4u <= n; o += 4u)
                if (MR32(b + HDR + o) != POISON){
                    if (hit++ < 10) fprintf(stderr, "  [heap] written after free (exit sweep): block 0x%08x (%u bytes) at +%u = 0x%08x\n",
                                            b + HDR, n, o, MR32(b + HDR + o));
                    break; }
        }
        st_poison_hit += hit;
    }
    if (g_check) fprintf(stderr, "  [heap] HEAPCHECK: %llu overruns, %llu writes after free, %llu double / %llu bad frees\n",
                         (unsigned long long)st_canary, (unsigned long long)st_poison_hit,
                         (unsigned long long)st_double, (unsigned long long)st_bad);
    if (g_sitestat){
        fprintf(stderr, "  [heap] live bytes by the code that asked (the 12 largest):\n");
        for (int k = 0; k < 12; k++){
            int best = -1;
            for (uint32_t i = 0; i < SITES; i++)
                if (g_site[i].site && g_site[i].live && (best < 0 || g_site[i].live > g_site[best].live)) best = (int)i;
            if (best < 0) break;
            fprintf(stderr, "    0x%08x %9llu KB in %6llu blocks (peak %llu KB, %llu allocations)\n", g_site[best].site,
                    (unsigned long long)(g_site[best].live >> 10), (unsigned long long)g_site[best].n,
                    (unsigned long long)(g_site[best].peak >> 10), (unsigned long long)g_site[best].allocs);
            g_site[best].live = 0;                 /* shown (the report is the last thing) */
        }
    }
    pthread_mutex_unlock(&g_lk);
}
