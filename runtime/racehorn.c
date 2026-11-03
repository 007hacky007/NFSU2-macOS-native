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
 * carries the players' frame rates ("N2FS"), the joiners' car states
 * straight from their games ("N2CS", which come from the other joiners, not
 * the race's peers: racenet.c checks them against the creator's list) and
 * the creator's list of the joiners they go to ("N2PL"), which go to
 * racenet.c.
 * Quick chat in these races goes there too ("N2QC", below: qc_*).
 * Only Online, where the server's virtual LAN is; the Mac's own LAN has no
 * such port (vlan_rt_* send and receive nothing), and only while horns or
 * quick chat are on (horn.h horn_on, qc_on; racehorn_reads): with both off
 * nothing is sent or passed on, and racenet.c reads the port for the frame
 * rates alone.  With one of them off, nothing of it is sent, passed on or
 * shown.
 *
 * Ported from th0mk's nfsu2-web runtime/racehorn.c (MIT); quick chat from
 * its f1247927. */
#include "cpu.h"
#include "horn.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
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
/*   and quick chat's way to Game Tools (native_controls.m): the phrase the
 *   player picked lately (-1 none new), a line said, and where the player is */
int vlan_rt_say_pick(void);
int vlan_rt_said(const char *json, int n);
void vlan_rt_race(int state);
const char *autotest_top_fng(void);            /* autotest.c: the front end's top package */

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
/* to the race's other players (but except): how many it went to */
static int send_all(const uint8_t *m, uint32_t except){
    int to = 0;
    for (int i = 0; i < g_npeers; i++) if (g_peers[i] != except && vlan_rt_send(HORN_PORT, g_peers[i], m, MSG_N) == 0) to++;
    return to;
}
/* the creator may pass on another of this joiner's horns now */
static int relay_ok(uint32_t from, uint32_t now){
    int j = 0, old = 0;
    for (; j < 16 && g_rl[j].ip != from; j++) if (now - g_rl[j].win > now - g_rl[old].win) old = j;
    if (j == 16){ j = old; g_rl[j].ip = from; g_rl[j].win = now; g_rl[j].n = 0; }
    if (now - g_rl[j].win >= 1000u){ g_rl[j].win = now; g_rl[j].n = 0; }
    return ++g_rl[j].n <= RELAY_PER_S;
}
/* Quick chat in races between players (nfsu2-web f1247927; free roam has its own, roam_game.c say_*).  Game Tools'
 * picker (native_controls.m) opens while this says the player is in such a race (qc_status, vlan_rt_race: 1
 * driving, 2 on its results, 0 elsewhere) and hands the phrase picked here (vlan_rt_say_pick).  It goes to the
 * race's players as the horn does: "N2QC", version 1, flags (2 relayed), the sender's sequence number, the phrase
 * (its number in nfsu2-web's phrases.ts: any number goes, Game Tools shows those it has), the name the player races
 * under; the creator passes each joiner's on to the other joiners, and drops a relayed one.  Free roam's limits:
 * at most QC_BURST phrases in QC_WINDOW_MS from one player (the player's own too), and the same phrase from one
 * player again within QC_AGAIN_MS is not shown; the creator holds back what it would not show, so every player
 * drops the same ones, and also more than QC_BURST in QC_WINDOW_MS from one joiner's game under any names.  What is
 * shown goes to Game Tools (vlan_rt_said) as {"id","name","p","race":1} (+ "me" for the player's own): its chat
 * log over the game.  Quick chat off (NFSU2_ROAM_SAY not 1): nothing said, nothing shown and nothing passed on,
 * as with horns off.  A build before N2QC drops it (it is no N2HN), so a creator on one passes no joiner's
 * phrase on; a joiner on one only misses them. */
#define QC_BURST     3
#define QC_WINDOW_MS 6000u
#define QC_AGAIN_MS  2000u
#define QC_WHO       8
static struct { char name[NAME_N]; uint32_t t[QC_BURST], at, heard_at; uint8_t seq, phrase, heard; } g_qc[QC_WHO];
static struct { uint32_t ip, at, t[QC_BURST]; } g_qc_ip[16];   /* the creator: what each joiner's game sent */
static uint32_t g_qc_mine[QC_BURST];
static uint8_t g_qc_seq;
static int g_qc_test = -1;                          /* a script's "racesay N" (career.c; -1 none) */
static int g_qc_racing;                             /* this frame: in a network race, with a name */
static char g_qc_me[NAME_N];                        /*   and the name we race under */
static int g_qc_on = -1;                            /* NFSU2_ROAM_SAY=1: the launcher's Quick chat switch */
static int qc_on(void){
    if (g_qc_on < 0){ const char *v = getenv("NFSU2_ROAM_SAY"); g_qc_on = v && strtol(v, 0, 10) == 1; }
    return g_qc_on;
}
/* racenet.c: this file reads the port (else racenet.c does, for the frame rates) */
int racehorn_reads(void){ return horn_on() || qc_on(); }
static int qc_burst(const uint32_t *t, uint32_t now){
    int k = 0;
    for (int i = 0; i < QC_BURST; i++) k += t[i] && now - t[i] < QC_WINDOW_MS;
    return k >= QC_BURST;
}
static void qc_stamp(uint32_t *t, uint32_t now){
    int o = 0;
    for (int i = 1; i < QC_BURST; i++) if (t[i] < t[o]) o = i;    /* the oldest goes */
    t[o] = now ? now : 1u;
}
/* the creator: another phrase from this joiner's game may go on now */
static int qc_ip_ok(uint32_t ip, uint32_t now){
    int j = 0, old = 0;
    for (; j < 16 && g_qc_ip[j].ip != ip; j++) if (now - g_qc_ip[j].at > now - g_qc_ip[old].at) old = j;
    if (j == 16){ j = old; memset(&g_qc_ip[j], 0, sizeof g_qc_ip[j]); g_qc_ip[j].ip = ip; }
    if (qc_burst(g_qc_ip[j].t, now)) return 0;
    qc_stamp(g_qc_ip[j].t, now); g_qc_ip[j].at = now;
    return 1;
}
static void qc_page(const char *name, int phrase, int me){
    char js[128];
    int o = snprintf(js, sizeof js, "{\"id\":%u,\"name\":\"", fnv1a(name));
    for (const char *s = name; *s && o < (int)sizeof js - 40; s++){ if (*s == '"' || *s == '\\') js[o++] = '\\'; js[o++] = *s; }
    o += snprintf(js + o, sizeof js - (size_t)o, "\",\"p\":%d,\"race\":1%s}", phrase, me ? ",\"me\":1" : "");
    if (vlan_rt_said(js, o) < 0) fprintf(stderr, "[racechat] Game Tools took no line: %s\n", js);
}
/* the player's pick: to the others, and to Game Tools as said */
static void qc_say(int phrase, uint32_t now){
    if (!qc_on()){ fprintf(stderr, "[racechat] phrase %d not said (quick chat is off)\n", phrase); return; }
    if (phrase < 0 || phrase > 255){ fprintf(stderr, "[racechat] phrase %d not said (no such phrase)\n", phrase); return; }
    if (!g_qc_racing){ fprintf(stderr, "[racechat] phrase %d not said (not in a race between players)\n", phrase); return; }
    if (qc_burst(g_qc_mine, now)){ fprintf(stderr, "[racechat] phrase %d not said (too many at once)\n", phrase); return; }
    qc_stamp(g_qc_mine, now);
    uint8_t m[MSG_N];
    memset(m, 0, sizeof m);
    memcpy(m, "N2QC", 4); m[4] = 1; m[6] = ++g_qc_seq; m[7] = (uint8_t)phrase;
    memcpy(m + 8, g_qc_me, strlen(g_qc_me));
    int to = send_all(m, 0);
    qc_page(g_qc_me, phrase, 1);
    fprintf(stderr, "[racechat] %s said phrase %d to %d player(s)\n", g_qc_me, phrase, to);
}
/* another player's, from them or passed on by the creator (from one of the race's peers) */
static void qc_got(uint8_t *m, uint32_t from, uint32_t now){
    if (!qc_on()) return;                                 /* off: nothing shown, nothing passed on */
    char name[NAME_N];
    int k = 0;
    for (; k < NAME_N - 1 && m[8 + k] >= 0x20 && m[8 + k] <= 0x7e; k++) name[k] = (char)m[8 + k];
    name[k] = 0;
    if (!name[0] || !strcmp(name, g_qc_me)) return;
    int phrase = m[7], relayed = m[5] & 2, creator = (int32_t)rd32(G_NET_HOST) > 0;
    if (creator && relayed){ fprintf(stderr, "[racechat] %s's phrase %d dropped (relayed to the creator)\n", name, phrase); return; }
    int j = 0, o = 0;
    while (j < QC_WHO && strcmp(g_qc[j].name, name)) j++;
    if (j == QC_WHO){                                     /* a new one takes the place heard from longest ago */
        for (j = 1; j < QC_WHO; j++) if (now - g_qc[j].heard_at > now - g_qc[o].heard_at) o = j;
        j = o;
        memset(&g_qc[j], 0, sizeof g_qc[j]);
        memcpy(g_qc[j].name, name, NAME_N);
    }
    const char *why = 0;
    if (g_qc[j].heard && m[6] == g_qc[j].seq) why = "again";                     /* the same one twice */
    else if (qc_burst(g_qc[j].t, now)) why = "too many at once";
    else if (g_qc[j].at && phrase == g_qc[j].phrase && now - g_qc[j].at < QC_AGAIN_MS) why = "the same again";
    else if (creator && !qc_ip_ok(from, now)) why = "too many from that game";
    g_qc[j].seq = m[6]; g_qc[j].heard = 1; g_qc[j].heard_at = now;
    if (why){ fprintf(stderr, "[racechat] %s's phrase %d not shown (%s)\n", name, phrase, why); return; }
    qc_stamp(g_qc[j].t, now);
    g_qc[j].phrase = (uint8_t)phrase; g_qc[j].at = now;
    int to = 0;
    if (creator){ m[5] |= 2; to = send_all(m, from); }   /* the creator passes it on */
    if (!g_qc_racing){
        fprintf(stderr, "[racechat] %s's phrase %d not shown (not in a race between players)%s\n", name, phrase, to ? ", passed on" : "");
        return;
    }
    qc_page(name, phrase, 0);
    fprintf(stderr, "[racechat] %s said phrase %d (%s)%s\n", name, phrase, relayed ? "passed on by the race's creator" : "straight",
            to ? ", passed on" : "");
}
/* career.c's "racesay N": the phrase as if the player picked it in Game Tools */
void racehorn_test_say(int phrase){ g_qc_test = phrase; }
/* where the player is, for Game Tools' picker (vlan_rt_race, every frame): 1 while the player drives in a race
 * between players (a race HUD the top package, the start's cutscene too), 2 on its results (UI_PostRace*), 0
 * elsewhere (the pause menu, the loading screen, a race of the career or a Quick Race: not the network mode, and
 * with quick chat off) */
static void qc_status(void){
    static int last = -1;
    const char *top = qc_on() && g_qc_racing ? autotest_top_fng() : 0;
    int v = !top ? 0 : !strncasecmp(top, "HUD_", 4) && strcasecmp(top, "HUD_World_Loading.fng") ? 1
          : !strncasecmp(top, "UI_PostRace", 11) ? 2 : 0;
    vlan_rt_race(v);
    if (v == last) return;
    last = v;
    fprintf(stderr, "[racechat] netrace %d (%s)\n", v, top ? top : "-");
}
void racenet_heard(uint8_t *m, int n, uint32_t from);   /* racenet.c: the players' frame rates, */
void racenet_carspam(CPU *c, const uint8_t *m, int n, uint32_t from);   /*   a joiner's car state straight from its game, */
void racenet_list(const uint8_t *m, int n, uint32_t from);              /*   and the creator's list of the joiners */
static void got(CPU *c, uint8_t *m, int n, uint32_t from, uint32_t now){
    if (n >= 4 && !memcmp(m, "N2CS", 4)){ racenet_carspam(c, m, n, from); return; }   /* (from a joiner on the list) */
    int peer = 0;
    for (int i = 0; i < g_npeers && !peer; i++) peer = g_peers[i] == from;
    if (!peer){ g_dropped++; return; }                   /* not one of the race's games */
    if (n >= 4 && !memcmp(m, "N2FS", 4)){ racenet_heard(m, n, from); return; }
    if (n >= 4 && !memcmp(m, "N2PL", 4)){ racenet_list(m, n, from); return; }
    if (n >= MSG_N && !memcmp(m, "N2QC", 4)){ if (m[4] == 1) qc_got(m, from, now); return; }
    if (!horn_on() || n < MSG_N || memcmp(m, "N2HN", 4) || m[4] != 1) return;
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
    if (!racehorn_reads()){ if (g_qc_test >= 0){ qc_say(g_qc_test, 0); g_qc_test = -1; } return; }   /* (says why not) */
    uint32_t now = now_ms(), from;
    static uint8_t m[8 + 0x400];                         /* (a car state: racenet.c's N2CS, up to a bit stream's 0x400 bytes) */
    int n;
    uint32_t pl = rd32(G_PLAYER1), me = pl ? rd32(pl + 4u) : 0, w = rd32(G_WORLD);
    float dt = MRF32(G_WORLDDT);
    int racing = rd32(G_FLOW) == 6u && (rd32(G_NETMODE) & 0x208u) && ok(me, 0x9e0) && ok(w, 0x80);
    int runs = racing && dt > 0.f && dt < 1.f;           /* not paused, not loading */
    char mine[NAME_N];
    car_name(me, mine);
    g_qc_racing = racing && mine[0]; memcpy(g_qc_me, g_qc_racing ? mine : "", g_qc_racing ? NAME_N : 1);
    g_npeers = vlan_race_peers(g_peers, 16, PEER_MS);
    for (int i = 0; i < HEAR_MAX && (n = vlan_rt_recv(HORN_PORT, &from, m, sizeof m)) >= 0; i++) got(c, m, n, from, now);
    /* quick chat: the player's pick (taken in any case, so none waits for the next race) */
    int pick = qc_on() ? vlan_rt_say_pick() : -1;
    if (g_qc_test >= 0){ pick = g_qc_test; g_qc_test = -1; }
    if (pick >= 0) qc_say(pick, now);
    qc_status();
    if (!horn_on()) return;
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
