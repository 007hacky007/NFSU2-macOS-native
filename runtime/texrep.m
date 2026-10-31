/* texrep.m -- texture packs: other pictures drawn in place of the game's textures.
 * After th0mk's nfsu2-web (runtime/web/texrep_web.c, its pack format and
 * tools/texpacks.py), which did it first for the browser.
 *
 *   NFSU2_TEXPACKS  = <path>[:<path>...]   the launcher's Texture Packs that are on, in
 *                                          its order: where two replace the same texture,
 *                                          the first one's is drawn
 *   NFSU2_UHUD      = off | on             LunicAura106's Upscaled HUD (off by default);
 *   NFSU2_UHUD_PACK = <absolute path>      its pack, otherwise TEXPACKS/uhud.pak in the
 *                                          game folder.  It comes after the Texture Packs.
 *   NFSU2_TEXPACKS_LOG = 1 (or NFSU2_UHUD_LOG = 1)   one line per replaced texture
 *
 * and a folder of DDS files, the upscaled texture pack (the launcher makes it from the
 * player's own game files, launcher/UpscaleBuilder.swift; a hand-made DDS pack of the
 * same layout works too).  It comes after all the packs above:
 *   NFSU2_TEXTURES  = original | upscaled  upscaled: use the pack (off by default)
 *   NFSU2_TEXPACK   = <name> | <path>      the pack's folder: absolute, or a name under
 *                                          ~/Library/Application Support/NFSU2/Textures/
 *                                          (default "default"); none or an empty one =
 *                                          the game's own textures
 *   NFSU2_TEXPARTS  = list | all           its parts (its sub-folders) to use: world, signs,
 *                                          cars, garage, sky, effects, frontend, hud, other;
 *                                          default world,signs,cars,garage
 *   NFSU2_TEXBUDGET = <MB>                 GPU memory for its textures, loading ones
 *                                          included; beyond it the game's own textures stay
 *                                          (default a sixth of the Mac's memory, at most 4096)
 *   NFSU2_TEXDUMP   = on | <path>          collect level 0 of every static texture the game
 *                                          uploads (once per content) as <dir>/<part>/
 *                                          <w>x<h>_<fmt>_<hash>.dds + index.csv: the next
 *                                          build's input for what the builder's scan cannot
 *                                          read (compressed front-end and car bundles)
 *   NFSU2_TEXLOG    = 1                    one line per texture the DDS pack replaces
 *
 * The launcher makes the NTXP packs (texpack.h) from the mods' own downloads:
 * launcher/UHUDPack.swift for UHUD, launcher/TexturePacks.swift for TexMod packs
 * (.tpf), TexWizard packs and mods that replace the game's texture files.
 *
 * On a PC such mods write larger textures into the game's files, or TexMod and
 * TexWizard put them into the game while it runs; the game then sees the new sizes,
 * and UHUD needs a plugin (NFSU2HDContentSupport.asi) that gives the game the old
 * sizes back where it measures a texture in texels (the fonts' glyph tables, the
 * mouse cursor).  Here the game keeps reading its own files and sees every texture
 * at its own size; GetLevelDesc, LockRect and every upload keep using the original
 * Metal texture.  Only the draw encoder (metal.m, texrep_pick) samples the pack's
 * texture in its place.  The game samples with coordinates of 0 to 1, so a larger
 * texture is drawn where the original was, and the fonts and the cursor stay right
 * without the plugin.
 *
 * Which texture (texpack.h): by the content of level 0 as the game uploads it (UHUD,
 * mods made from the game's files), by TexMod's hash of the same bytes, or by the
 * texture's name, which the game's texture loader (0x5CE180) has at hand when it
 * creates the texture (com.c passes it).  Every upload of level 0 is looked up again,
 * so a texture whose content changes shows a pack's only while its content is the one
 * the pack replaces.  Render targets, textures written through a surface (the car skin
 * composite) and movie frames are never a pack's.
 *
 * The DDS pack: <pack>/<part>/<anything>_<hash>.dds, <hash> = 16 hex digits = XXH3-64 of
 * level 0 as the game uploads it, seeded with w | h << 16 | D3DFORMAT << 32.  A file
 * whose levels stop above the original's size, in the original's block format (DXT1 ->
 * BC1, DXT3 -> BC2, DXT5 -> BC3, A8R8G8B8 -> BGRA8) and of w<<k x h<<k, is STACKED: the
 * game's own levels go underneath, unchanged (blitted on the main thread), so wherever
 * the game drew a texture at or below its own size the GPU reads the game's own texels;
 * where the game's sampler has no mip filter the replacement gets a linear one clamped
 * at level k (texrep_skey), so magnified it blends the pack's levels and minified it
 * reads the game's level 0 as before.  Any other DDS of the same aspect ratio (BC1/2/3/7,
 * BGRA8, RGBA8; a mip chain or one level) replaces the texture as a whole.  Only static
 * textures of more than 32 x 32 texels: one whose level 0 is uploaded again with other
 * content is dynamic from then on and shows the game's own.  The game creates new
 * texture ids for the same textures on every race load; ids with the same content (level
 * 0 and the lower levels) share one loaded file (DEnt), so memory stays at the pack's
 * unique content, and a DEnt goes when the last id showing it is released (com.c).
 *
 * Memory: an NTXP entry is one Metal texture, loaded on its first use and kept, so at
 * most the size of the packs' textures that were seen; the DDS pack's within its budget.
 *
 * Threads.  Guest thread: lookups and hashing at UnlockRect, which entries are loading,
 * the changes for the draw encoder (texrep_frame).  Loaders (GCD queues): reading the
 * files, making the Metal textures.  Main thread (texrep_main_frame, start of each
 * frame's encode): the id -> texture table the encoder reads, and the blits of the
 * game's own levels under a stacked replacement.  They hand over through two
 * mutex-protected lists.  The DDS path is the old fork's runtime/texrep.m.
 *
 * xxhash.h: XXH3 by Yann Collet, BSD 2-Clause (vendored, v0.8.4). */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#include "cpu.h"
#include "texrep.h"
#include "texpack.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <zlib.h>
#define XXH_INLINE_ALL
#include "xxhash.h"

id<MTLDevice> metal_device(void);                                   /* metal.m */
id<MTLTexture> metal_tex_object(unsigned id_);                      /* metal.m, main thread */
int fileio_game_path(const char *win, char *out, size_t outsz);    /* fileio.c */

/* ---- main-thread state the encoder reads -------------------------------- */
int g_texrep_frame_on;
__strong id<MTLTexture> g_texrep_tex[TEXREP_MAXTEX];
uint8_t g_texrep_k[TEXREP_MAXTEX] = {0};            /* (initialised: not a common symbol) */
static unsigned g_main_live;                       /* ids in g_texrep_tex */
static _Atomic int g_shown = 1;                    /* Cmd-T */
static unsigned long g_mipstat[4];                 /* main thread: replaced DDS binds by mip filter */

/* ---- the file the guest read last (fileio.c): a texture's part, movie frames ---- */
static char g_last_read[512];
void texrep_note_read(const char *path){ snprintf(g_last_read, sizeof g_last_read, "%s", path); }

/* ---- the packs (opened once, from whichever thread asks first) ---------- */
#define MAXPACKS 32
static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static int g_on;                                   /* a pack is open, or the dump is on */
static int g_log;
static Texpack g_pack[MAXPACKS];
static unsigned g_npack;
static unsigned g_base[MAXPACKS + 1];              /* entry e of pack k: g_base[k] + e */
static int g_hash_all;                             /* a pack has TexMod keys: hash every texture */
static int g_names;                                /* a pack has name keys */
static dispatch_queue_t g_lq;
static int g_dds_on, g_dumping;                    /* the DDS pack is indexed / the dump is on */
static void dds_init(void);

static void add_pack(const char *path, const char *what){
    char err[160];
    if (g_npack == MAXPACKS){ fprintf(stderr, "[texpacks] more than %d packs: %s left out\n", MAXPACKS, path); return; }
    if (path[0] != '/'){ fprintf(stderr, "[texpacks] %s: not an absolute path, left out\n", path); return; }
    Texpack *p = &g_pack[g_npack];
    if (!texpack_open(p, path, err, sizeof err)){
        fprintf(stderr, "[texpacks] %s: %s; left out\n", path, err);
        return;
    }
    g_base[g_npack + 1] = g_base[g_npack] + p->count;
    if (p->texmod_count) g_hash_all = 1;
    if (p->name_count) g_names = 1;
    fprintf(stderr, "[texpacks] %u: %s%s, %u textures (%u by content, %u TexMod, %u by name)\n",
            g_npack + 1, path, what, p->count, p->count - p->texmod_count - p->name_count,
            p->texmod_count, p->name_count);
    g_npack++;
}
static void open_packs(void){
    g_log = (getenv("NFSU2_TEXPACKS_LOG") && *getenv("NFSU2_TEXPACKS_LOG")) ||
            (getenv("NFSU2_UHUD_LOG") && *getenv("NFSU2_UHUD_LOG"));
    const char *list = getenv("NFSU2_TEXPACKS");
    if (list && *list){
        char *dup = strdup(list), *save = NULL;
        for (char *s = strtok_r(dup, ":", &save); s; s = strtok_r(NULL, ":", &save)) if (*s) add_pack(s, "");
        free(dup);
    }
    const char *v = getenv("NFSU2_UHUD");
    if (v && (!strcasecmp(v, "on") || !strcmp(v, "1"))){
        char path[4096] = "";
        const char *custom = getenv("NFSU2_UHUD_PACK");
        if (custom && *custom) snprintf(path, sizeof path, "%s", custom);
        else if (!fileio_game_path("TEXPACKS\\uhud.pak", path, sizeof path)) path[0] = 0;
        if (*path) add_pack(path, " (UHUD)");
        else fprintf(stderr, "[texpacks] UHUD not in use: no TEXPACKS/uhud.pak in the game folder\n");
    }
    if (g_npack)
        g_lq = dispatch_queue_create("nfsu2.texpacks.load",
                                     dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    dds_init();
    g_on = g_npack || g_dds_on || g_dumping;
}
static int on(void){ pthread_once(&g_once, open_packs); return g_on; }

/* pack and entry of a global entry index */
static unsigned pack_of(unsigned ei){ unsigned k = 0; while (ei >= g_base[k + 1]) k++; return k; }
static const TexpackEntry *entry(unsigned ei, unsigned *k, unsigned *e){
    *k = pack_of(ei); *e = ei - g_base[*k];
    return &g_pack[*k].entries[*e];
}

/* ---- per texture id and per pack entry (guest thread only) -------------- */
typedef struct {
    uint16_t w, h; uint32_t fmt;
    uint32_t name;                                 /* the game's name hash, or 0 */
    uint8_t ok;                                    /* an NTXP pack may replace it */
    uint8_t pending;                               /* in g_pend */
    int32_t want;                                  /* entry for its current content, or -1 */
    int32_t shown;                                 /* entry published for it, or -1 */
} Tex;
static Tex *g_t;
enum { E_NONE, E_LOADING, E_READY, E_FAILED };
typedef struct { uint8_t st; void *tex; } Ent;     /* tex: +1 while E_READY */
static Ent *g_ent;
static unsigned *g_pend, g_pend_n, g_pend_cap;     /* ids whose entry is loading */

/* ---- loader -> guest ------------------------------------------------------ */
typedef struct { unsigned ei; void *tex; } Ready;  /* tex NULL: the load failed */
static pthread_mutex_t g_rmx = PTHREAD_MUTEX_INITIALIZER;
static Ready *g_ready; static unsigned g_ready_n, g_ready_cap;
/* ---- guest -> main ---------------------------------------------------------- */
/* OP_SET: tex = a +1 reference for this id (NULL: the game's own again); k: the DDS
 * pack's levels above the original; stacked: copy this id's own levels under them.
 * OP_COPY: a lower level the game uploaded later, into a stacked replacement. */
enum { OP_SET, OP_COPY };
typedef struct { uint8_t op, k, stacked; unsigned mid, level; void *tex; } Op;
static pthread_mutex_t g_omx = PTHREAD_MUTEX_INITIALIZER;
static Op *g_ops; static unsigned g_ops_n, g_ops_cap;

static void push(pthread_mutex_t *mx, void **arr, unsigned *n, unsigned *cap, size_t sz, const void *item){
    pthread_mutex_lock(mx);
    if (*n == *cap){ *cap = *cap ? 2 * *cap : 256; *arr = realloc(*arr, *cap * sz); }
    memcpy((char *)*arr + *n * sz, item, sz); (*n)++;
    pthread_mutex_unlock(mx);
}
static void op_post(Op o){ push(&g_omx, (void **)&g_ops, &g_ops_n, &g_ops_cap, sizeof o, &o); }

static MTLPixelFormat pixel_format(uint32_t f){
    switch (f){
    case 0x31545844u: return MTLPixelFormatBC1_RGBA;          /* DXT1 */
    case 0x33545844u: return MTLPixelFormatBC2_RGBA;          /* DXT3 */
    case 0x35545844u: return MTLPixelFormatBC3_RGBA;          /* DXT5 */
    case 21: case 22: return MTLPixelFormatBGRA8Unorm;        /* A8R8G8B8, X8R8G8B8 */
    }
    return MTLPixelFormatInvalid;
}
static size_t row_bytes(uint32_t f, unsigned w){
    return f == 21 || f == 22 ? (size_t)w * 4 : (size_t)((w + 3) / 4) * (f == 0x31545844u ? 8 : 16);
}
static unsigned row_count(uint32_t f, unsigned h){ return f == 21 || f == 22 ? h : (h + 3) / 4; }

/* the loader: the entry's levels into a new Metal texture (texpack_open
 * checked the sizes, the formats and that the levels fit the file) */
static void load(unsigned ei){
    unsigned k, li;
    const TexpackEntry *e = entry(ei, &k, &li);
    Ready r = { ei, NULL };
    uint8_t *b = malloc(e->size);
    id<MTLDevice> dev = metal_device();
    if (b && dev && texpack_read(&g_pack[k], li, b, e->size)){
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixel_format(e->fmt)
                                       width:e->w height:e->h mipmapped:(e->levels > 1)];
        td.mipmapLevelCount = e->levels;
        td.usage = MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModeShared;
        id<MTLTexture> t = [dev newTextureWithDescriptor:td];
        size_t off = 0;
        for (unsigned l = 0; t && l < e->levels; l++){
            unsigned lw = e->w >> l, lh = e->h >> l; if (!lw) lw = 1; if (!lh) lh = 1;
            size_t row = row_bytes(e->fmt, lw);
            [t replaceRegion:MTLRegionMake2D(0, 0, lw, lh) mipmapLevel:l withBytes:b + off bytesPerRow:row];
            off += row * row_count(e->fmt, lh);
        }
        if (t) r.tex = (__bridge_retained void *)t;
    }
    free(b);
    push(&g_rmx, (void **)&g_ready, &g_ready_n, &g_ready_cap, sizeof r, &r);
}

/* publish what id mid should show now, if its entry is loaded */
static void settle(unsigned mid){
    Tex *t = &g_t[mid];
    int32_t ei = t->want;
    if (ei >= 0 && g_ent[ei].st == E_NONE){
        g_ent[ei].st = E_LOADING;
        dispatch_async(g_lq, ^{ load((unsigned)ei); });
    }
    if (ei >= 0 && g_ent[ei].st == E_LOADING){
        if (!t->pending){
            t->pending = 1;
            if (g_pend_n == g_pend_cap){ g_pend_cap = g_pend_cap ? 2 * g_pend_cap : 256;
                                         g_pend = realloc(g_pend, g_pend_cap * sizeof *g_pend); }
            g_pend[g_pend_n++] = mid;
        }
        return;
    }
    if (ei >= 0 && g_ent[ei].st != E_READY) ei = -1;           /* failed: the game's own */
    if (ei == t->shown) return;
    op_post((Op){ OP_SET, 0, 0, mid, 0, ei >= 0 ? (void *)CFRetain(g_ent[ei].tex) : NULL });
    if (ei >= 0 && g_log){
        unsigned k, li; const TexpackEntry *e = entry((unsigned)ei, &k, &li);
        fprintf(stderr, "[texpacks] t%u %ux%u -> pack %u %s %ux%u\n", mid, t->w, t->h, k + 1,
                texpack_name(&g_pack[k], li), e->w, e->h);
    }
    t->shown = ei;
}

/* the entry for a texture's level 0, or -1: the first pack that has it; in a pack,
 * by content, then TexMod's hash, then the name */
static int32_t find(const Tex *t, const uint8_t *data, size_t n){
    uint32_t crc = 0; int have = 0;
    for (unsigned k = 0; k < g_npack; k++){
        const Texpack *p = &g_pack[k];
        int r = -1;
        if (p->texmod_count || texpack_may_match(p, t->w, t->h, t->fmt)){
            if (!have){ crc = (uint32_t)crc32(0, data, (uInt)n); have = 1; }
            r = texpack_find(p, data, n, crc, t->w, t->h, t->fmt);
        }
        if (r < 0 && t->name) r = texpack_find_name(p, t->name);
        if (r >= 0) return (int32_t)(g_base[k] + (unsigned)r);
    }
    return -1;
}

/* ========================================================================== *
 * The DDS pack (the upscaled texture pack) and the texture dump
 * ========================================================================== */
static char g_packdir[1024], g_dumpdir[1024];
static unsigned g_parts;                           /* part bit mask */
static int g_verbose;
static unsigned long long g_budget;
static dispatch_queue_t g_q;                       /* dump writer */
#define NLQ 3
static dispatch_queue_t g_dlq[NLQ];                /* DDS loaders (round robin) */
static unsigned g_dlq_next;

enum { CAT_WORLD, CAT_SIGNS, CAT_CARS, CAT_GARAGE, CAT_SKY, CAT_EFFECTS, CAT_FRONTEND, CAT_HUD, CAT_OTHER, NCAT };
static const char *const k_cat[NCAT] = { "world", "signs", "cars", "garage", "sky", "effects", "frontend", "hud", "other" };
#define PARTS_DEFAULT ((1u << CAT_WORLD) | (1u << CAT_SIGNS) | (1u << CAT_CARS) | (1u << CAT_GARAGE))

/* ---- pack index: hash -> path ------------------------------------------- */
typedef struct { uint64_t h; uint32_t path; int32_t ent; uint8_t cat; } IdxEnt;   /* ent: its shared DEnt, or -1 */
static IdxEnt *g_idx; static unsigned g_idx_cap, g_idx_n;
static char *g_paths; static size_t g_paths_n, g_paths_cap;
static unsigned g_idx_cat[NCAT], g_idx_skipped;
static uint32_t path_put(const char *p){
    size_t l = strlen(p) + 1;
    if (g_paths_n + l > g_paths_cap){
        g_paths_cap = g_paths_cap ? g_paths_cap * 2 : 1u << 20;
        while (g_paths_n + l > g_paths_cap) g_paths_cap *= 2;
        g_paths = realloc(g_paths, g_paths_cap);
    }
    memcpy(g_paths + g_paths_n, p, l);
    uint32_t off = (uint32_t)g_paths_n; g_paths_n += l;
    return off;
}
static void idx_grow(void){
    unsigned oc = g_idx_cap; IdxEnt *o = g_idx;
    g_idx_cap = oc ? oc * 2 : 1u << 12;
    g_idx = calloc(g_idx_cap, sizeof *g_idx);
    for (unsigned i = 0; i < oc; i++) if (o[i].h){
        for (unsigned j = (unsigned)(o[i].h & (g_idx_cap - 1)); ; j = (j + 1) & (g_idx_cap - 1))
            if (!g_idx[j].h){ g_idx[j] = o[i]; break; }
    }
    free(o);
}
static void idx_put(uint64_t h, const char *path, int cat){
    if (!h) h = 1;
    if (2 * (g_idx_n + 1) > g_idx_cap) idx_grow();
    for (unsigned i = (unsigned)(h & (g_idx_cap - 1)); ; i = (i + 1) & (g_idx_cap - 1)){
        if (!g_idx[i].h){ g_idx[i].h = h; g_idx[i].path = path_put(path); g_idx[i].cat = (uint8_t)cat; g_idx[i].ent = -1;
                          g_idx_n++; g_idx_cat[cat]++; return; }
        if (g_idx[i].h == h) return;               /* first one wins */
    }
}
static IdxEnt *idx_get(uint64_t h){
    if (!g_idx_n) return 0;
    if (!h) h = 1;
    for (unsigned i = (unsigned)(h & (g_idx_cap - 1)); g_idx[i].h; i = (i + 1) & (g_idx_cap - 1))
        if (g_idx[i].h == h) return &g_idx[i];
    return 0;
}
/* file name ends in _<16 hex digits>.dds */
static int name_hash(const char *nm, uint64_t *h){
    size_t l = strlen(nm);
    if (l < 21 || strcasecmp(nm + l - 4, ".dds") || nm[l - 21] != '_') return 0;
    uint64_t v = 0;
    for (const char *p = nm + l - 20; p < nm + l - 4; p++){
        int c = (unsigned char)*p, d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else return 0;
        v = v << 4 | (uint64_t)d;
    }
    *h = v; return 1;
}
static void idx_scan_dir(const char *dir, int cat, int depth){
    DIR *d = opendir(dir); if (!d) return;
    struct dirent *e; char p[1400];
    while ((e = readdir(d))){
        if (e->d_name[0] == '.') continue;
        snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
        uint64_t h;
        if (name_hash(e->d_name, &h)){
            if ((g_parts >> cat) & 1u) idx_put(h, p, cat); else g_idx_skipped++;
        } else if (depth < 3 && e->d_type == DT_DIR) idx_scan_dir(p, cat, depth + 1);
        else if (depth < 3 && e->d_type == DT_UNKNOWN){
            struct stat st; if (stat(p, &st) == 0 && S_ISDIR(st.st_mode)) idx_scan_dir(p, cat, depth + 1); }
    }
    closedir(d);
}
static int cat_by_name(const char *s){
    for (int c = 0; c < NCAT; c++) if (!strcasecmp(s, k_cat[c])) return c;
    return -1;
}
/* part = the first folder below the pack; files directly in the pack (or in an
 * unknown folder) are "other" */
static void idx_scan(const char *pack){
    DIR *d = opendir(pack); if (!d) return;
    struct dirent *e; char p[1400];
    while ((e = readdir(d))){
        if (e->d_name[0] == '.') continue;
        snprintf(p, sizeof p, "%s/%s", pack, e->d_name);
        uint64_t h;
        if (name_hash(e->d_name, &h)){
            if ((g_parts >> CAT_OTHER) & 1u) idx_put(h, p, CAT_OTHER); else g_idx_skipped++;
            continue; }
        struct stat st;
        if (stat(p, &st) != 0 || !S_ISDIR(st.st_mode)) continue;
        int c = cat_by_name(e->d_name);
        idx_scan_dir(p, c < 0 ? CAT_OTHER : c, 1);
    }
    closedir(d);
}

static double now_ms(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}
/* "name" -> ~/Library/Application Support/NFSU2/Textures/name; absolute (or ./relative) paths as given */
static void resolve_dir(const char *v, const char *dflt, char *out, size_t n){
    const char *home = getenv("HOME");
    if (!v || !*v || !strcasecmp(v, "on") || !strcmp(v, "1")) v = dflt;
    if (v[0] == '/' || v[0] == '.' || v[0] == '~'){
        if (v[0] == '~' && home) snprintf(out, n, "%s%s", home, v + 1);
        else snprintf(out, n, "%s", v);
    } else snprintf(out, n, "%s/Library/Application Support/NFSU2/Textures/%s", home ? home : "/tmp", v);
    size_t l = strlen(out); while (l > 1 && out[l - 1] == '/') out[--l] = 0;
}
static int env_on(const char *k){ const char *v = getenv(k); return v && *v && strcasecmp(v, "off") && strcmp(v, "0"); }
int texrep_wanted(void){
    const char *t = getenv("NFSU2_TEXTURES");
    return t && (!strcasecmp(t, "upscaled") || !strcasecmp(t, "on") || !strcmp(t, "1"));
}

/* ---- per-texture state of the DDS path (guest thread only) -------------- */
enum { S_NONE, S_PENDING, S_ACTIVE };
typedef struct {
    uint8_t lev, ok, dyn, state, cat, k, dumped;
    uint32_t gen, lvmask;
    uint64_t hash, lvh;                            /* lvh: the lower levels' content (sum of hashes) */
    int32_t ent;                                   /* the DEnt it waits for (S_PENDING) or shows (S_ACTIVE) */
    long req_frame, last_up;                       /* g_frame of the pack hit / of the last level upload */
} TR;
static TR *g_tr;
static long g_frame;                               /* texrep_frame calls */

/* One DEnt per loaded pack file, shared by every texture id with the same content: the
 * game creates a new texture id for the same texture on every race load, and without
 * sharing each id would load its own copy (about 0.3 GB more per race load at 4x).  An
 * id shares a DEnt only when its own lower levels are the ones under the DEnt's pack
 * levels (same level count, same uploaded levels, same content: lvh), so what a
 * minified surface shows stays the game's own texels.  Memory is counted per DEnt from
 * the moment its load starts (g_bytes), which is what the budget limits. */
enum { D_LOADING, D_READY, D_FAILED, D_BUDGET };
typedef struct {
    IdxEnt *index;                                 /* stable pack index slot, NULL for private copies */
    int32_t next;                                  /* free list */
    uint32_t path;                                 /* pack file (g_paths offset) */
    uint8_t st, k, stacked, solo;                  /* solo: its lower levels changed after publication */
    uint8_t lev; uint32_t lvmask; uint64_t lvh;    /* the lower levels under it (set by the first id shown) */
    unsigned refs, waiters;                        /* ids showing it / ids waiting for it */
    void *tex;                                     /* +1 while D_READY */
    unsigned long long bytes;                      /* counted in g_bytes (D_BUDGET: what it needed) */
} DEnt;
static DEnt *g_dent; static unsigned g_dent_n, g_dent_cap; static int32_t g_dent_free = -1;
typedef struct { unsigned mid, gen; } Pend;        /* ids waiting for a DEnt */
static Pend *g_dpend; static unsigned g_dpend_n, g_dpend_cap;

/* ---- loader -> guest ------------------------------------------------------ */
typedef struct { int32_t ei; unsigned k, stacked, fail; void *tex; unsigned long long bytes; double ms; } DReady;
static pthread_mutex_t g_drmx = PTHREAD_MUTEX_INITIALIZER;
static DReady *g_dready; static unsigned g_dready_n, g_dready_cap;

/* ---- statistics ----------------------------------------------------------- */
static unsigned long g_n_created, g_n_eligible, g_n_hashed, g_n_hit, g_n_loaded, g_n_pub, g_n_drop,
                     g_n_fail, g_n_shape, g_n_budget, g_n_stale, g_n_dyn, g_n_dumped, g_n_unlinked,
                     g_n_shared, g_n_private, g_n_unshare, g_n_relevel, g_n_tex_peak, g_n_tex_live;
static unsigned long g_why[3];                                    /* published: all levels / uploads stopped / 60 frames */
static _Atomic unsigned long long g_bytes;                        /* every live DEnt, loading ones included */
static unsigned long long g_bytes_peak;
static double g_hash_ms, g_load_ms_sum, g_load_ms_max;           /* load: loader thread */
static unsigned long long g_hash_bytes;
static double g_hash_ms_mark, g_frame_ms_max; static unsigned long g_frames_over1;   /* guest time per frame */
static unsigned long g_lat_hist[8];                               /* publish latency in frames: 0,1,2,3-4,5-8,9-16,17-64,>64 */
static long g_lat_max;
static unsigned long g_pub_race, g_load_race;                     /* while GameFlow = 6 (race / free roam) */
static int in_race(void){ return mem_is_committed(GA(0x008654a4u)) && MR32(GA(0x008654a4u)) == 6u; }

static unsigned long long phys_mem(void){
    uint64_t m = 0; size_t l = sizeof m;
    if (sysctlbyname("hw.memsize", &m, &l, NULL, 0) != 0) m = 8ull << 30;
    return m;
}

static void dds_init(void){
    g_verbose = env_on("NFSU2_TEXLOG");
    const char *dv = getenv("NFSU2_TEXDUMP");
    if (dv && *dv && strcasecmp(dv, "off") && strcmp(dv, "0")){
        resolve_dir(dv, "dump", g_dumpdir, sizeof g_dumpdir);
        g_dumping = 1;
    }
    const char *bv = getenv("NFSU2_TEXBUDGET");
    unsigned long long auto_b = phys_mem() / 6; if (auto_b > (4096ull << 20)) auto_b = 4096ull << 20;
    g_budget = (bv && atof(bv) > 0) ? (unsigned long long)(atof(bv) * 1048576.0) : auto_b;
    if (texrep_wanted()){
        resolve_dir(getenv("NFSU2_TEXPACK"), "default", g_packdir, sizeof g_packdir);
        const char *pv = getenv("NFSU2_TEXPARTS");
        if (!pv || !*pv) g_parts = PARTS_DEFAULT;
        else if (!strcasecmp(pv, "all")) g_parts = (1u << NCAT) - 1u;
        else {
            char tmp[256]; snprintf(tmp, sizeof tmp, "%s", pv); char *sv = 0;
            for (char *t = strtok_r(tmp, ", ", &sv); t; t = strtok_r(0, ", ", &sv)){
                int c = cat_by_name(t);
                if (c >= 0) g_parts |= 1u << c;
                else fprintf(stderr, "[texrep] texture parts: unknown part \"%s\" left out\n", t);
            }
        }
        double t0 = now_ms();
        struct stat st;
        if (stat(g_packdir, &st) != 0 || !S_ISDIR(st.st_mode))
            fprintf(stderr, "[texrep] upscaled textures on, but there is no pack at %s: the game's own textures stay\n", g_packdir);
        else {
            idx_scan(g_packdir);
            fprintf(stderr, "[texrep] pack %s: %u replacement(s) indexed in %.1f ms (", g_packdir, g_idx_n, now_ms() - t0);
            for (int c = 0; c < NCAT; c++) if (g_idx_cat[c]) fprintf(stderr, " %s %u", k_cat[c], g_idx_cat[c]);
            fprintf(stderr, " ; %u in parts not used), GPU memory budget %.0f MB\n", g_idx_skipped, g_budget / 1048576.0);
            if (!g_idx_n) fprintf(stderr, "[texrep] nothing to replace: the game's own textures stay\n");
        }
        g_dds_on = g_idx_n > 0;
    }
    if (g_dds_on || g_dumping){
        g_tr = calloc(TEXREP_MAXTEX, sizeof *g_tr);
        if (!g_tr){ fprintf(stderr, "[texrep] out of memory: the DDS pack and the collecting are off\n"); g_dds_on = g_dumping = 0; return; }
        dispatch_queue_attr_t at = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        g_q = dispatch_queue_create("nfsu2.texrep.dump", at);
        for (int i = 0; i < NLQ; i++) g_dlq[i] = dispatch_queue_create("nfsu2.texrep.load", at);
    }
    if (g_dumping){
        char p[1200];
        snprintf(p, sizeof p, "%s", g_dumpdir);
        for (char *q = p + 1; *q; q++) if (*q == '/'){ *q = 0; mkdir(p, 0755); *q = '/'; }
        mkdir(p, 0755);
        fprintf(stderr, "[texrep] collecting static textures in %s\n", g_dumpdir);
    }
}

/* ---- formats ---------------------------------------------------------------- */
#define FMT_DXT1 0x31545844u
#define FMT_DXT3 0x33545844u
#define FMT_DXT5 0x35545844u
static const char *fmt_name(uint32_t f){
    switch (f){ case FMT_DXT1: return "DXT1"; case FMT_DXT3: return "DXT3"; case FMT_DXT5: return "DXT5";
                case 21: return "A8R8G8B8"; case 22: return "X8R8G8B8"; }
    return "?";
}
/* bytes per row / rows of a level */
static void pf_level(MTLPixelFormat pf, unsigned w, unsigned h, size_t *row, size_t *rows){
    switch (pf){
    case MTLPixelFormatBC1_RGBA: *row = (size_t)((w + 3) / 4) * 8; *rows = (h + 3) / 4; return;
    case MTLPixelFormatBC2_RGBA: case MTLPixelFormatBC3_RGBA: case MTLPixelFormatBC7_RGBAUnorm:
        *row = (size_t)((w + 3) / 4) * 16; *rows = (h + 3) / 4; return;
    default: *row = (size_t)w * 4; *rows = h; return;
    }
}
static unsigned full_levels(unsigned w, unsigned h){
    unsigned n = 1; for (unsigned q = w > h ? w : h; q > 1; q >>= 1) n++;
    return n;
}

/* ---- DDS -------------------------------------------------------------------- */
typedef struct { unsigned w, h, levels; MTLPixelFormat pf; size_t off; } Dds;
static uint32_t rd32(const uint8_t *p){ uint32_t v; memcpy(&v, p, 4); return v; }
static int dds_parse(const uint8_t *b, size_t n, Dds *d){
    if (n < 128 || memcmp(b, "DDS ", 4) || rd32(b + 4) != 124) return 0;
    d->h = rd32(b + 12); d->w = rd32(b + 16);
    d->levels = rd32(b + 28); if (!d->levels) d->levels = 1;
    if (rd32(b + 112) & 0x200u) return 0;                    /* cube map */
    uint32_t pff = rd32(b + 80), four = rd32(b + 84), bits = rd32(b + 88), rm = rd32(b + 92);
    d->off = 128; d->pf = MTLPixelFormatInvalid;
    if (pff & 4u){
        if (four == FMT_DXT1) d->pf = MTLPixelFormatBC1_RGBA;
        else if (four == FMT_DXT3 || four == 0x32545844u) d->pf = MTLPixelFormatBC2_RGBA;
        else if (four == FMT_DXT5 || four == 0x34545844u) d->pf = MTLPixelFormatBC3_RGBA;
        else if (four == 0x30315844u && n >= 148){            /* "DX10" */
            uint32_t dx = rd32(b + 128); d->off = 148;
            if (rd32(b + 132) != 3u) return 0;                /* TEXTURE2D only */
            switch (dx){                                      /* the game is not sRGB-aware: _SRGB = UNORM */
            case 71: case 72: d->pf = MTLPixelFormatBC1_RGBA; break;
            case 74: case 75: d->pf = MTLPixelFormatBC2_RGBA; break;
            case 77: case 78: d->pf = MTLPixelFormatBC3_RGBA; break;
            case 98: case 99: d->pf = MTLPixelFormatBC7_RGBAUnorm; break;
            case 87: case 91: d->pf = MTLPixelFormatBGRA8Unorm; break;
            case 28: case 29: d->pf = MTLPixelFormatRGBA8Unorm; break;
            }
        }
    } else if ((pff & 0x40u) && bits == 32){
        d->pf = rm == 0x00ff0000u ? MTLPixelFormatBGRA8Unorm : rm == 0x000000ffu ? MTLPixelFormatRGBA8Unorm
              : MTLPixelFormatInvalid;
    }
    if (d->pf == MTLPixelFormatInvalid || !d->w || !d->h || d->w > 16384 || d->h > 16384) return 0;
    unsigned fl = full_levels(d->w, d->h);
    if (d->levels > fl) d->levels = fl;
    size_t need = 0;
    for (unsigned l = 0; l < d->levels; l++){
        unsigned lw = d->w >> l, lh = d->h >> l; if (!lw) lw = 1; if (!lh) lh = 1;
        size_t row, rows; pf_level(d->pf, lw, lh, &row, &rows); need += row * rows;
    }
    return d->off + need <= n;
}

/* ---- loader (GCD queue) ----------------------------------------------------- */
static void dready_post(DReady r){ push(&g_drmx, (void **)&g_dready, &g_dready_n, &g_dready_cap, sizeof r, &r); }
static uint8_t *read_file(const char *path, size_t *n){
    int fd = open(path, O_RDONLY); if (fd < 0) return 0;
    struct stat st; if (fstat(fd, &st) != 0 || st.st_size < 128 || st.st_size > (1ll << 31)){ close(fd); return 0; }
    uint8_t *b = malloc((size_t)st.st_size);
    size_t got = 0;
    while (b && got < (size_t)st.st_size){
        ssize_t k = read(fd, b + got, (size_t)st.st_size - got);
        if (k <= 0) break;
        got += (size_t)k;
    }
    close(fd);
    if (!b || got != (size_t)st.st_size){ free(b); return 0; }
    *n = got; return b;
}
/* DReady.fail: 0 = loaded, 1: shape / format, 2: read / parse, 3: over the budget
 * (bytes = what it needed).  The bytes of a loaded texture stay counted in g_bytes
 * until its DEnt is freed (texrep_frame). */
static void dds_load(int32_t ei, const char *path, unsigned w, unsigned h, unsigned olev, uint32_t fmt){
    double t0 = now_ms();
    DReady r = { ei, 0, 0, 2, NULL, 0, 0 };
    size_t n = 0; Dds d;
    uint8_t *b = read_file(path, &n);
    if (b && !dds_parse(b, n, &d)){ free(b); b = NULL; }
    if (!b){ r.ms = now_ms() - t0; dready_post(r); return; }
    r.fail = 1;
    /* same aspect ratio, not smaller, at most 16x (the sampler's LOD clamp has 3 bits) */
    if (d.w < w || d.h < h || (unsigned long long)d.w * h != (unsigned long long)d.h * w || d.w > (w << 4)){
        free(b); r.ms = now_ms() - t0; dready_post(r); return; }
    unsigned k = 0; while ((w << k) < d.w && k < 4) k++;
    int pow2 = (w << k) == d.w && (h << k) == d.h;
    int stacked = pow2 && k >= 1 && d.levels == k && d.pf == pixel_format(fmt);
    unsigned tot = stacked ? k + olev : d.levels;
    unsigned fl = full_levels(d.w, d.h); if (tot > fl) tot = fl;
    unsigned kk = pow2 ? k : 0;                     /* the sampler clamp needs log2 of a power-of-two scale */
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:d.pf
                                   width:d.w height:d.h mipmapped:(tot > 1)];
    td.mipmapLevelCount = tot;
    td.usage = MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    id<MTLDevice> dev = metal_device();
    MTLSizeAndAlign sa = dev ? [dev heapTextureSizeAndAlignWithDescriptor:td] : (MTLSizeAndAlign){0, 0};
    unsigned long long want = sa.size;
    /* reserve first: three loaders at once can never pass the budget together */
    if (atomic_fetch_add(&g_bytes, want) + want > g_budget){
        atomic_fetch_sub(&g_bytes, want);
        free(b); r.fail = 3; r.bytes = want; r.ms = now_ms() - t0; dready_post(r); return; }
    id<MTLTexture> t = dev ? [dev newTextureWithDescriptor:td] : nil;
    if (!t){ atomic_fetch_sub(&g_bytes, want); free(b); r.fail = 2; r.ms = now_ms() - t0; dready_post(r); return; }
    unsigned long long got = t.allocatedSize;      /* the reservation becomes the real size */
    if (got > want) atomic_fetch_add(&g_bytes, got - want); else atomic_fetch_sub(&g_bytes, want - got);
    size_t off = d.off;
    for (unsigned l = 0; l < d.levels && l < tot; l++){
        unsigned lw = d.w >> l, lh = d.h >> l; if (!lw) lw = 1; if (!lh) lh = 1;
        size_t row, rows; pf_level(d.pf, lw, lh, &row, &rows);
        [t replaceRegion:MTLRegionMake2D(0, 0, lw, lh) mipmapLevel:l withBytes:b + off bytesPerRow:row];
        off += row * rows;
    }
    free(b);
    r.fail = 0; r.k = kk; r.stacked = (unsigned)stacked; r.bytes = got;
    r.tex = (__bridge_retained void *)t;
    r.ms = now_ms() - t0;
    dready_post(r);
}

/* ---- dump (GCD queue) ---------------------------------------------------------- */
static int cat_of_src(const char *p){
    if (!p) return CAT_OTHER;
    if (strcasestr(p, "DYNTEX")) return CAT_SKY;              /* LOC4DYNTEX.BIN: clouds */
    if (!strncasecmp(p, "CARS/", 5)) return CAT_CARS;
    if (!strncasecmp(p, "TRACKS/", 7) || !strncasecmp(p, "NIS/", 4)) return CAT_WORLD;
    if (!strncasecmp(p, "FRONTEND/PLATFORMS/", 19)) return CAT_GARAGE;
    if (!strncasecmp(p, "FRONTEND/", 9) || !strncasecmp(p, "LANGUAGES/", 10)) return CAT_FRONTEND;
    if (!strncasecmp(p, "GLOBAL/InGame", 13) || !strncasecmp(p, "GLOBAL/HUD", 10)) return CAT_HUD;
    if (!strncasecmp(p, "GLOBAL/", 7)) return CAT_FRONTEND;
    return CAT_OTHER;
}
/* the file the guest read last, relative to the game folder */
static void src_rel(char *out, size_t n){
    const char *lr = g_last_read;
    out[0] = 0; if (!*lr) return;
    static const char *const tops[] = { "/CARS/", "/TRACKS/", "/NIS/", "/FRONTEND/", "/GLOBAL/", "/LANGUAGES/", "/MOVIES/" };
    const char *best = 0;
    for (unsigned i = 0; i < sizeof tops / sizeof tops[0]; i++){
        const char *p = strcasestr(lr, tops[i]); if (p && (!best || p < best)) best = p; }
    snprintf(out, n, "%s", best ? best + 1 : lr);
    for (char *q = out; *q; q++) if (*q == '\\') *q = '/';
}
static void dump_write(const TR *t, const Tex *x, const uint8_t *data, size_t len, unsigned pitch){
    uint8_t *copy = malloc(len); if (!copy) return;
    memcpy(copy, data, len);
    unsigned w = x->w, h = x->h, lev = t->lev; uint32_t fmt = x->fmt; uint64_t hh = t->hash; int cat = t->cat;
    char src[256]; src_rel(src, sizeof src);
    char *srcd = strdup(src);
    g_n_dumped++;
    dispatch_async(g_q, ^{
        char dir[1200], p[1400];
        snprintf(dir, sizeof dir, "%s/%s", g_dumpdir, k_cat[cat]); mkdir(dir, 0755);
        snprintf(p, sizeof p, "%s/%ux%u_%s_%016llx.dds", dir, w, h, fmt_name(fmt), (unsigned long long)hh);
        struct stat st;
        if (stat(p, &st) != 0){
            uint8_t hd[128]; memset(hd, 0, sizeof hd);
            memcpy(hd, "DDS ", 4);
            uint32_t v[32]; memset(v, 0, sizeof v);
            int bc = fmt == FMT_DXT1 || fmt == FMT_DXT3 || fmt == FMT_DXT5;
            v[1] = 124; v[2] = 0x1 | 0x2 | 0x4 | 0x1000 | (bc ? 0x80000u : 0x8u);
            v[3] = h; v[4] = w; v[5] = bc ? (uint32_t)len : pitch; v[7] = 1;
            v[19] = 32;
            if (bc){ v[20] = 0x4; v[21] = fmt; }
            else { v[20] = fmt == 21 ? 0x41u : 0x40u; v[22] = 32; v[23] = 0x00ff0000u; v[24] = 0x0000ff00u;
                   v[25] = 0x000000ffu; v[26] = fmt == 21 ? 0xff000000u : 0u; }
            v[27] = 0x1000;
            memcpy(hd + 4, v + 1, 124);
            char tmp[1500]; snprintf(tmp, sizeof tmp, "%s.tmp", p);
            FILE *f = fopen(tmp, "wb");
            if (f){ fwrite(hd, 1, 128, f); fwrite(copy, 1, len, f);
                    if (fclose(f) == 0) rename(tmp, p); else unlink(tmp); }
            snprintf(p, sizeof p, "%s/index.csv", g_dumpdir);
            int fresh = stat(p, &st) != 0;
            FILE *ix = fopen(p, "a");
            if (ix){ if (fresh) fprintf(ix, "hash,w,h,fmt,levels,category,source\n");
                     fprintf(ix, "%016llx,%u,%u,%s,%u,%s,%s\n", (unsigned long long)hh, w, h, fmt_name(fmt), lev,
                             k_cat[cat], srcd); fclose(ix); }
        }
        free(copy); free(srcd);
    });
}
/* a collected texture turned out to be dynamic: take the file back */
static void dump_unlink(const TR *t, const Tex *x, uint64_t hh){
    unsigned w = x->w, h = x->h; uint32_t fmt = x->fmt; int cat = t->cat;
    g_n_unlinked++;
    dispatch_async(g_q, ^{
        char p[1400];
        snprintf(p, sizeof p, "%s/%s/%ux%u_%s_%016llx.dds", g_dumpdir, k_cat[cat], w, h, fmt_name(fmt), (unsigned long long)hh);
        unlink(p);
    });
}

/* ---- DEnt bookkeeping (guest thread) ------------------------------------------- */
static int32_t dent_new(IdxEnt *index, uint32_t path){
    int32_t ei;
    if (g_dent_free >= 0){ ei = g_dent_free; g_dent_free = g_dent[ei].next; }
    else {
        if (g_dent_n == g_dent_cap){ g_dent_cap = g_dent_cap ? 2 * g_dent_cap : 1024;
                                     g_dent = realloc(g_dent, g_dent_cap * sizeof *g_dent); }
        ei = (int32_t)g_dent_n++;
    }
    memset(&g_dent[ei], 0, sizeof g_dent[ei]);
    g_dent[ei].index = index; g_dent[ei].path = path; g_dent[ei].st = D_LOADING;
    if (index) index->ent = ei;
    return ei;
}
static void dent_free(int32_t ei){
    DEnt *en = &g_dent[ei];
    if (en->tex){ CFBridgingRelease(en->tex); en->tex = NULL; atomic_fetch_sub(&g_bytes, en->bytes); g_n_tex_live--; }
    if (en->index && en->index->ent == ei) en->index->ent = -1;
    en->next = g_dent_free; g_dent_free = ei; en->st = D_FAILED; en->refs = en->waiters = 0;
}
/* free a DEnt nobody shows or waits for (a loading one when its load ends).  A failed
 * load stays linked as a marker so its file is not read again; a budget failure is
 * retried once enough memory is free (dds_uploaded). */
static void dent_unref(int32_t ei){
    DEnt *en = &g_dent[ei];
    if (en->refs || en->waiters || en->st == D_LOADING) return;
    if ((en->st == D_FAILED || en->st == D_BUDGET) && en->index) return;
    dent_free(ei);
}
static void dds_load_start(int32_t ei, const Tex *x, const TR *t){
    unsigned w = x->w, h = x->h, olev = t->lev; uint32_t fmt = x->fmt;
    const char *path = g_paths + g_dent[ei].path;
    g_n_loaded++;
    dispatch_async(g_dlq[g_dlq_next++ % NLQ], ^{ dds_load(ei, path, w, h, olev, fmt); });
}
static void dpend_add(unsigned mid, unsigned gen){
    if (g_dpend_n == g_dpend_cap){ g_dpend_cap = g_dpend_cap ? 2 * g_dpend_cap : 256;
                                   g_dpend = realloc(g_dpend, g_dpend_cap * sizeof *g_dpend); }
    g_dpend[g_dpend_n++] = (Pend){ mid, gen };
}
/* this id stops showing / waiting for its DDS replacement: the game's own texture shows */
static void tr_drop(TR *t, unsigned mid){
    if (t->state == S_ACTIVE){
        op_post((Op){ OP_SET, 0, 0, mid, 0, NULL });
        g_dent[t->ent].refs--; dent_unref(t->ent);
    } else if (t->state == S_PENDING){
        g_dent[t->ent].waiters--; dent_unref(t->ent);
    }
    t->state = S_NONE; t->gen++; t->ent = -1;
}
static void tr_dynamic(TR *t, const Tex *x, unsigned mid){
    t->dyn = 1; g_n_dyn++;
    if (t->dumped){ dump_unlink(t, x, t->hash); t->dumped = 0; }
    if (t->state != S_NONE){ g_n_drop++; tr_drop(t, mid); }
}

/* level 0 (first upload or again) and the lower levels of a texture the DDS path may
 * replace or collect; ntxp: an NTXP pack has this content (it wins) */
static void dds_uploaded(unsigned mid, unsigned level, const uint8_t *data, unsigned pitch, unsigned rows, int ntxp){
    TR *t = &g_tr[mid]; const Tex *x = &g_t[mid];
    if (!t->ok || t->dyn) return;
    t->last_up = g_frame;
    size_t len = (size_t)pitch * rows;
    double t0 = now_ms();
    if (level){
        if (level >= 16) return;
        int again = (t->lvmask >> level) & 1u;
        if (!again){ t->lvmask |= 1u << level; t->lvh += XXH3_64bits_withSeed(data, len, level); }
        else g_n_relevel++;
        g_hash_ms += now_ms() - t0; g_hash_bytes += len;
        if (t->state == S_ACTIVE && t->k){
            DEnt *en = &g_dent[t->ent];
            if (en->refs > 1){
                /* the DEnt's lower levels are another id's: this one goes back to its own
                 * texture rather than change what the others show */
                g_n_unshare++; tr_drop(t, mid);
            } else {
                /* a stacked replacement keeps the game's level up to date */
                op_post((Op){ OP_COPY, t->k, 1, mid, level, NULL });
                if (again) en->solo = 1;               /* content may differ now: nobody shares it */
                else { en->lvmask = t->lvmask; en->lvh = t->lvh; }
            }
        }
        return;
    }
    uint64_t seed = (uint64_t)x->w | (uint64_t)x->h << 16 | (uint64_t)x->fmt << 32;
    uint64_t hh = XXH3_64bits_withSeed(data, len, seed);
    g_n_hashed++; g_hash_bytes += len;
    if (t->hash && t->hash != hh){
        /* new content under the same texture: it is dynamic, the game's own texture shows
         * from now on (and a collected copy of the old content goes) */
        tr_dynamic(t, x, mid);
        g_hash_ms += now_ms() - t0;
        return;
    }
    int first = !t->hash;
    t->hash = hh; t->lvmask |= 1u;
    if (first && g_dumping){ dump_write(t, x, data, len, pitch); t->dumped = 1; }
    if (ntxp && t->state != S_NONE) tr_drop(t, mid);
    if (first && g_dds_on && !ntxp && t->state == S_NONE){
        IdxEnt *e = idx_get(hh);
        if (e){
            int32_t ei = e->ent;
            if (ei >= 0 && g_dent[ei].st == D_FAILED){ if (g_dent[ei].bytes == 1) g_n_shape++; else g_n_fail++; ei = -2; }
            else if (ei >= 0 && g_dent[ei].st == D_BUDGET){
                if (atomic_load(&g_bytes) + g_dent[ei].bytes > g_budget){ g_n_budget++; ei = -2; }
                else { dent_free(ei); ei = -1; }        /* memory was freed: try again */
            }
            if (ei != -2){
                g_n_hit++;
                if (ei < 0 || g_dent[ei].solo){            /* nothing to share: load it */
                    ei = dent_new(ei < 0 ? e : NULL, e->path);
                    if (!g_dent[ei].index) g_n_private++;
                    dds_load_start(ei, x, t);
                }
                t->state = S_PENDING; t->gen++; t->req_frame = g_frame; t->ent = ei;
                g_dent[ei].waiters++;
                dpend_add(mid, t->gen);
                if (in_race()) g_load_race++;
            }
        }
    }
    g_hash_ms += now_ms() - t0;
}
static void lat_note(long d){
    int b = d <= 0 ? 0 : d == 1 ? 1 : d == 2 ? 2 : d <= 4 ? 3 : d <= 8 ? 4 : d <= 16 ? 5 : d <= 64 ? 6 : 7;
    g_lat_hist[b]++; if (d > g_lat_max) g_lat_max = d;
}
static void dds_frame(void){
    double t0 = now_ms();
    g_frame++;
    /* finished loads */
    pthread_mutex_lock(&g_drmx);
    DReady *rs = g_dready; unsigned n = g_dready_n;
    g_dready = NULL; g_dready_n = g_dready_cap = 0;
    pthread_mutex_unlock(&g_drmx);
    for (unsigned i = 0; i < n; i++){
        DReady r = rs[i];
        DEnt *en = &g_dent[r.ei];
        g_load_ms_sum += r.ms; if (r.ms > g_load_ms_max) g_load_ms_max = r.ms;
        if (r.fail){
            if (g_verbose) fprintf(stderr, "[texrep] %s: %s\n", g_paths + en->path,
                                   r.fail == 1 ? "size or format does not fit, left out"
                                   : r.fail == 3 ? "over the memory budget, left out" : "cannot read the file");
            en->st = r.fail == 3 ? D_BUDGET : D_FAILED;
            en->bytes = r.fail == 3 ? r.bytes : r.fail;   /* D_FAILED: 1 = shape, 2 = read */
            unsigned wt = en->waiters;
            if (r.fail == 1) g_n_shape += wt; else if (r.fail == 3) g_n_budget += wt; else g_n_fail += wt;
        } else {
            en->st = D_READY; en->tex = r.tex; en->k = (uint8_t)r.k; en->stacked = (uint8_t)r.stacked;
            en->bytes = r.bytes;
            if (++g_n_tex_live > g_n_tex_peak) g_n_tex_peak = g_n_tex_live;
            unsigned long long b = atomic_load(&g_bytes); if (b > g_bytes_peak) g_bytes_peak = b;
        }
        if (!en->waiters){ if (!r.fail) g_n_stale++; dent_unref(r.ei); }   /* nobody waits any more */
    }
    free(rs);
    /* ids waiting for a DEnt */
    unsigned keep = 0;
    for (unsigned i = 0; i < g_dpend_n; i++){
        Pend p = g_dpend[i];
        TR *t = &g_tr[p.mid];
        if (t->gen != p.gen || t->state != S_PENDING) continue;          /* dropped meanwhile */
        DEnt *en = &g_dent[t->ent];
        if (en->st == D_LOADING){ g_dpend[keep++] = p; continue; }
        if (en->st != D_READY){                                          /* failed: stays original */
            int32_t ei = t->ent; t->state = S_NONE; t->ent = -1; en->waiters--; dent_unref(ei);
            continue;
        }
        /* stacked: publish once the game's levels are in (they are copied under the
         * pack's), once it stopped uploading (some textures never get all their levels),
         * or after 60 frames; a level that comes later is copied then (OP_COPY) */
        unsigned want = t->lev >= 16 ? 0xFFFFu : (1u << t->lev) - 1u;
        int why = (t->lvmask & want) == want ? 0 : g_frame - t->last_up >= 2 ? 1 : g_frame - t->req_frame >= 60 ? 2 : -1;
        if (en->stacked && why < 0){ g_dpend[keep++] = p; continue; }
        if (!en->stacked) why = 0;
        int own = en->refs == 0;
        if (!own && (en->solo || en->lev != t->lev || en->lvmask != t->lvmask || en->lvh != t->lvh)){
            /* the same pack file, other lower levels: this id gets its own copy */
            int32_t old = t->ent;
            en->waiters--;
            int32_t ei = dent_new(NULL, en->path); g_n_private++;          /* (en may move: realloc) */
            t->ent = ei; g_dent[ei].waiters++;
            dds_load_start(ei, &g_t[p.mid], t);
            dent_unref(old);
            g_dpend[keep++] = p;
            continue;
        }
        if (own){ en->lev = t->lev; en->lvmask = t->lvmask; en->lvh = t->lvh; }
        else g_n_shared++;
        en->waiters--; en->refs++;
        t->state = S_ACTIVE; t->k = en->k;
        op_post((Op){ OP_SET, en->k, (uint8_t)(own && en->stacked), p.mid, 0, (void *)CFRetain(en->tex) });
        g_n_pub++; g_why[why]++; lat_note(g_frame - t->req_frame);
        if (in_race()) g_pub_race++;
        if (g_verbose){ const Tex *x = &g_t[p.mid];
            fprintf(stderr, "[texrep] f=%ld t%u %ux%u %s %016llx -> x%u%s%s %s\n", g_frame, p.mid, x->w, x->h,
                    fmt_name(x->fmt), (unsigned long long)t->hash, 1u << en->k,
                    en->stacked ? " (stacked)" : "", own ? "" : " (shared)", g_paths + en->path); }
    }
    g_dpend_n = keep;
    double ms = now_ms() - t0 + g_hash_ms - g_hash_ms_mark;   /* this frame's drain + hashing since the last frame */
    g_hash_ms_mark = g_hash_ms;
    if (ms > g_frame_ms_max) g_frame_ms_max = ms;
    if (ms > 1.0) g_frames_over1++;
}

/* ---- guest hooks -------------------------------------------------------------- */
void texrep_created(unsigned mid, unsigned w, unsigned h, unsigned levels, unsigned d3dfmt,
                    unsigned usage, unsigned pool, uint32_t name){
    if (!on() || !mid || mid >= TEXREP_MAXTEX) return;
    if (!g_t){ g_t = calloc(TEXREP_MAXTEX, sizeof *g_t); g_ent = calloc(g_base[g_npack] + 1, sizeof *g_ent);
               if (!g_t || !g_ent){ fprintf(stderr, "[texpacks] out of memory: off\n"); g_on = 0; return; } }
    Tex *t = &g_t[mid];
    if (t->ok && t->shown >= 0){ t->want = -1; settle(mid); }  /* an id used again: its old picture goes */
    if (g_tr && (g_tr[mid].state != S_NONE || g_tr[mid].hash)) texrep_released(mid);
    t->w = (uint16_t)w; t->h = (uint16_t)h; t->fmt = d3dfmt; t->want = t->shown = -1;
    t->name = g_names ? name : 0;
    char src[256]; src_rel(src, sizeof src);
    int movie = strncasecmp(src, "MOVIES/", 7) == 0;
    /* static game textures only: managed pool, no usage flags (render target,
     * dynamic), and a key a pack may have */
    int may = g_hash_all || t->name;
    for (unsigned k = 0; !may && k < g_npack; k++) may = texpack_may_match(&g_pack[k], w, h, d3dfmt);
    t->ok = g_npack && pool == 1u && usage == 0u && w <= 4096 && h <= 4096 && may;
    if (g_tr){
        TR *r = &g_tr[mid];
        uint32_t gen = r->gen + 1;
        memset(r, 0, sizeof *r);
        r->gen = gen; r->ent = -1;
        g_n_created++;
        r->lev = (uint8_t)(levels > 15 ? 15 : levels ? levels : 1);
        r->cat = (uint8_t)cat_of_src(src);
        /* a block or 32-bit format, more than 32 x 32 texels (ramps and lookup
         * tables), no movie frames */
        r->ok = pool == 1u && usage == 0u && pixel_format(d3dfmt) != MTLPixelFormatInvalid
             && w >= 16 && h >= 16 && w * h > 1024u && w <= 4096 && h <= 4096 && !movie;
        if (r->ok) g_n_eligible++;
    }
}
void texrep_uploaded(unsigned mid, unsigned level, const uint8_t *data, unsigned pitch, unsigned rows){
    if (!g_on || !g_t || !mid || mid >= TEXREP_MAXTEX || !data) return;
    Tex *t = &g_t[mid];
    int ntxp = 0;
    if (level == 0 && t->ok){
        t->want = find(t, data, (size_t)pitch * rows);
        ntxp = t->want >= 0;
    }
    if (g_tr) dds_uploaded(mid, level, data, pitch, rows, ntxp);
    if (level == 0 && t->ok) settle(mid);
}
void texrep_surface_written(unsigned mid){
    if (!g_on || !g_t || !mid || mid >= TEXREP_MAXTEX) return;
    Tex *t = &g_t[mid];
    if (g_tr && g_tr[mid].ok && !g_tr[mid].dyn) tr_dynamic(&g_tr[mid], t, mid);
    if (!t->ok) return;
    t->ok = 0; t->want = -1;
    settle(mid);
}
void texrep_released(unsigned mid){
    if (!g_on || !g_t || !mid || mid >= TEXREP_MAXTEX) return;
    Tex *t = &g_t[mid];
    if (t->ok && t->shown >= 0){ t->want = -1; settle(mid); }
    t->ok = 0;
    if (g_tr){ tr_drop(&g_tr[mid], mid); g_tr[mid].ok = 0; g_tr[mid].hash = 0; }
}
void texrep_frame(void){
    if (!g_on || !g_t) return;
    if (g_tr) dds_frame();
    if (!g_npack) return;
    pthread_mutex_lock(&g_rmx);
    Ready *rs = g_ready; unsigned n = g_ready_n;
    g_ready = NULL; g_ready_n = g_ready_cap = 0;
    pthread_mutex_unlock(&g_rmx);
    for (unsigned i = 0; i < n; i++){
        Ent *en = &g_ent[rs[i].ei];
        en->tex = rs[i].tex; en->st = rs[i].tex ? E_READY : E_FAILED;
        if (!rs[i].tex){ unsigned k, li; entry(rs[i].ei, &k, &li);
                         fprintf(stderr, "[texpacks] pack %u %s: cannot be loaded, the game's own stays\n",
                                 k + 1, texpack_name(&g_pack[k], li)); }
    }
    free(rs);
    if (!n || !g_pend_n) return;
    unsigned *pend = g_pend, pn = g_pend_n;
    g_pend = NULL; g_pend_n = g_pend_cap = 0;
    for (unsigned i = 0; i < pn; i++){ g_t[pend[i]].pending = 0; settle(pend[i]); }
    free(pend);
}

/* ---- main thread ---------------------------------------------------------------- */
void texrep_main_frame(id<MTLCommandQueue> q){
    if (!g_on) return;
    Op *ops = NULL; unsigned n = 0;
    if (g_ops_n){                                        /* racy peek; the lock decides */
        pthread_mutex_lock(&g_omx);
        ops = g_ops; n = g_ops_n; g_ops = NULL; g_ops_n = g_ops_cap = 0;
        pthread_mutex_unlock(&g_omx);
    }
    id<MTLCommandBuffer> cb = nil; id<MTLBlitCommandEncoder> bl = nil;
    for (unsigned i = 0; i < n; i++){
        Op o = ops[i];
        unsigned mid = o.mid;
        if (mid >= TEXREP_MAXTEX){ if (o.tex) CFBridgingRelease(o.tex); continue; }
        if (o.op == OP_SET){
            id<MTLTexture> t = o.tex ? (__bridge_transfer id<MTLTexture>)o.tex : nil;
            if (t && o.stacked){
                /* the game's own levels under the pack's */
                id<MTLTexture> orig = metal_tex_object(mid);
                if (orig && q && orig.pixelFormat == t.pixelFormat){
                    NSUInteger nl = orig.mipmapLevelCount;
                    if (o.k + nl > t.mipmapLevelCount) nl = t.mipmapLevelCount - o.k;
                    if (!cb){ cb = [q commandBuffer]; cb.label = @"texrep"; bl = [cb blitCommandEncoder]; }
                    if (nl) [bl copyFromTexture:orig sourceSlice:0 sourceLevel:0 toTexture:t
                               destinationSlice:0 destinationLevel:o.k sliceCount:1 levelCount:nl];
                }
            }
            if (!g_texrep_tex[mid] && t) g_main_live++;
            else if (g_texrep_tex[mid] && !t) g_main_live--;
            g_texrep_tex[mid] = t; g_texrep_k[mid] = t ? o.k : 0;
        } else if (o.op == OP_COPY){
            id<MTLTexture> t = g_texrep_tex[mid], orig = metal_tex_object(mid);
            if (t && orig && q && orig.pixelFormat == t.pixelFormat && o.level < orig.mipmapLevelCount
                && o.k + o.level < t.mipmapLevelCount){
                if (!cb){ cb = [q commandBuffer]; cb.label = @"texrep"; bl = [cb blitCommandEncoder]; }
                [bl copyFromTexture:orig sourceSlice:0 sourceLevel:o.level toTexture:t
                   destinationSlice:0 destinationLevel:o.k + o.level sliceCount:1 levelCount:1];
            }
        }
    }
    free(ops);
    if (cb){ [bl endEncoding]; [cb commit]; }       /* before this frame's command buffer */
    g_texrep_frame_on = g_main_live && atomic_load(&g_shown);
}
/* sampler key for a replaced texture (metal.m samp_for decodes bits 15-17): where the
 * game's sampler has no mip filter it read only the original's level 0; the DDS
 * replacement gets linear mip filtering with the LOD clamped at level k (= the
 * original's level 0), so magnified it blends the pack's levels and minified it still
 * reads the game's own texels, as before. */
unsigned texrep_skey_slow(unsigned sk, unsigned k){
    unsigned mp = (sk >> 4) & 3u;
    g_mipstat[mp]++;
    if (mp == 0 && k) sk = (sk & ~0x30u) | 0x20u | ((k & 7u) << 15);
    return sk;
}

/* ---- Cmd-T: the game's own textures and the packs', for comparing ------------------ */
void texrep_set_shown(int v){
    v = v < 0 ? !atomic_load(&g_shown) : !!v;
    atomic_store(&g_shown, v);
    fprintf(stderr, "[texpacks] %s\n", v ? "shown" : "hidden (the game's own textures)");
}
int texrep_shown(void){ return atomic_load(&g_shown); }
@interface TexrepMenuTarget : NSObject
- (void)toggle:(NSMenuItem *)it;
@end
@implementation TexrepMenuTarget
- (void)toggle:(NSMenuItem *)it {
    texrep_set_shown(-1);
    [it setState:texrep_shown() ? NSControlStateValueOn : NSControlStateValueOff];
}
@end
static TexrepMenuTarget *g_menu_target;
void texrep_add_menu(NSMenu *m){
    if (!on() || (!g_npack && !g_dds_on)) return;
    g_menu_target = [TexrepMenuTarget new];
    /* Cmd-T alone: a modifier pressed before Command reaches the game */
    NSMenuItem *it = [m addItemWithTitle:@"Texture Packs" action:@selector(toggle:) keyEquivalent:@"t"];
    [it setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [it setTarget:g_menu_target];
    [it setState:NSControlStateValueOn];
}

/* ---- report (com.c, at the end) -------------------------------------------------- */
void texrep_report(void){
    if (!g_on || !g_tr) return;
    if (g_dds_on){
        fprintf(stderr, "[texrep] textures %lu created, %lu eligible, %lu hashed (%.1f MB, %.1f ms); "
                "pack hits %lu: %lu shown (%lu sharing a texture already loaded), %lu dropped (content changed), "
                "%lu went back to their own levels; %lu left out (size/format), %lu over budget, %lu unreadable; dynamic %lu\n",
                g_n_created, g_n_eligible, g_n_hashed, g_hash_bytes / 1048576.0, g_hash_ms,
                g_n_hit, g_n_pub, g_n_shared, g_n_drop, g_n_unshare, g_n_shape, g_n_budget, g_n_fail, g_n_dyn);
        fprintf(stderr, "[texrep] replacement GPU memory %.1f MB (peak %.1f MB, budget %.0f MB) in %lu loaded texture(s) "
                "(peak %lu; %lu loads, %lu of them a private copy, %lu not needed any more); loader %.1f ms in total, "
                "slowest %.2f ms; lower levels uploaded again %lu\n",
                atomic_load(&g_bytes) / 1048576.0, g_bytes_peak / 1048576.0, g_budget / 1048576.0, g_n_tex_live,
                g_n_tex_peak, g_n_loaded, g_n_private, g_n_stale, g_load_ms_sum, g_load_ms_max, g_n_relevel);
        fprintf(stderr, "[texrep] publish latency (frames) 0:%lu 1:%lu 2:%lu 3-4:%lu 5-8:%lu 9-16:%lu 17-64:%lu >64:%lu, "
                "max %ld (all levels in %lu, uploads stopped %lu, 60 frames %lu); in race/free roam: %lu requested, %lu shown\n",
                g_lat_hist[0], g_lat_hist[1], g_lat_hist[2], g_lat_hist[3], g_lat_hist[4], g_lat_hist[5],
                g_lat_hist[6], g_lat_hist[7], g_lat_max, g_why[0], g_why[1], g_why[2], g_load_race, g_pub_race);
        fprintf(stderr, "[texrep] guest thread time in texrep per frame: max %.3f ms, %lu frame(s) over 1 ms of %ld; "
                "replaced binds by mip filter none/point/linear %lu/%lu/%lu\n",
                g_frame_ms_max, g_frames_over1, g_frame, g_mipstat[0], g_mipstat[1], g_mipstat[2]);
    }
    if (g_dumping)
        fprintf(stderr, "[texrep] collected: %lu texture(s) written to %s (%lu taken back: dynamic)\n",
                g_n_dumped, g_dumpdir, g_n_unlinked);
    if (g_q) dispatch_sync(g_q, ^{});                /* finish pending writes */
}
