/* hiddenraces_unit.c - the career's hidden races on the map (runtime/hiddenraces.c)
 * without the game (tests/hiddenraces_unit.sh): career tables as GlobalB's are
 * laid out, the setting off and on, a stage's caps (1 to 4 raised to 8, -1 and 8
 * or more kept), the change made once per loaded table and again for a new one.
 *   hiddenraces_unit off|on */
#include "../runtime/hiddenraces.c"
#include <assert.h>
#include <string.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];

static int fails;
#define CHECK(c, ...) do { if (c) printf("PASS "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); putchar('\n'); } while (0)

#define RACES   0x01000000u
#define RACES2  0x01100000u
#define STAGES  0x01200000u
#define NR      224u
#define NS      6u

static void commit(uint32_t a, uint32_t n){ for (uint32_t p = a >> 14; p <= (a + n - 1u) >> 14; p++) g_cbits[p >> 3] |= (uint8_t)(1u << (p & 7)); }
static int hidden(uint32_t races){ int n = 0; for (uint32_t i = 0; i < NR; i++) n += MR8(races + i * RACE_SZ + R_HIDDEN) != 0; return n; }
static void tables(uint32_t races){
    for (uint32_t i = 0; i < NR; i++) MR8(races + i * RACE_SZ + R_HIDDEN) = i % 6u == 3u && i < 6u * 33u;   /* 33 hidden */
    MR32(G_RACES) = races; MR32(G_NRACES) = NR;
}

int main(int argc, char **argv){
    int on = argc > 1 && !strcmp(argv[1], "on");
    g_mem = calloc(1, 0x02000000u); assert(g_mem);
    commit(RACES, NR * RACE_SZ); commit(RACES2, NR * RACE_SZ); commit(STAGES, NS * STAGE_SZ);
    /* before GlobalB is loaded: nothing to do */
    hiddenraces_frame();
    CHECK(g_done == 0, "no tables yet: nothing changed");
    tables(RACES);
    static const int8_t caps[NS][5] = { {1,1,0,0,0}, {2,2,1,1,0}, {3,3,2,2,1}, {4,4,2,3,2}, {4,4,3,3,3}, {-1,8,9,4,1} };
    for (uint32_t s = 0; s < NS; s++) for (uint32_t k = 0; k < 5u; k++) MR8(STAGES + s * STAGE_SZ + S_CAPS + k) = (uint8_t)caps[s][k];
    MR32(G_STAGES) = STAGES; MR32(G_NSTAGES) = NS;
    hiddenraces_frame();
    int8_t got[NS][5];
    for (uint32_t s = 0; s < NS; s++) for (uint32_t k = 0; k < 5u; k++) got[s][k] = (int8_t)MR8(STAGES + s * STAGE_SZ + S_CAPS + k);
    if (!on){
        CHECK(hidden(RACES) == 33, "off: the 33 hidden races stay hidden (%d)", hidden(RACES));
        CHECK(!memcmp(got, caps, sizeof caps), "off: the stages' caps as the game has them");
    } else {
        CHECK(hidden(RACES) == 0, "on: no race hidden (%d left)", hidden(RACES));
        int ok = 1;
        for (uint32_t s = 0; s < NS; s++) for (uint32_t k = 0; k < 5u; k++){
            int8_t want = caps[s][k] >= 0 && caps[s][k] < CAP ? CAP : caps[s][k];
            ok &= got[s][k] == want;
        }
        CHECK(ok, "on: every cap of 0 to 7 raised to 8, -1 (no cap) and 8 or more kept");
        /* once per table: a race the game hides again later (none does) is left */
        MR8(RACES + 5u * RACE_SZ + R_HIDDEN) = 1;
        hiddenraces_frame();
        CHECK(hidden(RACES) == 1, "on: the same table is changed once");
        /* GlobalB loaded again somewhere else: changed again */
        tables(RACES2);
        hiddenraces_frame();
        CHECK(hidden(RACES2) == 0 && g_done == RACES2, "on: a new table is changed too");
        /* a table that is not all there yet is left alone */
        MR32(G_RACES) = 0x01f00000u; MR32(G_NRACES) = NR;
        hiddenraces_frame();
        CHECK(g_done == RACES2, "on: a table out of committed memory is not touched");
    }
    printf(fails ? "hiddenraces_unit %s: %d FAILED\n" : "hiddenraces_unit %s: all passed\n", on ? "on" : "off", fails);
    return fails != 0;
}
