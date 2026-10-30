/* regional.c -- both regions' cars when the game folder has all of them.
 *
 * The European release has the Vauxhall Corsa and the Peugeot 106
 * (CARS\CORSA, CARS\PEUGOT106), the North American one the Honda Civic and
 * the Acura RSX (CARS\CIVIC, CARS\RSX).  CarTypeInfo lists all four (types 7,
 * 6, 5 and 18, among the 31 player cars, with their names in every language's
 * text), but the game keeps two of them off its lists by its region
 * ([0x7fa73c], see region_install in overrides.c):
 *  - 0x5022c0, whether the region sells a car type, for the car lot
 *    (UICareerCarLot::BuildCarList, 0x4df9c0, at 0x4dfa83) and every other
 *    car select (UIQRCarSelect::BuildCarList, 0x4e22e0, at 0x4e2374: Quick
 *    Race, Customize, LAN and Online): no for a type in the region's table,
 *    region 0's {7, 6} at 0x7f7c48, the others' {5, 18} at 0x7f7c50;
 *  - 0x4feaf0, the AI racers' cars: a random one rated near the player's car
 *    from the region's 26 types (region 0's at 0x7f6da4 with 5 and 18 last,
 *    the others' at 0x7f6dc0 with 7 and 6 in their place; 3 SUVs at 0x7f6ddc
 *    when the player drives an SUV).
 * A race with a car whose folder is missing hangs on "Loading", so this only
 * acts when all four folders are there (a folder made from both releases).
 * Then neither table holds a type (-1), and each AI list is 28 long, the
 * other region's two cars in the two bytes of padding after it (read by
 * nothing else; the hook at 0x4febad, where both lists' paths meet, makes
 * the length 28).  The same as NFSU2 Extra Options' UnlockRegionalCars
 * (ExOptsTeam/NFSU2ExOpts, ExtraOptionsStuff.h).
 *
 * NFSU2_ALL_CARS=0 keeps the region's own cars only.  The tables are at the
 * same addresses in the European and the North American build; GA() keeps
 * them in step anyway.
 * Ported from th0mk's nfsu2-web runtime/regional.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>

#define LOCKED          GA(0x007f7c48u)   /* region 0: {7, 6}; the others, +8: {5, 18} */
#define AI_CARS_R0      GA(0x007f6da4u)   /* region 0's AI car types, a byte each */
#define AI_CARS_OTHER   GA(0x007f6dc0u)   /* the other regions' */
#define AI_CARS_N       26u
#define T_CIVIC         5u
#define T_PEUGOT106     6u
#define T_CORSA         7u
#define T_RSX           18u

static int g_on;

static int ai_list_is(uint32_t a, uint8_t last0, uint8_t last1){
    return MR8(a + AI_CARS_N - 2u) == last0 && MR8(a + AI_CARS_N - 1u) == last1
        && MR16(a + AI_CARS_N) == 0u;
}

void regional_install(void){
    int fileio_game_file_exists(const char *win);
    const char *e = getenv("NFSU2_ALL_CARS");
    if (e && *e == '0') return;
    if (!fileio_game_file_exists("CARS\\CORSA\\GEOMETRY.BIN") || !fileio_game_file_exists("CARS\\PEUGOT106\\GEOMETRY.BIN")
        || !fileio_game_file_exists("CARS\\CIVIC\\GEOMETRY.BIN") || !fileio_game_file_exists("CARS\\RSX\\GEOMETRY.BIN"))
        return;                                   /* one region's data: its own cars only */
    /* only on the data this was made for */
    if (MR32(LOCKED) != T_CORSA || MR32(LOCKED + 4u) != T_PEUGOT106
        || MR32(LOCKED + 8u) != T_CIVIC || MR32(LOCKED + 12u) != T_RSX
        || !ai_list_is(AI_CARS_R0, T_CIVIC, T_RSX) || !ai_list_is(AI_CARS_OTHER, T_CORSA, T_PEUGOT106)){
        fprintf(stderr, "cars: the exe's region tables are not the ones expected, left as they are\n");
        return;
    }
    for (uint32_t i = 0; i < 4u; i++) MR32(LOCKED + 4u * i) = 0xffffffffu;
    MR8(AI_CARS_R0 + AI_CARS_N) = T_CORSA;
    MR8(AI_CARS_R0 + AI_CARS_N + 1u) = T_PEUGOT106;
    MR8(AI_CARS_OTHER + AI_CARS_N) = T_CIVIC;
    MR8(AI_CARS_OTHER + AI_CARS_N + 1u) = T_RSX;
    g_on = 1;
    fprintf(stderr, "cars: the game folder has both regions' cars, all four are for sale and race\n");
}

/* Called from guest_hook (debug.c); tools/gen_v2.sh lifts the hook site. */
int regional_hook(CPU *c, uint32_t ip){
    if (ip != GA(0x004febadu)) return 0;     /* mov eax, [esp+0x34]: esi the list, ebp its length */
    if (g_on && (c->esi == AI_CARS_R0 || c->esi == AI_CARS_OTHER) && c->ebp == AI_CARS_N){
        static int told;
        if (!told++) fprintf(stderr, "cars: AI racers pick from %u cars\n", AI_CARS_N + 2u);
        c->ebp = AI_CARS_N + 2u;
    }
    return 1;
}
