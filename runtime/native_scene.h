/* Native photo camera, drift HUD and asynchronous Metal screenshots. */
#pragma once
#include <stddef.h>
#include "gamepad.h"
typedef struct {
    int photo, opens, drift, multiplier, state, feedback;
    double fov, roll, pending, gain, total, best, banked, feedback_until;
} NativeSceneSnapshot;
int host_status_slot(const char *name);
void host_status_set_n(const int *slots,const double *values,int count);
void native_scene_snapshot(NativeSceneSnapshot *out);
void native_scene_pump(void);                     /* main thread */
void native_scene_guest_frame(void);              /* guest thread */
int native_scene_active(void);                   /* any thread */
void native_scene_focus(int focused);             /* main thread */
void native_scene_filter_pad(PadState *state);     /* game-facing guest snapshot */
int native_scene_take_capture(void);              /* main presenter */
int native_scene_capture_busy(void);
int native_scene_save_bgra(const void *pixels,size_t width,size_t height,size_t stride,char *path,size_t capacity);
#ifdef __OBJC__
#import <Metal/Metal.h>
@class NSWindow, NSMenu, NSEvent;
void native_scene_attach(NSWindow *window,NSMenu *menu);
int native_scene_handle_event(NSEvent *event);
int native_scene_encode_capture(id<MTLCommandBuffer> command,id<MTLTexture> source);
#endif
