/* autotest.c -- the scripted scenario runner (tests only).
 *
 * Everything here is driven from the GUEST thread at IDirect3DDevice9::
 * Present (autotest_on_present, com.c), in lock-step with the game's own
 * frames, so a script replays the same in windowed and headless runs.  Off
 * unless one of the variables below is set.
 *
 *   NFSU2_INPUT_SCRIPT=<file>   timed input script (format below)
 *   NFSU2_INPUT_SEQ=<steps>     the same runner from a one-line list (the
 *                               keyboard and pad scenarios, tests/input/ .seq files;
 *                               "Compact steps" below)
 *   NFSU2_QUIT_FRAMES=<n>       clean exit (reports) after n guest Present()s;
 *                               works headless too (QUITFRAMES counts host
 *                               frames and needs the window)
 *   NFSU2_TIMEOUT=<sec>         alias of ALARM (boot.c): exit after N s
 *   NFSU2_STATUS_EVERY=<n>      every n frames log: frame, wall time, guest
 *                               fps, GameFlowManager state [0x8654a4], CPU%,
 *                               guest heap
 *   NFSU2_LOG=<file>            stdout+stderr -> file (see autotest_early)
 *   NFSU2_FNG_LOG=1             log every change of the top front-end package
 *                               and of the current screen (3: also every press
 *                               of tapuntil/tappaduntil)
 *   NFSU2_CAR_TRACE=<file>      CSV of every race car per frame (car_trace)
 *
 * Game addresses in a script are European (as GA() in the runtime); on the
 * North American build each one is mapped through runtime/autotest_addrs.h
 * (tools/script_addrs.py lists every address the scripts in tests/ use, and
 * tools/addrmap.py maps them with the rest of the runtime's), so the same
 * script runs on both.  An address in the executable's range that the table
 * does not have is logged once and used as written.
 *
 * Script format: one event per line, '#' comments; ${NAME} is replaced by
 * the environment variable NAME (empty when unset).
 *     <when> <command> [args]
 *   <when>:  N | fN   absolute guest frame (Present count, 1-based)
 *            Nms      absolute ms since the first Present
 *            Nwms     game-world ms (the game's WorldTimer, counted while it
 *                     runs) since the last "wzero" (or the start): the same
 *                     driving input at any frame rate
 *            +N | +Nms | +Nwms  relative to the moment the previous line fired
 *   Lines fire strictly in order; a line never fires before the previous
 *   one (so "waitmem" blocks everything after it).
 *   commands:
 *     down KEY | up KEY        key state (DirectInput + WM_KEYDOWN/UP)
 *     tap KEY [frames]         down, release after frames (default 6)
 *     type TEXT                WM_CHAR + DI taps for each character
 *     dump [label]             write the next rendered frame as PNG (DUMPDIR)
 *     waitmem ADDR VAL [tmo]   wait until dword [ADDR]==VAL (tmo frames,
 *                              default unlimited); logs the result
 *     log TEXT                 marker line in the log
 *     waitfng NAME [tmo]       wait until the top front-end package, or the
 *                              current screen (the last "Init Package" /
 *                              "SwitchFEngPackages ... to" of the game's debug
 *                              printf, dinput_pad.c), is NAME
 *     tapuntil KEY NAME [every] [tmo]  tap KEY every `every` frames (default
 *                              90) until the top package is NAME
 *     peek ADDR [count]        log count dwords at ADDR on one line; ADDR
 *                              "@in+OFF" is relative to the player's input
 *                              controller (runtime/dinput_pad.c)
 *     in                       log the player car's input (steer, throttle,
 *                              brake, e-brake)
 *   synthetic game controller (runtime/gamepad.m; it goes through the same
 *   GameController -> DirectInput path as a real one):
 *     pad BUTTON down|up       button state; BUTTON = A B X Y LB RB BACK START
 *                              LS RS HOME DUP DDOWN DLEFT DRIGHT (or CROSS,
 *                              CIRCLE, SQUARE, TRIANGLE, L1, R1, VIEW, MENU...);
 *                              connects a virtual controller on first use
 *     pad connect|disconnect   plug / unplug the virtual controller
 *     tappad BUTTON [frames]   press, release after frames (default 6)
 *     axis LX|LY|RX|RY V       stick position, -1..1 (+X right, +Y down)
 *     trigger LT|RT V          trigger position, 0..1
 *     tappaduntil BUTTON NAME [every] [tmo]  like tapuntil, with a pad button
 *     padset ITEMS             the synthetic pad as NFSU2_PAD_FAKE sets it
 *                              (';' between items: A=1;LX=-0.5;PLUG=0 ...);
 *                              never plugs a pad in by itself
 *     padtap BUTTON [frames]   tap through padset (BUTTON=1, later BUTTON=0)
 *     padtapuntil BUTTON NAME [every] [tmo]  like tappaduntil, through padset
 *     poke ADDR VAL            write dword VAL to ADDR
 *     wzero [now]              world-time origin for absolute Nwms lines: the
 *                              start of the current race (GameFlow 6) when
 *                              racing, else (or with "now") the current time
 *     photo WHAT [ARGS]        photo mode (photo.c photo_script: on, off,
 *                              orbit, free, turn X Y ...)
 *     headlights MODE          the other cars' headlights (headlights.c):
 *                              NFSU2_HEADLIGHTS's modes, for an A/B in one run
 *     status [label]           print a [status] line now (memory trend points)
 *     stall SECONDS            block the guest thread (lock held) to exercise
 *                              the stall watchdog (watchdog.c)
 *     loop N                   repeat the lines up to the matching "endloop"
 *     endloop                  N times (loops may nest; N=0 means forever)
 *     trace EVERY NAME=EXPR... log the expressions every EVERY frames (one
 *                              "[trace]" line; up to 24; replaces the last set).
 *                              EXPR = [TYPE:]ADDR, ADDR = number | [ADDR] |
 *                              ADDR+number | ADDR-number, where [X] reads the
 *                              dword at X.  TYPE f (float, default), i (int32),
 *                              x (hex dword), b (byte), w (word), d (double).
 *                              $P is the local human racer of the current race
 *                              (GRaceStatus [0x890118]: racer pointers at
 *                              +0xBD0, count +0x24; driver type [[[r]+0x14]+4]
 *                              == 1), $R0..$R9 racer slot i, 0 if none.
 *     untrace                  stop the periodic trace
 *     expect EXPR OP VALUE     check once: logs "[expect] PASS|FAIL ..."
 *                              (tests/run_suite.sh fails a run on FAIL).
 *                              EXPR as in trace, OP one of > >= < <= == !=
 *     mark NAME EXPR           remember the value of EXPR as @NAME; VALUE in
 *                              expect/waitexpr may be @NAME or @NAME+number,
 *                              and EXPR may be @NAME
 *     edge NAME EXPR OP VALUE  from now on, every frame: count the frames where
 *                              the condition becomes true into @NAME (up to 8)
 *     waitexpr EXPR OP VALUE [tmo]  wait until the condition holds
 *     click X Y                a left click at X, Y (fractions of the window
 *                              content from the top left), released 8 frames
 *                              later (through the real mouse path)
 *     srvcycle N [MS]          LAN hosting test: N times start the lifted
 *                              server.dll through the game's own glue, keep it
 *                              running MS ms, stop and unload it; logs
 *                              "[srvcycle]" per cycle (threads, sockets, fds,
 *                              TLS, object slots) and an [expect] PASS|FAIL
 *     quit                     clean exit
 *     close                    what Cmd-Q / the close button do: WM_CLOSE to
 *                              the game, which then shuts itself down
 *     blur MS                  the app loses the focus for MS ms (as Cmd-Tab
 *                              away and back; lifecycle.c decides what the
 *                              game does meanwhile)
 *     audioreset               handle a default output device change now
 *     roam SUB ...             the old fork's free-roam research probes: only
 *                              the ones career.c also has are kept (waitroam,
 *                              shopgo, teleport, peek, wait, memdump, call,
 *                              racesay)
 *   career aids (runtime/career.c, test-only): call, memdump, waitx, peekx,
 *   teleport, autopilot, racewin, careerlist, careergo, shopgo, showgo,
 *   fnglist, waitfe, tapfe, waitroam, cargo, outrun, outrunwin, visual,
 *   watchw, bot, racesay.
 *   real-keyboard path (runtime/keyboard_mac.m): NSEvents are made and posted
 *   into AppKit's event queue on the main thread, so they go through the
 *   same handler as keys typed on a real keyboard:
 *     nsdown KEY | nsup KEY    key down / up; KEY = position name as above
 *                              (A = the key in the US A position), LCMD,
 *                              RCMD, LOPTION, ROPTION, CAPSLOCK, FN, or
 *                              kc:0xNN (a mac key code); "cmd+", "shift+",
 *                              "ctrl+", "opt+" prefixes hold modifiers
 *     nstap KEY [frames]       down, up after frames (default 6)
 *     nstapuntil KEY NAME [every] [tmo]  like tapuntil, with nstap
 *     nsrepeat KEY [n]         n autorepeat key downs (default 5), one every
 *                              2 frames, for a key that is down
 *     nstype TEXT              type characters on the keyboard layout in use
 *                              (NFSU2_KEYLAYOUT can pick another), Shift and
 *                              Option pressed as needed; one every 4 frames
 *                              (nstype8: one every 8 frames)
 *     nsfocus out|in           the app loses / regains focus
 *     nsmouse move X Y         mouse at X, Y (fractions of the window)
 *     nsmouse down|up L|R|M    mouse buttons;  nsmouse scroll DY  (lines)
 *     shot                     the app's own capture (Cmd+Shift+D)
 *   KEY: DIK name (RETURN ENTER ESCAPE UP DOWN LEFT RIGHT SPACE BACK TAB
 *        LSHIFT RSHIFT LCONTROL RCONTROL LMENU RMENU A..Z 0..9 F1..F12
 *        NUMPAD0..9 ...), or a number (0x1c = DIK code), or VK_xx / vk:0xNN.
 *
 * Compact steps (NFSU2_INPUT_SEQ="<when>:<action>,<when>:<action>,...";
 * tests/input/run.sh builds it from a .seq file).  <when> is a frame or +n;
 * each action becomes the script line in brackets:
 *   <key>[:<hold>] [nstap]   down:<key> [nsdown]   up:<key> [nsup]
 *   type:<text> [nstype8; '_' = space]   focus:out|in [nsfocus]
 *   wait:<pkg>[:<max>] [waitfng, max 3000]
 *   until:<key>:<pkg>[:<every>] [nstapuntil, every 120, at most 4000 frames]
 *   pad:<items> [padset]   padtap:<button>[:<hold>] [padtap]
 *   untilpad:<button>:<pkg>[:<every>] [padtapuntil]   shot   in
 *   peek:<hex addr>[:<n>] [peek]   log:<text> [log]
 *
 * Ported from th0mk's nfsu2-web runtime/autotest.c (MIT).
 */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <sys/resource.h>
#include "gamepad.h"
#include "kbd.h"
void gamepad_synth_items(const char *items);       /* gamepad.m: NFSU2_PAD_FAKE items */

#define G_FLOW        GA(0x008654a4u)   /* GameFlowManager state: 3 front end, 4/5 loading, 6 in the world */
#define G_FE_MGR      GA(0x008384c4u)   /* cFEng::pInstance (GetTopPackage reads [[+8]+0xE4]) */
#define G_RACE        GA(0x00890118u)   /* GRaceStatus: +0x24 racer count, +0xBD0 racers by position */
#define G_WORLDTIMER  GA(0x00865188u)   /* WorldTimer, 1/4000 s (stops while paused) */
#define G_REALTIMER   GA(0x008651a8u)   /* RealTimer, 1/4000 s */
#define G_FRAMECAP    GA(0x00865558u)   /* the frame-rate cap's frame time (float s) */
#define G_WORLD       GA(0x00890080u)   /* the race World: +0x10 car count, +0x1C car pointers */

/* ---- script addresses: European -> this build ------------------------------- */
static const uint32_t k_addr[][2] = {
#include "autotest_addrs.h"
};
static uint32_t map_addr(uint32_t a, int line){
    if (a < 0x00401000u || a >= 0x00a00000u) return a;
    for (unsigned i = 0; i < sizeof k_addr / sizeof *k_addr; i++) if (k_addr[i][0] == a) return k_addr[i][1];
#ifdef NFS_EXE_NA
    static uint32_t warned[64]; static int nw;
    for (int i = 0; i < nw; i++) if (warned[i] == a) return a;
    if (nw < 64) warned[nw++] = a;
    fprintf(stderr, "[autotest] line %d: 0x%08x is not in runtime/autotest_addrs.h (tools/script_addrs.py): used as written\n", line, a);
#endif
    (void)line;
    return a;
}
/* every hex number in the executable's range in a script line, mapped */
static void map_line(char *s, size_t cap, int line){
    char out[2048]; size_t o = 0;
    for (const char *p = s; *p && o + 16 < sizeof out; ){
        if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X') && isxdigit((unsigned char)p[2]) &&
            (p == s || !isalnum((unsigned char)p[-1]))){
            char *e; uint32_t v = (uint32_t)strtoul(p, &e, 16);
            uint32_t m = map_addr(v, line);
            if (m != v){ o += (size_t)snprintf(out + o, sizeof out - o, "0x%x", m); p = e; continue; }
            while (p < e && o + 1 < sizeof out) out[o++] = *p++;
            continue;
        }
        out[o++] = *p++;
    }
    out[o] = 0;
    snprintf(s, cap, "%s", out);
}

/* ---- key tables ------------------------------------------------------- */
typedef struct { const char *nm; unsigned char dik, vk; char ch; } KeyDef;
static const KeyDef K[] = {
    {"ESCAPE",0x01,0x1B,0x1B},{"ESC",0x01,0x1B,0x1B},
    {"1",0x02,'1','1'},{"2",0x03,'2','2'},{"3",0x04,'3','3'},{"4",0x05,'4','4'},
    {"5",0x06,'5','5'},{"6",0x07,'6','6'},{"7",0x08,'7','7'},{"8",0x09,'8','8'},
    {"9",0x0A,'9','9'},{"0",0x0B,'0','0'},{"MINUS",0x0C,0xBD,'-'},{"EQUALS",0x0D,0xBB,'='},
    {"BACK",0x0E,0x08,0x08},{"BACKSPACE",0x0E,0x08,0x08},{"TAB",0x0F,0x09,0x09},
    {"Q",0x10,'Q','q'},{"W",0x11,'W','w'},{"E",0x12,'E','e'},{"R",0x13,'R','r'},
    {"T",0x14,'T','t'},{"Y",0x15,'Y','y'},{"U",0x16,'U','u'},{"I",0x17,'I','i'},
    {"O",0x18,'O','o'},{"P",0x19,'P','p'},{"LBRACKET",0x1A,0xDB,'['},{"RBRACKET",0x1B,0xDD,']'},
    {"RETURN",0x1C,0x0D,0x0D},{"ENTER",0x1C,0x0D,0x0D},{"LCONTROL",0x1D,0x11,0},{"CTRL",0x1D,0x11,0},
    {"A",0x1E,'A','a'},{"S",0x1F,'S','s'},{"D",0x20,'D','d'},{"F",0x21,'F','f'},
    {"G",0x22,'G','g'},{"H",0x23,'H','h'},{"J",0x24,'J','j'},{"K",0x25,'K','k'},
    {"L",0x26,'L','l'},{"SEMICOLON",0x27,0xBA,';'},{"APOSTROPHE",0x28,0xDE,'\''},
    {"GRAVE",0x29,0xC0,'`'},{"LSHIFT",0x2A,0x10,0},{"SHIFT",0x2A,0x10,0},{"BACKSLASH",0x2B,0xDC,'\\'},
    {"Z",0x2C,'Z','z'},{"X",0x2D,'X','x'},{"C",0x2E,'C','c'},{"V",0x2F,'V','v'},
    {"B",0x30,'B','b'},{"N",0x31,'N','n'},{"M",0x32,'M','m'},{"COMMA",0x33,0xBC,','},
    {"PERIOD",0x34,0xBE,'.'},{"SLASH",0x35,0xBF,'/'},{"RSHIFT",0x36,0x10,0},
    {"MULTIPLY",0x37,0x6A,'*'},{"LMENU",0x38,0x12,0},{"ALT",0x38,0x12,0},{"SPACE",0x39,0x20,' '},
    {"CAPITAL",0x3A,0x14,0},
    {"F1",0x3B,0x70,0},{"F2",0x3C,0x71,0},{"F3",0x3D,0x72,0},{"F4",0x3E,0x73,0},
    {"F5",0x3F,0x74,0},{"F6",0x40,0x75,0},{"F7",0x41,0x76,0},{"F8",0x42,0x77,0},
    {"F9",0x43,0x78,0},{"F10",0x44,0x79,0},{"F11",0x57,0x7A,0},{"F12",0x58,0x7B,0},
    {"NUMPAD7",0x47,0x67,'7'},{"NUMPAD8",0x48,0x68,'8'},{"NUMPAD9",0x49,0x69,'9'},
    {"SUBTRACT",0x4A,0x6D,'-'},{"NUMPAD4",0x4B,0x64,'4'},{"NUMPAD5",0x4C,0x65,'5'},
    {"NUMPAD6",0x4D,0x66,'6'},{"ADD",0x4E,0x6B,'+'},{"NUMPAD1",0x4F,0x61,'1'},
    {"NUMPAD2",0x50,0x62,'2'},{"NUMPAD3",0x51,0x63,'3'},{"NUMPAD0",0x52,0x60,'0'},
    {"DECIMAL",0x53,0x6E,'.'},{"NUMPADENTER",0x9C,0x0D,0x0D},{"RCONTROL",0x9D,0x11,0},
    {"DIVIDE",0xB5,0x6F,'/'},{"RMENU",0xB8,0x12,0},{"PAUSE",0xC5,0x13,0},
    {"HOME",0xC7,0x24,0},{"UP",0xC8,0x26,0},{"PRIOR",0xC9,0x21,0},{"PGUP",0xC9,0x21,0},
    {"LEFT",0xCB,0x25,0},{"RIGHT",0xCD,0x27,0},{"END",0xCF,0x23,0},{"DOWN",0xD0,0x28,0},
    {"NEXT",0xD1,0x22,0},{"PGDN",0xD1,0x22,0},{"INSERT",0xD2,0x2D,0},{"DELETE",0xD3,0x2E,0},
};
#define NK (int)(sizeof K / sizeof *K)
static const KeyDef *key_by_dik(unsigned dik){
    for (int i = 0; i < NK; i++) if (K[i].dik == dik) return &K[i];
    return 0;
}
static int parse_key(const char *s, unsigned *dik){
    if (!strncasecmp(s, "DIK_", 4)) s += 4;
    if (!strncasecmp(s, "VK_", 3) || !strncasecmp(s, "vk:", 3)){
        unsigned vk = 0; const char *p = s + 3;
        if (isdigit((unsigned char)*p)) vk = (unsigned)strtoul(p, 0, 0);
        else for (int i = 0; i < NK; i++) if (!strcasecmp(K[i].nm, p)){ vk = K[i].vk; break; }
        for (int i = 0; i < NK; i++) if (K[i].vk == vk){ *dik = K[i].dik; return 1; }
        return 0;
    }
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')){ *dik = (unsigned)strtoul(s, 0, 16) & 0xFFu; return 1; }
    for (int i = 0; i < NK; i++) if (!strcasecmp(K[i].nm, s)){ *dik = K[i].dik; return 1; }
    if (isdigit((unsigned char)s[0])){ *dik = (unsigned)strtoul(s, 0, 0) & 0xFFu; return 1; }
    return 0;
}

/* ---- injected input (DirectInput state: runtime/keyboard.c) ------------- */
void win32_post_message(uint32_t msg, uint32_t wp, uint32_t lp);   /* win32_ext.c: the guest's message queue */
static void key_event(unsigned dik, int down){
    kbd_set_key(KSRC_SCRIPT, dik & 0xFFu, down);
    const KeyDef *k = key_by_dik(dik);
    if (!k) return;
    uint32_t lp = 1u | ((uint32_t)(dik & 0x7Fu) << 16) | ((dik & 0x80u) ? (1u << 24) : 0u);
    if (down){
        win32_post_message(0x0100u, k->vk, lp);              /* WM_KEYDOWN */
        if (k->ch) win32_post_message(0x0102u, (uint32_t)(unsigned char)k->ch, lp);   /* WM_CHAR */
    } else win32_post_message(0x0101u, k->vk, lp | 0xC0000000u);  /* WM_KEYUP */
}

/* ---- script ----------------------------------------------------------- */
enum { C_DOWN, C_UP, C_TAP, C_TYPE, C_DUMP, C_WAITMEM, C_LOG, C_QUIT, C_PEEK, C_POKE, C_WAITFNG, C_TAPUNTIL,
       C_CLOSE, C_BLUR, C_AUDIORESET, C_WZERO, C_HEADLIGHTS,
       C_PAD, C_TAPPAD, C_AXIS, C_TAPPADUNTIL, C_PADSET, C_PADTAP, C_PADTAPUNTIL, C_IN, C_SHOT,
       C_NSDOWN, C_NSUP, C_NSTAP, C_NSREPEAT, C_NSTYPE, C_NSFOCUS, C_NSMOUSE, C_NSTAPUNTIL,
       C_LOOP, C_ENDLOOP, C_STATUS, C_STALL, C_CAREER,
       C_TRACE, C_UNTRACE, C_EXPECT, C_WAITEXPR, C_MARK, C_EDGE, C_CLICK, C_PHOTO, C_SRVCYCLE };
#define PAD_PLUG 0xFFFFu           /* C_PAD: "pad connect|disconnect" */
/* career.c: test-only career aids (call, memdump, waitx, teleport, autopilot ...) */
int career_is_cmd(const char *cmd);
int career_cmd(CPU *c, const char *line, long *wait_start);
typedef struct {
    int rel, ms; long t;           /* timing */
    int cmd; unsigned key; long n; uint32_t addr, val; float fv;
    char text[200]; int line;
    char *xtext;                   /* trace, mark, edge, expect, waitexpr: the expressions */
} Ev;
static Ev   *g_ev; static int g_nev, g_iev, g_evcap;
static long  g_last_fire_f = 0; static double g_last_fire_ms = 0, g_last_fire_wms = 0, g_wzero = 0;
static long  g_wait_start = -1;
typedef struct { unsigned dik; long at; } Rel;
static Rel   g_rel[64]; static int g_nrel;
static Rel   g_prel[32]; static int g_nprel;   /* pad button releases */
static struct { char key[24]; long at; } g_irel[16]; static int g_nirel;   /* padtap releases */
/* NSEvent synthesis (ns* commands): scheduled requests, fired in order */
typedef struct { long at; int type; char key[40]; uint32_t ch; double a, b; } NsReq;
static NsReq g_nsq[1024]; static int g_nnsq;
static void ns_sched(long at, int type, const char *key, uint32_t ch, double a, double b){
    if (g_nnsq >= 1024){ fprintf(stderr, "[autotest] ns queue full\n"); return; }
    NsReq *q = &g_nsq[g_nnsq++];
    q->at = at; q->type = type; q->ch = ch; q->a = a; q->b = b;
    snprintf(q->key, sizeof q->key, "%s", key ? key : "");
}
static void ns_fire(const NsReq *q){
    int ok = 1;
    switch (q->type){
    case KSYN_DOWN: case KSYN_UP: case KSYN_REPEAT: ok = kbdmac_synth_key(q->type, q->key); break;
    case KSYN_CHAR_DOWN: case KSYN_CHAR_UP: ok = kbdmac_synth_char(q->type, q->ch); break;
    default: kbdmac_synth_simple(q->type, q->a, q->b); break;
    }
    if (!ok){
        if (q->type == KSYN_CHAR_DOWN) fprintf(stderr, "[autotest] nstype: no key types U+%04X on this layout\n", q->ch);
        else if (q->type != KSYN_CHAR_UP) fprintf(stderr, "[autotest] ns: unknown key '%s'\n", q->key);
    }
}
/* UTF-8 -> code point; advances *p */
static uint32_t utf8_next(const char **p){
    const unsigned char *s = (const unsigned char *)*p;
    uint32_t c = s[0]; int n = 0;
    if (c >= 0xF0 && c < 0xF8){ c &= 0x07; n = 3; }
    else if (c >= 0xE0){ c &= 0x0F; n = 2; }
    else if (c >= 0xC0){ c &= 0x1F; n = 1; }
    else if (c >= 0x80){ (*p)++; return 0xFFFD; }
    s++;
    for (int i = 0; i < n; i++, s++){ if ((*s & 0xC0) != 0x80) break; c = (c << 6) | (*s & 0x3F); }
    *p = (const char *)s;
    return c;
}
/* "type": characters still to send */
static char  g_type_q[256]; static int g_type_h, g_type_t; static long g_type_next;

static long   g_frame = 0;               /* guest Present count */
static int    g_fng_log = 0;
static double g_t0 = 0;                  /* ms at first Present */
static long   g_quit_frames = 0, g_status_every = 0;
static int    g_inited = 0;

static double now_ms(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

/* ---- world time ("Nwms", "wzero"): the game's WorldTimer while it runs ---- */
static double g_wms, g_race_start = -1; static uint32_t g_wt_last; static int g_wt_have;
static void world_tick(void){
    if (!mem_is_committed(G_WORLDTIMER + 3u)) return;
    uint32_t t = MR32(G_WORLDTIMER);
    if (g_wt_have && t > g_wt_last && t - g_wt_last < 4000u * 5u) g_wms += (t - g_wt_last) / 4.0;
    g_wt_last = t; g_wt_have = 1;
    static uint32_t last_flow;
    uint32_t fl = mem_is_committed(G_FLOW + 3u) ? MR32(G_FLOW) : 0u;
    if (fl == 6u && last_flow != 6u) g_race_start = g_wms;
    if (fl != 6u) g_race_start = -1;
    last_flow = fl;
}
static double world_ms(void){ return g_wms; }

/* ${NAME} -> getenv("NAME").  The result is as long as a script line may be. */
static void expand_env(char *line, size_t cap){
    char out[2048]; size_t o = 0;
    for (const char *p = line; *p && o + 1 < sizeof out; ){
        const char *e;
        if (p[0] == '$' && p[1] == '{' && (e = strchr(p + 2, '}'))){
            char nm[64]; size_t n = (size_t)(e - p - 2);
            if (n >= sizeof nm) n = sizeof nm - 1;
            memcpy(nm, p + 2, n); nm[n] = 0;
            const char *v = getenv(nm);
            for (; v && *v && o + 1 < sizeof out; v++) out[o++] = *v;
            p = e + 1;
        } else out[o++] = *p++;
    }
    out[o] = 0;
    snprintf(line, cap, "%s", out);
}

/* the rest of a line after `skip` words */
static const char *after_words(const char *s, int skip){
    for (int i = 0; i < skip; i++){
        while (isspace((unsigned char)*s)) s++;
        while (*s && !isspace((unsigned char)*s)) s++;
    }
    while (isspace((unsigned char)*s)) s++;
    return s;
}
/* One script line (already without its comment).  0 = nothing to add. */
static int add_line(char *p, int ln){
    map_line(p, 2048, ln);
    Ev e; memset(&e, 0, sizeof e); e.line = ln;
    char when[32] = {0}, cmd[32] = {0}; int used = 0;
    if (sscanf(p, "%31s %31s %n", when, cmd, &used) < 2){
        fprintf(stderr, "[autotest] script line %d: parse error\n", ln); return 0; }
    char *rest = p + used; rest[strcspn(rest, "\r\n")] = 0;
    const char *w = when;
    if (*w == '+'){ e.rel = 1; w++; }
    if (*w == 'f' || *w == 'F') w++;
    e.t = strtol(w, (char**)&w, 10);
    if (!strncasecmp(w, "ms", 2)) e.ms = 1;
    else if (!strncasecmp(w, "wms", 3)) e.ms = 2;
    char a1[64] = {0}, a2[64] = {0}, a3[64] = {0}, a4[32] = {0};
    sscanf(rest, "%63s %63s %63s %31s", a1, a2, a3, a4);
    if      (!strcasecmp(cmd, "down")) e.cmd = C_DOWN;
    else if (!strcasecmp(cmd, "up"))   e.cmd = C_UP;
    else if (!strcasecmp(cmd, "tap"))  { e.cmd = C_TAP; e.n = a2[0] ? atol(a2) : 6; }
    else if (!strcasecmp(cmd, "type")) { e.cmd = C_TYPE; snprintf(e.text, sizeof e.text, "%s", rest); }
    else if (!strcasecmp(cmd, "dump")) { e.cmd = C_DUMP; snprintf(e.text, sizeof e.text, "%s", a1); }
    else if (!strcasecmp(cmd, "shot")) e.cmd = C_SHOT;
    else if (!strcasecmp(cmd, "in"))   e.cmd = C_IN;
    else if (!strcasecmp(cmd, "log"))  { e.cmd = C_LOG;  snprintf(e.text, sizeof e.text, "%s", rest); }
    else if (!strcasecmp(cmd, "quit")) e.cmd = C_QUIT;
    else if (!strcasecmp(cmd, "close")) e.cmd = C_CLOSE;
    else if (!strcasecmp(cmd, "blur")) { e.cmd = C_BLUR; e.n = a1[0] ? atol(a1) : 3000; }
    else if (!strcasecmp(cmd, "audioreset")) e.cmd = C_AUDIORESET;
    else if (!strcasecmp(cmd, "wzero")){ e.cmd = C_WZERO; e.n = !strcasecmp(a1, "now"); }
    else if (!strcasecmp(cmd, "trace")) { e.cmd = C_TRACE; e.n = atol(a1); e.xtext = strdup(after_words(rest, 1)); }
    else if (!strcasecmp(cmd, "untrace")) e.cmd = C_UNTRACE;
    else if (!strcasecmp(cmd, "mark")){ e.cmd = C_MARK; snprintf(e.text, sizeof e.text, "%s", a1); e.xtext = strdup(a2); }
    else if (!strcasecmp(cmd, "edge")){ e.cmd = C_EDGE; snprintf(e.text, sizeof e.text, "%s", a1);
        e.xtext = strdup(after_words(rest, 1)); }
    else if (!strcasecmp(cmd, "expect") || !strcasecmp(cmd, "waitexpr")){
        e.cmd = !strcasecmp(cmd, "expect") ? C_EXPECT : C_WAITEXPR;
        e.xtext = strdup(rest);
        if (e.cmd == C_WAITEXPR) e.n = a4[0] ? atol(a4) : 0; }
    else if (!strcasecmp(cmd, "click")) { e.cmd = C_CLICK; e.fv = (float)atof(a1); e.val = (uint32_t)(atof(a2) * 1e6); }
    else if (!strcasecmp(cmd, "srvcycle")) { e.cmd = C_SRVCYCLE; e.n = a1[0] ? atol(a1) : 1; e.val = a2[0] ? (uint32_t)atol(a2) : 0u; }
    else if (!strcasecmp(cmd, "headlights")) { e.cmd = C_HEADLIGHTS; snprintf(e.text, sizeof e.text, "%s", a1); }
    else if (!strcasecmp(cmd, "photo")) { e.cmd = C_PHOTO; snprintf(e.text, sizeof e.text, "%s", rest); }
    else if (!strcasecmp(cmd, "waitfng")){ e.cmd = C_WAITFNG;
        snprintf(e.text, sizeof e.text, "%s", a1); e.n = a2[0] ? atol(a2) : 0; }
    else if (!strcasecmp(cmd, "tapuntil")){ e.cmd = C_TAPUNTIL;
        if (!parse_key(a1, &e.key)){ fprintf(stderr, "[autotest] script line %d: unknown key '%s'\n", ln, a1); return 0; }
        snprintf(e.text, sizeof e.text, "%s", a2);
        e.val = a3[0] ? (uint32_t)atol(a3) : 90u; e.n = a4[0] ? atol(a4) : 0; }
    else if (!strcasecmp(cmd, "peek")){ e.cmd = C_PEEK;
        if (!strncasecmp(a1, "@in", 3)){ e.val = 1; e.addr = (uint32_t)strtoul(a1 + 3, 0, 0); }
        else e.addr = (uint32_t)strtoul(a1, 0, 0);
        e.n = a2[0] ? atol(a2) : 1; if (e.n < 1 || e.n > 64) e.n = 1; }
    else if (!strcasecmp(cmd, "poke")){ e.cmd = C_POKE; e.addr = (uint32_t)strtoul(a1, 0, 0);
        e.val = (uint32_t)strtoul(a2, 0, 0); }
    else if (!strcasecmp(cmd, "loop")){ e.cmd = C_LOOP; e.n = atol(a1); }
    else if (!strcasecmp(cmd, "endloop")) e.cmd = C_ENDLOOP;
    else if (!strcasecmp(cmd, "status")){ e.cmd = C_STATUS; snprintf(e.text, sizeof e.text, "%s", a1); }
    else if (!strcasecmp(cmd, "stall")){ e.cmd = C_STALL; e.n = atol(a1); }
    else if (!strcasecmp(cmd, "waitmem")){ e.cmd = C_WAITMEM;
        e.addr = (uint32_t)strtoul(a1, 0, 0); e.val = (uint32_t)strtoul(a2, 0, 0);
        e.n = a3[0] ? atol(a3) : 0; }
    else if (!strcasecmp(cmd, "pad")){ e.cmd = C_PAD;
        if (!strcasecmp(a1, "connect") || !strcasecmp(a1, "disconnect")){
            if (!strcasecmp(a2, "wheel")){ fprintf(stderr, "[autotest] script line %d: no steering wheel device in this port\n", ln); return 0; }
            e.key = PAD_PLUG; e.n = !strcasecmp(a1, "connect"); }
        else { int b = gamepad_button_by_name(a1);
            if (b < 0){ fprintf(stderr, "[autotest] script line %d: unknown pad button '%s'\n", ln, a1); return 0; }
            e.key = (unsigned)b; e.n = strcasecmp(a2, "up") != 0; } }
    else if (!strcasecmp(cmd, "padset")){ e.cmd = C_PADSET; snprintf(e.text, sizeof e.text, "%s", a1); }
    else if (!strcasecmp(cmd, "padtap") || !strcasecmp(cmd, "padtapuntil")){
        snprintf(e.text, sizeof e.text, "%s", a1);
        if (cmd[6]){ e.cmd = C_PADTAPUNTIL; snprintf(e.text + 48, sizeof e.text - 48, "%s", a2);
            e.val = a3[0] ? (uint32_t)atol(a3) : 90u; e.n = a4[0] ? atol(a4) : 0; }
        else { e.cmd = C_PADTAP; e.n = a2[0] ? atol(a2) : 6; } }
    else if (!strcasecmp(cmd, "tappad") || !strcasecmp(cmd, "tappaduntil")){
        int b = gamepad_button_by_name(a1);
        if (b < 0){ fprintf(stderr, "[autotest] script line %d: unknown pad button '%s'\n", ln, a1); return 0; }
        e.key = (unsigned)b;
        if (cmd[6]){ e.cmd = C_TAPPADUNTIL; snprintf(e.text, sizeof e.text, "%s", a2);
            e.val = a3[0] ? (uint32_t)atol(a3) : 90u; e.n = a4[0] ? atol(a4) : 0; }
        else { e.cmd = C_TAPPAD; e.n = a2[0] ? atol(a2) : 6; } }
    else if (!strcasecmp(cmd, "axis") || !strcasecmp(cmd, "trigger")){ e.cmd = C_AXIS;
        int ax = gamepad_axis_by_name(a1);
        if (ax < 0 || (cmd[0] == 't' || cmd[0] == 'T') != (ax >= PAD_AXIS_LT)){
            fprintf(stderr, "[autotest] script line %d: unknown %s '%s'\n", ln, cmd, a1); return 0; }
        e.key = (unsigned)ax; e.fv = (float)atof(a2); }
    else if (!strcasecmp(cmd, "nsdown") || !strcasecmp(cmd, "nsup") || !strcasecmp(cmd, "nstap") ||
             !strcasecmp(cmd, "nsrepeat")){
        e.cmd = !strcasecmp(cmd, "nsdown") ? C_NSDOWN : !strcasecmp(cmd, "nsup") ? C_NSUP
              : !strcasecmp(cmd, "nstap") ? C_NSTAP : C_NSREPEAT;
        if (!a1[0]){ fprintf(stderr, "[autotest] script line %d: %s needs a key\n", ln, cmd); return 0; }
        snprintf(e.text, sizeof e.text, "%s", a1);
        e.n = a2[0] ? atol(a2) : (e.cmd == C_NSTAP ? 6 : 5); }
    else if (!strcasecmp(cmd, "nstapuntil")){ e.cmd = C_NSTAPUNTIL;
        snprintf(e.text, sizeof e.text, "%s", a1); snprintf(e.text + 48, sizeof e.text - 48, "%s", a2);
        e.val = a3[0] ? (uint32_t)atol(a3) : 90u; e.n = a4[0] ? atol(a4) : 0; }
    else if (!strcasecmp(cmd, "nstype") || !strcasecmp(cmd, "nstype8")){ e.cmd = C_NSTYPE;
        e.n = cmd[6] == '8' ? 8 : 4;
        snprintf(e.text, sizeof e.text, "%s", rest);
        for (size_t l = strlen(e.text); l && (e.text[l - 1] == ' ' || e.text[l - 1] == '\t'); ) e.text[--l] = 0; }
    else if (!strcasecmp(cmd, "nsfocus")){ e.cmd = C_NSFOCUS; e.n = !strcasecmp(a1, "in"); }
    else if (!strcasecmp(cmd, "nsmouse")){ e.cmd = C_NSMOUSE;
        if (!strcasecmp(a1, "move")){ e.n = KSYN_MOUSE_MOVE; e.fv = (float)atof(a2); snprintf(e.text, sizeof e.text, "%s", a3); }
        else if (!strcasecmp(a1, "down") || !strcasecmp(a1, "up")){
            e.n = !strcasecmp(a1, "down") ? KSYN_MOUSE_DOWN : KSYN_MOUSE_UP;
            e.fv = (float)(a2[0] == 'R' || a2[0] == 'r' ? 1 : a2[0] == 'M' || a2[0] == 'm' ? 2 : 0); }
        else if (!strcasecmp(a1, "scroll")){ e.n = KSYN_SCROLL; e.fv = (float)atof(a2); }
        else { fprintf(stderr, "[autotest] script line %d: nsmouse move|down|up|scroll\n", ln); return 0; } }
    else if (!strcasecmp(cmd, "roam")){
        /* the probes career.c also has */
        static const char *const keep[][2] = { {"waitroam","waitroam"}, {"shopgo","shopgo"}, {"teleport","teleport"},
                                               {"peek","peekx"}, {"wait","waitx"}, {"memdump","memdump"}, {"call","call"},
                                               {"racesay","racesay"}, {0,0} };
        int k; for (k = 0; keep[k][0] && strcasecmp(keep[k][0], a1); k++) ;
        if (!keep[k][0]){ fprintf(stderr, "[autotest] script line %d: 'roam %s' is a free-roam research probe of the old fork, "
                                          "not in this port\n", ln, a1); return 0; }
        e.cmd = C_CAREER; snprintf(e.text, sizeof e.text, "%s %s", keep[k][1], after_words(rest, 1)); }
    else if (!strcasecmp(cmd, "displayhz") || !strcasecmp(cmd, "texrep") || !strcasecmp(cmd, "covreset") ||
             !strcasecmp(cmd, "covdump") || !strcasecmp(cmd, "audiostall")){
        fprintf(stderr, "[autotest] script line %d: '%s' is not available in this port (skipped)\n", ln, cmd); return 0; }
    else if (career_is_cmd(cmd)){ e.cmd = C_CAREER; snprintf(e.text, sizeof e.text, "%s %s", cmd, rest); }
    else { fprintf(stderr, "[autotest] script line %d: unknown command '%s'\n", ln, cmd); return 0; }
    if (e.cmd == C_DOWN || e.cmd == C_UP || e.cmd == C_TAP){
        if (!parse_key(a1, &e.key)){
            fprintf(stderr, "[autotest] script line %d: unknown key '%s'\n", ln, a1); return 0; } }
    if (g_nev == g_evcap){ g_evcap = g_evcap ? g_evcap * 2 : 64; g_ev = realloc(g_ev, (size_t)g_evcap * sizeof *g_ev); }
    g_ev[g_nev++] = e;
    return 1;
}

static void load_script(const char *path){
    FILE *f = fopen(path, "r");
    if (!f){ fprintf(stderr, "[autotest] cannot open input script %s\n", path); return; }
    char line[2048]; int ln = 0;
    while (fgets(line, sizeof line, f)){
        ln++;
        expand_env(line, sizeof line);
        char *h = strchr(line, '#'); if (h) *h = 0;
        char *p = line; while (isspace((unsigned char)*p)) p++;
        if (!*p) continue;
        add_line(p, ln);
    }
    fclose(f);
    fprintf(stderr, "[autotest] input script %s: %d events\n", path, g_nev);
}

/* NFSU2_INPUT_SEQ: each "<when>:<action>" step as a script line */
static void load_seq(const char *seq){
    int n0 = g_nev, step = 0;
    for (const char *p = seq; *p; ){
        while (*p == ',' || *p == ' ' || *p == '\n') p++;
        if (!*p) break;
        const char *end = strchr(p, ','), *c = strchr(p, ':');
        if (!end) end = p + strlen(p);
        step++;
        if (!c || c > end){ fprintf(stderr, "[autotest] seq step %d: no ':'\n", step); p = end; continue; }
        char when[24], act[160], f[4][64] = {{0}}, line[512];
        snprintf(when, sizeof when, "%.*s", (int)(c - p), p);
        snprintf(act, sizeof act, "%.*s", (int)(end - c - 1), c + 1);
        int nf = 0;
        for (const char *q = act; nf < 4; ){
            const char *k = strchr(q, ':');
            int l = k ? (int)(k - q) : (int)strlen(q);
            snprintf(f[nf++], 64, "%.*s", l, q);
            if (!k) break;
            q = k + 1;
        }
        const char *a = f[0];
        if (!strcasecmp(a, "wait") && nf >= 2) snprintf(line, sizeof line, "%s waitfng %s %s", when, f[1], nf >= 3 ? f[2] : "3000");
        else if (!strcasecmp(a, "until") && nf >= 3)
            snprintf(line, sizeof line, "%s nstapuntil %s %s %s 4000", when, f[1], f[2], nf >= 4 ? f[3] : "120");
        else if (!strcasecmp(a, "untilpad") && nf >= 3)
            snprintf(line, sizeof line, "%s padtapuntil %s %s %s 4000", when, f[1], f[2], nf >= 4 ? f[3] : "120");
        else if (!strcasecmp(a, "type") && nf >= 2){
            char t[128]; snprintf(t, sizeof t, "%s", act + 5);
            for (char *q = t; *q; q++) if (*q == '_') *q = ' ';
            snprintf(line, sizeof line, "%s nstype8 %s", when, t); }
        else if (!strcasecmp(a, "focus") && nf >= 2) snprintf(line, sizeof line, "%s nsfocus %s", when, f[1]);
        else if (!strcasecmp(a, "down") && nf >= 2) snprintf(line, sizeof line, "%s nsdown %s", when, act + 5);
        else if (!strcasecmp(a, "up") && nf >= 2) snprintf(line, sizeof line, "%s nsup %s", when, act + 3);
        else if (!strcasecmp(a, "pad") && nf >= 2) snprintf(line, sizeof line, "%s padset %s", when, act + 4);
        else if (!strcasecmp(a, "padtap") && nf >= 2) snprintf(line, sizeof line, "%s padtap %s %s", when, f[1], nf >= 3 ? f[2] : "6");
        else if (!strcasecmp(a, "shot")) snprintf(line, sizeof line, "%s shot", when);
        else if (!strcasecmp(a, "in")) snprintf(line, sizeof line, "%s in", when);
        else if (!strcasecmp(a, "peek") && nf >= 2) snprintf(line, sizeof line, "%s peek 0x%s %s", when, f[1], nf >= 3 ? f[2] : "1");
        else if (!strcasecmp(a, "log")) snprintf(line, sizeof line, "%s log %s", when, act + 4);
        else {                                       /* a key, with an optional hold: J, J:30, kc:0x0c, kc:0x0c:30 */
            char key[64]; snprintf(key, sizeof key, "%s", act);
            const char *hold = "6";
            char *k = strrchr(key, ':');
            if (k && (strncasecmp(key, "kc:", 3) || k > key + 3)){ *k = 0; hold = k + 1; }
            snprintf(line, sizeof line, "%s nstap %s %s", when, key, hold);
        }
        add_line(line, step);
        p = end;
    }
    fprintf(stderr, "[autotest] NFSU2_INPUT_SEQ: %d step(s), %d events\n", step, g_nev - n0);
}


/* ---- front-end package tracking ----------------------------------------
 * cFEng::pInstance; GetTopPackage (0x50C8E0) returns [[cFEng+8]+0xE4]
 * (FNGInfo*), whose name pointer is found by scanning for a pointer to a
 * printable string ending in ".fng" (cached once found; +0x0C).  The current
 * screen comes from dinput_pad.c, which reads the game's debug printf. */
const char *dipad_fe_top(void);                    /* dinput_pad.c: the current screen (or the top package) */
int dipad_fe_is(const char *name);                 /* the top package, the current screen or one initialised with it */
uint32_t dipad_input_ctx(void);
static int g_fng_off = -1;
static const char *fng_str(uint32_t p){
    if (!p || !mem_is_committed(p) || !mem_is_committed(p + 63)) return 0;
    const char *s = (const char *)(g_mem + p); int n = 0;
    while (n < 63 && s[n] >= 0x20 && s[n] < 0x7f) n++;
    if (s[n] != 0 || n < 5 || strncasecmp(s + n - 4, ".fng", 4)) return 0;
    return s;
}
const char *autotest_top_fng(void){
    if (!mem_is_committed(G_FE_MGR + 3u)) return 0;
    uint32_t fe = MR32(G_FE_MGR);
    if (!fe || !mem_is_committed(fe + 11)) return 0;
    uint32_t mg = MR32(fe + 8);
    if (!mg || !mem_is_committed(mg + 0xe7)) return 0;
    uint32_t pk = MR32(mg + 0xe4);                    /* FNGInfo*; name ptr at +0x0C */
    if (!pk || !mem_is_committed(pk + 255)) return 0;
    if (g_fng_off >= 0){ const char *s = fng_str(MR32(pk + (uint32_t)g_fng_off)); if (s) return s; }
    for (int o = 0; o < 256; o += 4){
        const char *s = fng_str(MR32(pk + (uint32_t)o));
        if (s){ g_fng_off = o; return s; }
    }
    return 0;
}
/* The screens the game initialised in the guest frame of the last one
 * (dinput_pad.c passes each on, guest thread): returning to the main menu
 * prints UI_Main, GarageMain and Chyron_FE in one frame, so the last name
 * alone cannot tell the main menu from an Options page (the top package
 * stays GarageMain on both).  Counted in guest frames, so a wait sees the
 * same batch in every run. */
static char g_batch[8][64]; static int g_nbatch; static long g_batch_f = -1;
void autotest_note_screen(const char *nm){
    if (!nm) return;
    if (g_batch_f != g_frame){ g_nbatch = 0; g_batch_f = g_frame; }
    if (g_nbatch < 8) snprintf(g_batch[g_nbatch++], 64, "%.63s", nm);
}
/* the current front-end screen, or the top package, or 0 (career.c) */
const char *autotest_screen(void){ return dipad_fe_top(); }
static int fe_is(const char *want){
    if (dipad_fe_is(want)) return 1;
    for (int i = 0; i < g_nbatch; i++) if (!strcasecmp(g_batch[i], want)) return 1;
    return 0;
}

/* ---- periodic memory trace ("trace" command) ------------------------- */
#define TR_MAX 24
static struct { char name[24]; char type; char expr[80]; } g_tr[TR_MAX];
static int g_ntr = 0; static long g_tr_every = 0;
static uint32_t tr_rd(uint32_t a, int *ok){
    if (a && mem_is_committed(a) && mem_is_committed(a + 3)) return MR32(a);
    *ok = 0; return 0;
}
static uint32_t tr_racer(int want_human, int slot){
    int ok = 1; uint32_t gs = tr_rd(G_RACE, &ok);
    if (!ok || !gs) return 0;
    uint32_t n = tr_rd(gs + 0x24u, &ok);
    if (!ok || n > 16) return 0;
    if (!want_human) return (uint32_t)slot < n ? tr_rd(gs + 0xbd0u + 4u * (uint32_t)slot, &ok) : 0;
    for (uint32_t i = 0; i < n; i++){
        ok = 1; uint32_t r = tr_rd(gs + 0xbd0u + 4u * i, &ok);
        uint32_t t = tr_rd(tr_rd(tr_rd(r, &ok) + 0x14u, &ok) + 4u, &ok);
        if (ok && t == 1) return r;
    }
    return 0;
}
static uint32_t tr_eval(const char **pp, int *ok){
    const char *p = *pp; uint32_t v = 0;
    while (*p == ' ') p++;
    if (*p == '$'){
        if (p[1] == 'P'){ v = tr_racer(1, 0); p += 2; }
        else if (p[1] == 'R' && isdigit((unsigned char)p[2])){ v = tr_racer(0, p[2] - '0'); p += 3; }
        else p++;
        if (!v) *ok = 0;
    } else if (*p == '['){
        p++; uint32_t a = tr_eval(&p, ok);
        if (*p == ']') p++;
        if (*ok && mem_is_committed(a) && mem_is_committed(a + 3)) v = MR32(a); else *ok = 0;
    } else v = (uint32_t)strtoul(p, (char **)&p, 0);
    while (*p == '+' || *p == '-'){
        int neg = *p == '-'; p++;
        uint32_t k = (uint32_t)strtoul(p, (char **)&p, 0);
        v = neg ? v - k : v + k;
    }
    *pp = p; return v;
}
static void trace_set(const char *list, long every){
    g_ntr = 0; g_tr_every = every > 0 ? every : 1;
    const char *p = list;
    while (*p && g_ntr < TR_MAX){
        while (isspace((unsigned char)*p)) p++;
        if (!*p) break;
        const char *eq = strchr(p, '='), *end = p; while (*end && !isspace((unsigned char)*end)) end++;
        if (!eq || eq > end){ p = end; continue; }
        int nl = (int)(eq - p); if (nl > 23) nl = 23;
        memcpy(g_tr[g_ntr].name, p, (size_t)nl); g_tr[g_ntr].name[nl] = 0;
        const char *x = eq + 1; char ty = 'f';
        if (x[0] && x[1] == ':' && strchr("fixbwd", x[0])){ ty = x[0]; x += 2; }
        int xl = (int)(end - x); if (xl > 79) xl = 79;
        memcpy(g_tr[g_ntr].expr, x, (size_t)xl); g_tr[g_ntr].expr[xl] = 0;
        g_tr[g_ntr].type = ty; g_ntr++; p = end;
    }
}
static int tsize(char ty){ return ty == 'b' ? 1 : ty == 'w' ? 2 : ty == 'd' ? 8 : 4; }
static double tread(uint32_t a, char ty){
    return ty == 'i' ? (double)(int32_t)MR32(a) : ty == 'x' ? (double)MR32(a) : ty == 'b' ? MR8(a)
         : ty == 'w' ? MR16(a) : ty == 'd' ? MRF64(a) : (double)MRF32(a);
}
static void trace_emit(long frame, double tms){
    char line[2048]; int n = snprintf(line, sizeof line, "[trace] f=%ld t=%.0f w=%.3f", frame, tms, world_ms());
    for (int i = 0; i < g_ntr && n < (int)sizeof line - 64; i++){
        const char *x = g_tr[i].expr; int ok = 1; uint32_t a = tr_eval(&x, &ok);
        int sz = tsize(g_tr[i].type);
        if (!ok || !mem_is_committed(a) || !mem_is_committed(a + (uint32_t)sz - 1)){
            n += snprintf(line + n, sizeof line - (size_t)n, " %s=?", g_tr[i].name); continue; }
        switch (g_tr[i].type){
        case 'i': n += snprintf(line + n, sizeof line - (size_t)n, " %s=%d", g_tr[i].name, (int32_t)MR32(a)); break;
        case 'x': n += snprintf(line + n, sizeof line - (size_t)n, " %s=0x%08x", g_tr[i].name, MR32(a)); break;
        case 'b': n += snprintf(line + n, sizeof line - (size_t)n, " %s=%u", g_tr[i].name, MR8(a)); break;
        case 'w': n += snprintf(line + n, sizeof line - (size_t)n, " %s=%u", g_tr[i].name, MR16(a)); break;
        case 'd': n += snprintf(line + n, sizeof line - (size_t)n, " %s=%.9g", g_tr[i].name, MRF64(a)); break;
        default:  n += snprintf(line + n, sizeof line - (size_t)n, " %s=%.7g", g_tr[i].name, (double)MRF32(a)); break;
        }
    }
    fprintf(stderr, "%s\n", line);
}

/* "mark" values */
#define NMARK 16
static struct { char name[24]; double v; } g_mark[NMARK]; static int g_nmark;
static double *mark_ref(const char *name, int create){
    for (int i = 0; i < g_nmark; i++) if (!strcmp(g_mark[i].name, name)) return &g_mark[i].v;
    if (!create || g_nmark == NMARK) return 0;
    snprintf(g_mark[g_nmark].name, 24, "%s", name); g_mark[g_nmark].v = 0;
    return &g_mark[g_nmark++].v;
}
static double tr_value(const char *ex, int *okp){
    if (ex[0] == '@'){ double *m = mark_ref(ex + 1, 0); *okp = m != 0; return m ? *m : NAN; }
    const char *x = ex; char ty = 'f';
    if (x[0] && x[1] == ':' && strchr("fixbwd", x[0])){ ty = x[0]; x += 2; }
    int ok = 1; uint32_t a = tr_eval(&x, &ok);
    if (!ok || !mem_is_committed(a) || !mem_is_committed(a + (uint32_t)tsize(ty) - 1)){ *okp = 0; return NAN; }
    *okp = 1;
    return tread(a, ty);
}
/* "EXPR OP VALUE": 1 true, 0 false, -1 unreadable; *got = the value read */
static int cond_eval(const char *spec, double *got, char *desc, size_t dn){
    char ex[96] = {0}, op[4] = {0}, vs[48] = {0}; double want = 0;
    if (sscanf(spec, "%95s %3s %47s", ex, op, vs) < 3){ snprintf(desc, dn, "parse error: %s", spec); return -1; }
    if (vs[0] == '@'){
        char *plus = strpbrk(vs + 1, "+-"); double add = plus ? atof(plus) : 0.0;
        if (plus) *plus = 0;
        double *m = mark_ref(vs + 1, 0);
        if (!m){ snprintf(desc, dn, "unknown mark %s", vs); return -1; }
        want = *m + add;
    } else want = strtod(vs, 0);
    int ok; double v = tr_value(ex, &ok);
    *got = v;
    if (!ok){ snprintf(desc, dn, ex[0] == '@' ? "unknown mark %s" : "%s unreadable", ex); return -1; }
    int r = !strcmp(op, ">") ? v > want : !strcmp(op, ">=") ? v >= want : !strcmp(op, "<") ? v < want
          : !strcmp(op, "<=") ? v <= want : !strcmp(op, "==") ? v == want : !strcmp(op, "!=") ? v != want : -1;
    snprintf(desc, dn, "%s %s %g (value %.9g)", ex, op, want, v);
    return r;
}

/* "edge" counters, evaluated every frame */
#define NEDGE 8
static struct { char name[24]; char *spec; int last; } g_edge[NEDGE]; static int g_nedge;
static void edges_tick(void){
    for (int i = 0; i < g_nedge; i++){
        double v; char d[200];
        int r = cond_eval(g_edge[i].spec, &v, d, sizeof d) == 1;
        if (r && !g_edge[i].last){ double *m = mark_ref(g_edge[i].name, 1); if (m) *m += 1.0; }
        g_edge[i].last = r;
    }
}

void metal_request_dump(void);                                   /* metal.m: PNG of the next frame */
long metal_frames(void);
void metal_request_quit(void);                                   /* metal.m */
int  metal_window_ready(void);
extern void (*g_report_fn)(void);

static void do_quit(const char *why){
    fprintf(stderr, "\n[autotest] quit at guest frame %ld (%s)\n", g_frame, why);
    if (getenv("WINDOW") && metal_window_ready()){ metal_request_quit(); return; }
    { extern void discord_shutdown(void); discord_shutdown(); }   /* _exit skips atexit: clear the presence first */
    if (g_report_fn) g_report_fn();
    fflush(stdout); fflush(stderr);
    _exit(0);
}
/* "dump [label]" and career.c's bot: a PNG of the next frame (DUMPDIR) */
void autotest_dump(const char *label){
    fprintf(stderr, "[autotest] f=%ld dump %s (after window frame %ld)\n", g_frame, label && *label ? label : "dump", metal_frames());
    metal_request_dump();
}

static void status_line(double t, double tms, const char *label);
static void pad_items_tap(const char *button, int down){
    char b[24]; snprintf(b, sizeof b, "%s", button);
    /* in pad items X and Y are stick axes: the face buttons are SQUARE and TRIANGLE there */
    if (!strcasecmp(b, "X")) snprintf(b, sizeof b, "SQUARE");
    if (!strcasecmp(b, "Y")) snprintf(b, sizeof b, "TRIANGLE");
    char it[48]; snprintf(it, sizeof it, "%s=%d", b, down);
    gamepad_synth_items(it);
}
static void pad_items_release_later(const char *button, long at){
    if (g_nirel >= 16) return;
    snprintf(g_irel[g_nirel].key, sizeof g_irel[g_nirel].key, "%s", button);
    g_irel[g_nirel++].at = at;
}
/* a waiting tap command: 1 = done (the screen came, or the time ran out) */
static int tap_until(const Ev *e, const char *what, const char *want, long *last, void (*press)(const Ev *)){
    if (g_wait_start < 0){ g_wait_start = g_frame; *last = -1000000; }
    if (fe_is(want)){
        fprintf(stderr, "[autotest] f=%ld %s %s satisfied after %ld frames\n", g_frame, what, want, g_frame - g_wait_start);
        g_wait_start = -1; return 1; }
    if (e->n && g_frame - g_wait_start >= e->n){
        const char *t = autotest_top_fng();
        fprintf(stderr, "[autotest] f=%ld %s %s TIMEOUT (top=%s screen=%s)\n", g_frame, what, want, t ? t : "-", dipad_fe_top() ?: "-");
        g_wait_start = -1; return 1; }
    if (g_frame - *last >= (long)e->val){
        *last = g_frame; press(e);
        if (g_fng_log >= 3) fprintf(stderr, "[autotest] f=%ld %s tap %s\n", g_frame, what, want);
    }
    return 0;
}
static void press_key(const Ev *e){
    key_event(e->key, 1);
    if (g_nrel < 64){ g_rel[g_nrel].dik = e->key; g_rel[g_nrel].at = g_frame + 6; g_nrel++; }
}
static void press_pad(const Ev *e){
    gamepad_synth_button((int)e->key, 1);
    if (g_nprel < 32){ g_prel[g_nprel].dik = e->key; g_prel[g_nprel].at = g_frame + 6; g_nprel++; }
}
static void press_padset(const Ev *e){ pad_items_tap(e->text, 1); pad_items_release_later(e->text, g_frame + 6); }
static void press_ns(const Ev *e){
    ns_sched(g_frame, KSYN_DOWN, e->text, 0, 0, 0);
    ns_sched(g_frame + 6, KSYN_UP, e->text, 0, 0, 0);
}
static void log_input(void){
    uint32_t c = dipad_input_ctx();
    if (!c || !mem_is_committed(c + 0x2efu)){ fprintf(stderr, "[autotest] f=%ld in: no player input controller yet\n", g_frame); return; }
    fprintf(stderr, "[autotest] f=%ld in: steer %+.2f throttle %.2f brake %.2f e-brake %.2f\n", g_frame,
            (double)MRF32(c + 0x2c8u), (double)MRF32(c + 0x2d4u), (double)MRF32(c + 0x2dcu), (double)MRF32(c + 0x2ecu));
}

/* loop/endloop: start line and passes left (-1 = forever) */
static struct { int start; long left, pass; } g_lstk[8]; static int g_nl;
static long g_blur_in = -1;                  /* "blur": the frame the focus comes back */
/* returns 1 if the event fired (or is finished), 0 if it must wait */
static int fire(CPU *c, Ev *e, double tms){
    switch (e->cmd){
    case C_DOWN: key_event(e->key, 1); break;
    case C_UP:   key_event(e->key, 0); break;
    case C_TAP:
        key_event(e->key, 1);
        if (g_nrel < 64){ g_rel[g_nrel].dik = e->key; g_rel[g_nrel].at = g_frame + (e->n > 0 ? e->n : 1); g_nrel++; }
        break;
    case C_TYPE: {
        for (const char *s = e->text; *s && ((g_type_t + 1) & 255) != g_type_h; s++){
            g_type_q[g_type_t] = *s; g_type_t = (g_type_t + 1) & 255; }
        g_type_next = g_frame;
        break; }
    case C_DUMP: autotest_dump(e->text); break;
    case C_SHOT: ns_sched(g_frame, KSYN_DOWN, "cmd+shift+D", 0, 0, 0); ns_sched(g_frame + 2, KSYN_UP, "cmd+shift+D", 0, 0, 0);
        fprintf(stderr, "[autotest] f=%ld shot (Cmd+Shift+D)\n", g_frame); break;
    case C_IN: log_input(); break;
    case C_LOG:  fprintf(stderr, "[autotest] f=%ld t=%.0fms w=%.1fms LOG %s\n", g_frame, tms, world_ms(), e->text); break;
    case C_CLICK:                            /* through the real mouse path, released 8 frames later */
        ns_sched(g_frame, KSYN_MOUSE_MOVE, 0, 0, e->fv, e->val / 1e6);
        ns_sched(g_frame + 1, KSYN_MOUSE_DOWN, 0, 0, 0, 0);
        ns_sched(g_frame + 9, KSYN_MOUSE_UP, 0, 0, 0, 0);
        fprintf(stderr, "[autotest] f=%ld click %.3f %.3f\n", g_frame, (double)e->fv, e->val / 1e6); break;
    case C_SRVCYCLE: { int module_test_cycle(CPU *, int, int);   /* module.c: LAN server start/stop */
        int bad = module_test_cycle(c, (int)e->n, (int)e->val);
        fprintf(stderr, "[expect] %s f=%ld w=%.0f line %d: srvcycle %ld: %d failed\n", bad ? "FAIL" : "PASS",
                g_frame, world_ms(), e->line, e->n, bad);
        break; }
    case C_QUIT: do_quit("script"); break;
    case C_CLOSE: { void lifecycle_request_quit(const char *); lifecycle_request_quit("autotest close"); break; }
    case C_BLUR: {
        long fr = e->n * 60 / 1000; if (fr < 1) fr = 1;
        fprintf(stderr, "[autotest] f=%ld blur %ld ms\n", g_frame, e->n);
        ns_sched(g_frame, KSYN_FOCUS_OUT, 0, 0, 0, 0);
        g_blur_in = g_frame + fr;
        break; }
    case C_AUDIORESET: { void audio_device_changed(const char *);
        audio_device_changed("autotest audioreset"); break; }
    case C_WZERO:
        g_wzero = (!e->n && g_race_start >= 0) ? g_race_start : world_ms();
        fprintf(stderr, "[autotest] f=%ld t=%.0fms world-time origin at w=%.3fms (now w=%.3fms)\n",
                g_frame, tms, g_wzero, world_ms());
        break;
    case C_PHOTO: {
        int photo_script(const char *s);
        fprintf(stderr, "[autotest] f=%ld t=%.0fms photo %s%s\n", g_frame, tms, e->text, photo_script(e->text) ? "" : " (not known)");
        break; }
    case C_HEADLIGHTS: {
        int headlights_set(const char *mode);
        fprintf(stderr, "[autotest] f=%ld t=%.0fms headlights %s%s\n", g_frame, tms, e->text,
                headlights_set(e->text) ? "" : " (not known here)");
        break; }
    case C_TRACE: trace_set(e->xtext ? e->xtext : "", e->n);
        fprintf(stderr, "[autotest] f=%ld trace every %ld: %d expressions\n", g_frame, g_tr_every, g_ntr);
        break;
    case C_UNTRACE: g_ntr = 0; break;
    case C_MARK: { int ok; double v = tr_value(e->xtext ? e->xtext : "", &ok);
        double *m = mark_ref(e->text, 1); if (m) *m = v;
        fprintf(stderr, "[autotest] f=%ld mark %s = %.9g%s\n", g_frame, e->text, v, ok ? "" : " (unreadable)");
        break; }
    case C_EDGE:
        if (g_nedge < NEDGE){
            snprintf(g_edge[g_nedge].name, 24, "%s", e->text); g_edge[g_nedge].spec = e->xtext ? e->xtext : (char *)"";
            g_edge[g_nedge].last = 0; mark_ref(e->text, 1); g_nedge++; }
        fprintf(stderr, "[autotest] f=%ld edge @%s: %s\n", g_frame, e->text, e->xtext ? e->xtext : "");
        break;
    case C_EXPECT: { double v; char d[200]; int r = cond_eval(e->xtext ? e->xtext : "", &v, d, sizeof d);
        fprintf(stderr, "[expect] %s f=%ld w=%.0f line %d: %s\n", r == 1 ? "PASS" : "FAIL", g_frame, world_ms(), e->line, d);
        break; }
    case C_WAITEXPR: { double v; char d[200];
        if (g_wait_start < 0) g_wait_start = g_frame;
        int r = cond_eval(e->xtext ? e->xtext : "", &v, d, sizeof d);
        if (r != 1){
            if (e->n && g_frame - g_wait_start >= e->n){
                fprintf(stderr, "[autotest] f=%ld waitexpr TIMEOUT after %ld frames: %s\n", g_frame, g_frame - g_wait_start, d);
                g_wait_start = -1; return 1; }
            return 0; }
        fprintf(stderr, "[autotest] f=%ld waitexpr satisfied after %ld frames: %s\n", g_frame, g_frame - g_wait_start, d);
        g_wait_start = -1; break; }
    case C_WAITFNG: {
        if (g_wait_start < 0) g_wait_start = g_frame;
        if (!fe_is(e->text)){
            if (e->n && g_frame - g_wait_start >= e->n){
                const char *t = autotest_top_fng();
                fprintf(stderr, "[autotest] f=%ld waitfng %s TIMEOUT after %ld frames (top=%s screen=%s)\n",
                        g_frame, e->text, g_frame - g_wait_start, t ? t : "-", dipad_fe_top() ?: "-");
                g_wait_start = -1; return 1; }
            return 0; }
        fprintf(stderr, "[autotest] f=%ld waitfng %s satisfied after %ld frames\n", g_frame, e->text, g_frame - g_wait_start);
        g_wait_start = -1;
        break; }
    case C_TAPUNTIL:    { static long last; return tap_until(e, "tapuntil", e->text, &last, press_key); }
    case C_TAPPADUNTIL: { static long last; return tap_until(e, "tappaduntil", e->text, &last, press_pad); }
    case C_PADTAPUNTIL: { static long last; return tap_until(e, "padtapuntil", e->text + 48, &last, press_padset); }
    case C_NSTAPUNTIL:  { static long last; return tap_until(e, "nstapuntil", e->text + 48, &last, press_ns); }
    case C_PAD:
        if (e->key == PAD_PLUG) gamepad_synth_connect((int)e->n);
        else gamepad_synth_button((int)e->key, (int)e->n);
        break;
    case C_TAPPAD:
        gamepad_synth_button((int)e->key, 1);
        if (g_nprel < 32){ g_prel[g_nprel].dik = e->key; g_prel[g_nprel].at = g_frame + (e->n > 0 ? e->n : 1); g_nprel++; }
        break;
    case C_PADSET: gamepad_synth_items(e->text); break;
    case C_PADTAP: pad_items_tap(e->text, 1); pad_items_release_later(e->text, g_frame + (e->n > 0 ? e->n : 1)); break;
    case C_AXIS: gamepad_synth_axis((int)e->key, e->fv); break;
    case C_NSDOWN: ns_sched(g_frame, KSYN_DOWN, e->text, 0, 0, 0); break;
    case C_NSUP:   ns_sched(g_frame, KSYN_UP, e->text, 0, 0, 0); break;
    case C_NSTAP:
        ns_sched(g_frame, KSYN_DOWN, e->text, 0, 0, 0);
        ns_sched(g_frame + (e->n > 0 ? e->n : 1), KSYN_UP, e->text, 0, 0, 0);
        break;
    case C_NSREPEAT:
        for (long i = 0; i < e->n && i < 200; i++) ns_sched(g_frame + 2 * i, KSYN_REPEAT, e->text, 0, 0, 0);
        break;
    case C_NSTYPE: {
        long at = g_frame, step = e->n > 0 ? e->n : 4;
        for (const char *p = e->text; *p; at += step){
            uint32_t u = utf8_next(&p);
            ns_sched(at, KSYN_CHAR_DOWN, 0, u, 0, 0);
            ns_sched(at + step / 2, KSYN_CHAR_UP, 0, u, 0, 0);
        }
        break; }
    case C_NSFOCUS: ns_sched(g_frame, e->n ? KSYN_FOCUS_IN : KSYN_FOCUS_OUT, 0, 0, 0, 0);
        fprintf(stderr, "[autotest] f=%ld nsfocus %s\n", g_frame, e->n ? "in" : "out"); break;
    case C_NSMOUSE: ns_sched(g_frame, (int)e->n, 0, 0, e->fv, e->text[0] ? atof(e->text) : 0); break;
    case C_LOOP:
        if (g_nl < 8){ g_lstk[g_nl].start = g_iev; g_lstk[g_nl].left = e->n > 0 ? e->n : -1; g_lstk[g_nl].pass = 1; g_nl++; }
        fprintf(stderr, "[autotest] f=%ld loop (line %d) pass 1\n", g_frame, e->line);
        break;
    case C_ENDLOOP:
        if (g_nl){
            typeof(&g_lstk[0]) L = &g_lstk[g_nl - 1];
            if (L->left < 0 || --L->left > 0){
                g_iev = L->start;                    /* the caller's g_iev++ enters the body again */
                fprintf(stderr, "[autotest] f=%ld loop (line %d) pass %ld\n", g_frame, g_ev[L->start].line, ++L->pass);
            } else g_nl--;
        }
        break;
    case C_STATUS: {                         /* inside a loop the label gets the pass number */
        char lb[112]; snprintf(lb, sizeof lb, "%s", e->text[0] ? e->text : "mark");
        if (g_nl) snprintf(lb + strlen(lb), sizeof lb - strlen(lb), "_%ld", g_lstk[g_nl - 1].pass);
        status_line(now_ms(), tms, lb);
        break; }
    case C_STALL:
        fprintf(stderr, "[autotest] f=%ld stall %ld s (test-only)\n", g_frame, e->n);
        sleep((unsigned)(e->n > 0 ? e->n : 1));
        break;
    case C_CAREER:
        if (!career_cmd(c, e->text, &g_wait_start)) return 0;
        break;
    case C_PEEK: {
        uint32_t base = 0;
        if (e->val && !(base = dipad_input_ctx())){ fprintf(stderr, "[autotest] f=%ld peek @in: no input controller yet\n", g_frame); break; }
        char ln[1024]; int k = snprintf(ln, sizeof ln, "[autotest] f=%ld peek 0x%08x:", g_frame, base + e->addr);
        for (long i = 0; i < e->n && k < (int)sizeof ln - 16; i++){
            uint32_t a = base + e->addr + 4u * (uint32_t)i;
            k += mem_is_committed(a + 3) ? snprintf(ln + k, sizeof ln - (size_t)k, " %08x", MR32(a))
                                         : snprintf(ln + k, sizeof ln - (size_t)k, " ????????");
        }
        if (e->n == 1 && mem_is_committed(base + e->addr + 3)){
            uint32_t v = MR32(base + e->addr); float fv; memcpy(&fv, &v, 4);
            snprintf(ln + k, sizeof ln - (size_t)k, " (%u, %g)", v, (double)fv);
        }
        fprintf(stderr, "%s\n", ln);
        break; }
    case C_POKE:
        if (mem_is_committed(e->addr + 3)){ MR32(e->addr) = e->val;
            fprintf(stderr, "[autotest] f=%ld poke [0x%08x] <- 0x%08x\n", g_frame, e->addr, e->val); }
        break;
    case C_WAITMEM: {
        if (g_wait_start < 0) g_wait_start = g_frame;
        uint32_t v = mem_is_committed(e->addr + 3) ? MR32(e->addr) : 0xDEADBEEFu;
        if (v != e->val){
            if (e->n && g_frame - g_wait_start >= e->n){
                fprintf(stderr, "[autotest] f=%ld waitmem [0x%08x]==%u TIMEOUT after %ld frames (value %u)\n",
                        g_frame, e->addr, e->val, g_frame - g_wait_start, v);
                g_wait_start = -1; return 1; }
            return 0; }
        fprintf(stderr, "[autotest] f=%ld waitmem [0x%08x]==%u satisfied after %ld frames\n",
                g_frame, e->addr, e->val, g_frame - g_wait_start);
        g_wait_start = -1;
        break; }
    }
    if (getenv("NFSU2_INPUT_LOG")) fprintf(stderr, "[autotest] f=%ld line %d fired\n", g_frame, e->line);
    return 1;
}

static double g_st_t = 0; static long g_st_f = 0; static double g_st_cpu = 0, g_st_gcpu = 0;
static double thread_cpu_ms(void){
    struct timespec ts; clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}
static double proc_cpu_s(void){
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
    return ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6 + ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6;
}
uint32_t gheap_top_used(void);                   /* gheap.c: the guest heap's arena top */
uint64_t gheap_failed(void);
/* cpu = whole process (% of one core); gcpu = guest main thread CPU per frame;
 * rss = the host process's peak footprint; heap = the guest heap's arena top */
static void status_line(double t, double tms, const char *label){
    double cpu = proc_cpu_s(), gcpu = thread_cpu_ms();
    double dt = (t - g_st_t) / 1e3; long nf = g_frame - g_st_f;
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
    fprintf(stderr, "[status]%s%s f=%ld t=%.1fs fps=%.1f cpu=%.0f%% gcpu=%.2fms/f flow=%u rss=%ldMB heap=%uKB heapfail=%llu\n",
            label ? " " : "", label ? label : "", g_frame, tms / 1e3, dt > 0 ? nf / dt : 0.0,
            dt > 0 ? 100.0 * (cpu - g_st_cpu) / dt : 0.0, nf > 0 ? (gcpu - g_st_gcpu) / nf : 0.0,
            mem_is_committed(G_FLOW + 3u) ? MR32(G_FLOW) : 0u, (long)(ru.ru_maxrss / (1024 * 1024)),
            gheap_top_used() >> 10, (unsigned long long)gheap_failed());
    g_st_t = t; g_st_f = g_frame; g_st_cpu = cpu; g_st_gcpu = gcpu;
}

/* ---- NFSU2_CAR_TRACE=<file>: every car of the race World per frame -------
 * One CSV row per Present while racing (GameFlow 6): wall-clock time
 * (CLOCK_REALTIME, shared by every instance on this Mac), frame, whether
 * a race HUD (HUD_*.fng) is the top package, the frame cap, WorldTimer and
 * RealTimer (1/4000 s), then per car of the World's list (+0x10 count,
 * +0x1C car pointers) whether it is the local player's (player 1's
 * vehicle), position +0x60 and speed +0x430 (LAN tests). */
static FILE *g_ctrace;
uint32_t autopilot_vehicle(void);        /* career.c: player 1's vehicle, 0 = none */
static void car_trace(void){
    static uint32_t last_w = 0;
    if (!mem_is_committed(G_FLOW + 3u) || MR32(G_FLOW) != 6u) return;
    uint32_t w = MR32(G_WORLD);
    if (!w || !mem_is_committed(w + 0x3f)) return;
    uint32_t n = MR32(w + 0x10); if (n > 8) n = 8;
    uint32_t me = autopilot_vehicle();
    if (w != last_w){
        last_w = w;
        fprintf(stderr, "[cartrace] f=%ld world 0x%08x cars %u, local vehicle 0x%08x:", g_frame, w, n, me);
        for (uint32_t i = 0; i < n; i++) fprintf(stderr, " 0x%08x", MR32(w + 0x1c + 4 * i));
        fputc('\n', stderr);
    }
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    const char *top = autotest_top_fng();
    fprintf(g_ctrace, "%lld.%06ld,%ld,%d,%.7f,%u,%u,%u", (long long)ts.tv_sec, (long)(ts.tv_nsec / 1000), g_frame,
            top && !strncasecmp(top, "HUD_", 4), (double)MRF32(G_FRAMECAP), MR32(G_WORLDTIMER), MR32(G_REALTIMER), n);
    for (uint32_t i = 0; i < n; i++){
        uint32_t car = MR32(w + 0x1c + 4 * i);
        if (car && mem_is_committed(car + 0x433))
            fprintf(g_ctrace, ",%d,%.3f,%.3f,%.3f,%.3f", car == me, (double)MRF32(car + 0x60), (double)MRF32(car + 0x64),
                    (double)MRF32(car + 0x68), (double)MRF32(car + 0x430));
        else fprintf(g_ctrace, ",,,,,");
    }
    fputc('\n', g_ctrace);
}

/* com.c, at every IDirect3DDevice9::Present (guest thread) */
void autotest_on_present(CPU *c){
    if (!g_inited) return;
    g_frame++;
    world_tick();
    if (g_ctrace) car_trace();
    double t = now_ms();
    if (g_frame == 1){ g_t0 = t; g_st_t = t; g_st_cpu = proc_cpu_s(); g_st_gcpu = thread_cpu_ms(); }
    double tms = t - g_t0;

    if (g_fng_log){
        static char last[64], last_scr[64];
        const char *tp = autotest_top_fng();
        if (tp && strcmp(tp, last)){ snprintf(last, sizeof last, "%s", tp);
            fprintf(stderr, "[fng] f=%ld top package %s (flow=%u)\n", g_frame, tp,
                    mem_is_committed(G_FLOW + 3u) ? MR32(G_FLOW) : 0u); }
        const char *sc = dipad_fe_top();
        if (sc && strcmp(sc, last_scr)){ snprintf(last_scr, sizeof last_scr, "%s", sc);
            fprintf(stderr, "[fng] f=%ld screen %s\n", g_frame, sc); }
    }
    /* scheduled releases */
    for (int i = 0; i < g_nrel; ){
        if (g_frame >= g_rel[i].at){ key_event(g_rel[i].dik, 0); g_rel[i] = g_rel[--g_nrel]; }
        else i++;
    }
    for (int i = 0; i < g_nprel; ){
        if (g_frame >= g_prel[i].at){ gamepad_synth_button((int)g_prel[i].dik, 0); g_prel[i] = g_prel[--g_nprel]; }
        else i++;
    }
    for (int i = 0; i < g_nirel; ){
        if (g_frame >= g_irel[i].at){ pad_items_tap(g_irel[i].key, 0); g_irel[i] = g_irel[--g_nirel]; }
        else i++;
    }
    if (g_blur_in >= 0 && g_frame >= g_blur_in){ g_blur_in = -1; ns_sched(g_frame, KSYN_FOCUS_IN, 0, 0, 0, 0); }
    /* ns* requests due this frame, in the order they were made */
    { int w = 0;
      for (int i = 0; i < g_nnsq; i++){
          if (g_nsq[i].at <= g_frame) ns_fire(&g_nsq[i]);
          else g_nsq[w++] = g_nsq[i];
      }
      g_nnsq = w; }
    /* typing: one character every 4 frames (down at k, up at k+2) */
    if (g_type_h != g_type_t && g_frame >= g_type_next){
        char ch = g_type_q[g_type_h]; g_type_h = (g_type_h + 1) & 255;
        unsigned dik = 0; char up[2] = { (char)toupper((unsigned char)ch), 0 };
        if (ch == ' ') dik = 0x39; else if (ch == '\n') dik = 0x1C; else parse_key(up, &dik);
        if (dik){ kbd_set_key(KSRC_SCRIPT, dik, 1);
                  if (g_nrel < 64){ g_rel[g_nrel].dik = dik; g_rel[g_nrel].at = g_frame + 2; g_nrel++; } }
        const KeyDef *k = dik ? key_by_dik(dik) : 0;
        uint32_t lp = 1u | ((uint32_t)(dik & 0x7Fu) << 16);
        if (k) win32_post_message(0x0100u, k->vk, lp);
        win32_post_message(0x0102u, (uint32_t)(unsigned char)ch, lp);
        g_type_next = g_frame + 4;
    }
    /* script */
    while (g_iev < g_nev){
        Ev *e = &g_ev[g_iev];
        int due; double wms = world_ms();
        if (e->ms == 2) due = wms + 1e-6 >= (e->rel ? g_last_fire_wms : g_wzero) + e->t;
        else if (e->rel) due = e->ms ? (tms >= g_last_fire_ms + e->t) : (g_frame >= g_last_fire_f + e->t);
        else        due = e->ms ? (tms >= e->t) : (g_frame >= e->t);
        if (!due) break;
        if (!fire(c, e, tms)) break;
        g_last_fire_f = g_frame; g_last_fire_ms = tms; g_last_fire_wms = wms; g_iev++;
        if (g_iev == g_nev) fprintf(stderr, "[autotest] f=%ld input script finished\n", g_frame);
    }
    if (g_nedge) edges_tick();
    if (g_ntr && g_frame % g_tr_every == 0) trace_emit(g_frame, tms);
    if (g_status_every && g_frame % g_status_every == 0) status_line(t, tms, 0);
    if (g_quit_frames && g_frame >= g_quit_frames) do_quit("NFSU2_QUIT_FRAMES");
}
long autotest_frame(void){ return g_frame; }
/* career.c (test-only career bot): key taps through the same path as "tap" */
void autotest_tap(unsigned dik, long frames){
    key_event(dik, 1);
    if (g_nrel < 64){ g_rel[g_nrel].dik = dik; g_rel[g_nrel].at = g_frame + (frames > 0 ? frames : 1); g_nrel++; }
}
void autotest_quit(const char *why){ do_quit(why); }

/* boot.c, first thing in main(): log redirection and NFSU2_TIMEOUT */
void autotest_early(void){
    const char *lf = getenv("NFSU2_LOG");
    if (lf && *lf){
        int fd = open(lf, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0){ dup2(fd, 1); dup2(fd, 2); close(fd); }
        setvbuf(stdout, 0, _IOLBF, 0); setvbuf(stderr, 0, _IONBF, 0);
    }
    const char *to = getenv("NFSU2_TIMEOUT");
    if (to && *to) setenv("ALARM", to, 1);
}
/* boot.c, before the game starts */
void autotest_init(void){
    const char *s = getenv("NFSU2_INPUT_SCRIPT");
    if (s && *s) load_script(s);
    const char *sq = getenv("NFSU2_INPUT_SEQ");
    if (sq && *sq) load_seq(sq);
    const char *q = getenv("NFSU2_QUIT_FRAMES"); if (q) g_quit_frames = atol(q);
    const char *st = getenv("NFSU2_STATUS_EVERY"); if (st) g_status_every = atol(st);
    { const char *ct = getenv("NFSU2_CAR_TRACE");
      if (ct && *ct && (g_ctrace = fopen(ct, "w"))){
          setvbuf(g_ctrace, 0, _IOLBF, 0);
          fprintf(g_ctrace, "t,frame,hud,cap,worldtimer,realtimer,n");
          for (int i = 0; i < 8; i++) fprintf(g_ctrace, ",c%dlocal,c%dx,c%dy,c%dz,c%dv", i, i, i, i, i);
          fputc('\n', g_ctrace); } }
    { const char *fl = getenv("NFSU2_FNG_LOG"); g_fng_log = fl ? (atoi(fl) ? atoi(fl) : 1) : 0; }
    g_inited = g_nev || g_quit_frames || g_status_every || g_ctrace || g_fng_log;
}
