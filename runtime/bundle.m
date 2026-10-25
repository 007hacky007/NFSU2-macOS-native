/* .app bundle support
 *
 * Three things needed to be runnable from Finder without a shell script:
 *   1) the settings run.sh exports (set automatically inside the bundle),
 *   2) where the game data is (outside the bundle; the user is asked),
 *   3) stderr being written somewhere (no terminal when run from Finder).
 *
 * Nothing in this file changes running from the terminal: every path first
 * checks "are we running from a bundle" and returns immediately if not.  */
#import <Cocoa/Cocoa.h>
#include <string.h>
#include "enhance.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <libgen.h>
#include <mach-o/dyld.h>

static char g_exe_dir[1024];      /* .../NFSU2.app/Contents/MacOS      */
static char g_app_dir[1024];      /* the directory CONTAINING the .app */
static char g_res_dir[1024];      /* .../NFSU2.app/Contents/Resources  */
static int  g_bundled = -1;

/* Are we running from a bundle?  We look at the real path with symbolic links
 * resolved: yes if it is ".../X.app/Contents/MacOS/Y".                   */
int app_is_bundled(void){
    if (g_bundled >= 0) return g_bundled;
    char raw[1024]; uint32_t n = sizeof raw;
    if (_NSGetExecutablePath(raw, &n) != 0){ g_bundled = 0; return 0; }
    char real[1024];
    if (!realpath(raw, real)) snprintf(real, sizeof real, "%s", raw);

    snprintf(g_exe_dir, sizeof g_exe_dir, "%s", real);
    char *s = strrchr(g_exe_dir, '/'); if (s) *s = 0;

    const char *tail = "/Contents/MacOS";
    size_t el = strlen(g_exe_dir), tl = strlen(tail);
    if (el <= tl || strcmp(g_exe_dir + el - tl, tail) != 0){ g_bundled = 0; return 0; }

    /* .../X.app  ->  Resources and the directory containing the .app */
    char app[1024]; snprintf(app, sizeof app, "%.*s", (int)(el - tl), g_exe_dir);
    snprintf(g_res_dir, sizeof g_res_dir, "%s/Contents/Resources", app);
    snprintf(g_app_dir, sizeof g_app_dir, "%s", app);
    s = strrchr(g_app_dir, '/'); if (s) *s = 0;
    g_bundled = 1;
    return 1;
}

/* The in-bundle equivalent of the exports in run.sh.  If already in the
 * environment we leave them alone: overriding with "NFSU2_DATA=... open -a"
 * stays possible.  ALARM is deliberately 0: boot.c's 20 s diagnostic timeout
 * would take the game out of the user's hands.                          */
static void setdef(const char *k, const char *v){ if (!getenv(k)) setenv(k, v, 1); }
void app_set_defaults(void){
    setdef("WINDOW", "1");
    setdef("ALARM", "0");
    setdef("FIXMAT", "1");
    setdef("FIXMAT_MODE", "3");
    setdef("NOMOVIES", "1");
    setdef("SNDSYNC", "1");
    setdef("GPUVS", "1");
}

/* When run from Finder stderr goes to /dev/null; when an error report is
 * wanted we have nothing.  When run from the terminal (stderr is a tty) we
 * leave it alone.                                                       */
void app_open_log(void){
    if (isatty(2)) return;
    const char *home = getenv("HOME"); if (!home) return;
    char dir[1024], pth[1200];
    snprintf(dir, sizeof dir, "%s/Library/Logs/NFSU2", home);
    mkdir(dir, 0755);
    /* The HD build writes a separate log: so the two versions run side by side
     * don't overwrite each other's log. */
    const char *lg = NFS_ENHANCED ? "nfsu2-hd" : "nfsu2";
    snprintf(pth, sizeof pth, "%s/%s.log", dir, lg);
    /* "w": from scratch on every run.  The previous run may be needed for diagnosis. */
    char prev[1300]; snprintf(prev, sizeof prev, "%s/%s-previous.log", dir, lg);
    rename(pth, prev);
    freopen(pth, "w", stderr);
    setvbuf(stderr, NULL, _IOLBF, 0);
    freopen(pth, "a", stdout);
}

static int has_exe(const char *dir, char *out, size_t osz){
    char p[1200]; struct stat st;
    static const char *names[] = { "SPEED2.EXE", "speed2.exe", "Speed2.exe" };
    for (unsigned i = 0; i < sizeof names / sizeof names[0]; i++){
        snprintf(p, sizeof p, "%s/%s", dir, names[i]);
        if (stat(p, &st) == 0 && S_ISREG(st.st_mode)){ snprintf(out, osz, "%s", p); return 1; }
    }
    return 0;
}

/* The selected directory either contains SPEED2.EXE directly or is a parent
 * directory (like "Need for Speed Underground 2 - Clean Edition").  We look
 * two levels down; anything deeper is worth asking the user about.       */
static int find_under(const char *dir, char *out, size_t osz, int depth){
    if (has_exe(dir, out, osz)) return 1;
    if (depth <= 0) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *kids = [fm contentsOfDirectoryAtPath:@(dir) error:nil];
    for (NSString *k in kids){
        if ([k hasPrefix:@"."]) continue;
        char sub[1200]; snprintf(sub, sizeof sub, "%s/%s", dir, [k UTF8String]);
        struct stat st;
        if (stat(sub, &st) == 0 && S_ISDIR(st.st_mode) &&
            find_under(sub, out, osz, depth - 1)) return 1;
    }
    return 0;
}

static NSString *const kPrefKey = @"OyunDizini";
static int g_embedded = 0;        /* the data was found inside the bundle */

/* The directory saves (career profiles) are written to.  ALWAYS outside the
 * game and application folders: so the player's progress isn't lost when a new
 * version is distributed and the .app or game folder is replaced.  Writing
 * inside the bundle would also break the signature.  Saves that old versions
 * wrote to the game folder are moved here at startup (fileio_migrate_saves).
 * Can be changed with NFSU2_SAVEDIR (so tests don't touch real saves). */
const char *app_save_dir(void){
    static char dir[1200];
    const char *env = getenv("NFSU2_SAVEDIR");
    if (env && *env){ snprintf(dir, sizeof dir, "%s", env); return dir; }
    const char *home = getenv("HOME"); if (!home) return NULL;
    snprintf(dir, sizeof dir, "%s/Library/Application Support/NFSU2 Kayitlar", home);
    return dir;
}

static void app_alert(const char *title, const char *msg){
    NSAlert *a = [NSAlert new];
    [a setMessageText:@(title)];
    [a setInformativeText:@(msg)];
    [a addButtonWithTitle:@"Tamam"];
    [a runModal];
}

/* Ask the user for the game folder.  Returns 0 if they cancel.          */
static int app_ask(char *out, size_t osz){
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseFiles:NO];
    [op setCanChooseDirectories:YES];
    [op setAllowsMultipleSelection:NO];
    [op setPrompt:@"Sec"];
    [op setMessage:@"Choose the Need for Speed Underground 2 folder "
                   @"(the folder containing SPEED2.EXE)."];
    [NSApp activateIgnoringOtherApps:YES];
    if ([op runModal] != NSModalResponseOK) return 0;
    NSString *dir = [[op URL] path];
    if (!find_under([dir UTF8String], out, osz, 2)){
        app_alert("There is no SPEED2.EXE in this folder",
                  "Choose the folder where the game is installed: it contains SPEED2.EXE and "
                  "the CARS / TRACKS / SOUND folders.");
        return 0;
    }
    return 1;
}

/* Find the game data.  In order: the environment variable, a previously
 * selected path, inside the bundle, next to the .app, the home directory,
 * then ask the user.                                                     */
const char *app_find_game(void){
    static char found[1200];
    char dir[1200];

    const char *env = getenv("NFSU2_DATA");
    if (env && *env){
        struct stat st;
        if (stat(env, &st) == 0 && S_ISREG(st.st_mode)){
            snprintf(found, sizeof found, "%s", env); return found; }
        if (find_under(env, found, sizeof found, 2)) return found;
        fprintf(stderr, "no SPEED2.EXE in NFSU2_DATA=%s\n", env);
    }

    /* Data embedded inside the bundle (./pack.sh --embed) comes before everything:
     * a "single piece" app shouldn't drift to some other previously chosen folder. */
    if (app_is_bundled()){
        snprintf(dir, sizeof dir, "%s/Game", g_res_dir);
        if (find_under(dir, found, sizeof found, 2)){ g_embedded = 1; return found; }
    }

    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kPrefKey];
    if (saved && find_under([saved UTF8String], found, sizeof found, 2)) return found;

    if (app_is_bundled()){
        /* next to the .app and its parent directory: in the source tree the .app is
         * in out/, while the game is at the project root. */
        if (find_under(g_app_dir, found, sizeof found, 2)) return found;
        snprintf(dir, sizeof dir, "%s", g_app_dir);
        { char *s2 = strrchr(dir, '/'); if (s2 && s2 != dir){ *s2 = 0;
          if (find_under(dir, found, sizeof found, 2)) return found; } }
    }

    const char *home = getenv("HOME");
    if (home){
        static const char *cand[] = {
            "%s/Library/Application Support/NFSU2",
            "%s/Documents/Need for Speed Underground 2",
            "%s/Downloads/Need for Speed Underground 2",
        };
        for (unsigned i = 0; i < sizeof cand / sizeof cand[0]; i++){
            snprintf(dir, sizeof dir, cand[i], home);
            if (find_under(dir, found, sizeof found, 2)) return found;
        }
    }

    /* Not found: ask the user.  Store the chosen path so they aren't asked
     * again.  NSOpenPanel needs NSApp.                                   */
    fprintf(stderr, "game not found -> asking the user for the folder\n");
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    for (int tries = 0; tries < 3; tries++){
        if (!app_ask(found, sizeof found)) return NULL;
        char keep[1200]; snprintf(keep, sizeof keep, "%s", found);
        char *s = strrchr(keep, '/'); if (s) *s = 0;
        [[NSUserDefaults standardUserDefaults] setObject:@(keep) forKey:kPrefKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return found;
    }
    return NULL;
}

/* When exiting without finding the game, tell the user why. */
void app_no_game(void){
    app_alert("Game files not found",
              "NFSU2 doesn't come inside this app; your own installation is required.\n\n"
              "You can put the game folder (the one containing SPEED2.EXE) next to the app "
              "or open the app again and choose the folder.");
}
