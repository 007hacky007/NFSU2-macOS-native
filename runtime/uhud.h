/* uhud.h -- LunicAura106's Upscaled HUD (UHUD) as a texture pack: the menus,
 * HUD, fonts, icons and logos at four times their size (runtime/uhud.m).
 *
 * Off by default.  Without NFSU2_UHUD=on every guest hook returns at its
 * first line and the draw encoder binds the game's own textures only. */
#ifndef UHUD_H
#define UHUD_H
#include <stdint.h>

#define UHUD_MAXTEX 65536u        /* = metal.m MAXTEX */

/* ---- guest thread (com.c) -------------------------------------------- */
/* CreateTexture of a texture that is not a render target */
void uhud_created(unsigned mid, unsigned w, unsigned h, unsigned d3dfmt, unsigned usage, unsigned pool);
/* UnlockRect of level 0 of a 2D texture (after metal_upload_texture) */
void uhud_uploaded(unsigned mid, const uint8_t *data, unsigned pitch, unsigned rows);
/* written through one of its surfaces (the car skin composite): never the pack's */
void uhud_surface_written(unsigned mid);
/* once per Present, before metal_present */
void uhud_frame(void);

#ifdef __OBJC__
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
/* ---- main thread (metal.m) ---------------------------------------------- */
extern int g_uhud_frame_on;                       /* bind replacements this frame */
extern __strong id<MTLTexture> g_uhud_tex[UHUD_MAXTEX];
void uhud_main_frame(void);                       /* start of every frame's encode */
void uhud_add_menu(NSMenu *m);                    /* Cmd-T, only while the pack is in use */
/* the texture to sample for id_: the pack's, if it has one */
static inline id<MTLTexture> uhud_pick(unsigned id_, id<MTLTexture> orig){
    if (__builtin_expect(g_uhud_frame_on, 0) && id_ < UHUD_MAXTEX && g_uhud_tex[id_]) return g_uhud_tex[id_];
    return orig;
}
#endif
#endif
