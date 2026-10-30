/* intro.c -- the boot movies: skippable (default), original, or off.
 *
 *   NFSU2_INTRO=skippable | original | off
 *   NFSU2_INTRO_LOG=1   also log every message the boot-movie screens get
 *
 * The game boots through a list of front-end screens (tables 0x7f65e8 /
 * 0x7f6620, in the boot-flow object [0x836488] made by 0x4d9580): MC_Bootup,
 * LS_BlankMovie (blank.vp6), LS_EAlogo (ealogo.vp6), LS_THXMovie
 * (THX_logo.vp6), LS_PSAMovie (PSA.vp6), UG_LS_IntroFMV (FMVOpening.vp6),
 * UG_LS_Splash (the title).  Each movie screen ends in its
 * NotificationMessage handler (thiscall: msg, obj, p1, p2; ret 0x10), which
 * goes on to the next screen with 0x4c4f50:
 *
 *   0x4c53a0  LS_BlankMovie, LS_EAlogo, LS_THXMovie: only on 0xc3960eb9, the
 *             message the movie player posts when a movie ends (0x566100) or
 *             cannot be opened (0x566250).  Input is ignored: unskippable.
 *   0x4c53d0  LS_PSAMovie: on 0xc3960eb9 (sets [0x8383a8], saves the video
 *             options with 0x5beeb0, sets "boot done" [0x836494]); on
 *             PAD_ACCEPT/PAD_START only when the memory-card object
 *             [0x836498] has byte +5 set, i.e. a saved profile exists
 *             (0x4c618c, from 0x4a9c40).  First startup: unskippable.
 *   0x4c5330  UG_LS_IntroFMV: on 0xc3960eb9, PAD_ACCEPT or PAD_START.
 *
 * What reaches these handlers (cFEng 0x54d4c0 only sends a pad message that
 * the package has a response for): Enter, pad A and a left click arrive as
 * PAD_ACCEPT, pad Start as PAD_START.  Escape and pad B raise the joy event
 * FEPad_Back, but no boot package responds to PAD_BACK, so nothing arrives;
 * Space is no front-end key at all.
 *
 * skippable: PAD_ACCEPT/PAD_START (and PAD_BACK, should one come) end every
 * boot movie, and so does a new press of Escape, Space (the keyboard state,
 * metal_fill_keyboard) or pad B (gamepad_fill), seen on the screen's
 * per-frame tick 0xc98356ba.  Those three never produce PAD_ACCEPT/PAD_START
 * here, so one press ends one movie.  Where the game has its own skip (the
 * intro; the PSA with a profile) the screen gets PAD_ACCEPT; elsewhere it
 * gets 0xc3960eb9 and takes the same path as when its movie plays to the end
 * (the player is stopped by the package teardown, 0x511bc0, which posts
 * nothing).
 * off: the movie player's start (0x566030, called by the FE movie object
 * 0x566250 with "<dir>MOVIES\<name>.vp6", in the European build
 * "<name>_<language>.vp6") posts 0xc3960eb9 at once for the
 * boot movies instead of opening them, as 0x566030 itself does when
 * [0x8650a4] is set (and 0x566250 for a missing file, which WidescreenFix's
 * SkipIntro relies on).  Every screen then ends as after a full play.
 * original: none of this.  Story, tutorial and region movies (IG_PlayMovie)
 * are never touched; NOMOVIES=1 (fileio.c) still skips every movie.
 * Addresses are the European build's; GA() maps them (runtime/build_na.h).
 * Ported from th0mk's nfsu2-web runtime/intro.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

void metal_fill_keyboard(unsigned char *dst, unsigned n);
void gamepad_fill(unsigned char *dst);
long metal_frames(void);
uint32_t host_ms(void);
void sub_0055dc60(CPU *c);

#define MSG_PAD_ACCEPT 0x406415e3u   /* bStringHash("PAD_ACCEPT") */
#define MSG_PAD_START  0xb5af2461u   /* bStringHash("PAD_START") */
#define MSG_PAD_BACK   0x911ab364u   /* bStringHash("PAD_BACK") */
#define MSG_MOVIE_END  0xc3960eb9u   /* posted by the movie player */
#define MSG_TICK       0xc98356bau   /* every front-end update */
#define DIK_ESCAPE     0x01
#define DIK_SPACE      0x39
#define PAD_BTN_B      1             /* gamepad_fill: rgbButtons[1] */
#define MEMCARD        GA(0x00836498u)
#define BOOT_DONE      GA(0x00836494u)
#define FE_MANAGER     GA(0x008637b0u)

enum { INTRO_SKIPPABLE, INTRO_ORIGINAL, INTRO_OFF };
static int g_mode = -1, g_log;

static int intro_mode(void){
    if (g_mode < 0){
        const char *e = getenv("NFSU2_INTRO");
        g_mode = INTRO_SKIPPABLE;
        if (e && *e){
            if (!strcasecmp(e, "original")) g_mode = INTRO_ORIGINAL;
            else if (!strcasecmp(e, "off") || !strcmp(e, "0")) g_mode = INTRO_OFF;
            else if (strcasecmp(e, "skippable"))
                fprintf(stderr, "intro: NFSU2_INTRO=%s is not skippable, original or off; using skippable\n", e);
        }
        const char *l = getenv("NFSU2_INTRO_LOG"); g_log = l && *l && *l != '0';
        fprintf(stderr, "intro: boot movies %s\n",
                g_mode == INTRO_OFF ? "off" : g_mode == INTRO_ORIGINAL ? "as the game has them" : "skippable");
    }
    return g_mode;
}

static const char *msg_name(uint32_t m){
    switch (m){
    case MSG_PAD_ACCEPT: return "PAD_ACCEPT";
    case MSG_PAD_START:  return "PAD_START";
    case MSG_PAD_BACK:   return "PAD_BACK";
    case MSG_MOVIE_END:  return "movie end";
    default:             return 0;
    }
}
static int is_pad(uint32_t m){ return m == MSG_PAD_ACCEPT || m == MSG_PAD_START || m == MSG_PAD_BACK; }

/* NFSU2_INTRO_LOG=1: every message but the per-update tick */
static void trace(const char *who, uint32_t m){
    if (!g_log || m == MSG_TICK) return;
    const char *n = msg_name(m);
    if (n) fprintf(stderr, "intro: frame %ld, %s: %s\n", metal_frames(), who, n);
    else   fprintf(stderr, "intro: frame %ld, %s: 0x%08x\n", metal_frames(), who, m);
}

/* ---- presses the front end does not pass on: Escape, Space, pad B ---------
 * A key or button that goes down after the screen object got its first
 * message (a new object, or one that got nothing for half a second: a live
 * screen gets a tick every frame), so a press made before it (on the
 * previous movie, or held over) never ends it. */
static struct { uint32_t self, ms; unsigned char esc, space, b; } g_base;
static void held(unsigned char *esc, unsigned char *space, unsigned char *b){
    unsigned char k[256], p[272];
    metal_fill_keyboard(k, 256);
    gamepad_fill(p);
    *esc = k[DIK_ESCAPE] & 0x80; *space = k[DIK_SPACE] & 0x80; *b = p[0x30 + PAD_BTN_B] & 0x80;
}
static void rebase(uint32_t self){ g_base.self = self; held(&g_base.esc, &g_base.space, &g_base.b); }
static const char *new_press(void){
    unsigned char esc, space, b;
    held(&esc, &space, &b);
    const char *what = (esc && !g_base.esc) ? "Escape" : (space && !g_base.space) ? "Space"
                     : (b && !g_base.b) ? "pad B" : 0;
    g_base.esc = esc; g_base.space = space; g_base.b = b;
    return what;
}

/* The skip for one message: 0 = none, else the message the screen gets
 * instead.  own = the screen's own skip message (0: it has none). */
static uint32_t skip(CPU *c, const char *who, uint32_t own){
    uint32_t m = MR32(c->esp + 4u);
    intro_mode();
    trace(who, m);                       /* in every mode, so the unchanged game can be watched too */
    if (g_mode != INTRO_SKIPPABLE) return 0;
    uint32_t now = host_ms();
    if (c->ecx != g_base.self || now - g_base.ms > 500u) rebase(c->ecx);
    g_base.ms = now;
    const char *by = 0;
    if (is_pad(m)) by = msg_name(m);
    else if (m == MSG_TICK) by = new_press();
    if (!by) return 0;
    uint32_t to = own ? own : MSG_MOVIE_END;
    if (is_pad(m) && own && m != MSG_PAD_BACK) to = m;        /* the game's own skip, as is */
    fprintf(stderr, "intro: %s skipped by %s (%s)\n", who, by, msg_name(to));
    rebase(c->ecx);
    return to;
}

/* LS_BlankMovie, LS_EAlogo, LS_THXMovie */
void sub_004c53a0_orig(CPU *c);
void sub_004c53a0(CPU *c){
    uint32_t to = skip(c, "logo movie", 0);
    if (to) MR32(c->esp + 4u) = to;
    sub_004c53a0_orig(c);
}

/* LS_PSAMovie: its own skip needs a saved profile (byte +5 of the
 * memory-card object [0x836498], as 0x4c53ee tests) */
void sub_004c53d0_orig(CPU *c);
void sub_004c53d0(CPU *c){
    uint32_t mc = MR32(MEMCARD);
    uint32_t to = skip(c, "PSA movie", mc && MR8(mc + 5u) ? MSG_PAD_ACCEPT : 0);
    if (to) MR32(c->esp + 4u) = to;
    sub_004c53d0_orig(c);
}

/* UG_LS_IntroFMV (also the title screen's attract replay after 30 s) */
void sub_004c5330_orig(CPU *c);
void sub_004c5330(CPU *c){
    uint32_t to = skip(c, "intro movie", MSG_PAD_ACCEPT);
    if (to) MR32(c->esp + 4u) = to;
    sub_004c5330_orig(c);
}

/* ---- off ------------------------------------------------------------------ */
/* the boot movies by file name; blank.vp6 only while the boot is not done */
static int boot_movie(uint32_t path){
    if (!path || !mem_is_committed(path)) return 0;
    char p[128]; int n = 0;
    while (n < (int)sizeof p - 1 && mem_is_committed(path + (uint32_t)n) && MR8(path + (uint32_t)n)){
        p[n] = (char)MR8(path + (uint32_t)n); n++; }
    p[n] = 0;
    const char *b = p;
    for (const char *q = p; *q; q++) if (*q == '\\' || *q == '/') b = q + 1;
    size_t l = strlen(b);
    if (l > 4 && !strcasecmp(b + l - 4, ".vp6")) l -= 4;
    /* the European exe asks for the language's own first (ealogo_fr.vp6,
     * PSA_fr.vp6) and plays the plain one if that is missing */
    if (l > 3 && b[l - 3] == '_' && isalpha((unsigned char)b[l - 2]) && isalpha((unsigned char)b[l - 1])
        && strncasecmp(b, "blank", 5)) l -= 3;
    static const char *const names[] = { "ealogo", "THX_logo", "PSA", "FMVOpening" };
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++)
        if (strlen(names[i]) == l && !strncasecmp(b, names[i], l)) return 1;
    return l == 5 && !strncasecmp(b, "blank", 5) && !MR8(BOOT_DONE);
}

/* 0x566030(path, 1, flags), cdecl: start the movie player */
void sub_00566030_orig(CPU *c);
void sub_00566030(CPU *c){
    intro_mode();
    if (g_log){
        uint32_t p = MR32(c->esp + 4u);
        fprintf(stderr, "intro: frame %ld, movie start %s\n", metal_frames(),
                p && mem_is_committed(p) ? (const char *)(g_mem + p) : "?");
    }
    if (g_mode == INTRO_OFF && boot_movie(MR32(c->esp + 4u))){
        if (g_log) fprintf(stderr, "intro: frame %ld, movie not played (off)\n", metal_frames());
        /* as 0x56603a: FEManager (0x8637b0) ->QueueMessage(0xc3960eb9, 0)
         * (thiscall, ret 8); ecx comes back as it was (push/pop ecx) */
        uint32_t ecx = c->ecx;
        PUSH32(0u); PUSH32(MSG_MOVIE_END); c->ecx = FE_MANAGER;
        PUSH32(GA(0x0056604bu)); sub_0055dc60(c);
        c->ecx = ecx;
        POP32(c->eip);
        return;
    }
    sub_00566030_orig(c);
}
