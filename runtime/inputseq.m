/* inputseq.m -- NFSU2_INPUT_SEQ: a small input script for tests, through the
 * real input paths (keys as NSEvents into AppKit's queue, runtime/keyboard_mac.m;
 * the synthetic game pad, runtime/gamepad.m), so a test takes the path a
 * player's keyboard and controller take.  Run once per pass of metal.m's event
 * loop (kbdmac_tick, main thread).
 *
 *   NFSU2_INPUT_SEQ="<when>:<action>,<when>:<action>,..."
 * <when>: a frame number, or +<n>: n frames after the previous step.
 * <action>:
 *   <key>[:<hold>]           tap a key, held <hold> frames (default 6): J, RETURN,
 *                            LEFT, opt+E, cmd+N, kc:0x0c ... (kbdmac_synth_key)
 *   down:<key> / up:<key>    press / release a key
 *   type:<text>              type text, a character every 8 frames ('_' = space)
 *   focus:out / focus:in     the app loses / gets the focus, as with Cmd-Tab
 *   wait:<pkg>[:<max>]       wait until <pkg> is the front-end screen (the top
 *                            package, or the screen the game last opened; at
 *                            most <max> frames, default 3000)
 *   until:<key>:<pkg>[:<every>]   tap <key> every <every> frames (default 120)
 *                            until <pkg> is the screen
 *   pad:<items>              set the synthetic pad (NFSU2_PAD_FAKE items, ';'
 *                            between them: A=1, LX=-0.5, RT=1, OFF, PLUG=0 ...)
 *   padtap:<button>[:<hold>] tap a pad button (default 6 frames)
 *   untilpad:<button>:<pkg>[:<every>]   as until, with a pad button
 *   shot                     write this frame as a PNG (as Cmd+Shift+D does:
 *                            PERFLOG's folder, else ~/Library/Logs/NFSU2)
 *   peek:<addr>[:<n>]        log n dwords of guest memory (default 1)
 *   in                       log the player car's input (steer, throttle, brake,
 *                            e-brake; runtime/dinput_pad.c)
 *   log:<text>               a marker line in the log
 * Every step is logged as "[seq] frame N: <action>". */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "kbd.h"

long metal_frames(void);                           /* metal.m */
const char *dipad_fe_top(void);                    /* dinput_pad.c */
int dipad_fe_is(const char *name);
uint32_t dipad_peek32(uint32_t a);
uint32_t dipad_input_ctx(void);
void gamepad_synth_items(const char *items);       /* gamepad.m */

#define SEQMAX 400
typedef struct { int rel; long at; char act[96]; } Step;
static Step g_s[SEQMAX];
static int g_n, g_i, g_init;
static long g_base;                                /* frame of the previous step */
static long g_wait_since = -1, g_last_tap;
static struct { long at; char key[40]; int pad; } g_up[16];
static int g_nup;
static uint32_t g_text[64]; static long g_text_at = -1; static int g_text_pos, g_text_n;

static void parse(void){
    const char *e = getenv("NFSU2_INPUT_SEQ");
    for (const char *p = e; p && *p && g_n < SEQMAX; ){
        while (*p == ',' || *p == ' ' || *p == '\n') p++;
        if (!*p) break;
        const char *end = strchr(p, ','), *c = strchr(p, ':');
        if (!end) end = p + strlen(p);
        if (c && c < end){
            Step *s = &g_s[g_n++];
            s->rel = *p == '+';
            s->at = strtol(s->rel ? p + 1 : p, 0, 0);
            snprintf(s->act, sizeof s->act, "%.*s", (int)(end - c - 1), c + 1);
        }
        p = end;
    }
    if (g_n) fprintf(stderr, "[seq] NFSU2_INPUT_SEQ: %d step(s)\n", g_n);
}
static int top_is(const char *pkg){ return dipad_fe_is(pkg); }
/* "a:b:c" -> fields; returns the count */
static int fields(const char *s, char f[4][64]){
    int n = 0; const char *p = s;
    while (n < 4){
        const char *c = strchr(p, ':');
        int l = c ? (int)(c - p) : (int)strlen(p);
        snprintf(f[n++], 64, "%.*s", l, p);
        if (!c) break;
        p = c + 1;
    }
    return n;
}
static void release_later(const char *key, int pad, long at){
    if (g_nup >= 16) return;
    g_up[g_nup].at = at; g_up[g_nup].pad = pad;
    snprintf(g_up[g_nup].key, sizeof g_up[g_nup].key, "%s", key);
    g_nup++;
}
static void tap(const char *key, int pad, long f, long hold){
    /* pad buttons: X and Y are the stick axes in pad items, the buttons are
     * SQUARE and TRIANGLE there */
    if (pad && !strcasecmp(key, "X")) key = "SQUARE";
    if (pad && !strcasecmp(key, "Y")) key = "TRIANGLE";
    if (pad){
        char it[48]; snprintf(it, sizeof it, "%s=1", key);
        gamepad_synth_items(it);
    } else if (!kbdmac_synth_key(KSYN_DOWN, key)){
        fprintf(stderr, "[seq] unknown key %s\n", key); return;
    }
    release_later(key, pad, f + (hold > 0 ? hold : 6));
}
static void log_input(long f){
    uint32_t c = dipad_input_ctx();
    if (!c){ fprintf(stderr, "[seq] frame %ld: in: no player input controller yet\n", f); return; }
    uint32_t v[4] = { dipad_peek32(c + 0x2c8u), dipad_peek32(c + 0x2d4u), dipad_peek32(c + 0x2dcu), dipad_peek32(c + 0x2ecu) };
    float x[4]; memcpy(x, v, sizeof x);
    fprintf(stderr, "[seq] frame %ld: in: steer %+.2f throttle %.2f brake %.2f e-brake %.2f\n",
            f, (double)x[0], (double)x[1], (double)x[2], (double)x[3]);
}

/* 1 = the step is done, 0 = still waiting */
static int run(const char *act, long f){
    char fl[4][64]; int nf = fields(act, fl);
    if (!strcasecmp(fl[0], "wait") && nf >= 2){
        long mx = nf >= 3 ? strtol(fl[2], 0, 0) : 3000;
        if (g_wait_since < 0) g_wait_since = f;
        if (top_is(fl[1])){ fprintf(stderr, "[seq] frame %ld: %s is up\n", f, fl[1]); return 1; }
        if (f - g_wait_since > mx){ fprintf(stderr, "[seq] frame %ld: TIMEOUT waiting for %s (top: %s)\n",
                                            f, fl[1], dipad_fe_top() ?: "?"); return 1; }
        return 0;
    }
    if ((!strcasecmp(fl[0], "until") || !strcasecmp(fl[0], "untilpad")) && nf >= 3){
        long every = nf >= 4 ? strtol(fl[3], 0, 0) : 120;
        if (g_wait_since < 0){ g_wait_since = f; g_last_tap = f - every; }
        if (top_is(fl[2])){ fprintf(stderr, "[seq] frame %ld: %s is up\n", f, fl[2]); return 1; }
        if (f - g_wait_since > 4000){ fprintf(stderr, "[seq] frame %ld: TIMEOUT tapping %s for %s (top: %s)\n",
                                              f, fl[1], fl[2], dipad_fe_top() ?: "?"); return 1; }
        if (f - g_last_tap >= every){ g_last_tap = f; tap(fl[1], fl[0][5] == 'p' || fl[0][5] == 'P', f, 6); }
        return 0;
    }
    fprintf(stderr, "[seq] frame %ld: %s\n", f, act);
    if (!strcasecmp(fl[0], "type") && nf >= 2){
        g_text_n = 0;                            /* UTF-8 -> code points */
        for (const unsigned char *t = (const unsigned char *)act + 5; *t && g_text_n < 64; ){
            uint32_t u = *t++;
            if (u >= 0xC0 && u < 0xE0 && *t){ u = (u & 0x1F) << 6 | (*t++ & 0x3F); }
            else if (u >= 0xE0 && u < 0xF0 && t[0] && t[1]){ u = (u & 0x0F) << 12 | (t[0] & 0x3F) << 6 | (t[1] & 0x3F); t += 2; }
            g_text[g_text_n++] = u == '_' ? ' ' : u;
        }
        g_text_at = f; g_text_pos = 0;
    }
    else if (!strcasecmp(fl[0], "focus") && nf >= 2)
        kbdmac_synth_simple(!strcasecmp(fl[1], "out") ? KSYN_FOCUS_OUT : KSYN_FOCUS_IN, 0, 0);
    else if (!strcasecmp(fl[0], "down") && nf >= 2) kbdmac_synth_key(KSYN_DOWN, act + 5);
    else if (!strcasecmp(fl[0], "up") && nf >= 2) kbdmac_synth_key(KSYN_UP, act + 3);
    else if (!strcasecmp(fl[0], "pad") && nf >= 2) gamepad_synth_items(act + 4);
    else if (!strcasecmp(fl[0], "padtap") && nf >= 2) tap(fl[1], 1, f, nf >= 3 ? strtol(fl[2], 0, 0) : 6);
    else if (!strcasecmp(fl[0], "shot")){ kbdmac_synth_key(KSYN_DOWN, "cmd+shift+D"); release_later("cmd+shift+D", 0, f + 2); }
    else if (!strcasecmp(fl[0], "peek") && nf >= 2){
        uint32_t a = (uint32_t)strtoul(fl[1], 0, 16); int n = nf >= 3 ? atoi(fl[2]) : 1;
        fprintf(stderr, "[seq] frame %ld: peek 0x%08x:", f, a);
        for (int k = 0; k < n && k < 16; k++) fprintf(stderr, " %08x", dipad_peek32(a + 4u * (uint32_t)k));
        fprintf(stderr, "\n");
    }
    else if (!strcasecmp(fl[0], "in")) log_input(f);
    else if (!strcasecmp(fl[0], "log")) ;
    else {                                       /* a key */
        char key[64]; snprintf(key, sizeof key, "%s", act);
        long hold = 6;
        char *c = strrchr(key, ':');
        if (c && (strncasecmp(key, "kc:", 3) || c > key + 3)){ hold = strtol(c + 1, 0, 0); *c = 0; }
        tap(key, 0, f, hold);
    }
    return 1;
}

void inputseq_tick(void){
    if (!g_init){ g_init = 1; parse(); }
    if (!g_n) return;
    long f = metal_frames();
    for (int k = 0; k < g_nup; ){
        if (f >= g_up[k].at){
            if (g_up[k].pad){ char it[48]; snprintf(it, sizeof it, "%s=0", g_up[k].key); gamepad_synth_items(it); }
            else kbdmac_synth_key(KSYN_UP, g_up[k].key);
            g_up[k] = g_up[--g_nup];
        } else k++;
    }
    if (g_text_at >= 0 && f >= g_text_at){
        if (g_text_pos > 0) kbdmac_synth_char(KSYN_CHAR_UP, g_text[g_text_pos - 1]);
        if (g_text_pos < g_text_n){ kbdmac_synth_char(KSYN_CHAR_DOWN, g_text[g_text_pos]); g_text_pos++; g_text_at = f + 8; }
        else g_text_at = -1;
    }
    while (g_i < g_n){
        Step *s = &g_s[g_i];
        long at = s->rel ? g_base + s->at : s->at;
        if (f < at) return;
        if (!run(s->act, f)) return;
        g_wait_since = -1;
        g_base = f; g_i++;
    }
}
