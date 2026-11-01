/* native_controls.h -- Game Tools (Cmd+Shift+M) and quick chat
 * (native_controls.m).  The game side of the free-roam parts is roam_game.c
 * (the roam_plat.h calls this file answers); the music part drives
 * radio_native.h.  Nothing here calls into the guest. */
#ifndef NATIVE_CONTROLS_H
#define NATIVE_CONTROLS_H
#include <stdint.h>
#include <stddef.h>
#ifdef __OBJC__
@class NSWindow, NSEvent, NSString;
/* main thread, once the game window exists: the panel, its item in the app
 * menu (above Quit), the overlay over the game for quick chat */
void native_controls_install(NSWindow *game);
/* a room or crew name as it is kept: NFC, blanks one space, invisible ones out, trimmed */
NSString *native_controls_tidy_name(NSString *s);
/* main thread, every key event before the game sees it: 1 when it is ours
 * (a quick chat pick, or typing in one of our panels, handed to AppKit) */
int  native_controls_handle_event(NSEvent *ev);
#endif

/* ---- the controller (guest thread): quick chat's right stick ----
 * The core: the stick (-1..1, +y down), the B button and the right stick's
 * click; what the picker takes is taken out (the stick to 0, the buttons
 * cleared until let go).  connected 0: the pad went away (the picker closes). */
void native_controls_pad(int connected, float *rx, float *ry, int *b, int *rs);
/* dinput_pad.c's hook, right before the game reads the pad: through native_controls_pad */
#include "gamepad.h"
void native_controls_filter_pad(PadState *s);

/* ---- what roam_bsd.c tells it (any thread) ---- */
void native_controls_notice(const char *name, const char *what);   /* a line in the panel's log */
void native_controls_set_network(int say);   /* the session is up and takes quick chat (say), or down (0) */
void native_controls_forget(uint32_t id);    /* a player left: their line over the car goes (0: every line) */

/* ---- the panel's state, for tests and the panel itself ---- */
#define NATIVE_PHRASES 152                   /* nfsu2-web's phrases.ts (append only) */
const char *native_controls_phrase(int phrase);   /* NULL past the list */
int  native_controls_pick(int phrase);       /* the Say button: queue a phrase (0: full, or not one of ours) */
void native_controls_set_solid(int solid);   /* the panel's Solid cars box */
/* the panel's Room (and a friend's Join): the name as the launcher's Room box
 * takes it (UTF-8 up to 63 bytes after tidying, no control character, no # or
 * ; after a space, none names.h blocks; "" or blanks: no room); roam_game.c
 * takes it at its next frame where it can.  error (may be NULL) says why not */
int  native_controls_set_room(const char *name, char *error, size_t capacity);
/* the crews as typed: names by commas (up to four, each 1-24 characters, no
 * #, ; or control character, none twice, none that names.h blocks), their
 * colours rrggbb by commas (empty: the place's default).  The whole list or
 * nothing; error (may be NULL) says why */
int  native_controls_set_crews(const char *names, const char *colours, char *error, size_t capacity);
/* four groups of four phrase numbers; rejects the whole update when one is not a phrase */
int  native_controls_set_chat_layout(const int layout[16]);
enum { NATIVE_CONTROL_ENGAGE = 1, NATIVE_CONTROL_LEAVE = 2 };   /* roam_plat.h ROAM_ACTION_* */
void native_controls_action(int action);     /* Open / Join / Start, Leave lobby */
#endif
