/* racehorn.c -- horns in races between players (the game's Online races
 * through the server).  Free roam has its own (roam_game.c); the sound is
 * horn.c's.
 *
 * In a network race the other players' cars are the game's own: its race
 * link moves them with datagrams on UDP 3658 between the players' games, a
 * star around the game's creator.  The horn goes beside that link, between
 * the same games, on a UDP port of the runtime's own on the server's virtual
 * LAN (HORN_PORT, net_relay.c's vlan_rt_*), so the game never sees it:
 *   - to whom: the games the race link exchanged datagrams with in the last
 *     PEER_MS (vlan_race_peers): every joiner for the creator, the creator
 *     for a joiner.  The creator passes each joiner's horn on to the other
 *     joiners, marked relayed (never passed on again).
 *   - what: "N2HN", version 1, flags (1 the horn sounds, 2 relayed, bits
 *     2-5 which horn: horn.h's kinds, which a build before them leaves at 0,
 *     the dual one, and ignores), a sequence number, and the name the
 *     player races under, as the game shows it over their car on every
 *     screen: the network race's player table (G_NETPLAYERS: player i's
 *     name at +0x12, which its own lookup by name 0x5F0240 compares; the
 *     HUD's names over the cars, 0x4EC0D0, pair player i with the world's
 *     car whose +0xA is i, World 0x5F0E40).  While the horn sounds, every
 *     SEND_MS; when it stops, twice.  A horn not heard of for STALE_MS stops.
 *   - where it sounds: from the car of the player with that name.  (A car's
 *     racer record names the profile, not the player: "No Profile" for a
 *     player without one, nothing for the others' cars.)
 * What comes in is taken only from the race's own peers, only HEAR_MAX
 * datagrams a frame, a relayed one never by the creator, and the creator
 * passes on at most RELAY_PER_S a second of each joiner's.  The port also
 * carries the players' frame rates ("N2FS"), which go to racenet.c.
 * Only Online, where the server's virtual LAN is; the Mac's own LAN has no
 * such port (vlan_rt_* send and receive nothing), and only while horns are
 * on (horn.h horn_on): off, this port is not read, nothing is sent or
 * passed on.
 *
 * Ported from th0mk's nfsu2-web runtime/racehorn.c (MIT). */
#include "cpu.h"
#include "horn.h"
#include <stdio.h>
#include <string.h>
#include <time.h>

#define G_FLOW       GA(0x008654a4u)   /* 6: in the world */
#define G_NETMODE    GA(0x00850078u)   /* 8 Online, 0x200 LAN (1 career) */
#define G_NET_HOST   GA(0x00866a14u)   /* host race state, > 0: this game created the race */
#define G_WORLD      GA(0x00890080u)   /* World*: +0 the cars' list (a car's first two dwords are its node) */
#define G_PLAYER1    GA(0x008900acu)   /* Player*: +4 car */
#define G_WORLDDT    GA(0x00865150u)   /* float: this frame's world dt (s) */
#define G_VIEW1      GA(0x00832e50u)   /* eView 1: +0x40 camera (+0x40 position, +0x50 forward) */
#define G_NETPLAYERS GA(0x0089cf50u)   /* the network race's players: 6 pointers (0x89CF48 + 8), name at +0x12 */
#define NP_NAME      0x12u
#define HORN_PORT    3659u         /* next to the race link's 3658; the game binds neither else */
#define PEER_MS      5000u
#define SEND_MS      100u
#define STALE_MS     300u
#define NAME_N       16
#define MSG_N        (8 + NAME_N)
#define NHORNS       8
#define HEAR_MAX     64            /* datagrams taken a frame; the rest wait in the port's queue */
#define RELAY_PER_S  15u           /* a joiner's horns the creator passes on, a second (it sends 10) */

/* net_relay.c: the server's virtual LAN (nothing without Online) */
int vlan_rt_send(uint16_t port, uint32_t ip_h, const void *p, int n);
int vlan_rt_recv(uint16_t port, uint32_t *ip_h, void *p, int cap);
int vlan_race_peers(uint32_t *ip_h, int max, uint32_t within_ms);

static int ok(uint32_t a, uint32_t n){ return a && mem_is_committed(a) && mem_is_committed(a + n); }
static uint32_t rd32(uint32_t a){ return ok(a, 3) ? MR32(a) : 0u; }
static void rd3(uint32_t a, float *o){ o[0] = MRF32(a); o[1] = MRF32(a + 4u); o[2] = MRF32(a + 8u); }
static uint32_t now_ms(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)((uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u);
}
static uint32_t fnv1a(const char *s){
    uint32_t h = 2166136261u;
    for (; *s; s++){ h ^= (uint8_t)*s; h *= 16777619u; }
    return h;
}
/* the name of the player whose car this is (printable, at most 15
 * characters), "" for none */
static void car_name(uint32_t car, char *o){
    int i = ok(car, 0x9e0) ? (int16_t)MR16(car + 0xau) : -1;
    uint32_t pl = i >= 0 && i < 6 ? rd32(G_NETPLAYERS + 4u * (uint32_t)i) : 0;
    int n = 0;
    if (ok(pl, NP_NAME + NAME_N))
        for (; n < NAME_N - 1; n++){ uint8_t ch = MR8(pl + NP_NAME + (uint32_t)n); if (ch < 0x20 || ch > 0x7e) break; o[n] = (char)ch; }
    o[n] = 0;
}

static struct { char name[NAME_N]; uint32_t at; int on, kind; } g_h[NHORNS];   /* others' horns as last heard */
static uint16_t g_seq;
static int g_mine, g_offs, g_active;                 /* our horn; "stopped" messages still to send; voices driven */
static uint32_t g_sent_at;

static uint32_t g_peers[16]; static int g_npeers;   /* the race's peers, this frame */
static struct { uint32_t ip, win, n; } g_rl[16];       /* passed on per joiner, in the second from win */
static uint32_t g_dropped;
static void send_all(const uint8_t *m, uint32_t except){
    for (int i = 0; i < g_npeers; i++) if (g_peers[i] != except) vlan_rt_send(HORN_PORT, g_peers[i], m, MSG_N);
}
/* the creator may pass on another of this joiner's horns now */
static int relay_ok(uint32_t from, uint32_t now){
    int j = 0, old = 0;
    for (; j < 16 && g_rl[j].ip != from; j++) if (now - g_rl[j].win > now - g_rl[old].win) old = j;
    if (j == 16){ j = old; g_rl[j].ip = from; g_rl[j].win = now; g_rl[j].n = 0; }
    if (now - g_rl[j].win >= 1000u){ g_rl[j].win = now; g_rl[j].n = 0; }
    return ++g_rl[j].n <= RELAY_PER_S;
}
void racenet_heard(uint8_t *m, int n, uint32_t from);   /* racenet.c: the players' frame rates */
static void got(uint8_t *m, int n, uint32_t from, uint32_t now){
    int peer = 0;
    for (int i = 0; i < g_npeers && !peer; i++) peer = g_peers[i] == from;
    if (!peer){ g_dropped++; return; }                   /* not one of the race's games */
    if (n >= 4 && !memcmp(m, "N2FS", 4)){ racenet_heard(m, n, from); return; }
    if (n < MSG_N || memcmp(m, "N2HN", 4) || m[4] != 1) return;
    char name[NAME_N];
    int k = 0;
    for (; k < NAME_N - 1 && m[8 + k] >= 0x20 && m[8 + k] <= 0x7e; k++) name[k] = (char)m[8 + k];
    name[k] = 0;
    if (!name[0]) return;
    int creator = (int32_t)rd32(G_NET_HOST) > 0;
    if (creator && (m[5] & 2)){ g_dropped++; return; }  /* only the creator passes horns on */
    if (creator){                                        /* the creator passes it on */
        if (!relay_ok(from, now)){ g_dropped++; return; }
        m[5] |= 2; send_all(m, from);
    }
    int j = 0;
    while (j < NHORNS && strcmp(g_h[j].name, name)) j++;
    if (j == NHORNS){
        for (j = 0; j < NHORNS && g_h[j].name[0] && g_h[j].on && now - g_h[j].at < STALE_MS; j++) {}
        if (j == NHORNS) return;
        memcpy(g_h[j].name, name, NAME_N);
    }
    g_h[j].on = m[5] & 1; g_h[j].kind = m[5] >> 2 & 15; g_h[j].at = now;
}

/* every frame, on the game thread (roam.c's main-loop hook) */
void racehorn_frame(CPU *c){
    (void)c;
    if (!horn_on()) return;
    uint32_t now = now_ms(), from;
    uint8_t m[64];
    int n;
    g_npeers = vlan_race_peers(g_peers, 16, PEER_MS);
    for (int i = 0; i < HEAR_MAX && (n = vlan_rt_recv(HORN_PORT, &from, m, sizeof m)) >= 0; i++) got(m, n, from, now);
    uint32_t pl = rd32(G_PLAYER1), me = pl ? rd32(pl + 4u) : 0, w = rd32(G_WORLD);
    float dt = MRF32(G_WORLDDT);
    int racing = rd32(G_FLOW) == 6u && (rd32(G_NETMODE) & 0x208u) && ok(me, 0x9e0) && ok(w, 0x80);
    int runs = racing && dt > 0.f && dt < 1.f;           /* not paused, not loading */
    char mine[NAME_N];
    car_name(me, mine);
    /* our horn to the others */
    int horn = runs && mine[0] && horn_held();
    if (horn != g_mine){ g_mine = horn; g_offs = horn ? 0 : 2; g_sent_at = now - SEND_MS; }
    if (mine[0] && (g_mine || g_offs) && now - g_sent_at >= SEND_MS){
        memset(m, 0, MSG_N);
        memcpy(m, "N2HN", 4); m[4] = 1; m[5] = (uint8_t)(g_mine | (horn_mine() & 15) << 2); m[6] = (uint8_t)g_seq; m[7] = (uint8_t)(g_seq >> 8); g_seq++;
        memcpy(m + 8, mine, strlen(mine));
        send_all(m, 0);
        g_sent_at = now;
        if (!g_mine) g_offs--;
    }
    /* the horns heard here */
    if (!runs && !g_active) return;                      /* free roam may have the voices */
    float L[3] = {0}, f[3] = {1.f, 0.f, 0.f}, v[3] = {0};
    uint32_t cam = rd32(G_VIEW1 + 0x40u);
    if (runs && ok(cam, 0x60)){ rd3(cam + 0x40u, L); rd3(cam + 0x50u, f); }
    else if (runs){ rd3(me + 0x60u, L); rd3(me + 0x90u, f); }
    if (runs) rd3(me + 0x70u, v);
    horn_begin(runs ? L : 0, f, v);
    if (horn) horn_sound(fnv1a(mine), mine, horn_mine(), 0, 0);
    for (int j = 0; j < NHORNS; j++){
        if (!runs || !g_h[j].on || now - g_h[j].at >= STALE_MS) continue;
        uint32_t car = rd32(w);
        for (int k = 0; car && car != w && k < 64 && ok(car, 0x9e0); k++, car = rd32(car)){
            char nm[NAME_N];
            if (car == me) continue;
            car_name(car, nm);
            if (strcmp(nm, g_h[j].name)) continue;
            float p[3], cv[3];
            rd3(car + 0x60u, p); rd3(car + 0x70u, cv);
            horn_sound(fnv1a(nm), nm, g_h[j].kind, p, cv);
            break;
        }
    }
    horn_end();
    static int nlog;
    if (runs && !g_active && ++nlog <= 10){              /* a race starts (or goes on): who is in it, by name */
        char line[200]; int o = snprintf(line, sizeof line, "[horn] race: me %s, cars", mine[0] ? mine : "(no name)");
        uint32_t car = rd32(w);
        for (int k = 0; car && car != w && k < 64 && ok(car, 0x9e0) && o < (int)sizeof line - 20; k++, car = rd32(car)){
            char nm[NAME_N]; car_name(car, nm);
            o += snprintf(line + o, sizeof line - (size_t)o, " %s", nm[0] ? nm : "-");
        }
        fprintf(stderr, "%s\n", line);
    }
    if (!runs && g_active && g_dropped){ fprintf(stderr, "[horn] race over: %u horn datagrams not taken (not from the race, relayed to the creator, or past the rate)\n", g_dropped); g_dropped = 0; }
    g_active = runs;
}
