/* framerate_unit.c - frame-rate choices without a game or a GPU (tests/framerate.sh).
 *   framerate_unit <mode rate> <cutscene rate>
 * checks the rate for the mode (NFSU2_FPS, NFSU2_DISPLAY_HZ), the rate in a
 * cutscene (the game asks for 1/30; NFSU2_CUTSCENES_60), that the game's
 * request is left as it is, and the particle step at the call site.
 *   framerate_unit uncapped    NFSU2_FPS=uncapped: no rate, every fix, mailbox
 *   framerate_unit net <race rate> <ticks/timer on>
 *                              a network race (NFSU2_LAN_TIMING): the rate,
 *                              the clock fixes, and the World constructor's
 *                              30 fps request undone */
#include "../runtime/framerate.c"
#include <assert.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
int metal_display_hz(void){ return 120; }
void guest_sleep_ns(long ns){ (void)ns; }
uint64_t spin_slept_us(void){ return 0; }
long metal_frames(void){ return 0; }
void sub_005ff4a0_orig(CPU *c){ (void)c; MRF32(A_CAP) = 1.f / 30.f; }   /* the World constructor of a network race */

#define CHECK(c, ...) do { if (!(c)){ fprintf(stderr, "FAIL line %d: ", __LINE__); \
    fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); return 1; } } while (0)

/* the particle hook at the call site: [esp] = the step the game pushed */
static float particle_step(float realdt){
    CPU c; memset(&c, 0, sizeof c);
    c.esp = 0x00100000u; c.ecx = A_PART_SYS;
    MRF32(c.esp) = 1.f / 60.f;
    MRF32(A_REALDT) = realdt;
    assert(hfr_hook(&c, 0x005d2c27u) == 1);
    return MRF32(c.esp);
}

static int uncapped(void){
    g_mem = calloc(1, 0x1000000u); assert(g_mem);
    MRF32(A_CAP_DEF) = 1.f / 120.f; MRF32(A_CAP) = 1.f / 120.f;
    resolve();
    CHECK(hfr_uncapped() && mode_rate() == 0, "uncapped: mode rate %d", mode_rate());
    fixes_follow_rate();
    CHECK(g_fix == FX_ALL, "uncapped: fixes 0x%x, expected all", g_fix);
    atomic_store(&g_rate_now, 0);
    CHECK(hfr_mailbox() == 1, "uncapped: no mailbox");
    CHECK(hfr_vclock_floor_us() == 500u, "uncapped: virtual clock floor %llu", (unsigned long long)hfr_vclock_floor_us());
    CHECK(hfr_present_min_duration() == 0.0, "uncapped: a present minimum duration");
    printf("PASS uncapped: no rate, fixes 0x%x, mailbox\n", g_fix);
    return 0;
}
static int net(int want_rate, int clocks){
    g_mem = calloc(1, 0x1000000u); assert(g_mem);
    MRF32(A_CAP_DEF) = 1.f / 120.f; MRF32(A_CAP) = 1.f / 120.f;
    resolve();
    fixes_follow_rate();
    int before = g_fix, mr = mode_rate();
    MR8(A_ONLINE) = 1;                                 /* World::IsOnline */
    CHECK(content_rate() == want_rate, "network race rate %d, expected %d", content_rate(), want_rate);
    fixes_follow_rate();
    int clk = (g_fix & (FX_TICKS | FX_TIMER)) != 0;
    CHECK(clk == clocks, "network race: ticks/timer %s (fixes 0x%x)", clk ? "on" : "off", g_fix);
    CPU c; memset(&c, 0, sizeof c);
    MRF32(A_CAP) = 1.f / 120.f;
    sub_005ff4a0(&c);
    CHECK(MRF32(A_CAP) == 1.f / 120.f, "the World constructor's 30 fps request stayed (%g)", MRF32(A_CAP));
    MR8(A_ONLINE) = 0;
    fixes_follow_rate();
    CHECK(g_fix == before && content_rate() == mr, "after the network race: fixes 0x%x, rate %d", g_fix, content_rate());
    printf("PASS network race at mode %d: rate %d, ticks/timer %s, 30 fps request undone\n", mr, want_rate, clk ? "on" : "off");
    return 0;
}

int main(int argc, char **argv){
    if (argc == 2 && !strcmp(argv[1], "uncapped")) return uncapped();
    if (argc == 4 && !strcmp(argv[1], "net")) return net(atoi(argv[2]), atoi(argv[3]));
    if (argc != 3){ fprintf(stderr, "usage: framerate_unit <mode rate> <cutscene rate>\n"); return 2; }
    int mode = atoi(argv[1]), intro = atoi(argv[2]);
    g_mem = calloc(1, 0x1000000u);
    assert(g_mem);
    MRF32(A_CAP_DEF) = 1.f / 120.f;
    MRF32(A_CAP) = 1.f / 120.f;
    resolve();
    CHECK(mode_rate() == mode, "mode rate %d, expected %d", mode_rate(), mode);
    CHECK(content_rate() == mode, "race rate %d, expected %d", content_rate(), mode);
    MRF32(A_CAP) = 1.f / 30.f;                      /* a race intro asks for 30 */
    int got = content_rate();
    CHECK(got == intro, "cutscene rate %d, expected %d", got, intro);
    CHECK(MRF32(A_CAP) == 1.f / 30.f, "the game's request was changed");
    MRF32(A_CAP) = 1.f / 24.f;
    CHECK(content_rate() == (mode < 24 ? mode : 24), "a 24 fps request is not kept");
    MRF32(A_CAP) = MRF32(A_CAP_DEF);
    CHECK(content_rate() == mode, "the race does not go back to %d", mode);

    /* the fix set: none at 60 (the original), all above, the 30 set at 30 */
    fixes_follow_rate();
    int want = g_mode == M_OFF ? 0 : mode > 60 ? FX_ALL : mode == 30 ? FX_30 : 0;
    CHECK(g_fix == want, "fixes 0x%x, expected 0x%x", g_fix, want);
    /* the tick base follows the ticks fix */
    CHECK((MRF32(A_TICK_HZ) == 3600.f) == !!(g_fix & FX_TICKS), "tick base %g", MRF32(A_TICK_HZ));

    /* particles: real dt up to 1/60 (1/30 at 30 fps), the game's step otherwise */
    float s = particle_step(1.f / mode);
    float expect = (g_fix & FX_PARTICLES) ? 1.f / mode : 1.f / 60.f;
    CHECK(fabsf(s - expect) < 1e-6f, "particle step %g at %d fps, expected %g", s, mode, expect);
    s = particle_step(0.1f);
    expect = (g_fix & FX_PARTICLES) && mode == 30 ? 1.f / 30.f : 1.f / 60.f;
    CHECK(fabsf(s - expect) < 1e-6f, "particle step %g after a long frame, expected %g", s, expect);

    /* presenting: frames above the screen's rate replace each other */
    int hz = display_hz();
    atomic_store(&g_rate_now, mode);
    CHECK(hfr_mailbox() == (mode > hz + 1), "mailbox %d at %d fps on %d Hz", hfr_mailbox(), mode, hz);
    double md = hfr_present_min_duration(), mdw = 1.0 / mode - 0.5 / hz;
    CHECK(fabs(md - (mdw > 0.0005 ? mdw : 0.0)) < 1e-9, "present min duration %g at %d fps", md, mode);
    CHECK(hfr_vclock_floor_us() == (mode > 200 ? 1000u : 4000u), "virtual clock floor %llu",
          (unsigned long long)hfr_vclock_floor_us());
    free(g_mem);
    printf("PASS rate %d, cutscenes %d, fixes 0x%x\n", mode, intro, g_fix);
    return 0;
}
