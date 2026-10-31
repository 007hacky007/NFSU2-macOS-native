/* native_scene.h -- the Mac side of photo mode (photo.c) and drift mode (drift.c):
 * keys, mouse and controller for the photo camera, the app menu's Photo Mode,
 * the photo help panel and the drift panel over the game window, and screenshots
 * read back from the GPU and saved as PNGs without holding the game up
 * (runtime/native_scene.m). */
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
    int photo, opens, drift, multiplier, state, feedback;
    double fov, roll, pending, gain, total, best, banked, feedback_until;
} NativeSceneSnapshot;

/* the controller as the game's DirectInput reads it (gamepad.m, DIJOYSTATE2), the way the camera wants it */
enum { NPAD_A, NPAD_B, NPAD_X, NPAD_Y, NPAD_LB, NPAD_RB, NPAD_BACK, NPAD_START, NPAD_LS, NPAD_RS,
       NPAD_DUP, NPAD_DDOWN, NPAD_DLEFT, NPAD_DRIGHT };
typedef struct {
    uint32_t buttons;                    /* 1u << NPAD_x */
    float lx, ly, rx, ry, lt, rt;        /* sticks -1..1 (+x right, +y down), triggers 0..1 */
} NativePad;
void native_scene_pad_parse(const unsigned char *dijoystate2, NativePad *out);

/* the status photo.c and drift.c publish: named numbers, set in one consistent section */
int  host_status_slot(const char *name);
void host_status_set_n(const int *slots, const double *values, int count);
void native_scene_snapshot(NativeSceneSnapshot *out);

int  photo_enabled(void);                          /* photo.c: NFSU2_PHOTO=1 */
int  drift_enabled(void);                          /* drift.c: NFSU2_DRIFT=1 */
void native_scene_pump(void);                      /* main thread, every loop */
void native_scene_guest_frame(void);               /* guest thread, every frame (photo.c) */
int  native_scene_active(void);                    /* photo mode is on (any thread) */
void native_scene_focus(int focused);              /* main thread */
void native_scene_filter_raw(unsigned char *dijoystate2);   /* the same filter on a DIJOYSTATE2 (tests) */
void native_scene_f12(void);                       /* F12: open photo mode where it can, else a screenshot */
void native_scene_request_capture(void);           /* a screenshot of the next frame */
int  native_scene_take_capture(void);              /* the presenter: 1 if this frame is to be saved */
int  native_scene_capture_busy(void);
int  native_scene_save_bgra(const void *pixels, size_t width, size_t height, size_t stride, char *path, size_t capacity);
#ifdef __OBJC__
#import <Metal/Metal.h>
@class NSWindow, NSMenu, NSEvent;
void native_scene_attach(NSWindow *window);        /* the panels, once the game window is up */
void native_scene_add_menu(NSMenu *appMenu);       /* Photo Mode in the app menu */
int  native_scene_handle_event(NSEvent *event);    /* 1: photo mode took it */
int  native_scene_encode_capture(id<MTLCommandBuffer> command, id<MTLTexture> source);
#endif
