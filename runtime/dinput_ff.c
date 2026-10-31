/* dinput_ff.c -- force feedback on the game pad (runtime/dinput_pad.c): the
 * game's DirectInput effects mixed into two motor levels, which
 * runtime/rumble.m plays on the controller's motors.
 *
 * How SPEED2.EXE v1.2 uses force feedback (static analysis and logs of quick
 * races with NFSU2_FF_LOG, the same on the European and the North American
 * build; European addresses, North American ones in parentheses):
 *   - A device whose axes are force-feedback actuators (DIDOI_FFACTUATOR,
 *     counted in [0x86ff80]) gets effects through the game's force-feedback
 *     manager [0x870760]: 0x5c9160 .. 0x5ca082 (0x5c9150 .. 0x5ca072) create
 *     and change a constant force, springs, a damper and square, sine,
 *     triangle and sawtooth vibrations.
 *   - The player car's 0x406460, every frame of a race: a damper that weighs
 *     the steering with the speed, a centring spring at full strength for a
 *     while after hard steering, and one vibration of 50 ms period (20 Hz) for the road and
 *     the engine: a square or sine wave whose magnitude (400 to 1600 of 10000)
 *     it changes nearly every frame with SetParameters (DIEP_TYPESPECIFICPARAMS
 *     | DIEP_ENVELOPE).  When the kind of vibration changes it Unloads the old
 *     one (0x5c0000 (0x5bfff0)) and creates a new one, and never releases the
 *     old.  The pause menu stops them and the race starts them again.
 *   - Those effects are made for wheels (0x5cd200 (0x5cd1f0) sorts a device
 *     by its type: driving, joystick, gamepad).  On a pad only the vibration
 *     can be felt: a light, steady rumble while driving.  A crash makes
 *     nothing of its own.  tests/ff_unit.c replays what a race sends.
 *
 * Here the pad reports force feedback (NFSU2_FF=1, the launcher's Rumble
 * switch) and plays the effects itself: every poll (GetDeviceState) the
 * running ones are mixed into two motor levels (dipad_ff_frame).  A periodic
 * effect is a vibration: slow ones (period 60 ms and more) on the strong,
 * low-frequency motor, fast ones (25 ms and less) on the weak one, those
 * between (the game's 50 ms) on both, as a force-feedback pad's driver plays
 * them.  A constant or ramp force is what pushes a wheel; on a pad it is a
 * light rumble on the weak motor.  Springs, dampers, inertia and friction
 * centre or weigh a wheel and are not played.  Effect gain x device gain x
 * the envelope.  With NFSU2_FF_JOLT=1 (the launcher's "Rumble on crashes")
 * the pad also rumbles on the player car's own jolts, as the console
 * versions do (ff_jolt).  While the world stands (the pause menu, photo
 * mode) the motors are still.
 *
 *   NFSU2_FF=1          report force feedback and play it (default off: the
 *                       pad without force feedback, as before)
 *   NFSU2_FF_JOLT=1     also rumble on crashes and hard landings
 *   NFSU2_FF_LOG=1      log the effects the game creates, changes, starts and
 *                       stops, and the motor levels when they change
 * Ported from th0mk's nfsu2-web runtime/dinput_pad.c (MIT). */
#include "cpu.h"
#include "gamepad.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

uint32_t call_guest(CPU *c, uint32_t fn, int nargs, const uint32_t *args);
uint32_t com_scratch(uint32_t n);                       /* com.c */
uint32_t com_new_dieffect(void);

#define DI_OK               0x00000000u
#define DIERR_INVALIDPARAM  0x80070057u
#define DIERR_UNSUPPORTED   0x80004001u
#define DIERR_DEVICEFULL    0x80040208u
#define E_OUTOFMEMORY       0x8007000Eu

/* game data (world step: EU 0x865150, NA 0x865154) */
#define G_PLAYER1  GA(0x008900acu)      /* Player*: +4 its car */
#define G_STEP     GA(0x00865150u)      /* this frame's world step, s (0 while the world stands) */
#define G_FLOW     GA(0x008654a4u)      /* GameFlowManager: 6 in the world */
#define G_FREEZE   GA(0x00890084u)      /* the world freeze (photo mode, runtime/photo.c) */

#define FF_INFINITE 0xFFFFFFFFu
enum { EF_CONST = 0x20, EF_RAMP, EF_SQUARE, EF_SINE, EF_TRIANGLE, EF_SAWUP, EF_SAWDOWN,
       EF_SPRING, EF_DAMPER, EF_INERTIA, EF_FRICTION, EF_CUSTOM };   /* GUID_* Data1 low byte */
static const uint8_t k_ff_d4[8] = {0x9A, 0xD0, 0x00, 0xA0, 0xC9, 0xA0, 0x6E, 0x35};
typedef struct {
    uint32_t obj;                       /* the guest IDirectInputEffect; 0 = a free slot */
    int      kind;                      /* EF_* */
    uint32_t dur_us, gain, delay_us;    /* DIEFFECT */
    int32_t  mag, offset;               /* DIPERIODIC dwMagnitude/lOffset, DICONSTANTFORCE, DIRAMPFORCE,
                                           DICONDITION lPositiveCoefficient/lOffset (logs only) */
    uint32_t period_us;
    int      env; uint32_t att_lvl, att_us, fade_lvl, fade_us;   /* DIENVELOPE */
    int      playing; uint32_t iters; double t0;
    int      unloaded;                  /* Unload gave its place on the device back (see CreateEffect) */
} Eff;
#define NEFF 64
static Eff g_eff[NEFF];
static uint32_t g_ff_gain = 10000u;     /* DIPROP_FFGAIN */
static int g_ff_paused, g_ff_actoff;    /* SendForceFeedbackCommand */
static float g_level[2];                /* the last motor levels (strong, weak) */

static int ff_log(void){ static int v = -1; if (v < 0) v = gamepad_env_flag("NFSU2_FF_LOG", 0); return v; }
static int g_on = -1;
int dipad_ff_on(void){
    if (g_on < 0){
        g_on = gamepad_env_flag("NFSU2_FF", 0);
        if (g_on || ff_log()) fprintf(stderr, "[ff] force feedback %s\n",
                                      g_on ? "on: the game's effects play as rumble" : "off (NFSU2_FF)");
    }
    return g_on;
}
static int g_jolt_on = -1;            /* NFSU2_FF_JOLT */
static int jolt_on(void){ if (g_jolt_on < 0) g_jolt_on = gamepad_env_flag("NFSU2_FF_JOLT", 0); return g_jolt_on; }

static double mono_s(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec + (double)t.tv_nsec * 1e-9; }
static double (*g_clock)(void) = mono_s;
static double ff_now(void){ return g_clock(); }

static const char *ff_name(int k){
    static const char *const n[] = { "constant", "ramp", "square", "sine", "triangle", "sawtooth up", "sawtooth down",
                                     "spring", "damper", "inertia", "friction", "custom" };
    return k >= EF_CONST && k <= EF_CUSTOM ? n[k - EF_CONST] : "?";
}
static int ff_periodic(int k){ return k >= EF_SQUARE && k <= EF_SAWDOWN; }
static int ff_condition(int k){ return k >= EF_SPRING && k <= EF_FRICTION; }
static Eff *eff_of(uint32_t obj){
    if (!obj || !mem_is_committed(obj + 7u)) return 0;
    uint32_t i = MR32(obj + 4u);
    return i >= 1u && i <= NEFF && g_eff[i - 1].obj == obj ? &g_eff[i - 1] : 0;
}
static void put_ff_guid(uint32_t p, int k){
    MR32(p) = 0x13541C00u | (uint32_t)k; MR16(p + 4) = 0x8E33; MR16(p + 6) = 0x11D0;
    memcpy(g_mem + p + 8, k_ff_d4, 8);
}
static int guid_kind(uint32_t g){
    if (!g || !mem_is_committed(g + 15u)) return 0;
    uint32_t d1 = MR32(g);
    if ((d1 & 0xFFFFFF00u) != 0x13541C00u || MR16(g + 4) != 0x8E33u || MR16(g + 6) != 0x11D0u ||
        memcmp(g_mem + g + 8, k_ff_d4, 8)) return 0;
    int k = (int)(d1 & 0xFFu);
    return k >= EF_CONST && k <= EF_CUSTOM ? k : 0;
}

/* DIEFFECT (dwSize 0x38 for DirectX 5, 0x44 since 6): the fields DIEP_* names */
#define DIEP_DURATION 0x1u
#define DIEP_GAIN 0x4u
#define DIEP_ENVELOPE 0x80u
#define DIEP_TYPESPECIFICPARAMS 0x100u
#define DIEP_STARTDELAY 0x200u
#define DIEP_ALLPARAMS 0x3FFu
#define DIEP_START 0x20000000u
static void eff_start(Eff *e, uint32_t iters, uint32_t flags){
    if (flags & 1u)                                     /* DIES_SOLO */
        for (int i = 0; i < NEFF; i++) if (&g_eff[i] != e) g_eff[i].playing = 0;
    e->playing = 1; e->iters = iters ? iters : 1u; e->t0 = ff_now();
    if (ff_log()) fprintf(stderr, "[ff] start %s #%d x%u (magnitude %d, period %u us, duration %u us, gain %u)\n",
                          ff_name(e->kind), (int)(e - g_eff), e->iters, e->mag, e->period_us, e->dur_us, e->gain);
}
static uint32_t eff_set(Eff *e, uint32_t p, uint32_t fl){
    if (!p || !mem_is_committed(p + 0x33u)) return DIERR_INVALIDPARAM;
    uint32_t sz = MR32(p);
    if (fl & DIEP_DURATION) e->dur_us = MR32(p + 0x08);
    if (fl & DIEP_GAIN){ uint32_t g = MR32(p + 0x10); e->gain = g > 10000u ? 10000u : g; }
    if (fl & DIEP_ENVELOPE){
        uint32_t ev = MR32(p + 0x28);
        e->env = ev && mem_is_committed(ev + 19u);
        if (e->env){ e->att_lvl = MR32(ev + 4); e->att_us = MR32(ev + 8); e->fade_lvl = MR32(ev + 12); e->fade_us = MR32(ev + 16); }
    }
    if (fl & DIEP_TYPESPECIFICPARAMS){
        uint32_t cb = MR32(p + 0x2c), tp = MR32(p + 0x30);
        if (tp && cb && mem_is_committed(tp + cb - 1u)){
            if (ff_periodic(e->kind) && cb >= 16u){
                e->mag = (int32_t)MR32(tp); e->offset = (int32_t)MR32(tp + 4); e->period_us = MR32(tp + 12);
            } else if (e->kind == EF_CONST && cb >= 4u) e->mag = (int32_t)MR32(tp);
            else if (e->kind == EF_RAMP && cb >= 8u){
                int32_t a = (int32_t)MR32(tp), b = (int32_t)MR32(tp + 4);
                e->mag = abs(a) > abs(b) ? a : b;
            } else if (ff_condition(e->kind) && cb >= 24u){     /* DICONDITION, the first axis */
                e->offset = (int32_t)MR32(tp); e->mag = (int32_t)MR32(tp + 4);
            }
        }
    }
    if ((fl & DIEP_STARTDELAY) && sz >= 0x38u) e->delay_us = MR32(p + 0x34);
    if (ff_log()) fprintf(stderr, "[ff] parameters %s #%d: flags 0x%x magnitude %d offset %d period %u us duration %u us gain %u delay %u us"
                          " envelope %d (attack %u over %u us, fade %u over %u us)\n",
                          ff_name(e->kind), (int)(e - g_eff), fl, e->mag, e->offset, e->period_us, e->dur_us, e->gain, e->delay_us,
                          e->env, e->att_lvl, e->att_us, e->fade_lvl, e->fade_us);
    if (fl & DIEP_START) eff_start(e, 1u, 0u);
    return DI_OK;
}

/* ---- the player car's jolts ------------------------------------------------------
 * Impacts and hard landings.  car+0x70 is the velocity (m/s), the world step
 * this frame's (s; 0 while the world stands), [0x8654a4] 6 in the world.  A
 * change of velocity over the last 30 ms of world time (the same window at
 * 60 and 120 fps: a crash may take two steps at 120) that driving cannot
 * make (more than 40 m/s^2, about 4 g) is a hit: its excess sets the level
 * (4 m/s and more: full), on the strong motor and a little of it on the weak
 * one, decaying with a time constant of 0.12 s.  A jump of more than 60 m/s
 * is the game putting the car back (a reset, a teleport), not a hit, and so
 * is everything in the car's first second (the race intro drops it onto the
 * grid: 8.8 m/s, measured).  Measured in a quick race at 60 fps: 6.4 m/s for
 * a wall at 23 m/s, 16 m/s for a crash, 1.2 to 5 m/s scraping along a
 * barrier. */
static float g_jolt;                    /* 0..1, decaying */
static uint32_t g_jolt_car;
#define JOLT_HIST 32
static struct { float v[3], t; } g_jh[JOLT_HIST];   /* velocity at world time t (s), newest at g_jhn - 1 */
static int g_jhn;
static float g_jolt_age, g_jolt_logt;   /* world seconds since this car appeared; since the last speed line */
static void ff_jolt(void){
    uint32_t pl = mem_is_committed(G_PLAYER1 + 3u) ? MR32(G_PLAYER1) : 0u;
    uint32_t car = pl && mem_is_committed(pl + 7u) ? MR32(pl + 4u) : 0u;
    if (!mem_is_committed(G_FLOW + 3u) || MR32(G_FLOW) != 6u || !car || !mem_is_committed(car + 0x7bu)){
        g_jolt_car = 0; g_jolt = 0; return;
    }
    float dt = MRF32(G_STEP);
    float v[3] = { MRF32(car + 0x70u), MRF32(car + 0x74u), MRF32(car + 0x78u) };
    if (!isfinite(v[0]) || !isfinite(v[1]) || !isfinite(v[2])) return;
    if (!(dt > 0.f && dt < 0.25f)) return;              /* the world stands (pause, a menu over it) */
    g_jolt_age = car == g_jolt_car ? g_jolt_age + dt : 0.f;
    if (ff_log() && (g_jolt_logt += dt) >= 2.f){
        g_jolt_logt = 0.f;
        fprintf(stderr, "[ff] car speed %.1f m/s\n", (double)sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]));
    }
    if (car != g_jolt_car) g_jhn = 0;
    float now = g_jolt_age;
    if (car == g_jolt_car && g_jolt_age > 1.f && g_jhn > 0){
        /* the oldest sample still inside the 30 ms window (or the oldest kept) */
        int k = g_jhn - 1;
        while (k > 0 && now - g_jh[(k - 1) % JOLT_HIST].t <= 0.030f && g_jhn - k < JOLT_HIST - 1) k--;
        const float *o = g_jh[k % JOLT_HIST].v;
        float span = now - g_jh[k % JOLT_HIST].t;
        float dx = v[0] - o[0], dy = v[1] - o[1], dz = v[2] - o[2];
        float dv = sqrtf(dx * dx + dy * dy + dz * dz);
        float hit = dv - 40.f * span;
        if (dv < 60.f && hit > 0.f){
            float lvl = hit / 4.f;
            if (lvl > 1.f) lvl = 1.f;
            if (lvl > g_jolt + 0.05f && ff_log()) fprintf(stderr, "[ff] jolt %.2f m/s in %.1f ms: level %.2f\n", (double)dv, (double)span * 1000.0, (double)lvl);
            if (lvl > g_jolt) g_jolt = lvl;
        }
    }
    { int n = g_jhn % JOLT_HIST; g_jh[n].v[0] = v[0]; g_jh[n].v[1] = v[1]; g_jh[n].v[2] = v[2]; g_jh[n].t = now; g_jhn++; }
    g_jolt *= expf(-dt / 0.12f);
    if (g_jolt < 0.01f) g_jolt = 0.f;
    g_jolt_car = car;
}

/* The world stands: photo mode (the world freeze), or a world step of 0 for
 * three polls in a row (the pause menu; a single frame without a step is
 * the frame pacer's). */
static int g_still;
static int world_stands(void){
    if (!mem_is_committed(G_FLOW + 3u) || MR32(G_FLOW) != 6u){ g_still = 0; return 0; }
    if (mem_is_committed(G_FREEZE + 3u) && MR32(G_FREEZE)) return 1;
    if (!mem_is_committed(G_STEP + 3u)) return 0;
    g_still = MRF32(G_STEP) > 0.f ? 0 : g_still + 1;
    return g_still >= 3;
}

/* ---- the mix ---------------------------------------------------------------------- */
static float g_ff_last[2] = { -1.f, -1.f };
static int g_stood = -1;
void dipad_ff_frame(void){
    if (!dipad_ff_on()) return;
    double now = ff_now();
    double strong = 0, weak = 0;
    for (int i = 0; i < NEFF; i++){
        Eff *e = &g_eff[i];
        if (!e->obj || !e->playing || g_ff_paused) continue;
        double t = (now - e->t0) * 1e6 - (double)e->delay_us;
        if (t < 0) continue;
        double dur = e->dur_us == FF_INFINITE ? INFINITY : (double)e->dur_us;
        if (isfinite(dur)){
            double total = e->iters == FF_INFINITE ? INFINITY : dur * (double)e->iters;
            if (t >= total){ e->playing = 0; continue; }
            if (dur > 0) t = fmod(t, dur);
        }
        double lvl = ff_periodic(e->kind) ? fabs((double)e->mag) + fabs((double)e->offset) : fabs((double)e->mag);
        if (e->env){
            if (e->att_us && t < (double)e->att_us) lvl = (double)e->att_lvl + (lvl - (double)e->att_lvl) * t / (double)e->att_us;
            else if (e->fade_us && isfinite(dur) && t > dur - (double)e->fade_us)
                lvl = (double)e->fade_lvl + (lvl - (double)e->fade_lvl) * (dur - t) / (double)e->fade_us;
        }
        double a = lvl / 10000.0 * (double)e->gain / 10000.0 * (double)g_ff_gain / 10000.0;
        if (a <= 0) continue;
        if (ff_periodic(e->kind)){
            if (e->period_us >= 60000u) strong += a;
            else if (e->period_us <= 25000u) weak += a;
            else { strong += a; weak += a; }
        } else if (e->kind == EF_CONST || e->kind == EF_RAMP) weak += a * 0.5;
    }
    if (jolt_on()){ ff_jolt(); strong += g_jolt; weak += g_jolt * 0.4f; }
    int stands = world_stands();
    if (g_ff_actoff || stands){ strong = 0; weak = 0; }
    if (stands != g_stood){
        if (ff_log() && g_stood >= 0) fprintf(stderr, "[ff] the world %s\n", stands ? "stands: motors still" : "runs again");
        g_stood = stands;
    }
    float s = strong > 1 ? 1.f : (float)strong, w = weak > 1 ? 1.f : (float)weak;
    g_level[0] = s; g_level[1] = w;
    gamepad_rumble(s, w);
    if (ff_log() && (fabsf(s - g_ff_last[0]) > 0.05f || fabsf(w - g_ff_last[1]) > 0.05f || ((s == 0.f) != (g_ff_last[0] == 0.f)) || ((w == 0.f) != (g_ff_last[1] == 0.f)))){
        fprintf(stderr, "[ff] motors strong %.2f weak %.2f\n", (double)s, (double)w);
        g_ff_last[0] = s; g_ff_last[1] = w;
    }
}

/* ---- the device's force-feedback methods ------------------------------------------- */
static void effinfo(uint32_t p, uint32_t size, int k){
    if (size < 0x20u || size > 0x124u) size = 0x124u;
    mem_commit(p, size); memset(g_mem + p, 0, size);
    MR32(p) = size; put_ff_guid(p + 4, k);
    uint32_t type = k == EF_CONST ? 1u : k == EF_RAMP ? 2u : ff_periodic(k) ? 3u : k == EF_CUSTOM ? 5u : 4u;
    if (type <= 3u) type |= 0x200u | 0x400u | 0x8000u;      /* DIEFT_FFATTACK | FFFADE | STARTDELAY */
    MR32(p + 0x14) = type;
    MR32(p + 0x18) = MR32(p + 0x1c) = DIEP_ALLPARAMS;
    if (size >= 0x124u) snprintf((char *)(g_mem + p + 0x20), 260, "%s", ff_name(k));
}
/* DIPROP_FFGAIN (7) and DIPROP_FFLOAD (8) */
uint32_t dipad_ff_prop(int set, uint32_t prop, uint32_t h){
    if (!dipad_ff_on()) return DIERR_UNSUPPORTED;
    if (prop == 7u){
        if (set){ uint32_t g = MR32(h + 16); g_ff_gain = g > 10000u ? 10000u : g;
                  if (ff_log()) fprintf(stderr, "[ff] device gain %u\n", g_ff_gain); }
        else MR32(h + 16) = g_ff_gain;
        return DI_OK;
    }
    if (set) return DIERR_UNSUPPORTED;
    MR32(h + 16) = 0;
    return DI_OK;
}
/* IDirectInputDevice8's force-feedback methods; -1 = not one of them */
int64_t dipad_ff_dev_call(CPU *c, const char *nm, const uint32_t *a){
    if (!strcmp(nm, "CreateEffect")){
        uint32_t g = a[1], peff = a[2], pp = a[3];
        if (pp && mem_is_committed(pp + 3)) MR32(pp) = 0;
        if (!dipad_ff_on()) return DIERR_UNSUPPORTED;
        int k = guid_kind(g);
        if (!k || !pp) return DIERR_INVALIDPARAM;
        /* The game changes a rumble by Unload and a new effect, and never
         * releases the old one: on Windows Unload frees the effect's place in
         * the device, so an unloaded effect's slot is taken once none is free
         * (otherwise 64 changes in every CreateEffect would fail, and the game
         * logs two errors every frame from then on). */
        int slot = -1;
        for (int i = 0; i < NEFF; i++) if (!g_eff[i].obj){ slot = i; break; }
        for (int i = 0; slot < 0 && i < NEFF; i++) if (g_eff[i].unloaded) slot = i;
        if (slot < 0){
            static int said;
            if (!said++) fprintf(stderr, "[ff] CreateEffect: all %d effects are in use (DIERR_DEVICEFULL)\n", NEFF);
            return DIERR_DEVICEFULL;
        }
        uint32_t obj = com_new_dieffect();
        if (!obj) return E_OUTOFMEMORY;
        Eff *e = &g_eff[slot];
        int reused = e->obj != 0;               /* the old object stays, with no slot (eff_of: 0) */
        memset(e, 0, sizeof *e);
        e->obj = obj; e->kind = k; e->gain = 10000u; e->dur_us = FF_INFINITE;
        MR32(obj + 4u) = (uint32_t)slot + 1u;
        if (ff_log()) fprintf(stderr, "[ff] CreateEffect %s -> #%d 0x%08x%s\n", ff_name(k), slot, obj, reused ? " (an unloaded effect's place)" : "");
        if (peff) eff_set(e, peff, DIEP_ALLPARAMS);
        MR32(pp) = obj;
        return DI_OK;
    }
    if (!strcmp(nm, "EnumEffects")){
        uint32_t cb = a[1], ref = a[2], want = a[3] & 0xFFu;
        if (!cb || !dipad_ff_on()) return DI_OK;
        static uint32_t ei = 0;
        if (!ei) ei = com_scratch(0x124);
        for (int k = EF_CONST; k <= EF_DAMPER; k++){
            uint32_t type = k == EF_CONST ? 1u : k == EF_RAMP ? 2u : ff_periodic(k) ? 3u : 4u;
            if (want && want != type) continue;
            effinfo(ei, 0x124u, k);
            uint32_t args[2] = { ei, ref };
            if (call_guest(c, cb, 2, args) == 0u) break;    /* DIENUM_STOP */
        }
        return DI_OK;
    }
    if (!strcmp(nm, "GetEffectInfo")){
        uint32_t p = a[1]; int k = guid_kind(a[2]);
        if (!dipad_ff_on()) return DIERR_UNSUPPORTED;
        if (!k || !p || !mem_is_committed(p + 3)) return DIERR_INVALIDPARAM;
        effinfo(p, MR32(p), k);
        return DI_OK;
    }
    if (!strcmp(nm, "GetForceFeedbackState")){
        uint32_t p = a[1];
        if (!dipad_ff_on()) return DIERR_UNSUPPORTED;
        if (!p || !mem_is_committed(p + 3)) return DIERR_INVALIDPARAM;
        int any = 0;
        for (int i = 0; i < NEFF; i++) if (g_eff[i].obj && g_eff[i].playing) any = 1;
        MR32(p) = (any ? 0u : 2u) | (g_ff_paused ? 4u : 0u) | (g_ff_actoff ? 0x20u : 0x10u) | 0x40u | 0x400u;
        return DI_OK;                                   /* STOPPED, PAUSED, ACTUATORSON/OFF, POWERON, USERFFSWITCHON */
    }
    if (!strcmp(nm, "SendForceFeedbackCommand")){
        uint32_t f = a[1];
        if (!dipad_ff_on()) return DI_OK;
        if (f & 3u) for (int i = 0; i < NEFF; i++) g_eff[i].playing = 0;      /* RESET, STOPALL */
        if (f & 4u) g_ff_paused = 1;
        if (f & 8u) g_ff_paused = 0;
        if (f & 0x10u) g_ff_actoff = 0;
        if (f & 0x20u) g_ff_actoff = 1;
        if (ff_log()) fprintf(stderr, "[ff] SendForceFeedbackCommand 0x%x\n", f);
        if (f & 0x27u) dipad_ff_frame();
        return DI_OK;
    }
    if (!strcmp(nm, "EnumCreatedEffectObjects")){
        uint32_t cb = a[1], ref = a[2];
        if (!cb) return DIERR_INVALIDPARAM;
        for (int i = 0; i < NEFF; i++) if (g_eff[i].obj){
            uint32_t args[2] = { g_eff[i].obj, ref };
            if (call_guest(c, cb, 2, args) == 0u) break;
        }
        return DI_OK;
    }
    return -1;
}

/* ---- IDirectInputEffect (com.c dispatches here; IUnknown is com.c's) ----------------- */
uint32_t dipad_effect_call(CPU *c, uint32_t self, const char *nm, int nargs, const uint32_t *a){
    (void)c; (void)nargs;
    Eff *e = eff_of(self);
    if (!e) return DIERR_INVALIDPARAM;
    /* SetParameters, Start and Download put an unloaded effect back on the device */
    if (!strcmp(nm, "SetParameters")){ e->unloaded = 0; return eff_set(e, a[1], a[2]); }
    if (!strcmp(nm, "Start")){ e->unloaded = 0; eff_start(e, a[1], a[2]); return DI_OK; }
    if (!strcmp(nm, "Stop") || !strcmp(nm, "Unload")){
        if (ff_log() && (e->playing || nm[0] == 'U')) fprintf(stderr, "[ff] %s %s #%d\n", nm[0] == 'U' ? "unload" : "stop", ff_name(e->kind), (int)(e - g_eff));
        e->playing = 0;
        if (nm[0] == 'U') e->unloaded = 1;
        return DI_OK;
    }
    if (!strcmp(nm, "GetEffectStatus")){
        uint32_t p = a[1];
        if (!p || !mem_is_committed(p + 3)) return DIERR_INVALIDPARAM;
        MR32(p) = e->playing ? 1u : 0u;                 /* DIEGES_PLAYING */
        return DI_OK;
    }
    if (!strcmp(nm, "GetEffectGuid")){
        uint32_t p = a[1];
        if (!p || !mem_is_committed(p + 15)) return DIERR_INVALIDPARAM;
        put_ff_guid(p, e->kind); return DI_OK;
    }
    if (!strcmp(nm, "GetParameters")){
        uint32_t p = a[1], fl = a[2];
        if (!p || !mem_is_committed(p + 0x33u)) return DIERR_INVALIDPARAM;
        if (fl & DIEP_DURATION) MR32(p + 0x08) = e->dur_us;
        if (fl & DIEP_GAIN) MR32(p + 0x10) = e->gain;
        if ((fl & DIEP_STARTDELAY) && MR32(p) >= 0x38u) MR32(p + 0x34) = e->delay_us;
        if (fl & DIEP_TYPESPECIFICPARAMS){
            uint32_t cb = MR32(p + 0x2c), tp = MR32(p + 0x30);
            if (tp && ff_periodic(e->kind) && cb >= 16u && mem_is_committed(tp + 15u)){
                MR32(tp) = (uint32_t)e->mag; MR32(tp + 4) = (uint32_t)e->offset; MR32(tp + 8) = 0; MR32(tp + 12) = e->period_us;
            } else if (tp && ff_condition(e->kind) && cb >= 24u && mem_is_committed(tp + 23u)){
                MR32(tp) = (uint32_t)e->offset; MR32(tp + 4) = (uint32_t)e->mag;
            } else if (tp && cb >= 4u && mem_is_committed(tp + 3u)) MR32(tp) = (uint32_t)e->mag;
        }
        return DI_OK;
    }
    if (!strcmp(nm, "Download")){ e->unloaded = 0; return DI_OK; }
    if (!strcmp(nm, "Initialize")) return DI_OK;
    return DIERR_UNSUPPORTED;                           /* Escape */
}
/* AddRef (+1) and Release (-1): the effect's references past the first at
 * obj+8; the last Release gives its slot back (the object itself stays, as
 * every COM object here: com.c never reuses one) */
void dipad_effect_ref(uint32_t obj, int add){
    Eff *e = eff_of(obj);
    if (!e || !mem_is_committed(obj + 11u)) return;
    if (add > 0){ MR32(obj + 8u)++; return; }
    if (MR32(obj + 8u)){ MR32(obj + 8u)--; return; }
    if (ff_log()) fprintf(stderr, "[ff] release %s #%d\n", ff_name(e->kind), (int)(e - g_eff));
    memset(e, 0, sizeof *e);
    MR32(obj + 4u) = 0;
}

/* ---- tests (tests/ff_unit.c) ------------------------------------------------------- */
void dipad_ff_test_clock(double (*now)(void)){ g_clock = now ? now : mono_s; }
void dipad_ff_test_reset(int on){
    memset(g_eff, 0, sizeof g_eff);
    g_ff_gain = 10000u; g_ff_paused = g_ff_actoff = 0; g_on = on; g_jolt_on = -1;
    g_jolt = 0; g_jolt_car = 0; g_jhn = 0; g_still = 0; g_stood = -1;
    g_level[0] = g_level[1] = 0;
}
void dipad_ff_levels(float out[2]){ out[0] = g_level[0]; out[1] = g_level[1]; }
