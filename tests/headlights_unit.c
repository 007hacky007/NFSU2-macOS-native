/* headlights_unit.c -- the other cars' headlights (runtime/headlights.c)
 * without the game: which cars get a light in each mode (players, all, off,
 * self), the exclusions (headlights switched off, a car blinked out, a car
 * out of reach, traffic in a network race), the nearest eight, the projector
 * transform and the light colour.  The file is included so each case can
 * start from an unread NFSU2_HEADLIGHTS.  Built for both game versions
 * (tests/headlights_native.sh): the addresses go through GA(). */
#include "../runtime/headlights.c"
#include <assert.h>
#include <math.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
static HeadlightsBlock block;
static int original_calls;
void metal_headlights(const HeadlightsBlock *value){ block = *value; }
void sub_005d6d30_orig(CPU *c){ (void)c; original_calls++; }

static void car(uint32_t at, uint32_t next, int driver, uint32_t color, float x){
    MR32(at) = next; MR32(at + CAR_DRIVER) = (uint32_t)driver; MRF32(at + CAR_POS) = x;
    for (int i = 0; i < 3; i++) MRF32(at + CAR_ROT + i * 20) = 1;
    MR8(at + CAR_ACTIVE) = 1; MR32(at + CAR_RENDER) = at + 0x1000;
    MR32(at + 0x1000 + 0x380) = color;
}
/* a mode as if NFSU2_HEADLIGHTS had it at the start */
static void mode(const char *m){
    if (m) setenv("NFSU2_HEADLIGHTS", m, 1); else unsetenv("NFSU2_HEADLIGHTS");
    g_mode = -1; g_gain = 0.6f;
}
int main(void){
    g_mem = calloc(1, 16 * 1024 * 1024); assert(g_mem);
    memset(g_cbits, 255, sizeof g_cbits);
    CPU cpu = {0}; cpu.esp = 0x1000; cpu.ecx = 0x12000;
    MR32(cpu.esp + 4) = VIEW9; MR32(cpu.esp + 8) = LIT_CB;
    MR32(G_PLAYERS) = 0x10000; MR32(0x10004) = 0x20000;          /* player 1's car */
    MR32(G_WORLD) = 0x11000; MR32(0x11000) = 0x20000;            /* the World's car list */
    MR32(HL_ENABLE) = 1;
    car(0x20000, 0x21000, 1, 0xffffff, 0);                       /* the player */
    car(0x21000, 0x23000, 3, 0x0000ff, 2);                       /* an AI racer, red */
    car(0x23000, 0x11000, 4, 0x00ff00, 4);                       /* traffic, green */
    float plat[48] = {0}; for (int i = 0; i < 4; i++) plat[32 + 5 * i] = 1;
    headlights_view(9, plat); headlights_vs_ramp(0.01f, 0.25f);

    /* players (the default): nobody outside a network race */
    mode(0); sub_005d6d30(&cpu); assert(block.n == 0);
    /* a LAN race: every car but traffic */
    MR32(G_GAMEMODE) = 0x200;
    mode("players"); sub_005d6d30(&cpu);
    assert(block.n == 1 && fabsf(block.l[0].col[0] - 0.6f) < 1e-6f && block.l[0].col[1] == 0);
    assert(block.s == 0.01f && block.o == 0.25f);
    assert(block.l[0].t[3] == -2 && block.l[0].t[0] == 1);         /* car 2 m ahead in x */
    MR32(G_GAMEMODE) = 0;
    /* all: AI racers and traffic too, nearest first */
    mode("all"); sub_005d6d30(&cpu);
    assert(block.n == 2 && block.l[0].col[0] > 0.59f && block.l[1].col[1] > 0.59f);
    /* MODE:GAIN */
    mode("all:1"); sub_005d6d30(&cpu); assert(block.n == 2 && fabsf(block.l[0].col[0] - 1.f) < 1e-6f);
    /* self: the player's own light once more */
    mode("self"); sub_005d6d30(&cpu); assert(block.n == 1 && block.l[0].t[3] == 0 && block.l[0].col[0] > 0.59f);
    /* off */
    mode("off"); sub_005d6d30(&cpu); assert(block.n == 0);
    /* an unknown word is the default */
    mode("bogus"); sub_005d6d30(&cpu); assert(g_mode == HL_PLAYERS && block.n == 0);
    /* the game's headlights off: no lights */
    mode("all"); MR32(HL_ENABLE) = 0; sub_005d6d30(&cpu); assert(block.n == 0);
    MR32(HL_ENABLE) = 1;
    /* a blinked-out car is skipped */
    MR8(0x21000 + CAR_BLINKOUT) = 1;
    sub_005d6d30(&cpu); assert(block.n == 1 && block.l[0].col[1] > 0.59f);
    MR8(0x21000 + CAR_BLINKOUT) = 0;
    /* out of reach (160 m) */
    MRF32(0x21000 + CAR_POS) = 200;
    sub_005d6d30(&cpu); assert(block.n == 1 && block.l[0].col[1] > 0.59f);
    MRF32(0x21000 + CAR_POS) = 2;
    /* another view or another callback: the original only */
    int before = original_calls;
    MR32(cpu.esp + 8) = LIT_CB + 0x10; block.n = 99;
    sub_005d6d30(&cpu); assert(original_calls == before + 1 && block.n == 99);
    MR32(cpu.esp + 8) = LIT_CB;
    /* the nearest eight of twelve */
    MR32(0x11000) = 0x40000;
    for (unsigned i = 0; i < 12; i++){
        uint32_t at = 0x40000 + 0x2000 * i;
        car(at, i == 11 ? 0x11000 : at + 0x2000, 3, 0xffffff, (float)(12 - i));
    }
    MR32(0x40000 + 0x2000 * 11) = 0x20000;                       /* ... then the player, then the end */
    MR32(0x20000) = 0x11000;
    mode("all"); sub_005d6d30(&cpu); assert(block.n == HEADLIGHTS_MAX);
    assert(block.l[0].t[3] == -1 && block.l[7].t[3] == -8);
    /* no view 9 matrices yet: no lights */
    g_have_vp9 = 0; sub_005d6d30(&cpu); assert(block.n == 0);

    free(g_mem);
#ifdef NFS_EXE_NA
    printf("headlights_unit (North American addresses): ");
#else
    printf("headlights_unit (European addresses): ");
#endif
    puts("players/all/off/self and gain, disabled/blink/reach exclusions, "
         "other views untouched, nearest eight and projector transform passed");
    return 0;
}
