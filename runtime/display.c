/* display.c - display options on top of the widescreen picture (com.c res_pick
 * and aspect_apply, wsfov.c): resolution scale, movie framing, the lens rain
 * drops' shape and the full-screen tint quads.
 *
 * The game draws for its own 4:3 mode; com.c creates the device at the
 * window's pixels and shows the game's 640x480 HUD space in the 4:3 middle of
 * a wider screen (aspfix = game aspect / device aspect < 1).  wsfov.c makes the
 * 3D view Hor+.  What that leaves:
 *
 *   resolution scale (NFSU2_RENDER=backing|panel|scale:<f>, f 0.25..2,
 *   default backing = 1:1, as before): the size of the resolution menu's
 *   "Screen" row (com.c modes_refresh) relative to the window's pixels.  panel:
 *   the physical panel's pixel density, which in a scaled display mode ("More
 *   Space") is below the backing store's (3024 panel pixels for 3600 backing
 *   pixels); never above the backing store, the window server would only scale
 *   it down again.  NFSMAXPIX bounds the size at a scale of 1 and below; a
 *   scale above 1 is chosen to go beyond it and multiplies the bounded size
 *   (bounded after the scale, 150% and 200% both came out at ~104% on a 4K
 *   screen), up to 8192 a side.
 *
 *   movie framing (NFSU2_MOVIE=fit|fill|stretch, default fit = the original
 *   game's pillarbox): the game draws a movie as one quad in HUD fractions
 *   (sub_00536860 -> sub_0051a1c0; left, top, right, bottom -0.5..0.5 are
 *   the last four pushes before the call at 0x536a42, 0x536a32 in the North
 *   American build).  Fill widens it so the movie covers the screen keeping
 *   its aspect (top and bottom cut off), stretch widens it to the screen's
 *   edges.
 *
 *   lens rain drops (always): quads in clip units around the centre [esp+10]
 *   with the extent in ST0 (the fadd at 0x5c7cf9, 0x5c7ce9 in the North
 *   American build, in sub_005c7ac0).  The same extent in x and y gave the
 *   4:3 shape at 4:3 and wider drops on a wider screen; x times aspfix keeps
 *   the original shape.
 *
 *   full-screen tint quads (always): sub_005c7150 (sub_005c7140 in the North
 *   American build) makes a surface the render target and draws one quad
 *   over all of it in HUD units (identity clip space): the rain and overcast
 *   tint of sub_005c7870 and two alpha passes of sub_005caae0.  com.c narrows
 *   such orthographic draws to the 4:3 middle like the HUD, which left
 *   untinted strips at the sides; while the function runs aspect_apply
 *   leaves them full size (display_fill_target).
 *
 * The addresses were found from the North American ones (tools/addrmap.py)
 * and checked by disassembly in both executables: the same instructions.
 *
 * Ported from th0mk's nfsu2-web runtime/widescreen.c (MIT). */
#include "cpu.h"
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

float com_aspfix(void);

enum { MOV_FIT, MOV_FILL, MOV_STRETCH };
enum { RENDER_BACKING, RENDER_PANEL, RENDER_SCALE };
static int g_init, g_movie = MOV_FIT, g_render = RENDER_BACKING;
static double g_render_f = 1.0;
static unsigned long g_movies, g_framed, g_rain, g_fills;

static void display_init(void){
    if (g_init) return;
    g_init = 1;
    const char *e = getenv("NFSU2_MOVIE");
    if (e && *e){
        if (!strcasecmp(e, "fill")) g_movie = MOV_FILL;
        else if (!strcasecmp(e, "stretch")) g_movie = MOV_STRETCH;
        else if (strcasecmp(e, "fit")) fprintf(stderr, "display: NFSU2_MOVIE=%s not understood (fit, fill or stretch)\n", e);
    }
    e = getenv("NFSU2_RENDER");
    if (e && *e && strcasecmp(e, "backing")){
        if (!strcasecmp(e, "panel")) g_render = RENDER_PANEL;
        else {
            double f = atof(!strncasecmp(e, "scale:", 6) ? e + 6 : e);
            if (f >= 0.25 && f <= 2.0){ g_render = RENDER_SCALE; g_render_f = f; }
            else fprintf(stderr, "display: NFSU2_RENDER=%s ignored (backing, panel or scale:0.25 .. scale:2)\n", e);
        }
    }
    fprintf(stderr, "display: movies %s, resolution scale ", g_movie == MOV_FILL ? "fill the screen"
            : g_movie == MOV_STRETCH ? "stretched" : "fit (original)");
    if (g_render == RENDER_SCALE) fprintf(stderr, "%.0f%% of the window's pixels\n", g_render_f * 100.0);
    else fprintf(stderr, "%s\n", g_render == RENDER_PANEL ? "the panel's pixels" : "100% (original)");
}

/* panel pixels / backing pixels of the main display (<= 1; 1 when unknown) */
static double panel_factor(void){
    CGDirectDisplayID d = CGMainDisplayID();
    CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
    if (!cur) return 1.0;
    double backing = (double)CGDisplayModeGetPixelWidth(cur);
    CGDisplayModeRelease(cur);
    size_t best = 0, native = 0;
    const void *k[] = { kCGDisplayShowDuplicateLowResolutionModes }, *v[] = { kCFBooleanTrue };
    CFDictionaryRef opt = CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(d, opt);
    if (opt) CFRelease(opt);
    if (modes){
        for (CFIndex i = 0; i < CFArrayGetCount(modes); i++){
            CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            size_t pw = CGDisplayModeGetPixelWidth(m);
            if (pw > best) best = pw;
            if ((CGDisplayModeGetIOFlags(m) & 0x02000000u) && pw > native) native = pw;   /* kDisplayModeNativeFlag */
        }
        CFRelease(modes);
    }
    size_t panel = native ? native : best;
    double f = (panel && backing > 0.0) ? (double)panel / backing : 1.0;
    return f > 1.0 ? 1.0 : f;
}

/* com.c modes_refresh: the Screen row's size relative to the window's pixels */
double display_render_factor(void){
    display_init();
    if (g_render == RENDER_SCALE) return g_render_f;
    if (g_render == RENDER_PANEL){
        static double f = 0.0;
        if (f <= 0.0){ f = panel_factor(); fprintf(stderr, "display: the panel has %.3f of the window's pixels\n", f); }
        return f;
    }
    return 1.0;
}

/* HUD squeeze com.c applies to the screen's orthographic draws: aspfix on a
 * screen wider than 4:3 (HUDFIX, on unless HUDFIX=0), otherwise none. */
static float hud_k(void){
    static int hf = -1;
    if (hf < 0){ const char *e = getenv("HUDFIX"); hf = !(e && *e == '0'); }
    float k = com_aspfix();
    return (hf && k > 0.05f && k < 0.999f) ? k : 1.f;
}

static void movie_quad(uint32_t sp){
    g_movies++;
    if (g_movie == MOV_FIT || !mem_is_committed(sp + 15u)) return;
    if (fabsf(MRF32(sp) + 0.5f) > 1e-4f || fabsf(MRF32(sp + 4u) + 0.5f) > 1e-4f ||
        fabsf(MRF32(sp + 8u) - 0.5f) > 1e-4f || fabsf(MRF32(sp + 12u) - 0.5f) > 1e-4f){
        static int shown;
        if (shown++ < 4) fprintf(stderr, "display: a movie quad of another shape left as it is (%.3f %.3f %.3f %.3f)\n",
                                 (double)MRF32(sp), (double)MRF32(sp + 4u), (double)MRF32(sp + 8u), (double)MRF32(sp + 12u));
        return;
    }
    float k = hud_k();
    if (k >= 1.f) return;                    /* 4:3 or narrower: the movie fills the screen already */
    float hx = 0.5f / k, hy = g_movie == MOV_FILL ? 0.5f / k : 0.5f;
    MRF32(sp) = -hx; MRF32(sp + 4u) = -hy; MRF32(sp + 8u) = hx; MRF32(sp + 12u) = hy;
    if (g_framed++ < 2)
        fprintf(stderr, "display: movie quad %s to %.3f x %.3f HUD widths (aspfix %.4f)\n",
                g_movie == MOV_FILL ? "filled" : "stretched", (double)(2.f * hx), (double)(2.f * hy), (double)k);
}

/* sub_005c7150(surface, texture, colour, ?, src blend, dest blend, flag) */
static int g_fill;
void sub_005c7150_orig(CPU *c);
void sub_005c7150(CPU *c){
    g_fills++;
    g_fill++;
    sub_005c7150_orig(c);
    g_fill--;
}
/* com.c aspect_apply: an orthographic draw over the whole target right now */
int display_fill_target(void){ return g_fill > 0; }

/* Called from guest_hook (debug.c) BEFORE the instruction at ip runs; the
 * lifter writes the x87 region back first, so ST(0) is the live value. */
int display_hook(CPU *c, uint32_t ip){
    switch (ip){
    case HOOK_SITE(0x00536a42u):                    /* mov ecx, ebx; call sub_0051a1c0 (the movie quad) */
        display_init();
        movie_quad(c->esp);
        return 1;
    case HOOK_SITE(0x005c7cf9u):                    /* fadd [esp+10]: centre + the rain drop's extent */
        g_rain++;
        ST(0) *= (double)hud_k();
        return 1;
    }
    return 0;
}

void display_report(void){
    display_init();
    fprintf(stderr, "  display          : movie quads %lu (reframed %lu), rain drops %lu, full-screen tints %lu\n",
            g_movies, g_framed, g_rain, g_fills);
}
