/* rumble_unit.m -- runtime/rumble.m with fake haptic engines (tests/rumble_unit.sh):
 * which motors a controller's haptic localities give, the levels on them,
 * and when they stop (focus loss, the levels no longer coming, a second at
 * zero, the controller going away, the app quitting), without a controller.
 * A software GCController (no haptics) checks the real path for a pad
 * without motors.  The CoreHaptics motor itself (NFSHapticMotor) needs a
 * controller with haptics and is not run here.
 *   rumble_unit           the checks
 *   rumble_unit strength  NFSU2_FF_STRENGTH (set by the .sh) scales the levels
 * Exit status 0 when every check passes. */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "gamepad.h"
#include "rumble.h"

long metal_frames(void){ return 0; }

static int g_fail;
static void check(const char *what, int ok){
    printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) g_fail++;
}
static int near(float a, float b){ return fabsf(a - b) < 0.002f; }

@interface FakeMotor : NSObject <NFSRumbleMotor>
@property NSString *loc;
@property float sharp, last;
@property int starts, stops, sends, running, failStart;
@end
@implementation FakeMotor
- (BOOL)rumbleStart { if (self.failStart){ self.failStart--; return NO; } self.starts++; self.running = 1; return YES; }
- (void)rumbleIntensity:(float)v { self.sends++; self.last = v; }
- (void)rumbleStop { self.stops++; self.running = 0; self.last = 0; }
@end

static NSMutableArray<FakeMotor *> *g_made;
static NFSRumbleFactory factory(NSString *refuse){
    return ^id<NFSRumbleMotor>(NSString *l, float sharp){
        if (refuse && [l isEqualToString:refuse]) return nil;
        FakeMotor *m = [FakeMotor new]; m.loc = l; m.sharp = sharp;
        [g_made addObject:m];
        return m;
    };
}
static void bind_pad(NSArray *loc, NSString *refuse){
    g_made = [NSMutableArray array];
    rumble_bind(loc ? [NSSet setWithArray:loc] : nil, "Test Pad", loc ? factory(refuse) : nil);
    rumble_sync();
}
static void level(float s, float w){ gamepad_rumble(s, w); rumble_sync(); }
static void post(NSString *nm){ [[NSNotificationCenter defaultCenter] postNotificationName:nm object:NSApp]; rumble_sync(); }
static NSArray *dual(void){
    return @[GCHapticsLocalityDefault, GCHapticsLocalityAll, GCHapticsLocalityHandles,
             GCHapticsLocalityLeftHandle, GCHapticsLocalityRightHandle];
}

static void run_checks(void){
    printf("controllers without haptics\n");
    bind_pad(nil, nil);
    check("nil haptics (an MFi pad): no motors", !gamepad_rumble_ok());
    level(1, 1);
    check("levels for it go nowhere", g_made.count == 0);
    bind_pad(@[], nil);
    check("no supported locality: no motors", !gamepad_rumble_ok() && g_made.count == 0);
    GCController *soft = [GCController controllerWithExtendedGamepad];
    g_made = [NSMutableArray array];
    rumble_controller(soft); rumble_sync();
    check("a software GCController (haptics nil) through rumble_controller: no motors", !gamepad_rumble_ok());
    level(0.5f, 0.5f);

    printf("two motors (Xbox, DualShock 4, DualSense: left and right handles)\n");
    bind_pad(dual(), nil);
    FakeMotor *st = g_made.count > 0 ? g_made[0] : nil, *wk = g_made.count > 1 ? g_made[1] : nil;
    check("one engine per handle: left strong (low sharpness), right weak",
          gamepad_rumble_ok() && g_made.count == 2 && [st.loc isEqualToString:GCHapticsLocalityLeftHandle]
          && [wk.loc isEqualToString:GCHapticsLocalityRightHandle] && st.sharp < wk.sharp);
    check("nothing starts before a level", st.starts == 0 && wk.starts == 0);
    level(0, 0);
    check("levels of zero start nothing", st.starts == 0 && wk.starts == 0);
    level(0.8f, 0.3f);
    check("strong 0.8 weak 0.3: both started at those intensities", st.running && wk.running && near(st.last, 0.8f) && near(wk.last, 0.3f));
    int sends = st.sends;
    level(0.805f, 0.3f);
    check("a change under 0.01 is not sent", st.sends == sends);
    level(0.6f, 0.3f);
    check("a bigger one is", st.sends == sends + 1 && near(st.last, 0.6f));
    level(1.7f, NAN);
    check("out of range and NaN levels: clamped to 1 and 0", near(st.last, 1.f) && near(wk.last, 0.f));
    level(0, 0);
    check("zero: intensity 0, engines still running", st.running && wk.running && near(st.last, 0) && near(wk.last, 0));
    for (int i = 0; i < 25; i++){ usleep(50000); gamepad_rumble(0, 0); }
    rumble_tick_now();
    check("after a second at zero the engines stop", !st.running && !wk.running && st.stops == 1 && wk.stops == 1);
    level(0.5f, 0.5f);
    check("the next level starts them again", st.running && st.starts == 2 && near(st.last, 0.5f));
    usleep(300000); rumble_tick_now();
    check("no level for 300 ms (a game that stopped polling): intensity 0", near(st.last, 0) && near(wk.last, 0));
    level(0.5f, 0.5f);
    check("levels coming again play again", near(st.last, 0.5f));

    printf("focus\n");
    post(NSApplicationDidResignActiveNotification);
    check("app inactive: motors stopped at once", !st.running && !wk.running);
    level(0.9f, 0.9f);
    check("levels while inactive are not played", !st.running && !wk.running);
    post(NSApplicationDidBecomeActiveNotification);
    level(0.9f, 0.9f);
    check("active again: played", st.running && near(st.last, 0.9f));

    printf("the controller goes away\n");
    rumble_controller(nil); rumble_sync();
    check("motors stopped and let go", !gamepad_rumble_ok() && !st.running && !wk.running);
    level(1, 1);
    check("levels after it go nowhere", !st.running);

    printf("one motor (only the default locality)\n");
    bind_pad(@[GCHapticsLocalityDefault], nil);
    FakeMotor *one = g_made.count ? g_made[0] : nil;
    check("one engine, default locality", g_made.count == 1 && [one.loc isEqualToString:GCHapticsLocalityDefault]);
    level(0.4f, 0.4f);
    check("both levels on it: strong + half the weak (0.6)", near(one.last, 0.6f));
    level(0.9f, 0.9f);
    check("clamped at 1", near(one.last, 1.f));
    bind_pad(dual(), GCHapticsLocalityRightHandle);
    check("a handle without an engine: one motor on the handles instead", g_made.count == 2 && gamepad_rumble_ok()
          && [g_made[1].loc isEqualToString:GCHapticsLocalityHandles]);
    check("the motor made before it is never started", g_made[0].starts == 0);
    bind_pad(dual(), nil);
    st = g_made[0];
    st.failStart = 1;
    level(0.7f, 0);
    check("an engine that does not start: nothing played, no crash", !st.running && st.sends == 0);
    level(0.7f, 0);
    check("tried again with the next level", st.running && near(st.last, 0.7f));

    printf("the app quits\n");
    rumble_shutdown();
    check("motors stopped, none bound", !st.running && !gamepad_rumble_ok());
    level(1, 1);
    check("levels after it go nowhere", !st.running);
    bind_pad(dual(), nil);
    check("no motors bound after it", !gamepad_rumble_ok() && g_made.count == 0);
}

int main(int argc, char **argv){
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc > 1 && !strcmp(argv[1], "strength")){
            printf("strength (NFSU2_FF_STRENGTH=%s)\n", getenv("NFSU2_FF_STRENGTH") ?: "");
            bind_pad(dual(), nil);
            level(0.8f, 0.4f);
            check("strength 50: half the levels", near(g_made[0].last, 0.4f) && near(g_made[1].last, 0.2f));
            rumble_shutdown();
        } else run_checks();
        printf(g_fail ? "rumble_unit: %d FAILED\n" : "rumble_unit: all passed\n", g_fail);
    }
    return g_fail != 0;
}
