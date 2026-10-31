/* rumble.m -- the controller's motors: the two levels runtime/dinput_ff.c
 * mixes from the game's force-feedback effects (gamepad_rumble), played on
 * the controller driving the pad through GameController's haptics and
 * CoreHaptics (macOS 11 and later).
 *
 * GCController.haptics is nil for a controller without haptics (most MFi
 * pads, the synthetic pad), and its supportedLocalities says where the
 * actuators are.  A pad with two rumble motors (Xbox Wireless Controller,
 * DualShock 4, DualSense) has a left and a right handle: the left one, the
 * heavy low-frequency motor, plays the strong level and the right one the
 * weak level, one CHHapticEngine each.  A controller with only the default
 * locality gets both levels combined on one engine.  Each engine plays one
 * continuous event of infinite duration (GCHapticDurationInfinite) at full
 * intensity, and the level is its intensity control
 * (CHHapticDynamicParameterIDHapticIntensityControl), sent whenever it
 * changes.  Nothing plays for a controller without haptics: gamepad_rumble
 * then does nothing.
 *
 * The motors stop when the app is no longer in front, when the controller
 * goes away and when the app quits.  They are still when the levels stop
 * coming for 250 ms (a loading screen, a game that stopped polling the pad),
 * and after a second at zero the engines stop too (they cost the
 * controller's battery).  The pause
 * menu and photo mode are dinput_ff.c's (the world stands: levels of zero).
 *
 * Threading: gamepad_rumble (the guest thread) stores the levels and wakes
 * the motor queue; the engines are only touched on that queue.
 *   NFSU2_FF_STRENGTH=<percent>  scale both levels (1..100, default 100)
 *   NFSU2_FF_LOG=1 / NFSU2_PAD_LOG=1   log motors bound, started and stopped */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <CoreHaptics/CoreHaptics.h>
#include <os/lock.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "gamepad.h"
#include "rumble.h"

#define WATCHDOG_S 0.25          /* no level for this long: still */
#define IDLE_STOP_S 1.0          /* at zero for this long: engines off */
#define TICK_MS 50

/* ---- CoreHaptics motor ----------------------------------------------------------- */
API_AVAILABLE(macos(11.0))
@interface NFSHapticMotor : NSObject <NFSRumbleMotor>
- (instancetype)initWithHaptics:(GCDeviceHaptics *)h locality:(GCHapticsLocality)loc sharpness:(float)sharp;
@end

static dispatch_queue_t g_rq;     /* the motor queue */
static int rlog(void){
    static int v = -1;
    if (v < 0) v = gamepad_env_flag("NFSU2_FF_LOG", 0) || gamepad_env_flag("NFSU2_PAD_LOG", 0);
    return v;
}

@implementation NFSHapticMotor {
    CHHapticEngine *_engine;
    id<CHHapticAdvancedPatternPlayer> _player;
    BOOL _running;
    float _sharp;
    NSString *_loc;
}
- (instancetype)initWithHaptics:(GCDeviceHaptics *)h locality:(GCHapticsLocality)loc sharpness:(float)sharp {
    if (!(self = [super init])) return nil;
    _engine = [h createEngineWithLocality:loc];
    if (!_engine) return nil;
    _sharp = sharp; _loc = loc;
    _engine.playsHapticsOnly = YES;
    _engine.autoShutdownEnabled = NO;
    __weak NFSHapticMotor *w = self;
    /* the system stopped or reset the engine (another app, the controller
     * asleep): the next level starts it again */
    _engine.stoppedHandler = ^(CHHapticEngineStoppedReason r){
        dispatch_async(g_rq, ^{ NFSHapticMotor *m = w; if (m){ m->_player = nil; m->_running = NO; } });
        if (rlog()) fprintf(stderr, "[rumble] %s engine stopped by the system (reason %ld)\n", loc.UTF8String, (long)r);
    };
    _engine.resetHandler = ^{
        dispatch_async(g_rq, ^{ NFSHapticMotor *m = w; if (m){ m->_player = nil; m->_running = NO; } });
    };
    return self;
}
- (BOOL)rumbleStart {
    NSError *err = nil;
    if (!_running){
        if (![_engine startAndReturnError:&err]){
            if (rlog()) fprintf(stderr, "[rumble] %s engine does not start: %s\n", _loc.UTF8String, err.localizedDescription.UTF8String ?: "?");
            return NO;
        }
        _running = YES;
    }
    if (!_player){
        CHHapticEventParameter *in = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1.f];
        CHHapticEventParameter *sh = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:_sharp];
        CHHapticEvent *ev = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:@[in, sh]
                                                        relativeTime:0 duration:GCHapticDurationInfinite];
        CHHapticPattern *pat = [[CHHapticPattern alloc] initWithEvents:@[ev] parameters:@[] error:&err];
        id<CHHapticAdvancedPatternPlayer> p = pat ? [_engine createAdvancedPlayerWithPattern:pat error:&err] : nil;
        if (!p){
            if (rlog()) fprintf(stderr, "[rumble] %s: no player: %s\n", _loc.UTF8String, err.localizedDescription.UTF8String ?: "?");
            return NO;
        }
        [self sendIntensity:p value:0.f];
        if (![p startAtTime:CHHapticTimeImmediate error:&err]){
            if (rlog()) fprintf(stderr, "[rumble] %s: player does not start: %s\n", _loc.UTF8String, err.localizedDescription.UTF8String ?: "?");
            return NO;
        }
        _player = p;
    }
    return YES;
}
- (void)sendIntensity:(id<CHHapticAdvancedPatternPlayer>)p value:(float)v {
    CHHapticDynamicParameter *dp = [[CHHapticDynamicParameter alloc]
        initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:v relativeTime:0];
    [p sendParameters:@[dp] atTime:CHHapticTimeImmediate error:nil];
}
- (void)rumbleIntensity:(float)v { if (_player) [self sendIntensity:_player value:v]; }
- (void)rumbleStop {
    if (_player){ [_player stopAtTime:CHHapticTimeImmediate error:nil]; _player = nil; }
    if (_running){ [_engine stopWithCompletionHandler:nil]; _running = NO; }
}
@end

/* ---- the motors (motor queue) ------------------------------------------------------ */
enum { M_STRONG, M_WEAK };
static id<NFSRumbleMotor> g_m[2];       /* two motors, or one in g_m[0] that plays both levels */
static int      g_nm;                   /* 0 none, 1 combined, 2 strong + weak */
static int      g_on[2];                /* started */
static float    g_cur[2];               /* intensity last sent */
static double   g_zero_since;           /* every intensity at 0 since (0: not) */
static dispatch_source_t g_timer;
static char     g_name[64];
/* written by gamepad_rumble, read on the queue */
static os_unfair_lock g_lk = OS_UNFAIR_LOCK_INIT;
static float    g_want[2];
static double   g_want_t;               /* when the last level came */
static _Atomic int g_pending, g_bound, g_focused = 1, g_down;

static double mono_s(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec + (double)t.tv_nsec * 1e-9; }
static float strength(void){
    static float k = -1.f;
    if (k < 0.f){
        const char *e = getenv("NFSU2_FF_STRENGTH");
        int p = e && *e ? atoi(e) : 100;
        k = (p < 1 ? 1 : p > 100 ? 100 : p) / 100.f;
    }
    return k;
}
static void motor_off(int i){
    if (!g_m[i]) return;
    if (g_on[i]){ [g_m[i] rumbleStop]; g_on[i] = 0;
                  if (rlog()) fprintf(stderr, "[rumble] %s motor stopped\n", g_nm == 2 ? (i ? "weak" : "strong") : "the"); }
    g_cur[i] = 0.f;
}
static void motor_set(int i, float v){
    if (!g_m[i]) return;
    if (v > 0.f && !g_on[i]){
        if (![g_m[i] rumbleStart]) return;
        g_on[i] = 1; g_cur[i] = -1.f;
        if (rlog()) fprintf(stderr, "[rumble] %s motor started\n", g_nm == 2 ? (i ? "weak" : "strong") : "the");
    }
    if (!g_on[i]) return;
    if (fabsf(v - g_cur[i]) >= 0.01f || (v == 0.f) != (g_cur[i] == 0.f)){
        [g_m[i] rumbleIntensity:v];
        g_cur[i] = v;
    }
}
static void all_off(void){ for (int i = 0; i < 2; i++) motor_off(i); g_zero_since = 0; }
/* the levels as they should be now, onto the motors */
static void apply(void){
    atomic_store(&g_pending, 0);
    if (!g_nm || atomic_load(&g_down)) return;
    os_unfair_lock_lock(&g_lk);
    float s = g_want[0], w = g_want[1]; double t = g_want_t;
    os_unfair_lock_unlock(&g_lk);
    double now = mono_s();
    if (!atomic_load(&g_focused)){ if (g_on[0] || g_on[1]) all_off(); return; }
    if (now - t > WATCHDOG_S) s = w = 0.f;
    s *= strength(); w *= strength();
    if (g_nm == 2){ motor_set(M_STRONG, s); motor_set(M_WEAK, w); }
    else { float c = s + w * 0.5f; motor_set(0, c > 1.f ? 1.f : c); }
    int zero = (!g_on[0] || g_cur[0] == 0.f) && (!g_on[1] || g_cur[1] == 0.f);
    if (!zero) g_zero_since = 0;
    else if (g_on[0] || g_on[1]){
        if (!g_zero_since) g_zero_since = now;
        else if (now - g_zero_since >= IDLE_STOP_S) all_off();
    }
}
static void queue_init(void){
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_rq = dispatch_queue_create("nfsu2.rumble", DISPATCH_QUEUE_SERIAL);
        /* the watchdog and the idle stop */
        g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, g_rq);
        dispatch_source_set_timer(g_timer, dispatch_time(DISPATCH_TIME_NOW, TICK_MS * NSEC_PER_MSEC),
                                  TICK_MS * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(g_timer, ^{ if (g_on[0] || g_on[1]) apply(); });
        dispatch_resume(g_timer);
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:nil
            usingBlock:^(NSNotification *n){ (void)n; atomic_store(&g_focused, 0);
                dispatch_async(g_rq, ^{ apply(); });
                if (rlog() && g_nm) fprintf(stderr, "[rumble] app inactive: motors still\n"); }];
        [nc addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil
            usingBlock:^(NSNotification *n){ (void)n; atomic_store(&g_focused, 1); }];
        [nc addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil
            usingBlock:^(NSNotification *n){ (void)n; rumble_shutdown(); }];
        atexit(rumble_shutdown);
    });
}

/* ---- the controller (main thread) ---------------------------------------------------- */
void rumble_bind(NSSet<NSString *> *loc, const char *name, NFSRumbleFactory factory){
    queue_init();
    NSString *nm = name ? @(name) : nil;
    dispatch_async(g_rq, ^{
        if (g_nm && !nm && rlog()) fprintf(stderr, "[rumble] %s gone: motors off\n", g_name);
        all_off();
        g_m[0] = g_m[1] = nil; g_nm = 0;
        os_unfair_lock_lock(&g_lk); g_want[0] = g_want[1] = 0.f; os_unfair_lock_unlock(&g_lk);   /* the next poll's levels */
        if (nm) snprintf(g_name, sizeof g_name, "%s", nm.UTF8String);
        const char *how = "no haptics: no rumble";
        if (factory && loc.count && !atomic_load(&g_down)){
            if ([loc containsObject:GCHapticsLocalityLeftHandle] && [loc containsObject:GCHapticsLocalityRightHandle]){
                g_m[M_STRONG] = factory(GCHapticsLocalityLeftHandle, 0.2f);
                g_m[M_WEAK]   = factory(GCHapticsLocalityRightHandle, 0.8f);
                if (g_m[0] && g_m[1]){ g_nm = 2; how = "two motors (left handle strong, right handle weak)"; }
                else { g_m[0] = g_m[1] = nil; }
            }
            if (!g_nm){
                NSString *l = [loc containsObject:GCHapticsLocalityHandles] ? GCHapticsLocalityHandles : GCHapticsLocalityDefault;
                g_m[0] = factory(l, 0.5f);
                if (g_m[0]){ g_nm = 1; how = "one motor (both levels)"; }
                else how = "no haptic engine: no rumble";
            }
        }
        atomic_store(&g_bound, g_nm);
        if (nm && (rlog() || g_nm)) fprintf(stderr, "[rumble] %s: %s\n", g_name, how);
        apply();
    });
}
void rumble_controller(GCController *k){
    if (!k){ rumble_bind(nil, 0, nil); return; }
    const char *nm = k.vendorName.length ? k.vendorName.UTF8String : "Game Controller";
    if (@available(macOS 11.0, *)){
        GCDeviceHaptics *h = k.haptics;
        if (!h){ rumble_bind(nil, nm, nil); return; }
        rumble_bind(h.supportedLocalities, nm, ^id<NFSRumbleMotor>(NSString *l, float sharp){
            return [[NFSHapticMotor alloc] initWithHaptics:h locality:l sharpness:sharp];
        });
    } else rumble_bind(nil, nm, nil);
}

/* ---- the levels (any thread) ------------------------------------------------------- */
void gamepad_rumble(float strong, float weak){
    if (!atomic_load(&g_bound)) return;
    if (!(strong >= 0.f)) strong = 0.f; if (strong > 1.f) strong = 1.f;   /* NaN too */
    if (!(weak >= 0.f)) weak = 0.f;     if (weak > 1.f) weak = 1.f;
    os_unfair_lock_lock(&g_lk);
    g_want[0] = strong; g_want[1] = weak; g_want_t = mono_s();
    os_unfair_lock_unlock(&g_lk);
    if (!atomic_exchange(&g_pending, 1)) dispatch_async(g_rq, ^{ apply(); });
}
int gamepad_rumble_ok(void){ return atomic_load(&g_bound) != 0; }

void rumble_shutdown(void){
    if (!g_rq || atomic_exchange(&g_down, 1)) return;
    atomic_store(&g_bound, 0);
    dispatch_sync(g_rq, ^{
        all_off(); g_m[0] = g_m[1] = nil; g_nm = 0;
        if (rlog()) fprintf(stderr, "[rumble] shut down: motors off\n");
    });
}
void rumble_sync(void){ if (g_rq) dispatch_sync(g_rq, ^{}); }
void rumble_tick_now(void){ if (g_rq) dispatch_sync(g_rq, ^{ apply(); }); }
