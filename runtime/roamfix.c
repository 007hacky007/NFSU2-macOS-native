/* roamfix.c -- four of the game's own bugs that free roam with many friends'
 * cars (roam_game.c) runs into: the world map's icons, a load hang, a crash
 * and a freeze in the car loader.  They are the game's bugs, so the fixes are
 * on whether free roam with others is or not; each test aid below brings the
 * game's way back.  tools/gen_v2.sh OVR / OVR_NA have the four functions.
 * European v1.2 addresses (NA in parentheses where it differs).
 */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

uint32_t call_guest(CPU *c, uint32_t fn, int nargs, const uint32_t *args);   /* com.c */
uint32_t gheap_alloc(uint32_t n, int zero);                                   /* gheap.c */
long metal_frames(void);                                                      /* metal.m */
static int test_aid(const char *name){ const char *e = getenv(name); return e && *e == '1'; }

/* --- sub_0050b410: FEng's level sorter, more than 512 objects a package ---
 * The FE renderer draws a package (the package loop 0x536520) by gathering
 * its objects into a list of 1024 (renderer +0x114), sorting it, and handing
 * each object to the level sorter (0x51B850), which hangs it in one of 256
 * depth buckets on an 8-byte node of the array this (cdecl: package, nodes,
 * bytes) gives it: 0x1000 bytes of the package loop's stack, 512 nodes.  An
 * object past them is not drawn.  The game's own packages fit in that; free
 * roam's world map does not (a marker for each player besides the map's own
 * 235 objects, roam_game.c), and lost its shop and event icons to the
 * markers.  Every package gets 1024 nodes instead, as many as its list holds
 * (roam_host.h RH_FE_NODES); the packages are drawn one after another, and
 * 0x50B430 lets go of the nodes after each. */
#define FE_NODES        1024u
#define G_FE_NODES      GA(0x00838494u)   /* the level sorter's nodes */
#define G_FE_NODES_N    GA(0x0083848cu)   /* ...how many */
void sub_0050b410_orig(CPU *c);
void sub_0050b410(CPU *c){
    static uint32_t nodes; static int game = -1;
    if (game < 0) game = test_aid("NFSU2_TEST_FE_NODES_512");
    sub_0050b410_orig(c);
    if (game) return;
    if (!nodes){
        nodes = gheap_alloc(FE_NODES * 8u, 1);
        fprintf(stderr, "[fe] the level sorter draws up to %u objects a package (the game: %u)\n", nodes ? FE_NODES : MR32(G_FE_NODES_N), MR32(G_FE_NODES_N));
    }
    if (nodes){ MR32(G_FE_NODES) = nodes; MR32(G_FE_NODES_N) = FE_NODES; }
}

/* --- sub_0061c610 (NA 0x61C600): the car loader reads a car type's PARTS_ANIMATIONS.BIN ---
 * The CarLoader (0x8A3288) has one read under way at a time: a step that
 * starts one (a model or texture pack, a car's textures) sets its busy word
 * (+0x14, 0x8A329C), the read's callback clears it and runs the next step,
 * and the frame's service (0x63BCE0) steps only while it is clear.  This one
 * (thiscall loader, the car type's hash, ret 4) sets busy and starts its read
 * without looking.  The step calls it only in the front end, after the car
 * before it is done; a cover shoot's start calls it at any time (the player's
 * car type), and in free roam a friend's car is often loading then.  Its
 * callback then cleared busy and stepped while the friend's read was still
 * under way, so the loader ran two reads at once and stepped a car on before
 * its pack was in, and busy could stay set for good.  The next Load that
 * found the rides pool full (0x63AE80: it waits for busy to clear, then
 * purges) waited forever, holding the GIL: the game froze with the sound
 * looping.  Here a read under way finishes first, the way that Load waits
 * (the reads serviced, 0x57EF70 (NA 0x57EF60), until busy is clear).
 * NFSU2_TEST_LOADER_OVERLAP=1 (test aid): the game's way. */
#define CARLOADER_BUSY  GA(0x008a329cu)
#define CARTYPEINFO     GA(0x008a1cccu)   /* -> 46 x 0x890 bytes: +0 the name, +0xD0 the hash */
#define FN_READS_SERVICE GA(0x0057ef70u)
void sub_0061c610_orig(CPU *c);
void sub_0061c610(CPU *c){
    static int overlap = -1;
    if (overlap < 0) overlap = test_aid("NFSU2_TEST_LOADER_OVERLAP");
    if (MR32(CARLOADER_BUSY) && overlap)
        fprintf(stderr, "[loader] f=%ld TEST: part animations read with the car loader's read under way\n", metal_frames());
    if (MR32(CARLOADER_BUSY) && !overlap){
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        while (MR32(CARLOADER_BUSY)) call_guest(c, FN_READS_SERVICE, 0, 0);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        uint32_t h = MR32(c->esp + 4u), t = MR32(CARTYPEINFO);
        char nm[16] = "?";
        for (uint32_t k = 0; t && k < 46u; k++)
            if (MR32(t + k * 0x890u + 0xd0u) == h){
                for (int i = 0; i < 15 && MR8(t + k * 0x890u + (uint32_t)i); i++){ nm[i] = (char)MR8(t + k * 0x890u + (uint32_t)i); nm[i + 1] = 0; }
                break; }
        fprintf(stderr, "[loader] f=%ld %s's part animations waited %.0f ms for the car loader's read under way\n",
                metal_frames(), nm, (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6);
    }
    sub_0061c610_orig(c);
}

/* --- sub_00631e30 (NA 0x631E20) (list, ride, ...): a ride's texture names, cdecl ---
 * A ride's textures by name hash, into two lists of 69 (list +0 and +0x114,
 * their counts at +0x228 and +0x22C): for the car loader's Load (0x63AE80,
 * the loader's copy of the ride), which takes a reference to each name on
 * the loader's list of them and lets them go when the ride is unloaded, and
 * for a car's render info.  Every add skips a name the list has; a full
 * list's add was meant to add nothing but returns the count, so from the 70th
 * different name on every add doubles the count.  A ride with many different
 * decals gets there: up to 56 (7 places of 8, DECAL_HOOD_TEX0 ..
 * DECAL_RIGHT_QUARTER_TEX7) after its other textures (a 350Z with shop rims:
 * 25).  With 56, the count was 69 x 2^12 = 282,624 and Load took references
 * for that many "names" read from past the list, writing past it, and froze;
 * with a few too many it corrupts less at once, but the references written
 * past the list are let go twice or never, and the loader's list breaks (a
 * later load walked it forever: in free roam after an hour of friends' cars
 * coming and going, any player's car with more than about 44 different
 * decals).  Here a run without the ride's decals (the 7 places' shapes, ride
 * +0x660, off for it) counts the other textures, and the decals that would
 * not fit are off the ride while the list is made (the first ones, place by
 * place, stay), then back on it: the ride keeps them, its list has no names
 * for them.  It keeps locals in its arguments' places, so they are put back
 * for the second run.  NFSU2_TEST_TEXLIST_FULL=1 (test aid): the game's way. */
#define TEXLIST_MAX     0x45u
#define RIDE_DECALZONES 0x660u        /* RideInfo: the 7 decal places' shapes (DECAL_HOOD ..), a part each */
#define RIDE_DECALS     0x714u        /* RideInfo: each place's 8 decals (+0x20 a place), a part each */
void sub_00631e30_orig(CPU *c);
void sub_00631e30(CPU *c){
    static int full = -1;
    if (full < 0) full = test_aid("NFSU2_TEST_TEXLIST_FULL");
    uint32_t esp0 = c->esp, list = MR32(esp0 + 4u), ride = MR32(esp0 + 8u);
    uint32_t seen[56], off[56], offp[56]; int nd = 0, noff = 0;
    for (uint32_t z = 0; ride && z < 7u; z++){
        if (!MR32(ride + RIDE_DECALZONES + 4u * z)) continue;
        for (uint32_t i = 0; i < 8u; i++){
            uint32_t p = MR32(ride + RIDE_DECALS + 0x20u * z + 4u * i), k = 0;
            while (p && k < (uint32_t)nd && seen[k] != p) k++;
            if (p && k == (uint32_t)nd) seen[nd++] = p;
        }
    }
    if (full || !nd){ sub_00631e30_orig(c); return; }
    uint32_t arg[4], zone[7];
    for (uint32_t i = 0; i < 4u; i++) arg[i] = MR32(esp0 + 4u + 4u * i);
    for (uint32_t z = 0; z < 7u; z++){ zone[z] = MR32(ride + RIDE_DECALZONES + 4u * z); MR32(ride + RIDE_DECALZONES + 4u * z) = 0; }
    sub_00631e30_orig(c);
    for (uint32_t z = 0; z < 7u; z++) MR32(ride + RIDE_DECALZONES + 4u * z) = zone[z];
    uint32_t others = MR32(list + 0x228u);
    int room = others < TEXLIST_MAX ? (int)(TEXLIST_MAX - others) : 0, kept = 0;
    if (nd > room){
        for (uint32_t z = 0; z < 7u; z++){
            if (!zone[z]) continue;
            for (uint32_t i = 0; i < 8u; i++){
                uint32_t a = ride + RIDE_DECALS + 0x20u * z + 4u * i, p = MR32(a), k = 0;
                if (!p) continue;
                while (k < (uint32_t)kept && seen[k] != p) k++;
                if (k < (uint32_t)kept) continue;                    /* a decal already kept: no name more */
                if (kept < room) seen[kept++] = p;
                else { off[noff] = a; offp[noff++] = p; MR32(a) = 0; }
            }
        }
        fprintf(stderr, "[textures] f=%ld a ride with %d different decals and %u other textures: %d decal(s) left out of "
                "its texture list (it holds %u)\n", metal_frames(), nd, others, nd - kept, TEXLIST_MAX);
    }
    c->esp = esp0;
    for (uint32_t i = 0; i < 4u; i++) MR32(esp0 + 4u + 4u * i) = arg[i];
    sub_00631e30_orig(c);
    for (int i = 0; i < noff; i++) MR32(off[i]) = offp[i];
    uint32_t n1 = MR32(list + 0x228u), n2 = MR32(list + 0x22cu);
    if (n1 > TEXLIST_MAX || n2 > TEXLIST_MAX){
        fprintf(stderr, "[textures] f=%ld a ride's texture lists still count %u and %u: cut to %u\n", metal_frames(), n1, n2, TEXLIST_MAX);
        if (n1 > TEXLIST_MAX) MR32(list + 0x228u) = TEXLIST_MAX;
        if (n2 > TEXLIST_MAX) MR32(list + 0x22cu) = TEXLIST_MAX;
    }
}

/* --- sub_00639f30 (NA 0x639F20) (texture set): a ride's textures let go, thiscall, ret 4 ---
 * The car loader keeps a reference for each texture on a loaded ride's list
 * (its texture set: the list +0x31C, the count +0x318) on the texture's name
 * record (the word at +0xC), and a texture is unloaded when its count gets to
 * 0.  This gives back the set's references, unloads the textures that are
 * then at 0, and only then empties the list and returns 1; when none got to 0
 * (each texture is on another ride's list too: a car type shown twice) it
 * returns 0 with the references given back and the list as it was.  The purge
 * (0x63A1C0 (NA 0x63A1B0) with phase 1: a load step found no room in the Cars
 * pool) calls it for each ride it holds, the ones on cars too, until one
 * returns 1.  The rides before it kept their lists without references: their
 * textures were unloaded when the other ride went, with the car still showing
 * its ride, whose render info then drew with freed textures ("memory access
 * out of bounds" in free roam with friends' cars coming and going), and when
 * the ride itself went, its list gave the references back a second time.
 * Here a purge's call that unloaded nothing takes them again; a ride's own
 * unload lets them go as before.  NFSU2_TEST_TEXREFS_DROP=1 (test aid): the
 * game's way. */
#define PURGE_RET       GA(0x0063a233u)   /* the purge's call (phase 1, 0x63A22E (NA 0x63A21E)) returns here */
#define TS_COUNT        0x318u
#define TS_NAMES        0x31cu
void sub_00639f30_orig(CPU *c);
void sub_00639f30(CPU *c){
    static int drop = -1; static long kept;
    if (drop < 0) drop = test_aid("NFSU2_TEST_TEXREFS_DROP");
    uint32_t ret = MR32(c->esp), ts = MR32(c->esp + 4u);
    sub_00639f30_orig(c);
    if (c->eax || ret != PURGE_RET || !ts || drop) return;
    uint32_t n = MR32(ts + TS_COUNT);
    if (n > TEXLIST_MAX) n = TEXLIST_MAX;
    if (!n) return;
    for (uint32_t i = 0; i < n; i++){
        uint32_t r = MR32(ts + TS_NAMES + 4u * i);
        if (r) MR16(r + 0xcu) = (uint16_t)(MR16(r + 0xcu) + 1u);
    }
    if (++kept == 1 || kept == 10 || kept == 100 || kept % 1000 == 0)
        fprintf(stderr, "[textures] f=%ld the car loader's purge gave back a ride's %u texture references and unloaded none: "
                "taken again (%ld times)\n", metal_frames(), n, kept);
}
