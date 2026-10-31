/* dinput_pad.c -- the virtual game pad (runtime/gamepad.m) as a DirectInput8
 * gamepad device (device kind 3 in com.c).
 *
 * How SPEED2.EXE v1.2 uses game controllers (static analysis; European
 * addresses, North American ones in parentheses where they differ; data
 * addresses are the same in both):
 *   - IDirectInput8 #1 [0x8709ec]: EnumDevices(DI8DEVCLASS_GAMECTRL, ATTACHEDONLY)
 *     once at start-up.  The rescan every 32 frames in 0x5cfa20 (0x5cfa10) is
 *     gated by [0x8364e8], which nothing ever sets.
 *   - 0x5cd200 (0x5cd1f0) creates at most two devices (slots [0x86ffb4],
 *     [0x86ffb8]): c_dfDIJoystick2, cooperative level EXCLUSIVE|FOREGROUND,
 *     EnumObjects -> DIPROP_RANGE -10000..10000 per axis.
 *   - Every frame 0x5c8710 (0x5c8700) does Poll + GetDeviceState(DIJOYSTATE2)
 *     (DIERR_INPUTLOST releases the slot).
 *   - Each slot gets a free input channel (0x874c40 + n*0x370); 0x5c11b0
 *     (0x5c11a0) sets that channel's defaults: button/POV -> action tables at
 *     +0x18 (in game), +0x98 (front end), +0x118, +0x198 and the analog axes at
 *     +0x344..+0x368.  0x5b81c0 (0x5b81b0) is the built-in profile lookup by
 *     guidProduct (nine Logitech/Microsoft/Saitek/... pads).
 *   - The channel bindings (+0x18 table, axes) are saved with the profile
 *     (0x5b9430 (0x5b9420)) keyed by the device's guidInstance.
 *
 * So the pad is a classic DIJOYSTATE2 gamepad with a STABLE guidInstance
 * (bindings persist) and our own entry in the game's profile lookup
 * (sub_005b81c0 below) giving the default layout.  Layout:
 *   axes    X/Y = left stick, Z = left trigger, Rx/Ry = right stick,
 *           Rz = right trigger (triggers rest at the minimum)
 *   POV 0   D-pad;  POV 1  left stick as four directions (menus)
 *   buttons 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 View, 7 Menu, 8 LS, 9 RS,
 *           10 LT and 11 RT pressed to the end of their travel (as a
 *           DualShock 4 under DirectInput reports L2/R2 twice), or half
 *           way when the game reads that trigger as no axis (fill_state)
 * (Upstream's pad combined both triggers into one Z axis, as an Xbox 360 pad's
 * driver does, and had no profile entry: the game's generic defaults.)
 *
 *   NFSU2_PAD=0         no game pad device (also off/no/false)
 *   NFSU2_PAD=hotplug   the device exists only while a controller is
 *                       connected (DirectInput-faithful: unplugging reports
 *                       DIERR_INPUTLOST and the game's own 32-frame rescan
 *                       is switched on).  Default: the device appears once
 *                       a controller has been connected (at start-up or
 *                       later, through the same rescan) and then stays,
 *                       reading centred while nothing is connected, so
 *                       bindings survive unplugging.
 *   NFSU2_PAD_TRIGGER_CLICK=<f>  trigger travel (0..1) at which buttons 10/11
 *                       press while the game reads the trigger as an axis
 *                       (default 0.97); off: never (no trigger buttons)
 *   NFSU2_PAD_FE_KEYS=0 A, B and View post no Enter/Escape/Q in the menus
 *   NFSU2_PAD_LOG=1     log enumeration, properties and state changes
 *
 * Force feedback (rumble, NFSU2_FF=1): the pad then reports force-feedback
 * actuators on X and Y and plays the game's effects (runtime/dinput_ff.c) on
 * the controller's motors (runtime/rumble.m).
 * Not ported from nfsu2-web: the browser's steering wheel.
 * Ported from th0mk's nfsu2-web runtime/dinput_pad.c (MIT). */
#include "cpu.h"
#include "gamepad.h"
#include "kbd.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>

/* Overlays that want the pad for themselves (photo mode, quick chat) can
 * filter it before the game sees it. */
__attribute__((weak)) void native_controls_filter_pad(PadState *s) { (void)s; }
__attribute__((weak)) void native_scene_filter_pad(PadState *s) { (void)s; }

uint32_t call_guest(CPU *c, uint32_t fn, int nargs, const uint32_t *args);
uint32_t com_scratch(uint32_t n);                          /* com.c */
/* force feedback (dinput_ff.c) */
int      dipad_ff_on(void);
void     dipad_ff_frame(void);
uint32_t dipad_ff_prop(int set, uint32_t prop, uint32_t h);
int64_t  dipad_ff_dev_call(CPU *c, const char *nm, const uint32_t *a);

#define DI_OK                 0x00000000u
#define DI_NOEFFECT           0x00000001u
#define DIERR_OBJECTNOTFOUND  0x80070002u
#define DIERR_INPUTLOST       0x8007001Eu
#define DIERR_INVALIDPARAM    0x80070057u
#define DIERR_UNSUPPORTED     0x80004001u

#define DIDFT_ABSAXIS   0x00000002u
#define DIDFT_PSHBUTTON 0x00000004u
#define DIDFT_POV       0x00000010u
#define DIDFT_TYPEMASK  0x000000FFu
#define DIDFT_FFACTUATOR 0x01000000u
#define DIDOI_ASPECTPOSITION 0x00000100u
#define DIDOI_FFACTUATOR     0x00000001u
#define DIDC_FORCEFEEDBACK   0x00000100u
#define DI8DEVTYPE_GAMEPAD 0x15u
#define PAD_DEVTYPE     (0x00010000u | (2u << 8) | DI8DEVTYPE_GAMEPAD)  /* HID, STANDARD */

/* game data (the same in both builds) */
#define G_RESCAN     GA(0x008364e8u)    /* 1: EnumDevices again every 32 frames */
#define G_PADSLOTS   GA(0x0086ffb4u)    /* the two pad devices the game holds */
#define G_CHANNELS   GA(0x00874c40u)    /* input channels, 0x370 bytes each, six */
#define G_FLOW       GA(0x008654a4u)    /* GameFlowManager: 3 front end, 6 in the world */
#define G_FE_MGR     GA(0x008384c4u)    /* the front-end manager (GetTopPackage) */
#define CHAN_SIZE    0x370u
#define CHAN_COUNT   6u

/* ---- configuration ---------------------------------------------------- */
enum { MODE_OFF, MODE_ALWAYS, MODE_HOTPLUG };
static int pad_mode(void){
    static int m = -1;
    if (m < 0){
        const char *e = getenv("NFSU2_PAD");
        m = e && !strcasecmp(e, "hotplug") ? MODE_HOTPLUG
          : gamepad_env_flag("NFSU2_PAD", 1) ? MODE_ALWAYS : MODE_OFF;
        if (m != MODE_OFF) gamepad_init();
    }
    return m;
}
static int pad_log(void){
    static int l = -1;
    if (l < 0) l = gamepad_env_flag("NFSU2_PAD_LOG", 0);
    return l;
}

/* ---- objects ---------------------------------------------------------------
 * Axes 0..5, POVs 6..7, buttons 8..19.  Object GUIDs are dinput.h's
 * GUID_XAxis family: {A36D02xx-C9F3-11CF-BFC7-444553540000}. */
#define NAXES 6
#define NPOVS 2
#define NBTNS 12
#define NOBJS (NAXES + NPOVS + NBTNS)
static const uint8_t k_axis_ofs[NAXES]  = {0x00, 0x04, 0x08, 0x0C, 0x10, 0x14};
static const uint32_t k_axis_guid[NAXES] = {0xA36D02E0u, 0xA36D02E1u, 0xA36D02E2u,
                                            0xA36D02F4u, 0xA36D02F5u, 0xA36D02E3u};
static const uint16_t k_axis_usage[NAXES] = {0x30, 0x31, 0x32, 0x33, 0x34, 0x35};
/* which pad axis feeds each DirectInput axis */
static const int k_axis_src[NAXES] = {PAD_AXIS_LX, PAD_AXIS_LY, PAD_AXIS_LT,
                                      PAD_AXIS_RX, PAD_AXIS_RY, PAD_AXIS_RT};
#define SRC_LT_FULL -1
#define SRC_RT_FULL -2
static const int k_btn_src[NBTNS] = {PAD_A, PAD_B, PAD_X, PAD_Y, PAD_LB, PAD_RB,
                                     PAD_BACK, PAD_START, PAD_LS, PAD_RS,
                                     SRC_LT_FULL, SRC_RT_FULL};

static uint32_t obj_ofs(int i){
    return i < NAXES ? k_axis_ofs[i] : i < NAXES + NPOVS ? 0x20u + 4u * (uint32_t)(i - NAXES)
                                                       : 0x30u + (uint32_t)(i - NAXES - NPOVS);
}
static uint32_t obj_type(int i){
    if (i < NAXES) return DIDFT_ABSAXIS | ((uint32_t)i << 8);
    if (i < NAXES + NPOVS) return DIDFT_POV | ((uint32_t)(i - NAXES) << 8);
    return DIDFT_PSHBUTTON | ((uint32_t)(i - NAXES - NPOVS) << 8);
}
/* The names the Joypad page shows; positional buttons, so a PlayStation
 * pad's A is "Cross" and a Nintendo pad's A is its bottom button "B". */
static const char *obj_name(int i, int fam){
    static const char *const ax[NAXES] = {"Left Stick X", "Left Stick Y", "Left Trigger",
                                          "Right Stick X", "Right Stick Y", "Right Trigger"};
    static const char *const trig[4][2] = {{"Left Trigger", "Right Trigger"}, {"LT", "RT"},
                                           {"L2", "R2"}, {"ZL", "ZR"}};
    static const char *const btn[4][NBTNS] = {
        {"A", "B", "X", "Y", "LB", "RB", "Back", "Start", "Left Stick", "Right Stick",
         "Left Trigger Full", "Right Trigger Full"},
        {"A", "B", "X", "Y", "LB", "RB", "View", "Menu", "Left Stick", "Right Stick",
         "LT Full", "RT Full"},
        {"Cross", "Circle", "Square", "Triangle", "L1", "R1", "Create", "Options", "L3", "R3",
         "L2 Full", "R2 Full"},
        {"B", "A", "Y", "X", "L", "R", "Minus", "Plus", "Left Stick", "Right Stick",
         "ZL Full", "ZR Full"} };
    if (fam < 0 || fam > 3) fam = 0;
    if (i == 2) return trig[fam][0];
    if (i == 5) return trig[fam][1];
    if (i < NAXES) return ax[i];
    if (i == NAXES) return "D-pad";
    if (i < NAXES + NPOVS) return "Left Stick Directions";
    return btn[fam][i - NAXES - NPOVS];
}
static int obj_by_ofs(uint32_t ofs){
    for (int i = 0; i < NOBJS; i++) if (obj_ofs(i) == ofs) return i;
    return -1;
}
static int obj_by_id(uint32_t id){
    for (int i = 0; i < NOBJS; i++){
        uint32_t t = obj_type(i);
        if (((t >> 8) & 0xFFFFu) == ((id >> 8) & 0xFFFFu) && (t & id & DIDFT_TYPEMASK)) return i;
    }
    return -1;
}
static int obj_find(uint32_t obj, uint32_t how){
    return how == 1u ? obj_by_ofs(obj) : how == 2u ? obj_by_id(obj) : -1;
}

/* ---- GUIDs and the device instance ------------------------------------------ */
static void put_guid(uint32_t p, uint32_t d1, uint16_t d2, uint16_t d3, const uint8_t d4[8]){
    MR32(p) = d1; MR16(p + 4) = d2; MR16(p + 6) = d3;
    for (int i = 0; i < 8; i++) MR8(p + 8 + (uint32_t)i) = d4[i];
}
/* guidInstance never changes: the game keys saved bindings on it */
static const uint8_t k_inst_d4[8] = {0x80, 0x00, 'N', 'F', 'S', 'U', '2', 0x01};
#define INST_D1 0x50414447u               /* "GDAP" */
static void put_instance_guid(uint32_t p){ put_guid(p, INST_D1, 0x4E46, 0x11F0, k_inst_d4); }
/* 1: the pad's guidInstance, 0: not ours */
int dipad_guid(uint32_t g){
    if (!g || !mem_is_committed(g + 15) || MR32(g) != INST_D1) return 0;
    if (memcmp(g_mem + g + 8, k_inst_d4, 8) || MR16(g + 4) != 0x4E46 || MR16(g + 6) != 0x11F0) return 0;
    return 1;
}
/* A HID-style product GUID {PIDVID-0000-0000-0000-504944564944}; the VID/PID
 * collide with none of the game's own pad lists. */
static uint32_t family_vidpid(int fam){
    switch (fam){
    case PADF_XBOX:        return 0x0B13045Eu;        /* Xbox Wireless Controller */
    case PADF_PLAYSTATION: return 0x0CE6054Cu;        /* DualSense */
    case PADF_NINTENDO:    return 0x2009057Eu;        /* Switch Pro Controller */
    default:               return 0x55441209u;        /* pid.codes test range */
    }
}
/* DIDEVICEINSTANCEA, with the name of the controller driving the pad */
static void write_devinst(uint32_t p, uint32_t size, const PadState *s){
    static const uint8_t pidvid[8] = {0x00, 0x00, 'P', 'I', 'D', 'V', 'I', 'D'};
    if (size > 0x244u || size < 0x24u) size = 0x244u;
    mem_commit(p, size);
    memset(g_mem + p, 0, size);
    MR32(p) = size;
    put_instance_guid(p + 0x04);
    put_guid(p + 0x14, family_vidpid(s->family), 0, 0, pidvid);
    if (size < 0x28u) return;
    MR32(p + 0x24) = PAD_DEVTYPE;
    const char *nm = s->connected && s->name[0] ? s->name : "Gamepad";
    if (size >= 0x12cu) snprintf((char *)(g_mem + p + 0x28), 260, "%s", nm);
    if (size >= 0x230u) snprintf((char *)(g_mem + p + 0x12c), 260, "%s", nm);
    if (size >= 0x244u){ MR16(p + 0x240) = 1; MR16(p + 0x242) = 5; }   /* Generic Desktop, Game Pad */
    if (size >= 0x240u && dipad_ff_on()) put_guid(p + 0x230, 0x4646504Eu, 0x4E46, 0x11F0, k_inst_d4);   /* guidFFDriver */
}

/* ---- per-device state ---------------------------------------------------------- */
typedef struct {
    uint32_t obj;                        /* guest IDirectInputDevice8 */
    int32_t  mn[NAXES], mx[NAXES];       /* DIPROP_RANGE */
    uint32_t dz[NAXES], sat[NAXES];      /* DIPROP_DEADZONE / _SATURATION, 0..10000 */
    uint32_t bufsize, axismode, autocenter;
    int      pov1;                       /* left-stick direction with hysteresis */
    uint32_t last_btn, fe_prev;
    int      fe_down[3];                 /* Enter / Escape / Q keystroke is down */
    int      rest;                       /* hotplug: polls answered at rest since the unplug */
    int      trig[2];                    /* buttons 10/11 (LT, RT as buttons) are down */
} Dev;
static Dev g_dev[4];
static Dev *dev_of(uint32_t obj){
    for (int i = 0; i < 4; i++) if (g_dev[i].obj == obj) return &g_dev[i];
    /* a free slot, else the oldest: in hotplug mode every replug is a new
     * device object and the released ones are never called again */
    static int next = 0;
    Dev *d = 0;
    for (int i = 0; i < 4 && !d; i++) if (!g_dev[i].obj) d = &g_dev[i];
    if (!d) d = &g_dev[next++ & 3];
    memset(d, 0, sizeof *d); d->obj = obj;
    for (int a = 0; a < NAXES; a++){ d->mn[a] = 0; d->mx[a] = 65535; d->sat[a] = 10000; }
    return d;
}
/* CreateDevice with our guidInstance */
void dipad_created(uint32_t obj, uint32_t guid){
    (void)guid;
    dev_of(obj);
    PadState s; gamepad_read(&s);
    if (pad_log()) fprintf(stderr, "[pad] CreateDevice -> 0x%08x (%s)\n", obj,
                           s.connected ? s.name : "no controller yet");
}

/* ---- enumeration ------------------------------------------------------------- */
/* IDirectInput8::EnumDevices: offer the pad for DI8DEVCLASS_ALL, _GAMECTRL
 * and DI8DEVTYPE_GAMEPAD.  Returns 1 when the callback said DIENUM_STOP. */
int dipad_enum(CPU *c, uint32_t devtype, uint32_t cb, uint32_t ref, uint32_t flags){
    int mode = pad_mode();
    if (mode == MODE_OFF || !cb) return 0;
    if ((flags & 0x100u) && !dipad_ff_on()) return 0;     /* DIEDFL_FORCEFEEDBACK */
    PadState s; gamepad_read(&s);
    uint32_t t = devtype & 0xFFu;
    if (t != 0u && t != 4u && t != DI8DEVTYPE_GAMEPAD) return 0;
    /* The game's own rescan every 32 frames (0x5cfa20 (0x5cfa10) reads
     * [0x8364e8] every frame) finds a controller plugged in later.  Hotplug
     * mode keeps it on.  The default mode offers the device once a
     * controller has been seen and keeps it from then on (rescan off again):
     * with no controller there is no game pad, as in the original game.  A
     * device that nothing drives would leave a keyboard player stuck on the
     * Joypad page's "Press a button" prompt, which only a pad button ends. */
    static int seen = 0;
    if (mode == MODE_HOTPLUG || !seen){
        if (mem_is_committed(G_RESCAN)) MR32(G_RESCAN) = mode == MODE_HOTPLUG || !s.connected;
        if (!s.connected) return 0;
    }
    else if (mem_is_committed(G_RESCAN)) MR32(G_RESCAN) = 0;
    seen = 1;
    static uint32_t ddi = 0;
    if (!ddi) ddi = com_scratch(0x260);
    write_devinst(ddi, 0x244u, &s);
    static int nlog = 0;
    if (nlog < 8){ nlog++;
        fprintf(stderr, "[pad] EnumDevices(type 0x%x): game pad offered to the game: \"%s\"\n",
                devtype, (char *)(g_mem + ddi + 0x12c)); }
    uint32_t args[2] = { ddi, ref };
    return call_guest(c, cb, 2, args) == 0u;
}

/* ---- state ---------------------------------------------------------------------- */
/* t in -1..1 to the device range, with DirectInput's dead zone and
 * saturation (fractions of the distance from the centre, 0..10000). */
static int32_t scale_axis(float t, const Dev *d, int a){
    if (t > 1.f) t = 1.f; if (t < -1.f) t = -1.f;
    double dz = d->dz[a] > 10000u ? 10000.0 : d->dz[a];
    double sat = d->sat[a] > 10000u ? 10000.0 : d->sat[a];
    if (sat < dz) sat = dz;
    double mag = (t < 0 ? -t : t) * 10000.0, f;
    if (mag <= dz) f = 0; else if (mag >= sat) f = 1; else f = (mag - dz) / (sat - dz);
    int64_t lo = d->mn[a], hi = d->mx[a], mid = lo + (hi - lo + 1) / 2;
    int64_t v = t >= 0 ? mid + (int64_t)(f * (double)(hi - mid) + 0.5)
                       : mid - (int64_t)(f * (double)(mid - lo) + 0.5);
    return (int32_t)v;
}
static uint32_t pov_of(int up, int down, int left, int right){
    int x = right - left, y = down - up;
    static const uint32_t T[3][3] = {{31500u, 0u, 4500u}, {27000u, 0xFFFFFFFFu, 9000u},
                                     {22500u, 18000u, 13500u}};
    return T[y + 1][x + 1];
}
/* The left stick as a four-way hat for the menus: the dominant direction
 * past 0.55, released below 0.40. */
static uint32_t stick_pov(Dev *d, float x, float y){
    float ax = x < 0 ? -x : x, ay = y < 0 ? -y : y;
    int dir = d->pov1;                                     /* 0 none, 1 up, 2 right, 3 down, 4 left */
    if (dir && (ax > ay ? ax : ay) < 0.40f) dir = 0;
    if (!dir && (ax > 0.55f || ay > 0.55f))
        dir = ax > ay ? (x > 0 ? 2 : 4) : (y > 0 ? 3 : 1);
    if (dir == 2 || dir == 4){ if (ay > ax + 0.2f) dir = y > 0 ? 3 : 1; }
    else if (dir){ if (ax > ay + 0.2f) dir = x > 0 ? 2 : 4; }
    d->pov1 = dir;
    static const uint32_t P[5] = {0xFFFFFFFFu, 0u, 9000u, 18000u, 27000u};
    return P[dir];
}
/* The game's input channel that reads this device (+0x230 the device's slot
 * in [0x86ffb4], +0x234 its type), or 0. */
static uint32_t dev_channel(const Dev *d){
    for (uint32_t s = 0; s < 2u; s++){
        if (!d->obj || !mem_is_committed(G_PADSLOTS + 7u) || MR32(G_PADSLOTS + 4u * s) != d->obj) continue;
        for (uint32_t ch = G_CHANNELS; ch < G_CHANNELS + CHAN_COUNT * CHAN_SIZE; ch += CHAN_SIZE){
            uint8_t t = MR8(ch + 0x234u);
            if (MR32(ch + 0x230u) == s && t >= 0x14u && t <= 0x16u) return ch;
        }
    }
    return 0;
}
/* whether the channel reads the axis at state offset ofs as the steering or
 * a pedal (0x5c1fca (0x5c1fba): +0x364..+0x367 switch the axes
 * +0x344..+0x350 on, and +0x368 with +0x367 makes one axis both pedals) */
static int chan_reads_axis(uint32_t ch, uint32_t ofs){
    if (MR8(ch + 0x364u) && MR32(ch + 0x344u) == ofs) return 1;
    if (MR8(ch + 0x368u) && MR8(ch + 0x367u)) return MR32(ch + 0x350u) == ofs;
    return (MR8(ch + 0x365u) && MR32(ch + 0x348u) == ofs) || (MR8(ch + 0x366u) && MR32(ch + 0x34cu) == ofs);
}
static float trigger_click(void){
    static float click = -1.f;
    if (click < 0.f){
        const char *e = getenv("NFSU2_PAD_TRIGGER_CLICK");
        if (e && *e && !gamepad_env_flag("NFSU2_PAD_TRIGGER_CLICK", 1)) click = 2.f;   /* off: never */
        else { click = e && *e ? (float)atof(e) : 0.97f;
               if (click < 0.05f || click > 1.f) click = 0.97f; }
    }
    return click;
}
static void fill_state(uint8_t *buf, uint32_t size, Dev *d, const PadState *s){
    uint8_t st[0x110];
    memset(st, 0, sizeof st);
    for (int a = 0; a < NAXES; a++){
        int src = k_axis_src[a];
        float t = s->axis[src];
        if (src >= PAD_AXIS_LT) t = t * 2.f - 1.f;          /* triggers rest at the minimum */
        int32_t v = scale_axis(t, d, a);
        memcpy(st + k_axis_ofs[a], &v, 4);
    }
    uint32_t b = s->buttons;
    uint32_t pov[4] = { pov_of(!!(b & 1u << PAD_DUP), !!(b & 1u << PAD_DDOWN),
                               !!(b & 1u << PAD_DLEFT), !!(b & 1u << PAD_DRIGHT)),
                        stick_pov(d, s->axis[PAD_AXIS_LX], s->axis[PAD_AXIS_LY]),
                        0xFFFFFFFFu, 0xFFFFFFFFu };
    memcpy(st + 0x20, pov, sizeof pov);
    float click = trigger_click();
    /* A trigger the game reads as a pedal presses its button at the end of
     * its travel (the digital top of the pedal, see the default layout).  One
     * it reads as no axis is a plain button (shifting, in the PS2 layout): it
     * presses at half travel and lets go below 0.4.  Not while the Joypad
     * page waits for the steering or a pedal (+0x33c 1..4): a trigger should
     * bind there as its axis (past 5 % of its travel), and the page looks at
     * the buttons first (0x5ca730 (0x5ca720)), so a fast pull could bind the
     * button. */
    uint32_t ch = dev_channel(d);
    int axis_bind = ch && MR32(ch + 0x33cu) - 1u < 4u;
    for (int k = 0; k < 2; k++){
        float v = s->axis[k ? PAD_AXIS_RT : PAD_AXIS_LT];
        int was = d->trig[k];
        if (click > 1.f) d->trig[k] = 0;
        else if (!ch || axis_bind || chan_reads_axis(ch, k_axis_ofs[k ? 5 : 2])) d->trig[k] = v >= click;
        else d->trig[k] = v >= (d->trig[k] ? 0.4f : 0.5f);
        if (d->trig[k] != was && pad_log())
            fprintf(stderr, "[pad] %s trigger button (%d) %s\n", k ? "right" : "left", 10 + k, d->trig[k] ? "down" : "up");
    }
    for (int i = 0; i < NBTNS; i++){
        int src = k_btn_src[i];
        int on = src == SRC_LT_FULL ? d->trig[0] : src == SRC_RT_FULL ? d->trig[1] : !!(b & (1u << src));
        if (on) st[0x30 + i] = 0x80;
    }
    memcpy(buf, st, size < sizeof st ? size : sizeof st);
}

/* ---- front-end keystrokes ----------------------------------------------------------
 * Some front-end input exists only as characters from the window procedure
 * (FESendKeystroke), not as DirectInput actions: text fields (the profile
 * name) take Enter and Escape that way, and the "Are you sure you want to
 * quit?" prompt opens on 'Q'/'q'.  A keyboard key produces both the action and
 * the character.  So while the game is in the front end (GameFlowManager
 * [0x8654a4] == 3) A, B and View also post Enter, Escape and Q.  (In a text
 * field View therefore types a 'q', as the Q key would.)
 * NFSU2_PAD_FE_KEYS=0 (or off) turns this off. */
static void fe_key(int *down, int pressed, int released, int fe, uint32_t vk, uint32_t scan,
                   uint32_t ch){
    uint32_t lp = 1u | (scan << 16);
    if (pressed && fe && !*down){
        kbd_post(0x0100u, vk, lp);                            /* WM_KEYDOWN */
        kbd_post(0x0102u, ch, lp);                            /* WM_CHAR */
        *down = 1;
        if (pad_log()) fprintf(stderr, "[pad] front end: keystroke 0x%02x\n", vk);
    } else if (released && *down){
        kbd_post(0x0101u, vk, lp | 0xC0000000u);              /* WM_KEYUP */
        *down = 0;
    }
}
static void fe_keys(Dev *d, uint32_t buttons){
    static int on = -1;
    if (on < 0) on = gamepad_env_flag("NFSU2_PAD_FE_KEYS", 1);
    uint32_t press = buttons & ~d->fe_prev, rel = d->fe_prev & ~buttons;
    d->fe_prev = buttons;
    if (!on || !mem_is_committed(G_FLOW + 3u)) return;
    int fe = MR32(G_FLOW) == 3u;
    fe_key(&d->fe_down[0], !!(press & 1u << PAD_A), !!(rel & 1u << PAD_A), fe, 0x0D, 0x1C, 0x0D);
    fe_key(&d->fe_down[1], !!(press & 1u << PAD_B), !!(rel & 1u << PAD_B), fe, 0x1B, 0x01, 0x1B);
    fe_key(&d->fe_down[2], !!(press & 1u << PAD_BACK), !!(rel & 1u << PAD_BACK), fe, 'Q', 0x10, 'q');
}

/* ---- the default layout ------------------------------------------------------------
 * Tables of 32 action ids: buttons 0..15, then per POV 0..3 the directions
 * down, up, left, right (the channel tests cos/sin of the hat angle in that
 * order).  The ids are the uAppData values of the game's keyboard action
 * maps, i.e. bits of the channel's action mask.
 *
 * In game this is the game's own built-in layout for its known gamepads
 * (entry 2, Logitech Dual Action / RumblePad 2: X brake, A throttle, B look
 * back, Y camera, LB nitrous, RB e-brake, LT/RT shift, Back reset, Start
 * pause, sticks hydraulics, D-pad engage/legend/map/SMS), except that
 * throttle and brake move to the analog triggers and shifting moves to the
 * buttons they free (A shift up, X shift down).  A trigger pressed to the end
 * also sends the digital throttle/brake: the analog path tops out at channel
 * byte 253 and the game's throttle curve (steep above 0.95) then gives 0.958,
 * the digital 1.0.
 * Front end: A select, B back, X customise ("C"), Y preset ("P"), LB/RB
 * L1/R1, Menu = FENG_START (the "comma" action, as on Xbox ports), View =
 * quit ("Q"; the prompt itself comes from the posted 'q', see fe_keys),
 * D-pad and left stick navigate.
 * The game's generic defaults (no profile) do not fit this pad: no pause or
 * reset, and the combined pedal axis would be Rz, our right trigger, which
 * rests at -10000 and so reads as full throttle. */
static const uint32_t g_prof_game[32] = {
    0x07, 0x09, 0x08, 0x0a, 0x06, 0x05, 0x0e, 0x0c, 0x16, 0x13, 0x02, 0x01, 0, 0, 0, 0,
    0x12, 0x0f, 0x10, 0x11,   0, 0, 0, 0,   0, 0, 0, 0,   0, 0, 0, 0 };
static const uint32_t g_prof_fe[32] = {
    0x1f, 0x22, 0x23, 0x2e, 0x26, 0x27, 0x2f, 0x24, 0, 0, 0, 0, 0, 0, 0, 0,
    0x1c, 0x1b, 0x1d, 0x1e,   0x1c, 0x1b, 0x1d, 0x1e,   0, 0, 0, 0,   0, 0, 0, 0 };

static void apply_profile(uint32_t ch){
    for (int i = 0; i < 32; i++){
        MR32(ch + 0x018 + 4u * (uint32_t)i) = g_prof_game[i];
        MR32(ch + 0x098 + 4u * (uint32_t)i) = g_prof_fe[i];
        MR32(ch + 0x118 + 4u * (uint32_t)i) = 0;            /* secondary tables unused */
        MR32(ch + 0x198 + 4u * (uint32_t)i) = 0;
    }
    /* analog: steer = X, throttle = Rz (right trigger), brake = Z (left
     * trigger), as separate pedals (what the Joypad page stores when two
     * different axes are bound).  The channel turns them into +0x12 steer and
     * +0x10 throttle / +0x11 brake, 0..254. */
    MR32(ch + 0x344) = 0x00;  MR32(ch + 0x354) = 1;          /* steer: offset, sign */
    MR32(ch + 0x348) = 0x14;  MR32(ch + 0x358) = 1;          /* throttle */
    MR32(ch + 0x34c) = 0x08;  MR32(ch + 0x35c) = 1;          /* brake */
    MR32(ch + 0x350) = 0x14;  MR32(ch + 0x360) = 1;          /* combined pedal (unused) */
    MR8(ch + 0x364) = 1; MR8(ch + 0x365) = 1; MR8(ch + 0x366) = 1;
    MR8(ch + 0x367) = 0; MR8(ch + 0x368) = 0;
    if (pad_log()) fprintf(stderr, "[pad] default pad layout applied to input channel 0x%08x\n", ch);
}
/* 0x5b81c0 (0x5b81b0)(devinfo, tableA, tableB): the game's built-in profile
 * lookup, called from the channel set-up 0x5c11b0 (0x5c11a0) (device attach,
 * and "reset to default" on the Joypad page).  cdecl, returns al = 1 when
 * found. */
void sub_005b81c0_orig(CPU *c);
void sub_005b81c0(CPU *c){
    uint32_t ddi = MR32(c->esp + 4u), ta = MR32(c->esp + 8u);
    int ours = pad_mode() != MODE_OFF && ddi ? dipad_guid(ddi + 4u) : 0;
    if (ours && ta > 0x18u){
        apply_profile(ta - 0x18u);
        c->eax = (c->eax & 0xFFFFFF00u) | 1u;
        POP32(c->eip);
        return;
    }
    sub_005b81c0_orig(c);
}

/* ---- binding on the Joypad page -------------------------------------------------------
 * The page has two columns.  For the steering and the pedals (actions 1..4)
 * an axis, while one is on, shows in the first column and the action's
 * button in the second.  Binding a button (0x5b8470 (0x5b8460)) or a hat
 * direction (0x5c1730 (0x5c1720)) replaces the action's other buttons but
 * leaves its axis on, and nothing on the page turns an axis off: with the gas
 * and brake moved to buttons and the triggers to shifting (the PS2 layout), a
 * trigger still accelerated or braked as it shifted.  Here a button or hat
 * direction bound to the throttle or the brake in the first column takes the
 * axis's place, as the column shows: the axis goes off (and pulling a trigger
 * there binds it again).  The steering keeps its axis (left and right are the
 * one stick axis), and so does one axis bound to both pedals (+0x368).
 * Channel (thiscall ecx): +0x33c the action being bound, +0x340 the column (0
 * the first), +0x365/+0x366 the throttle/brake axis on; saved with the
 * profile. */
static void bind_takes_axis(uint32_t ch){
    if (!ch || !mem_is_committed(ch + 0x36bu)) return;
    uint32_t act = MR32(ch + 0x33cu);
    if ((act != 1u && act != 2u) || MR32(ch + 0x340u) != 0u || MR8(ch + 0x368u) || !MR8(ch + 0x364u + act)) return;
    MR8(ch + 0x364u + act) = 0;
    if (pad_log()) fprintf(stderr, "[pad] %s bound to a button: its axis is off\n", act == 1u ? "throttle" : "brake");
}
void sub_005b8470_orig(CPU *c);
void sub_005b8470(CPU *c){ bind_takes_axis(c->ecx); sub_005b8470_orig(c); }
void sub_005c1730_orig(CPU *c);
void sub_005c1730(CPU *c){ bind_takes_axis(c->ecx); sub_005c1730_orig(c); }

/* ---- the Controls page ---------------------------------------------------------------
 * The Controls page lists the devices it found when it opened (0x4ace00).
 * Losing the pad while it is open crashes the game as soon as one of the
 * pad's bindings is edited (Enter: 0x4f9340 reads a NULL object at +0x64),
 * so there an unplugged pad reads at rest and is lost once the page is left.
 * The page is found by name: the top front-end package (GetTopPackage
 * 0x50c8e0: the front-end manager [0x8384c4], its package list +8, that
 * package's FNGInfo +0xe4, whose name pointer offset is found once by
 * scanning) or the screen the game's log last named. */
static const char *fng_str(uint32_t p){
    if (!p || !mem_is_committed(p) || !mem_is_committed(p + 63)) return 0;
    const char *s = (const char *)(g_mem + p);
    int n = 0;
    while (n < 63 && s[n] >= 0x20 && s[n] < 0x7f) n++;
    if (s[n] != 0 || n < 5 || strncasecmp(s + n - 4, ".fng", 4)) return 0;
    return s;
}
static const char *fe_top(void){
    static int off = -1;
    if (!mem_is_committed(G_FE_MGR + 3u)) return 0;
    uint32_t fe = MR32(G_FE_MGR);
    if (!fe || !mem_is_committed(fe + 11)) return 0;
    uint32_t mg = MR32(fe + 8);
    if (!mg || !mem_is_committed(mg + 0xe7)) return 0;
    uint32_t pk = MR32(mg + 0xe4);
    if (!pk || !mem_is_committed(pk + 255)) return 0;
    if (off >= 0){ const char *s = fng_str(MR32(pk + (uint32_t)off)); if (s) return s; }
    for (int o = 0; o < 256; o += 4){
        const char *s = fng_str(MR32(pk + (uint32_t)o));
        if (s){ off = o; return s; }
    }
    return 0;
}
/* The screen the game last initialised or switched to, from its debug log
 * (overrides.c's sub_0050d510: "Init Package %s", "SwitchFEngPackages from %s
 * to %s"), and the ones initialised in the same frame: the top package can be
 * a backdrop (GarageMain.fng) under the screen in use. */
long metal_frames(void);                                  /* metal.m */
static char g_screen[64], g_batch[8][64];
static int g_nbatch; static long g_batch_frame = -1;
static const char *gstr64(uint32_t p){
    return p && mem_is_committed(p) && mem_is_committed(p + 63) ? (const char *)(g_mem + p) : 0;
}
void dipad_fe_log(CPU *c){
    const char *f = gstr64(MR32(c->esp + 4u)), *nm = 0;
    if (!f) return;
    if (!strncmp(f, "Init Package %s", 15)) nm = gstr64(MR32(c->esp + 8u));
    else if (!strncmp(f, "SwitchFEngPackages from %s to %s", 32)) nm = gstr64(MR32(c->esp + 12u));
    if (!nm) return;
    long fr = metal_frames();
    if (fr != g_batch_frame){ g_nbatch = 0; g_batch_frame = fr; }
    if (g_nbatch < 8) snprintf(g_batch[g_nbatch++], 64, "%.63s", nm);
    snprintf(g_screen, sizeof g_screen, "%.63s", nm);
}
/* name is the top package, the current screen or one initialised with it */
int dipad_fe_is(const char *name){
    const char *t = fe_top();
    if ((t && !strcasecmp(t, name)) || (g_screen[0] && !strcasecmp(g_screen, name))) return 1;
    for (int i = 0; i < g_nbatch; i++) if (!strcasecmp(g_batch[i], name)) return 1;
    return 0;
}
/* for logs (tests: runtime/autotest.c) */
const char *dipad_fe_top(void){ return g_screen[0] ? g_screen : fe_top(); }
/* a dword of guest memory, 0 when not committed (tests: runtime/autotest.c) */
uint32_t dipad_peek32(uint32_t a){ return mem_is_committed(a + 3u) ? MR32(a) : 0u; }
static int on_controls_page(void){
    if (!mem_is_committed(G_FLOW + 3u) || MR32(G_FLOW) != 3u) return 0;
    return dipad_fe_is("UI_Options_PC_Controller.fng");
}

/* ---- IDirectInputDevice8 methods for the pad --------------------------------------- */
static void write_objinst(uint32_t p, uint32_t size, int i, int fam){
    if (!size || size > 0x13cu) size = 0x13cu;
    mem_commit(p, size);
    memset(g_mem + p, 0, size);
    MR32(p) = size;
    static const uint8_t tail[8] = {0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00};
    uint32_t g = i < NAXES ? k_axis_guid[i] : i < NAXES + NPOVS ? 0xA36D02F2u : 0xA36D02F0u;
    put_guid(p + 0x04, g, 0xC9F3, 0x11CF, tail);
    MR32(p + 0x14) = obj_ofs(i);
    int act = i < 2 && dipad_ff_on();                    /* X and Y: force-feedback actuators */
    MR32(p + 0x18) = obj_type(i) | (act ? DIDFT_FFACTUATOR : 0u);
    MR32(p + 0x1c) = (i < NAXES ? DIDOI_ASPECTPOSITION : 0u) | (act ? DIDOI_FFACTUATOR : 0u);
    if (act && size >= 0x12cu){ MR32(p + 0x124) = 10000u; MR32(p + 0x128) = 1u; }   /* dwFFMaxForce, dwFFForceResolution */
    if (size >= 0x124u) snprintf((char *)(g_mem + p + 0x20), 260, "%s", obj_name(i, fam));
    if (size >= 0x134u){
        MR16(p + 0x130) = i >= NAXES + NPOVS ? 9u : 1u;      /* Button / Generic Desktop */
        MR16(p + 0x132) = i < NAXES ? k_axis_usage[i] : i < NAXES + NPOVS ? 0x39u
                        : (uint16_t)(i - NAXES - NPOVS + 1);
    }
}

static void dipad_input_log(void);
uint32_t dipad_call(CPU *c, uint32_t self, const char *nm, int nargs, const uint32_t *a){
    Dev *d = dev_of(self);
    PadState s; gamepad_read(&s);
    native_controls_filter_pad(&s); native_scene_filter_pad(&s);
    int lost = pad_mode() == MODE_HOTPLUG && !s.connected && !on_controls_page();
    (void)nargs;
    if (!strcmp(nm, "GetDeviceState")){
        uint32_t cb = a[1], p = a[2];
        /* Unplugged (hotplug mode): answer two polls with the pad at rest
         * before DIERR_INPUTLOST.  The game drops the device's channel with
         * its last values, which then stay applied (steering, throttle, held
         * buttons) until its next 32-frame rescan. */
        if (lost && d->rest >= 2){
            if (d->rest == 2 && pad_log()) fprintf(stderr, "[pad] unplugged: DIERR_INPUTLOST\n");
            d->rest = 3;
            return DIERR_INPUTLOST;
        }
        d->rest = lost ? d->rest + 1 : 0;
        if (!p || !cb || cb > 0x110u) return DIERR_INVALIDPARAM;
        mem_commit(p, cb);
        PadState at = s;
        if (lost) memset(&at, 0, sizeof at);
        fill_state(g_mem + p, cb, d, &at);
        dipad_ff_frame();                                     /* rumble */
        fe_keys(d, at.buttons);
        dipad_input_log();
        if (pad_log() && s.buttons != d->last_btn){
            fprintf(stderr, "[pad] buttons 0x%04x  LX %+.2f LY %+.2f LT %.2f RT %.2f\n", s.buttons,
                    (double)s.axis[PAD_AXIS_LX], (double)s.axis[PAD_AXIS_LY],
                    (double)s.axis[PAD_AXIS_LT], (double)s.axis[PAD_AXIS_RT]);
            d->last_btn = s.buttons;
        }
        return DI_OK;
    }
    /* An unplugged pad fails GetDeviceState only: the game polls first and,
     * when Poll fails, just re-acquires and returns, so only a failing
     * GetDeviceState reaches the game's release path. */
    if (!strcmp(nm, "Poll"))    return DI_NOEFFECT;
    if (!strcmp(nm, "Acquire")) return DI_OK;
    if (!strcmp(nm, "Unacquire") || !strcmp(nm, "SetCooperativeLevel") ||
        !strcmp(nm, "SetEventNotification")) return DI_OK;
    if (!strcmp(nm, "SetDataFormat")){
        uint32_t df = a[1];
        uint32_t sz = (df && mem_is_committed(df + 15)) ? MR32(df + 12) : 0;
        if (sz != 0x110u && sz != 0x50u){
            fprintf(stderr, "[pad] SetDataFormat: unsupported data size %u\n", sz);
            return DIERR_INVALIDPARAM;
        }
        MR32(self + 4) = df;
        return DI_OK;
    }
    if (!strcmp(nm, "GetCapabilities")){
        uint32_t p = a[1];
        if (!p || !mem_is_committed(p + 3)) return DIERR_INVALIDPARAM;
        uint32_t sz = MR32(p); if (sz < 0x18u || sz > 0x2cu) sz = 0x2cu;
        mem_commit(p, sz); memset(g_mem + p, 0, sz); MR32(p) = sz;
        MR32(p + 0x04) = 0x00000001u;                         /* DIDC_ATTACHED */
        MR32(p + 0x08) = PAD_DEVTYPE;
        MR32(p + 0x0c) = NAXES; MR32(p + 0x10) = NBTNS; MR32(p + 0x14) = NPOVS;
        if (dipad_ff_on()){
            MR32(p + 0x04) |= DIDC_FORCEFEEDBACK;
            if (sz >= 0x2cu){ MR32(p + 0x18) = 10000u; MR32(p + 0x1c) = 1000u; MR32(p + 0x28) = 1u; }   /* sample period, min. time resolution, driver version */
        }
        return DI_OK;
    }
    if (!strcmp(nm, "GetDeviceInfo")){
        uint32_t p = a[1];
        if (!p || !mem_is_committed(p + 3)) return DIERR_INVALIDPARAM;
        write_devinst(p, MR32(p), &s);
        return DI_OK;
    }
    if (!strcmp(nm, "EnumObjects")){
        uint32_t cb = a[1], ref = a[2], fl = a[3];
        if (!cb) return DIERR_INVALIDPARAM;
        static uint32_t oi = 0;
        if (!oi) oi = com_scratch(0x140);
        for (int i = 0; i < NOBJS; i++){
            uint32_t t = obj_type(i);
            if ((fl & DIDFT_TYPEMASK) && !(fl & t & DIDFT_TYPEMASK)) continue;   /* DIDFT_ALL = 0 */
            if ((fl & DIDFT_FFACTUATOR) && !(i < 2 && dipad_ff_on())) continue;
            write_objinst(oi, 0x13cu, i, s.family);
            uint32_t args[2] = { oi, ref };
            if (call_guest(c, cb, 2, args) == 0u) break;      /* DIENUM_STOP */
        }
        return DI_OK;
    }
    if (!strcmp(nm, "GetObjectInfo")){
        uint32_t p = a[1], obj = a[2], how = a[3];
        int i = obj_find(obj, how);
        if (i < 0) return DIERR_OBJECTNOTFOUND;
        if (!p || !mem_is_committed(p + 3)) return DIERR_INVALIDPARAM;
        write_objinst(p, MR32(p), i, s.family);
        return DI_OK;
    }
    if (!strcmp(nm, "SetProperty") || !strcmp(nm, "GetProperty")){
        int set = nm[0] == 'S';
        uint32_t prop = a[1], h = a[2];
        if (!h || !mem_is_committed(h + 0x17)) return DIERR_INVALIDPARAM;
        uint32_t obj = MR32(h + 8), how = MR32(h + 12);
        int lo = 0, hi = NAXES;                               /* DIPH_DEVICE: every axis */
        if (how){ int i = obj_find(obj, how);
                  if (i < 0) return DIERR_OBJECTNOTFOUND;
                  if (prop >= 4u && prop <= 6u && i >= NAXES) return DIERR_UNSUPPORTED;
                  lo = i; hi = i + 1; }
        switch (prop){
        case 1u:  if (set) d->bufsize = MR32(h + 16); else MR32(h + 16) = d->bufsize; return DI_OK;
        case 2u:  if (set) d->axismode = MR32(h + 16); else MR32(h + 16) = d->axismode; return DI_OK;
        case 4u:                                              /* RANGE */
            if (set){
                int32_t mn = (int32_t)MR32(h + 16), mx = (int32_t)MR32(h + 20);
                if (mn >= mx) return DIERR_INVALIDPARAM;
                for (int i = lo; i < hi; i++){ d->mn[i] = mn; d->mx[i] = mx; }
                if (pad_log()) fprintf(stderr, "[pad] SetProperty RANGE obj 0x%x how %u: %d..%d\n", obj, how, mn, mx);
            } else { MR32(h + 16) = (uint32_t)d->mn[lo]; MR32(h + 20) = (uint32_t)d->mx[lo]; }
            return DI_OK;
        case 5u: case 6u: {                                   /* DEADZONE, SATURATION */
            uint32_t *v = prop == 5u ? d->dz : d->sat;
            if (set){ uint32_t x = MR32(h + 16); if (x > 10000u) return DIERR_INVALIDPARAM;
                      for (int i = lo; i < hi; i++) v[i] = x;
                      if (pad_log()) fprintf(stderr, "[pad] SetProperty %s obj 0x%x: %u\n", prop == 5u ? "DEADZONE" : "SATURATION", obj, x); }
            else MR32(h + 16) = v[lo];
            return DI_OK; }
        case 9u:  if (set) d->autocenter = MR32(h + 16); else MR32(h + 16) = d->autocenter; return DI_OK;
        case 7u: case 8u: return dipad_ff_prop(set, prop, h);   /* FFGAIN, FFLOAD */
        case 3u:  if (!set){ MR32(h + 16) = 1; return DI_OK; } return DIERR_UNSUPPORTED;   /* GRANULARITY */
        case 15u: if (!set){ MR32(h + 16) = 0; return DI_OK; } return DIERR_UNSUPPORTED;   /* JOYSTICKID */
        case 24u: if (!set){ MR32(h + 16) = family_vidpid(s.family); return DI_OK; } return DIERR_UNSUPPORTED;
        default:  return set ? DI_OK : DIERR_UNSUPPORTED;
        }
    }
    if (!strcmp(nm, "GetDeviceData")){                        /* the game polls state only */
        uint32_t pn = a[3];
        if (pn && mem_is_committed(pn + 3)) MR32(pn) = 0;
        return lost ? DIERR_INPUTLOST : DI_OK;
    }
    /* force feedback: played as rumble with NFSU2_FF=1, otherwise answered
     * as a device without force feedback (dinput_ff.c) */
    { int64_t r = dipad_ff_dev_call(c, nm, a); if (r >= 0) return (uint32_t)r; }
    if (!strcmp(nm, "Escape")) return DI_OK;
    if (!strcmp(nm, "BuildActionMap") || !strcmp(nm, "SetActionMap") ||
        !strcmp(nm, "GetImageInfo") || !strcmp(nm, "RunControlPanel")) return DIERR_UNSUPPORTED;
    return DI_OK;
}

/* ---- the player's input controller (logs, test scripts) ---------------------------
 * 0x407750 is the player's steering joy-event handler (cdecl: port, id,
 * value, ctx).  ctx is the object the car reads its input from: +0x2c8 steer
 * (-1..1, positive = left), +0x2d4 throttle, +0x2dc brake, +0x2ec e-brake
 * (0..1).  Only observed: dipad_input_ctx() for test scripts ("@in+<offset>"),
 * and with NFSU2_PAD_LOG the values whenever they change (read at each pad
 * poll). */
static uint32_t g_in_ctx;
uint32_t dipad_input_ctx(void){ return g_in_ctx; }
static void dipad_input_log(void){
    if (!pad_log() || !g_in_ctx || !mem_is_committed(g_in_ctx + 0x2efu)) return;
    static float last[4] = {9, 9, 9, 9};
    float v[4] = { MRF32(g_in_ctx + 0x2c8u), MRF32(g_in_ctx + 0x2d4u), MRF32(g_in_ctx + 0x2dcu), MRF32(g_in_ctx + 0x2ecu) };
    int ch = 0;
    for (int i = 0; i < 4; i++) if (fabsf(v[i] - last[i]) > 0.05f){ ch = 1; last[i] = v[i]; }
    if (ch) fprintf(stderr, "[pad] car input: steer %+.2f throttle %.2f brake %.2f e-brake %.2f\n",
                    (double)v[0], (double)v[1], (double)v[2], (double)v[3]);
}
void sub_00407750_orig(CPU *c);
void sub_00407750(CPU *c){
    uint32_t ctx = MR32(c->esp + 0x10u);
    if (ctx != g_in_ctx){
        g_in_ctx = ctx;
        if (pad_log()) fprintf(stderr, "[pad] player input controller at 0x%08x\n", ctx);
    }
    sub_00407750_orig(c);
}
