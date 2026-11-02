/* uniques_unit.c - the unique visual parts after Caleb (runtime/uniques.c)
 * without the game (tests/uniques_unit.sh): the career's events as the game
 * lays them out, the game's own answer stood in for, the setting off and on.
 *   uniques_unit off|on */
#include "../runtime/uniques.c"
#include <assert.h>
#include <string.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];

static int fails;
#define CHECK(c, ...) do { if (c) printf("PASS "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); putchar('\n'); } while (0)

#define S5INFO  0x01000000u
#define PART    0x01100000u
#define STACK   0x01200000u
#define CALEB   0x1234abcdu             /* stage 5's final event's hash */

static void commit(uint32_t a, uint32_t n){ for (uint32_t p = a >> 14; p <= (a + n - 1u) >> 14; p++) g_cbits[p >> 3] |= (uint8_t)(1u << (p & 7)); }
static uint32_t g_answer;               /* the game's own answer (0x515500) */
void sub_00515500_orig(CPU *c){ c->eax = g_answer; }

static int ask(uint32_t filter, int level, int game){
    CPU c; memset(&c, 0, sizeof c);
    c.esp = STACK;
    MR32(STACK + 4u) = filter; MR32(STACK + 8u) = 6u; MR32(STACK + 12u) = PART;
    MR8(PART + P_LEVEL) = (uint8_t)(level << 5);
    g_answer = (uint32_t)game | 0x12345600u;
    sub_00515500(&c);
    return (int)(c.eax & 0xffu);
}
static void caleb(int won){
    MR32(G_CAREER + C_NEVENTS) = 3u;
    for (uint32_t i = 0; i < 3u; i++){ MR32(G_CAREER + C_EVENTS + 8u * i) = 0x1000u + i; MR8(G_CAREER + C_EVENTS + 8u * i + 6u) = 1u; }
    MR32(G_CAREER + C_EVENTS + 16u) = CALEB; MR8(G_CAREER + C_EVENTS + 16u + 6u) = (uint8_t)won;
}

int main(int argc, char **argv){
    int on = argc > 1 && !strcmp(argv[1], "on");
    g_mem = calloc(1, 0x02000000u); assert(g_mem);
    commit(G_CAREER, C_EVENTS + 8u * C_MAXEVENTS); commit(G_S5_INFO, 4u); commit(S5INFO, 0x100u); commit(PART, 16u); commit(STACK - 64u, 128u);
    MR32(G_S5_INFO) = S5INFO; MR32(S5INFO + SI_FINAL) = CALEB;
    caleb(0);
    CHECK(!ask(F_STAGE, LEVEL_UNIQUE, 0), "Caleb not beaten: a unique part stays locked in the shops");
    CHECK(ask(F_STAGE, LEVEL_UNIQUE, 1), "the game's own yes (the car owns it) is kept");
    caleb(1);
    if (!on){
        CHECK(!ask(F_STAGE, LEVEL_UNIQUE, 0), "off: after Caleb a unique part stays the game's (locked)");
    } else {
        CHECK(ask(F_STAGE, LEVEL_UNIQUE, 0), "on: after Caleb a unique part is in the shops");
        CHECK(!ask(2u, LEVEL_UNIQUE, 0), "on: the garage's check (no stage bit) is left alone");
        CHECK(!ask(F_STAGE, 3, 0), "on: a part of another level is left alone");
    }
    printf(fails ? "uniques_unit %s: %d FAILED\n" : "uniques_unit %s: all passed\n", on ? "on" : "off", fails);
    return fails != 0;
}
