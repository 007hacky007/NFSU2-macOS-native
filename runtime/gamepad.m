/* gamepad.m -- GameController.framework input for the virtual game pad
 * (runtime/gamepad.h), which runtime/dinput_pad.c presents to the game as a
 * DirectInput8 gamepad.  The keyboard keeps working next to it: the game ANDs
 * all its input channels together.
 *
 * The first connected controller with an extended gamepad profile drives the
 * pad; when it goes away the next connected one takes over (hot-plug).
 *
 * Threading: connect/disconnect notifications arrive on the main thread
 * (metal.m pumps its run loop).  Value changes run on a private serial queue
 * (controller.handlerQueue) and copy the controller state into g_real under
 * g_lk.  gamepad_read() is called from the guest thread.  Without a main run
 * loop (headless runs) no real controller is ever seen; the synthetic pad
 * works either way.
 *
 * Focus: on Windows the game's pad (cooperative level EXCLUSIVE|FOREGROUND)
 * reads nothing while another application is in front.  So does this one:
 * from the moment the app resigns active the pad reads at rest, and once it
 * is active again it stays at rest until the controller has been let go
 * (every button up, sticks and triggers near the middle), so a button held
 * through Cmd-Tab does not fire on return.  Controller values are always
 * monitored (also in the background), so nothing is stale when it comes back.
 *
 *   NFSU2_PAD=0 (or off)        no game pad at all (keyboard and mouse only);
 *                               NFSU2_PAD=hotplug: see dinput_pad.c
 *   NFSU2_PAD_DEADZONE=<f>      radial stick dead zone, fraction of full
 *                               deflection (default 0.10); the rest of the
 *                               travel is rescaled to stay proportional
 *   NFSU2_PAD_TRIGGER_DEADZONE=<f>  trigger dead zone (default 0.02)
 *   NFSU2_PAD_BACKGROUND=1      keep reading the controller while another app
 *                               is in front (no focus rule)
 *   NFSU2_PAD_FAKE="X=0.5;A=1;RT=1"   a synthetic pad (tests, no hardware).
 *                               Axes LX LY RX RY LT RT, and as upstream named
 *                               them X Y (the left stick), Z (LT +, RT -), RZ
 *                               (RT, -1 at rest); buttons by name (A, B, LB,
 *                               START, DUP...; the X and Y buttons are B2 and
 *                               B3, or SQUARE and TRIANGLE) or B0..B9 (A B X Y
 *                               LB RB View Menu LS RS); POV=<centidegrees>
 *                               for the D-pad (-1 centred)
 *   NFSU2_PAD_SEQ="<frame>:<items>[,<frame>:<items>...]"   the synthetic pad
 *                               changes at those frames (items as in
 *                               NFSU2_PAD_FAKE, ';' between them); OFF as an
 *                               item lets go of everything, PLUG=0 / PLUG=1
 *                               unplugs the pad and plugs it back in
 *   NFSU2_PAD_LOG=1             log controllers connecting and disconnecting
 *   NFSU2_TEST_PAD_NO_REAL=1    (test aid) only the synthetic pad: a script's
 *                               "pad disconnect" unplugs it on a Mac with a
 *                               controller of its own
 * Ported from th0mk's nfsu2-web runtime/gamepad.m (MIT); the synthetic pad,
 * the start-up wait and the report come from upstream's gamepad.m. */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#include <os/lock.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include "gamepad.h"
#include "rumble.h"

__attribute__((weak)) long metal_frames(void);   /* metal.m (absent in the harness) */

static os_unfair_lock g_lk = OS_UNFAIR_LOCK_INIT;
static PadState g_real;              /* active controller, raw values */
static PadState g_syn;               /* the synthetic controller */
static int      g_log = 0;

static GCController   *g_active;     /* main thread only */
static unsigned        g_gen;        /* bumped under g_lk when g_active changes */
static NSMutableArray *g_order;      /* connected controllers, oldest first */
static dispatch_queue_t g_q;
static _Atomic int     g_focused = 1;   /* the app is (or never stopped being) active */
static _Atomic unsigned g_focus_epoch;
static _Atomic int     g_started;       /* discovery has run (main thread) */
static unsigned long long g_reads, g_pressed;

static float envf(const char *nm, float dflt, float lo, float hi){
    const char *e = getenv(nm);
    if (!e || !*e) return dflt;
    float v = (float)atof(e);
    return v < lo ? lo : (v > hi ? hi : v);
}
int gamepad_env_flag(const char *nm, int dflt){
    const char *e = getenv(nm);
    if (!e || !*e) return dflt;
    if ((*e >= '0' && *e <= '9') || *e == '-' || *e == '+') return atoi(e) != 0;
    return strcasecmp(e, "off") && strcasecmp(e, "no") && strcasecmp(e, "false");
}
/* NFSU2_PAD: on (default), hotplug (also on) or off */
static int pad_wanted(void){
    const char *e = getenv("NFSU2_PAD");
    return (e && !strcasecmp(e, "hotplug")) || gamepad_env_flag("NFSU2_PAD", 1);
}

/* ---- controller state ------------------------------------------------ */
static void snap(GCExtendedGamepad *g, unsigned gen){
    uint32_t b = 0;
#define BT(e_, bit_) do { GCControllerButtonInput *_e = (e_); if (_e && _e.pressed) b |= 1u << (bit_); } while (0)
    BT(g.buttonA, PAD_A);            BT(g.buttonB, PAD_B);
    BT(g.buttonX, PAD_X);            BT(g.buttonY, PAD_Y);
    BT(g.leftShoulder, PAD_LB);      BT(g.rightShoulder, PAD_RB);
    BT(g.buttonOptions, PAD_BACK);   BT(g.buttonMenu, PAD_START);
    BT(g.leftThumbstickButton, PAD_LS); BT(g.rightThumbstickButton, PAD_RS);
    BT(g.buttonHome, PAD_HOME);
    BT(g.dpad.up, PAD_DUP);          BT(g.dpad.down, PAD_DDOWN);
    BT(g.dpad.left, PAD_DLEFT);      BT(g.dpad.right, PAD_DRIGHT);
#undef BT
    /* GameController's y axes point up; DirectInput's point down */
    float ax[PAD_NAXES] = {
        g.leftThumbstick.xAxis.value,  -g.leftThumbstick.yAxis.value,
        g.rightThumbstick.xAxis.value, -g.rightThumbstick.yAxis.value,
        g.leftTrigger.value,           g.rightTrigger.value };
    os_unfair_lock_lock(&g_lk);
    /* a change still queued for a controller that is no longer the active
     * one (it went away, or another took over) must not land in g_real */
    if (gen == g_gen){
        g_real.buttons = b;
        memcpy(g_real.axis, ax, sizeof ax);
    }
    os_unfair_lock_unlock(&g_lk);
}

static int family_of(GCController *k){
    NSString *cat = k.productCategory ?: @"";
    if ([cat containsString:@"Xbox"]) return PADF_XBOX;
    if ([cat containsString:@"DualShock"] || [cat containsString:@"DualSense"]) return PADF_PLAYSTATION;
    if ([cat containsString:@"Switch"] || [cat containsString:@"Joy-Con"]) return PADF_NINTENDO;
    return PADF_GENERIC;
}

/* ---- connect / disconnect (main thread) ---------------------------------- */
static void pick_active(void){
    GCController *best = nil;
    for (GCController *k in g_order) if (k.extendedGamepad){ best = k; break; }
    if (best == g_active) return;
    if (g_active) g_active.extendedGamepad.valueChangedHandler = nil;
    g_active = best;
    os_unfair_lock_lock(&g_lk);
    unsigned gen = ++g_gen;
    memset(&g_real, 0, sizeof g_real);
    if (best){
        g_real.connected = 1;
        g_real.family = family_of(best);
        snprintf(g_real.name, sizeof g_real.name, "%s",
                 best.vendorName.length ? best.vendorName.UTF8String : "Game Controller");
    }
    os_unfair_lock_unlock(&g_lk);
    if (best){
        best.handlerQueue = g_q;
        GCExtendedGamepad *gp = best.extendedGamepad;
        gp.valueChangedHandler = ^(GCExtendedGamepad *p, GCControllerElement *el){ (void)el; snap(p, gen); };
        dispatch_async(g_q, ^{ snap(gp, gen); });
    }
    rumble_controller(best);                    /* its motors (runtime/rumble.m) */
    fprintf(stderr, "[pad] player 1 controller: %s (%s)\n", best ? g_real.name : "none",
            best ? (best.productCategory.UTF8String ?: "?") : "-");
}

static void focus(int on){
    if (atomic_exchange(&g_focused, on) != on) atomic_fetch_add(&g_focus_epoch, 1u);
}

static void setup(void){
    g_order = [NSMutableArray array];
    g_q = dispatch_queue_create("nfsu2.gamepad", DISPATCH_QUEUE_SERIAL);
    /* values keep coming while another app is in front: the focus rule
     * (gamepad_read) decides what the game gets */
    if (@available(macOS 11.3, *)) GCController.shouldMonitorBackgroundEvents = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:GCControllerDidConnectNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){
            GCController *k = n.object;
            if (g_log) fprintf(stderr, "[pad] connected: %s (%s)\n", k.vendorName.UTF8String ?: "?",
                               k.productCategory.UTF8String ?: "?");
            if (![g_order containsObject:k]) [g_order addObject:k];
            pick_active();
        }];
    [nc addObserverForName:GCControllerDidDisconnectNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){
            GCController *k = n.object;
            if (g_log) fprintf(stderr, "[pad] disconnected: %s\n", k.vendorName.UTF8String ?: "?");
            [g_order removeObject:k];
            pick_active();
        }];
    /* NSApplication's own notifications: a real Cmd-Tab, Spotlight, another
     * window.  A run that is never active (NOFOCUS tests) stays "focused". */
    [nc addObserverForName:NSApplicationDidResignActiveNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){ (void)n; focus(0);
            if (g_log) fprintf(stderr, "[pad] app inactive: %s\n", gamepad_env_flag("NFSU2_PAD_BACKGROUND", 0)
                               ? "the pad keeps reading (NFSU2_PAD_BACKGROUND)" : "the pad reads at rest"); }];
    [nc addObserverForName:NSApplicationDidBecomeActiveNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){ (void)n; focus(1);
            if (g_log && !gamepad_env_flag("NFSU2_PAD_BACKGROUND", 0))
                fprintf(stderr, "[pad] app active: the pad reads once let go\n"); }];
    for (GCController *k in [GCController controllers])
        if (![g_order containsObject:k]) [g_order addObject:k];
    fprintf(stderr, "[pad] GameController: %lu controller(s) connected at start-up\n",
            (unsigned long)g_order.count);
    pick_active();
    atomic_store(&g_started, 1);
}

/* ---- synthetic pad: NFSU2_PAD_FAKE, NFSU2_PAD_SEQ ------------------------ */
static void syn_item(PadState *s, const char *t){
    char k[16]; const char *eq = strchr(t, '=');
    if (!strcasecmp(t, "OFF")){ s->buttons = 0; memset(s->axis, 0, sizeof s->axis); return; }
    if (!strncasecmp(t, "PLUG=", 5)){ s->connected = atoi(t + 5) != 0; return; }   /* unplug / plug in */
    if (!eq || eq == t || eq - t >= (long)sizeof k) return;
    memcpy(k, t, (size_t)(eq - t)); k[eq - t] = 0;
    float v = (float)atof(eq + 1);
    if (!strcasecmp(k, "Z")){                                    /* upstream's combined triggers */
        s->axis[PAD_AXIS_LT] = v > 0 ? v : 0; s->axis[PAD_AXIS_RT] = v < 0 ? -v : 0; return; }
    int a = !strcasecmp(k, "X") ? PAD_AXIS_LX : !strcasecmp(k, "Y") ? PAD_AXIS_LY
          : !strcasecmp(k, "RZ") ? PAD_AXIS_RT : gamepad_axis_by_name(k);
    if (!strcasecmp(k, "RZ")) v = (v + 1.f) / 2.f;              /* DirectInput: -1 at rest */
    if (a >= 0){
        float lo = a >= PAD_AXIS_LT ? 0.f : -1.f;
        s->axis[a] = v < lo ? lo : (v > 1.f ? 1.f : v); return; }
    if (!strcasecmp(k, "POV")){
        s->buttons &= ~(1u << PAD_DUP | 1u << PAD_DDOWN | 1u << PAD_DLEFT | 1u << PAD_DRIGHT);
        int d = (int)v;
        if (d >= 0){
            int o = ((d + 2250) / 4500) % 8;                     /* 0 up, 2 right, 4 down, 6 left */
            if (o == 7 || o <= 1) s->buttons |= 1u << PAD_DUP;
            if (o >= 1 && o <= 3) s->buttons |= 1u << PAD_DRIGHT;
            if (o >= 3 && o <= 5) s->buttons |= 1u << PAD_DDOWN;
            if (o >= 5 && o <= 7) s->buttons |= 1u << PAD_DLEFT;
        }
        return;
    }
    int b = -1;
    if ((k[0] == 'B' || k[0] == 'b') && k[1] >= '0' && k[1] <= '9'){
        static const int di[10] = {PAD_A, PAD_B, PAD_X, PAD_Y, PAD_LB, PAD_RB, PAD_BACK, PAD_START, PAD_LS, PAD_RS};
        int n = atoi(k + 1); if (n >= 0 && n < 10) b = di[n];
    } else b = gamepad_button_by_name(k);
    if (b >= 0){ if (v != 0) s->buttons |= 1u << b; else s->buttons &= ~(1u << b); }
}
static void syn_items(PadState *s, const char *list){
    char *buf = strdup(list), *save = NULL;
    for (char *t = strtok_r(buf, ";", &save); t; t = strtok_r(NULL, ";", &save)){
        while (*t == ' ') t++;
        syn_item(s, t);
    }
    free(buf);
}
#define SEQMAX 128
static struct { long frame; char items[96]; } g_seq[SEQMAX];
static int g_nseq, g_iseq;
static void syn_setup(void){
    const char *fake = getenv("NFSU2_PAD_FAKE"), *seq = getenv("NFSU2_PAD_SEQ");
    if (!(fake && *fake) && !(seq && *seq)) return;
    memset(&g_syn, 0, sizeof g_syn);
    g_syn.connected = 1; g_syn.synthetic = 1; g_syn.family = PADF_XBOX;
    snprintf(g_syn.name, sizeof g_syn.name, "Fake Pad");
    if (fake && *fake) syn_items(&g_syn, fake);
    for (const char *p = seq; p && *p && g_nseq < SEQMAX; ){
        while (*p == ',' || *p == ' ') p++;
        if (!*p) break;
        const char *c = strchr(p, ':'), *e = strchr(p, ',');
        if (!e) e = p + strlen(p);
        if (c && c < e){
            g_seq[g_nseq].frame = strtol(p, 0, 0);
            snprintf(g_seq[g_nseq].items, sizeof g_seq[g_nseq].items, "%.*s", (int)(e - c - 1), c + 1);
            g_nseq++;
        }
        p = e;
    }
    fprintf(stderr, "[pad] synthetic pad (NFSU2_PAD_FAKE/_SEQ): %d timed change(s)\n", g_nseq);
}
static void syn_tick(void){                     /* under g_lk */
    if (g_iseq >= g_nseq || !metal_frames) return;
    long f = metal_frames();
    while (g_iseq < g_nseq && f >= g_seq[g_iseq].frame){
        syn_items(&g_syn, g_seq[g_iseq].items);
        if (g_log) fprintf(stderr, "[pad] NFSU2_PAD_SEQ frame %ld: %s\n", f, g_seq[g_iseq].items);
        g_iseq++;
    }
}

void gamepad_init(void){
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_log = gamepad_env_flag("NFSU2_PAD_LOG", 0);
        os_unfair_lock_lock(&g_lk); syn_setup(); os_unfair_lock_unlock(&g_lk);
        if ([NSThread isMainThread]) setup();
        else dispatch_async(dispatch_get_main_queue(), ^{ setup(); });
    });
}
/* tests/boot.c, before the game starts (main thread) */
void gamepad_install(void){ if (pad_wanted()) gamepad_init(); }

/* ---- reading ----------------------------------------------------------- */
/* Radial dead zone with the remaining travel rescaled, so half a stick
 * still reads (about) half. */
static void stick_dz(float *x, float *y, float dz){
    float r = sqrtf(*x * *x + *y * *y);
    if (r <= dz || r <= 0.f){ *x = *y = 0.f; return; }
    float k = (r >= 1.f ? 1.f : (r - dz) / (1.f - dz)) / r;
    *x *= k; *y *= k;
    if (*x > 1.f) *x = 1.f; if (*x < -1.f) *x = -1.f;
    if (*y > 1.f) *y = 1.f; if (*y < -1.f) *y = -1.f;
}
static float trig_dz(float v, float dz){
    if (v <= dz) return 0.f;
    return v >= 1.f ? 1.f : (v - dz) / (1.f - dz);
}
static int at_rest(const PadState *s){
    if (!s->connected) return 1;
    if (s->buttons) return 0;
    for (int i = 0; i < PAD_NAXES; i++) if (fabsf(s->axis[i]) > 0.08f) return 0;
    return 1;
}

/* The game asks for the pad long after start-up, but discovery needs the
 * main run loop: give a slow start a moment (upstream's gamepad_present). */
static void wait_discovery(void){
    static int waited;
    if (waited || [NSThread isMainThread]) return;
    waited = 1;
    for (int i = 0; i < 20 && !atomic_load(&g_started); i++) usleep(10000);
    for (int i = 0; i < 20; i++){
        os_unfair_lock_lock(&g_lk); int c = g_real.connected; os_unfair_lock_unlock(&g_lk);
        if (c || [GCController controllers].count == 0) break;
        usleep(10000);
    }
}

int gamepad_read(PadState *s){
    static float dz = -1.f, tdz = -1.f;
    static int bg = -1, no_real;
    if (dz < 0.f){ dz = envf("NFSU2_PAD_DEADZONE", 0.10f, 0.f, 0.9f);
                   tdz = envf("NFSU2_PAD_TRIGGER_DEADZONE", 0.02f, 0.f, 0.9f);
                   bg = gamepad_env_flag("NFSU2_PAD_BACKGROUND", 0);
                   no_real = gamepad_env_flag("NFSU2_TEST_PAD_NO_REAL", 0); }
    wait_discovery();
    os_unfair_lock_lock(&g_lk);
    syn_tick();
    *s = g_syn.connected ? g_syn : g_real;      /* the synthetic pad wins while connected */
    if (no_real && !g_syn.connected) memset(s, 0, sizeof *s);   /* (test aid: a controller of the Mac's own is not seen) */
    os_unfair_lock_unlock(&g_lk);
    stick_dz(&s->axis[PAD_AXIS_LX], &s->axis[PAD_AXIS_LY], dz);
    stick_dz(&s->axis[PAD_AXIS_RX], &s->axis[PAD_AXIS_RY], dz);
    s->axis[PAD_AXIS_LT] = trig_dz(s->axis[PAD_AXIS_LT], tdz);
    s->axis[PAD_AXIS_RT] = trig_dz(s->axis[PAD_AXIS_RT], tdz);
    /* the focus rule (see the top) */
    static unsigned epoch; static int quarantine;
    unsigned ep = atomic_load(&g_focus_epoch);
    if (!bg){
        if (ep != epoch){ epoch = ep; quarantine = 1; }
        if (!atomic_load(&g_focused)) quarantine = 1;
        else if (quarantine && at_rest(s)){
            quarantine = 0;
            if (g_log) fprintf(stderr, "[pad] controller let go: the game reads it again\n");
        }
        if (quarantine){ s->buttons = 0; memset(s->axis, 0, sizeof s->axis); }
    }
    g_reads++;
    if (s->buttons) g_pressed++;
    return s->connected;
}

/* The pad as a DIJOYSTATE2 (272 bytes, buttons from 0x30 in dinput_pad.c's
 * order: A B X Y LB RB View Menu LS RS), for the runtime's own "is a pad
 * button down" checks (overrides.c's boot-movie skip). */
void gamepad_fill(unsigned char *dst){
    memset(dst, 0, 272);
    uint32_t *pov = (uint32_t *)(dst + 0x20);
    for (int i = 0; i < 4; i++) pov[i] = 0xFFFFFFFFu;
    if (!pad_wanted()) return;
    PadState s; gamepad_read(&s);
    for (int i = 0; i < 10; i++) if (s.buttons & (1u << i)) dst[0x30 + i] = 0x80;
}

void gamepad_report(void){
    os_unfair_lock_lock(&g_lk);
    PadState s = g_syn.connected ? g_syn : g_real;
    os_unfair_lock_unlock(&g_lk);
    if (!g_reads && !s.connected) return;
    fprintf(stderr, "[pad] %s: %s, %llu reads, %llu with a button down\n",
            s.synthetic ? "synthetic" : "GameController", s.connected ? s.name : "no controller",
            g_reads, g_pressed);
}

/* ---- synthetic controller (test scripts) ------------------------------------ */
/* items as in NFSU2_PAD_FAKE (runtime/autotest.c padset); the pad connects first
 * unless the items say PLUG=0 */
void gamepad_synth_items(const char *items){
    os_unfair_lock_lock(&g_lk);
    if (!g_syn.synthetic){
        memset(&g_syn, 0, sizeof g_syn);
        g_syn.synthetic = 1; g_syn.family = PADF_XBOX; g_syn.connected = 1;
        snprintf(g_syn.name, sizeof g_syn.name, "Fake Pad");
    }
    syn_items(&g_syn, items);
    os_unfair_lock_unlock(&g_lk);
}
void gamepad_synth_connect(int on){
    os_unfair_lock_lock(&g_lk);
    if ((on != 0) != g_syn.connected){
        memset(&g_syn, 0, sizeof g_syn);
        g_syn.connected = on ? 1 : 0;
        g_syn.synthetic = 1;
        g_syn.family = PADF_XBOX;
        snprintf(g_syn.name, sizeof g_syn.name, "Virtual Controller (autotest)");
    }
    os_unfair_lock_unlock(&g_lk);
}
void gamepad_synth_button(int b, int down){
    if (b < 0 || b >= PAD_NBUTTONS) return;
    if (!g_syn.connected) gamepad_synth_connect(1);
    os_unfair_lock_lock(&g_lk);
    if (down) g_syn.buttons |= 1u << b; else g_syn.buttons &= ~(1u << b);
    os_unfair_lock_unlock(&g_lk);
}
void gamepad_synth_axis(int a, float v){
    if (a < 0 || a >= PAD_NAXES) return;
    if (!g_syn.connected) gamepad_synth_connect(1);
    float lo = a >= PAD_AXIS_LT ? 0.f : -1.f;
    os_unfair_lock_lock(&g_lk);
    g_syn.axis[a] = v < lo ? lo : (v > 1.f ? 1.f : v);
    os_unfair_lock_unlock(&g_lk);
}

int gamepad_button_by_name(const char *nm){
    static const struct { const char *nm; int b; } T[] = {
        {"A",PAD_A},{"CROSS",PAD_A},{"B",PAD_B},{"CIRCLE",PAD_B},{"X",PAD_X},{"SQUARE",PAD_X},
        {"Y",PAD_Y},{"TRIANGLE",PAD_Y},{"LB",PAD_LB},{"L1",PAD_LB},{"RB",PAD_RB},{"R1",PAD_RB},
        {"BACK",PAD_BACK},{"VIEW",PAD_BACK},{"SELECT",PAD_BACK},{"SHARE",PAD_BACK},{"CREATE",PAD_BACK},
        {"START",PAD_START},{"MENU",PAD_START},{"OPTIONS",PAD_START},
        {"LS",PAD_LS},{"L3",PAD_LS},{"RS",PAD_RS},{"R3",PAD_RS},{"HOME",PAD_HOME},{"GUIDE",PAD_HOME},
        {"DUP",PAD_DUP},{"DDOWN",PAD_DDOWN},{"DLEFT",PAD_DLEFT},{"DRIGHT",PAD_DRIGHT},
    };
    for (unsigned i = 0; i < sizeof T / sizeof *T; i++) if (!strcasecmp(nm, T[i].nm)) return T[i].b;
    return -1;
}
int gamepad_axis_by_name(const char *nm){
    static const char *const T[PAD_NAXES] = {"LX","LY","RX","RY","LT","RT"};
    for (int i = 0; i < PAD_NAXES; i++) if (!strcasecmp(nm, T[i])) return i;
    if (!strcasecmp(nm, "L2")) return PAD_AXIS_LT;
    if (!strcasecmp(nm, "R2")) return PAD_AXIS_RT;
    return -1;
}
