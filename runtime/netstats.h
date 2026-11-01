/* netstats.h -- the Online statistics panel, see netstats.m.
 *
 * The pure parts (netstats_core.c, tests/netstats_unit.c): the server's /players
 * address for its WebSocket address, the /players answer, the panel's text. */
#ifndef NETSTATS_H
#define NETSTATS_H
#include <stddef.h>
#include <stdint.h>

#define NETSTATS_CREWS      4           /* roam_core.h RC_CREW_MAX */
#define NETSTATS_ANSWER_MAX 64000       /* bytes of a /players answer at most (the launcher's PlayerCounts.swift) */

/* the link to the server (net_native.m native_net_get_status) */
enum { NETSTATS_OFFLINE, NETSTATS_CONNECTING, NETSTATS_QUEUED, NETSTATS_RECONNECTING, NETSTATS_CONNECTED };

/* a /players answer; -1: not in it (an older server) or null */
typedef struct {
    int players, online, roam, queue, room;
    int full, roam_busy;                /* 0 / 1 */
    int ncrews, crews[NETSTATS_CREWS];  /* the crews asked about, in their order */
} netstats_counts;

/* free roam with other players (roam_game.c roam_game_netstats) */
typedef struct {
    int      shown;                     /* friends' cars shown near the player (active slots) */
    int      linked;                    /* players the hub's last list links us with; -1: no hub answers */
    uint32_t room;                      /* rc_room_hash of the room (0: none) */
    int      ncrews; uint32_t crews[NETSTATS_CREWS];
    char     room_name[64];
    char     crew_name[NETSTATS_CREWS][100];   /* "": not known (changed in Game Tools) */
} netstats_roam;

/* what the panel shows */
typedef struct {
    int    conn, queue_pos, queue_of;   /* NETSTATS_*; the place in the queue (0: not known) */
    int    rtt_ms;                      /* -1: not known */
    int    counts;                      /* 1: c holds the last answer, 0: none yet, -1: none, the last ask failed */
    netstats_counts c;
    int    asked_room;                  /* the answer is for a room (room_name) */
    int    asked_crews;                 /* ...and for that many crews (crew_name) */
    int    free_roam;                   /* free roam with other players runs: r holds it */
    netstats_roam r;
} netstats_view;

/* https://host[:port]/players (http:// for a ws:// server on this Mac) for a
 * wss:// or ws:// server address, with ?room=<hash> and &crews=<h1,h2> (none
 * 0, at most NETSTATS_CREWS) as launcher/PlayerCounts.swift asks; 0: no valid
 * address or out too small */
int    netstats_players_url(const char *server, uint32_t room, const uint32_t *crews, int ncrews, char *out, size_t cap);
/* a /players answer; 0: not one (players missing, a count below 0, not JSON) */
int    netstats_parse_players(const char *json, size_t len, netstats_counts *out);
/* the panel's lines, ended by '\n' between them; returns the length */
size_t netstats_text(const netstats_view *v, char *out, size_t cap);

/* netstats.m */
int  netstats_on(void);                 /* NFSU2_NET_STATS=1 and Play online (NFSU2_NET=online) */
void netstats_start(void);              /* the numbers four times a second and /players (netstats_init does it) */
size_t netstats_snapshot(char *out, size_t cap);   /* the panel's text now (tests) */
/* roam_game.c: 0 while free-roam multiplayer is off.  Any thread */
int  roam_game_netstats(netstats_roam *out);
#ifdef __OBJC__
#import <Metal/Metal.h>
void netstats_init(id<MTLDevice> dev);
/* after the game's frame, on the presenter's thread: dst = the frame's
 * texture, px_per_pt = its pixels per window point, top = the pixels from the
 * top already taken in the corner (the frame-rate counter) */
void netstats_draw(id<MTLCommandBuffer> cb, id<MTLTexture> dst, double px_per_pt, double top);
#endif
#endif
