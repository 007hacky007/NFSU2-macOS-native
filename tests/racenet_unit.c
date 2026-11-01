/* racenet_unit.c -- unit tests of runtime/racenet.c's car states straight
 * between the joiners' games ("N2CS", the creator's list "N2PL") and the
 * fading of the corrections, without the game: the game's memory is a 4 GB
 * reservation of our own with only the pages a test uses marked committed,
 * the virtual LAN and the game's handler are stand-ins, the clock a fake one.
 * tests/racenet_unit.sh builds and runs it. */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

static uint64_t g_fake_ns = 5000000000u;
static int fake_clock_gettime(clockid_t id, struct timespec *ts){
    (void)id; ts->tv_sec = (time_t)(g_fake_ns / 1000000000u); ts->tv_nsec = (long)(g_fake_ns % 1000000000u); return 0;
}
#define clock_gettime(a, b) fake_clock_gettime((a), (b))
#include "../runtime/cpu.h"
uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
static void commit(uint32_t a, uint32_t n){ for (uint32_t pg = a >> 14; pg <= (a + n - 1) >> 14; pg++) g_cbits[pg >> 3] |= (uint8_t)(1u << (pg & 7)); }

static int g_fail, g_pass;
#define CHECK(c, ...) do { if (c) g_pass++; else { g_fail++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* horn.c: off, so racenet.c reads the port itself */
int horn_on(void){ return 0; }
/* net_relay.c: the race's peers, what was sent, what comes */
static uint32_t g_peer[3]; static int g_npeer;
static struct { uint32_t ip; uint8_t m[1100]; int n; } g_out[64]; static int g_nout;
static struct { uint32_t ip; uint8_t m[1100]; int n; } g_in[16]; static int g_inh, g_int;
int vlan_rt_send(uint16_t port, uint32_t ip_h, const void *p, int n){
    (void)port;
    if (g_nout < 64 && n <= 1100){ g_out[g_nout].ip = ip_h; memcpy(g_out[g_nout].m, p, (size_t)n); g_out[g_nout].n = n; g_nout++; }
    return 0;
}
int vlan_rt_recv(uint16_t port, uint32_t *ip_h, void *p, int cap){
    (void)port;
    if (g_inh == g_int) return -1;
    int n = g_in[g_inh].n < cap ? g_in[g_inh].n : cap;
    memcpy(p, g_in[g_inh].m, (size_t)n); *ip_h = g_in[g_inh].ip; g_inh++;
    return n;
}
int vlan_race_peers(uint32_t *ip_h, int max, uint32_t within_ms){ (void)within_ms; int n = g_npeer < max ? g_npeer : max; memcpy(ip_h, g_peer, 4u * (size_t)n); return n; }
static uint32_t g_sentto[4]; static int g_nsentto;    /* the addresses the game's race link sends to */
int vlan_race_sent_to(uint32_t ip_h, uint32_t within_ms){ (void)within_ms; for (int i = 0; i < g_nsentto; i++) if (g_sentto[i] == ip_h) return 1; return 0; }
/* the lifted functions racenet.c wraps */
static int g_orig_send, g_orig_state;
void sub_005f8d50_orig(CPU *c){ (void)c; }
void sub_005f8910_orig(CPU *c){ (void)c; g_orig_state++; }
void sub_00585d60_orig(CPU *c){ (void)c; g_orig_send++; }
/* the game's handler of the creator's messages, as dispatch_indirect calls it */
static int g_calls, g_direct_seen; static uint32_t g_fn, g_ret, g_len, g_zero; static uint8_t g_bytes[1100];
void dispatch_indirect(CPU *c, uint32_t addr);
#include "../runtime/racenet.c"
void dispatch_indirect(CPU *c, uint32_t addr){
    g_calls++; g_fn = addr; g_direct_seen = g_direct;
    g_ret = MR32(c->esp); uint32_t buf = MR32(c->esp + 4u); g_len = MR32(c->esp + 8u); g_zero = MR32(c->esp + 12u);
    for (uint32_t i = 0; i < g_len && i < sizeof g_bytes; i++) g_bytes[i] = MR8(buf + i);
    c->eax = 0x1234u; c->esp += 4u;                       /* its ret */
}

/* a network race: a world with a friend's car and ours */
#define W     0x10000000u
#define CAR_A 0x10010000u
#define CAR_ME 0x10020000u
#define PL    0x10030000u
#define RC    0x10040000u
#define CTL   0x10050000u
#define BS    0x10060000u
#define STACK 0x00130000u
static CPU g_c;
static void race_setup(int host){
    uint32_t g[] = { G_FLOW, G_NETMODE, G_NET_HOST, G_WORLD, G_PLAYER1, G_WORLDDT, G_RACE, G_WORLDTIME, G_NETPLAYERS,
                     G_MYSLOT, G_HOSTSLOT, G_SLOTBITS, G_SLOTMIN };
    for (unsigned i = 0; i < sizeof g / sizeof g[0]; i++) commit(g[i], 32);
    commit(W, 0x100); commit(CAR_A, 0xa00); commit(CAR_ME, 0xa00); commit(PL, 16); commit(RC, 0xc00); commit(CTL, 0x200); commit(BS, 0x410);
    commit(STACK - 0x4000u, 0x8000u);
    MR32(G_FLOW) = 6; MR32(G_NETMODE) = 8; MR32(G_NET_HOST) = host ? 1u : 0u;
    MR32(G_WORLD) = W; MR32(W) = CAR_A; MR32(CAR_A) = CAR_ME; MR32(CAR_ME) = W;
    MR32(G_PLAYER1) = PL; MR32(PL + 4u) = CAR_ME;
    MR32(G_RACE) = RC; MR32(RC) = RC_RACING; MR32(RC + 0x24u) = 0;
    MRF32(G_WORLDDT) = 0.02f;
    MR32(G_SLOTBITS) = 3; MR32(G_SLOTMIN) = 0; MR32(G_MYSLOT) = 1; MR32(G_HOSTSLOT) = 0;
    MR16(CAR_A + 0xau) = 0xffffu; MR16(CAR_ME + 0xau) = 0xffffu;
    g_c.esp = STACK;
}
static void frame(void){ racenet_frame(&g_c); g_fake_ns += 20000000u; MR32(G_WORLDTIME) += 80u; }
static void setf3(uint32_t a, float x, float y, float z){ MRF32(a) = x; MRF32(a + 4u) = y; MRF32(a + 8u) = z; }
/* a car state message: kind 2, then at bit 40 the slot in 3 bits */
static int carspam(uint8_t *m, uint32_t slot, int len){
    memset(m, 0, CS_HDR + (size_t)len);
    memcpy(m, "N2CS", 4); m[4] = 1; m[6] = (uint8_t)len; m[7] = (uint8_t)(len >> 8);
    m[CS_HDR] = MSG_CARSPAM;
    m[CS_HDR + 5] = (uint8_t)(slot << 5);
    for (int i = 6; i < len; i++) m[CS_HDR + i] = (uint8_t)(0x40 + i);
    return (int)CS_HDR + len;
}

int main(void){
    g_mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_NORESERVE, -1, 0);
    if (g_mem == MAP_FAILED){ printf("no 4 GB reservation\n"); return 1; }
    const uint32_t creator = 0x0a4d0101u, j1 = 0x0a4d0202u, j2 = 0x0a4d0303u, j3 = 0x0a4d0404u, stranger = 0x0a4d0909u;

    /* ---- the creator: each joiner gets the list of the others, every PL_MS ---- */
    race_setup(1);
    g_peer[0] = j1; g_peer[1] = j2; g_peer[2] = j3; g_npeer = 3;
    frame();
    int lists = 0, right = 1;
    for (int i = 0; i < g_nout; i++){
        if (memcmp(g_out[i].m, "N2PL", 4)) continue;
        lists++;
        const uint8_t *m = g_out[i].m;
        right &= m[4] == 1 && m[6] == 2 && g_out[i].n == 16;
        for (int k = 0; k < m[6]; k++){
            uint32_t a = (uint32_t)m[8 + 4 * k] | (uint32_t)m[9 + 4 * k] << 8 | (uint32_t)m[10 + 4 * k] << 16 | (uint32_t)m[11 + 4 * k] << 24;
            right &= a != g_out[i].ip && (a == j1 || a == j2 || a == j3);
        }
    }
    CHECK(lists == 3 && right, "the creator: 3 lists, each of the 2 other joiners (%d lists)", lists);
    g_nout = 0; frame();
    CHECK(g_nout == 0, "the next list only after PL_MS (%d sent)", g_nout);
    g_fake_ns += 1000000000u; frame();
    CHECK(g_nout == 3, "a second later: the lists again (%d)", g_nout);
    /* the creator takes no list and sends no car state of its own straight */
    racenet_list((const uint8_t *)"N2PL\1\0\1\0\2\2\x4d\x0a", 12, creator);
    CHECK(g_pl.n == 0, "the creator takes no list");

    /* ---- a joiner ---- */
    race_setup(0);
    g_peer[0] = creator; g_npeer = 1; g_nout = 0;
    uint8_t pl[16] = { 'N', '2', 'P', 'L', 1, 0, 2, 0 };
    for (int b = 0; b < 4; b++){ pl[8 + b] = (uint8_t)(j2 >> (8 * b)); pl[12 + b] = (uint8_t)(j3 >> (8 * b)); }
    racenet_list(pl, 16, stranger);
    CHECK(g_pl.n == 0, "a list from outside the race: not taken");
    g_peer[1] = stranger; g_npeer = 2;                   /* a datagram to our UDP 3658 makes anyone a race peer */
    g_nsentto = 1; g_sentto[0] = creator;                /* the game's race link sends only to its creator */
    racenet_list(pl, 16, stranger);
    CHECK(g_pl.n == 0 && R.pl_refused == 2, "a list from a race peer the game does not send to: refused (%u)", R.pl_refused);
    pl[6] = 9; racenet_list(pl, 16, creator); pl[6] = 2;
    CHECK(g_pl.n == 0, "a list longer than NPL or than its bytes: not taken");
    g_in[0].ip = creator; memcpy(g_in[0].m, pl, 16); g_in[0].n = 16; g_inh = 0; g_int = 1;
    frame();                                             /* through the port, as it comes */
    CHECK(g_pl.n == 2 && g_pl.ip[0] == j2 && g_pl.ip[1] == j3 && g_pl.from == creator, "the creator's list taken from the port (%u)", g_pl.n);
    CHECK(g_nout == 0, "a joiner sends no list (%d)", g_nout);
    g_nsentto = 2; g_sentto[1] = stranger;
    uint8_t pl2[12] = { 'N', '2', 'P', 'L', 1, 0, 1, 0 };
    for (int b = 0; b < 4; b++) pl2[8 + b] = (uint8_t)(stranger >> (8 * b));
    racenet_list(pl2, 12, stranger);
    CHECK(g_pl.n == 2 && g_pl.from == creator && g_pl.ip[0] == j2 && R.pl_refused == 3,
          "a second list from another address the game sends to: refused, the first creator's kept");
    g_nsentto = 1; g_npeer = 1;

    /* our car state (0x585D60: kind 2, the bit stream) also goes to the joiners on the list */
    for (uint32_t i = 0; i < 13; i++) MR8(BS + i) = (uint8_t)(i ? 0x10 + i : MSG_CARSPAM);
    MR32(BS + BS_BYTES) = 100;                           /* 100 bits: 13 bytes */
    g_c.esp = STACK - 16u; MR32(g_c.esp + 4u) = MSG_CARSPAM; MR32(g_c.esp + 8u) = BS;
    g_nout = 0; g_orig_send = 0;
    sub_00585d60(&g_c);
    int same = g_nout == 2 && g_out[0].n == (int)CS_HDR + 13 && g_out[0].ip == j2 && g_out[1].ip == j3 &&
               !memcmp(g_out[0].m, "N2CS", 4) && g_out[0].m[6] == 13 && g_out[0].m[7] == 0;
    for (uint32_t i = 0; same && i < 13; i++) same = g_out[0].m[CS_HDR + i] == MR8(BS + i);
    CHECK(same && g_orig_send == 1 && R.cs_sent == 2, "our car state straight to the 2 joiners on the list, and to the creator (%d %d)", g_nout, g_orig_send);
    g_nout = 0; MR32(g_c.esp + 4u) = 3;
    sub_00585d60(&g_c);
    CHECK(g_nout == 0 && g_orig_send == 2, "another message: only to the creator");
    g_nout = 0; MR32(g_c.esp + 4u) = MSG_CARSPAM; g_fake_ns += 6000000000u;
    sub_00585d60(&g_c);
    CHECK(g_nout == 0, "with a list over PL_STALE_MS old: only to the creator");
    g_fake_ns -= 6000000000u;
    g_c.esp = STACK;

    /* a car state straight from a joiner on the list: to the game's handler, as the creator's copy goes */
    uint8_t m[CS_HDR + 64];
    int n = carspam(m, 3, 20);
    CPU before = g_c;
    racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 1 && g_fn == FN_JOIN_MSG && g_ret == HOOK_MAINLOOP && g_len == 20 && g_zero == 0 && !memcmp(g_bytes, m + CS_HDR, 20)
          && g_direct_seen == 1 && g_direct == 0, "a joiner's car state: the game's handler gets its bytes (%d calls, len %u)", g_calls, g_len);
    CHECK(g_c.esp == before.esp && g_c.eax == before.eax && R.cs_came == 1, "the CPU as it was after the call");
    racenet_carspam(&g_c, m, n, stranger);
    CHECK(g_calls == 1 && R.cs_refused == 1, "from an address not on the list: refused");
    n = carspam(m, 1, 20); racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 1 && R.cs_refused == 2, "for our own slot: refused");
    n = carspam(m, 0, 20); racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 1 && R.cs_refused == 3, "for the creator's slot: refused");
    n = carspam(m, 7, 20); racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 1 && R.cs_refused == 4, "a slot past 5: refused");
    n = carspam(m, 2, 20); racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 1 && R.cs_refused == 5, "j2 naming another slot than its first: refused");
    n = carspam(m, 3, 20); racenet_carspam(&g_c, m, n, j3);
    CHECK(g_calls == 1 && R.cs_refused == 6, "j3 naming j2's slot: refused");
    R.cs_refused -= 2;
    n = carspam(m, 3, 20); m[CS_HDR] = 4; racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 1 && R.cs_refused == 5, "another message: refused");
    n = carspam(m, 3, 20); racenet_carspam(&g_c, m, n - 1, j2);
    CHECK(g_calls == 1 && R.cs_refused == 6, "shorter than its length: refused");
    n = carspam(m, 2, 20);
    g_in[0].ip = j3; memcpy(g_in[0].m, m, (size_t)n); g_in[0].n = n; g_inh = 0; g_int = 1;
    frame();
    CHECK(g_calls == 2, "through the port, as it comes (%d)", g_calls);

    /* ---- the fade ---- */
    /* the friend's car gets a state (so the fade knows it), then moves at 10 m/s along x */
    MR32(CTL + CTL_CAR) = CAR_A; g_c.ecx = CTL; MR32(g_c.esp + 4u) = 0;
    sub_005f8910(&g_c);
    CHECK(fade_of(CAR_A, 0) != 0 && fade_of(CAR_ME, 0) == 0, "the fade keeps the friend's car, not ours");
    float x = 100.f;
    setf3(CAR_A + CAR_VEL, 10.f, 0.f, 0.f);
    for (int i = 0; i < 5; i++){ racenet_prestep(&g_c); x += 0.2f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame(); }
    CHECK(fabsf(MRF32(CAR_A + CAR_POS) - x) < 1e-5f, "a car that moves as it goes: drawn where it is (%.3f %.3f)", (double)MRF32(CAR_A + CAR_POS), (double)x);
    /* a state pulls it 2 m ahead: drawn where it was going, the step fading */
    racenet_prestep(&g_c); x += 0.2f + 2.f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame();
    float shown = MRF32(CAR_A + CAR_POS);
    Car *e = car_of(CAR_A, 0);
    CHECK(fabsf(shown - (x - 2.f)) < 0.1f && e && e->faded == 1, "a 2 m correction: drawn %.3f m behind, faded %u", (double)(x - shown), e ? e->faded : 0);
    racenet_prestep(&g_c);
    union { float f; uint32_t u; } own = { x };
    CHECK(MR32(CAR_A + CAR_POS) == own.u && MRF32(CAR_A + 0x50u) == x, "before the world's step: the car's own place back, bit for bit");
    float off[12];
    for (int i = 0; i < 12; i++){ x += 0.2f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame(); off[i] = x - MRF32(CAR_A + CAR_POS); racenet_prestep(&g_c); }
    int down = 1;
    for (int i = 1; i < 12; i++) down &= off[i] <= off[i - 1] + 1e-4f && off[i] >= -1e-4f;
    CHECK(down && off[0] > 1.f && off[9] < 0.2f, "the offset fades without a kick: %.3f, %.3f after 0.2 s, %.3f", (double)off[0], (double)off[9], (double)off[11]);
    /* a reset by the game between the frame and the step: its place is the game's */
    x += 0.2f + 3.f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame();
    CHECK(MRF32(CAR_A + CAR_POS) < x - 2.f, "another correction drawn behind");
    setf3(CAR_A + CAR_POS, 500.f, 5.f, 7.f);
    racenet_prestep(&g_c);
    CHECK(MRF32(CAR_A + CAR_POS) == 500.f && fade_of(CAR_A, 0)->o[0] == 0.f, "a place the game changed meanwhile: kept, the offset gone");
    /* over FADE_MAX: shown where it is */
    x = 500.f; setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame(); racenet_prestep(&g_c);
    x += 0.2f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame(); racenet_prestep(&g_c);
    uint32_t kept = e->kept;
    x += 30.f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame();
    CHECK(MRF32(CAR_A + CAR_POS) == x && e->kept == kept + 1, "a 30 m correction (after a stall): shown where it is");
    racenet_prestep(&g_c);
    /* the race over: the cars as the game has them */
    x += 0.2f; setf3(CAR_A + CAR_POS, x, 5.f, 7.f); setf3(CAR_A + 0x50u, x, 5.f, 7.f); frame();
    racenet_prestep(&g_c);
    MR32(RC) = 0; frame();
    CHECK(g_fade_world == 0 && !fade_of(CAR_A, 0) && MRF32(CAR_A + CAR_POS) == x, "the race over: no fade left");
    CHECK(g_pl.n == 0 && g_pl.from == 0 && g_nbind == 0, "the race over: no list, no slots (%u %d)", g_pl.n, g_nbind);
    racenet_carspam(&g_c, m, n, j2);
    CHECK(g_calls == 2, "out of the race: no car state taken");

    printf("racenet: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail != 0;
}
