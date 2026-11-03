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
 * acts when all four folders are there (a folder made from both releases, or
 * the launcher's Both Releases' Cars data mod: RKBDI's files of the four).
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
#include <strings.h>

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
    int fileio_game_can_read(const char *win);
    const char *e = getenv("NFSU2_ALL_CARS");
    if (e && *e == '0') return;
    if (!fileio_game_can_read("CARS\\CORSA\\GEOMETRY.BIN") || !fileio_game_can_read("CARS\\PEUGOT106\\GEOMETRY.BIN")
        || !fileio_game_can_read("CARS\\CIVIC\\GEOMETRY.BIN") || !fileio_game_can_read("CARS\\RSX\\GEOMETRY.BIN"))
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
    fprintf(stderr, "cars: the game has both regions' cars, all four are for sale and race\n");
}

/* Called from guest_hook (debug.c); tools/gen_v2.sh lifts the hook site. */
int regional_hook(CPU *c, uint32_t ip){
    if (ip != HOOK_SITE(0x004febadu)) return 0;     /* mov eax, [esp+0x34]: esi the list, ebp its length */
    if (g_on && (c->esi == AI_CARS_R0 || c->esi == AI_CARS_OTHER) && c->ebp == AI_CARS_N){
        static int told;
        if (!told++) fprintf(stderr, "cars: AI racers pick from %u cars\n", AI_CARS_N + 2u);
        c->ebp = AI_CARS_N + 2u;
    }
    return 1;
}

/* --- other players' cars this game folder does not have ---------------------
 * A car of a type CarTypeInfo lists but whose files are not here (the other
 * region's two cars on one region's data, a mod's car on one side only)
 * cannot be loaded: the car loader's read of its pack never comes back, its
 * busy word (0x8A329C) stays set, and the race's "Loading" or the world's
 * unload (0x63B080) waits for it for good.  Another player's car of such a
 * type is shown as the other region's car in its place, as the game's own
 * region tables pair them (the AI lists have the Corsa where the other
 * region has the Civic, the 106 for the RSX), else a type of the same name
 * prefix (an add-on car), else the Peugeot 206 (type 0); with stock parts,
 * since the sender's parts are its type's.  Free roam's friends (roam_game.c
 * build_ride) and the LAN and online races' cars (below) both. */
#define CARTYPES        GA(0x008a1cccu)   /* CarTypeInfo[]: 0x890 bytes, +0 the name */
#define N_CARTYPES      46u
static void type_name(uint32_t type, char *n, int cap){
    uint32_t t = MR32(CARTYPES);
    int i = 0;
    if (t && type < N_CARTYPES)
        for (; i < cap - 1 && MR8(t + type * 0x890u + (uint32_t)i) >= 0x20 && MR8(t + type * 0x890u + (uint32_t)i) < 0x7f; i++)
            n[i] = (char)MR8(t + type * 0x890u + (uint32_t)i);
    n[i] = 0;
}
int regional_type_has_files(uint32_t type){
    static int8_t seen[N_CARTYPES];               /* 0 not looked, 1 there, -1 not there */
    int fileio_game_can_read(const char *win);
    if (type >= N_CARTYPES) return 0;
    if (!seen[type]){
        char n[20], p[48]; type_name(type, n, sizeof n);
        snprintf(p, sizeof p, "CARS\\%s\\GEOMETRY.BIN", n);
        seen[type] = n[0] && fileio_game_can_read(p) ? 1 : -1;
    }
    return seen[type] > 0;
}
uint32_t regional_stand_in(const char *name){
    static const char *const other[][2] = { { "CIVIC", "CORSA" }, { "RSX", "PEUGOT106" } };
    char n[20];
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++)
            if (!strcasecmp(name, other[i][j]))
                for (uint32_t t = 0; t < N_CARTYPES; t++){
                    type_name(t, n, sizeof n);
                    if (!strcasecmp(n, other[i][!j]) && regional_type_has_files(t)) return t;
                }
    for (uint32_t t = 0; t < N_CARTYPES; t++){
        type_name(t, n, sizeof n);
        if (n[0] && !strncasecmp(n, name, 4) && regional_type_has_files(t)) return t;
    }
    return 0;
}

/* sub_005f04e0 (thiscall, ride, bit reader, skin; ret 0xC): a LAN (and
 * online) race's car description into a RideInfo, the game's decoder: the
 * type (0x610280, RideInfo::Init), the skin (0x61C290), the performance
 * parts (+0x318 ten flags; +0x340 68 bytes, set from 9 bytes of bits by
 * 0x5AC4C0 on +0x2F0), the tuning (+0x398, 41 bytes), the physics pass
 * (0x5B4FD0 on +0x10), then the parts by their index in the CarPartDB, or
 * stock ones (0x637050).  A type with no files here: the ride is made again
 * the same way as the stand-in type, with the same performance parts and
 * tuning, and stock parts.  NFSU2_TEST_RACE_CARS_AS_SENT=1 (test aid): the
 * game's way. */
#define FN_RIDE_INIT    GA(0x00610280u)   /* thiscall ride (type, skin, 0, 0) */
#define FN_RIDE_SKINS   GA(0x0061c290u)   /* thiscall ride (skin) */
#define FN_PERF_SET     GA(0x005ac4c0u)   /* thiscall ride +0x2F0 (perf*): {u32 0, u8 0, 9 bytes of bits} */
#define FN_PHYSICS      GA(0x005b4fd0u)   /* thiscall ride +0x10 (1, 1, 1) */
#define FN_RIDE_STOCK   GA(0x00637050u)   /* thiscall ride (0): stock parts */
static uint32_t this_call(CPU *c, uint32_t fn, uint32_t ecx, int n, const uint32_t *arg){
    void dispatch_indirect(CPU *c, uint32_t addr);
    CPU save = *c;
    c->esp = (c->esp - 512u) & ~15u;
    for (int i = n - 1; i >= 0; i--) PUSH32(arg[i]);
    c->ecx = ecx;
    PUSH32(0xdeadbeefu);
    dispatch_indirect(c, fn);
    uint32_t r = c->eax;
    *c = save;
    return r;
}
void sub_005f04e0_orig(CPU *c);
void sub_005f04e0(CPU *c){
    long metal_frames(void);
    static int as_sent = -1;
    if (as_sent < 0){ const char *e = getenv("NFSU2_TEST_RACE_CARS_AS_SENT"); as_sent = e && *e == '1'; }
    uint32_t ride = MR32(c->esp + 4u), skin = MR32(c->esp + 12u);
    sub_005f04e0_orig(c);
    uint32_t type = MR32(ride);
    char was[20], now[20]; type_name(type, was, sizeof was);
    if (regional_type_has_files(type)) return;
    if (as_sent){
        fprintf(stderr, "[cars] f=%ld TEST: another player's %s, not in this game folder, loaded as sent\n", metal_frames(), was);
        return;
    }
    uint32_t eax = c->eax;
    uint32_t flags[10]; uint8_t tune[41], bits[9] = {0};
    for (int i = 0; i < 10; i++) flags[i] = MR32(ride + 0x318u + 4u * (uint32_t)i);
    for (int i = 0; i < 68; i++) if (MR8(ride + 0x340u + (uint32_t)i)) bits[i >> 3] |= (uint8_t)(0x80u >> (i & 7));
    for (int i = 0; i < 41; i++) tune[i] = MR8(ride + 0x398u + (uint32_t)i);
    uint32_t to = regional_stand_in(was);
    type_name(to, now, sizeof now);
    this_call(c, FN_RIDE_INIT, ride, 4, (uint32_t[]){ to, skin, 0, 0 });
    this_call(c, FN_RIDE_SKINS, ride, 1, (uint32_t[]){ skin });
    for (int i = 0; i < 10; i++) MR32(ride + 0x318u + 4u * (uint32_t)i) = flags[i];
    /* the perf parts' bits, as the decoder's own (a 0x5A6310 record on its stack) */
    uint32_t pr = (c->esp - 64u) & ~15u;
    MR32(pr) = 0; MR8(pr + 4u) = 0;
    for (int i = 0; i < 9; i++) MR8(pr + 5u + (uint32_t)i) = bits[i];
    this_call(c, FN_PERF_SET, ride + 0x2f0u, 1, (uint32_t[]){ pr });
    for (int i = 0; i < 41; i++) MR8(ride + 0x398u + (uint32_t)i) = tune[i];
    this_call(c, FN_PHYSICS, ride + 0x10u, 3, (uint32_t[]){ 1, 1, 1 });
    this_call(c, FN_RIDE_STOCK, ride, 1, (uint32_t[]){ 0 });
    c->eax = eax;
    fprintf(stderr, "[cars] f=%ld another player's %s, not in this game folder, is shown as a stock %s (type %u)\n",
            metal_frames(), was, now, to);
}
