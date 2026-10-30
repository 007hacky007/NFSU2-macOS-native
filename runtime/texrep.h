/* texrep.h -- texture packs drawn in place of the game's textures (runtime/texrep.m):
 * the launcher's Texture Packs (TexMod, TexWizard and texture mods made into NTXP packs)
 * and LunicAura106's Upscaled HUD (UHUD).
 *
 * Off by default.  Without NFSU2_TEXPACKS or NFSU2_UHUD=on every guest hook returns
 * at its first line and the draw encoder binds the game's own textures only. */
#ifndef TEXREP_H
#define TEXREP_H
#include <stdint.h>

#define TEXREP_MAXTEX 65536u      /* = metal.m MAXTEX */

/* ---- guest thread (com.c) -------------------------------------------- */
/* CreateTexture of a texture that is not a render target; name: the game's name
 * hash of the texture when the game's texture loader creates it, otherwise 0 */
void texrep_created(unsigned mid, unsigned w, unsigned h, unsigned d3dfmt, unsigned usage,
                    unsigned pool, uint32_t name);
/* UnlockRect of level 0 of a 2D texture (after metal_upload_texture) */
void texrep_uploaded(unsigned mid, const uint8_t *data, unsigned pitch, unsigned rows);
/* written through one of its surfaces (the car skin composite): never a pack's */
void texrep_surface_written(unsigned mid);
/* once per Present, before metal_present */
void texrep_frame(void);

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
/* ---- main thread (metal.m) ---------------------------------------------- */
extern int g_texrep_frame_on;                     /* bind replacements this frame */
extern __strong id<MTLTexture> g_texrep_tex[TEXREP_MAXTEX];
void texrep_main_frame(void);                     /* start of every frame's encode */
void texrep_add_menu(NSMenu *m);                  /* Cmd-T, only while a pack is in use */
/* the texture to sample for id_: a pack's, if one replaces it */
static inline id<MTLTexture> texrep_pick(unsigned id_, id<MTLTexture> orig){
    if (__builtin_expect(g_texrep_frame_on, 0) && id_ < TEXREP_MAXTEX && g_texrep_tex[id_]) return g_texrep_tex[id_];
    return orig;
}
#endif
#endif
