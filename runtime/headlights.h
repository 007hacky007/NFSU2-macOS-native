#ifndef NFSU2_HEADLIGHTS_H
#define NFSU2_HEADLIGHTS_H
#include <stdint.h>
#include <stddef.h>
#define HEADLIGHTS_MAX 8
/* Matches the donor's GwHL block; matrices are column-major. */
typedef struct { float t[16]; float col[4]; } Headlight;
typedef struct { uint32_t n; float s, o, pad; Headlight l[HEADLIGHTS_MAX]; } HeadlightsBlock;
_Static_assert(sizeof(HeadlightsBlock) == 656 && offsetof(HeadlightsBlock, l) == 16, "HeadlightsBlock layout");
void metal_headlights(const HeadlightsBlock *block);
#endif
