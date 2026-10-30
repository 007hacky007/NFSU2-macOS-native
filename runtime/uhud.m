/* uhud.m -- LunicAura106's Upscaled HUD (UHUD, nfsmods.xyz/mod/4319) as a
 * texture pack: the menus, HUD, fonts, icons and logos redrawn at four times
 * their size.  After th0mk's nfsu2-web (runtime/web/texrep_web.c, its pack
 * format and tools/texpacks.py), which did it first for the browser.
 *
 *   NFSU2_UHUD      = off | on        off by default (the game's own textures)
 *   NFSU2_UHUD_PACK = <absolute path> the pack; otherwise TEXPACKS/uhud.pak in
 *                                     the game folder.  The launcher makes it
 *                                     from the mod's archive (launcher/UHUDPack.swift).
 *   NFSU2_UHUD_LOG  = 1               one line per replaced texture
 *
 * On a PC the mod's installer writes the larger textures into the game's
 * files, and its plugin (NFSU2HDContentSupport.asi) gives the game the old
 * sizes back where it measures a texture in texels: the fonts' glyph tables,
 * the mouse cursor.  Here the game keeps reading its own files and sees every
 * texture at its own size; GetLevelDesc, LockRect and every upload keep using
 * the original Metal texture.  Only the draw encoder (metal.m, uhud_pick)
 * samples the pack's texture in its place.  The game samples with coordinates
 * of 0 to 1, so the larger texture is drawn where the original was, and the
 * fonts and the cursor stay right without the plugin.
 *
 * Which texture: the pack (texpack.c) keys each one by CRC-32 and Adler-32 of
 * level 0 as the game uploads it, its size and its format.  Every upload of
 * level 0 of a texture whose size and format the pack has is looked up again,
 * so a texture whose content changes shows the pack's only while its content
 * is the one the pack replaces.  A texture a language pack redrew has other
 * bytes and keeps the language pack's own.  Render targets, textures written
 * through a surface (the car skin composite) and movie frames are never the
 * pack's.
 *
 * Memory: one Metal texture per pack entry, loaded on its first use and kept
 * (the game creates new texture ids for the same textures on every load; they
 * share it), so at most the pack's size, about 100 MB.
 *
 * Threads.  Guest thread: lookups, which pack entries are loading, the
 * changes for the draw encoder (uhud_frame).  Loader (a GCD queue): reading
 * the levels, making the Metal texture.  Main thread (uhud_main_frame, start
 * of each frame's encode): the id -> texture table the encoder reads.  They
 * hand over through two mutex-protected lists. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#include "uhud.h"
#include "texpack.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <pthread.h>
#include <stdatomic.h>

id<MTLDevice> metal_device(void);                                   /* metal.m */
int fileio_game_path(const char *win, char *out, size_t outsz);    /* fileio.c */

/* ---- main-thread state the encoder reads -------------------------------- */
int g_uhud_frame_on;
__strong id<MTLTexture> g_uhud_tex[UHUD_MAXTEX];
static unsigned g_main_live;                       /* ids in g_uhud_tex */
static _Atomic int g_shown = 1;                    /* Cmd-T */

/* ---- the pack (opened once, from whichever thread asks first) ----------- */
static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static int g_on;                                   /* the pack is open */
static int g_log;
static Texpack g_pack;
static dispatch_queue_t g_lq;

static void open_pack(void){
    const char *v = getenv("NFSU2_UHUD");
    if (!v || (strcasecmp(v, "on") && strcmp(v, "1"))) return;
    g_log = getenv("NFSU2_UHUD_LOG") && *getenv("NFSU2_UHUD_LOG");
    char path[4096] = "", err[160];
    const char *custom = getenv("NFSU2_UHUD_PACK");
    if (custom && *custom){
        if (custom[0] == '/' && strlen(custom) < sizeof path) snprintf(path, sizeof path, "%s", custom);
        else fprintf(stderr, "[uhud] NFSU2_UHUD_PACK must be an absolute path\n");
    } else if (!fileio_game_path("TEXPACKS\\uhud.pak", path, sizeof path)) path[0] = 0;
    if (!*path || !texpack_open(&g_pack, path, err, sizeof err)){
        fprintf(stderr, "[uhud] not in use: %s; the game's own textures stay\n",
                *path ? err : "no TEXPACKS/uhud.pak in the game folder");
        return;
    }
    g_lq = dispatch_queue_create("nfsu2.uhud.load",
                                 dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    g_on = 1;
    fprintf(stderr, "[uhud] %u textures from %s\n", g_pack.count, path);
}
static int on(void){ pthread_once(&g_once, open_pack); return g_on; }

/* ---- per texture id and per pack entry (guest thread only) -------------- */
typedef struct {
    uint16_t w, h; uint32_t fmt;
    uint8_t ok;                                    /* the pack has its size and format */
    uint8_t pending;                               /* in g_pend */
    int32_t want;                                  /* pack entry for its current content, or -1 */
    int32_t shown;                                 /* pack entry published for it, or -1 */
} Tex;
static Tex *g_t;
enum { E_NONE, E_LOADING, E_READY, E_FAILED };
typedef struct { uint8_t st; void *tex; } Ent;     /* tex: +1 while E_READY */
static Ent *g_ent;
static unsigned *g_pend, g_pend_n, g_pend_cap;     /* ids whose entry is loading */
static unsigned long g_n_hashed, g_n_shown, g_n_back, g_n_loaded, g_n_failed;

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
    const TexpackEntry *e = &g_pack.entries[ei];
    Ready r = { ei, NULL };
    uint8_t *b = malloc(e->size);
    id<MTLDevice> dev = metal_device();
    if (b && dev && texpack_read(&g_pack, ei, b, e->size)){
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
        g_ent[ei].st = E_LOADING; g_n_loaded++;
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
    if (ei >= 0){
        g_n_shown++;
        if (g_log){ const TexpackEntry *e = &g_pack.entries[ei];
                    fprintf(stderr, "[uhud] t%u %s %ux%u -> %ux%u\n", mid, texpack_name(&g_pack, (unsigned)ei),
                            e->ow, e->oh, e->w, e->h); }
    } else g_n_back++;
    t->shown = ei;
}

/* ---- guest hooks -------------------------------------------------------------- */
void uhud_created(unsigned mid, unsigned w, unsigned h, unsigned d3dfmt, unsigned usage, unsigned pool){
    if (!on() || !mid || mid >= UHUD_MAXTEX) return;
    if (!g_t){ g_t = calloc(UHUD_MAXTEX, sizeof *g_t); g_ent = calloc(g_pack.count, sizeof *g_ent);
               if (!g_t || !g_ent){ fprintf(stderr, "[uhud] out of memory: off\n"); g_on = 0; return; } }
    Tex *t = &g_t[mid];
    if (t->shown >= 0 && t->ok){ t->want = -1; settle(mid); }  /* an id used again: its old picture goes */
    t->w = (uint16_t)w; t->h = (uint16_t)h; t->fmt = d3dfmt; t->want = t->shown = -1;
    /* static game textures only: managed pool, no usage flags (render
     * target, dynamic), a size and format the pack has */
    t->ok = pool == 1u && usage == 0u && texpack_may_match(&g_pack, w, h, d3dfmt);
}
void uhud_uploaded(unsigned mid, const uint8_t *data, unsigned pitch, unsigned rows){
    if (!g_on || !g_t || !mid || mid >= UHUD_MAXTEX || !data) return;
    Tex *t = &g_t[mid];
    if (!t->ok) return;
    size_t n = (size_t)pitch * rows;
    g_n_hashed++;
    t->want = texpack_find(&g_pack, data, n, t->w, t->h, t->fmt);
    settle(mid);
}
void uhud_surface_written(unsigned mid){
    if (!g_on || !g_t || !mid || mid >= UHUD_MAXTEX) return;
    Tex *t = &g_t[mid];
    if (!t->ok) return;
    t->ok = 0; t->want = -1;
    settle(mid);
}
void uhud_frame(void){
    if (!g_on || !g_t) return;
    pthread_mutex_lock(&g_rmx);
    Ready *rs = g_ready; unsigned n = g_ready_n;
    g_ready = NULL; g_ready_n = g_ready_cap = 0;
    pthread_mutex_unlock(&g_rmx);
    for (unsigned i = 0; i < n; i++){
        Ent *en = &g_ent[rs[i].ei];
        en->tex = rs[i].tex; en->st = rs[i].tex ? E_READY : E_FAILED;
        if (!rs[i].tex){ g_n_failed++;
                         fprintf(stderr, "[uhud] %s: cannot be loaded, the game's own stays\n",
                                 texpack_name(&g_pack, rs[i].ei)); }
    }
    free(rs);
    if (!n || !g_pend_n) return;
    unsigned *pend = g_pend, pn = g_pend_n;
    g_pend = NULL; g_pend_n = g_pend_cap = 0;
    for (unsigned i = 0; i < pn; i++){ g_t[pend[i]].pending = 0; settle(pend[i]); }
    free(pend);
}

/* ---- main thread ---------------------------------------------------------------- */
void uhud_main_frame(void){
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
        if (!g_uhud_tex[mid] && t) g_main_live++;
        else if (g_uhud_tex[mid] && !t) g_main_live--;
        g_uhud_tex[mid] = t;
    }
    free(ops);
    g_uhud_frame_on = g_main_live && atomic_load(&g_shown);
}

/* ---- Cmd-T: the game's own textures and the pack's, for comparing ------------------ */
@interface UHUDMenuTarget : NSObject
- (void)toggle:(NSMenuItem *)it;
@end
@implementation UHUDMenuTarget
- (void)toggle:(NSMenuItem *)it {
    int v = !atomic_load(&g_shown);
    atomic_store(&g_shown, v);
    [it setState:v ? NSControlStateValueOn : NSControlStateValueOff];
    fprintf(stderr, "[uhud] %s\n", v ? "shown" : "hidden (the game's own textures)");
}
@end
static UHUDMenuTarget *g_menu_target;
void uhud_add_menu(NSMenu *m){
    if (!on()) return;
    g_menu_target = [UHUDMenuTarget new];
    /* Cmd-T alone: a modifier pressed before Command reaches the game */
    NSMenuItem *it = [m addItemWithTitle:@"Buyuk HUD (UHUD)" action:@selector(toggle:) keyEquivalent:@"t"];
    [it setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [it setTarget:g_menu_target];
    [it setState:NSControlStateValueOn];
}
