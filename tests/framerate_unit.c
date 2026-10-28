/* Exercise frame-rate selection against real game cap values without a GPU. */
#include "../runtime/framerate.c"
#include <assert.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
int metal_display_hz(void){ return 120; }

int main(int argc, char **argv){
    assert(argc == 3);
    int mode = atoi(argv[1]), intro = atoi(argv[2]);
    g_mem = calloc(1, 0x1000000u);
    assert(g_mem);
    assert(hfr_mode_rate() == mode);
    MRF32(A_CAP_DEF) = 1.f / 120.f;
    MRF32(A_CAP) = 1.f / 30.f;
    int got = content_rate();
    if (got != intro){ fprintf(stderr, "FAIL cutscene cap: got %d, expected %d\n", got, intro); return 1; }
    assert(MRF32(A_CAP) == 1.f / 30.f);  /* leave the game's request intact */
    MRF32(A_CAP) = MRF32(A_CAP_DEF);
    assert(content_rate() == mode);   /* gameplay resumes at its selected rate */
    MRF32(A_CAP) = 1.f / 24.f;
    assert(content_rate() == 24);     /* no blanket override of other cap requests */
    free(g_mem);
    puts("PASS cutscene and gameplay rate selection");
    return 0;
}
