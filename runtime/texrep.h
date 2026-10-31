/* texrep.h -- texture packs drawn in place of the game's textures (runtime/texrep.m):
 * the launcher's Texture Packs (TexMod, TexWizard and texture mods made into NTXP packs),
 * LunicAura106's Upscaled HUD (UHUD), and the upscaled texture pack (a folder of DDS
 * files the launcher makes from the player's own game files).
 *
 * Off by default.  Without NFSU2_TEXPACKS, NFSU2_UHUD=on, NFSU2_TEXTURES=upscaled or
 * NFSU2_TEXDUMP every guest hook returns at its first line and the draw encoder binds
 * the game's own textures only. */
#ifndef TEXREP_H
#define TEXREP_H
#include <stdint.h>

#define TEXREP_MAXTEX 65536u      /* = metal.m MAXTEX */

/* ---- guest thread (com.c, fileio.c) ------------------------------------ */
/* CreateTexture of a texture that is not a render target; levels: its Metal level
 * count; name: the game's name hash of the texture when the game's texture loader
 * creates it, otherwise 0 */
void texrep_created(unsigned mid, unsigned w, unsigned h, unsigned levels, unsigned d3dfmt,
                    unsigned usage, unsigned pool, uint32_t name);
/* UnlockRect of a level of a 2D texture (after metal_upload_texture) */
void texrep_uploaded(unsigned mid, unsigned level, const uint8_t *data, unsigned pitch, unsigned rows);
/* written through one of its surfaces (the car skin composite): never a pack's */
void texrep_surface_written(unsigned mid);
/* the last reference to the texture went (com.c obj_release) */
void texrep_released(unsigned mid);
/* once per Present, before metal_present */
void texrep_frame(void);
/* ReadFile of a game file (a texture's part for the texture collecting, movie frames) */
void texrep_note_read(const char *path);
/* the end of the run (com.c com_report) */
void texrep_report(void);

/* ---- any thread --------------------------------------------------------- */
int  texrep_wanted(void);         /* NFSU2_TEXTURES = upscaled */
void texrep_set_shown(int on);    /* -1 = toggle (Cmd-T) */
int  texrep_shown(void);

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
/* ---- main thread (metal.m) ---------------------------------------------- */
extern int g_texrep_frame_on;                     /* bind replacements this frame */
extern __strong id<MTLTexture> g_texrep_tex[TEXREP_MAXTEX];
extern uint8_t g_texrep_k[TEXREP_MAXTEX];         /* log2(scale): DDS pack levels above the original */
/* start of every frame's encode: what the guest thread published (and the game's own
 * levels copied under a stacked replacement, on q) */
void texrep_main_frame(id<MTLCommandQueue> q);
void texrep_add_menu(NSMenu *m);                  /* Cmd-T, only while a pack is in use */
unsigned texrep_skey_slow(unsigned sk, unsigned k);
/* the texture to sample for id_: a pack's, if one replaces it */
static inline id<MTLTexture> texrep_pick(unsigned id_, id<MTLTexture> orig){
    if (__builtin_expect(g_texrep_frame_on, 0) && id_ < TEXREP_MAXTEX && g_texrep_tex[id_]) return g_texrep_tex[id_];
    return orig;
}
/* sampler key for a stage whose texture is id_ (texrep_skey_slow) */
static inline unsigned texrep_skey(unsigned id_, unsigned sk){
    if (__builtin_expect(g_texrep_frame_on, 0) && id_ && id_ < TEXREP_MAXTEX && g_texrep_tex[id_])
        return texrep_skey_slow(sk, g_texrep_k[id_]);
    return sk;
}
#endif
#endif
