/* The Online statistics panel's /players fetch (runtime/netstats.m) against
 * tests/netstats_fetch.py's stand-in on 127.0.0.1, driven by it:
 *   netstats_fetch <server-url> <scenario> [seconds]
 * waits for the panel's text the scenario expects and prints it; exit 0 when
 * it came.  Free roam is a stand-in here (roam_game_netstats below): off at
 * first, on with a room and two crews once the first counts are shown
 * (scenario counts), so the panel asks again with ?room= and &crews=. */
#import <Foundation/Foundation.h>
#include "netstats.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile int g_roam;
int roam_game_netstats(netstats_roam *o){
    memset(o, 0, sizeof *o); o->linked = -1;
    if (!g_roam) return 0;
    o->shown = 3; o->linked = 7; o->room = 111; o->ncrews = 2; o->crews[0] = 222; o->crews[1] = 333;
    snprintf(o->room_name, sizeof o->room_name, "tokyo"); snprintf(o->crew_name[0], sizeof o->crew_name[0], "Night Owls");
    return 1;
}
static int wait_for(const char *const *want, int n, double seconds, char *t, size_t cap){
    for (int i = 0; i < (int)(seconds * 20); i++){
        netstats_snapshot(t, cap);
        int all = 1;
        for (int k = 0; k < n; k++) all &= strstr(t, want[k]) != NULL;
        if (all) return 1;
        usleep(50000);
    }
    return 0;
}
int main(int argc, char **argv){
    @autoreleasepool {
        if (argc < 3){ fprintf(stderr, "usage: netstats_fetch <server-url> <scenario> [seconds]\n"); return 2; }
        const char *sc = argv[2];
        double secs = argc > 3 ? atof(argv[3]) : 10;
        setenv("NFSU2_SERVER_URL", argv[1], 1);
        setenv("NFSU2_NET_STATS", "1", 1);
        if (strcmp(sc, "offline")) setenv("NFSU2_NET", "online", 1);
        else unsetenv("NFSU2_NET");
        char t[1024] = "";
        if (!strcmp(sc, "offline")){
            netstats_start(); usleep(1000000); netstats_snapshot(t, sizeof t);
            printf("netstats_on %d, text \"%s\"\n", netstats_on(), t);
            return netstats_on() || t[0];
        }
        netstats_start();
        if (!strcmp(sc, "counts")){
            const char *first[] = { "Connection: offline", "Round trip: -- ms", "Players on the server: 14\nFree roam: 9, Online lobby: 3" };
            if (!wait_for(first, 3, secs, t, sizeof t)){ printf("no counts:\n%s\n", t); return 1; }
            if (strstr(t, "Room") || strstr(t, "Cars shown")){ printf("free roam lines without free roam:\n%s\n", t); return 1; }
            printf("first:\n%s\n", t);
            g_roam = 1;
            const char *then[] = { "Room \"tokyo\": 4", "Crew \"Night Owls\": 2", "Crew 2: 1", "Server busy: fewer cars shown",
                                   "Cars shown near you: 3", "Linked by the hub: 7" };
            if (!wait_for(then, 6, secs, t, sizeof t)){ printf("no room and crews:\n%s\n", t); return 1; }
            printf("then:\n%s\n", t);
            return 0;
        }
        /* redirect, big, bigstream, notjson, status, remote: never counts */
        const char *none[] = { "Players on the server: no answer" };
        int ok = wait_for(none, 1, secs, t, sizeof t);
        printf("%s:\n%s\n", sc, t);
        return !ok;
    }
}
