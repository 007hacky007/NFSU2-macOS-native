/* The common vertex format between com.c (guest side) and metal.m (draw side).
 * Since the vertex shader runs on the CPU, the positions arriving here are in
 * CLIP SPACE; the rasterizer does the perspective divide. */
#ifndef GFX_H
#define GFX_H
/* CAUTION: texture coordinates carry FOUR components per stage.
 * Previously only .xy was carried; but the game's vertex shaders produce
 * PROJECTIVE coordinates (measured: oT1.x/y/z = dot(v0, c4..c6),
 * oT1.w = r0.x).  With z/w dropped, road/car reflections came out striped
 * and dark. */
typedef struct {
    float x, y, z, w;      /* clip space */
    float r, g, b, a;      /* oD0 - diffuse */
    float r1,g1,b1,a1;     /* oD1 - specular */
    float t[4][4];         /* oT0..oT3, all four components */
} TVert;

void metal_draw_tv(const TVert *tv, unsigned nverts, unsigned prim, unsigned tex);
#endif
