/* native_controls.h -- Game Tools (Cmd+Shift+M) and quick chat
 * (native_controls.m).  The game side of the free-roam parts is roam_game.c
 * (the roam_plat.h calls this file answers); the music part drives
 * radio_native.h.  Nothing here calls into the guest. */
#ifndef NATIVE_CONTROLS_H
#define NATIVE_CONTROLS_H
#include <stdint.h>
#include <stddef.h>
#ifdef __OBJC__
@class NSWindow, NSEvent, NSString, NSArray<ObjectType>;
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
/* ---- what racehorn.c tells it, through net_relay.c (the game thread) ---- */
void native_controls_set_race(int state);    /* every frame: 1 driving in a race between players, 2 on its results, 0 not */
int  native_controls_race_pick(void);        /* a phrase picked in such a race, once (-1 none) */

/* ---- the panel's state, for tests and the panel itself ---- */
#define NATIVE_PHRASES 152                   /* nfsu2-web's phrases.ts (append only) */
const char *native_controls_phrase(int phrase);   /* NULL past the list */
int  native_controls_pick(int phrase);       /* the Say button: queue a phrase (0: full, or not one of ours) */
void native_controls_set_solid(int solid);   /* the panel's Cars menu: 1 solid, 0 ghosts, 2 everything (traffic and tuners too) */
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

/* ---- friends (NFSU2_ROAM_FRIENDS; free roam with a claimed name) ----
 * net_native.m's link: each welcome (claimed: the hello named the keyphrase's
 * token) and the server's {"t":"friend",...} messages (its queue); what goes
 * out is sent from native_controls_friends_tick (the main thread, ~30 a
 * second) through native_net_text */
void native_controls_net_welcome(int claimed);
void native_controls_net_friend(const char *json);
void native_controls_friends_tick(double now);
/* the line under the picture (front bumpers): 1 with one, its text into buf,
 * *actionable 1 when F or the panel's button does something; F or the button */
int  native_controls_friend_line(char *buf, size_t cap, int *actionable);
int  native_controls_friend_act(void);
/* the toast at the top of the picture now (a friend in free roam, a request): 1 with one */
int  native_controls_friend_toast(char *buf, size_t cap);
#ifdef __OBJC__
/* the friends in free roam in another room: [name, room ("" everyone's)] each */
NSArray<NSArray<NSString *> *> *native_controls_friends_to_join(void);
#endif
void native_controls_action(int action);     /* Open / Join / Start, Leave lobby */
#endif
