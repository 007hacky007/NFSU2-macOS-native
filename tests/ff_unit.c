/* ff_unit.c -- runtime/dinput_ff.c without the game (tests/ff_unit.sh): the
 * DirectInput calls SPEED2.EXE makes on a force-feedback pad, replayed into
 * the effect objects and the mixer, and the motor levels that come out.
 *
 * The race sequence is the one NFSU2_FF_LOG shows in a quick race with the
 * synthetic pad (tests/input/pad_rumble.seq), the same on the European and
 * the North American SPEED2.EXE: device gain 10000, actuators on, a damper
 * (7055) and a silent sine created and started at the start; in the race a
 * 50 ms square or sine whose magnitude SetParameters changes every frame
 * (flags 0x140: type-specific parameters and an all-zero envelope), Unload +
 * CreateEffect when the kind changes, a full-strength spring after hard
 * steering, Stop of the vibration and the damper in the pause menu and Start
 * again after it.  Then the rules of the mix itself (periods, constant and
 * ramp forces, durations and iterations, start delay, envelope, gains,
 * SOLO, the device commands), the slot reuse after 64 changes, the car's
 * jolts and the world standing still.
 * Exit status 0 when every check passes. */
#include "cpu.h"
#include "gamepad.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <sys/mman.h>

uint8_t *g_mem;
uint8_t  g_cbits[1u << 15] = {0};
void mem_commit(uint32_t a, uint32_t n){ (void)a; (void)n; }

/* runtime/dinput_ff.c */
int      dipad_ff_on(void);
void     dipad_ff_frame(void);
uint32_t dipad_ff_prop(int set, uint32_t prop, uint32_t h);
int64_t  dipad_ff_dev_call(CPU *c, const char *nm, const uint32_t *a);
uint32_t dipad_effect_call(CPU *c, uint32_t self, const char *nm, int nargs, const uint32_t *a);
void     dipad_effect_ref(uint32_t obj, int add);
void     dipad_ff_test_clock(double (*now)(void));
void     dipad_ff_test_reset(int on);
void     dipad_ff_levels(float out[2]);

/* ---- what dinput_ff.c needs from the rest of the runtime ---- */
static uint32_t g_bump = 0x30000000u;               /* com.c's objects */
uint32_t com_new_dieffect(void){ uint32_t o = g_bump; g_bump += 0x20u; MR32(o) = 0xE0110000u; return o; }
uint32_t com_scratch(uint32_t n){ uint32_t p = g_bump; g_bump += (n + 15u) & ~15u; return p; }
static int g_enum_n, g_enum_types[16];
uint32_t call_guest(CPU *c, uint32_t fn, int nargs, const uint32_t *args){
    (void)c; (void)fn; (void)nargs;
    if (g_enum_n < 16) g_enum_types[g_enum_n] = (int)(MR32(args[0] + 0x14) & 0xFFu);
    g_enum_n++;
    return 1;                                         /* DIENUM_CONTINUE */
}
int gamepad_env_flag(const char *nm, int dflt){
    const char *e = getenv(nm);
    return e && *e ? atoi(e) != 0 : dflt;
}
static float g_motor[2] = {-1, -1}; static int g_calls;
void gamepad_rumble(float s, float w){ g_motor[0] = s; g_motor[1] = w; g_calls++; }

static double g_t = 100.0;
static double fake_now(void){ return g_t; }

static int g_fail;
static void check(const char *what, int ok){
    printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) g_fail++;
}
static int near(float a, float b){ return fabsf(a - b) < 0.002f; }
static int levels(float s, float w){
    dipad_ff_frame();
    return near(g_motor[0], s) && near(g_motor[1], w);
}
static char g_lv[64];
static const char *lv(void){ snprintf(g_lv, sizeof g_lv, "(strong %.3f weak %.3f)", (double)g_motor[0], (double)g_motor[1]); return g_lv; }
#define CHECKL(what, s, w) do { int ok_ = levels(s, w); char m_[160]; snprintf(m_, sizeof m_, "%s %s", what, lv()); check(m_, ok_); } while (0)

/* ---- guest structures ---- */
#define GUIDS 0x00100000u                             /* GUID_ConstantForce ... GUID_Friction */
#define DIEFF 0x00101000u
#define TPAR  0x00101100u
#define ENVL  0x00101200u
#define OUTP  0x00101300u
#define PROPH 0x00101400u
enum { CONST = 0x20, RAMP, SQUARE, SINE, TRIANGLE, SAWUP, SAWDOWN, SPRING, DAMPER };
static uint32_t guid(int k){
    static const uint8_t d4[8] = {0x9A, 0xD0, 0x00, 0xA0, 0xC9, 0xA0, 0x6E, 0x35};
    uint32_t g = GUIDS + 16u * (uint32_t)(k - CONST);
    MR32(g) = 0x13541C00u | (uint32_t)k; MR16(g + 4) = 0x8E33; MR16(g + 6) = 0x11D0;
    memcpy(g_mem + g + 8, d4, 8);
    return g;
}
/* DIEFFECT (DirectX 6+, 0x44 bytes) with type-specific parameters: periodic
 * (magnitude, offset, period), constant (magnitude), ramp (start, end),
 * condition (offset, coefficient) */
static uint32_t dieffect(int k, int32_t mag, int32_t off, uint32_t period_us, uint32_t dur_us, uint32_t gain, int env){
    memset(g_mem + DIEFF, 0, 0x300);
    MR32(DIEFF) = 0x44u; MR32(DIEFF + 4) = 0x12u;      /* DIEFF_CARTESIAN | DIEFF_OBJECTOFFSETS */
    MR32(DIEFF + 8) = dur_us; MR32(DIEFF + 0x10) = gain;
    MR32(DIEFF + 0x14) = 0xFFFFFFFFu;                 /* DIEB_NOTRIGGER */
    MR32(DIEFF + 0x28) = env ? ENVL : 0u;             /* the game's: all zero */
    MR32(ENVL) = 0x14u;
    MR32(DIEFF + 0x30) = TPAR;
    if (k >= SQUARE && k <= SAWDOWN){ MR32(DIEFF + 0x2c) = 16u; MR32(TPAR) = (uint32_t)mag; MR32(TPAR + 4) = (uint32_t)off; MR32(TPAR + 12) = period_us; }
    else if (k == CONST){ MR32(DIEFF + 0x2c) = 4u; MR32(TPAR) = (uint32_t)mag; }
    else if (k == RAMP){ MR32(DIEFF + 0x2c) = 8u; MR32(TPAR) = (uint32_t)off; MR32(TPAR + 4) = (uint32_t)mag; }
    else { MR32(DIEFF + 0x2c) = 24u; MR32(TPAR) = (uint32_t)off; MR32(TPAR + 4) = (uint32_t)mag; MR32(TPAR + 8) = (uint32_t)mag; }
    return DIEFF;
}
static int64_t dev(const char *nm, uint32_t a1, uint32_t a2, uint32_t a3){
    uint32_t a[5] = { 0x40000000u, a1, a2, a3, 0 };
    return dipad_ff_dev_call(0, nm, a);
}
static uint32_t create(int k, int32_t mag, uint32_t period_us){
    uint32_t pp = OUTP;
    MR32(pp) = 0xDEADBEEFu;
    int64_t r = dev("CreateEffect", guid(k), dieffect(k, mag, 0, period_us, 0xFFFFFFFFu, 10000u, k >= SQUARE && k <= SAWDOWN), pp);
    return r == 0 ? MR32(pp) : 0u;
}
static uint32_t eff(uint32_t o, const char *nm, uint32_t a1, uint32_t a2){
    uint32_t a[3] = { o, a1, a2 };
    return dipad_effect_call(0, o, nm, 3, a);
}
static uint32_t set_mag(uint32_t o, int k, int32_t mag, uint32_t period_us){
    dieffect(k, mag, 0, period_us, 0xFFFFFFFFu, 10000u, 1);
    return eff(o, "SetParameters", DIEFF, 0x140u);           /* the game's flags */
}
static uint32_t prop(int set, uint32_t p, uint32_t v){
    memset(g_mem + PROPH, 0, 0x20); MR32(PROPH) = 0x14u; MR32(PROPH + 4) = 0x10u; MR32(PROPH + 16) = v;
    return dipad_ff_prop(set, p, PROPH);
}

/* ---- the player car for the jolts ---- */
#define G_PLAYER1 0x008900acu
#define G_STEP    0x00865150u
#define G_FLOW    0x008654a4u
#define G_FREEZE  0x00890084u
#define PLAYER    0x00200000u
#define CAR       0x00201000u
static void world(int flow, float step, float vx){
    MR32(G_FLOW) = (uint32_t)flow; MRF32(G_STEP) = step;
    MR32(G_PLAYER1) = PLAYER; MR32(PLAYER + 4) = CAR;
    MRF32(CAR + 0x70) = vx; MRF32(CAR + 0x74) = 0; MRF32(CAR + 0x78) = 0;
}

static void race_sequence(void){
    printf("a quick race, as the game sends it\n");
    dipad_ff_test_reset(1);
    check("force feedback on (NFSU2_FF=1)", dipad_ff_on());
    check("SetProperty DIPROP_FFGAIN 10000", prop(1, 7u, 10000u) == 0);
    check("SendForceFeedbackCommand DISFFC_SETACTUATORSON", dev("SendForceFeedbackCommand", 0x10u, 0, 0) == 0);
    uint32_t damper = create(DAMPER, 7055, 0);
    check("CreateEffect damper", damper && eff(damper, "Start", 1, 0) == 0);
    uint32_t sine = create(SINE, 0, 0);
    check("CreateEffect sine (magnitude 0)", sine && eff(sine, "Start", 1, 0) == 0);
    CHECKL("front of the grid: a damper and a silent sine are still", 0.f, 0.f);
    for (int i = 0; i < 5; i++){ dieffect(DAMPER, 5207 - 900 * i, 0, 0, 0xFFFFFFFFu, 10000u, 0); eff(damper, "SetParameters", DIEFF, 0x140u); }
    CHECKL("the damper weighing the steering is not played", 0.f, 0.f);
    /* the vibration changes kind: Unload, a new one, started */
    check("Unload the sine", eff(sine, "Unload", 0, 0) == 0);
    uint32_t sq = create(SQUARE, 1224, 50000u);
    check("CreateEffect square (1224, 50 ms)", sq && eff(sq, "Start", 1, 0) == 0);
    CHECKL("a 50 ms vibration on both motors at its magnitude", 0.1224f, 0.1224f);
    static const int32_t mags[] = { 444, 409, 1171, 1168, 1566, 1557, 1194 };
    for (unsigned i = 0; i < sizeof mags / sizeof *mags; i++) set_mag(sq, SQUARE, mags[i], 50000u);
    CHECKL("SetParameters every frame: the last magnitude (1194)", 0.1194f, 0.1194f);
    uint32_t spring = create(SPRING, 10000, 0);
    check("CreateEffect spring (10000)", spring && eff(spring, "Start", 1, 0) == 0);
    CHECKL("the centring spring is not played", 0.1194f, 0.1194f);
    eff(spring, "Stop", 0, 0);
    printf("the pause menu\n");
    eff(sq, "Stop", 0, 0); eff(damper, "Stop", 0, 0);
    CHECKL("Stop: still", 0.f, 0.f);
    uint32_t st = OUTP; eff(sq, "GetEffectStatus", st, 0);
    check("GetEffectStatus: not playing", MR32(st) == 0);
    eff(damper, "Start", 1, 0); eff(sq, "Start", 1, 0);
    CHECKL("Start again after it", 0.1194f, 0.1194f);
    eff(sq, "GetEffectStatus", st, 0);
    check("GetEffectStatus: playing", MR32(st) == 1);
    dieffect(SQUARE, 0, 0, 0, 0, 0, 0);
    eff(sq, "GetParameters", DIEFF, 0x105u);
    check("GetParameters: duration, gain, magnitude and period back", MR32(DIEFF + 8) == 0xFFFFFFFFu && MR32(DIEFF + 0x10) == 10000u
          && MR32(TPAR) == 1194u && MR32(TPAR + 12) == 50000u);

    printf("a long drive: Unload and CreateEffect, the old ones never released\n");
    uint32_t cur = sq; int ok = 1;
    for (int i = 0; i < 150; i++){
        eff(cur, "Unload", 0, 0);
        uint32_t n = create(i & 1 ? SQUARE : SINE, 800 + i, 50000u);
        if (!n || eff(n, "Start", 1, 0)){ ok = 0; break; }
        cur = n;
    }
    check("150 changes: every CreateEffect succeeds (an unloaded effect's place is taken)", ok);
    check("the effect whose place was taken first (the sine) is known no more", eff(sine, "Start", 1, 0) == 0x80070057u);
    CHECKL("the newest vibration plays (949)", 0.0949f, 0.0949f);
}

static void mix_rules(void){
    printf("the mix\n");
    dipad_ff_test_reset(1);
    uint32_t slow = create(SINE, 5000, 80000u); eff(slow, "Start", 1, 0);
    CHECKL("slow vibration (80 ms) on the strong motor only", 0.5f, 0.f);
    uint32_t fast = create(TRIANGLE, 4000, 20000u); eff(fast, "Start", 1, 0);
    CHECKL("plus a fast one (20 ms) on the weak motor", 0.5f, 0.4f);
    eff(slow, "Stop", 0, 0); eff(fast, "Stop", 0, 0);
    uint32_t c = create(CONST, -6000, 0); eff(c, "Start", 1, 0);
    CHECKL("a constant force (-6000): half its strength on the weak motor", 0.f, 0.3f);
    eff(c, "Stop", 0, 0);
    uint32_t r = create(RAMP, 8000, 0); eff(r, "Start", 1, 0);
    CHECKL("a ramp (0 to 8000): its bigger end, half, weak", 0.f, 0.4f);
    eff(r, "Stop", 0, 0);
    uint32_t a = create(SAWUP, 7000, 100000u), b = create(SAWDOWN, 7000, 100000u);
    eff(a, "Start", 1, 0); eff(b, "Start", 1, 0);
    CHECKL("two strong vibrations add up, clamped at 1", 1.f, 0.f);
    eff(b, "Start", 1, 1u);                                   /* DIES_SOLO */
    CHECKL("Start with DIES_SOLO stops the others", 0.7f, 0.f);
    check("DIPROP_FFGAIN 5000", prop(1, 7u, 5000u) == 0 && prop(0, 7u, 0) == 0 && MR32(PROPH + 16) == 5000u);
    CHECKL("device gain halves it", 0.35f, 0.f);
    prop(1, 7u, 10000u);
    dev("SendForceFeedbackCommand", 0x4u, 0, 0);              /* PAUSE */
    CHECKL("DISFFC_PAUSE: still", 0.f, 0.f);
    dev("SendForceFeedbackCommand", 0x8u, 0, 0);              /* CONTINUE */
    CHECKL("DISFFC_CONTINUE: back", 0.7f, 0.f);
    dev("SendForceFeedbackCommand", 0x20u, 0, 0);             /* SETACTUATORSOFF */
    CHECKL("actuators off: still", 0.f, 0.f);
    dev("SendForceFeedbackCommand", 0x10u, 0, 0);
    dev("SendForceFeedbackCommand", 0x2u, 0, 0);              /* STOPALL */
    CHECKL("DISFFC_STOPALL: still", 0.f, 0.f);

    printf("durations, iterations, delay, envelope, effect gain\n");
    dipad_ff_test_reset(1);
    uint32_t p = OUTP;
    dev("CreateEffect", guid(SINE), dieffect(SINE, 6000, 0, 100000u, 500000u, 5000u, 0), p);
    uint32_t e = MR32(p); eff(e, "Start", 2, 0);
    CHECKL("effect gain 5000: half", 0.3f, 0.f);
    g_t += 0.9; CHECKL("two iterations of 0.5 s: still playing at 0.9 s", 0.3f, 0.f);
    g_t += 0.2; CHECKL("over after 1 s", 0.f, 0.f);
    dieffect(SINE, 6000, 0, 100000u, 1000000u, 10000u, 0);
    MR32(DIEFF + 0x34) = 200000u;                             /* dwStartDelay */
    MR32(DIEFF + 0x28) = ENVL; MR32(ENVL + 4) = 0; MR32(ENVL + 8) = 400000u; MR32(ENVL + 12) = 0; MR32(ENVL + 16) = 200000u;
    eff(e, "SetParameters", DIEFF, 0x3FFu | 0x20000000u);     /* DIEP_ALLPARAMS | DIEP_START */
    CHECKL("DIEP_START with a 200 ms start delay: nothing yet", 0.f, 0.f);
    g_t += 0.4; CHECKL("half way through a 400 ms attack from 0", 0.3f, 0.f);
    g_t += 0.4; CHECKL("after the attack, before the fade", 0.6f, 0.f);
    g_t += 0.3; CHECKL("half way through the 200 ms fade to 0", 0.3f, 0.f);
    g_t += 0.2; CHECKL("over", 0.f, 0.f);

    printf("the device's other answers\n");
    g_enum_n = 0;
    check("EnumEffects (all): constant, ramp, five periodic, spring, damper",
          dev("EnumEffects", 0x401000u, 0, 0) == 0 && g_enum_n == 9 && g_enum_types[0] == 1 && g_enum_types[1] == 2
          && g_enum_types[2] == 3 && g_enum_types[8] == 4);
    g_enum_n = 0;
    check("EnumEffects (DIEFT_PERIODIC): five", dev("EnumEffects", 0x401000u, 0, 3u) == 0 && g_enum_n == 5);
    MR32(OUTP) = 0;
    check("GetForceFeedbackState: stopped, actuators on, power on", dev("GetForceFeedbackState", OUTP, 0, 0) == 0
          && (MR32(OUTP) & 0x52u) == 0x52u);
    check("CreateEffect with an unknown GUID: DIERR_INVALIDPARAM", dev("CreateEffect", DIEFF, 0, OUTP) == 0x80070057u && MR32(OUTP) == 0);
    check("DIPROP_FFLOAD: 0", prop(0, 8u, 7u) == 0 && MR32(PROPH + 16) == 0);
    uint32_t x = create(SINE, 3000, 100000u); eff(x, "Start", 1, 0);
    dipad_effect_ref(x, 1); dipad_effect_ref(x, -1);
    CHECKL("AddRef + Release: still there", 0.3f, 0.f);
    dipad_effect_ref(x, -1);
    CHECKL("the last Release: gone", 0.f, 0.f);
    check("a released effect answers DIERR_INVALIDPARAM", eff(x, "Start", 1, 0) == 0x80070057u);

    printf("force feedback off (NFSU2_FF=0)\n");
    dipad_ff_test_reset(0);
    g_calls = 0;
    check("CreateEffect: DIERR_UNSUPPORTED, no object", dev("CreateEffect", guid(SINE), dieffect(SINE, 1, 0, 1, 1, 1, 0), OUTP) == 0x80004001u && MR32(OUTP) == 0);
    check("DIPROP_FFGAIN: DIERR_UNSUPPORTED", prop(1, 7u, 1u) == 0x80004001u);
    dipad_ff_frame();
    check("no motor levels at all", g_calls == 0);
}

static void jolts_and_standing(void){
    printf("the car's jolts (NFSU2_FF_JOLT=1)\n");
    setenv("NFSU2_FF_JOLT", "1", 1);
    dipad_ff_test_reset(1);
    const float dt = 1.f / 60.f;
    for (int i = 0; i < 90; i++){ world(6, dt, 20.f); dipad_ff_frame(); }
    check("1.5 s at a steady 20 m/s: still", near(g_motor[0], 0) && near(g_motor[1], 0));
    world(6, dt, 26.f); dipad_ff_frame();
    check("6 m/s in one step (a wall): full on the strong motor, 0.4 on the weak", g_motor[0] > 0.85f && g_motor[1] > 0.33f && g_motor[1] < 0.4f);
    float peak = g_motor[0];
    for (int i = 0; i < 30; i++){ world(6, dt, 26.f); dipad_ff_frame(); }
    check("half a second later it has died away", g_motor[0] < 0.05f * peak + 0.01f);
    for (int i = 0; i < 30; i++){ world(6, dt, 26.f); dipad_ff_frame(); }
    for (int i = 0; i < 2; i++){ world(6, dt, 26.f + 0.5f * (float)(i + 1)); dipad_ff_frame(); }
    check("hard acceleration (30 m/s^2) is no jolt", near(g_motor[0], 0));
    world(6, dt, 200.f); dipad_ff_frame();
    check("a jump of 170 m/s (the car put back) is no jolt", near(g_motor[0], 0));
    unsetenv("NFSU2_FF_JOLT");

    printf("the world stands (the pause menu, photo mode)\n");
    dipad_ff_test_reset(1);
    uint32_t v = create(SQUARE, 1500, 50000u); eff(v, "Start", 1, 0);
    world(6, dt, 20.f); CHECKL("driving: the vibration", 0.15f, 0.15f);
    world(6, 0.f, 20.f); CHECKL("one frame without a world step: still the vibration", 0.15f, 0.15f);
    dipad_ff_frame(); CHECKL("three in a row: still", 0.f, 0.f);
    world(6, dt, 20.f); CHECKL("the world runs again", 0.15f, 0.15f);
    MR32(G_FREEZE) = 1; CHECKL("photo mode (the world freeze): still", 0.f, 0.f);
    MR32(G_FREEZE) = 0;
    world(3, 0.f, 0.f); dipad_ff_frame(); dipad_ff_frame();
    CHECKL("the front end (no world step) is not the world standing", 0.15f, 0.15f);
}

int main(void){
    g_mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
    if (g_mem == MAP_FAILED){ printf("FAIL no guest memory\n"); return 1; }
    memset(g_cbits, 0xFF, sizeof g_cbits);
    unsetenv("NFSU2_FF_JOLT");
    dipad_ff_test_clock(fake_now);
    race_sequence();
    mix_rules();
    jolts_and_standing();
    printf(g_fail ? "ff_unit: %d FAILED\n" : "ff_unit: all passed\n", g_fail);
    return g_fail != 0;
}
