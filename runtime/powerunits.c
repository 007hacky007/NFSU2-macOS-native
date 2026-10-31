/* powerunits.c -- Power Units, a row of the game's own Gameplay options after
 * Speedometer Units: the engine's power in bhp or kW wherever the game shows
 * it, whatever the speedometer shows (km/h with hp, as many players want).  The game takes
 * both from Speedometer Units (0x83AA1A: 1 = km/h, Nm, kW; 0 = mph, ft-lbs,
 * bhp), and torque and speeds still do.  The value is the registry's
 * PowerUnits (1 = bhp, 0 = kW); none: as the speedometer, as in the original
 * game, until the row is changed.
 *
 * Power is kept in kW.  Each place that shows it asks 0x5EA8C0 ("km/h?") or
 * 0x5EA8B0 ("mph?") once for the factor (x1.341, 0x79BEF8, for bhp) and once
 * for the label, or reads the byte itself; hooks right after answer for the
 * power instead:
 *    0x53D0B0  the dyno chart: its power axis (600 bhp or 447 kW, 0x79BF08),
 *              the legend's "Power ( bhp )", the curve
 *    0x54A630  the chart's maximum power
 *    0x54A980  the results' power, of each run
 *    0x562540  the performance shop's single parts (UI_BuyPerformanceParts):
 *              a part's gain (the byte in bl, which the torque's has used
 *              by then)
 *
 * The row is a copy of Speedometer Units' class (vtable 0x791C90, a toggle of
 * 0x54 bytes made by 0x51E240) with two methods here, at guest addresses
 * nothing runs (the nops after Speedometer Units' own), which the dispatch
 * table sends to this file:
 *    1  0x49AE80  (?, message): a left or right (0x9120409E, 0xB5971BF1)
 *                 changes the value, the arrow blinks (16), the texts again (3)
 *    3  0x49AEE0  the name (+0x2C) and the value (+0x30), both by hash
 * Its value is the game's own "bhp" and "kW" (0xCBBC6512, 0x5B81D5BA), as
 * each language writes them ("CV", "pk", ...).  The screens' lists (0x54EF40;
 * the pause menu's 0x54F180) find an entry's parts in the screen's package by
 * name and number (OPTION_NAME_4, ...), and place them in its row: the row
 * goes in only where the package has them for the list's last entry too,
 * which ours makes one more.  Addresses are the European build's; GA() maps
 * them (runtime/build_na.h).
 * Ported from th0mk's nfsu2-web runtime/powerunits.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <string.h>

void dispatch_patch(uint32_t a, void (*f)(CPU *));
void dispatch_indirect(CPU *c, uint32_t addr);
int  win32_reg_get_dword(const char *nm, uint32_t *out);
void win32_reg_put_dword(const char *nm, uint32_t v);

#define REG_NAME      "PowerUnits"
#define A_KMH         GA(0x0083aa1au)   /* byte: Speedometer Units, 1 = km/h */
#define FN_NEW        GA(0x00575630u)   /* cdecl (size): operator new */
#define FN_TOGGLE     GA(0x0051e240u)   /* thiscall (screen +0xFC, +0x10C, +0x114, +0x11C, 1): a toggle entry */
#define FN_ADD        GA(0x0054ef40u)   /* thiscall screen (entry, 1): Options > Gameplay's list takes a toggle */
#define FN_ADD_PAUSE  GA(0x0054f180u)   /* thiscall screen (entry, 1): the pause menu's */
#define FN_MODE       GA(0x005026f0u)   /* thiscall 0x83AAB4: the game mode (2: the pause menu has no Explore Map Mode) */
#define FN_FE_STRING  GA(0x0050c900u)   /* cdecl (string object, hash): its text, in the game's language */
#define FN_FE_SETSTR  GA(0x00535ff0u)   /* thiscall string object (char*): its text */
#define FN_FE_HASH    GA(0x00505450u)   /* cdecl (name) -> hash */
#define FN_FE_PACKAGE GA(0x0052cf00u)   /* cdecl (package name) -> FEPackage* */
#define FN_PKG_FIND   GA(0x00517f80u)   /* thiscall package (hash) -> its object, 0: none */
#define VT_SPEEDO     GA(0x00791c90u)   /* Speedometer Units' class */
#define VT_N          18
#define M_ACT         GA(0x0049aed8u)   /* our methods 1 and 3 */
#define M_LABEL       GA(0x0049af13u)
#define MSG_LEFT      0x9120409eu
#define MSG_RIGHT     0xb5971bf1u
#define T_BHP         0xcbbc6512u
#define T_KW          0x5b81d5bau
#define S_COUNT       0x12cu        /* the screen: its entries so far (the next one's number) */
#define S_PACKAGE     4u            /* its package's name */
#define S_HEAD        0x4cu         /* its entries' list (an entry's node at +4: next, prev) */
#define W_LABEL       0x2cu         /* the entry: its OPTION_NAME_n */
#define W_VALUE       0x30u         /* its value */

static int g_installed;
static int g_hp = -1;                            /* 1: bhp, 0: kW, -1: as the speedometer */
static uint32_t g_vt, g_scr;                     /* guest memory: our vtable, then scratch for strings */

/* a guest function with ecx and stack arguments, the CPU as it was after */
static uint32_t gcall(CPU *c, uint32_t fn, uint32_t ecx, int n, const uint32_t *arg){
    CPU save = *c;
    c->esp = (c->esp - 256u) & ~15u;
    for (int i = n - 1; i >= 0; i--) PUSH32(arg[i]);
    c->ecx = ecx;
    PUSH32(fn);                                  /* the callee's ret pops it */
    dispatch_indirect(c, fn);
    uint32_t r = c->eax;
    *c = save;
    return r;
}
static void gstr(uint32_t a, const char *s, uint32_t cap){
    uint32_t i = 0;
    for (; s[i] && i + 1 < cap; i++) MR8(a + i) = (uint8_t)s[i];
    MR8(a + i) = 0;
}

static int bhp(void){ return g_hp >= 0 ? g_hp : MR8(A_KMH) != 1; }

/* the row's name (the game's own rows' names come from its language file,
 * which has none for this one) */
static const char *label(void){ return "Power Units"; }

/* 1: a left or right changes the value, to the registry */
static void pu_act(CPU *c){
    uint32_t self = c->ecx, msg = MR32(c->esp + 8u);
    if (msg == MSG_LEFT || msg == MSG_RIGHT){
        g_hp = !bhp();
        win32_reg_put_dword(REG_NAME, (uint32_t)g_hp);
        fprintf(stderr, "units: power in %s\n", g_hp ? "bhp" : "kW");
    }
    gcall(c, MR32(MR32(self) + 0x40u), self, 1, &msg);
    gcall(c, MR32(MR32(self) + 0x0cu), self, 0, 0);
    POP32(c->eip); c->esp += 8u;
}
/* 3: the name and the value */
static void pu_label(CPU *c){
    uint32_t self = c->ecx, obj = MR32(self + W_LABEL);
    if (obj && g_scr){
        gstr(g_scr, label(), 64);
        gcall(c, FN_FE_SETSTR, obj, 1, &g_scr);
        MR32(obj + 0x1cu) |= 2u;                 /* a text of its own, as FEPrintf leaves it (0x537B40) */
    }
    uint32_t a[2] = { MR32(self + W_VALUE), bhp() ? T_BHP : T_KW };
    gcall(c, FN_FE_STRING, 0, 2, a);
    POP32(c->eip);
}

/* the registry's value, and our methods to the dispatch table (once) */
void powerunits_install(void){
    if (g_installed) return;
    g_installed = 1;
    uint32_t v;
    if (win32_reg_get_dword(REG_NAME, &v)){
        g_hp = v != 0;
        fprintf(stderr, "units: power in %s (registry %s)\n", g_hp ? "bhp" : "kW", REG_NAME);
    }
    dispatch_patch(M_ACT, pu_act);
    dispatch_patch(M_LABEL, pu_label);
}

/* ---- the row ------------------------------------------------------------- */
/* a part's object in the package by name and number, 0: none */
static uint32_t part(CPU *c, uint32_t pk, uint32_t base, uint32_t n, char *nm, size_t cap){
    int k = 0;
    for (; k < 32 && MR8(base + (uint32_t)k); k++) nm[k] = (char)MR8(base + (uint32_t)k);
    snprintf(nm + k, cap - (size_t)k, "%u", n);
    gstr(g_scr, nm, 48);
    uint32_t h = gcall(c, FN_FE_HASH, 0, 1, &g_scr);
    return gcall(c, FN_PKG_FIND, pk, 1, &h);
}
/* Has the screen's package every part for entry n that it has for n - 1?
 * The names the toggles' list reads: +0xC4 OPTION_NAME_ .. +0xD8, but for
 * +0xCC in the menus' (0x54EF40). */
static int parts_there(CPU *c, uint32_t scr, uint32_t n, int pause){
    uint32_t pn = MR32(scr + S_PACKAGE), pk = pn ? gcall(c, FN_FE_PACKAGE, 0, 1, &pn) : 0;
    if (!pk || n < 2u) return 0;
    for (uint32_t o = 0xc4u; o <= 0xd8u; o += 4u){
        char nm[48], was[48];
        uint32_t b = o == 0xccu && !pause ? 0 : MR32(scr + o);
        if (b && !part(c, pk, b, n, nm, sizeof nm) && part(c, pk, b, n - 1u, was, sizeof was)){
            fprintf(stderr, "units: the screen has %s but no %s: no Power Units row\n", was, nm);
            return 0;
        }
    }
    return 1;
}
/* our row, entry n, before `after` more of the game's */
static void add(CPU *c, uint32_t scr, uint32_t fn_add, uint32_t after){
    powerunits_install();
    if (!g_vt){
        uint32_t sz = VT_N * 4u + 64u;
        if (!(g_vt = gcall(c, FN_NEW, 0, 1, &sz))) return;
        for (uint32_t i = 0; i < VT_N; i++) MR32(g_vt + 4u * i) = MR32(VT_SPEEDO + 4u * i);
        MR32(g_vt + 4u * 1u) = M_ACT; MR32(g_vt + 4u * 3u) = M_LABEL;
        g_scr = g_vt + VT_N * 4u;
    }
    uint32_t n = MR32(scr + S_COUNT);
    if (!parts_there(c, scr, n + after, fn_add == FN_ADD_PAUSE)) return;
    uint32_t sz = 0x54u, w = gcall(c, FN_NEW, 0, 1, &sz);
    if (!w) return;
    uint32_t a[5] = { scr + 0xfcu, scr + 0x10cu, scr + 0x114u, scr + 0x11cu, 1u };
    gcall(c, FN_TOGGLE, w, 5, a);
    MR32(w) = g_vt;
    uint32_t b[2] = { w, 1u };
    gcall(c, fn_add, scr, 2, b);
    fprintf(stderr, "units: Power Units row in the %s\n", fn_add == FN_ADD_PAUSE ? "pause menu" : "Gameplay options");
}
/* Speedometer Units changed: our row, right after it, shows the power's
 * units again while they follow it */
static void speedo_changed(CPU *c, uint32_t self){
    uint32_t nd = MR32(self + 4u), w = nd ? nd - 4u : 0;
    if (g_hp < 0 && g_vt && w && MR32(w) == g_vt) gcall(c, M_LABEL, w, 0, 0);
}

/* Called from guest_hook (debug.c); tools/gen_v2.sh lifts the hook sites. */
int powerunits_hook(CPU *c, uint32_t ip){
    switch (ip){
    case GA(0x004b7439u): add(c, c->esi, FN_ADD, 4u); return 1;   /* Options > Gameplay: after Speedometer Units, before Career Difficulty .. Save */
    case GA(0x004c3b3au): {                                        /* the pause menu's: Explore Map Mode (not in mode 2), Race Map Mode and Save follow */
        uint32_t m = gcall(c, FN_MODE, GA(0x0083aab4u), 0, 0);
        add(c, c->esi, FN_ADD_PAUSE, m == 2u ? 2u : 3u);
        return 1; }
    case GA(0x0049aeb6u):                                          /* Speedometer Units' method 1, its texts again */
    case GA(0x0049aed4u): speedo_changed(c, c->esi); return 1;
    case GA(0x0053d0fau):                                          /* "km/h?" (0x5EA8C0): the chart's power axis */
    case GA(0x0053d155u):                                          /*   the legend */
    case GA(0x0054a745u):                                          /*   the chart's maximum, its factor */
    case GA(0x0054a75fu):                                          /*   and label */
    case GA(0x0054ae4cu):                                          /*   a run's result, its factor */
    case GA(0x0054ae63u):                                          /*   and label */
        powerunits_install();
        if (g_hp >= 0) c->eax = (uint32_t)!g_hp;
        return 1;
    case GA(0x0053d4a6u):                                          /* "mph?" (0x5EA8B0): the chart's curve */
        powerunits_install();
        if (g_hp >= 0) c->eax = (uint32_t)g_hp;
        return 1;
    case GA(0x005626b8u):                                          /* a part's gain: km/h in bl */
        powerunits_install();
        if (g_hp >= 0) c->ebx = (c->ebx & ~0xffu) | (uint32_t)!g_hp;
        return 1;
    }
    return 0;
}
