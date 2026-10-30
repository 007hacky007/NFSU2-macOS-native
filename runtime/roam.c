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
 * its own LAN race labels.  Both are tools/gen_v2.sh HOOKS.  The whole CPU
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

#define HOOK_MAINLOOP   GA(0x00581485u)   /* GameLoop, before its second debug no-op call */
#define HOOK_HUD        GA(0x006005f0u)   /* Player::Update (0x6005A0), behind its call of the HUD update (0x4EC5A0) */

static int roam_on(void){
    static int on = -1;
    if (on < 0){ const char *e = getenv("NFSU2_ROAM"); on = e && *e == '1'; }
    return on;
}

/* debug.c guest_hook */
int roam_hook(CPU *c, uint32_t ip){
    if (ip == HOOK_MAINLOOP){
        if (roam_on()){ roam_texts_frame(c); mprace_frame(c); roam_game_frame(c); }
        return 1;
    }
    if (ip == HOOK_HUD){
        if (roam_on()) roam_game_hud(c);
        return 1;
    }
    return 0;
}

/* ---- overrides (tools/gen_v2.sh OVR, OVR_NA) ----------------------------------- */
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
#define FN_NEW          GA(0x00575630u)   /* cdecl (size): operator new */
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
 * buttons, roam_game.c) go into its language table under names of ours, so
 * that it looks them up as its own.  The game only points the table into
 * its language chunk (0x5125B0 loads it, 0x4FFAE0 clears it).  Each frame a
 * table that is not ours, or one older than a text added since, is replaced
 * by a copy with every text of ours merged in by hash (unsigned, as 0x4FF9D0
 * compares; a hash the game has keeps the game's), their strings after the
 * entries.  The game's own array stays as it was, for the next copy. */
#define OWN_MAX         8
static struct { uint32_t hash; char text[256]; } g_own[OWN_MAX];
static int g_nown, g_own_merged;              /* texts named; how many of them the copy has */
static uint32_t g_own_copy, g_own_from, g_own_from_n;   /* the copy, while the game points at it; the game's array */
uint32_t roam_add_text(const char *name, const char *text){
    uint32_t h = 0xffffffffu;                 /* bStringHash (0x43DB50) */
    for (const char *s = name; *s; s++) h = h * 33u + (uint8_t)*s;
    int i = 0;
    while (i < g_nown && g_own[i].hash != h) i++;
    if (i == OWN_MAX){ fprintf(stderr, "[roam] no room for the text %s\n", name); return h; }
    if (i == g_nown) g_nown++;
    g_own[i].hash = h;
    snprintf(g_own[i].text, sizeof g_own[i].text, "%s", text);
    g_own_merged = -1;                        /* a new copy, also for a text changed */
    return h;
}
static uint32_t guest_new(CPU *c, uint32_t size){
    CPU save = *c;
    c->esp = (c->esp - 256u) & ~15u;
    PUSH32(size);
    PUSH32(HOOK_MAINLOOP);                    /* the hook's address as the return address: the callee's ret pops it */
    dispatch_indirect(c, FN_NEW);
    uint32_t r = c->eax;
    *c = save;
    return r;
}
void roam_texts_frame(CPU *c){
    uint32_t t = MR32(G_LANG), n = MR32(G_LANG_N);
    if (!g_nown || !t || !n || n > 0x100000u) return;
    if (t == g_own_copy){
        if (g_own_merged == g_nown) return;
        t = g_own_from; n = g_own_from_n;
    }
    if (!mem_is_committed(t) || !mem_is_committed(t + 8u * n - 1u)) return;
    int ord[OWN_MAX];
    uint32_t strs = 0;
    for (int i = 0; i < g_nown; i++){ ord[i] = i; strs += (uint32_t)strlen(g_own[i].text) + 1u; }
    for (int i = 1; i < g_nown; i++)
        for (int j = i; j > 0 && g_own[ord[j - 1]].hash > g_own[ord[j]].hash; j--){ int x = ord[j]; ord[j] = ord[j - 1]; ord[j - 1] = x; }
    uint32_t mem = guest_new(c, (n + (uint32_t)g_nown) * 8u + strs);
    if (!mem){ fprintf(stderr, "[roam] guest memory for our texts failed\n"); g_own_copy = t; g_own_merged = g_nown; return; }
    uint32_t sp = mem + (n + (uint32_t)g_nown) * 8u, sa[OWN_MAX];
    for (int i = 0; i < g_nown; i++){
        size_t l = strlen(g_own[i].text) + 1u;
        memcpy(g_mem + sp, g_own[i].text, l); sa[i] = sp; sp += (uint32_t)l;
    }
    uint32_t o = 0; int k = 0, kept = 0;
    for (uint32_t i = 0; i <= n; i++){
        uint32_t h = i < n ? MR32(t + 8u * i) : 0xffffffffu;
        while (k < g_nown && g_own[ord[k]].hash <= h){
            if (g_own[ord[k]].hash == h && i < n){ k++; kept++; continue; }   /* the game has the name already */
            MR32(mem + 8u * o) = g_own[ord[k]].hash; MR32(mem + 8u * o + 4u) = sa[ord[k]]; o++; k++;
        }
        if (i < n){ MR32(mem + 8u * o) = h; MR32(mem + 8u * o + 4u) = MR32(t + 8u * i + 4u); o++; }
    }
    MR32(G_LANG) = mem; MR32(G_LANG_N) = o;
    g_own_copy = mem; g_own_from = t; g_own_from_n = n; g_own_merged = g_nown;
    fprintf(stderr, "[roam] %d text%s of our own added to the game's %u%s\n", g_nown - kept, g_nown - kept == 1 ? "" : "s", n,
            kept ? " (some names the game has already: the game's stay)" : "");
}
