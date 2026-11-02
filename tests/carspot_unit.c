/* carspot_unit.c - the career's kept spot (runtime/carspot.c) without the
 * game (tests/carspot_unit.sh): a good spot is left, a NaN, infinite or
 * far-off one becomes the new career's start. */
#include "../runtime/carspot.c"
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
long autotest_frame(void){ return 7; }

static int fails;
#define CHECK(c, ...) do { if (c) printf("PASS "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); putchar('\n'); } while (0)

static void spot(float x, float y, float z){ MRF32(G_CAREER + C_SPOT) = x; MRF32(G_CAREER + C_SPOT + 4u) = y; MRF32(G_CAREER + C_SPOT + 8u) = z; MR16(G_CAREER + C_SPOT_HEADING) = 0x1234u; }
static int at_start(void){ for (int i = 0; i < 3; i++) if (MRF32(G_CAREER + C_SPOT + 4u * (uint32_t)i) != START[i]) return 0; return MR16(G_CAREER + C_SPOT_HEADING) == START_HEADING; }

int main(void){
    g_mem = calloc(1, 0x01000000u); assert(g_mem);
    spot(120.5f, -300.f, 12.f); carspot_frame();
    CHECK(MRF32(G_CAREER + C_SPOT) == 120.5f && MR16(G_CAREER + C_SPOT_HEADING) == 0x1234u, "a spot on the map is left as it is");
    spot(NAN, 1.f, 2.f); carspot_frame();
    CHECK(at_start(), "a NaN spot becomes the new career's start");
    spot(1.f, INFINITY, 2.f); carspot_frame();
    CHECK(at_start(), "an infinite spot becomes the new career's start");
    spot(1.f, 2.f, 250000.f); carspot_frame();
    CHECK(at_start(), "a spot far off the map becomes the new career's start");
    printf(fails ? "carspot_unit: %d FAILED\n" : "carspot_unit: all passed\n", fails);
    return fails != 0;
}
