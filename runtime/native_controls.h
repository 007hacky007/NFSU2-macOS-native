/* Native multiplayer tools. Callbacks never dispatch or enter guest code. */
#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __OBJC__
@class NSWindow, NSMenu, NSEvent;
int native_controls_handle_event(NSEvent *event);
void native_controls_attach(NSWindow *window);
void native_controls_add_menu(NSMenu *menu);
#endif
void native_controls_pump(void);                 /* main thread */
void native_controls_guest_frame(void);          /* guest thread */
int native_controls_lobby(const char *json);
void native_controls_notice(const char *name, const char *what);
int native_controls_said(const char *json);
int native_controls_pick(int phrase);
int native_controls_say_pick(void);
int native_controls_solid(void);
void native_controls_set_solid(int solid);
uint32_t native_controls_crews(uint32_t crews[4], uint32_t rgb[4]);
/* Validates the whole update before changing any state. error may be NULL. */
int native_controls_set_crews(const char *names, const char *colours, char *error, size_t capacity);
enum { NATIVE_CONTROL_ENGAGE = 1, NATIVE_CONTROL_LEAVE = 2 };
void native_controls_action(int action);

#include "gamepad.h"
/* Game-facing pad only. The scene adapter reads the unfiltered pad. */
void native_controls_filter_pad(PadState *state);
/* Four rows of four donor phrase IDs. Rejects the whole invalid update. */
int native_controls_set_chat_layout(const int layout[16]);
void native_controls_say_marks(const uint32_t *ids, const float *xys, int count);
/* id 0 clears every transient line, including after transport shutdown. */
void native_controls_forget(uint32_t id);
/* Successful free-roam transport and its negotiated quick-chat capability. */
void native_controls_set_network(int enabled);
