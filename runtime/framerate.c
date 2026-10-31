/* framerate.c - frame-rate modes, the frame pacer, and the fixes that keep the
 * game's frame-count-driven parts right at any frame rate.
 *
 * The game runs one simulation step and one render per main-loop iteration;
 * dt is variable and the frame rate is the simulation rate.  The car physics
 * substeps (<= 4.4 ms) make the handling the same at 30, 60, 120 and 240 fps
 * as long as dt is exactly 1/rate, so the work here is
 *   (1) pace the frames on a fixed slot grid and hand the game exact ticks,
 *   (2) fix the few subsystems that count frames instead of time.
 *
 * The original PC game presents without vsync (D3DPRESENT_INTERVAL_IMMEDIATE)
 * and its own limiter in FrameTimeUpdate waits until 1/120 s ([0x7fb710]) has
 * passed: up to 120 fps.  It was made for 60 or less: above 60 smoke and
 * sparks age faster, the NOS trail is shorter, the engine sound and some
 * counters run fast.  Race intros and other in-engine scenes (NIS) ask for
 * 30 fps (SetFrameRate 0x576cc0, called at 0x435fa3).
 *
 * Options (read once):
 *   NFSU2_FPS = auto | 30 | 60 | 120 | 240 | off
 *       auto (default): the screen's maximum refresh rate mapped to the
 *       nearest supported rate (>= 239 Hz -> 240, >= 119 Hz -> 120, up to
 *       31 Hz -> 30, otherwise 60).
 *       30: for a Mac that cannot hold 60: steady frames at half the rate,
 *       the game otherwise as at 60 (the fixes below).
 *       off: the game's own limiter at 1/120 s and the screen's vsync, no
 *       fix: the timing of this port before this file.
 *       PACE60=1 (the old 60 Hz limiter) is NFSU2_FPS=60 when NFSU2_FPS is
 *       not set.
 *   NFSU2_CUTSCENES_60 = 1     race intros and other NIS scenes at 60 instead
 *                              of the game's 30 (never above the chosen rate;
 *                              above 60 the intro camera goes wrong)
 *   NFSU2_HFR_FIX = default | all | none | comma list of
 *       ticks,timer,particles,trail,audio,rtf,rain,spinners; a '-' prefix
 *       removes one ("default,-audio").  default = all above 60 fps, none at
 *       60 (60 stays the original game), all but audio and rtf at 30 (they
 *       only act above 60).
 *       With auto the set follows the rate when the window moves to a screen
 *       with another refresh rate.
 *   NFSU2_NOS_TRAIL_LEN = x    NOS / streak trail length factor (default 1)
 *   NFSU2_HFR_LOG = 1 | 2      one [hfr] line per second of racing (2: of
 *                              every frame, menus too)
 *   NFSU2_DISPLAY_HZ = <hz>    the screen's refresh rate for auto (tests)
 *   NFSU2_PRESENT_MINDUR = 0   no presentDrawable:afterMinimumDuration: (A/B)
 *
 * Fixes (each one independent):
 *   ticks      exact ticks: a 1/3600 s tick base instead of 1/1800, so every
 *              supported rate is a whole number of ticks; the count comes
 *              from the pacer's slots
 *   timer      fractional carry for RealTimer / WorldTimer (1/4000 s units)
 *   particles  the "Acid" effect step: the frame's real dt (at most 1/60 s,
 *              1/30 at 30 fps) instead of a constant 1/60
 *   trail      NOS / streak trail sampled every frame, its history resampled
 *              to the 1/60 s spacing of the original
 *   audio      EAXSound::Update: dt carried across its 15 ms gate
 *   rtf        RealTimeFrames without the forced minimum of one a frame
 *   rain       Rain::Update on every frame, its per-call steps scaled to time
 *   spinners   the front end's spinning wheels turn by time, not per frame
 *
 * The fixes for particles, trail, rtf and cutscenes overlap with iburakct's
 * high-FPS work for this repository (PR #10), which follows ThirteenAG's
 * NFSU2 Widescreen Fix (MIT); the call site of the particle step is from
 * there.  Addresses are the European v1.2 ones (GA() maps them for the North
 * American build), each checked against both executables.
 *
 * Ported from th0mk's nfsu2-web runtime/framerate.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <time.h>
#include <pthread.h>
#include <stdatomic.h>

void guest_sleep_ns(long ns);           /* win32_ext.c: sleeps with the guest lock released */
int  metal_display_hz(void);            /* metal.m: the window's screen, maximum fps */

enum { FX_TICKS = 1, FX_TIMER = 2, FX_PARTICLES = 4, FX_TRAIL = 8, FX_AUDIO = 16, FX_RTF = 32,
       FX_RAIN = 64, FX_SPIN = 128, FX_ALL = 255, FX_N = 8 };
static const char *const g_fx_name[FX_N] = { "ticks", "timer", "particles", "trail", "audio", "rtf", "rain", "spinners" };

#define M_OFF      (-1)
#define M_AUTO     (-3)

/* ---- game addresses (European v1.2) ------------------------------------- */
#define A_FLOW        GA(0x008654a4u)   /* GameFlowManager state, 6 = racing */
#define A_CAP         GA(0x00865558u)   /* minimum frame time (the game's request) */
#define A_CAP_DEF     GA(0x007fb710u)   /* default request, 1/120 */
#define A_PLAYBACK    GA(0x008650ccu)   /* JoyLog playback active */
#define A_CARRY       GA(0x00865144u)   /* FrameTimeUpdate carry (1/4000 domain) */
#define A_TICKS       GA(0x0086513cu)   /* ticks this frame */
#define A_REALDT      GA(0x00865194u)   /* real dt (s) = ticks * [A_TICK_S] */
#define A_WORLDDT     GA(0x00865150u)   /* world dt (s), read by 0x57a0f0 */
#define A_TICK_HZ     GA(0x007a0624u)   /* 1800.0 */
#define A_TICK_4K     GA(0x007a0ab0u)   /* 4000/1800 */
#define A_TICK_S      GA(0x007a0620u)   /* 1/1800 */
#define A_RT_CARRY    GA(0x00865140u)   /* RealTimeFrames carry */
#define A_RTF         GA(0x007fb708u)   /* RealTimeFrames (60 Hz units) */
#define A_RTF_COPY    GA(0x007fb704u)
#define A_RTF_TICK    GA(0x007fb70cu)   /* RealTimeFrames this tick */
#define A_SIXTY       GA(0x00787590u)   /* 60.0 */
#define A_REALTIMER   GA(0x008651a8u)   /* RealTimer, 1/4000 s */
#define A_WORLDTIMER  GA(0x00865188u)   /* WorldTimer, 1/4000 s */
#define A_WORLD_S     GA(0x007fb718u)   /* WorldTimer in seconds (float) */
#define A_WTF         GA(0x007fb720u)   /* WorldTimeFrames */
#define A_U4000       GA(0x00784268u)   /* 1/4000 */
#define A_FRAMECNT    GA(0x00870818u)   /* eFrameCounter (render) */
#define A_STREAK_FC   GA(0x008a44ecu)   /* UpdateCarStreakingFlares: last frame */
#define A_CARLIST     GA(0x00890080u)   /* car list head (sentinel) */
#define A_SND_ON      GA(0x007faaa8u)
#define A_SND_PAUSE   GA(0x0082b8dcu)
#define A_PART_SYS    GA(0x00835860u)   /* the effect system eDisplayFrame steps */

#define TICK_HZ   3600              /* tick base with the ticks fix */
#define TICK_MAX  180               /* 50 ms, the game's largest dt */

/* ---- options ------------------------------------------------------------ */
static int    g_mode = M_AUTO;      /* M_OFF, M_AUTO or a fixed rate */
static int    g_fix = 0;            /* fixes in effect (fixes_follow_rate) */
static int    g_fix_hi = 0, g_fix_lo = 0, g_fix_30 = 0;   /* NFSU2_HFR_FIX above 60 fps, at 60, at 30 */
static double g_trail_len = 1.0;
static int    g_log = 0;
static int    g_resolved = 0;
static int    g_cutscenes60;
static double g_rt_carry = 0, g_wt_carry = 0;   /* timer fix: RealTimer / WorldTimer fractions */

static uint64_t mono_ns(void){ return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
static int display_hz(void){
    static int forced = -1;
    if (forced < 0){ const char *e = getenv("NFSU2_DISPLAY_HZ"); forced = e && *e ? atoi(e) : 0; }
    return forced > 0 ? forced : metal_display_hz();
}
/* the supported rate for a refresh rate */
static int rate_for_hz(int hz){
    if (hz >= 239) return 240;
    if (hz >= 119) return 120;
    if (hz > 0 && hz <= 31) return 30;
    return 60;
}
static void parse_mode(void){
    const char *e = getenv("NFSU2_FPS");
    if (!e || !*e){
        const char *p = getenv("PACE60");
        g_mode = p && *p && *p != '0' ? 60 : M_AUTO;
        return;
    }
    if (!strcasecmp(e, "auto")) g_mode = M_AUTO;
    else if (!strcasecmp(e, "off")) g_mode = M_OFF;
    else {
        int v = atoi(e);
        if (v == 30 || v == 60 || v == 120 || v == 240) g_mode = v;
        else { fprintf(stderr, "[hfr] NFSU2_FPS=%s not supported (auto|30|60|120|240|off): auto\n", e);
               g_mode = M_AUTO; }
    }
}
/* the mode's own rate (before the game's 30 fps requests); 120 = the game's
 * own limit when off */
static int mode_rate(void){
    if (g_mode == M_AUTO) return rate_for_hz(display_hz());
    if (g_mode == M_OFF) return 120;
    return g_mode;
}
static const char *mode_name(void){
    return g_mode == M_OFF ? "off" : g_mode == M_AUTO ? "auto" : "fixed";
}
/* the fix set for a mode rate above 60 when def = FX_ALL, for 60 when
 * def = 0, for 30 when def = FX_30 */
#define FX_30 (FX_TICKS | FX_TIMER | FX_PARTICLES | FX_TRAIL | FX_RAIN | FX_SPIN)
static int parse_fix(int def, int warn){
    const char *e = getenv("NFSU2_HFR_FIX");
    if (!e || !*e) return def;
    int f = 0;
    char buf[256]; snprintf(buf, sizeof buf, "%s", e);
    for (char *t = strtok(buf, ", "); t; t = strtok(0, ", ")){
        int neg = *t == '-'; if (neg || *t == '+') t++;
        int bit = 0;
        if (!strcasecmp(t, "all")) bit = FX_ALL;
        else if (!strcasecmp(t, "none")) { f = 0; continue; }
        else if (!strcasecmp(t, "default")) bit = def;
        else for (int i = 0; i < FX_N; i++) if (!strcasecmp(t, g_fx_name[i])) bit = 1 << i;
        if (!bit && strcasecmp(t, "default")){
            if (warn) fprintf(stderr, "[hfr] NFSU2_HFR_FIX: unknown fix '%s'\n", t);
            continue; }
        f = neg ? (f & ~bit) : (f | bit);
    }
    return f;
}
static void fix_str(int f, char *out, size_t n){
    out[0] = 0;
    for (int i = 0; i < FX_N; i++) if (f & (1 << i)){
        size_t l = strlen(out); snprintf(out + l, n - l, "%s%s", l ? "," : "", g_fx_name[i]); }
    if (!out[0]) snprintf(out, n, "none");
}
static int fix_for_rate(int r){ return r > 60 ? g_fix_hi : r <= 30 ? g_fix_30 : g_fix_lo; }

/* Tick base 1/3600 s: 30, 60, 120 and 240 fps are 120, 60, 30 and 15 whole
 * ticks, so every supported rate gets dt = exactly 1/rate and the car
 * substep 1/240 s.  The three constants are read only by FrameTimeUpdate
 * (0x57eae0) and the replay tick conversion (0x576cf0).  The JoyLog 8-bit
 * tick field still fits (180 at the 50 ms maximum).  1800 Hz (the game's)
 * cannot express 240 fps. */
static void set_tick_base(int on){
    static int saved = 0;
    static float van[3];            /* the game's own 1/1800 base */
    if (!saved){ saved = 1; van[0] = MRF32(A_TICK_HZ); van[1] = MRF32(A_TICK_4K); van[2] = MRF32(A_TICK_S); }
    MRF32(A_TICK_HZ) = on ? (float)TICK_HZ : van[0];
    MRF32(A_TICK_4K) = on ? (float)(4000.0 / TICK_HZ) : van[1];
    MRF32(A_TICK_S)  = on ? (float)(1.0 / TICK_HZ) : van[2];
}

static void resolve_once(void){
    parse_mode();
    { const char *e = getenv("NFSU2_CUTSCENES_60"); g_cutscenes60 = e && !strcmp(e, "1"); }
    g_fix_hi = g_mode == M_OFF ? 0 : parse_fix(FX_ALL, 1);
    g_fix_lo = g_mode == M_OFF ? 0 : parse_fix(0, 0);
    g_fix_30 = g_mode == M_OFF ? 0 : parse_fix(FX_30, 0);
    g_fix = fix_for_rate(mode_rate());
    { const char *e = getenv("NFSU2_NOS_TRAIL_LEN"); if (e && *e) g_trail_len = atof(e);
      if (!(g_trail_len > 0.05 && g_trail_len < 20.0)) g_trail_len = 1.0; }
    { const char *e = getenv("NFSU2_HFR_LOG"); g_log = e && *e ? atoi(e) : 0; }
    char fs[96]; fix_str(g_fix, fs, sizeof fs);
    fprintf(stderr, "[hfr] mode %s, display %d Hz, rate %d, fixes: %s, 60 FPS cutscenes: %s\n",
            mode_name(), display_hz(), mode_rate(), fs, g_cutscenes60 ? "on" : "off");
    g_resolved = 1;
}
/* first use may come from the main thread (present) or the guest */
static void resolve(void){
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, resolve_once);
}

int hfr_mode_off(void){ resolve(); return g_mode == M_OFF; }

/* ---- the current rate ---------------------------------------------------
 * The game's own request in [0x865558]: 1/120 by default (= the mode's
 * rate), 1/30 in NIS scenes.  Requests only lower the rate: the default
 * 1/120 must not cap 240. */
static _Atomic int g_rate_now = 0;
static int content_rate(void){
    int m = mode_rate();
    float cap = MRF32(A_CAP);
    if (cap > 0.f && cap != MRF32(A_CAP_DEF)){
        int req = (int)lround(1.0 / (double)cap);
        if (req == 30 && g_cutscenes60) req = 60;
        if (req >= 10 && req < m) m = req;
    }
    return m;
}
/* fps = 30, or auto on a 30 Hz screen, outside the game's own 30 fps
 * requests (a cutscene runs at 30 in every mode and keeps the effects it
 * has there at 60): a frame is two of 60, so the effects stepped once a
 * frame step for both */
static int at_30(void){
    float cap = MRF32(A_CAP);
    return mode_rate() == 30 && !(cap > 0.f && cap != MRF32(A_CAP_DEF));
}
int hfr_rate_now(void){ return atomic_load(&g_rate_now); }
/* metal_present: replace a frame the screen has not shown yet instead of
 * waiting for it, when the rate is above the screen's (240 on a 120 Hz
 * screen, 120 on a 60 Hz one): the game keeps its rate, the screen shows
 * what it can. */
int hfr_mailbox(void){
    int r = atomic_load(&g_rate_now), hz = display_hz();
    return r > 0 && hz > 0 && r > hz + 1;
}
/* presentDrawable:afterMinimumDuration: for the main thread, 0 = none.  Half
 * a refresh less than the frame period: 60 fps on a 120 Hz screen holds every
 * frame for two refreshes, and a refresh a hair faster than nominal cannot
 * push a frame one refresh too far. */
double hfr_present_min_duration(void){
    static int off = -1;
    if (off < 0){ const char *e = getenv("NFSU2_PRESENT_MINDUR"); off = e && *e == '0'; }
    if (off) return 0.0;
    int r = atomic_load(&g_rate_now);
    int hz = display_hz();
    if (r <= 0 || hz <= 0) return 0.0;
    double d = 1.0 / r - 0.5 / hz;
    return d > 0.0005 ? d : 0.0;
}
/* virtual clock (win32.c vclock_tick): the smallest step a frame.  4 ms
 * caps at 250 fps; at 240 frames often come in under 4 ms and game time
 * would run fast. */
uint64_t hfr_vclock_floor_us(void){
    if (g_mode != M_OFF && atomic_load(&g_rate_now) > 200) return 1000u;
    return 4000u;
}

/* ---- statistics (NFSU2_HFR_LOG and the exit report) ---------------------
 * Counted are the frames of a race (GameFlow 6), or all with LOG=2.  At any
 * rate, with the fixes on, these per wall-clock second stay as at 60:
 * sim/wall and real/wall 1.0, rtf 60/s, particles 1.0 s/s, trail 0.033 s
 * (the time the player's NOS trail spans: its length / the car's speed). */
typedef struct {
    uint64_t frames, slots, missed, sleep_ns, work_ns;
    double   sim_s, real_s, wall_s;
    uint64_t rtf, wtf, rtimer, wtimer;
    uint64_t au_upd; double au_dt;
    double   part_s;
    uint64_t trail_samples;
    double   span_s; uint64_t span_n;
} Stat;
static Stat g_tot, g_sec;
static uint64_t g_sec_t0;
static uint64_t g_sleep_all_ns = 0;
uint64_t hfr_paced_sleep_us(void){ return g_sleep_all_ns / 1000u; }

/* ---- the pacer ------------------------------------------------------------
 * Slots of the frame period: a frame that is early sleeps to the start of
 * the slot after its predecessor's and takes that slot; a late frame takes
 * the last slot boundary it passed and the missed slots are dropped (no
 * burst to catch up).  The game's dt is the number of slots times the
 * period, so game time follows the wall clock to within one slot whatever
 * the frame times are.  The screen's vsync (the present waits for a
 * drawable) still holds back a frame the screen cannot take yet; then the
 * pacer finds it late and gives it two slots. */
static int64_t g_last_slot = 0;     /* start of the previous frame's slot, ns */
static int pace(int rate, uint64_t *slept, uint64_t *missed){
    int64_t now = (int64_t)mono_ns();
    *slept = 0; *missed = 0;
    int64_t P = (int64_t)llround(1e9 / rate);
    if (!g_last_slot || now - g_last_slot > 4 * 1000000000ll){     /* first frame, or after a load */
        g_last_slot = now;
        return 1;
    }
    int64_t target = g_last_slot + P;
    if (now < target){
        guest_sleep_ns((long)(target - now));
        *slept = (uint64_t)(target - now);
        g_last_slot = target;
        return 1;
    }
    int64_t n = (now - g_last_slot) / P; if (n < 1) n = 1;
    *missed = (uint64_t)(n - 1);
    g_last_slot += n * P;
    return (int)n;
}

static void stat_add(Stat *d, const Stat *s){
    d->frames += s->frames; d->slots += s->slots; d->missed += s->missed;
    d->sleep_ns += s->sleep_ns; d->work_ns += s->work_ns;
    d->sim_s += s->sim_s; d->real_s += s->real_s; d->wall_s += s->wall_s;
    d->rtf += s->rtf; d->wtf += s->wtf; d->rtimer += s->rtimer; d->wtimer += s->wtimer;
    d->au_upd += s->au_upd; d->au_dt += s->au_dt; d->part_s += s->part_s;
    d->trail_samples += s->trail_samples; d->span_s += s->span_s; d->span_n += s->span_n;
}
static void stat_line(const char *tag, const Stat *s){
    double w = s->wall_s > 0 ? s->wall_s : 1e-9;
    fprintf(stderr, "[hfr] %s wall=%.2fs fps=%.2f slots/f=%.3f miss=%llu sim/wall=%.4f real/wall=%.4f "
            "realtimer/real=%.4f worldtimer/sim=%.4f rtf=%.2f/s wtf=%.2f/s audio=%.1fupd/s,%.3fs/s "
            "particles=%.3fs/s trail=%.1f/s,span %.4fs work=%.2fms/f sleep=%.2fms/f\n",
            tag, s->wall_s, s->frames / w, s->frames ? (double)s->slots / s->frames : 0.0,
            (unsigned long long)s->missed, s->sim_s / w, s->real_s / w,
            s->real_s > 0 ? s->rtimer / 4000.0 / s->real_s : 0.0,
            s->sim_s > 0 ? s->wtimer / 4000.0 / s->sim_s : 0.0,
            s->rtf / w, s->wtf / w, s->au_upd / w, s->au_dt / w, s->part_s / w,
            s->trail_samples / w, s->span_n ? s->span_s / s->span_n : 0.0,
            s->frames ? s->work_ns / 1e6 / s->frames : 0.0,
            s->frames ? s->sleep_ns / 1e6 / s->frames : 0.0);
}

/* The frame being measured runs from one FrameTimeUpdate's pacer wake-up to
 * the next: the work of one main-loop iteration plus the pacer's sleep. */
static struct {
    uint64_t t, work;               /* start (after the pacer), work time */
    int      slots;
    uint32_t rt0, wt0, rtf0, wtf0;
    double   wdt, au_dt, part;
    uint64_t au_upd, trail;
} g_f;
/* the player's NOS / streak trail: the time it spans, i.e. the distance from
 * its newest to its oldest ring entry over the car's speed (car+0x430, the
 * same unit a frame: only the ratio between rates matters) */
static double trail_span_s(void){
    uint32_t w = MR32(A_CARLIST), nw = w && mem_is_committed(w + 0x2f) ? MR32(w + 0x10) : 0;
    uint32_t c0 = nw ? MR32(w + 0x1c) : 0;
    if (!c0 || !mem_is_committed(c0 + 0x557)) return -1;
    double v = MRF32(c0 + 0x430);
    uint32_t r = MR32(c0 + 0x554);
    if (!(v > 5.0) || !r || !mem_is_committed(r + 0x2183)) return -1;
    uint32_t i = MR32(r + 0x2180);
    if (i >= 3) return -1;
    uint32_t a = r + 0x2150 + i * 16u, b = r + 0x2150 + ((i + 1) % 3) * 16u;
    double dx = MRF32(a) - MRF32(b), dy = MRF32(a + 4) - MRF32(b + 4), dz = MRF32(a + 8) - MRF32(b + 8);
    return sqrt(dx * dx + dy * dy + dz * dz) / v;
}
/* closes the previous frame at `now` (after the pacer) */
static void frame_close(uint64_t now, uint64_t sleep, uint64_t missed){
    if (!g_f.t) return;
    int racing = MR32(A_FLOW) == 6u;
    if (racing || g_log == 2){
        Stat f; memset(&f, 0, sizeof f);
        f.frames = 1; f.slots = (uint64_t)g_f.slots; f.missed = missed;
        f.sleep_ns = sleep; f.work_ns = g_f.work;
        f.wall_s = (now - g_f.t) / 1e9;
        f.real_s = MRF32(A_REALDT);
        f.sim_s  = g_f.wdt;
        f.rtimer = MR32(A_REALTIMER) - g_f.rt0; f.wtimer = MR32(A_WORLDTIMER) - g_f.wt0;
        f.rtf = MR32(A_RTF) - g_f.rtf0; f.wtf = MR32(A_WTF) - g_f.wtf0;
        f.au_upd = g_f.au_upd; f.au_dt = g_f.au_dt; f.part_s = g_f.part; f.trail_samples = g_f.trail;
        if (racing){ double sp = trail_span_s(); if (sp >= 0 && sp < 1){ f.span_s = sp; f.span_n = 1; } }
        stat_add(&g_sec, &f);
    }
    if (!g_sec_t0) g_sec_t0 = now;
    if (now - g_sec_t0 >= 1000000000ull){
        if (g_sec.frames){
            if (g_log) stat_line("1s", &g_sec);
            stat_add(&g_tot, &g_sec);
        }
        memset(&g_sec, 0, sizeof g_sec);
        g_sec_t0 = now;
    }
}
static void frame_open(uint64_t now, int slots){
    memset(&g_f, 0, sizeof g_f);
    g_f.t = now; g_f.slots = slots;
    g_f.rt0 = MR32(A_REALTIMER); g_f.wt0 = MR32(A_WORLDTIMER);
    g_f.rtf0 = MR32(A_RTF); g_f.wtf0 = MR32(A_WTF);
}

/* The fix set follows the mode's rate at a frame boundary: auto changes the
 * rate when the window moves to a screen with another refresh rate, and a
 * game that started on a 60 Hz screen needs the fixes once it runs at 120
 * (and is the original again back at 60). */
static void fixes_follow_rate(void){
    static int first = 1;
    int r = mode_rate(), fx = fix_for_rate(r);
    if (!first && fx != g_fix){
        char a[96], b[96]; fix_str(g_fix, a, sizeof a); fix_str(fx, b, sizeof b);
        fprintf(stderr, "[hfr] display %d Hz: rate %d, fixes %s -> %s\n", display_hz(), r, a, b);
    }
    if (!first && fx == g_fix) return;
    if (first || ((fx ^ g_fix) & FX_TICKS)) set_tick_base(fx & FX_TICKS);
    if ((fx ^ g_fix) & FX_TIMER){ g_rt_carry = 0; g_wt_carry = 0; }
    g_fix = fx; first = 0;
}

/* ---- ticks: FrameTimeUpdate 0x57eae0 (limiter, clamp, tick quantiser) ---
 * cdecl, [esp+4] = work time since the previous limiter (s).  The original
 * waits until [0x865558] has passed (SPINSLEEP in win32.c sleeps there),
 * adds the wait to dt (overshoot is discarded), clamps to [cap, 50 ms] and
 * quantises to 1/1800 s ticks with a mixed-domain carry: +1.33 % game speed
 * when the limiter binds at 1/120, and 15/16/14-tick jitter.
 *
 * Here the pacer does the waiting (guest lock released) and the original
 * runs with its limiter disarmed:
 *   ticks fix: dt = T/3600 with T the exact slot count in ticks, carry 0,
 *     cap 0.  The original then computes ticks = T itself, so a JoyLog
 *     recording gets the same ticks the game uses.
 *   without:   dt = slots x period, cap = period: the game's quantiser in
 *     its limiter-bound state (exactly 30 ticks a frame at 60).
 * JoyLog playback ([0x8650cc]) keeps its recorded tick stream. */
void sub_0057eae0_orig(CPU *c);
uint64_t spin_slept_us(void);           /* win32.c: SPINSLEEP sleep inside the game's limiter */
static void fe_spinners(void);
static double g_tick_acc = 0;
void sub_0057eae0(CPU *c){
    resolve();
    if (g_mode == M_OFF){
        /* the original timing: the game's own limiter inside the original;
         * only the bookkeeping around it */
        uint64_t t_in = mono_ns();
        if (g_f.t) g_f.work = t_in - g_f.t;
        uint64_t sl0 = spin_slept_us();
        sub_0057eae0_orig(c);
        uint64_t now = mono_ns();
        frame_close(now, (spin_slept_us() - sl0) * 1000u, 0);
        frame_open(now, 1);
        return;
    }
    fixes_follow_rate();
    uint64_t t_in = mono_ns();
    if (g_f.t) g_f.work = t_in - g_f.t;

    int rate = content_rate();
    int prev = atomic_exchange(&g_rate_now, rate);
    if (prev && prev != rate){
        long metal_frames(void);
        fprintf(stderr, "[hfr] rate %d -> %d at frame %ld (%s)\n", prev, rate, metal_frames(),
                rate < mode_rate() ? "the game asks for it: a cutscene" : "the chosen rate");
    }
    uint64_t slept = 0, missed = 0;
    int slots = pace(rate, &slept, &missed);
    double frame_s = (double)slots / rate;
    g_sleep_all_ns += slept;
    uint64_t now = mono_ns();
    frame_close(now, slept, missed);
    frame_open(now, slots);

    if (MR32(A_PLAYBACK)){ sub_0057eae0_orig(c); fe_spinners(); return; }
    float cap = MRF32(A_CAP);
    if (g_fix & FX_TICKS){
        g_tick_acc += frame_s * TICK_HZ;
        double t = floor(g_tick_acc + 0.5);
        g_tick_acc -= t;
        if (t > TICK_MAX){ t = TICK_MAX; g_tick_acc = 0; }   /* the game's 50 ms max dt: slow down, no catch-up */
        if (t < 0) t = 0;
        MRF32(c->esp + 4u) = (float)(t / TICK_HZ);
        MRF32(A_CARRY) = 0.f;
        MRF32(A_CAP) = 0.f;
        sub_0057eae0_orig(c);
        MRF32(A_CARRY) = 0.f;
    } else {
        double p = 1.0 / rate;
        MRF32(c->esp + 4u) = (float)frame_s;
        MRF32(A_CAP) = (float)(p < frame_s ? p : frame_s);
        sub_0057eae0_orig(c);
    }
    MRF32(A_CAP) = cap;
    fe_spinners();
}

/* ---- rtf + timer: RealTimer advance 0x57a060 ----------------------------
 * n = trunc(60 (dt + carry)), carry -= n/60, then "if (n == 0) n = 1"
 * (the jne at 0x57a094): one RealTimeFrame per rendered frame below 1/60 s
 * frame times, twice the count at 120.  The carry was already computed with
 * n = 0, so undoing the forced 1 leaves the game's own exact 60 Hz count
 * (what #10 does by turning the jne into a jmp).  RealTimer += round(dt x
 * 4000) has no carry: 15/1800 s -> 33 units (-1 %); the timer fix carries
 * the fraction. */
void sub_0057a060_orig(CPU *c);
void sub_0057a060(CPU *c){
    float dt = MRF32(A_REALDT), carry0 = MRF32(A_RT_CARRY);
    uint32_t frames0 = MR32(A_RTF), timer0 = MR32(A_REALTIMER);
    sub_0057a060_orig(c);
    if (g_fix & FX_RTF){
        int n0 = (int)(((double)dt + (double)carry0) * (double)MRF32(A_SIXTY));
        if (n0 == 0 && MR32(A_RTF_TICK) == 1u){
            MR32(A_RTF_TICK) = 0; MR32(A_RTF) = frames0; MR32(A_RTF_COPY) = frames0;
        }
    }
    if (g_fix & FX_TIMER){
        double ex = (double)dt * 4000.0 + g_rt_carry;
        double u = floor(ex + 0.5);
        g_rt_carry = ex - u;
        MR32(A_REALTIMER) = timer0 + (uint32_t)(int32_t)u;
    }
}

/* ---- timer: WorldTimer advance 0x57a0f0 (skipped while world dt == 0) --- */
void sub_0057a0f0_orig(CPU *c);
void sub_0057a0f0(CPU *c){
    float wdt = MRF32(A_WORLDDT);
    uint32_t w0 = MR32(A_WORLDTIMER);
    sub_0057a0f0_orig(c);
    if (wdt == 0.f) return;
    g_f.wdt += wdt;
    if (g_fix & FX_TIMER){
        double ex = (double)wdt * 4000.0 + g_wt_carry;
        double u = floor(ex + 0.5);
        g_wt_carry = ex - u;
        MR32(A_WORLDTIMER) = w0 + (uint32_t)(int32_t)u;
        MRF32(A_WORLD_S) = (float)((double)(int32_t)MR32(A_WORLDTIMER) * (double)MRF32(A_U4000));
    }
}

/* ---- particles: the "Acid" effect update, call at 0x5d2c27 ---------------
 * eDisplayFrame pushes a constant 1/60 (0x5d2c1d) for the system at
 * 0x835860 and calls its update (0x492e10, __thiscall, [esp] = the step here
 * at the call) once per rendered frame: smoke, sparks and flames age twice as
 * fast at 120.  The step becomes the frame's real dt, never more than the
 * original 1/60: at 60 and in the 30 fps cutscenes the argument is the
 * game's own.  At fps = 30 they would age at half speed: there the step is
 * the real dt up to 1/30 (the emitters' countdowns take it as time too).
 * Hook site from #10. */
int hfr_hook(CPU *c, uint32_t ip){
    if (ip != GA(0x005d2c27u)) return 0;
    if (c->ecx == A_PART_SYS){
        float k = MRF32(c->esp);
        if (g_fix & FX_PARTICLES){
            float dt = MRF32(A_REALDT), hi = at_30() ? 2.f * k : k;
            if (dt < k) MRF32(c->esp) = dt > 0.f ? dt : 0.f;
            else MRF32(c->esp) = dt < hi ? dt : hi;
        }
        g_f.part += MRF32(c->esp);
    }
    return 1;
}

/* ---- trail: UpdateCarStreakingFlares 0x61ad90 ----------------------------
 * cdecl(eView), once per rendered frame (it returns when [0x8a44ec] already
 * equals the frame counter [0x870818]), it pushes every visible car's matrix
 * and position into a 3-entry ring (index car ring +0x2180, matrices
 * +0x2090, positions +0x2150); the renderer draws the NOS trail between the
 * ring entries.  At 120 fps the ring spans 2/120 s instead of 2/60: half the
 * length.  Recording only every 1/60 s instead (the Widescreen Fix, #10)
 * makes the length right but the trail's head then lags the car on the
 * frames in between.  Here the game still records every frame (the head
 * stays on the car) and the two older entries are replaced by this car's
 * position 1/60 s and 2/60 s ago (x NFSU2_NOS_TRAIL_LEN), from its recent
 * samples.  At 60 fps those are exactly the game's own entries; at 30 the
 * 1/60 s one is halfway between two frames (the original trail at 30 is
 * twice as long). */
void sub_0061ad90_orig(CPU *c);
#define TR_CARS 16
#define TR_HIST 24
#define TR_GAP  0.1                 /* s without a sample: the history is stale */
typedef struct { uint32_t ring; int n, head; double t[TR_HIST];
                 uint8_t m[TR_HIST][64]; uint8_t p[TR_HIST][16]; } TrailHist;
static TrailHist g_tr[TR_CARS];
static double    g_tr_time = 0;
static TrailHist *trail_of(uint32_t ring){
    int free_i = -1;
    for (int i = 0; i < TR_CARS; i++){
        if (g_tr[i].ring == ring) return &g_tr[i];
        if (!g_tr[i].ring && free_i < 0) free_i = i;
    }
    if (free_i < 0){ free_i = (int)(ring >> 4) % TR_CARS; }
    memset(&g_tr[free_i], 0, sizeof g_tr[free_i]);
    g_tr[free_i].ring = ring;
    return &g_tr[free_i];
}
/* the car's matrix and position at time t into the ring entry at m / p:
 * the newest sample at t or older, blended with the next newer one by time
 * (at 30 fps the 1/60 s point lies halfway between two frames; at 60 and
 * above it is a sample of its own).  0 = no sample that old yet. */
static int trail_at(const TrailHist *h, double t, uint32_t m, uint32_t p){
    int j = -1;                     /* the next newer sample */
    for (int k = 0; k < h->n; k++){
        int i = (h->head - k + TR_HIST) % TR_HIST;
        if (h->t[i] <= t + 1e-4){
            float w = 0.f, a, b;
            if (j >= 0 && t > h->t[i] + 1e-4 && h->t[j] > h->t[i])
                w = (float)((t - h->t[i]) / (h->t[j] - h->t[i]));
            for (int q = 0; q < 16; q++){
                memcpy(&a, h->m[i] + 4 * q, 4);
                if (w > 0.f){ memcpy(&b, h->m[j] + 4 * q, 4); a += (b - a) * w; }
                MRF32(m + 4u * (uint32_t)q) = a;
            }
            for (int q = 0; q < 4; q++){
                memcpy(&a, h->p[i] + 4 * q, 4);
                if (w > 0.f){ memcpy(&b, h->p[j] + 4 * q, 4); a += (b - a) * w; }
                MRF32(p + 4u * (uint32_t)q) = a;
            }
            return 1;
        }
        j = i;
    }
    return 0;
}
void sub_0061ad90(CPU *c){
    static int on = 0;
    if (!(g_fix & FX_TRAIL)){ on = 0; sub_0061ad90_orig(c); return; }
    if (!on){ on = 1; memset(g_tr, 0, sizeof g_tr); }      /* (re)enabled: no history from before */
    if (MR32(A_FRAMECNT) == MR32(A_STREAK_FC)){ sub_0061ad90_orig(c); return; }
    /* first call this rendered frame: the trail clock advances by the real
     * frame dt (split screen calls once per eView: only the first counts) */
    float dt = MRF32(A_REALDT);
    g_tr_time += dt > 0.f && dt < 0.25f ? dt : 0.0;
    uint32_t rings[TR_CARS]; int idx0[TR_CARS], nc = 0;
    uint32_t head = MR32(A_CARLIST);
    if (head && mem_is_committed(head + 3)){
        for (uint32_t e = MR32(head); e && e != head && nc < TR_CARS && mem_is_committed(e + 0x557); e = MR32(e)){
            uint32_t r = MR32(e + 0x554);
            if (!r || !mem_is_committed(r + 0x2183)) continue;
            rings[nc] = r; idx0[nc] = (int)MR32(r + 0x2180); nc++;
        }
    }
    sub_0061ad90_orig(c);
    double back = g_trail_len / 60.0;
    for (int i = 0; i < nc; i++){
        uint32_t r = rings[i];
        int idx = (int)MR32(r + 0x2180);
        if (idx == idx0[i] || idx < 0 || idx > 2) continue;      /* not recorded this frame */
        g_f.trail++;
        TrailHist *h = trail_of(r);
        /* A car that was not recorded for a while (culled, off screen) has a
         * history that ends where it was then, hundreds of metres away in
         * traffic: start afresh, so the game's own entries are used until
         * 1/60 s of new samples exists. */
        if (h->n && g_tr_time - h->t[h->head] > TR_GAP) h->n = 0;
        h->head = (h->head + 1) % TR_HIST; if (h->n < TR_HIST) h->n++;
        h->t[h->head] = g_tr_time;
        memcpy(h->m[h->head], g_mem + r + 0x2090 + (uint32_t)idx * 64u, 64);
        memcpy(h->p[h->head], g_mem + r + 0x2150 + (uint32_t)idx * 16u, 16);
        uint32_t prev = (uint32_t)(idx + 2) % 3u, old = (uint32_t)(idx + 1) % 3u;
        if (!trail_at(h, g_tr_time - back, r + 0x2090 + prev * 64u, r + 0x2150 + prev * 16u)) continue;
        trail_at(h, g_tr_time - 2.0 * back, r + 0x2090 + old * 64u, r + 0x2150 + old * 16u);
    }
}

/* ---- audio: EAXSound::Update 0x483b40 ------------------------------------
 * __thiscall(ecx = audio manager, [esp+4] = real dt), ret 4.  It returns
 * unless more than 15 ms ([0x787af4], a shared constant) of QPC time passed
 * since [this+0xa4], then hands its single frame dt to the 9 slot objects:
 * engine pitch and gear-shift sound logic ran at half speed at 120 fps.  The
 * dt of gated calls is carried into the next real update (at most 0.25 s, the
 * idea of dstudnicki's NFSU2HighFPSAudioFix),
 * passed through untouched when sound is off or paused and for dt = 0 calls,
 * and the carry is reset when the manager object changes. */
void sub_00483b40_orig(CPU *c);
static uint32_t g_au_this = 0;
static double   g_au_carry = 0;
void sub_00483b40(CPU *c){
    uint32_t self = c->ecx;
    float dt = MRF32(c->esp + 4u);
    if (self != g_au_this){ g_au_this = self; g_au_carry = 0; }
    int ok = self && mem_is_committed(self + 0xa7) && MR32(A_SND_ON) && !MR32(A_SND_PAUSE);
    if (!ok || dt <= 0.f){ if (dt > 0.f) g_au_carry = 0; sub_00483b40_orig(c); return; }
    int active = !MR8(self + 0x13);
    uint32_t stamp = MR32(self + 0xa4);
    double d2 = dt;
    if ((g_fix & FX_AUDIO) && active){
        d2 = (double)dt + g_au_carry; if (d2 > 0.25) d2 = 0.25;
        MRF32(c->esp + 4u) = (float)d2;
    }
    sub_00483b40_orig(c);
    if (MR32(self + 0xa4) != stamp){ g_f.au_upd++; g_f.au_dt += active ? d2 : 0.0; g_au_carry = 0; }
    else g_au_carry = (g_fix & FX_AUDIO) && active ? d2 : 0.0;
}

/* ---- rain: Rain::Update 0x61f130 ------------------------------------------
 * __thiscall(ecx = the Rain at eView+0x64), once per frame in the world;
 * overrides.c (FORCERAIN) calls it through hfr_rain_update.  It returns at
 * once unless |world dt| > 9 ms ([0x7a873c], read only here), which is meant
 * for a world that stands but also skips every 1/120 s frame.  At 120 the
 * rain then ran only on frames that missed their slot, and only those frames
 * armed its screen tint (the main view's lighting): in rain the picture
 * jumped between tinted frames and ~20 % brighter ones, and the grey storm
 * sky flashed.  Here a frame shorter than 1/60 s (s = 60 dt < 1) runs it
 * too, with its per-call steps scaled to world time as at 60 fps (longer
 * frames run it untouched):
 *   a rain drop moves by its velocity (one of ten at Rain+0x5120) plus a
 *   per-type share of the wind (Rain+0x4d4c..+0x4d68) a call: x s; it also
 *   moves by -0.02 x the camera's velocity (camera +0x1e0, m/s), flattened
 *   and capped at length 1 a call, i.e. 50 m/s: for the call the rain sees
 *   that velocity capped at 50 m/s and x s, so the game's cap never acts and
 *   the share is s x the 60 fps one.  Its length (Rain+0x5090) lengthens
 *   every streak and is divided by s again afterwards;
 *   lens drops slide out by [0x803ac4] x the camera speed a call: the
 *   constant makes up for the cap, the s is in the velocity already;
 *   the cloud cover eases 5 % / 0.15 % a call towards its target
 *   ([0x7a67c8] / [0x7a67cc], read only here): 1 - (1 - f)^s.
 * All of it is put back after the call (a drop value only if the call did
 * not write it again).
 * At fps = 30 (s = 2) the rain would fall at half speed, and the camera's
 * share cannot be scaled up past the game's cap: the update runs twice
 * instead, each call a 60 fps frame with half the world dt. */
void sub_0061f130_orig(CPU *c);
#define A_RAIN_GATE   GA(0x007a873cu)   /* 0.009 s */
#define A_RAIN_EASE   GA(0x007a67c8u)   /* cloud easing a call: towards clear, +4 towards overcast */
#define A_RAIN_SLIDE  GA(0x00803ac4u)   /* lens drop slide per camera speed */
#define RAIN_WIND     0x4d4cu       /* Rain: 4 drop types x {wind share, half of it} */
#define RAIN_FALL     0x5120u       /* Rain: 10 drop velocities {x, y, z, -99999.9} */
#define RAIN_STRETCH  0x5090u       /* Rain: streak length added for the camera speed */
#define RAIN_VMAX     50.0          /* m/s: the game's cap, 1 / 0.02 */
void hfr_rain_update(CPU *c){
    uint32_t rain = c->ecx;
    double s = 60.0 * MRF32(A_WORLDDT);
    uint32_t view = rain && mem_is_committed(rain + RAIN_FALL + 0x9fu) ? MR32(rain + 0x1ecu) : 0;
    uint32_t cam = view && mem_is_committed(view + 0x43u) ? MR32(view + 0x40u) : 0;
    if ((g_fix & FX_RAIN) && s > 1.5 && at_30()){
        float wdt = MRF32(A_WORLDDT);
        uint32_t ret = MR32(c->esp);                         /* popped by the call: pushed again for the second */
        MRF32(A_WORLDDT) = wdt * 0.5f;
        sub_0061f130_orig(c);
        c->esp -= 4u; MR32(c->esp) = ret; c->ecx = rain;
        sub_0061f130_orig(c);
        MRF32(A_WORLDDT) = wdt;
        return;
    }
    if (!(g_fix & FX_RAIN) || !(s > 0.0 && s < 1.0) || !cam || !mem_is_committed(cam + 0x1ebu)){
        sub_0061f130_orig(c); return; }
    float gate = MRF32(A_RAIN_GATE), up = MRF32(A_RAIN_EASE), down = MRF32(A_RAIN_EASE + 4u);
    float slide = MRF32(A_RAIN_SLIDE), stretch = MRF32(rain + RAIN_STRETCH), old[38], v[3];
    uint32_t at[38], put[38];
    for (uint32_t i = 0; i < 8; i++) at[i] = rain + RAIN_WIND + 4u * i;
    for (uint32_t i = 0; i < 30; i++) at[8 + i] = rain + RAIN_FALL + 16u * (i / 3) + 4u * (i % 3);
    for (int i = 0; i < 38; i++){ old[i] = MRF32(at[i]); MRF32(at[i]) = (float)(old[i] * s); put[i] = MR32(at[i]); }
    double vl = 0;
    for (uint32_t i = 0; i < 3; i++){ v[i] = MRF32(cam + 0x1e0u + 4u * i); vl += (double)v[i] * v[i]; }
    vl = sqrt(vl);
    double cap = vl > RAIN_VMAX ? RAIN_VMAX / vl : 1.0;
    for (uint32_t i = 0; i < 3; i++) MRF32(cam + 0x1e0u + 4u * i) = (float)(v[i] * cap * s);
    MRF32(A_RAIN_SLIDE) = (float)(slide / cap);
    MRF32(rain + RAIN_STRETCH) = -1.f;                       /* not computed this call: stays -1 */
    MRF32(A_RAIN_GATE) = 0.f;
    MRF32(A_RAIN_EASE) = (float)(1.0 - pow(1.0 - up, s));
    MRF32(A_RAIN_EASE + 4u) = (float)(1.0 - pow(1.0 - down, s));
    sub_0061f130_orig(c);
    for (int i = 0; i < 38; i++) if (MR32(at[i]) == put[i]) MRF32(at[i]) = old[i];
    for (uint32_t i = 0; i < 3; i++) MRF32(cam + 0x1e0u + 4u * i) = v[i];
    float st = MRF32(rain + RAIN_STRETCH);
    MRF32(rain + RAIN_STRETCH) = st < 0.f ? stretch : (float)fmin(st / s, 1.0);
    MRF32(A_RAIN_GATE) = gate; MRF32(A_RAIN_EASE) = up; MRF32(A_RAIN_EASE + 4u) = down;
    MRF32(A_RAIN_SLIDE) = slide;
}

/* ---- spinners: the front end's spinning wheels ---------------------------
 * The front end's car renderer (garage, shops, car lot) turns spinners by a
 * constant 0.5 degree a call ([0x7a6684], read only there), twice a rendered
 * frame: 60 degrees a second at 60 fps, four times that at 240.  The world's
 * spinners turn by time.  After each FrameTimeUpdate the step becomes 0.5 x
 * 60 x the frame's real dt: 60 degrees a second at every rate, the game's
 * own 0.5 at 60. */
#define A_FE_SPIN     GA(0x007a6684u)   /* 0.5: degrees a front-end spinner turns a call */
static void fe_spinners(void){
    static float van = -1.f;
    if (van < 0.f) van = MRF32(A_FE_SPIN);
    float dt = MRF32(A_REALDT);
    MRF32(A_FE_SPIN) = (g_fix & FX_SPIN) && dt > 0.f ? (float)(van * 60.0 * dt) : van;
}

/* ---- exit report ------------------------------------------------------- */
void hfr_report(void){
    if (!g_resolved) return;
    if (g_sec.frames) stat_add(&g_tot, &g_sec), memset(&g_sec, 0, sizeof g_sec);
    char fs[96]; fix_str(g_fix, fs, sizeof fs);
    fprintf(stderr, "\n=== frame rate (framerate.c) ===\n");
    fprintf(stderr, "  mode %s, display %d Hz, rate %d, fixes %s, 60 FPS cutscenes %s\n",
            mode_name(), display_hz(), mode_rate(), fs, g_cutscenes60 ? "on" : "off");
    if (g_tot.frames) stat_line(g_log == 2 ? "all" : "race", &g_tot);
}
