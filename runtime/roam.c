/* roam.c -- free-roam multiplayer: where the game calls it.
 *
 * Players see each other's cars in career free roam and can race each other
 * from its race markers (roam_game.c; the trip to the race, mprace.c).  Off
 * unless NFSU2_ROAM=1 (the launcher's Multiplayer card, with Play online).
 *
 * The guest calls run in the game's main loop, at an instruction hook before
 * the second debug no-op call of GameLoop (0x581485, NA 0x581475), on the
 * guest thread between two frames; the names over the cars after the HUD's
 * update in Player::Update (0x6005F0, NA 0x6005E0), where the game places
 * its own LAN race labels.  The main-loop hook also runs the horns of
 * network races and the Horn Volume slider's frame (racehorn.c,
 * hornmenu.c; only with horns on, NFSU2_HORN), free roam or not.  Both are tools/gen_v2.sh HOOKS.  The whole CPU
 * state is saved and restored around each call (roam_host.h rh_call).
 *
 * The overrides below hand the game's functions to roam_game.c, which says
 * what each one is for.  It also has what the two files need from the rest
 * of the runtime: the front end's packages, texts of our own in the game's
 * language table, a HUD marker's place on a wide screen.
 *
 * Adapted from th0mk's nfsu2-web runtime/roam.c and language.c (MIT).
 */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

void dispatch_indirect(CPU *c, uint32_t addr);
void roam_game_frame(CPU *c);
void roam_game_hud(CPU *c);
void mprace_frame(CPU *c);
void roam_texts_frame(CPU *c);
void racehorn_frame(CPU *c);                  /* racehorn.c: horns in network races (NFSU2_HORN) */
void hornmenu_frame(CPU *c);                  /* hornmenu.c: the Horn Volume slider (NFSU2_HORN) */

#define HOOK_MAINLOOP   HOOK_SITE(0x00581485u)   /* GameLoop, before its second debug no-op call */
#define HOOK_HUD        HOOK_SITE(0x006005f0u)   /* Player::Update (0x6005A0), behind its call of the HUD update (0x4EC5A0) */

static int roam_on(void){
    static int on = -1;
    if (on < 0){ const char *e = getenv("NFSU2_ROAM"); on = e && *e == '1'; }
    return on;
}

/* debug.c guest_hook */
int roam_hook(CPU *c, uint32_t ip){
    if (ip == HOOK_MAINLOOP){
        if (roam_on()){ roam_texts_frame(c); mprace_frame(c); roam_game_frame(c); }
        racehorn_frame(c); hornmenu_frame(c);  /* with or without free roam */
        { void career_frame(CPU *); career_frame(c); }   /* career.c: the test runner's career aids */
        return 1;
    }
    if (ip == HOOK_HUD){
        if (roam_on()) roam_game_hud(c);
        return 1;
    }
    return 0;
}

/* ---- overrides (the sub_X_orig names: tools/genlists.py) ---------------------- */
/* Car::SetPhysicsMode (thiscall mode, ret 4): a friend's car is not woken
 * into physics when a car comes near it (roam_game_inert) */
void sub_005f46b0_orig(CPU *c);
int roam_game_inert(uint32_t car, uint32_t mode, uint32_t from);
void sub_005f46b0(CPU *c){
    if (roam_on() && roam_game_inert(c->ecx, MR32(c->esp + 4u), MR32(c->esp))){ POP32(c->eip); c->esp += 4u; return; }
    sub_005f46b0_orig(c);
}
/* a touching pair of collision bodies (thiscall, from the collision step
 * only): a hit between the player's car and a friend's car is shared
 * between the two (roam_game_contact) */
void sub_005b2620_orig(CPU *c);
void roam_game_contact(CPU *c, void (*orig)(CPU *));
void sub_005b2620(CPU *c){
    if (roam_on()) roam_game_contact(c, sub_005b2620_orig);
    else sub_005b2620_orig(c);
}
/* the race's end, for the random encounters: new goals for the AI range's
 * cars through their brains; friends' cars have none (roam_game_goals) */
void sub_0042cd60_orig(CPU *c);
void roam_game_goals(CPU *c, void (*orig)(CPU *));
void sub_0042cd60(CPU *c){
    if (roam_on()) roam_game_goals(c, sub_0042cd60_orig);
    else sub_0042cd60_orig(c);
}
/* GetTextureInfo(hash, default, ...) (cdecl): friends' cars past the game's
 * six paint slots composite into textures of our own (roam_game_texture) */
void sub_004901d0_orig(CPU *c);
uint32_t roam_game_texture(uint32_t hash);
void sub_004901d0(CPU *c){
    uint32_t ti = roam_on() ? roam_game_texture(MR32(c->esp + 4u)) : 0;
    if (ti){ MR8(ti + 0x53u) = 1; c->eax = ti; POP32(c->eip); return; }     /* as the game marks a texture it hands out */
    sub_004901d0_orig(c);
}
/* bSlotPool's constructor (cdecl size, count, name, flags): more of a few
 * pools than the game makes (roam_game_pool) */
void sub_00440df0_orig(CPU *c);
uint32_t roam_game_pool(uint32_t name, uint32_t count);
void sub_00440df0(CPU *c){
    if (roam_on()) MR32(c->esp + 8u) = roam_game_pool(MR32(c->esp + 12u), MR32(c->esp + 8u));
    sub_00440df0_orig(c);
}
/* CarLoader: give back the memory a track load added to the Cars pool
 * (thiscall, no arguments) only once it is free; a track load's addition
 * (thiscall size, ret 4) only when the pool is smaller
 * (roam_game_loader_release, roam_game_pool_grow) */
void sub_0063a700_orig(CPU *c);
int roam_game_loader_release(CPU *c);
void sub_0063a700(CPU *c){
    if (!roam_on() || roam_game_loader_release(c)) sub_0063a700_orig(c);
    else POP32(c->eip);
}
void sub_00610760_orig(CPU *c);
int roam_game_pool_grow(uint32_t size);
void sub_00610760(CPU *c){
    if (!roam_on() || roam_game_pool_grow(MR32(c->esp + 4u))) sub_00610760_orig(c);
    else { POP32(c->eip); c->esp += 4u; }
}
/* CarLoader's purge (thiscall phase, ret 4): at a load's memory check in
 * free roam a ride nobody uses goes first, then the pool grows
 * (roam_game_purge) */
void sub_0063a1c0_orig(CPU *c);
int roam_game_purge(CPU *c, uint32_t ret);
void sub_0063a1c0(CPU *c){
    if (roam_on() && MR8(c->esp + 4u) && roam_game_purge(c, MR32(c->esp))){ c->eax = 1; POP32(c->eip); c->esp += 4u; return; }
    sub_0063a1c0_orig(c);
}

/* ---- the front end's packages ---------------------------------------------------
 * cFEng [0x8384C4] +8 -> its manager, whose lists at +0xE4 and +0xF4 chain
 * FNGInfo records through +4, the package's name at +0xC; the first of
 * +0xE4 is the top package (GetTopPackage 0x50C8E0).  Overlays such as a
 * dialog are on these lists while the top package still names the screen
 * under them. */
#define G_FENG          GA(0x008384c4u)
static uint32_t fe_mgr(void){
    if (!mem_is_committed(G_FENG)) return 0;
    uint32_t fe = MR32(G_FENG);
    if (!fe || !mem_is_committed(fe + 11u)) return 0;
    uint32_t mg = MR32(fe + 8u);
    return mg && mem_is_committed(mg + 0xf7u) ? mg : 0;
}
static const char *fe_name(uint32_t p){
    uint32_t n = MR32(p + 0xcu);
    if (!n || !mem_is_committed(n) || !mem_is_committed(n + 47u)) return 0;
    const char *q = (const char *)(g_mem + n); int k = 0;
    while (k < 47 && q[k] >= 0x20 && q[k] < 0x7f) k++;
    return k > 4 && !q[k] ? q : 0;
}
const char *roam_top_fng(void){
    uint32_t mg = fe_mgr(), p = mg ? MR32(mg + 0xe4u) : 0;
    return p && mem_is_committed(p + 0x10u) ? fe_name(p) : 0;
}
int roam_fe_active(const char *want){
    uint32_t mg = fe_mgr();
    if (!mg) return 0;
    for (uint32_t head = 0xe4u; head <= 0xf4u; head += 0x10u){
        uint32_t p = MR32(mg + head);
        for (int k = 0; p && k < 64 && mem_is_committed(p) && mem_is_committed(p + 0x10u); k++, p = MR32(p + 4u)){
            const char *nm = fe_name(p);
            if (nm && !strcasecmp(nm, want)) return 1;
        }
    }
    return 0;
}

/* ---- a HUD marker on a wide screen ----------------------------------------------
 * The HUD is shown squeezed into the 4:3 middle; a marker placed from the
 * view's pixels gets the inverse of that squeeze, as wsfov.c gives the
 * game's own markers. */
int ws_game_fov(void);
float com_aspfix(void);
void roam_hud_marker(float *x, float *y){
    (void)y;
    if (ws_game_fov()) *x = 320.f + (*x - 320.f) / com_aspfix();
}

/* ---- the game's texts -----------------------------------------------------------
 * Its language table ([0x8383D8]: {hash, char *} sorted by hash, [0x8383D0]
 * of them; 0x4FF9D0 searches it). */
#define G_LANG          GA(0x008383d8u)
#define G_LANG_N        GA(0x008383d0u)
static uint32_t game_text(uint32_t hash){
    uint32_t tab = MR32(G_LANG), n = MR32(G_LANG_N);
    if (!tab || !n || n > 0x100000u || !mem_is_committed(tab) || !mem_is_committed(tab + 8u * n - 1u)) return 0;
    uint32_t lo = 0, hi = n;
    while (lo < hi){
        uint32_t mid = lo + (hi - lo) / 2, h = MR32(tab + 8u * mid);
        if (h == hash) return MR32(tab + 8u * mid + 4u);
        if (h < hash) lo = mid + 1; else hi = mid;
    }
    return 0;
}
/* Whether a profile name (16 bytes at most) is the game's "No Profile": what
 * 0x512360 puts in the profile's name (0x83A9E0) while none is loaded, in
 * the game's language ("Aucun profil", "Kein Profil", ...). */
int roam_no_profile(const char *name){
    if (!strcasecmp(name, "No Profile")) return 1;
    uint32_t s = game_text(0xcf4f80c2u);
    if (!s) s = game_text(0xc01a6f63u);
    return s && mem_is_committed(s) && mem_is_committed(s + 15u) && !strncasecmp(name, (const char *)(g_mem + s), 16);
}
/* Texts the game shows but has none of (the free-roam race questions'
 * buttons, roam_game.c) go into its language table under names of ours
 * (language.c language_add_text: one table for every text of ours, merged in
 * each frame from the main-loop hook). */
uint32_t language_add_text(const char *name, const char *text);
void language_texts_frame(CPU *c);
uint32_t roam_add_text(const char *name, const char *text){ return language_add_text(name, text); }
void roam_texts_frame(CPU *c){ language_texts_frame(c); }
