/* gamepad_harness.m -- checks runtime/gamepad.m against GameController.framework
 * without a physical controller (tests/gamepad_harness.sh builds and runs it).
 *
 * Software controllers (+[GCController controllerWithExtendedGamepad]) are
 * snapshots: their element values can be set, but they never fire
 * valueChangedHandler.  So the values are set before the controller
 * "connects" (posting GCControllerDidConnectNotification ourselves), and the
 * snapshot that pick_active() queues on the handler queue reads them.  That
 * covers the element -> PadState mapping, the dead zones, the takeover
 * order, the late-snapshot case and the focus rule; live value changes from a
 * real pad are not covered.
 *
 *   harness           the real-controller path
 *   harness synth     the synthetic pad (NFSU2_PAD_FAKE, set by the .sh)
 * Exit status 0 when every check passes.
 * Ported from th0mk's nfsu2-web tests/gamepad_harness.m (MIT). */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "gamepad.h"

long metal_frames(void){ return 0; }       /* metal.m's frame counter (NFSU2_PAD_SEQ) */

static int g_fail;
static void pump(double s){ [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static void check(const char *what, int ok){
    printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) g_fail++;
}
static int near(float a, float b){ return fabsf(a - b) < 0.002f; }
static void post(NSString *nm, id k){
    [[NSNotificationCenter defaultCenter] postNotificationName:nm object:k];
}

static void real_controllers(void){
    PadState s;
    printf("mapping and dead zones\n");
    GCController *a = [GCController controllerWithExtendedGamepad];
    GCExtendedGamepad *g = a.extendedGamepad;
    [g.buttonA setValue:1]; [g.buttonMenu setValue:1]; [g.buttonOptions setValue:1];
    [g.rightShoulder setValue:1]; [g.leftThumbstickButton setValue:1];
    [g.dpad setValueForXAxis:-1 yAxis:1];                      /* up-left */
    [g.leftThumbstick setValueForXAxis:0.5f yAxis:0.25f];       /* GC: +y up */
    [g.rightThumbstick setValueForXAxis:-1 yAxis:-1];
    [g.leftTrigger setValue:0.01f]; [g.rightTrigger setValue:0.75f];
    post(GCControllerDidConnectNotification, a); pump(0.2);
    gamepad_read(&s);
    uint32_t want = 1u << PAD_A | 1u << PAD_START | 1u << PAD_BACK | 1u << PAD_RB |
                    1u << PAD_LS | 1u << PAD_DUP | 1u << PAD_DLEFT;
    check("connected", s.connected == 1);
    check("buttons A Menu Options RB LS, D-pad up+left", s.buttons == want);
    /* radial dead zone 0.08: |(0.5, 0.25)| = 0.559 -> 0.521, direction kept;
     * y flipped to DirectInput's +down */
    check("left stick (0.5, 0.25 up) -> (0.466, -0.233)",
          near(s.axis[PAD_AXIS_LX], 0.466f) && near(s.axis[PAD_AXIS_LY], -0.233f));
    check("right stick past the rim clamps to the unit circle",
          near(s.axis[PAD_AXIS_RX], -0.707f) && near(s.axis[PAD_AXIS_RY], 0.707f));
    check("left trigger 0.01 inside its dead zone", s.axis[PAD_AXIS_LT] == 0.f);
    check("right trigger 0.75 -> 0.745", near(s.axis[PAD_AXIS_RT], 0.745f));

    printf("focus\n");
    post(NSApplicationDidResignActiveNotification, NSApp); pump(0.1);
    gamepad_read(&s);
    check("another app in front: the pad reads at rest", s.connected && !s.buttons && s.axis[PAD_AXIS_RT] == 0.f);
    post(NSApplicationDidBecomeActiveNotification, NSApp); pump(0.1);
    gamepad_read(&s);
    check("back in front, buttons still held: at rest until let go", s.connected && !s.buttons && s.axis[PAD_AXIS_LX] == 0.f);

    printf("takeover\n");
    GCController *b = [GCController controllerWithExtendedGamepad];
    [b.extendedGamepad.buttonB setValue:1];
    post(GCControllerDidConnectNotification, b); pump(0.2);
    post(GCControllerDidDisconnectNotification, a); pump(0.2);
    gamepad_read(&s);
    check("first one gone, the second (B held) still waits for a let-go", s.connected && !s.buttons);
    GCController *b2 = [GCController controllerWithExtendedGamepad];   /* the second, let go */
    post(GCControllerDidConnectNotification, b2); pump(0.1);
    post(GCControllerDidDisconnectNotification, b); pump(0.2);
    gamepad_read(&s);
    check("a controller at rest ends the wait", s.connected && !s.buttons);
    GCController *c = [GCController controllerWithExtendedGamepad];
    [c.extendedGamepad.buttonB setValue:1];
    post(GCControllerDidConnectNotification, c); pump(0.1);
    gamepad_read(&s);
    check("an older controller keeps the pad (the new one does not take over)", s.connected && !s.buttons);
    post(GCControllerDidDisconnectNotification, b2); pump(0.2);
    gamepad_read(&s);
    check("it goes: the next one drives the pad (B)", s.connected && s.buttons == 1u << PAD_B);
    post(GCControllerDidDisconnectNotification, c); pump(0.2);
    gamepad_read(&s);
    check("last one gone: not connected, at rest", !s.connected && !s.buttons &&
          s.axis[PAD_AXIS_RT] == 0.f && s.axis[PAD_AXIS_LX] == 0.f);

    printf("late snapshot\n");
    /* D connects and goes away while its first snapshot is still queued
     * behind a blocked handler queue: it must not land in the pad */
    GCController *d = [GCController controllerWithExtendedGamepad];
    [d.extendedGamepad.buttonX setValue:1]; [d.extendedGamepad.rightTrigger setValue:1];
    dispatch_async(a.handlerQueue, ^{ usleep(300000); });
    post(GCControllerDidConnectNotification, d); pump(0.05);
    post(GCControllerDidDisconnectNotification, d); pump(0.6);
    gamepad_read(&s);
    check("queue drained: still at rest", !s.connected && !s.buttons && s.axis[PAD_AXIS_RT] == 0.f);
}

/* NFSU2_PAD_FAKE="X=0.5;Y=-1;B0=1;SQUARE=1;RT=0.6;Z=0.4;POV=9000" (the .sh sets it) */
static void synthetic(void){
    PadState s;
    printf("synthetic pad\n");
    gamepad_read(&s);
    check("connected, synthetic", s.connected && s.synthetic);
    check("B0 = A, SQUARE = X, POV 9000 = D-pad right",
          s.buttons == (1u << PAD_A | 1u << PAD_X | 1u << PAD_DRIGHT));
    /* (0.5, -1): |v| = 1.118 -> clamped to the rim */
    check("X/Y = the left stick", near(s.axis[PAD_AXIS_LX], 0.447f) && near(s.axis[PAD_AXIS_LY], -0.894f));
    /* Z=0.4 after RT=0.6: upstream's combined axis, LT 0.4 and RT 0 */
    check("Z = LT +, RT -", near(s.axis[PAD_AXIS_LT], 0.388f) && s.axis[PAD_AXIS_RT] == 0.f);
    unsigned char st[272]; void gamepad_fill(unsigned char *);
    gamepad_fill(st);
    check("gamepad_fill: A and X buttons in DIJOYSTATE2", st[0x30] == 0x80 && st[0x32] == 0x80 && st[0x31] == 0);
}

int main(int argc, char **argv){
    @autoreleasepool {
        [NSApplication sharedApplication];
        setenv("NFSU2_PAD_DEADZONE", "0.08", 1);
        setenv("NFSU2_PAD_TRIGGER_DEADZONE", "0.02", 1);
        gamepad_init(); pump(0.2);
        if (argc > 1 && !strcmp(argv[1], "synth")) synthetic();
        else real_controllers();
    }
    printf("%s\n", g_fail ? "FAILED" : "all passed");
    return g_fail ? 1 : 0;
}
