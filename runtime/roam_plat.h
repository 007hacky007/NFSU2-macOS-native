/* roam_plat.h -- free-roam multiplayer: the platform layer under the core
 * (roam_core.h).  macOS: roam_bsd.c (BSD sockets or the server's switch,
 * pthreads).
 *
 * One UDP socket (or switch port) per instance.  A network thread receives, feeds the session
 * and runs its timers; the game thread pushes the local state and reads the
 * remote poses.  Both hold roam_plat_lock() around every session call.
 *
 * Test-harness guard (fail closed): in test mode the socket is bound to
 * 127.0.0.1, every destination outside 127/8 and every broadcast is refused
 * before it reaches the kernel and logged as "[roam] BLOCKED ...", and peers
 * outside 127/8 are rejected when the list is parsed.  Test mode is on in
 * any automated run (roam_plat_test_mode()).
 *
 * Ported from th0mk's nfsu2-web runtime/roam_plat.h (MIT).
 */
#ifndef ROAM_PLAT_H
#define ROAM_PLAT_H
#include "roam_core.h"

typedef struct {
    uint16_t    port;
    int         test_mode;
    int         discovery;          /* LAN beacon (production only) */
    const char *impair;             /* test aid: "loss=5,delay=100,jitter=10,dup=1,seed=1" (jitter wider than 50 ms reorders) */
} roam_plat_cfg;

/* 1 when this run is automated: NFSU2_ROAM_HARNESS / NFSU2_NET_HARNESS = 1,
 * NFSU2_INPUT_SCRIPT, NFSU2_QUIT_FRAMES, NFSU2_TIMEOUT, ALARM other than 0, or
 * NOFOCUS other than 0 */
int      roam_plat_test_mode(void);
/* opens and binds the socket, installs io.send / io.broadcast into the
 * session and starts the network thread; 0 on success */
int      roam_plat_start(const roam_plat_cfg *cfg, rc_session *s);
void     roam_plat_stop(uint8_t bye_reason);       /* BYE, close, join */
void     roam_plat_lock(void);
void     roam_plat_unlock(void);
int64_t  roam_plat_now_us(void);                   /* host monotonic clock */
uint32_t roam_plat_random(void);                   /* nonzero */
/* "a.b.c.d[:port], ..." -> up to max entries; IPv4 literals only (no DNS);
 * in test mode only 127/8.  Returns the count; bad entries are logged. */
int      roam_plat_parse_peers(const char *list, int test_mode, uint16_t defport,
                               uint32_t *ip, uint16_t *port, int max);

/* --- pieces exposed for the unit tests (no socket needed) --- */
typedef struct { char name[16]; uint32_t addr, mask; int up, loopback, can_broadcast; } roam_if;
/* where a discovery beacon goes: 255.255.255.255 plus every usable
 * interface's directed broadcast (no loopback, utun, awdl, llw, ipsec) */
int      roam_bcast_targets(const roam_if *ifs, int n, uint32_t *out, int max);
/* the guard on its own: 1 = may be sent, 0 = refused (and logged) */
int      roam_plat_guard(int test_mode, uint32_t ip, int is_broadcast);
typedef struct { uint64_t sent, sent_bytes, recv, recv_bytes, blocked, send_err, impair_drop, impair_dup; } roam_plat_stats;
void     roam_plat_get_stats(roam_plat_stats *out);
/* a message over the game ("<name><what>", as the joins and leaves; name 0:
 * what alone, as the room's "Nobody else"): a log line here.  With the
 * session lock held */
void     roam_plat_notice(const char *name, const char *what);
const char *roam_ip_str(uint32_t ip, char *buf);   /* buf >= 16 */

/* --- Game Tools and quick chat (native_controls.m) --- */
/* the race lobby for the panel (roam_game.c mp_panel): its state as a JSON
 * object, "{}" for none, sent when it changes.  1: taken; 0: no panel (none
 * sent after that); -1: not taken, again next frame.  With the session lock
 * held */
int      roam_plat_lobby(const char *json);
/* solid cars as the player switched them in the panel while the game runs: 1
 * on, 0 off, 2 off and the game's traffic and tuners pass through too (Ghost
 * mode: Everything), -1 not switched (NFSU2_ROAM_COLLIDE holds) */
int      roam_plat_solid(void);
/* the crews as the player changed them in the panel: their rc_room_hash
 * values in the player's order (0: none) into crews, their colours into rgb
 * (0x00RRGGBB, 0: the place's default), and a number that changes with each
 * change (0: not changed, NFSU2_ROAM_CREW and NFSU2_ROAM_CREW_RGB hold) */
uint32_t roam_plat_crews(uint32_t crews[RC_CREW_MAX], uint32_t rgb[RC_CREW_MAX]);
/* the room as the player changed it in the panel while the game runs (its
 * Room box, or a friend's Join): its name into name (UTF-8 ending in a 0
 * byte; "" for no room), and a number that changes with each change (0: not
 * changed, NFSU2_ROAM_ROOM holds) */
uint32_t roam_plat_room(char name[64]);
/* quick chat (roam_game.c say_*): whether this platform has it (a picker and
 * the lines over the cars), the phrase the player picked since the last call
 * (-1: none), and a phrase said (by a friend, or by the player) as a JSON
 * object (1 shown, -1 not).  With the session lock held */
int      roam_plat_quickchat(void);
int      roam_plat_say_pick(void);
int      roam_plat_said(const char *json);
/* front bumpers (roam_game.c bump_*): the player's car and a friend's touched
 * nose to nose for 3 s, or parted after that, as a JSON object
 * {"id","name","on"}: Game Tools offers to add that player as a friend (1
 * taken, -1 not).  With the session lock held */
int      roam_plat_friend(const char *json);
/* the player's car flew in free roam for minutes (roam_game.c fly_frame), as
 * a JSON object {"s": seconds}: the game leaves the server for the rest of
 * the session, as an operator's kick takes a player, and tells it (1 done, 0
 * not on the server now, -1 try again).  With the session lock held */
int      roam_plat_flying(const char *json);
/* where the names of the players who said something lately are this frame:
 * ids[i] at xys[3i], xys[3i + 1] (parts of the picture from its top left
 * corner) with the name's scale xys[3i + 2]; n = 0: none.  On the game
 * thread, without the lock */
void     roam_plat_say_marks(const uint32_t *ids, const float *xys, int n);
/* the player drives in free roam this frame (quick chat may take the keys
 * and the stick), and the panel's button pressed since the last call */
void     roam_plat_driving(int driving);
enum { ROAM_ACTION_NONE = 0, ROAM_ACTION_ENGAGE = 1, ROAM_ACTION_LEAVE = 2 };   /* Open / Join / Start; Leave lobby */
int      roam_plat_action(void);

#endif
