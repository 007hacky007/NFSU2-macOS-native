/* netstats_core.c -- the Online statistics panel's pure parts (netstats.h): the
 * server's /players address, its answer and the panel's text.  No I/O, no
 * allocation; tests/netstats_unit.c checks them.  The fetch and the drawing
 * are netstats.m's. */
#include "netstats.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

/* ---- the address ------------------------------------------------------------------------ */
/* localhost, ::1 or 127.a.b.c (OnlineSettings.isLoopback) */
static int loopback(const char *h, size_t n){
    if ((n == 9 && !strncasecmp(h, "localhost", 9)) || (n == 3 && !memcmp(h, "::1", 3))) return 1;
    int parts = 0; size_t i = 0;
    while (i <= n){
        unsigned v = 0; size_t d = 0;
        while (i < n && h[i] >= '0' && h[i] <= '9' && d < 4){ v = v * 10 + (unsigned)(h[i] - '0'); i++; d++; }
        if (!d || d > 3 || v > 255 || (!parts && v != 127)) return 0;
        parts++;
        if (i == n) break;
        if (h[i] != '.') return 0;
        i++;
        if (i == n) return 0;
    }
    return parts == 4;
}
int netstats_players_url(const char *server, uint32_t room, const uint32_t *crews, int ncrews, char *out, size_t cap){
    if (!server || !out || !cap) return 0;
    out[0] = 0;
    size_t len = strlen(server);
    if (!len || len > 4096) return 0;
    for (size_t i = 0; i < len; i++){
        unsigned char ch = (unsigned char)server[i];
        if (ch <= 0x20 || ch >= 0x7f || ch == '#') return 0;           /* blanks, controls, a fragment */
    }
    int tls;
    const char *p;
    if (!strncasecmp(server, "wss://", 6)){ tls = 1; p = server + 6; }
    else if (!strncasecmp(server, "ws://", 5)){ tls = 0; p = server + 5; }
    else return 0;
    size_t an = strcspn(p, "/?");                                       /* the authority */
    if (!an || memchr(p, '@', an)) return 0;                            /* no host, or a user and password */
    const char *host = p; size_t hn; const char *rest;
    if (*p == '['){
        const char *e = memchr(p, ']', an);
        if (!e || e == p + 1) return 0;
        host = p + 1; hn = (size_t)(e - host); rest = e + 1;
        for (size_t i = 0; i < hn; i++){ char ch = host[i];
            if (!((ch >= '0' && ch <= '9') || ((ch | 0x20) >= 'a' && (ch | 0x20) <= 'f') || ch == ':' || ch == '.')) return 0; }
    } else {
        hn = strcspn(p, ":/?"); if (hn > an) hn = an;
        rest = p + hn;
        for (size_t i = 0; i < hn; i++){ char ch = host[i];
            if (!((ch >= '0' && ch <= '9') || ((ch | 0x20) >= 'a' && (ch | 0x20) <= 'z') || ch == '-' || ch == '.' || ch == '_')) return 0; }
    }
    if (!hn) return 0;
    long port = -1;
    if (rest < p + an){
        if (*rest != ':' || rest + 1 == p + an) return 0;
        port = 0;
        for (const char *q = rest + 1; q < p + an; q++){
            if (*q < '0' || *q > '9') return 0;
            port = port * 10 + (*q - '0'); if (port > 65535) return 0;
        }
        if (port < 1) return 0;
    }
    if (!tls && !loopback(host, hn)) return 0;                          /* ws:// only to this Mac */
    int bracket = *p == '[';
    int n = snprintf(out, cap, "%s://%s%.*s%s", tls ? "https" : "http", bracket ? "[" : "", (int)hn, host, bracket ? "]" : "");
    if (n < 0 || (size_t)n >= cap) goto small;
    if (port > 0){ int k = snprintf(out + n, cap - (size_t)n, ":%ld", port); if (k < 0 || (size_t)(n += k) >= cap) goto small; }
    int k = snprintf(out + n, cap - (size_t)n, "/players"); if (k < 0 || (size_t)(n += k) >= cap) goto small;
    char sep = '?';
    if (room){ k = snprintf(out + n, cap - (size_t)n, "%croom=%u", sep, room); if (k < 0 || (size_t)(n += k) >= cap) goto small; sep = '&'; }
    int listed = 0;
    for (int i = 0; crews && i < ncrews && listed < NETSTATS_CREWS; i++){
        if (!crews[i]) continue;
        k = listed ? snprintf(out + n, cap - (size_t)n, ",%u", crews[i]) : snprintf(out + n, cap - (size_t)n, "%ccrews=%u", sep, crews[i]);
        if (k < 0 || (size_t)(n += k) >= cap) goto small;
        listed++;
    }
    return 1;
small:
    out[0] = 0;
    return 0;
}

/* ---- the answer ------------------------------------------------------------------------- */
typedef struct { const char *p, *e; } js;
static void ws(js *s){ while (s->p < s->e && (*s->p == ' ' || *s->p == '\t' || *s->p == '\n' || *s->p == '\r')) s->p++; }
static int lit(js *s, const char *w){
    size_t n = strlen(w);
    if ((size_t)(s->e - s->p) < n || memcmp(s->p, w, n)) return 0;
    s->p += n; return 1;
}
/* a string; its first cap-1 bytes (escapes as they are) into k */
static int str(js *s, char *k, size_t cap){
    if (s->p >= s->e || *s->p != '"') return 0;
    s->p++; size_t n = 0;
    while (s->p < s->e && *s->p != '"'){
        if ((unsigned char)*s->p < 0x20) return 0;
        if (*s->p == '\\'){ if (++s->p >= s->e) return 0; }
        if (k && n + 1 < cap) k[n++] = *s->p;
        s->p++;
    }
    if (s->p >= s->e) return 0;
    s->p++;
    if (k) k[n] = 0;
    return 1;
}
/* a number that is a whole one from 0 to 1e9 (-1: a negative one; -2: not a number or not whole) */
static long num(js *s){
    int neg = 0;
    if (s->p < s->e && *s->p == '-'){ neg = 1; s->p++; }
    double v = 0; int d = 0;
    while (s->p < s->e && *s->p >= '0' && *s->p <= '9'){ v = v * 10 + (*s->p - '0'); s->p++; d++; }
    if (!d) return -2;
    int whole = 1;
    if (s->p < s->e && *s->p == '.'){
        s->p++; int fd = 0;
        while (s->p < s->e && *s->p >= '0' && *s->p <= '9'){ whole &= *s->p == '0'; s->p++; fd++; }
        if (!fd) return -2;
    }
    if (s->p < s->e && (*s->p == 'e' || *s->p == 'E')) return -2;     /* (never sent: refused, not guessed) */
    if (!whole) return -2;
    if (neg) return v > 0 ? -1 : 0;
    return v <= 1e9 ? (long)v : -2;
}
static int skip(js *s, int depth){
    ws(s);
    if (s->p >= s->e || depth > 16) return 0;
    char c = *s->p;
    if (c == '"') return str(s, 0, 0);
    if (c == '{' || c == '['){
        char close = c == '{' ? '}' : ']'; s->p++; ws(s);
        if (s->p < s->e && *s->p == close){ s->p++; return 1; }
        for (;;){
            if (c == '{'){ ws(s); if (!str(s, 0, 0)) return 0; ws(s); if (s->p >= s->e || *s->p++ != ':') return 0; }
            if (!skip(s, depth + 1)) return 0;
            ws(s);
            if (s->p < s->e && *s->p == ','){ s->p++; continue; }
            if (s->p < s->e && *s->p == close){ s->p++; return 1; }
            return 0;
        }
    }
    if (lit(s, "true") || lit(s, "false") || lit(s, "null")) return 1;
    /* any JSON number (a field this panel does not show) */
    const char *b = s->p;
    if (s->p < s->e && *s->p == '-') s->p++;
    int d = 0;
    while (s->p < s->e && ((*s->p >= '0' && *s->p <= '9') || *s->p == '.' || *s->p == 'e' || *s->p == 'E' || *s->p == '+' || *s->p == '-')){
        d += *s->p >= '0' && *s->p <= '9'; s->p++; }
    return d > 0 && s->p > b;
}
int netstats_parse_players(const char *json, size_t len, netstats_counts *o){
    memset(o, 0, sizeof *o);
    o->players = o->online = o->roam = o->queue = o->room = -1;
    if (!json || len > NETSTATS_ANSWER_MAX) return 0;
    js s = { json, json + len };
    int bad = 0;
    ws(&s);
    if (s.p >= s.e || *s.p++ != '{') return 0;
    ws(&s);
    if (s.p < s.e && *s.p == '}') s.p++;
    else for (;;){
        char k[16];
        ws(&s);
        if (!str(&s, k, sizeof k)) return 0;
        ws(&s);
        if (s.p >= s.e || *s.p++ != ':') return 0;
        ws(&s);
        int *slot = !strcmp(k, "players") ? &o->players : !strcmp(k, "online") ? &o->online : !strcmp(k, "roam") ? &o->roam
                  : !strcmp(k, "queue") ? &o->queue : !strcmp(k, "room") ? &o->room : 0;
        int *flag = !strcmp(k, "full") ? &o->full : !strcmp(k, "roamBusy") ? &o->roam_busy : 0;
        if (slot){
            if (lit(&s, "null")) *slot = -1;
            else { long v = num(&s); if (v == -2) return 0; if (v < 0) bad = 1; *slot = v < 0 ? -1 : (int)v; }
        } else if (flag){
            if (lit(&s, "true")) *flag = 1;
            else if (lit(&s, "false") || lit(&s, "null")) *flag = 0;
            else return 0;
        } else if (!strcmp(k, "crews")){
            o->ncrews = 0;
            if (lit(&s, "null")) {}
            else {
                if (s.p >= s.e || *s.p++ != '[') return 0;
                ws(&s);
                if (s.p < s.e && *s.p == ']') s.p++;
                else for (;;){
                    ws(&s);
                    long v = num(&s); if (v == -2) return 0; if (v < 0) bad = 1;
                    if (o->ncrews < NETSTATS_CREWS) o->crews[o->ncrews++] = v < 0 ? 0 : (int)v;
                    ws(&s);
                    if (s.p < s.e && *s.p == ','){ s.p++; continue; }
                    if (s.p < s.e && *s.p == ']'){ s.p++; break; }
                    return 0;
                }
            }
        } else if (!skip(&s, 0)) return 0;
        ws(&s);
        if (s.p < s.e && *s.p == ','){ s.p++; continue; }
        if (s.p < s.e && *s.p == '}'){ s.p++; break; }
        return 0;
    }
    ws(&s);
    if (s.p != s.e) return 0;                                          /* something after the object */
    return !bad && o->players >= 0;
}

/* ---- the text --------------------------------------------------------------------------- */
typedef struct { char *o; size_t cap, n; } tb;
static void put(tb *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void put(tb *b, const char *fmt, ...){
    if (b->n + 1 >= b->cap) return;
    va_list a; va_start(a, fmt);
    int k = vsnprintf(b->o + b->n, b->cap - b->n, fmt, a);
    va_end(a);
    if (k < 0) return;
    b->n += (size_t)k;
    if (b->n >= b->cap) b->n = b->cap - 1;
}
static void count(tb *b, int v){ if (v >= 0) put(b, "%d", v); else put(b, "--"); }
size_t netstats_text(const netstats_view *v, char *out, size_t cap){
    if (!out || !cap) return 0;
    tb b = { out, cap, 0 }; out[0] = 0;
    static const char *conn[] = { "offline", "connecting", "waiting in the server queue", "reconnecting", "connected" };
    int cs = v->conn >= NETSTATS_OFFLINE && v->conn <= NETSTATS_CONNECTED ? v->conn : NETSTATS_OFFLINE;
    put(&b, "Connection: %s", conn[cs]);
    if (cs == NETSTATS_QUEUED && v->queue_pos > 0){
        put(&b, "\nPlace in the queue: %d", v->queue_pos);
        if (v->queue_of >= v->queue_pos) put(&b, " of %d", v->queue_of);
    }
    put(&b, "\nRound trip: ");
    if ((cs == NETSTATS_CONNECTED || cs == NETSTATS_QUEUED) && v->rtt_ms >= 0) put(&b, "%d ms", v->rtt_ms);
    else put(&b, "-- ms");
    put(&b, "\nPlayers on the server: ");
    if (v->counts > 0){
        put(&b, "%d", v->c.players);
        put(&b, "\nFree roam: "); count(&b, v->c.roam);
        put(&b, ", Online lobby: "); count(&b, v->c.online);
        if (v->asked_room){ put(&b, "\nRoom \"%s\": ", v->r.room_name[0] ? v->r.room_name : "?"); count(&b, v->c.room); }
        for (int i = 0; i < v->asked_crews && i < NETSTATS_CREWS; i++){
            if (v->r.crew_name[i][0]) put(&b, "\nCrew \"%s\": ", v->r.crew_name[i]);
            else put(&b, "\nCrew %d: ", i + 1);
            count(&b, i < v->c.ncrews ? v->c.crews[i] : -1);
        }
        if (v->c.roam_busy) put(&b, "\nServer busy: fewer cars shown");
    } else put(&b, v->counts < 0 ? "no answer" : "--");
    if (v->free_roam){
        put(&b, "\nCars shown near you: %d", v->r.shown);
        put(&b, "\nLinked by the hub: "); count(&b, v->r.linked);
    }
    return b.n;
}
