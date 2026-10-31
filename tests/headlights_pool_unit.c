/* headlights_pool_unit.c -- the per-frame pool of the other cars' headlight
 * sets in runtime/metal.m (HL_POOL, hl_pool_reset, hl_pool_put): a set the
 * frame already holds is reused, every draw keeps the set it saw, block 0 is
 * "no light", a full pool gives 0, a reset empties it.  The pool lives inside
 * metal.m, so tests/headlights_native.sh cuts that part out of metal.m into
 * HLPOOL_SRC (from "#define HL_POOL" to metal_headlights) and this file
 * includes it, so the test follows the code the renderer runs. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "headlights.h"
#include HLPOOL_SRC
int main(void){
    static HLPool frames[2];
    HeadlightsBlock light = { .n = 1, .s = 1 };
    hl_pool_reset(&frames[0]); hl_pool_reset(&frames[1]);
    unsigned first = hl_pool_put(&frames[0], &light); assert(first == 1);
    assert(hl_pool_put(&frames[0], &light) == first);                 /* the same set: reused */
    light.l[0].col[0] = 0.75f;
    unsigned next = hl_pool_put(&frames[0], &light); assert(next == 2);
    assert(frames[0].block[first].l[0].col[0] == 0 && frames[0].block[next].l[0].col[0] == 0.75f);
    assert(frames[1].count == 1 && !frames[1].block[0].n);            /* the other frame untouched */
    for (unsigned i = 3; i < HL_POOL; i++){ light.s = (float)i; assert(hl_pool_put(&frames[0], &light) == i); }
    light.s = 100; assert(hl_pool_put(&frames[0], &light) == 0);      /* full: no light, not a wrong one */
    assert(!frames[0].block[0].n);
    assert(hl_pool_put(&frames[0], &frames[0].block[first]) == first);
    light.n = 0; assert(!hl_pool_put(&frames[0], &light));            /* no lights: block 0 */
    light.n = HEADLIGHTS_MAX + 1; assert(!hl_pool_put(&frames[0], &light));
    hl_pool_reset(&frames[0]); assert(frames[0].count == 1 && !frames[0].block[0].n);
    static HLPool zero; light.n = 1; assert(hl_pool_put(&zero, &light) == 1);   /* never reset: resets itself */
    puts("headlights_pool_unit: per-frame sets, reuse, immutable draws, overflow, bounds and reset passed");
    return 0;
}
