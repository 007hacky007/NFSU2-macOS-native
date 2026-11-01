/* The Online statistics panel's pure parts (runtime/netstats_core.c), no
 * network: the server's /players address for its WebSocket address (as
 * launcher/PlayerCounts.swift makes it), the /players answer, the panel's
 * text.  tests/netstats_unit.sh builds and runs it. */
#include "netstats.h"
#include <stdio.h>
#include <string.h>

static int g_pass, g_fail;
#define CHECK(c, ...) do { if (c) g_pass++; else { g_fail++; printf("FAIL  line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* (roam_game.c's, not linked here) */
int roam_game_netstats(netstats_roam *o){ memset(o, 0, sizeof *o); return 0; }

static const char *url(const char *server, uint32_t room, const uint32_t *crews, int n){
    static char b[512];
    return netstats_players_url(server, room, crews, n, b, sizeof b) ? b : "(none)";
}
static void t_url(void){
    CHECK(!strcmp(url("wss://nfsu2.xyz/lan", 0, 0, 0), "https://nfsu2.xyz/players"), "%s", url("wss://nfsu2.xyz/lan", 0, 0, 0));
    CHECK(!strcmp(url("ws://127.0.0.1:18093/lan", 0, 0, 0), "http://127.0.0.1:18093/players"), "loopback ws:// -> http://");
    CHECK(!strcmp(url("ws://localhost/lan?queue", 0, 0, 0), "http://localhost/players"), "the server address's query is not taken");
    CHECK(!strcmp(url("ws://[::1]:8080/lan", 0, 0, 0), "http://[::1]:8080/players"), "%s", url("ws://[::1]:8080/lan", 0, 0, 0));
    CHECK(!strcmp(url("WSS://Example.com:8443/lan", 0, 0, 0), "https://Example.com:8443/players"), "%s", url("WSS://Example.com:8443/lan", 0, 0, 0));
    CHECK(!strcmp(url("wss://example.com", 0, 0, 0), "https://example.com/players"), "no path");
    /* the launcher's own test: PlayerCounts.endpoint(room: "Blue Room", crews: "Blue Room, ,Night Owls") */
    uint32_t crews[4] = { 370129458u, 0, 1234u, 0 };
    CHECK(!strcmp(url("wss://nfsu2.xyz/lan", 370129458u, crews, 4), "https://nfsu2.xyz/players?room=370129458&crews=370129458,1234"),
          "%s", url("wss://nfsu2.xyz/lan", 370129458u, crews, 4));
    CHECK(!strcmp(url("wss://nfsu2.xyz/lan", 0, crews, 3), "https://nfsu2.xyz/players?crews=370129458,1234"), "crews alone");
    uint32_t five[5] = { 1, 2, 3, 4, 5 };
    CHECK(!strcmp(url("wss://h/lan", 9, five, 5), "https://h/players?room=9&crews=1,2,3,4"), "at most four crews");
    const char *bad[] = { "ws://example.com/lan", "https://example.com/lan", "wss://user:pass@example.com/lan", "wss://example.com/lan#x",
                          "wss://example.com:99999/lan", "wss://example.com:0/lan", "wss://example.com:/lan", "wss://example.com/lan\n",
                          "", "ws://127.0.0.1.evil.com/lan", "ws://128.0.0.1/lan", "wss:///lan", "wss://exa mple.com/lan",
                          "wss://[]/lan", "wss://ex%61mple.com/lan", "ws://127.0.0.256/lan", "ws://127.0.0/lan", "wss://caf\xc3\xa9.com/lan" };
    for (unsigned i = 0; i < sizeof bad / sizeof bad[0]; i++) CHECK(!strcmp(url(bad[i], 0, 0, 0), "(none)"), "refused: \"%s\"", bad[i]);
    CHECK(!strcmp(url(NULL, 0, 0, 0), "(none)"), "no address");
    char tiny[20];
    CHECK(!netstats_players_url("wss://nfsu2.xyz/lan", 0, 0, 0, tiny, sizeof tiny) && !tiny[0], "too small a buffer: none, not cut");
}
static void t_parse(void){
    netstats_counts c;
    const char *full = "{\"players\":14,\"online\":3,\"roam\":9,\"full\":false,\"queue\":0,\"roamBusy\":true,\"room\":4,\"crews\":[2,0]}";
    CHECK(netstats_parse_players(full, strlen(full), &c) && c.players == 14 && c.online == 3 && c.roam == 9 && !c.full && c.queue == 0
          && c.roam_busy && c.room == 4 && c.ncrews == 2 && c.crews[0] == 2 && c.crews[1] == 0, "the server's answer");
    const char *old = " { \"players\" : 2 , \"online\" : null }\n";
    CHECK(netstats_parse_players(old, strlen(old), &c) && c.players == 2 && c.online == -1 && c.roam == -1 && c.room == -1 && !c.roam_busy
          && c.ncrews == 0, "an older server: what it lacks is -1");
    const char *extra = "{\"players\":5,\"new\":{\"a\":[1,\"x\\\"y\",{}],\"b\":-2.5e3},\"note\":\"hi\"}";
    CHECK(netstats_parse_players(extra, strlen(extra), &c) && c.players == 5, "unknown fields are skipped");
    const char *bad[] = { "", "[]", "{}", "{\"online\":1}", "{\"players\":-1}", "{\"players\":1,\"roam\":-3}", "{\"players\":1.5}",
                          "{\"players\":\"3\"}", "{\"players\":3", "{\"players\":3}x", "{\"players\":3,}", "{\"players\":1,\"crews\":[1,-1]}",
                          "{\"players\":1,\"full\":1}", "{\"players\":99999999999}", "{\"players\":1e3}", "{players:1}", "null" };
    for (unsigned i = 0; i < sizeof bad / sizeof bad[0]; i++)
        CHECK(!netstats_parse_players(bad[i], strlen(bad[i]), &c), "refused: %s", bad[i]);
    CHECK(netstats_parse_players("{\"players\":3.0}", 15, &c) && c.players == 3, "a whole number written with .0");
    CHECK(!netstats_parse_players("{\"players\":3}", NETSTATS_ANSWER_MAX + 1, &c), "longer than the limit");
    /* deep nesting is refused, not recursed into without end */
    char deep[200]; int n = snprintf(deep, sizeof deep, "{\"players\":1,\"x\":");
    for (int i = 0; i < 40; i++) deep[n++] = '[';
    for (int i = 0; i < 40; i++) deep[n++] = ']';
    deep[n++] = '}'; deep[n] = 0;
    CHECK(!netstats_parse_players(deep, (size_t)n, &c), "nesting deeper than 16");
    const char *five = "{\"players\":9,\"crews\":[1,2,3,4,5]}";
    CHECK(netstats_parse_players(five, strlen(five), &c) && c.ncrews == 4 && c.crews[3] == 4, "four crews kept");
}
static void t_text(void){
    char t[1024]; netstats_view v;
    memset(&v, 0, sizeof v); v.rtt_ms = 40;
    netstats_text(&v, t, sizeof t);
    CHECK(!strcmp(t, "Connection: offline\nRound trip: -- ms\nPlayers on the server: --"), "nothing yet:\n%s", t);
    v.conn = NETSTATS_QUEUED; v.queue_pos = 3; v.queue_of = 12; v.counts = -1;
    netstats_text(&v, t, sizeof t);
    CHECK(!strcmp(t, "Connection: waiting in the server queue\nPlace in the queue: 3 of 12\nRound trip: 40 ms\nPlayers on the server: no answer"),
          "in the queue:\n%s", t);
    v.queue_pos = 0; netstats_text(&v, t, sizeof t);
    CHECK(!strstr(t, "Place"), "no place known: no line");
    v.conn = NETSTATS_RECONNECTING; netstats_text(&v, t, sizeof t);
    CHECK(strstr(t, "Connection: reconnecting\nRound trip: -- ms\n") != NULL, "reconnecting: no round trip\n%s", t);
    v.conn = NETSTATS_CONNECTING; netstats_text(&v, t, sizeof t);
    CHECK(strstr(t, "Connection: connecting\n") != NULL, "connecting");
    /* connected, free roam with a room and two crews, the second's name not known (Game Tools changed it) */
    memset(&v, 0, sizeof v);
    v.conn = NETSTATS_CONNECTED; v.rtt_ms = 38; v.counts = 1;
    v.c = (netstats_counts){ .players = 214, .online = 12, .roam = 61, .queue = 0, .room = 5, .roam_busy = 1, .ncrews = 2, .crews = { 3, 1 } };
    v.asked_room = 1; v.asked_crews = 2; v.free_roam = 1;
    v.r.shown = 4; v.r.linked = 9;
    snprintf(v.r.room_name, sizeof v.r.room_name, "tokyo"); snprintf(v.r.crew_name[0], sizeof v.r.crew_name[0], "Night Owls");
    netstats_text(&v, t, sizeof t);
    const char *want = "Connection: connected\nRound trip: 38 ms\nPlayers on the server: 214\nFree roam: 61, Online lobby: 12\n"
                       "Room \"tokyo\": 5\nCrew \"Night Owls\": 3\nCrew 2: 1\nServer busy: fewer cars shown\n"
                       "Cars shown near you: 4\nLinked by the hub: 9";
    CHECK(!strcmp(t, want), "connected, free roam:\n%s", t);
    printf("INFO  the panel:\n%s\n", t);
    /* an older server: no free roam, lobby or room counts; no hub answering */
    v.c.online = v.c.roam = v.c.room = -1; v.c.ncrews = 0; v.c.roam_busy = 0; v.r.linked = -1;
    netstats_text(&v, t, sizeof t);
    CHECK(strstr(t, "Free roam: --, Online lobby: --\nRoom \"tokyo\": --\nCrew \"Night Owls\": --\nCrew 2: --\nCars shown near you: 4\nLinked by the hub: --")
          != NULL && !strstr(t, "busy"), "unknown counts are --:\n%s", t);
    /* free roam off: no room, crew or free-roam lines */
    v.free_roam = 0; v.asked_room = 0; v.asked_crews = 0; v.c.roam = 2; v.c.online = 0;
    netstats_text(&v, t, sizeof t);
    CHECK(!strcmp(t, "Connection: connected\nRound trip: 38 ms\nPlayers on the server: 214\nFree roam: 2, Online lobby: 0"), "free roam off:\n%s", t);
    /* bounded: a small buffer is cut, ended, never overrun */
    char small[16]; memset(small, 'x', sizeof small);
    size_t n = netstats_text(&v, small, 12);
    CHECK(n == 11 && small[11] == 0 && small[12] == 'x', "cut at the buffer (%zu)", n);
    for (const char *p = want; *p; p++) CHECK((unsigned char)*p < 0x80, "ASCII only");
}
int main(void){
    t_url(); t_parse(); t_text();
    printf("netstats_unit: %d passed, %d failed\n", g_pass, g_fail);
    return g_fail != 0;
}
