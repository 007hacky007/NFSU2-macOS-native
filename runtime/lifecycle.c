/* lifecycle.c - quitting and app activation, delivered the way Windows does.
 *
 * Quit (Cmd-Q, the window's close button, Dock > Quit, logout):
 *   the request becomes a WM_CLOSE in the game's message queue, like the
 *   close box or Alt-F4 on Windows.  The game's window procedure
 *   (sub_005ccd70; 0x5ccd60 in the North American build) sets its quit flag
 *   [0x864f48] ([0x864f4c]) - except while PC_Loading.fng is up
 *   (sub_004a9330), so the message is posted again every second - its main
 *   loop (sub_005811d0; 0x5811c0) returns and the game shuts itself down
 *   through its own code to ExitProcess, which ends the window loop
 *   (win32.c guest_exit_now).  Before, the host loop just stopped and the
 *   game was cut off wherever it was.  A second request, or
 *   NFSU2_QUIT_GRACE seconds (default 10) without the game exiting, stops
 *   the host loop the old way.  Either way main() then waits for save files
 *   the game still has open for writing (lifecycle_drain_writes) and freezes
 *   the guest threads before the process exits, so no save is cut in half.
 *
 * Activation (Cmd-Tab, clicking another app, hiding the app, minimizing):
 *   deactivation sends WM_ACTIVATE(WA_INACTIVE), WM_ACTIVATEAPP(FALSE) and
 *   WM_KILLFOCUS; activation WM_ACTIVATEAPP(TRUE), WM_ACTIVATE(WA_ACTIVE)
 *   and WM_SETFOCUS (the order Windows uses).  WM_ACTIVATE pauses and
 *   resumes the game's own sound (EAXSound [0x82b884]: sub_004810f0 /
 *   sub_00481210) and WM_ACTIVATEAPP(FALSE) clears [0x870988], after which
 *   the game's message pump (sub_005bf1d0; 0x5bf1c0) waits in GetMessageA
 *   until the app is active again: the game freezes in the background
 *   exactly as it does after an alt-tab on Windows, its sound output muted.
 *   Before, it went on playing (and racing) behind the other app.
 *   NFSU2_BACKGROUND=run keeps it running instead (no messages are sent).
 *   During a LAN session the game is not parked (lifecycle_may_park): the
 *   messages still go out, but it keeps running, as the game itself does in
 *   a network race.  Runs with NOFOCUS (tests) ignore activation: their
 *   window is never meant to be the active one.  BLURFAKE=<frame>:<ms>
 *   (test) deactivates at that presented frame and activates again <ms>
 *   later, without touching the window.  QUITFAKE=<frame> (test) requests the
 *   quit at that presented frame, as Cmd-Q does.
 *
 * The host side (AppKit main thread) only flips atomics; everything that
 * touches the game's message queue runs on the guest thread, in
 * PeekMessageA / GetMessageA (lifecycle_pump), so the queue stays
 * single-threaded.
 *
 * Ported from th0mk's nfsu2-web runtime/lifecycle.c (MIT). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <stdatomic.h>
#include <time.h>
#include <unistd.h>

void win32_post_message(uint32_t m, uint32_t wp, uint32_t lp);   /* win32_ext.c */
void metal_request_quit(void);                                     /* metal.m */
long metal_frames(void);                                           /* metal.m: frames presented */
int  fileio_open_writers(void);                                    /* fileio.c */
int  winsock_session_active(void);                                 /* winsock.c */
void audio_set_muted(int on);                                      /* audio.m */

#define WM_ACTIVATE    0x0006u
#define WM_SETFOCUS    0x0007u
#define WM_KILLFOCUS   0x0008u
#define WM_CLOSE       0x0010u
#define WM_ACTIVATEAPP 0x001Cu

static double mono_s(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

/* ---- quit ---------------------------------------------------------------- */
static _Atomic int    g_quit_req = 0;        /* requests so far (Cmd-Q, close...) */
static _Atomic int    g_guest_gone = 0;      /* the game called ExitProcess / returned */
static _Atomic int    g_leaving = 0;         /* host loop told to stop */
static _Atomic int    g_pumping = 0;         /* the game window exists, lifecycle_pump runs */
static _Atomic double g_quit_t0 = 0;         /* time of the first request */
static double         g_close_last = 0;
static int            g_close_sent = 0;

static double quit_grace_s(void){
    const char *e = getenv("NFSU2_QUIT_GRACE");
    double g = (e && *e) ? atof(e) : 10.0;
    return g > 0 ? g : 10.0;
}
static void leave(const char *why){
    if (atomic_exchange(&g_leaving, 1)) return;
    fprintf(stderr, "app: leaving the event loop (%s)\n", why);
    metal_request_quit();
}

/* Host thread: Cmd-Q, window close, Dock > Quit.  The time is stored before
 * the request is counted, so lifecycle_tick never sees a request without
 * its start time. */
void lifecycle_request_quit(const char *why){
    double none = 0;
    atomic_compare_exchange_strong(&g_quit_t0, &none, mono_s());
    int n = atomic_fetch_add(&g_quit_req, 1) + 1;
    if (n == 1 && !atomic_load(&g_pumping)){
        fprintf(stderr, "app: quit requested (%s) before the game has a window\n", why);
        leave("nothing to send WM_CLOSE to yet");
    } else if (n == 1) fprintf(stderr, "app: quit requested (%s) -> WM_CLOSE to the game\n", why);
    else if (n == 2){
        fprintf(stderr, "app: quit requested again (%s) -> forcing the exit\n", why);
        leave("second quit request");
    }
    if (atomic_load(&g_guest_gone)) leave("the game already exited");
}

/* tests/boot.c, when the game's entry point returns or calls ExitProcess. */
void lifecycle_guest_exited(int code){
    atomic_store(&g_guest_gone, 1);
    fprintf(stderr, "app: the game exited (code %d)%s\n", code,
            atomic_load(&g_quit_req) ? " after the quit request" : "");
    if (getenv("WINDOW")) leave("the game exited");
}

/* main(), after the event loop: give the game time to finish writing and
 * close its save files (the guest threads still run).  Returns the number
 * of write handles still open when it gave up. */
int lifecycle_drain_writes(double max_s){
    double t0 = mono_s();
    int n = fileio_open_writers();
    if (n) fprintf(stderr, "app: waiting for %d open save file(s) to be closed\n", n);
    while (n && mono_s() - t0 < max_s){
        usleep(10000);
        n = fileio_open_writers();
    }
    if (n) fprintf(stderr, "app: %d file(s) still open for writing after %.1f s\n", n, max_s);
    else if (mono_s() - t0 > 0.005) fprintf(stderr, "app: save files closed after %.2f s\n", mono_s() - t0);
    return n;
}

/* ---- activation ----------------------------------------------------------- */
static _Atomic int g_want_active = 1;        /* what AppKit says */
static int         g_told_active = 1;        /* what the game was told (guest thread) */
static double      g_parked_t0;              /* guest thread: when it was told */
static long        g_parked_f0;
static int g_bg_mode = -1;                   /* 1 = NFSU2_BACKGROUND=run */

static int background_runs(void){
    if (g_bg_mode < 0){
        const char *e = getenv("NFSU2_BACKGROUND");
        g_bg_mode = (e && (!strcasecmp(e, "run") || !strcmp(e, "1") || !strcasecmp(e, "on"))) ? 1 : 0;
        fprintf(stderr, "app: in the background the game %s\n", g_bg_mode
                ? "keeps running (NFSU2_BACKGROUND=run)" : "pauses, as on Windows");
    }
    return g_bg_mode;
}
static void set_active(int on, const char *why){
    if (atomic_exchange(&g_want_active, on ? 1 : 0) != (on ? 1 : 0))
        fprintf(stderr, "app: %s (%s)\n", on ? "activated" : "deactivated", why);
}
/* Host thread: NSApplicationDidBecomeActive / DidResignActive, window
 * minimized / restored. */
void lifecycle_set_active(int on, const char *why){
    const char *nf = getenv("NOFOCUS");
    if (background_runs() || (nf && *nf && *nf != '0')) return;
    set_active(on, why);
}

/* Host event loop, once per iteration: the quit grace period, BLURFAKE and
 * QUITFAKE. */
void lifecycle_tick(void){
    static long qf = -1;
    if (qf < 0){ const char *e = getenv("QUITFAKE"); qf = (e && *e) ? atol(e) : 0; }
    if (qf > 0 && metal_frames() >= qf){ qf = 0; lifecycle_request_quit("QUITFAKE test"); }
    static int bf = -1; static long bf_frame; static double bf_ms, bf_until;
    if (bf < 0){
        const char *e = getenv("BLURFAKE");
        bf = 0;
        if (e && *e && sscanf(e, "%ld:%lf", &bf_frame, &bf_ms) == 2 && bf_frame > 0 && bf_ms > 0) bf = 1;
    }
    if (bf == 1 && metal_frames() >= bf_frame){
        bf = 2;
        if (background_runs()) fprintf(stderr, "app: BLURFAKE: the game keeps running in the background, nothing sent\n");
        else { bf_until = mono_s() + bf_ms / 1000.0; set_active(0, "BLURFAKE test"); }
    } else if (bf == 2 && bf_until > 0 && mono_s() >= bf_until){
        bf_until = 0; set_active(1, "BLURFAKE test over");
    }
    if (!atomic_load(&g_quit_req) || atomic_load(&g_leaving)) return;
    if (mono_s() - atomic_load(&g_quit_t0) > quit_grace_s()){
        fprintf(stderr, "app: the game did not exit within %g s of WM_CLOSE\n", quit_grace_s());
        leave("quit grace period over");
    }
}

/* win32_ext.c GetMessageA: may the inactive game wait there?  Only while it
 * has been told it is inactive (that is the one case where its pump calls
 * GetMessageA, and where Windows would block too), no quit is pending and
 * no LAN session is open.  The game never parks in a network race: its pump
 * only peeks while World::IsOnline (sub_005f0100).  In the LAN screens, the
 * lobby and the game room it does, and a parked game stops answering its
 * lobby server's ping (server.cfg PINGWAIT 30 s): the server drops it, and a
 * host's own drop ends every player's session.  So while a LAN session is
 * open (from the game's WSAStartup on its LAN screens to the last
 * WSACleanup) the game is not parked: the deactivation messages went out (it
 * paused its sound and ignores input, [0x870988] = 0), it keeps running as
 * in a network race, the output muted.  Single-player is unchanged. */
static int g_inactive_gen, g_park_noted = -1;
int lifecycle_may_park(void){
    if (g_told_active || atomic_load(&g_quit_req)) return 0;
    if (winsock_session_active()){
        if (g_park_noted != g_inactive_gen){
            g_park_noted = g_inactive_gen;
            fprintf(stderr, "app: in the background during a LAN session: the game keeps running (sound muted) "
                    "so the other players do not drop it\n");
            audio_set_muted(1);
        }
        return 0;
    }
    return 1;
}
/* Parked in the background right now (inactive and outside a LAN session),
 * for code that pauses its own work while the game is parked. */
int lifecycle_game_parked(void){ return !g_told_active && !winsock_session_active(); }

/* Guest thread, from PeekMessageA / GetMessageA once the game window
 * exists: turns pending host events into window messages. */
void lifecycle_pump(void){
    if (!atomic_load(&g_pumping)) atomic_store(&g_pumping, 1);
    int want = atomic_load(&g_want_active);
    if (want != g_told_active){
        g_told_active = want;
        if (want){
            fprintf(stderr, "app: the game resumes after %.1f s in the background (%ld frames presented meanwhile)\n",
                    mono_s() - g_parked_t0, metal_frames() - g_parked_f0);
            audio_set_muted(0);
            win32_post_message(WM_ACTIVATEAPP, 1u, 0u);
            win32_post_message(WM_ACTIVATE, 1u, 0u);       /* WA_ACTIVE */
            win32_post_message(WM_SETFOCUS, 0u, 0u);
        } else {
            g_inactive_gen++;
            g_parked_t0 = mono_s(); g_parked_f0 = metal_frames();
            fprintf(stderr, "app: the game is told it is inactive (WM_ACTIVATE, WM_ACTIVATEAPP): it pauses\n");
            win32_post_message(WM_ACTIVATE, 0u, 0u);       /* WA_INACTIVE */
            win32_post_message(WM_ACTIVATEAPP, 0u, 0u);
            win32_post_message(WM_KILLFOCUS, 0u, 0u);
        }
        { void discord_lifecycle_changed(void); discord_lifecycle_changed(); }   /* discord.c: "Paused" while parked */
    }
    if (atomic_load(&g_quit_req)){
        double t = mono_s();
        if (!g_close_sent || t - g_close_last >= 1.0){
            if (g_close_sent == 1) fprintf(stderr, "app: WM_CLOSE ignored (loading screen?), posting it every second\n");
            g_close_sent++; g_close_last = t;
            win32_post_message(WM_CLOSE, 0u, 0u);
        }
    }
}
