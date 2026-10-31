/* shop_music.m -- test helper for tests/shop_music.sh: from a new career's first SMS into the Car Lot, the way
 * the old fork's tests/scripts/shop_music.txt went (autotest's waitfng / shopgo), here as a library
 * the game loads with DYLD_INSERT_LIBRARIES.  It reads the game's log (GAMELOG=1) through a pipe on stderr to
 * wait for the FE packages, taps keys with metal_key_tap and jumps onto the Car Lot's marker with the game's
 * hot-position jump.  Log lines "[shoptest] ...": "shop_in" once the shop's garage is up, "music_end" 20 s later.
 * The game's addresses below are the same in the EU and NA builds. */
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#define G_HOTPOS        0x00890140u   /* the hot position the jump goes to (x, y, z) */
#define G_HOTPOS_ANGLE  0x008900d0u   /* u16 */
#define G_HOTPOS_JUMP   0x008900cdu   /* u8: jump to the hot position */
#define G_HOTPOS_VALID  0x008900ceu   /* u8: a hot position is stored */
#define G_FLOW          0x008654a4u   /* 6 in the world */
#define G_SHOPS         0x008383f0u   /* the career's shops, SHOP_SIZE bytes each, the name first */
#define G_NSHOPS        0x008383f4u
#define SHOP_SIZE       0xa0u
#define SHOP_MARKER     0x3cu         /* in a shop: the hash of its marker */
#define G_PATHS         0x0088f298u   /* the world's markers: +0x43c first, +0x438 bytes */
#define DIK_RETURN 0x1C
#define DIK_LEFT   0xCB

static uint8_t **mem;
static long (*frames)(void);
static void (*tap)(unsigned, long);
static int out_fd;
static char seen[64][48];
static int nseen;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

#define M32(a) (*(uint32_t *)(*mem + (uint32_t)(a)))
#define MF(a)  (*(float *)(*mem + (uint32_t)(a)))

static void say(const char *fmt, ...) {
    char line[256]; va_list ap; va_start(ap, fmt);
    int n = snprintf(line, sizeof line, "[shoptest] f=%ld ", frames ? frames() : -1L);
    vsnprintf(line + n, sizeof line - (size_t)n, fmt, ap); va_end(ap);
    strlcat(line, "\n", sizeof line);
    write(out_fd, line, strlen(line));
}
/* the log goes on to the real stderr; "Init Package X.fng" lines are remembered */
static void *tee(void *arg) {
    int in = (int)(intptr_t)arg; char buf[8192], line[1024]; size_t ln = 0; ssize_t n;
    while ((n = read(in, buf, sizeof buf)) > 0) {
        write(out_fd, buf, (size_t)n);
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] != '\n') { if (ln < sizeof line - 1) line[ln++] = buf[i]; continue; }
            line[ln] = 0; ln = 0;
            const char *p = strstr(line, "Init Package ");
            if (!p) continue;
            pthread_mutex_lock(&lock);
            if (nseen < 64) strlcpy(seen[nseen++], p + 13, sizeof seen[0]);
            pthread_mutex_unlock(&lock);
        }
    }
    return NULL;
}
static int was_seen(const char *pkg, int from) {
    pthread_mutex_lock(&lock);
    int k = -1;
    for (int i = from; i < nseen; i++) if (!strcmp(seen[i], pkg)) { k = i; break; }
    pthread_mutex_unlock(&lock);
    return k;
}
static void wait_frames(long n) { long f = frames() + n; while (frames() < f) usleep(5000); }
static int wait_pkg(const char *pkg, long timeout, int from) {
    long end = frames() + timeout;
    for (int k; frames() < end; usleep(10000)) if ((k = was_seen(pkg, from)) >= 0) return k;
    say("timeout waiting for %s", pkg);
    return -1;
}
static uint32_t marker_by_hash(uint32_t h) {
    uint32_t m = M32(G_PATHS + 0x43cu), end = m + M32(G_PATHS + 0x438u);
    for (unsigned k = 0; m && m < end && k < 4096; k++) {
        if (M32(m + 0x30u) == h) return m;
        int16_t sz = *(int16_t *)(*mem + m + 0x42u);
        if (sz <= 0) break;
        m += (uint32_t)sz;
    }
    return 0;
}
static int shop_go(const char *name) {
    uint32_t t = M32(G_SHOPS), n = M32(G_NSHOPS), m = 0;
    for (uint32_t i = 0; t && i < n && i < 256; i++)
        if (!strcasecmp((const char *)*mem + t + i * SHOP_SIZE, name)) { m = marker_by_hash(M32(t + i * SHOP_SIZE + SHOP_MARKER)); break; }
    if (!m) { say("shopgo %s: not found", name); return 0; }
    float x = MF(m + 4u), y = MF(m + 8u), z = MF(m + 0x14u);
    double a = atan2((double)MF(m + 0x10u), (double)MF(m + 0xcu));
    MF(G_HOTPOS) = x; MF(G_HOTPOS + 4) = y; MF(G_HOTPOS + 8) = z + 0.5f;
    *(uint16_t *)(*mem + G_HOTPOS_ANGLE) = (uint16_t)(int)(a / (2.0 * M_PI) * 65536.0);
    (*mem)[G_HOTPOS_VALID] = 1; (*mem)[G_HOTPOS_JUMP] = 1;
    say("shopgo %s: %.1f %.1f %.1f", name, x, y, z);
    return 1;
}
static void *run(void *unused) {
    (void)unused;
    int k = wait_pkg("UI_StartCareer.fng", 20000, 0);
    if (k < 0 || (k = wait_pkg("UI_EngageMessageDialog.fng", 12000, k)) < 0) return NULL;
    wait_frames(300); tap(DIK_RETURN, 8);                        /* SMS: Continue */
    long end = frames() + 3000;
    while (M32(G_FLOW) != 6u && frames() < end) usleep(10000);
    wait_frames(600); say("status world");
    wait_frames(600);
    if (!shop_go("CC_CAR_LOT_1")) return NULL;
    /* On the marker Enter opens the shop's dialog (tapuntil RETURN UI_EngageShopDialog.fng), with Cancel chosen:
     * Left, Enter.  When the garage does not come, the dialog is opened again. */
    int from = k, garage = -1;
    for (int tries = 0; tries < 4 && garage < 0; tries++) {
        int shop = -1;
        for (end = frames() + 2400; frames() < end; ) {
            wait_frames(120);
            if ((shop = was_seen("UI_EngageShopDialog.fng", from)) >= 0) break;
            tap(DIK_RETURN, 8);
        }
        if (shop < 0) { say("timeout waiting for UI_EngageShopDialog.fng"); return NULL; }
        say("shop dialog");
        wait_frames(30); tap(DIK_LEFT, 8);
        wait_frames(30); tap(DIK_RETURN, 8);                     /* Enter Shop */
        say("enter shop");
        for (end = frames() + 600; garage < 0 && frames() < end; usleep(10000)) garage = was_seen("GarageMain.fng", shop);
        from = nseen;
    }
    if (garage < 0) { say("timeout waiting for GarageMain.fng"); return NULL; }
    wait_frames(600); say("status shop_in");
    wait_frames(1200); say("status music_end");
    return NULL;
}
__attribute__((constructor)) static void start(void) {
    mem = dlsym(RTLD_MAIN_ONLY, "g_mem");
    frames = dlsym(RTLD_MAIN_ONLY, "metal_frames");
    tap = dlsym(RTLD_MAIN_ONLY, "metal_key_tap");
    out_fd = dup(2);
    if (!mem || !frames || !tap) { dprintf(out_fd, "[shoptest] the game's symbols are missing\n"); return; }
    int p[2]; pipe(p); dup2(p[1], 2); close(p[1]);
    setvbuf(stderr, NULL, _IOLBF, 0);
    pthread_t t; pthread_create(&t, NULL, tee, (void *)(intptr_t)p[0]); pthread_detach(t);
    pthread_create(&t, NULL, run, NULL); pthread_detach(t);
}
