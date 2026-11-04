/* catchup_unit.c - the career's rubberbanding (runtime/catchup.c) without the
 * game (tests/catchup_unit.sh): an AI driver and its car with the factors the
 * game's 0x4172D0 leaves, outside and in a career race, for each setting.
 *   catchup_unit original|noboost|off */
#define CATCHUP_UNIT
#include "../runtime/catchup.c"
#include <assert.h>
#include <string.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];

static int fails;
#define CHECK(c, ...) do { if (c) printf("PASS "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); putchar('\n'); } while (0)

#define DRV  0x01000000u
#define VEH  0x01100000u

static void commit(uint32_t a, uint32_t n){ for (uint32_t p = a >> 14; p <= (a + n - 1u) >> 14; p++) g_cbits[p >> 3] |= (uint8_t)(1u << (p & 7)); }
/* what 0x4172D0 leaves for a factor m: m in the driver, max(m, 1) in the car */
static void game(float m){ MRF32(DRV + DRV_PACE) = m; MRF32(VEH + VEH_BOOST) = m > 1.f ? m : 1.f; }

int main(int argc, char **argv){
    const char *mode = argc > 1 ? argv[1] : "original";
    g_mem = calloc(1, 0x02000000u); assert(g_mem);
    commit(G_CAREER, CAREER_RACE + 4u); commit(DRV, 0x800u); commit(VEH, 0x800u);
    MR32(DRV + DRV_VEHICLE) = VEH;

    /* not in a career race (free roam, Quick Race): as the game made them */
    MR32(G_CAREER + CAREER_RACE) = 0;
    game(1.3f); catchup_apply(DRV);
    CHECK(MRF32(DRV + DRV_PACE) == 1.3f && MRF32(VEH + VEH_BOOST) == 1.3f, "%s, no career race: the game's factors kept", mode);

    MR32(G_CAREER + CAREER_RACE) = 0x01200000u;
    float behind_pace, behind_car, ahead_pace, ahead_car;
    game(1.3f); catchup_apply(DRV); behind_pace = MRF32(DRV + DRV_PACE); behind_car = MRF32(VEH + VEH_BOOST);
    game(0.6f); catchup_apply(DRV); ahead_pace = MRF32(DRV + DRV_PACE); ahead_car = MRF32(VEH + VEH_BOOST);
    if (!strcmp(mode, "noboost")){
        CHECK(behind_pace == 1.f && behind_car == 1.f, "no boost: an AI behind keeps its own pace (%.2f, car %.2f)", behind_pace, behind_car);
        CHECK(ahead_pace == 0.6f && ahead_car == 1.f, "no boost: an AI ahead still waits (%.2f, car %.2f)", ahead_pace, ahead_car);
    } else if (!strcmp(mode, "off")){
        CHECK(behind_pace == 1.f && behind_car == 1.f, "off: an AI behind keeps its own pace (%.2f, car %.2f)", behind_pace, behind_car);
        CHECK(ahead_pace == 1.f && ahead_car == 1.f, "off: an AI ahead does not wait (%.2f, car %.2f)", ahead_pace, ahead_car);
    } else {
        CHECK(behind_pace == 1.3f && behind_car == 1.3f, "original: an AI behind gains (%.2f, car %.2f)", behind_pace, behind_car);
        CHECK(ahead_pace == 0.6f && ahead_car == 1.f, "original: an AI ahead waits (%.2f, car %.2f)", ahead_pace, ahead_car);
    }
    /* a driver without a car yet: only the driver's factor */
    MR32(DRV + DRV_VEHICLE) = 0;
    game(1.3f); catchup_apply(DRV);
    CHECK(MRF32(DRV + DRV_PACE) == (strcmp(mode, "original") ? 1.f : 1.3f), "%s, no car: no fault, driver %.2f", mode, MRF32(DRV + DRV_PACE));
    return fails != 0;
}
