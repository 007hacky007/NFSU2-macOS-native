/* gamepad.h -- the virtual game pad between GameController.framework
 * (runtime/gamepad.m) and the DirectInput8 gamepad device the game sees
 * (runtime/dinput_pad.c).
 *
 * Exactly one virtual pad exists.  The first connected controller with an
 * extended gamepad profile (Xbox, DualSense, DualShock 4, Switch Pro, MFi)
 * drives it; a synthetic pad (NFSU2_PAD_FAKE / NFSU2_PAD_SEQ, or a test
 * script through gamepad_synth_*) can drive it instead, so a scripted run
 * takes the same path as a real controller from here on.
 * Buttons are positional, Xbox names: A = bottom face button (Cross on a
 * PlayStation pad), B = right, X = left, Y = top.
 * Ported from th0mk's nfsu2-web runtime/gamepad.h (MIT). */
#ifndef GAMEPAD_H
#define GAMEPAD_H
#include <stdint.h>

enum {
    PAD_A, PAD_B, PAD_X, PAD_Y, PAD_LB, PAD_RB, PAD_BACK, PAD_START,
    PAD_LS, PAD_RS, PAD_HOME, PAD_DUP, PAD_DDOWN, PAD_DLEFT, PAD_DRIGHT,
    PAD_NBUTTONS
};
enum { PAD_AXIS_LX, PAD_AXIS_LY, PAD_AXIS_RX, PAD_AXIS_RY, PAD_AXIS_LT, PAD_AXIS_RT, PAD_NAXES };
/* controller family: picks the button names and the reported VID/PID */
enum { PADF_GENERIC, PADF_XBOX, PADF_PLAYSTATION, PADF_NINTENDO };

typedef struct {
    int      connected;          /* a controller (or the synthetic pad) drives the pad */
    uint32_t buttons;            /* 1u << PAD_x */
    float    axis[PAD_NAXES];    /* sticks -1..1 (+x right, +y down), triggers 0..1 */
    int      family;             /* PADF_x */
    int      synthetic;          /* driven by NFSU2_PAD_FAKE / _SEQ or a test script */
    char     name[64];           /* "Xbox Wireless Controller", ... */
} PadState;

/* An on/off option: a number is on unless 0; off/no/false and on/yes/true
 * (any other word) as written; unset or empty gives dflt. */
int  gamepad_env_flag(const char *nm, int dflt);
/* Starts GameController discovery (idempotent; any thread). */
void gamepad_init(void);
/* Snapshot of the virtual pad after dead zones and the focus rule; returns
 * s->connected. */
int  gamepad_read(PadState *s);

/* test scripts: a synthetic controller (connects on first use) */
void gamepad_synth_connect(int on);
void gamepad_synth_button(int b, int down);
void gamepad_synth_axis(int a, float v);
int  gamepad_button_by_name(const char *nm);   /* "A", "LB", "START", "DUP", ... or -1 */
int  gamepad_axis_by_name(const char *nm);     /* "LX" .. "RT" or -1 */
#endif
