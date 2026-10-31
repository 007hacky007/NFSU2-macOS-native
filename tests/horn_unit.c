/* horn_unit.c -- unit tests of the horns between players and the other
 * players' car sounds (runtime/horn.c, racehorn.c, carsfx.c), without the
 * game: tests/horn_unit.sh builds this file three times, each with one of
 * them (-DT_HORN, -DT_RACEHORN, -DT_CARSFX), and runs them.  The game's
 * memory is a 4 GB reservation of our own with only the pages a test uses
 * marked committed; the clock is a fake one, 10 ms a block.
 *
 * carsfx's test also reads the game's own sound files when NFSU2_DATA names
 * a SPEED2.EXE (its folder's SOUND\NOS banks and an engine's GIN files). */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

static uint64_t g_fake_ns = 1000000000u;
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

static float peak(const float *st, unsigned n, int ch){ float p = 0.f; for (unsigned i = 0; i < n; i++) if (fabsf(st[2 * i + ch]) > p) p = fabsf(st[2 * i + ch]); return p; }

#if defined(T_HORN)
static int g_key;
int metal_key_down(unsigned dik){ return dik == 0x31 && g_key; }
#include "../runtime/horn.c"

static void blk(float *st, unsigned n){ memset(st, 0, 2u * n * sizeof *st); horn_mix(st, n, 44100); g_fake_ns += 10000000u; }
int main(void){
    /* off: no horn, the key does nothing (a child process, as the setting is read once) */
    pid_t pid = fork();
    if (!pid){
        unsetenv("NFSU2_HORN"); g_key = 1;
        int bad = horn_on() || horn_mine() != -1 || horn_held();
        float st[2 * 441] = {0};
        horn_preview(); horn_mix(st, 441, 44100);       /* nothing made, nothing mixed */
        bad |= peak(st, 441, 0) != 0.f;
        _exit(bad);
    }
    int ws = 0; waitpid(pid, &ws, 0);
    CHECK(WIFEXITED(ws) && WEXITSTATUS(ws) == 0, "NFSU2_HORN unset: horns off, the key does nothing");
    pid = fork();
    if (!pid){ setenv("NFSU2_HORN", "off", 1); _exit(horn_on() || horn_mine() != -1); }
    waitpid(pid, &ws, 0);
    CHECK(WIFEXITED(ws) && WEXITSTATUS(ws) == 0, "NFSU2_HORN=off: horns off");
    pid = fork();
    if (!pid){ setenv("NFSU2_HORN", "bogus", 1); _exit(!(horn_on() && horn_mine() == 0)); }
    waitpid(pid, &ws, 0);
    CHECK(WIFEXITED(ws) && WEXITSTATUS(ws) == 0, "NFSU2_HORN=bogus: the dual horn");

    setenv("NFSU2_HORN", "Truck", 1);
    CHECK(horn_on() && horn_mine() == 2 && !strcmp(horn_name(horn_mine()), "truck"), "NFSU2_HORN=Truck: the truck horn (%d)", horn_mine());
    CHECK(!strcmp(horn_name(-5), "dual") && !strcmp(horn_name(99), "dual"), "a kind out of range is named as the dual horn");
    g_key = 0; CHECK(!horn_held(), "key up: no horn");
    g_key = 1; CHECK(horn_held(), "N held: the horn");

    /* the volume: 0.1 .. 1, anything else to its nearer end */
    horn_set_volume(5.f);  CHECK(bitsf(g_vol) == 1.f, "volume 5 -> 1");
    horn_set_volume(0.f);  CHECK(bitsf(g_vol) == HORN_VOL_MIN, "volume 0 -> 0.1");
    horn_set_volume(NAN);  CHECK(bitsf(g_vol) == HORN_VOL_MIN, "volume NaN -> 0.1");
    horn_set_volume(1.f);

    float pos[3] = {0, 0, 0}, fwd[3] = {1, 0, 0}, vel[3] = {0, 0, 0}, st[2 * 441];
    /* a friend's horn: out of hearing, near, its voice kept */
    horn_begin(pos, fwd, vel);
    float far[3] = {300.f, 0, 0}, nanp[3] = {NAN, 0, 0};
    CHECK(horn_sound(1, "far", 0, far, 0) == -1, "300 m: out of hearing");
    CHECK(horn_sound(2, "nan", 0, nanp, 0) == -1, "a NaN position: out of hearing");
    float left[3] = {0, 5.f, 0};                       /* x forward, y left (z up) */
    CHECK(horn_sound(3, "Bravo", 200, left, vel) == 1, "5 m to the left: starts (a kind past the known ones)");
    horn_end();
    blk(st, 441);
    for (int i = 0; i < 20; i++){ horn_begin(pos, fwd, vel); CHECK(horn_sound(3, "Bravo", 200, left, vel) == 0, "goes on"); horn_end(); blk(st, 441); }
    float pl = peak(st, 441, 0), pr = peak(st, 441, 1);
    CHECK(pl > 0.05f && pl < 1.f && pr < pl * 0.5f, "a horn on the left: left %.3f, right %.3f", (double)pl, (double)pr);
    /* farther is quieter */
    float mid[3] = {60.f, 0, 0};
    for (int i = 0; i < 20; i++){ horn_begin(pos, fwd, vel); horn_sound(3, "Bravo", 0, mid, vel); horn_end(); blk(st, 441); }
    float pm = peak(st, 441, 0);
    CHECK(pm < pl * 0.35f && pm > 0.f, "60 m: quieter (%.4f against %.4f)", (double)pm, (double)pl);
    /* let go: it fades out */
    for (int i = 0; i < 60; i++){ horn_begin(pos, fwd, vel); horn_end(); blk(st, 441); }
    CHECK(peak(st, 441, 0) < 1e-4f, "let go: silent after 0.6 s (%.6f)", (double)peak(st, 441, 0));
    /* every voice taken: the next horn waits */
    horn_begin(pos, fwd, vel);
    int started = 0;
    for (uint32_t w = 100; w < 100 + HORN_VOICES; w++) started += horn_sound(w, "x", 1, left, 0) == 1;
    CHECK(started == HORN_VOICES && horn_sound(999, "y", 1, left, 0) == -1, "%d voices, the next one: none", started);
    horn_end();
    /* a parked game: a voice not set for 250 ms falls silent in the mixer */
    for (int i = 0; i < 5; i++) blk(st, 441);
    for (int i = 0; i < 40; i++) blk(st, 441);
    CHECK(peak(st, 441, 0) < 1e-4f, "not driven: silent (%.6f)", (double)peak(st, 441, 0));
    /* the preview (the Horn Volume slider) */
    for (int i = 0; i < 60; i++){ horn_begin(pos, fwd, vel); horn_end(); blk(st, 441); }
    horn_set_volume(0.5f); horn_preview(); blk(st, 441); blk(st, 441);
    float p50 = peak(st, 441, 0);
    CHECK(p50 > 0.01f, "the preview sounds (%.3f)", (double)p50);
    printf("horn: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail != 0;
}

#elif defined(T_RACEHORN)
/* horn.c, as racehorn.c uses it */
static int g_on = 1, g_held;
int horn_on(void){ return g_on; }
int horn_held(void){ return g_held; }
int horn_mine(void){ return 4; }
static int g_sounded; static char g_last[32]; static int g_kind;
void horn_begin(const float *pos, const float *fwd, const float *vel){ (void)pos; (void)fwd; (void)vel; }
int horn_sound(uint32_t who, const char *name, int kind, const float *p, const float *v){
    (void)who; (void)p; (void)v; g_sounded++; snprintf(g_last, sizeof g_last, "%s", name); g_kind = kind; return 0; }
void horn_end(void){}
/* net_relay.c and racenet.c */
#define PEERS 3
static uint32_t g_peer[PEERS] = { 0x0a4d0102u, 0x0a4d0202u, 0x0a4d0302u };
static int g_npeer = PEERS, g_sent, g_n2fs;
static struct { uint32_t ip; uint8_t m[64]; int n; } g_q[256]; static int g_qh, g_qt;
int vlan_rt_send(uint16_t port, uint32_t ip_h, const void *p, int n){ (void)port; (void)ip_h; (void)p; (void)n; g_sent++; return 0; }
int vlan_rt_recv(uint16_t port, uint32_t *ip_h, void *p, int cap){
    (void)port;
    if (g_qh == g_qt) return -1;
    int n = g_q[g_qh].n < cap ? g_q[g_qh].n : cap;
    memcpy(p, g_q[g_qh].m, (size_t)n); *ip_h = g_q[g_qh].ip; g_qh = (g_qh + 1) % 256;
    return n;
}
int vlan_race_peers(uint32_t *ip_h, int max, uint32_t within_ms){ (void)within_ms; int n = g_npeer < max ? g_npeer : max; memcpy(ip_h, g_peer, 4u * (size_t)n); return n; }
void racenet_heard(uint8_t *m, int n, uint32_t from){ (void)m; (void)n; (void)from; g_n2fs++; }
#include "../runtime/racehorn.c"

static void put(uint32_t ip, const void *m, int n){ g_q[g_qt].ip = ip; memcpy(g_q[g_qt].m, m, (size_t)(n < 64 ? n : 64)); g_q[g_qt].n = n; g_qt = (g_qt + 1) % 256; }
static void honk(uint32_t ip, const char *name, uint8_t flags){
    uint8_t m[MSG_N] = { 'N', '2', 'H', 'N', 1, flags, 0, 0 };
    memcpy(m + 8, name, strlen(name) < NAME_N ? strlen(name) : NAME_N);
    put(ip, m, MSG_N);
}
static CPU g_c;
static void frame(void){ racehorn_frame(&g_c); g_fake_ns += 10000000u; }
int main(void){
    g_mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_NORESERVE, -1, 0);
    if (g_mem == MAP_FAILED){ printf("no 4 GB reservation\n"); return 1; }
    commit(G_NET_HOST, 4);
    /* a joiner: what its creator passes on is taken, nothing is passed on */
    MR32(G_NET_HOST) = 0;
    honk(g_peer[0], "Alpha", 1 | 2 | 3 << 2); frame();
    CHECK(g_sent == 0 && g_h[0].on && !strcmp(g_h[0].name, "Alpha") && g_h[0].kind == 3, "a joiner takes a relayed horn (sent %d)", g_sent);
    /* not from a peer of the race: dropped */
    honk(0x0a4d0909u, "Mallory", 1); frame();
    CHECK(g_dropped == 1 && strcmp(g_h[1].name, "Mallory"), "a horn from outside the race: dropped");
    /* short, other versions, names without a printable first byte */
    uint8_t m[64] = { 'N', '2', 'H', 'N', 1, 1 };
    put(g_peer[0], m, 7); m[4] = 2; put(g_peer[0], m, MSG_N); m[4] = 1; m[8] = 0x07; put(g_peer[0], m, MSG_N);
    put(g_peer[0], "N2FS", 4);
    frame();
    int used = 0; for (int j = 0; j < NHORNS; j++) used += g_h[j].name[0] != 0;
    CHECK(used == 1 && g_n2fs == 1, "short, other version, unprintable name: none taken; N2FS to racenet (%d %d)", used, g_n2fs);
    /* a name of 16 printable bytes and more: cut at 15 */
    honk(g_peer[1], "ABCDEFGHIJKLMNOPQRSTUVWX", 1); frame();
    int cut = 0; for (int j = 0; j < NHORNS; j++) cut |= !strcmp(g_h[j].name, "ABCDEFGHIJKLMNO");
    CHECK(cut, "a long name: its first 15 characters");
    /* the creator: passes a joiner's on, at most RELAY_PER_S a second, never a relayed one */
    MR32(G_NET_HOST) = 1; g_sent = 0; g_dropped = 0;
    honk(g_peer[2], "Bravo", 1 | 2); frame();
    CHECK(g_sent == 0 && g_dropped == 1, "the creator drops a relayed horn");
    for (int i = 0; i < 40; i++) honk(g_peer[2], "Bravo", 1);
    frame();
    CHECK(g_sent == (PEERS - 1) * (int)RELAY_PER_S && g_dropped == 1 + 40 - RELAY_PER_S, "40 at once: %d passed on (%d sends), %u dropped",
          (int)RELAY_PER_S, g_sent, g_dropped);
    g_fake_ns += 1100000000u; g_sent = 0;
    honk(g_peer[2], "Bravo", 1); frame();
    CHECK(g_sent == PEERS - 1, "a second later: passed on again (%d)", g_sent);
    /* a flood: HEAR_MAX a frame, the rest later */
    g_qh = g_qt = 0;
    for (int i = 0; i < 200; i++) honk(0x0a4d0909u, "Mallory", 1);
    frame();
    int left = (g_qt - g_qh + 256) % 256;
    CHECK(left == 200 - HEAR_MAX, "a flood: %d taken this frame, %d wait", HEAR_MAX, left);
    g_qh = g_qt = 0;
    /* off: the port is not read, nothing goes out */
    g_on = 0; g_sent = 0; g_held = 1;
    honk(g_peer[0], "Alpha", 1); frame();
    CHECK(g_qh != g_qt && g_sent == 0, "horns off: nothing read, nothing sent");
    printf("racehorn: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail != 0;
}

#elif defined(T_CARSFX)
static char g_dir[1024];
int fileio_resolve_game(const char *win, char *out, size_t outsz){
    if (!g_dir[0]) return 0;
    int n = snprintf(out, outsz, "%s/", g_dir);
    for (const char *s = win; *s && n + 1 < (int)outsz; s++) out[n++] = *s == '\\' ? '/' : *s;
    out[n] = 0;
    return 1;
}
#include "../runtime/carsfx.c"

/* every prefix of a file, and every byte of its head flipped, through a parser: no crash, no sample past the data */
static void fuzz_bank(const uint8_t *f, size_t len){
    uint8_t *c = malloc(len);
    int ok = 0;
    for (size_t l = 0; l <= len; l += l < 4096 ? 1 : 997){
        memcpy(c, f, l); Sample s = {0};
        if (bank_sample(c, l, 3, &s)){ ok++; free(s.pcm); }
    }
    for (size_t i = 0; i < 4096 && i < len; i++){
        memcpy(c, f, len); c[i] ^= 0xff; Sample s = {0};
        if (bank_sample(c, len, 3, &s)){ CHECK(s.n <= 1u << 22 && s.loop1 <= s.n, "flipped byte %zu: a sample within bounds", i); free(s.pcm); }
    }
    free(c);
    CHECK(ok >= 1, "the whole bank parses (%d prefixes did)", ok);
}
int main(void){
    g_mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_NORESERVE, -1, 0);
    if (g_mem == MAP_FAILED){ printf("no 4 GB reservation\n"); return 1; }
    const char *exe = getenv("NFSU2_DATA");
    if (exe && *exe){ snprintf(g_dir, sizeof g_dir, "%s", exe); char *sl = strrchr(g_dir, '/'); if (sl) *sl = 0; else g_dir[0] = 0; }
    /* garbage banks */
    uint8_t junk[512];
    for (int i = 0; i < 512; i++) junk[i] = (uint8_t)(i * 37 + 11);
    memcpy(junk + 100, "BNKl", 4);
    Sample s0 = {0};
    CHECK(!bank_sample(junk, sizeof junk, 3, &s0), "a junk bank: no sample");
    CHECK(!bank_sample(junk, 0, 0, &s0) && !bank_sample(junk, 103, 0, &s0), "empty and cut banks: no sample");
    if (g_dir[0]){
        long len = 0;
        uint8_t *f = game_file("SOUND\\NOS\\Nitrous_01_MB.abk", &len);
        CHECK(f && len > 1000, "the game's nitrous bank (%ld bytes)", len);
        if (f){ fuzz_bank(f, (size_t)len); free(f); }
        Gin g;
        CHECK(!gin_load("..\\..\\nothing.gin", &g), "a GIN file that is not there");
        /* three engines of the game's SOUND/ENGINE */
        int found = 0;
        char path[1100]; snprintf(path, sizeof path, "%s/SOUND/ENGINE", g_dir);
        FILE *ls = 0; char cmd[1200]; snprintf(cmd, sizeof cmd, "ls '%s' | grep -i '\\.gin$' | head -3", path);
        ls = popen(cmd, "r");
        char nm[128];
        while (ls && fgets(nm, sizeof nm, ls)){
            nm[strcspn(nm, "\r\n")] = 0;
            if (gin_load(nm, &g)){
                found++;
                CHECK(g.ngr >= 1 && g.start[g.ngr] <= g.n && g.rmax > g.rmin, "%s: %u grains, rpm %.0f .. %.0f", nm, g.ngr, (double)g.rmin, (double)g.rmax);
                uint32_t a = gin_grain(&g, -1e9f), b = gin_grain(&g, 1e9f), c = gin_grain(&g, NAN);
                CHECK(a < g.ngr && b < g.ngr && c < g.ngr, "%s: a grain in range for any rpm (%u %u %u)", nm, a, b, c);
                gin_free(&g);
            }
        }
        if (ls) pclose(ls);
        CHECK(found > 0, "an engine's GIN file of the game loads (%d)", found);
    } else printf("carsfx: NFSU2_DATA not set, the game's files not tried\n");
    /* the game thread's side: a friend's car with odd numbers from the network */
    float pos[3] = {0, 0, 0}, fwd[3] = {1, 0, 0};
    carsfx_begin(pos, fwd, 0);
    for (int i = 0; i < 2000 && !__atomic_load_n(&g_ready, __ATOMIC_ACQUIRE); i++) usleep(1000);
    float p[3] = {10.f, 0, 0}, nanp[3] = {NAN, NAN, NAN}, v[3] = {INFINITY, 0, 0};
    for (int f = 0; f < 50; f++){
        carsfx_begin(pos, fwd, 0);
        carsfx_state st = { (uint8_t)(f & 1), (uint8_t)((f & 2) != 0), (uint8_t)(f * 37), (uint8_t)f, 0, { 0, 0 }, NAN, { NAN, INFINITY } };
        carsfx_car(1, "Bravo", p, v, &st);
        carsfx_car(2, "Nan", nanp, nanp, &st);
        for (uint32_t w = 3; w < 3 + 40; w++) carsfx_car(w, "crowd", p, 0, &st);   /* more cars than there is room for */
        carsfx_end();
        float st2[2 * 441] = {0};
        carsfx_mix(st2, 441, 44100);
        int fin = 1; for (int i = 0; i < 2 * 441; i++) fin &= isfinite(st2[i]) != 0;
        if (!fin){ CHECK(0, "frame %d: the mix is not finite", f); break; }
        g_fake_ns += 10000000u;
    }
    int used = 0; for (int k = 0; k < CARSFX_VOICES; k++) used += g_vo[k].used;
    CHECK(used <= CARSFX_VOICES, "odd states, a NaN car, 42 cars: the mix stays finite, %d voices", used);
    printf("carsfx: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail != 0;
}
#endif
