/* rumble.h -- runtime/rumble.m, the controller's motors (CoreHaptics through
 * GameController), between gamepad.m (which controller) and dinput_ff.c
 * (which levels, through gamepad_rumble in gamepad.h). */
#ifndef RUMBLE_H
#define RUMBLE_H
#ifdef __OBJC__
#import <Foundation/Foundation.h>
@class GCController;

/* One motor: a haptic engine of one locality playing one continuous event
 * whose intensity follows the level.  rumble.m's own drives CoreHaptics;
 * tests/rumble_unit.m passes fakes. */
@protocol NFSRumbleMotor <NSObject>
- (BOOL)rumbleStart;                  /* engine and player running; NO: it cannot */
- (void)rumbleIntensity:(float)v;     /* 0..1, while started */
- (void)rumbleStop;
@end
/* a motor for a locality (GCHapticsLocality*), or nil */
typedef id<NFSRumbleMotor> (^NFSRumbleFactory)(NSString *locality, float sharpness);

/* gamepad.m (main thread): the controller now driving the pad (nil: none) */
void rumble_controller(GCController *k);
/* the same with the controller's haptic localities spelled out (tests) */
void rumble_bind(NSSet<NSString *> *localities, const char *name, NFSRumbleFactory factory);
#endif
/* every motor off and let go (the app quits; also atexit) */
void rumble_shutdown(void);
/* tests: wait until the motor queue has done what was asked of it so far */
void rumble_sync(void);
/* tests: run the motor queue's periodic check now (the watchdog and idle stop) */
void rumble_tick_now(void);
#endif
