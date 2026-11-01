/* gamefix.c -- fixes for bugs of the game itself, and two native fast paths
 * for its loaders.
 *
 *   sub_00559ca0  the Performance Shop's package screen: a field its
 *                 constructor never writes (the shop locked up after Nitrous)
 *   sub_004e8b70  the memory card screen's profile name, never written (a
 *                 cover shoot whose save failed renamed the profile)
 *   sub_004ff3b0  a first profile's name box starts with the launcher's
 *                 Player name instead of NAME (NFSU2_NEW_PROFILE_NAME)
 *   sub_004df9c0  the car lot's list: a stock car of no car type (the game
 *                 ended as the car lot opened on a damaged profile)
 *   sub_00483e40  a positional sound's source removed: its voice requests
 *                 recounted (a crash when every voice was busy)
 *   sub_00574680  JDLZ blocks unpacked natively (loading)
 *   sub_0061b990  NewGetCarPart answers kept (car and part screens, loading)
 *
 * Every address is the European v1.2 one (GA() and build_na.h map them for
 * the North American build); each function was compared instruction by
 * instruction in both executables, and the data they read is at the same
 * address in both.
 *
 * NFSU2_FIXTEST=<test>@<frame>[,...] (test aid): at that Present, set up the
 * state a fix is for and run the game's code over it, so the fix can be seen
 * acting in a short scripted run:
 *   badstock   player 0's first stock car gets a car type no car has, and the
 *              stock-car check of sub_004df9c0 runs (the "[cars]" lines)
 *   shopstale  from then on every Performance Shop package screen starts with
 *              the stale 1 in its field +0xC0 that locked the shop up
 *   badvoices  the next 3 positional sound removals find the voice request
 *              count 3 too high, as a removal left it in the game
 * NFSU2_SHOPFIX=0 (test aid): the package screen is left as the game makes it.
 * NFSU2_TEST_MC_STALE=1 (test aid): the memory card screen's name holds 0xEF
 * bytes, as a stale heap block left it (tests/scripts/career_cover_name.txt).
 *
 * Ported from th0mk's nfsu2-web runtime/overrides.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

long metal_frames(void);

static uint64_t g_jdlz_n, g_jdlz_bytes, g_jdlz_lifted, g_jdlz_diff;
static uint64_t g_pm_hits, g_pm_calls, g_pm_clears, g_pm_diff;
static uint64_t g_snd_recount, g_snd_fixed, g_shop_init, g_lot_fixed;
static int g_shop_stale;                 /* NFSU2_FIXTEST=shopstale */
static int g_snd_stale;                  /* NFSU2_FIXTEST=badvoices */

/* --- UI_ChoosePerformancePackage: a field the game never initialises ------
 * The Performance Shop's package screen (vtable 0x79D2D8, 0x250 bytes from
 * operator new, constructor sub_00559ca0) never writes its field +0xC0, but
 * its refresh method sub_005620e0 -- first called from inside the
 * constructor -- reads it: -10 or 1 there means "close the parts list and
 * open it again".  The field holds whatever the heap block held before
 * (0xEEEEEEEE in a fresh block; 1 after some heap histories: movies played,
 * 60 fps or a slow frame rate).  With 1, entering a category whose carousel
 * starts at "Choose Individual Parts" (Nitrous Oxide) opens
 * UI_BuyPerformanceParts twice; the first one is popped at once, the package
 * screen stays hidden with control mask 0 under the second, and after ESC no
 * screen takes input: the shop is dead until the game is quit.  Nothing else
 * in the game reads or writes the field, so the screen is given the value of
 * a fresh block before its constructor runs: the parts list opens once, both
 * screens keep input, and ESC goes back to the categories. */
void sub_00559ca0_orig(CPU *c);
void sub_00559ca0(CPU *c){
    static int on = -1;
    if (on < 0){ const char *e = getenv("NFSU2_SHOPFIX"); on = !(e && *e == '0'); }
    uint32_t self = c->ecx;
    if (self && mem_is_committed(self) && mem_is_committed(self + 0xc3u)){
        if (g_shop_stale) MR32(self + 0xc0u) = 1u;
        uint32_t was = MR32(self + 0xc0u);
        if (!on){
            fprintf(stderr, "[shop] f=%ld Performance Shop package screen 0x%08x: field +0xC0 is 0x%08x, left as it is (NFSU2_SHOPFIX=0)\n",
                    metal_frames(), self, was);
            sub_00559ca0_orig(c); return; }
        if (g_shop_init++ < 4)
            fprintf(stderr, "[shop] f=%ld Performance Shop package screen 0x%08x: field +0xC0 was 0x%08x%s, set to 0xEEEEEEEE\n",
                    metal_frames(), self, was, was == 1u || was == 0xfffffff6u ? " (would lock the shop up)" : "");
        MR32(self + 0xc0u) = 0xEEEEEEEEu;
    }
    sub_00559ca0_orig(c);
}

/* --- sub_004e8b70: the memory card screen's profile name, never initialised ---
 * The memory card screen (MC_Main.fng: constructor 0x4F3320, 0x9C bytes from
 * operator new, then this base constructor, thiscall, ret 4) keeps a
 * profile's name at +0x6C, 32 bytes.  The Save question shows it ("Are you
 * sure you want to save the profile named %s?", 0x4A3C10), and the save
 * makes it the profile's name (states 6 and 7 of 0x4E8D30: 0x4E8ED4 and
 * 0x4E8F17 copy it into 0x83A9E0 with 0x502F40) before the file is written
 * under it.  Most ways into the save copy the profile's name there first
 * (0x4F3462, 0x4F35FC, 0x4FD694); those through state 2 do not (0x4FD658:
 * message 0xDC12AF2E, which 0x4C6457 sends when a memory card operation
 * fails; 0x4FBA5F), and the field holds what the heap block held before.
 * The PC game's heap mostly gives the screen the block the last one left,
 * name and all; ours does not.  A cover shoot (DVD or magazine) whose save
 * failed (its new 1 MB cover file not written) went on to the profile's save
 * that way: the question showed the heap's bytes as the name and Yes renamed
 * the profile to them and saved it in a folder of that name (nfsu2-web,
 * 2026-10-27 report; tests/scripts/career_cover_name.txt).  The field now
 * starts as the profile's name (zeros with none loaded), as the old block
 * held it; the ways that put another name there still do. */
#define MC_NAME         0x6cu               /* the screen's profile name, 32 bytes */
#define PROFILE_NAME    GA(0x0083a9e0u)     /* the profile's name, 32 bytes; +0x20 a byte, 1: a profile is loaded */
void sub_004e8b70_orig(CPU *c);
void sub_004e8b70(CPU *c){
    static int stale = -1;
    if (stale < 0){ const char *e = getenv("NFSU2_TEST_MC_STALE"); stale = e && *e == '1'; }
    uint32_t self = c->ecx;
    sub_004e8b70_orig(c);
    if (!self || !mem_is_committed(self + MC_NAME) || !mem_is_committed(self + MC_NAME + 31u)) return;
    int named = MR8(PROFILE_NAME + 0x20u) != 0;
    for (uint32_t i = 0; i < 32u; i++)
        MR8(self + MC_NAME + i) = stale ? 0xefu : named ? MR8(PROFILE_NAME + i) : 0u;
}

/* --- sub_004ff3b0: a first profile's name box starts with the Player name ---
 * The game's one text entry (0x83A7B0) is set up here (thiscall, ret 0x10:
 * record, kind, text, most): the text goes to +0x100 (what is typed, and
 * shown) and +0 (what it started with), its length to +0x200.  A new
 * profile's name (0x5564A0, NA 0x556490: kind 6, letters and digits, 7 at
 * most) starts with the game's text 0x818F0385, NAME in English (empty in
 * some languages), and typing goes after it: many players kept NAME.  When
 * the save folder has no profile the launcher passes its Player name as
 * NFSU2_NEW_PROFILE_NAME (Model.swift: letters and digits, 7 at most; never
 * NAME, Player or a name names.h blocks), and while no profile is loaded the
 * box starts with it.  One Enter takes it.  The other kind-6 boxes (12 at
 * most) stay as they are.  Ported from th0mk's nfsu2-web
 * runtime/overrides.c (MIT). */
#define TXT_TEXT         0x100u        /* what is typed (and shown); +0 what it started with */
#define TXT_LEN          0x200u
#define TXT_KIND         0x204u
#define TXT_MOST         0x20cu
#define NEW_PROFILE_MOST 7u
uint32_t language_text(uint32_t hash);  /* language.c: the game's text by its hash, a guest address (0: none) */
void sub_004ff3b0_orig(CPU *c);
void sub_004ff3b0(CPU *c){
    static const char *want;
    static int got;
    if (!got){ got = 1; want = getenv("NFSU2_NEW_PROFILE_NAME"); if (want && !*want) want = 0; }
    uint32_t self = c->ecx;
    sub_004ff3b0_orig(c);
    if (!want || !self || !mem_is_committed(self) || !mem_is_committed(self + TXT_MOST + 3u)) return;
    if (MR32(self + TXT_KIND) != 6u || MR32(self + TXT_MOST) != NEW_PROFILE_MOST || MR8(PROFILE_NAME + 0x20u)) return;
    /* the game's start: empty, or its default name */
    uint32_t def = language_text(0x818f0385u), len = MR32(self + TXT_LEN);
    if (len){
        if (!def || len > 32u || !mem_is_committed(def) || !mem_is_committed(def + len)) return;
        for (uint32_t i = 0; i <= len; i++) if (MR8(def + i) != MR8(self + TXT_TEXT + i)) return;
    }
    char name[NEW_PROFILE_MOST]; uint32_t n = 0;
    for (const char *p = want; *p && n < NEW_PROFILE_MOST; p++)
        if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9')) name[n++] = *p;
    if (!n) return;
    for (uint32_t i = 0; i < 0x100u; i++){
        uint8_t b = i < n ? (uint8_t)name[i] : 0u;
        MR8(self + TXT_TEXT + i) = b;
        MR8(self + i) = b;
    }
    MR32(self + TXT_LEN) = n;
    fprintf(stderr, "[profile] a new profile's name starts as the Player name (NFSU2_NEW_PROFILE_NAME), not the game's default\n");
}

/* --- sub_004df9c0: a screen's list of the player's cars, a stock car of no type ---
 * The car lot's list (filter 1: the stock cars) and the game's other lists of
 * the player's cars (0x4ED935: filter 4) are made here (thiscall: the screen,
 * its +0xEC the player; ret 4) from the player's car records (FEDatabase
 * +0x3C0, 0x83AD90 + 0xAB4C a player), each one's car type looked up in
 * CarTypeInfo[] ([0x8A1CCC], 46 of 0x890 bytes) with no bound.  The 48 stock
 * cars (0x1C bytes from +0: +8 the handle, bStringHash of "STOCK_<name>",
 * +0x10 in use, +0x14 1, +0x18 the type's index) are made once, for a new
 * profile (sub_00516500: the types the car lot sells), then saved and loaded
 * with the profile as they are.  A player's profile held one in use with an
 * index no car has: the car lot's list read its CarTypeInfo out of bounds and
 * the game ended as the car lot opened, so the player could buy no car (a
 * memory access out of bounds in 0x4DF9C0, at +0xDA).  How the profile got it
 * is not known.  Before a list is made, a stock car in use past the 46 types
 * has the table made again as the game makes it for a new profile, and the
 * records that leaves unused get the index of none (-1, as their constructor
 * leaves it); the profile keeps the table at its next save. */
#define FECARS          GA(0x0083ad90u)
#define FECARS_PLAYER   0xab4cu
#define STOCK_N         48u
#define STOCK_SZ        0x1cu
#define CARTYPES_N      46u           /* the builder walks 0x189E0 bytes of CarTypeInfo */
void sub_004df9c0_orig(CPU *c);
void sub_00516500(CPU *c);
static void stock_check(CPU *c, uint32_t who){
    if (who >= 2u) return;
    uint32_t db = FECARS + who * FECARS_PLAYER, bad = STOCK_N;
    for (uint32_t i = 0; i < STOCK_N && bad == STOCK_N; i++){
        uint32_t r = db + i * STOCK_SZ;
        if (MR32(r + 0x10u) && MR32(r + 0x18u) >= CARTYPES_N) bad = i;
    }
    if (bad == STOCK_N) return;
    uint32_t r = db + bad * STOCK_SZ;
    fprintf(stderr, "[cars] player %u's stock car %u (handle 0x%08x) has car type %u, none of the game's %u: "
            "the stock cars made again, as for a new profile\n", who, bad, MR32(r + 8u), MR32(r + 0x18u), CARTYPES_N);
    CPU save = *c;
    c->esp = (c->esp - 256u) & ~15u;
    PUSH32(0u);                           /* its argument, not read */
    c->ecx = db;
    PUSH32(GA(0x004df9c0u));              /* the ret pops it into eip; the state is put back below */
    sub_00516500(c);
    *c = save;
    for (uint32_t i = 0; i < STOCK_N; i++)
        if (!MR32(db + i * STOCK_SZ + 0x10u)) MR32(db + i * STOCK_SZ + 0x18u) = 0xffffffffu;
    g_lot_fixed++;
    uint32_t over = 0;
    for (uint32_t i = 0; i < STOCK_N; i++)
        if (MR32(db + i * STOCK_SZ + 0x10u) && MR32(db + i * STOCK_SZ + 0x18u) >= CARTYPES_N) over++;
    fprintf(stderr, "[cars] %u stock cars, %u with a car type past the game's\n", MR32(db + 0x540u), over);
}
void sub_004df9c0(CPU *c){
    stock_check(c, MR32(c->ecx + 0xecu));
    sub_004df9c0_orig(c);
}

/* --- sub_00483e40: a positional sound's source goes ----------------------
 * The world's positional sounds (the list at [[0x82B884]+0x3C], vtable
 * 0x78BFD0) keep their sound objects at +0x24 and the frame's voice requests
 * at +4: bPNode list nodes, one per object waiting for a voice, their count
 * at +0xC.  A request recounts the list (0x479770).  The voice arbitration
 * (0x481850, from the list's update 0x481BD0) gives the requesters voices;
 * when the count and the voices in use [0x82B950] pass the limit [0x7ECBC8]
 * (5), it takes voices from quieter objects instead, walking its sorted copy
 * of the requests from the first node without checking that there is one
 * (0x481AB4).  Removing a source (0x483E40 -> 0x481E50, from the source's
 * destructor 0x5A9580) takes its object's request out of the list and
 * destroys the object, but leaves the count.  With every voice in use and
 * that the only request, the arbitration took its empty list's head for a
 * request, read an object pointer off the stack, and trapped or called 0
 * (0x481B1C).  Many cars round the player keep all five voices busy, so
 * requests wait, and a jump away frees the old place's world objects with
 * their sources.  After a removal the count is made again, as a request does
 * (0x43BE80: the list's length). */
void sub_00483e40_orig(CPU *c);
void sub_00483e40(CPU *c){
    uint32_t list = MR32(c->ecx + 0x3cu);
    if (g_snd_stale && list && MR32(GA(0x007faaa8u))){ g_snd_stale--; MR32(list + 0xcu) += 3u; }
    sub_00483e40_orig(c);
    if (!MR32(GA(0x007faaa8u)) || !list) return;     /* sound off: nothing was removed */
    uint32_t head = list + 4u, n = 0, was = MR32(list + 0xcu);
    for (uint32_t e = MR32(head); e && e != head && n < 1024u; e = MR32(e)) n++;
    MR32(list + 0xcu) = n;
    g_snd_recount++;
    if (n != was && g_snd_fixed++ < 8)
        fprintf(stderr, "[sound] f=%ld a positional source removed: %u voice requests left, the count said %u\n",
                metal_frames(), n, was);
}

/* --- sub_00574680(block, out): a compressed block unpacked, cdecl ----------
 * The game's four kinds by the block's tag: COMP, HUFF, RAWW and JDLZ, for
 * the model and texture packs' callbacks, the FE packs and the track
 * streamer.  A car's TEXTURES.BIN keeps most of its textures in JDLZ blocks
 * (~8 MB unpacked); the game's loop, lifted, unpacked them on the game thread
 * at about 2 ms a car.  JDLZ is unpacked here, natively, as the game's loop
 * does it: the two flag words (a byte | 0x100, shifted right, the next byte
 * once down to 1); a flagged pair of bytes a match -- with the second flag
 * set 4 bits of distance - 1 and 12 of length - 3, else 5 of length - 3 and
 * 11 of distance - 17 -- copied a byte at a time; a literal byte only while
 * the output has room (past it the byte stays unread but is counted); the
 * loop runs until the block's size (+0xC) less the 16-byte header and the
 * first two flag bytes is used up; the unpacked size (+8) is returned.  A
 * block whose bytes are not all in guest memory, which overlaps the output,
 * or would read or write past the output's ends goes to the game's code from
 * the start (each byte it writes again is the same).  The other kinds: the
 * game's.  NFSU2_JDLZ_VERIFY=1 (test aid): each block unpacked both ways,
 * compared ("[jdlz] DIFFERS"); NFSU2_JDLZ=0: the game's code only. */
#define JDLZ_TAG        0x5a4c444au
void sub_00574680_orig(CPU *c);
static int range_committed(uint32_t a, uint32_t n){
    if (!n) return 1;
    if (a + n < a) return 0;
    for (uint32_t pg = a >> 14, last = (a + n - 1u) >> 14; pg <= last; pg++)
        if (!((g_cbits[pg >> 3] >> (pg & 7)) & 1)) return 0;
    return 1;
}
/* 1: unpacked into out; 0: not done (out may hold some of it) */
static int jdlz_native(uint32_t blk, uint32_t out){
    uint32_t size = MR32(blk + 8u), csize = MR32(blk + 0xcu);
    if (csize < 0x12u || !range_committed(blk, csize) || !range_committed(out, size)) return 0;
    if (blk < out + size && out < blk + csize) return 0;
    const uint8_t *s = &MR8(blk + 0x12u);
    uint8_t *o0 = &MR8(out), *o = o0, *end = o0 + size;
    uint32_t f1 = (uint32_t)MR8(blk + 0x10u) | 0x100u, f2 = (uint32_t)MR8(blk + 0x11u) | 0x100u, left = csize - 0x12u;
    const uint8_t *s_end = &MR8(blk) + csize;
    while (left){
        if (f1 & 1u){
            uint32_t len, dist;
            if (s + 2 > s_end) return 0;
            if (f2 & 1u){ len = ((uint32_t)(s[0] & 0xf0u) << 4 | s[1]) + 3u; dist = (s[0] & 0x0fu) + 1u; }
            else { dist = ((uint32_t)(s[0] & 0xe0u) << 3 | s[1]) + 17u; len = (s[0] & 0x1fu) + 3u; }
            if ((uint32_t)(o - o0) < dist || len > (uint32_t)(end - o)) return 0;
            for (uint32_t i = 0; i < len; i++) o[i] = o[(int32_t)i - (int32_t)dist];
            o += len; s += 2; left -= 2u; f2 >>= 1;
            if (left > 0x80000000u) return 0;           /* (the game's count would have passed 0: it runs on) */
        } else {
            if (o < end){ if (s >= s_end) return 0; *o++ = *s++; }
            left--;
        }
        f1 >>= 1;
        if (f1 == 1u){ if (!left || s >= s_end) return 0; f1 = (uint32_t)*s++ | 0x100u; left--; }
        if (f2 == 1u){ if (!left || s >= s_end) return 0; f2 = (uint32_t)*s++ | 0x100u; left--; }
    }
    return 1;
}
void sub_00574680(CPU *restrict c){
    static int mode = -1;     /* 0 the game's code, 1 native, 2 verify */
    if (mode < 0){
        const char *e = getenv("NFSU2_JDLZ"), *v = getenv("NFSU2_JDLZ_VERIFY");
        mode = e && *e == '0' ? 0 : v && *v == '1' ? 2 : 1;
    }
    uint32_t e = c->esp, blk = MR32(e + 4u), out = MR32(e + 8u);
    if (mode && blk && out && mem_is_committed(blk) && mem_is_committed(blk + 15u) && MR32(blk) == JDLZ_TAG && MR8(blk + 4u) == 2){
        uint32_t size = MR32(blk + 8u);
        if (mode == 1){
            if (jdlz_native(blk, out)){ g_jdlz_n++; g_jdlz_bytes += size; c->eax = size; POP32(c->eip); return; }
            g_jdlz_lifted++;
        } else if (range_committed(out, size)){
            uint8_t *mine = malloc(size ? size : 1);
            int done = mine && jdlz_native(blk, out);
            if (done) memcpy(mine, &MR8(out), size);
            sub_00574680_orig(c);
            if (done && memcmp(mine, &MR8(out), size)){
                uint32_t at = 0; while (at < size && mine[at] == MR8(out + at)) at++;
                if (g_jdlz_diff++ < 8)
                    fprintf(stderr, "[jdlz] f=%ld DIFFERS from the game's: block 0x%08x, %u bytes, first at %u\n", metal_frames(), blk, size, at);
            }
            if (done){ g_jdlz_n++; g_jdlz_bytes += size; } else g_jdlz_lifted++;
            free(mine);
            return;
        }
    }
    sub_00574680_orig(c);
}

/* --- sub_0061b990: NewGetCarPart(type, slot, key, previous, level), thiscall
 * CarPartDB, ret 0x14 -------------------------------------------------------
 * A part of a car type in a ride slot (with a key, after a part, of an
 * upgrade level), found by walking the database's parts of the type's owners
 * one by one, three attribute names hashed at each.  A ride's stock parts ask
 * it for each of 170 slots, going through a slot's parts one after another
 * until one of the level, and run UpdatePartsEnabled (which asks it again)
 * after each slot: about 3,900 asks a car; the player's own car and the shops
 * ask it too.  It reads the database and its owner and attribute tables,
 * which do not change once the game has loaded them, and writes nothing, so
 * its answers (no part among them: most slots have none) are kept by their
 * arguments: all forgotten if one of those tables moves, or when PARTMEMO_N
 * is 3/4 full.  NFSU2_PARTMEMO=0 (test aid): asked every time; 2: asked every
 * time, each kept answer checked against it ("[parts] DIFFERS"). */
#define PARTMEMO_N      262144                  /* a power of two: 4 MB */
#define G_CARPARTDB_OBJ GA(0x008a2b68u)
void sub_0061b990_orig(CPU *c);
static struct { uint32_t key, prev, part; uint8_t type, slot, lvl, used; } g_pm[PARTMEMO_N];
static uint32_t g_pm_n, g_pm_tabs[4];
void sub_0061b990(CPU *restrict c){
    static int mode = -1;
    if (mode < 0){ const char *e = getenv("NFSU2_PARTMEMO"); mode = e && *e == '0' ? 0 : e && *e == '2' ? 2 : 1; }
    uint32_t e = c->esp, db = c->ecx;
    if (!mode || db != G_CARPARTDB_OBJ || !mem_is_committed(e + 0x14u)){ sub_0061b990_orig(c); return; }
    uint32_t type = MR32(e + 4u), slot = MR32(e + 8u), key = MR32(e + 12u), prev = MR32(e + 16u), lvl = MR32(e + 20u);
    if (type > 0xffu || slot > 0xffu || (int32_t)lvl < -128 || (int32_t)lvl > 127){ sub_0061b990_orig(c); return; }
    uint32_t tabs[4] = { MR32(db), MR32(GA(0x008a1cb8u)), MR32(GA(0x008a1cbcu)), MR32(GA(0x008a1cc8u)) };   /* parts, owners, their count, attributes */
    if (memcmp(tabs, g_pm_tabs, sizeof tabs) || g_pm_n >= PARTMEMO_N / 4u * 3u){
        memset(g_pm, 0, sizeof g_pm); g_pm_n = 0; memcpy(g_pm_tabs, tabs, sizeof tabs); g_pm_clears++;
    }
    g_pm_calls++;
    uint32_t h = (type * 0x85ebca77u) ^ (slot * 0xc2b2ae3du) ^ (key * 0x27d4eb2fu) ^ (prev * 0x165667b1u) ^ (lvl * 0xd3a2646cu);
    h = (h ^ (h >> 15)) * 0x2c1b3c6du;
    h = (h ^ (h >> 12)) & (PARTMEMO_N - 1u);
    for (; g_pm[h].used; h = (h + 1u) & (PARTMEMO_N - 1u)){
        if (g_pm[h].type != type || g_pm[h].slot != slot || g_pm[h].key != key || g_pm[h].prev != prev || g_pm[h].lvl != (uint8_t)lvl) continue;
        if (mode == 1){ g_pm_hits++; c->eax = g_pm[h].part; POP32(c->eip); c->esp += 0x14u; return; }
        uint32_t kept = g_pm[h].part;
        sub_0061b990_orig(c);
        g_pm_hits++;
        if (c->eax != kept && g_pm_diff++ < 8)
            fprintf(stderr, "[parts] f=%ld DIFFERS from the game's: type %u slot 0x%x key 0x%x after 0x%x level %d: 0x%x, kept 0x%x\n",
                    metal_frames(), type, slot, key, prev, (int32_t)lvl, c->eax, kept);
        return;
    }
    sub_0061b990_orig(c);
    g_pm[h].type = (uint8_t)type; g_pm[h].slot = (uint8_t)slot; g_pm[h].key = key; g_pm[h].prev = prev; g_pm[h].lvl = (uint8_t)lvl;
    g_pm[h].part = c->eax; g_pm[h].used = 1; g_pm_n++;
}

/* --- NFSU2_FIXTEST --------------------------------------------------------- */
static void fixtest(CPU *c, long f){
    static int parsed = 0, n = 0;
    static struct { char name[16]; long at; int done; } t[8];
    if (!parsed){
        parsed = 1;
        const char *e = getenv("NFSU2_FIXTEST");
        while (e && *e && n < 8){
            const char *at = strchr(e, '@'), *nx = strchr(e, ',');
            if (!at || (nx && at > nx)) break;
            size_t l = (size_t)(at - e); if (l >= sizeof t[n].name) l = sizeof t[n].name - 1;
            memcpy(t[n].name, e, l); t[n].name[l] = 0; t[n].at = atol(at + 1); t[n].done = 0; n++;
            e = nx ? nx + 1 : 0;
        }
    }
    for (int i = 0; i < n; i++){
        if (t[i].done || f < t[i].at) continue;
        t[i].done = 1;
        if (!strcmp(t[i].name, "badstock")){
            uint32_t r = FECARS;
            fprintf(stderr, "[fixtest] f=%ld badstock: player 0's stock car 0 (in use %u, type %u) given car type 0x9a3c5e71\n",
                    f, MR32(r + 0x10u), MR32(r + 0x18u));
            MR32(r + 0x10u) = 1u; MR32(r + 0x18u) = 0x9a3c5e71u;
            stock_check(c, 0);
        } else if (!strcmp(t[i].name, "badvoices")){
            fprintf(stderr, "[fixtest] f=%ld badvoices: the next 3 positional sound removals start with the count 3 too high\n", f);
            g_snd_stale = 3;
        } else if (!strcmp(t[i].name, "shopstale")){
            fprintf(stderr, "[fixtest] f=%ld shopstale: package screens start with +0xC0 = 1 from now on\n", f);
            g_shop_stale = 1;
        } else fprintf(stderr, "[fixtest] unknown test \"%s\"\n", t[i].name);
    }
}

/* com.c Present, on the game thread with the guest lock held */
void gamefix_on_present(CPU *c){
    static int on = -1;
    if (on < 0) on = getenv("NFSU2_FIXTEST") != 0;
    if (on) fixtest(c, metal_frames());
}

void gamefix_report(void){
    if (g_jdlz_n || g_jdlz_lifted)
        fprintf(stderr, "  JDLZ: %llu blocks unpacked natively (%.1f MB), %llu by the game's code%s\n",
                (unsigned long long)g_jdlz_n, g_jdlz_bytes / 1048576.0, (unsigned long long)g_jdlz_lifted,
                g_jdlz_diff ? ", DIFFERENCES" : "");
    if (g_pm_calls)
        fprintf(stderr, "  NewGetCarPart: %llu of %llu answers kept from before (all forgotten %llu times)%s\n",
                (unsigned long long)g_pm_hits, (unsigned long long)g_pm_calls, (unsigned long long)g_pm_clears,
                g_pm_diff ? ", DIFFERENCES" : "");
    if (g_snd_recount)
        fprintf(stderr, "  positional sounds: %llu sources removed, %llu voice request counts corrected\n",
                (unsigned long long)g_snd_recount, (unsigned long long)g_snd_fixed);
    if (g_shop_init || g_lot_fixed)
        fprintf(stderr, "  shop screens: %llu package screens initialised, %llu stock car tables rebuilt\n",
                (unsigned long long)g_shop_init, (unsigned long long)g_lot_fixed);
}
