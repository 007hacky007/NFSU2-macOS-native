/* Native access to the browser-compatible switch protocol. No connection
 * exists unless NFSU2_NET=online and an explicit player name is supplied.
 *
 * The client side of th0mk's nfsu2-web server's switch (its wire format:
 * net_proto.h, MIT). */
#ifndef NFSU2_NET_NATIVE_H
#define NFSU2_NET_NATIVE_H
#include "net_proto.h"
#include <stdint.h>
int native_net_enabled(void);
int native_net_url_valid(const char *url);
net_mailbox *native_net_mailbox(uint32_t mode);
void native_net_shutdown(void);
/* 1: the launcher handed the engine a claimed name's token (NFSU2_CLAIM_FD) */
int native_net_has_claim(void);
/* a control message of free roam's friends to the switch (JSON, at most 4096 bytes): 1 sent, 0 no link now
 * (native_controls.m) */
int native_net_text(const char *json);
void native_net_wait(int *word, int expected, int64_t ns);
/* the player's car flew in free roam for secs (roam_game.c fly_frame): the server hears it ({"t":"flying"}: its
 * log), and the game goes off the switch for the rest of the session, as after a kick, with a line saying why.
 * 1 when that happens, 0 with no link now (any thread) */
int native_net_flying(int secs);
#define NATIVE_NET_FLYING_MSG "You're not an airplane, get down to the ground like the rest of us"
/* the Online statistics panel (netstats.m): the link to the server
 * (NETSTATS_* of netstats.h), its place in the server's queue (pos of of, 0:
 * not known) and the round trip of the last ping (ms, -1: none yet).  Any
 * thread; NETSTATS_OFFLINE until free roam or LAN play first wants the server */
typedef struct { int state, queue_pos, queue_of, rtt_ms; } native_net_status;
void native_net_get_status(native_net_status *out);
#define __builtin_wasm_memory_atomic_wait32(p, v, ns) native_net_wait((p), (v), (ns))
#define __builtin_wasm_memory_atomic_notify(p, n) ((void)(p), (void)(n))
#endif
