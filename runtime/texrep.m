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
 * The launcher makes the packs (NTXP, texpack.h) from the mods' own downloads:
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
 * Memory: one Metal texture per pack entry, loaded on its first use and kept (the game
 * creates new texture ids for the same textures on every load; they share it), so at
 * most the size of the packs' textures that were seen.
 *
 * Threads.  Guest thread: lookups, which pack entries are loading, the changes for the
 * draw encoder (texrep_frame).  Loader (a GCD queue): reading the levels, making the
 * Metal texture.  Main thread (texrep_main_frame, start of each frame's encode): the
 * id -> texture table the encoder reads.  They hand over through two mutex-protected
 * lists. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#include "texrep.h"
#include "texpack.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <pthread.h>
#include <stdatomic.h>
#include <zlib.h>

id<MTLDevice> metal_device(void);                                   /* metal.m */
int fileio_game_path(const char *win, char *out, size_t outsz);    /* fileio.c */

/* ---- main-thread state the encoder reads -------------------------------- */
int g_texrep_frame_on;
__strong id<MTLTexture> g_texrep_tex[TEXREP_MAXTEX];
static unsigned g_main_live;                       /* ids in g_texrep_tex */
static _Atomic int g_shown = 1;                    /* Cmd-T */

/* ---- the packs (opened once, from whichever thread asks first) ---------- */
#define MAXPACKS 32
static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static int g_on;                                   /* a pack is open */
static int g_log;
static Texpack g_pack[MAXPACKS];
static unsigned g_npack;
static unsigned g_base[MAXPACKS + 1];              /* entry e of pack k: g_base[k] + e */
static int g_hash_all;                             /* a pack has TexMod keys: hash every texture */
static int g_names;                                /* a pack has name keys */
static dispatch_queue_t g_lq;

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
    if (!g_npack) return;
    g_lq = dispatch_queue_create("nfsu2.texpacks.load",
                                 dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    g_on = 1;
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
    uint8_t ok;                                    /* a pack may replace it */
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
typedef struct { unsigned mid; void *tex; } Op;    /* tex: a +1 reference, NULL = the game's own again */
static pthread_mutex_t g_omx = PTHREAD_MUTEX_INITIALIZER;
static Op *g_ops; static unsigned g_ops_n, g_ops_cap;

static void push(pthread_mutex_t *mx, void **arr, unsigned *n, unsigned *cap, size_t sz, const void *item){
    pthread_mutex_lock(mx);
    if (*n == *cap){ *cap = *cap ? 2 * *cap : 256; *arr = realloc(*arr, *cap * sz); }
    memcpy((char *)*arr + *n * sz, item, sz); (*n)++;
    pthread_mutex_unlock(mx);
}

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
    Op o = { mid, ei >= 0 ? (void *)CFRetain(g_ent[ei].tex) : NULL };
    push(&g_omx, (void **)&g_ops, &g_ops_n, &g_ops_cap, sizeof o, &o);
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

/* ---- guest hooks -------------------------------------------------------------- */
void texrep_created(unsigned mid, unsigned w, unsigned h, unsigned d3dfmt, unsigned usage,
                    unsigned pool, uint32_t name){
    if (!on() || !mid || mid >= TEXREP_MAXTEX) return;
    if (!g_t){ g_t = calloc(TEXREP_MAXTEX, sizeof *g_t); g_ent = calloc(g_base[g_npack], sizeof *g_ent);
               if (!g_t || !g_ent){ fprintf(stderr, "[texpacks] out of memory: off\n"); g_on = 0; return; } }
    Tex *t = &g_t[mid];
    if (t->shown >= 0 && t->ok){ t->want = -1; settle(mid); }  /* an id used again: its old picture goes */
    t->w = (uint16_t)w; t->h = (uint16_t)h; t->fmt = d3dfmt; t->want = t->shown = -1;
    t->name = g_names ? name : 0;
    /* static game textures only: managed pool, no usage flags (render target,
     * dynamic), and a key a pack may have */
    int may = g_hash_all || t->name;
    for (unsigned k = 0; !may && k < g_npack; k++) may = texpack_may_match(&g_pack[k], w, h, d3dfmt);
    t->ok = pool == 1u && usage == 0u && w <= 4096 && h <= 4096 && may;
}
void texrep_uploaded(unsigned mid, const uint8_t *data, unsigned pitch, unsigned rows){
    if (!g_on || !g_t || !mid || mid >= TEXREP_MAXTEX || !data) return;
    Tex *t = &g_t[mid];
    if (!t->ok) return;
    t->want = find(t, data, (size_t)pitch * rows);
    settle(mid);
}
void texrep_surface_written(unsigned mid){
    if (!g_on || !g_t || !mid || mid >= TEXREP_MAXTEX) return;
    Tex *t = &g_t[mid];
    if (!t->ok) return;
    t->ok = 0; t->want = -1;
    settle(mid);
}
void texrep_frame(void){
    if (!g_on || !g_t) return;
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
void texrep_main_frame(void){
    if (!g_on) return;
    Op *ops = NULL; unsigned n = 0;
    if (g_ops_n){                                        /* racy peek; the lock decides */
        pthread_mutex_lock(&g_omx);
        ops = g_ops; n = g_ops_n; g_ops = NULL; g_ops_n = g_ops_cap = 0;
        pthread_mutex_unlock(&g_omx);
    }
    for (unsigned i = 0; i < n; i++){
        unsigned mid = ops[i].mid;
        id<MTLTexture> t = ops[i].tex ? (__bridge_transfer id<MTLTexture>)ops[i].tex : nil;
        if (!g_texrep_tex[mid] && t) g_main_live++;
        else if (g_texrep_tex[mid] && !t) g_main_live--;
        g_texrep_tex[mid] = t;
    }
    free(ops);
    g_texrep_frame_on = g_main_live && atomic_load(&g_shown);
}

/* ---- Cmd-T: the game's own textures and the packs', for comparing ------------------ */
@interface TexrepMenuTarget : NSObject
- (void)toggle:(NSMenuItem *)it;
@end
@implementation TexrepMenuTarget
- (void)toggle:(NSMenuItem *)it {
    int v = !atomic_load(&g_shown);
    atomic_store(&g_shown, v);
    [it setState:v ? NSControlStateValueOn : NSControlStateValueOff];
    fprintf(stderr, "[texpacks] %s\n", v ? "shown" : "hidden (the game's own textures)");
}
@end
static TexrepMenuTarget *g_menu_target;
void texrep_add_menu(NSMenu *m){
    if (!on()) return;
    g_menu_target = [TexrepMenuTarget new];
    /* Cmd-T alone: a modifier pressed before Command reaches the game */
    NSMenuItem *it = [m addItemWithTitle:@"Doku Paketleri" action:@selector(toggle:) keyEquivalent:@"t"];
    [it setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [it setTarget:g_menu_target];
    [it setState:NSControlStateValueOn];
}
