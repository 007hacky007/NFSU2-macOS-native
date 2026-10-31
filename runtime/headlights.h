/* headlights.h -- the other cars' headlights (headlights.c) as the renderer
 * gets them: up to HEADLIGHTS_MAX lights, each a 4x4 that takes the player's
 * light coordinate to that car's (column-major) and its colour.  The lit pixel
 * shaders read the block at fragment buffer 1 (vsemu.c, metal.m). */
#ifndef NFSU2_HEADLIGHTS_H
#define NFSU2_HEADLIGHTS_H
#include <stdint.h>
#include <stddef.h>
#define HEADLIGHTS_MAX 8
typedef struct { float t[16]; float col[4]; } Headlight;
/* s, o: the lit vertex shaders' falloff (oT2.x = s * q.w + o) */
typedef struct { uint32_t n; float s, o, pad; Headlight l[HEADLIGHTS_MAX]; } HeadlightsBlock;
_Static_assert(sizeof(HeadlightsBlock) == 656 && offsetof(HeadlightsBlock, l) == 16, "HeadlightsBlock layout");
void metal_headlights(const HeadlightsBlock *block);
#endif
