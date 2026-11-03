/* native_controls.m -- Game Tools and quick chat.
 *
 * Game Tools (the app menu, Cmd+Shift+M) is a panel beside the game window.
 * With free roam with other players (NFSU2_ROAM=1, roam_game.c): the race
 * lobby at the marker the player is at (roam_game.c mp_panel), its players
 * and countdown, Open / Join / Start and Leave buttons, solid or ghost cars
 * (or everything a ghost: traffic and tuners too)
 * and up to four crews with their colours (changed while the game runs:
 * roam_game.c solid_follow, crews_follow; kept in the launcher's settings, the
 * same defaults domain), the room (changed while the game runs: roam_game.c
 * room_follow; kept in the launcher's settings too), friends (below), a phrase
 * to say, and a log of the notices and phrases.
 *
 * Friends (NFSU2_ROAM_FRIENDS, on unless 0; ported from th0mk's nfsu2-web
 * web/src/app/friends.ts, MIT): with a claimed name (the launcher hands the
 * game its keyphrase's token: net_native.m) the game asks the server for its
 * friends on its link ({"t":"friend","op":"list"}: the hub then links them
 * first and marks them, roam_game.c FRIEND_CREW), tells it the room's name
 * once it has friends (their Join), and asks where they play every minute
 * ("where": a notice when one comes into free roam, and Game Tools' Join).
 * Two cars touching front bumpers for 3 s (roam_game.c bump_*,
 * roam_plat_friend) ask the server what that player is to this one ("can")
 * and a line under the middle of the picture offers "Add Bo as a friend" or
 * "Bo wants to be friends: accept" (F, or the panel's button: "add"), or says
 * why not.  The launcher's Friends lists them outside the game (/friends).
 * Every message goes out from the main thread (friends_tick), never with
 * this file's lock held.  Always: the music folder's controls (radio_native.h): Pause /
 * Resume, Next track, Shuffle, and back to the game's own soundtrack.
 *
 * Quick chat (NFSU2_ROAM_SAY=1, the launcher's Quick chat switch): four
 * groups of four phrases (NFSU2_QUICKCHAT_GROUPS, NFSU2_QUICKCHAT_PHRASES;
 * "Quick chat groups..." in the launcher or in the panel changes them).
 * While the player drives in free roam with the session up
 * (roam_plat_driving), and in a race between players, driving or on its
 * results (racehorn.c says so: native_controls_set_race; Online races, the
 * LAN menu's and free roam's lobby races through the server, with free roam
 * on or off; never a career race or a Quick Race), 1-4 opens a group and 1-4
 * again says one of its phrases; on a controller the right stick flicked up /
 * right / down / left twice does the same (the click opens group 1, B
 * closes).  The picker closes after 4 s, when the game window loses focus or
 * when the player is no longer there; at all other times (offline, in the
 * career's races, in the menus) the keys and the stick go to the game as
 * before.  Free roam takes the picks made in free roam (roam_plat_say_pick),
 * racehorn.c those made in a race (native_controls_race_pick).  What players
 * said in free roam shows over their cars (an overlay on the game window,
 * where roam_game.c tags_update puts their names: roam_plat_say_marks), what
 * they said in a race in a chat log on the left of the picture (the game
 * says nobody where it draws its racers' names), and both in the panel's
 * log.
 *
 * Threads: the guest thread calls the roam_plat_* functions (some with the
 * session lock held) and the pad filter; AppKit runs on the main thread.
 * Both sides only copy bounded state under this file's own lock.
 *
 * The phrases are th0mk's nfsu2-web's (web/src/app/phrases.ts, MIT), in its
 * order: a phrase's number is what goes on the wire, so the list is only ever
 * added to at the end (launcher/QuickChat.swift has the same list). */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <pthread.h>
#include <math.h>
#include <time.h>
#include "native_controls.h"
#include "gamepad.h"
#include "roam_plat.h"
#include "radio_native.h"
#include "names.h"

/* photo mode (native_scene.m, when it is in the build): no quick chat over it */
#ifndef NATIVE_CONTROLS_TEST_SCENE
__attribute__((weak)) int native_scene_active(void){ return 0; }
#else
int native_scene_active(void);
#endif
long metal_frames(void);                       /* metal.m */
__attribute__((weak)) long metal_frames(void){ return 0; }

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;

/* ---- the phrases ------------------------------------------------------------- */
static const char *const phrases[] = {
    "Hey!",
    "Nice car!",
    "Thanks!",
    "Bye!",
    "Yes",
    "No",
    "Sorry!",
    "lol",
    "Follow me!",
    "Wait up!",
    "Let's go!",
    "Nice!",
    "Race?",
    "Join my race!",
    "gg",
    "One more?",
    "Yo!",
    "Hi all!",
    "Welcome!",
    "Welcome back!",
    "Long time no see!",
    "Good luck!",
    "Have fun!",
    "Gotta go!",
    "See you around!",
    "Good night!",
    "brb",
    "Back!",
    "Sure!",
    "Maybe",
    "Okay",
    "Nope",
    "One sec",
    "On my way!",
    "Can't right now",
    "Same",
    "True",
    "What?",
    "Where?",
    "Here!",
    "haha",
    "ty",
    "np",
    "No worries!",
    "My bad!",
    "All good!",
    "Didn't see you!",
    "Lag, sorry!",
    "Thanks for waiting!",
    "Thanks for the race!",
    "Clean build!",
    "Love the vinyl!",
    "Love the colour!",
    "Sick rims!",
    "Nice kit!",
    "Sleeper!",
    "What's under the hood?",
    "Nice drift!",
    "Nice line!",
    "Smooth!",
    "Nice save!",
    "Great driving!",
    "You're fast!",
    "Respect.",
    "Nice driving!",
    "What a save!",
    "Let's cruise!",
    "Convoy!",
    "Lead the way!",
    "I'll lead!",
    "This way!",
    "Turn around!",
    "Slow down!",
    "Speed up!",
    "Shortcut here!",
    "Jump here!",
    "Watch out!",
    "Traffic!",
    "Behind you!",
    "Lost you!",
    "Where are you?",
    "Check the map!",
    "Pull over!",
    "Send it!",
    "Car meet?",
    "Meet here!",
    "Park up!",
    "Line up!",
    "Photo time!",
    "Hold still!",
    "Show your build!",
    "Going to the shop",
    "Going to the garage",
    "Join my crew?",
    "Meet at City Core?",
    "Meet at Beacon Hill?",
    "Meet at Jackson Heights?",
    "Meet at Coal Harbor?",
    "Meet at the airport?",
    "Outrun?",
    "Sprint?",
    "Circuit?",
    "Drag race?",
    "Drift battle?",
    "Street X?",
    "You're on!",
    "Ready?",
    "Ready!",
    "Not ready!",
    "Wait for everyone!",
    "Close one!",
    "So close!",
    "Good race!",
    "Run it back?",
    "Best of three?",
    "You got me!",
    "Too fast for me!",
    "I'm out",
    "Wow!",
    "Whoa!",
    "No way!",
    "Yes!",
    "Let's gooo!",
    "Nooo!",
    "Oops!",
    "Ouch!",
    "Oof",
    "Yikes!",
    "Whew!",
    "omg",
    "What a jump!",
    "Huge air!",
    "Clean!",
    "Unreal!",
    "Calculated.",
    "Classic.",
    "Did you see that?",
    "W",
    "Let him cook",
    "I'm cooked",
    "skill issue",
    "ratio",
    "I'm stuck!",
    "Help?",
    "Lag!",
    "AFK a sec",
    "Out of nitrous",
    "Tuning tips?",
    "Which car is that?",
    "New here!",
    "First time?",
    "On my phone!",
};
#define PHRASE_COUNT ((int)(sizeof phrases / sizeof phrases[0]))
_Static_assert(PHRASE_COUNT == NATIVE_PHRASES, "nfsu2-web's phrases.ts has 152 phrases");
const char *native_controls_phrase(int p){ return p >= 0 && p < PHRASE_COUNT ? phrases[p] : NULL; }

/* ---- quick chat's state (under mu) ------------------------------------------- */
#define CHAT_LINES 32
#define CHAT_SHOW_S    5.0       /* a line over a car: as long as roam_game.c's SAY_SHOW_US */
#define CHAT_OPEN_S    4.0       /* the picker closes by itself after this */
#define CHAT_BURST     3         /* at most this many of the player's own in CHAT_WINDOW_S (roam_game.c SAY_BURST) */
#define CHAT_WINDOW_S  6.0
#define RACE_LOG       5         /* the race's chat log: its last lines, */
#define RACE_LOG_S     8.0       /*   each this long */
static struct { uint32_t id; int phrase, me; double until; } qLines[CHAT_LINES];
static struct { uint32_t id; float x, y, scale; } qMarks[CHAT_LINES];
static int qMarksCount;
static double qMarksAt;
static int qLayout[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
static char qGroupNames[4][100] = {"Greetings", "Replies", "Driving", "Racing"};
static int qNetwork, qDriving, qRace, qFocused, qTestFocus, qGroup = -1, qPad, qArmed = 1, qStickHeld;
static double qDriveAt, qRaceAt, qUntil, qSent[CHAT_BURST];
static struct { char name[64]; int phrase, me; double at; } qRaceLog[RACE_LOG];   /* the oldest first */
static int qRaceLogCount;
static int qSentCount;
static int picks[16], pickHead, pickCount;
static int qPadB, qPadRS;                       /* pad buttons the picker took, until let go */
static BOOL qKeys[128];                         /* keys the picker took: their releases are ours too */
/* the panel's state */
static NSDictionary *lobby;
static NSMutableArray<NSString *> *messages;
static int solid = -1, action;
static uint32_t crewHashes[4], crewRGB[4], crewGeneration;
static NSString *crewNames = @"", *crewColours = @"";
static char roomName[64];
static uint32_t roomGeneration;
static const uint32_t crewDefaults[4] = {0x3cd2ff, 0xff50c8, 0xa078ff, 0xff4646};   /* roam_game.c CREW_RGB */

static double now_s(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
/* a race between players, driving or on its results (racehorn.c said so this frame or the last few) */
static int chat_racing(double now){ return qRace && now - qRaceAt < 0.25; }
/* the keys and the stick are quick chat's: the session takes it and the
 * player drives in free roam (said this frame or the last few), or a race
 * between players; the window has focus, no photo mode */
static int chat_eligible(double now){
    return ((qNetwork && qDriving && now - qDriveAt < 0.25) || chat_racing(now)) && (qFocused || qTestFocus) && !native_scene_active();
}
static void chat_close(void){ qGroup = -1; }
static int chat_enqueue(int phrase){
    if (pickCount == 16) return 0;
    picks[(pickHead + pickCount) % 16] = phrase; pickCount++; return 1;
}
/* the player said CHAT_BURST lately: wait (roam_game.c would not send it) */
static int chat_wait(double now){
    while (qSentCount && now - qSent[0] >= CHAT_WINDOW_S){ memmove(qSent, qSent + 1, (size_t)(--qSentCount) * sizeof *qSent); }
    return qSentCount == CHAT_BURST;
}
static void chat_expire(double now){
    if (qGroup >= 0 && (now >= qUntil || !chat_eligible(now))) chat_close();
    for (int i = 0; i < CHAT_LINES; i++) if (qLines[i].until <= now) qLines[i].id = 0;
}
/* 1-4 (or a flick): the first opens that group, the second says its phrase */
static void chat_choose(int direction, int pad, double now){
    if (qGroup < 0 || qPad != pad){ qGroup = direction; qPad = pad; qUntil = now + CHAT_OPEN_S; return; }
    if (!chat_wait(now) && chat_enqueue(qLayout[qGroup * 4 + direction])) qSent[qSentCount++] = now;
    chat_close();
}
int native_controls_set_chat_layout(const int layout[16]){
    if (!layout) return 0;
    for (int i = 0; i < 16; i++) if (layout[i] < 0 || layout[i] >= PHRASE_COUNT) return 0;
    pthread_mutex_lock(&mu); memcpy(qLayout, layout, sizeof qLayout); chat_close(); pthread_mutex_unlock(&mu);
    return 1;
}
/* a group's name: 1-24 printable ASCII characters, no comma (the list's separator) */
static int group_name_ok(NSString *s){
    if (s.length < 1 || s.length > 24) return 0;
    for (NSUInteger i = 0; i < s.length; i++){ unichar c = [s characterAtIndex:i]; if (c < 32 || c > 126 || c == ',') return 0; }
    return 1;
}

/* ---- the platform calls (roam_plat.h) ------------------------------------------ */
int roam_plat_quickchat(void){ return 1; }
void roam_plat_driving(int driving){
    pthread_mutex_lock(&mu);
    qDriving = !!driving; qDriveAt = now_s();
    if (!driving){ chat_close(); qMarksCount = 0; }
    pthread_mutex_unlock(&mu);
}
void native_controls_action(int a){
    if (a != NATIVE_CONTROL_ENGAGE && a != NATIVE_CONTROL_LEAVE) return;
    pthread_mutex_lock(&mu); action = a; pthread_mutex_unlock(&mu);
}
int roam_plat_action(void){ pthread_mutex_lock(&mu); int a = action; action = 0; pthread_mutex_unlock(&mu); return a; }
/* free roam takes the picks made outside races between players, racehorn.c those made in one */
static int take_pick(int race){
    pthread_mutex_lock(&mu); int p = -1;
    if (pickCount && !!qRace == race){ p = picks[pickHead]; pickHead = (pickHead + 1) % 16; pickCount--; }
    pthread_mutex_unlock(&mu); return p;
}
int roam_plat_say_pick(void){ return take_pick(0); }
int native_controls_race_pick(void){ return take_pick(1); }
void native_controls_set_race(int state){
    pthread_mutex_lock(&mu);
    int was = qRace;
    qRace = state == 1 || state == 2 ? state : 0; qRaceAt = now_s();
    if (!was != !qRace){ pickCount = 0; pickHead = 0; chat_close(); }    /* into a race or out of one: nothing picked before goes */
    if (!was && qRace) qRaceLogCount = 0;                               /* a new race's log */
    pthread_mutex_unlock(&mu);
}
int native_controls_pick(int phrase){
    if (phrase < 0 || phrase >= PHRASE_COUNT) return 0;
    pthread_mutex_lock(&mu); int ok = chat_enqueue(phrase); pthread_mutex_unlock(&mu);
    return ok;
}
int roam_plat_solid(void){ pthread_mutex_lock(&mu); int s = solid; pthread_mutex_unlock(&mu); return s; }
void native_controls_set_solid(int s){ pthread_mutex_lock(&mu); solid = s == 2 ? 2 : !!s; pthread_mutex_unlock(&mu); }
uint32_t roam_plat_crews(uint32_t h[RC_CREW_MAX], uint32_t rgb[RC_CREW_MAX]){
    pthread_mutex_lock(&mu);
    for (int i = 0; i < RC_CREW_MAX; i++){ h[i] = i < 4 ? crewHashes[i] : 0; rgb[i] = i < 4 ? crewRGB[i] : 0; }
    uint32_t g = crewGeneration; pthread_mutex_unlock(&mu); return g;
}
uint32_t roam_plat_room(char name[64]){
    pthread_mutex_lock(&mu);
    memcpy(name, roomName, 64); name[63] = 0;
    uint32_t g = roomGeneration; pthread_mutex_unlock(&mu); return g;
}
void roam_plat_say_marks(const uint32_t *ids, const float *xy, int count){
    pthread_mutex_lock(&mu); qMarksCount = 0; qMarksAt = now_s();
    for (int i = 0; ids && xy && i < count && i < CHAT_LINES; i++){
        float x = xy[3 * i], y = xy[3 * i + 1], sc = xy[3 * i + 2];
        if (!ids[i] || !isfinite(x) || !isfinite(y) || !isfinite(sc) || x < 0 || x > 1 || y < 0 || y > 1 || sc <= 0) continue;
        int n = qMarksCount++; qMarks[n].id = ids[i]; qMarks[n].x = x; qMarks[n].y = y; qMarks[n].scale = MIN(sc, 1.f);
    }
    pthread_mutex_unlock(&mu);
}
void native_controls_set_network(int say){
    pthread_mutex_lock(&mu); qNetwork = !!say; pthread_mutex_unlock(&mu);
    if (!say) native_controls_forget(0);
}
void native_controls_forget(uint32_t id){
    pthread_mutex_lock(&mu);
    for (int i = 0; i < CHAT_LINES; i++) if (!id || qLines[i].id == id) qLines[i].id = 0;
    if (!id){ qMarksCount = 0; pickCount = 0; pickHead = 0; qSentCount = 0; chat_close(); }
    pthread_mutex_unlock(&mu);
}

static NSString *utf8n(const char *s, size_t max){
    if (!s) return @"";
    return [[NSString alloc] initWithBytes:s length:strnlen(s, max) encoding:NSUTF8StringEncoding] ?: @"";
}
static void add_message(NSString *text){
    pthread_mutex_lock(&mu);
    if (!messages) messages = [NSMutableArray array];
    if (messages.count == 64) [messages removeObjectAtIndex:0];
    [messages addObject:text];
    pthread_mutex_unlock(&mu);
}
void native_controls_notice(const char *name, const char *what){ @autoreleasepool {
    add_message([NSString stringWithFormat:@"%@%@", utf8n(name, 256), utf8n(what, 512)]);
} }
static NSDictionary *json_object(const char *json){
    if (!json || strnlen(json, 8193) > 8192) return nil;
    NSData *data = [NSData dataWithBytes:json length:strlen(json)];
    id o = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [o isKindOfClass:NSDictionary.class] ? o : nil;
}
static BOOL json_int(id v, double lo, double hi){
    if (![v isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return NO;
    double n = [v doubleValue];
    return isfinite(n) && floor(n) == n && n >= lo && n <= hi;
}
/* a phrase said: {"id", "name", "p"} (+ "me": the player's own, "lobby": one
 * of our race lobby's, "race": one said in a race between players,
 * racehorn.c) -> a line over that car (in a race: in the race's chat log) and
 * in the panel's log.  A number past our list (a newer game's phrase) is
 * taken and not shown */
int roam_plat_said(const char *json){ @autoreleasepool {
    NSDictionary *s = json_object(json);
    if (!s || !json_int(s[@"id"], 1, UINT32_MAX) || ![s[@"name"] isKindOfClass:NSString.class] || [s[@"name"] length] > 128) return -1;
    if (!json_int(s[@"p"], 0, 255)) return -1;
    if (s[@"me"] && !json_int(s[@"me"], 0, 1)) return -1;
    if (s[@"lobby"] && !json_int(s[@"lobby"], 0, 1)) return -1;
    if (s[@"race"] && !json_int(s[@"race"], 0, 1)) return -1;
    int p = [s[@"p"] intValue];
    if (p >= PHRASE_COUNT) return 1;
    BOOL me = [s[@"me"] intValue] == 1;
    uint32_t id = [s[@"id"] unsignedIntValue];
    if ([s[@"race"] intValue] == 1){
        pthread_mutex_lock(&mu);
        if (qRaceLogCount == RACE_LOG){ memmove(qRaceLog, qRaceLog + 1, (RACE_LOG - 1) * sizeof *qRaceLog); qRaceLogCount--; }
        int n = qRaceLogCount++;
        snprintf(qRaceLog[n].name, sizeof qRaceLog[n].name, "%s", me ? "You" : [s[@"name"] UTF8String]);
        qRaceLog[n].phrase = p; qRaceLog[n].me = me; qRaceLog[n].at = now_s();
        pthread_mutex_unlock(&mu);
        add_message([NSString stringWithFormat:@"%@ (race): %s", me ? @"You" : s[@"name"], phrases[p]]);
        return 1;
    }
    pthread_mutex_lock(&mu);
    double now = now_s(); int slot = 0;
    for (int i = 1; i < CHAT_LINES; i++) if (qLines[i].until < qLines[slot].until) slot = i;      /* the oldest, */
    for (int i = 0; i < CHAT_LINES; i++) if (!qLines[i].id || qLines[i].until <= now){ slot = i; break; }   /* a free one, */
    for (int i = 0; i < CHAT_LINES; i++) if (qLines[i].id == id){ slot = i; break; }     /* the same player's */
    qLines[slot].id = id; qLines[slot].phrase = p; qLines[slot].me = me; qLines[slot].until = now + CHAT_SHOW_S;
    pthread_mutex_unlock(&mu);
    add_message([NSString stringWithFormat:@"%@: %s", me ? @"You" : s[@"name"], phrases[p]]);
    return 1;
} }
/* the race lobby (roam_game.c mp_panel's JSON): checked, then kept for the panel */
int roam_plat_lobby(const char *json){ @autoreleasepool {
    NSDictionary *st = json_object(json); if (!st) return -1;
    if (st[@"v"] && ![@[@"spot", @"join", @"full", @"lobby", @"trip", @"note"] containsObject:st[@"v"]]) return -1;
    if (st[@"st"] && ![@[@"host", @"asked", @"in", @"count"] containsObject:st[@"st"]]) return -1;
    for (NSString *k in @[@"v", @"st", @"kind", @"track", @"text", @"step", @"why"])
        if (st[k] && ![st[k] isKindOfClass:NSString.class]) return -1;
    for (NSString *k in @[@"t", @"away", @"closes", @"laps", @"stage", @"max", @"me", @"fee", @"even", @"prize"])
        if (st[k] && !json_int(st[k], -1, 1e9)) return -1;
    id names = st[@"names"];
    if (names){
        if (![names isKindOfClass:NSArray.class] || [names count] > RC_LOBBY_MAX) return -1;
        for (id n in names) if (![n isKindOfClass:NSString.class] || [n length] > 128) return -1;
    }
    pthread_mutex_lock(&mu); lobby = st; pthread_mutex_unlock(&mu);
    return 1;
} }

/* ---- friends (net_native.m's link; any thread in, the main thread out) ------------------------- */
__attribute__((weak)) int native_net_text(const char *json){ (void)json; return 0; }   /* net_native.m */
#define FRIEND_LIST_TRY_S  2.0       /* the list tried this often until the link takes it */
#define FRIEND_WHERE_S     60.0      /* where the friends play, asked this often while there are some */
#define FRIEND_TOAST_S     6.0
static int fOn = -1, fClaimed, fListed, fPendCan, fPendAdd;
static double fListTry, fWhereAt, fToastUntil;
static NSString *fMe, *fRoomSent, *fToast;
static NSArray<NSString *> *fFriends;
static NSArray<NSDictionary *> *fWhere;                 /* [{name, where: roam|online|"", room?}], the server's last */
static NSMutableDictionary<NSString *, NSString *> *fWas;   /* each friend's where (lower case name), for the notices */
static NSMutableSet<NSString *> *fAsksNoted;
static uint32_t fOfferId;
static NSString *fOfferName, *fOfferSt;                 /* the car touched; "wait", "new", "asks", "asked", "friends", "claim", "theirs" */
static int friends_on(void){
    if (fOn < 0){ const char *r = getenv("NFSU2_ROAM"), *f = getenv("NFSU2_ROAM_FRIENDS"); fOn = r && *r == '1' && !(f && *f == '0'); }
    return fOn;
}
/* two names of one player: the same Online form, in any case (the name over a car, a claimed name) */
static NSString *online_form(NSString *s){
    NSMutableString *o = [NSMutableString string]; BOOL gap = NO;
    for (NSUInteger i = 0; i < s.length && o.length < 15; i++){
        unichar c = [s characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok){ gap = YES; continue; }
        if (gap && o.length && o.length < 14) [o appendString:@"_"];
        gap = NO; [o appendFormat:@"%C", c];
    }
    while (o.length && o.length < 3) [o appendString:@"_"];
    return o.length ? o.lowercaseString : s.lowercaseString;
}
static BOOL same_player(NSString *a, NSString *b){ return a && b && [online_form(a) isEqualToString:online_form(b)]; }
static void friend_toast(NSString *text){
    pthread_mutex_lock(&mu); fToast = text; fToastUntil = now_s() + FRIEND_TOAST_S; pthread_mutex_unlock(&mu);
    add_message(text);
}
static NSString *room_now(void){
    pthread_mutex_lock(&mu);
    NSString *r = roomGeneration ? [NSString stringWithUTF8String:roomName] : nil; pthread_mutex_unlock(&mu);
    if (!r){ const char *e = getenv("NFSU2_ROAM_ROOM"); r = native_controls_tidy_name(e ? [NSString stringWithUTF8String:e] ?: @"" : @""); }
    return r ?: @"";
}
static BOOL in_room(NSDictionary *f, NSString *mine){
    return [f[@"where"] isEqual:@"roam"] && [f[@"room"] isKindOfClass:NSString.class] && rc_room_hash([f[@"room"] UTF8String]) == rc_room_hash(mine.UTF8String);
}
/* the link is up (again): the list asked again, the room's name told again */
void native_controls_net_welcome(int claimed){
    pthread_mutex_lock(&mu); fClaimed = claimed; fListed = 0; fListTry = 0; fRoomSent = nil; pthread_mutex_unlock(&mu);
}
/* the car touched nose to nose for 3 s (on 1), or parted (roam_game.c bump_page): {"id","name","on"} */
int roam_plat_friend(const char *json){ @autoreleasepool {
    NSDictionary *m = json_object(json);
    if (!m || !json_int(m[@"id"], 0, UINT32_MAX) || ![m[@"name"] isKindOfClass:NSString.class] || [m[@"name"] length] > 64 || !json_int(m[@"on"], 0, 1)) return -1;
    if (!friends_on()) return 1;
    NSString *name = m[@"name"];
    pthread_mutex_lock(&mu);
    if ([m[@"on"] intValue] == 1){ fOfferId = [m[@"id"] unsignedIntValue]; fOfferName = name; fOfferSt = @"wait"; fPendCan = 1; fPendAdd = 0; }
    else if (same_player(fOfferName, name)){ fOfferName = nil; fOfferSt = nil; fPendCan = fPendAdd = 0; }
    pthread_mutex_unlock(&mu);
    return 1;
} }
/* what the line under the picture says now (0: none), and whether F (or the panel's button) does something */
int native_controls_friend_line(char *buf, size_t cap, int *actionable){ @autoreleasepool {
    pthread_mutex_lock(&mu); NSString *n = fOfferName, *st = fOfferSt; pthread_mutex_unlock(&mu);
    NSString *t = nil;
    if ([st isEqual:@"new"]) t = [NSString stringWithFormat:@"F: add %@ as a friend", n];
    else if ([st isEqual:@"asks"]) t = [NSString stringWithFormat:@"F: %@ wants to be friends, accept", n];
    else if ([st isEqual:@"asked"]) t = [NSString stringWithFormat:@"Friend request sent to %@", n];
    else if ([st isEqual:@"friends"]) t = [NSString stringWithFormat:@"You and %@ are friends", n];
    else if ([st isEqual:@"claim"]) t = @"Claim your name in the launcher (Settings, Online) to add friends";
    else if ([st isEqual:@"theirs"]) t = [NSString stringWithFormat:@"%@ has no claimed name, so can't add friends yet", n];
    if (actionable) *actionable = [st isEqual:@"new"] || [st isEqual:@"asks"];
    if (buf && cap) snprintf(buf, cap, "%s", t ? t.UTF8String : "");
    return t != nil;
} }
/* F, or the panel's button: the request (or the answer to theirs) */
int native_controls_friend_act(void){
    pthread_mutex_lock(&mu);
    int ok = fOfferName && ([fOfferSt isEqual:@"new"] || [fOfferSt isEqual:@"asks"]);
    if (ok){ fPendAdd = 1; fOfferSt = @"wait"; }
    pthread_mutex_unlock(&mu);
    return ok;
}
static NSString *where_text(NSDictionary *f, NSString *mine){
    if ([f[@"where"] isEqual:@"roam"]){
        if (in_room(f, mine)) return @"free roam, your room";
        NSString *r = f[@"room"];
        return [r isKindOfClass:NSString.class] ? (r.length ? [NSString stringWithFormat:@"free roam, room %@", r] : @"free roam, no room") : @"free roam";
    }
    return [f[@"where"] isEqual:@"online"] ? @"Online lobby" : @"offline";
}
/* the friends in free roam in another room (a Join each): name and room ("" everyone's); the panel's popup */
NSArray<NSArray<NSString *> *> *native_controls_friends_to_join(void){
    NSString *mine = room_now();
    pthread_mutex_lock(&mu); NSArray *w = fWhere; pthread_mutex_unlock(&mu);
    NSMutableArray *o = [NSMutableArray array];
    for (NSDictionary *f in w) if ([f[@"where"] isEqual:@"roam"] && [f[@"room"] isKindOfClass:NSString.class] && !in_room(f, mine)) [o addObject:@[f[@"name"], f[@"room"]]];
    return o;
}
/* a server message of friends' ({"t":"friend",...}, net_native.m's queue) */
void native_controls_net_friend(const char *json){ @autoreleasepool {
    NSDictionary *m = json_object(json);
    if (!m || !friends_on() || ![m[@"op"] isKindOfClass:NSString.class]) return;
    NSString *op = m[@"op"], *name = [m[@"name"] isKindOfClass:NSString.class] ? m[@"name"] : @"";
    if (name.length > 64) return;
    NSMutableArray<NSString *> *toasts = [NSMutableArray array], *lines = [NSMutableArray array];
    pthread_mutex_lock(&mu);
    BOOL mine = fOfferName && name.length && same_player(fOfferName, name);
    if ([op isEqual:@"list"]){
        NSMutableArray *fr = [NSMutableArray array];
        if ([m[@"friends"] isKindOfClass:NSArray.class]) for (id f in m[@"friends"]) if ([f isKindOfClass:NSString.class] && [f length] <= 64) [fr addObject:f];
        fFriends = fr; fMe = [m[@"me"] isKindOfClass:NSString.class] ? m[@"me"] : nil; fListed = 1; fWhereAt = 0;
        if (!fAsksNoted) fAsksNoted = [NSMutableSet set];
        if ([m[@"asks"] isKindOfClass:NSArray.class]) for (id a in m[@"asks"])
            if ([a isKindOfClass:NSString.class] && [a length] <= 64 && ![fAsksNoted containsObject:[a lowercaseString]]){
                [fAsksNoted addObject:[a lowercaseString]];
                [lines addObject:[NSString stringWithFormat:@"%@ wants to be friends: accept in the launcher (Settings, Online, Friends)", a]];
            }
        if ([m[@"mail"] isKindOfClass:NSArray.class]) for (id x in m[@"mail"])
            if ([x isKindOfClass:NSDictionary.class] && [x[@"from"] isKindOfClass:NSString.class] && [x[@"body"] isKindOfClass:NSString.class])
                [lines addObject:[NSString stringWithFormat:@"Message from %@: %@", x[@"from"], [x[@"body"] substringToIndex:MIN([x[@"body"] length], 500u)]]];
    } else if ([op isEqual:@"where"] && [m[@"friends"] isKindOfClass:NSArray.class]){
        NSMutableArray *w = [NSMutableArray array];
        for (id f in m[@"friends"]){
            if (![f isKindOfClass:NSDictionary.class] || ![f[@"name"] isKindOfClass:NSString.class] || [f[@"name"] length] > 64) continue;
            NSMutableDictionary *e = [@{ @"name": f[@"name"], @"where": [@[@"roam", @"online"] containsObject:f[@"where"]] ? f[@"where"] : @"" } mutableCopy];
            if ([f[@"room"] isKindOfClass:NSString.class] && [f[@"room"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 63) e[@"room"] = f[@"room"];
            [w addObject:e];
        }
        NSMutableDictionary *was = fWas ?: [NSMutableDictionary dictionary];
        fWas = [NSMutableDictionary dictionary]; fWhere = w;
        pthread_mutex_unlock(&mu);
        NSString *mineRoom = room_now();
        pthread_mutex_lock(&mu);
        for (NSDictionary *f in w){
            NSString *key = [f[@"name"] lowercaseString];
            fWas[key] = f[@"where"];
            if (![f[@"where"] isEqual:@"roam"] || [was[key] isEqual:@"roam"]) continue;
            NSString *r = f[@"room"];
            [toasts addObject:!r || in_room(f, mineRoom) ? [NSString stringWithFormat:@"Your friend %@ is in free roam", f[@"name"]]
                            : r.length ? [NSString stringWithFormat:@"Your friend %@ is in free roam, room %@: Join in Game Tools (Cmd+Shift+M)", f[@"name"], r]
                            : [NSString stringWithFormat:@"Your friend %@ is in free roam, in no room: Join in Game Tools (Cmd+Shift+M)", f[@"name"]]];
        }
    } else if ([op isEqual:@"can"]){
        if (mine){
            NSString *st = [m[@"st"] isKindOfClass:NSString.class] ? m[@"st"] : @"";
            if ([st isEqual:@"far"]){ fOfferName = nil; fOfferSt = nil; }
            else if ([@[@"new", @"asks", @"asked", @"friends", @"claim", @"theirs"] containsObject:st]){ fOfferName = name; fOfferSt = st; }
        }
    } else if ([op isEqual:@"add"]){
        NSString *done = [m[@"done"] isKindOfClass:NSString.class] ? m[@"done"] : @"";
        if ([done isEqual:@"friends"]){ if (!fWas) fWas = [NSMutableDictionary dictionary]; fWas[name.lowercaseString] = @"roam"; }
        if ([done isEqual:@"friends"] && !mine) [toasts addObject:[NSString stringWithFormat:@"You and %@ are friends now", name]];
        else if ([done isEqual:@"full"]) [toasts addObject:@"A friends list is full (50 at most)"];
        if (mine && [@[@"asked", @"friends", @"claim", @"theirs"] containsObject:done]) fOfferSt = done;
        else if (mine && [done isEqual:@"full"]){ fOfferName = nil; fOfferSt = nil; }
        if (mine && [done isEqual:@"asked"]) [lines addObject:[NSString stringWithFormat:@"Friend request sent to %@", name]];
        if (mine && [done isEqual:@"friends"]) [lines addObject:[NSString stringWithFormat:@"You and %@ are friends now", name]];
    } else if ([op isEqual:@"asks"]){
        if (mine && fOfferName) fOfferSt = @"asks";
        else [toasts addObject:[NSString stringWithFormat:@"%@ wants to be friends: answer in the launcher (Settings, Online, Friends)", name]];
    } else if ([op isEqual:@"friends"]){
        if (!fWas) fWas = [NSMutableDictionary dictionary];
        fWas[name.lowercaseString] = @"roam";
        if (mine && fOfferName){ fOfferSt = @"friends"; [lines addObject:[NSString stringWithFormat:@"You and %@ are friends now", name]]; }
        else [toasts addObject:[NSString stringWithFormat:@"You and %@ are friends now", name]];
    } else if ([op isEqual:@"mail"] && [m[@"from"] isKindOfClass:NSString.class] && [m[@"body"] isKindOfClass:NSString.class]){
        [toasts addObject:[NSString stringWithFormat:@"Message from %@: %@", m[@"from"], [m[@"body"] substringToIndex:MIN([m[@"body"] length], 500u)]]];
    }
    pthread_mutex_unlock(&mu);
    for (NSString *t in lines) add_message(t);
    for (NSString *t in toasts) friend_toast(t);
} }
static NSString *friend_json(NSDictionary *d){
    NSData *data = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}
/* the main thread, ~30 times a second: what is due goes out (never with the lock held: net_native.m waits for its
 * own queue, whose messages come in here under it) */
void native_controls_friends_tick(double now){ @autoreleasepool {
    if (!friends_on()) return;
    NSString *room = room_now();
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    pthread_mutex_lock(&mu);
    int list = 0, where = 0, sendRoom = 0, can = 0, add = 0;
    NSString *who = fOfferName;
    if (fClaimed){
        if (!fListed && now - fListTry >= FRIEND_LIST_TRY_S){ fListTry = now; list = 1; fListed = 1; }   /* (again if not sent) */
        if (fListed && fFriends.count && now - fWhereAt >= FRIEND_WHERE_S){ fWhereAt = now; where = 1; }
        if (fListed && fFriends.count && ![room isEqual:fRoomSent]){ fRoomSent = room; sendRoom = 1; }
    }
    if (fPendCan && who){ fPendCan = 0; can = fClaimed; if (!fClaimed) fOfferSt = @"claim"; }
    if (fPendAdd && who){ fPendAdd = 0; add = 1; }
    pthread_mutex_unlock(&mu);
    if (list) [out addObject:@{ @"t": @"friend", @"op": @"list" }];
    if (sendRoom) [out addObject:@{ @"t": @"room", @"name": room }];
    if (where) [out addObject:@{ @"t": @"friend", @"op": @"where" }];
    if (can) [out addObject:@{ @"t": @"friend", @"op": @"can", @"name": who }];
    if (add) [out addObject:@{ @"t": @"friend", @"op": @"add", @"name": who }];
    for (NSDictionary *d in out){
        NSString *j = friend_json(d);
        int sent = j && native_net_text(j.UTF8String);
        if (sent) continue;
        pthread_mutex_lock(&mu);                          /* not sent: again (the list) or forgotten (the line goes) */
        if ([d[@"t"] isEqual:@"room"]) fRoomSent = nil;
        if ([d[@"op"] isEqual:@"list"]) fListed = 0;
        if ([d[@"op"] isEqual:@"can"] || [d[@"op"] isEqual:@"add"]){ fOfferName = nil; fOfferSt = nil; }
        pthread_mutex_unlock(&mu);
    }
    if (list || can || add) fprintf(stderr, "[friends] %s%s%s\n", list ? "asked for the list " : "", can ? "asked what the player touched is " : "",
                                    add ? "sent the request (or the answer)" : "");
} }
/* the toast at the top of the picture (a friend in free roam, a request, friends now): "" none */
static NSString *friend_toast_now(double now){
    pthread_mutex_lock(&mu); NSString *t = now < fToastUntil ? fToast : nil; pthread_mutex_unlock(&mu);
    return t;
}
int native_controls_friend_toast(char *buf, size_t cap){ @autoreleasepool {
    NSString *t = friend_toast_now(now_s());
    if (buf && cap) snprintf(buf, cap, "%s", t ? t.UTF8String : "");
    return t != nil;
} }

/* ---- the controller (guest thread) --------------------------------------------- */
void native_controls_pad(int connected, float *rx, float *ry, int *b, int *rs){
    pthread_mutex_lock(&mu);
    double now = now_s();
    if (!connected){ if (qPad) chat_close(); qPadB = qPadRS = qStickHeld = 0; qArmed = 1; pthread_mutex_unlock(&mu); return; }
    if (!*b) qPadB = 0;
    if (!*rs) qPadRS = 0;
    float x = *rx, y = *ry, r = hypotf(x, y);                         /* y: up is negative */
    if (r < 0.35f){ qArmed = 1; qStickHeld = 0; }
    chat_expire(now);
    if (chat_eligible(now)){
        if (qGroup >= 0 && *b){ qPadB = 1; chat_close(); }                                   /* B closes */
        else if (*rs && !qPadRS){ qPadRS = 1; qGroup = 0; qPad = 1; qUntil = now + CHAT_OPEN_S; }   /* the click: group 1 */
        else if (r >= 0.8f && qArmed){
            qArmed = 0; qStickHeld = 1;
            int d = fabsf(x) > fabsf(y) ? (x > 0 ? 1 : 3) : (y < 0 ? 0 : 2);   /* up, right, down, left */
            chat_choose(d, 1, now);
        }
    } else qArmed = r < 0.35f;
    /* the game sees no stick while it picks, nor the buttons it took */
    if (qStickHeld || (qGroup >= 0 && qPad)) *rx = *ry = 0;
    if (qPadB) *b = 0;
    if (qPadRS) *rs = 0;
    pthread_mutex_unlock(&mu);
}
/* dinput_pad.c's pad, right before the game reads it (its weak default is a no-op) */
void native_controls_filter_pad(PadState *s){
    float x = s->axis[PAD_AXIS_RX], y = s->axis[PAD_AXIS_RY];
    int b = (s->buttons >> PAD_B) & 1, rs = (s->buttons >> PAD_RS) & 1;
    native_controls_pad(s->connected, &x, &y, &b, &rs);
    if (!s->connected) return;
    s->axis[PAD_AXIS_RX] = x; s->axis[PAD_AXIS_RY] = y;
    if (!b) s->buttons &= ~(1u << PAD_B);
    if (!rs) s->buttons &= ~(1u << PAD_RS);
}

/* ---- the keyboard (main thread) -------------------------------------------------- */
static NSWindow *g_game;
@class GameTools;
static GameTools *ui;
static BOOL ours(NSWindow *w);
int native_controls_handle_event(NSEvent *ev){
    if (ev.type != NSEventTypeKeyDown && ev.type != NSEventTypeKeyUp) return 0;
    /* typing in one of our panels: AppKit's, not the game's */
    if (g_game && ev.window && ev.window != g_game){ if (ours(ev.window)){ [NSApp sendEvent:ev]; return 1; } return 0; }
    unsigned code = ev.keyCode; if (code >= 128) return 0;
    pthread_mutex_lock(&mu);
    if (ev.type == NSEventTypeKeyUp){ int mine = qKeys[code]; qKeys[code] = NO; pthread_mutex_unlock(&mu); return mine; }
    if (qKeys[code]){ pthread_mutex_unlock(&mu); return 1; }        /* held: its repeats are ours too */
    double now = now_s();
    chat_expire(now);
    /* F while a friend's line offers something (the game has no use for F) */
    if (code == 3 && fOfferName && ([fOfferSt isEqual:@"new"] || [fOfferSt isEqual:@"asks"]) && qDriving && (qFocused || qTestFocus) &&
        now - qDriveAt < 0.25 && !native_scene_active() && !(ev.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))){
        qKeys[code] = YES;
        if (!ev.isARepeat){ fPendAdd = 1; fOfferSt = @"wait"; }
        pthread_mutex_unlock(&mu);
        return 1;
    }
    int d = -1;
    switch (code){                                                   /* 1-4, also on the keypad */
    case 18: case 83: d = 0; break; case 19: case 84: d = 1; break;
    case 20: case 85: d = 2; break; case 21: case 86: d = 3; break;
    default: break;
    }
    int mine = chat_eligible(now) && !(ev.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) &&
               (d >= 0 || (code == 53 && qGroup >= 0));              /* Esc closes the picker */
    if (mine){ qKeys[code] = YES; if (!ev.isARepeat){ if (code == 53) chat_close(); else chat_choose(d, 0, now); } }
    pthread_mutex_unlock(&mu);
    return mine;
}

/* ---- the crews --------------------------------------------------------------------- */
static NSString *trim(NSString *s){ return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
int native_controls_set_crews(const char *names, const char *colours, char *error, size_t capacity){ @autoreleasepool {
    NSString *value = names ? [NSString stringWithUTF8String:names] : @"", *col = colours ? [NSString stringWithUTF8String:colours] : @"";
    NSString *why = nil; uint32_t h[4] = {0}, rgb[4] = {0};
    NSMutableArray *clean = [NSMutableArray array], *cleanRGB = [NSMutableArray array];
    NSArray *parts = [value componentsSeparatedByString:@","], *colparts = [col componentsSeparatedByString:@","];
    if (!value || !col || parts.count > 4 || colparts.count > 4) why = @"Use up to four crews and colours.";
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@";#\x7f"];
    for (NSUInteger i = 0; !why && i < parts.count; i++){
        /* spaces inside a name count once, at its ends not at all */
        NSString *name = [[[trim(parts[i]) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                             filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
        NSString *colour = i < colparts.count ? trim(colparts[i]) : @"";
        if (colour.length && (colour.length != 6 || [colour rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound))
            { why = @"Colours are six hex digits (RRGGBB)."; break; }
        if (!name.length) continue;
        NSUInteger length = [name lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding] / 4;
        if (length > 24 || [name rangeOfCharacterFromSet:bad].location != NSNotFound || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)
            { why = @"A crew name has up to 24 characters; no #, ; or control characters."; break; }
        uint32_t x = rc_room_hash(name.UTF8String); NSUInteger n = clean.count;
        if (!x || name_blocked(name.UTF8String)){ why = @"Choose another crew name."; break; }
        for (NSUInteger k = 0; k < n; k++) if (h[k] == x) why = @"That crew is in the list twice.";
        if (why) break;
        unsigned c = crewDefaults[n];
        if (colour.length) [[NSScanner scannerWithString:colour] scanHexInt:&c];
        h[n] = x; rgb[n] = c ? c : crewDefaults[n];
        [clean addObject:name]; [cleanRGB addObject:[NSString stringWithFormat:@"%06x", rgb[n]]];
    }
    if (why){ if (error && capacity) snprintf(error, capacity, "%s", why.UTF8String); return 0; }
    pthread_mutex_lock(&mu);
    memcpy(crewHashes, h, sizeof h); memcpy(crewRGB, rgb, sizeof rgb);
    crewNames = [clean componentsJoinedByString:@", "]; crewColours = [cleanRGB componentsJoinedByString:@","];
    if (!++crewGeneration) ++crewGeneration;
    pthread_mutex_unlock(&mu);
    return 1;
} }

/* ---- the room ------------------------------------------------------------------------ */
/* a typed or linked name as it is kept: composed (NFC), its blanks single spaces, the invisible characters out
 * (the ones rc_room_hash leaves out), trimmed (nfsu2-web's invite.ts tidyName) */
NSString *native_controls_tidy_name(NSString *s){
    s = s.precomposedStringWithCanonicalMapping ?: @"";
    NSMutableString *o = [NSMutableString string]; BOOL gap = NO;
    for (NSUInteger i = 0; i < s.length; ){
        NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:i]; NSString *ch = [s substringWithRange:r]; i = NSMaxRange(r);
        unichar u = [ch characterAtIndex:0];
        if (u == 0xAD || (u >= 0x200B && u <= 0x200D) || u == 0x2060 || u == 0xFEFF) continue;
        BOOL blank = [ch rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound ||
                     u == 0xA0 || u == 0x1680 || (u >= 0x2000 && u <= 0x200A) || u == 0x2028 || u == 0x2029 || u == 0x202F || u == 0x205F || u == 0x3000;
        if (blank){ gap = o.length > 0; continue; }
        if (gap) [o appendString:@" "];
        gap = NO; [o appendString:ch];
    }
    return o;
}
int native_controls_set_room(const char *name, char *error, size_t capacity){ @autoreleasepool {
    NSString *s = native_controls_tidy_name(name ? [NSString stringWithUTF8String:name] ?: @"" : @""), *why = nil;
    const char *u = s.UTF8String;
    if (strlen(u) > 63) why = @"A room name has up to 63 bytes.";
    else if ([s rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) why = @"No control characters in a room name.";
    else if ([s hasPrefix:@"#"] || [s hasPrefix:@";"] || [s rangeOfString:@" #"].location != NSNotFound || [s rangeOfString:@" ;"].location != NSNotFound)
        why = @"No # or ; after a space in a room name.";
    else if (s.length && (!rc_room_hash(u) || name_blocked(u))) why = @"Choose another room name.";
    if (why){ if (error && capacity) snprintf(error, capacity, "%s", why.UTF8String); return 0; }
    pthread_mutex_lock(&mu);
    snprintf(roomName, sizeof roomName, "%s", rc_room_hash(u) ? u : "");
    if (!++roomGeneration) ++roomGeneration;
    pthread_mutex_unlock(&mu);
    return 1;
} }

/* ---- the overlay over the game: the picker and the lines over the cars ------------ */
@interface GameToolsOverlay : NSView @end
@implementation GameToolsOverlay
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)p { (void)p; return nil; }
/* where the game's picture is in the window (the layer keeps its aspect: bars on the sides or above and below) */
- (NSRect)picture {
    NSRect b = self.bounds;
    CALayer *l = self.superview.layer;
    CGSize d = [l isKindOfClass:CAMetalLayer.class] ? ((CAMetalLayer *)l).drawableSize : CGSizeZero;
    if (d.width <= 0 || d.height <= 0 || b.size.width <= 0 || b.size.height <= 0) return b;
    CGFloat k = MIN(b.size.width / d.width, b.size.height / d.height), w = d.width * k, h = d.height * k;
    return NSMakeRect(b.origin.x + (b.size.width - w) / 2, b.origin.y + (b.size.height - h) / 2, w, h);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty; double now = now_s();
    pthread_mutex_lock(&mu);
    int group = qGroup, pad = qPad, layout[16]; memcpy(layout, qLayout, sizeof layout);
    char gname[100]; snprintf(gname, sizeof gname, "%s", group >= 0 ? qGroupNames[group] : "");
    BOOL visible = chat_eligible(now), wait = chat_wait(now);
    BOOL driving = qDriving && (qFocused || qTestFocus) && now - qDriveAt < 0.25 && !native_scene_active(), shown = (qFocused || qTestFocus);
    typeof(qLines) lines; memcpy(lines, qLines, sizeof lines);
    typeof(qMarks) marks; memcpy(marks, qMarks, sizeof marks);
    int count = now - qMarksAt < 0.15 ? qMarksCount : 0;
    typeof(qRaceLog) rlog; memcpy(rlog, qRaceLog, sizeof rlog);
    int rlogs = chat_racing(now) && shown && !native_scene_active() ? qRaceLogCount : 0;
    pthread_mutex_unlock(&mu);
    NSRect pic = self.picture;
    CGFloat k = MAX(0.75, MIN(1.6, MIN(pic.size.width / 1280, pic.size.height / 720)));
    /* friends: the front bumpers' line under the middle of the picture while driving, a toast at its top */
    char fl[200]; int act = 0;
    NSString *toast = shown ? friend_toast_now(now) : nil;
    NSString *line = driving && native_controls_friend_line(fl, sizeof fl, &act) ? [NSString stringWithUTF8String:fl] : nil;
    for (int i = 0; i < 2; i++){
        NSString *t = i ? toast : line;
        if (!t.length) continue;
        NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:15 * k weight:NSFontWeightSemibold],
                            NSForegroundColorAttributeName: i == 0 && act ? [NSColor colorWithSRGBRed:0.89 green:0.94 blue:0.82 alpha:1] : NSColor.whiteColor};
        NSSize ts = [t sizeWithAttributes:a];
        CGFloat y = i ? pic.origin.y + 18 * k : pic.origin.y + pic.size.height * 0.62;
        NSRect box = NSMakeRect(pic.origin.x + (pic.size.width - ts.width) / 2 - 12 * k, y, ts.width + 24 * k, ts.height + 12 * k);
        [[NSColor colorWithWhite:0.04 alpha:0.85] setFill]; [[NSBezierPath bezierPathWithRoundedRect:box xRadius:8 * k yRadius:8 * k] fill];
        [t drawAtPoint:NSMakePoint(box.origin.x + 12 * k, box.origin.y + 6 * k) withAttributes:a];
    }
    /* a race's chat log: on the left, under the picker's place, each line for RACE_LOG_S */
    for (int i = 0, row = 0; i < rlogs; i++){
        if (now - rlog[i].at >= RACE_LOG_S) continue;
        CGFloat alpha = MIN(1, (RACE_LOG_S - (now - rlog[i].at)) / 0.6);
        NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:14 * k weight:NSFontWeightSemibold],
                            NSForegroundColorAttributeName: [(rlog[i].me ? [NSColor colorWithSRGBRed:0.89 green:0.94 blue:0.82 alpha:1] : NSColor.whiteColor)
                                                             colorWithAlphaComponent:alpha]};
        NSString *t = [NSString stringWithFormat:@"%@: %s", [NSString stringWithUTF8String:rlog[i].name] ?: @"", phrases[rlog[i].phrase]];
        NSSize ts = [t sizeWithAttributes:a];
        NSRect box = NSMakeRect(pic.origin.x + 20 * k, pic.origin.y + (190 + 30 * row++) * k, MIN(ts.width + 20 * k, pic.size.width * 0.6), ts.height + 8 * k);
        [[NSColor colorWithWhite:0.04 alpha:0.8 * alpha] setFill]; [[NSBezierPath bezierPathWithRoundedRect:box xRadius:7 * k yRadius:7 * k] fill];
        [t drawAtPoint:NSMakePoint(box.origin.x + 10 * k, box.origin.y + 4 * k) withAttributes:a];
    }
    if (!visible) return;
    if (group >= 0){
        NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:14 * k weight:NSFontWeightMedium], NSForegroundColorAttributeName: NSColor.whiteColor};
        NSRect box = NSMakeRect(pic.origin.x + 20 * k, pic.origin.y + 20 * k, 300 * k, 155 * k);
        [[NSColor colorWithWhite:0.04 alpha:0.9] setFill]; [[NSBezierPath bezierPathWithRoundedRect:box xRadius:10 * k yRadius:10 * k] fill];
        CGFloat x = box.origin.x + 14 * k, y = box.origin.y + 10 * k;
        [[NSString stringWithUTF8String:gname] drawAtPoint:NSMakePoint(x, y) withAttributes:a];
        if (wait) [@"Wait a moment" drawAtPoint:NSMakePoint(x, y + 25 * k) withAttributes:a];
        NSArray *keys = pad ? @[@"Up", @"Right", @"Down", @"Left"] : @[@"1", @"2", @"3", @"4"];
        for (int i = 0; !wait && i < 4; i++)
            [[NSString stringWithFormat:@"%@: %s", keys[i], phrases[layout[group * 4 + i]]] drawAtPoint:NSMakePoint(x, y + (25 + 22 * i) * k) withAttributes:a];
        [(pad ? @"B closes" : @"Esc closes") drawAtPoint:NSMakePoint(x, y + 118 * k)
                                         withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10 * k], NSForegroundColorAttributeName: NSColor.lightGrayColor}];
    }
    for (int i = 0; i < CHAT_LINES; i++){
        if (!lines[i].id || lines[i].until <= now) continue;
        for (int j = 0; j < count; j++){
            if (marks[j].id != lines[i].id) continue;
            CGFloat sc = MAX(0.7, marks[j].scale) * k, alpha = MIN(1, (lines[i].until - now) / 0.6);
            NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:15 * sc weight:NSFontWeightSemibold],
                                NSForegroundColorAttributeName: [NSColor.whiteColor colorWithAlphaComponent:alpha]};
            NSString *text = [NSString stringWithUTF8String:phrases[lines[i].phrase]];
            NSSize ts = [text sizeWithAttributes:a];
            /* over the name (a friend's) or over the roof (the player's own, which has no name) */
            CGFloat x = pic.origin.x + marks[j].x * pic.size.width, y = pic.origin.y + marks[j].y * pic.size.height - (lines[i].me ? 0 : 16 * sc);
            NSRect box = NSMakeRect(MAX(pic.origin.x + 2, MIN(x - ts.width / 2 - 9, NSMaxX(pic) - ts.width - 20)),
                                    MAX(pic.origin.y + 2, y - ts.height - 14), ts.width + 18, ts.height + 10);
            [[NSColor colorWithWhite:0.04 alpha:0.85 * alpha] setFill]; [[NSBezierPath bezierPathWithRoundedRect:box xRadius:7 yRadius:7] fill];
            [text drawAtPoint:NSMakePoint(box.origin.x + 9, box.origin.y + 5) withAttributes:a];
            break;
        }
    }
}
@end

/* ---- the panels ----------------------------------------------------------------- */
@interface GameToolsView : NSView @end
@implementation GameToolsView
- (void)drawRect:(NSRect)r { [NSColor.windowBackgroundColor setFill]; NSRectFill(r); }
@end

@interface GameTools : NSObject <NSWindowDelegate>
@property NSPanel *panel, *chatPanel;
@property GameToolsOverlay *overlay;
@property NSTextField *status, *crewNote, *chatHint, *chatError, *music, *roomField, *friendStatus;
@property NSArray<NSTextField *> *crewFields, *groupFields;
@property NSArray<NSColorWell *> *crewWells;
@property NSArray<NSPopUpButton *> *groupPhrases;
@property NSPopUpButton *collision;
@property NSButton *engage, *leave, *say, *groups, *apply, *joinRoom, *friendAct, *joinFriend;
@property NSPopUpButton *friendPopup;
@property NSButton *musicOn, *pause, *next, *shuffle;
@property NSPopUpButton *phrase;
@property NSTextView *log;
@property BOOL roam;
@end
static BOOL ours(NSWindow *w){ return ui && w && (w == ui.panel || w == ui.chatPanel || [w isKindOfClass:NSColorPanel.class]); }
static NSTextField *label(NSView *v, NSString *text, NSRect f){
    NSTextField *l = [NSTextField wrappingLabelWithString:text]; l.frame = f; [v addSubview:l]; return l;
}
static NSButton *button(NSView *v, NSString *title, SEL sel, NSRect f){
    NSButton *b = [NSButton buttonWithTitle:title target:ui action:sel]; b.frame = f; [v addSubview:b]; return b;
}
static NSButton *checkbox(NSView *v, NSString *title, SEL sel, NSRect f){
    NSButton *b = [NSButton checkboxWithTitle:title target:ui action:sel]; b.frame = f; [v addSubview:b]; return b;
}
static NSPopUpButton *phrase_popup(NSView *v, NSRect f){
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:f pullsDown:NO];
    for (int k = 0; k < PHRASE_COUNT; k++) [p addItemWithTitle:[NSString stringWithFormat:@"%d. %s", k + 1, phrases[k]]];
    [v addSubview:p]; return p;
}
static NSString *str(id v){ return [v isKindOfClass:NSString.class] ? v : @""; }
static unsigned rgb_of(NSColor *c){
    NSColor *s = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return ((unsigned)lround(s.redComponent * 255) << 16) | ((unsigned)lround(s.greenComponent * 255) << 8) | (unsigned)lround(s.blueComponent * 255);
}
static NSColor *color_of(unsigned rgb){
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
@implementation GameTools
- (void)toggle:(id)sender {
    (void)sender;
    if (self.panel.visible){ [self.panel orderOut:nil]; [g_game makeKeyWindow]; return; }
    [self refresh];
    NSRect f = g_game.frame, s = g_game.screen.visibleFrame, p = self.panel.frame;
    p.origin.x = NSMaxX(f) - p.size.width; p.origin.y = NSMaxY(f) - 36 - p.size.height;
    p.origin.x = MAX(NSMinX(s), MIN(p.origin.x, NSMaxX(s) - p.size.width));
    p.origin.y = MAX(NSMinY(s), MIN(p.origin.y, NSMaxY(s) - p.size.height));
    [self.panel setFrame:p display:NO];
    [g_game addChildWindow:self.panel ordered:NSWindowAbove];
    [self.panel makeKeyAndOrderFront:nil];
}
- (BOOL)windowShouldClose:(NSWindow *)w {
    [w orderOut:nil];
    if (w == self.panel) [g_game makeKeyWindow]; else [self.panel makeKeyAndOrderFront:nil];
    return NO;
}
- (void)engage:(id)sender { (void)sender; native_controls_action(NATIVE_CONTROL_ENGAGE); [self.panel orderOut:nil]; [g_game makeKeyWindow]; }
- (void)leave:(id)sender { (void)sender; native_controls_action(NATIVE_CONTROL_LEAVE); }
- (void)sayPhrase:(id)sender {
    (void)sender;
    pthread_mutex_lock(&mu); double now = now_s();
    int ok = !chat_wait(now) && chat_enqueue((int)self.phrase.indexOfSelectedItem);
    if (ok) qSent[qSentCount++] = now;
    pthread_mutex_unlock(&mu);
    self.crewNote.stringValue = ok ? @"Said (shown to players near you while you drive in free roam)." : @"Quick chat is busy. Wait a moment.";
}
- (void)musicOn:(id)sender { (void)sender; radio_native_set_enabled(self.musicOn.state == NSControlStateValueOn); [self refresh]; }
- (void)pause:(id)sender { (void)sender; radio_native_toggle_pause(); [self refresh]; }
- (void)next:(id)sender { (void)sender; radio_native_next(); }
- (void)shuffle:(id)sender { (void)sender; radio_native_set_shuffle(self.shuffle.state == NSControlStateValueOn); }
/* the Cars menu: 0 solid cars, 1 ghost cars, 2 everything passes through (traffic and tuners too) */
- (void)collision:(id)sender {
    (void)sender; NSInteger i = self.collision.indexOfSelectedItem;
    native_controls_set_solid(i == 0 ? 1 : i == 2 ? 2 : 0);
    [NSUserDefaults.standardUserDefaults setObject:i == 0 ? @"solid" : i == 2 ? @"everything" : @"ghost" forKey:@"LauncherFreeRoam"];
}
- (void)applyCrews:(id)sender {
    (void)sender; char error[160];
    NSMutableArray *names = [NSMutableArray array], *cols = [NSMutableArray array];
    for (int i = 0; i < 4; i++){
        [names addObject:self.crewFields[i].stringValue];
        [cols addObject:[NSString stringWithFormat:@"%06x", rgb_of(self.crewWells[i].color)]];
    }
    /* a cleared name leaves its crew: its colour goes with it */
    NSMutableArray *keepNames = [NSMutableArray array], *keepCols = [NSMutableArray array];
    for (int i = 0; i < 4; i++) if (trim(names[i]).length){ [keepNames addObject:names[i]]; [keepCols addObject:cols[i]]; }
    if (!native_controls_set_crews([keepNames componentsJoinedByString:@","].UTF8String, [keepCols componentsJoinedByString:@","].UTF8String, error, sizeof error)){
        self.crewNote.stringValue = [NSString stringWithUTF8String:error]; return; }
    pthread_mutex_lock(&mu); NSString *n = crewNames, *c = crewColours; pthread_mutex_unlock(&mu);
    [self showCrews:n colours:c];
    [NSUserDefaults.standardUserDefaults setObject:n forKey:@"LauncherRoamCrew"];
    [NSUserDefaults.standardUserDefaults setObject:c forKey:@"LauncherRoamCrewColours"];
    self.crewNote.stringValue = @"Crews changed. The same name is the same crew for everyone; crews are public.";
}
- (void)joinRoom:(id)sender {
    (void)sender; char error[160];
    NSString *typed = self.roomField.stringValue ?: @"";
    if (!native_controls_set_room(typed.UTF8String, error, sizeof error)){ self.crewNote.stringValue = [NSString stringWithUTF8String:error]; return; }
    NSString *room = native_controls_tidy_name(typed);
    self.roomField.stringValue = room;
    [NSUserDefaults.standardUserDefaults setObject:room forKey:@"LauncherRoamRoom"];
    self.crewNote.stringValue = room.length ? [NSString stringWithFormat:@"Room \u201c%@\u201d: only its players see you. You leave the old room's players now (after a race or a lobby, once it is over).", room]
                                            : @"No room: you see everyone again. You leave the old room's players now (after a race or a lobby, once it is over).";
}
- (void)friendAct:(id)sender { (void)sender; native_controls_friend_act(); [self refresh]; }
- (void)joinFriend:(id)sender {
    (void)sender;
    NSArray *all = native_controls_friends_to_join(); NSInteger i = self.friendPopup.indexOfSelectedItem;
    if (i < 0 || i >= (NSInteger)all.count) return;
    self.roomField.stringValue = all[i][1];
    [self joinRoom:nil];
}
- (void)showCrews:(NSString *)names colours:(NSString *)colours {
    NSArray *n = [names componentsSeparatedByString:@","], *c = [colours componentsSeparatedByString:@","];
    for (int i = 0; i < 4; i++){
        self.crewFields[i].stringValue = i < (int)n.count ? trim(n[i]) : @"";
        unsigned x = crewDefaults[i];
        if (i < (int)c.count && trim(c[i]).length == 6) [[NSScanner scannerWithString:trim(c[i])] scanHexInt:&x];
        self.crewWells[i].color = color_of(x);
    }
}
- (void)configureChat:(id)sender {
    (void)sender;
    pthread_mutex_lock(&mu); chat_close(); int layout[16]; memcpy(layout, qLayout, sizeof layout);
    char names[4][100]; memcpy(names, qGroupNames, sizeof names); pthread_mutex_unlock(&mu);
    if (!self.chatPanel){
        NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 930, 290) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered defer:NO];
        p.title = @"Quick chat groups"; p.releasedWhenClosed = NO; p.delegate = self;
        p.contentView = [[GameToolsView alloc] initWithFrame:NSMakeRect(0, 0, 930, 290)];
        NSView *v = p.contentView;
        label(v, @"While driving in free roam: press 1-4 to open a group, then 1-4 to say its phrase. On a controller flick the right stick twice (back to the centre in between); its click opens group 1.", NSMakeRect(20, 246, 890, 34));
        NSMutableArray *fields = [NSMutableArray array], *pops = [NSMutableArray array];
        for (int i = 0; i < 4; i++){
            label(v, [NSString stringWithFormat:@"%d", i + 1], NSMakeRect(20, 202 - i * 42, 20, 24));
            NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(42, 202 - i * 42, 170, 24)];
            f.accessibilityLabel = [NSString stringWithFormat:@"Quick chat group %d name", i + 1];
            [v addSubview:f]; [fields addObject:f];
            for (int j = 0; j < 4; j++){
                NSPopUpButton *b = phrase_popup(v, NSMakeRect(220 + j * 174, 200 - i * 42, 170, 28));
                b.accessibilityLabel = [NSString stringWithFormat:@"Group %d phrase %d", i + 1, j + 1];
                [pops addObject:b];
            }
        }
        self.groupFields = fields; self.groupPhrases = pops;
        self.chatError = label(v, @"Group names: 1-24 letters, numbers or signs. The launcher keeps the same groups.", NSMakeRect(20, 20, 680, 28));
        button(v, @"Save groups", @selector(saveChat:), NSMakeRect(774, 18, 136, 32));
        self.chatPanel = p;
    }
    for (int i = 0; i < 4; i++) self.groupFields[i].stringValue = [NSString stringWithUTF8String:names[i]];
    for (int i = 0; i < 16; i++) [self.groupPhrases[i] selectItemAtIndex:layout[i]];
    [self.chatPanel center]; [self.chatPanel makeKeyAndOrderFront:nil];
}
- (void)saveChat:(id)sender {
    (void)sender; NSMutableArray *names = [NSMutableArray array], *ids = [NSMutableArray array]; int layout[16];
    for (int i = 0; i < 4; i++){
        NSString *n = trim(self.groupFields[i].stringValue);
        if (!group_name_ok(n)){ self.chatError.stringValue = @"Give each group a name of 1-24 letters, numbers or signs (no comma)."; return; }
        [names addObject:n];
    }
    for (int i = 0; i < 16; i++){ layout[i] = (int)self.groupPhrases[i].indexOfSelectedItem; [ids addObject:@(layout[i])]; }
    if (!native_controls_set_chat_layout(layout)) return;
    pthread_mutex_lock(&mu); for (int i = 0; i < 4; i++) snprintf(qGroupNames[i], sizeof qGroupNames[i], "%s", [names[i] UTF8String]); pthread_mutex_unlock(&mu);
    [NSUserDefaults.standardUserDefaults setObject:names forKey:@"LauncherQuickChatGroups"];
    [NSUserDefaults.standardUserDefaults setObject:ids forKey:@"LauncherQuickChatPhrases"];
    [self.chatPanel orderOut:nil]; [self.panel makeKeyAndOrderFront:nil];
}
- (void)refresh {
    pthread_mutex_lock(&mu); NSDictionary *s = lobby; NSArray *lines = [messages copy]; int net = qNetwork || chat_racing(now_s()); pthread_mutex_unlock(&mu);
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSString *v = str(s[@"v"]), *st = str(s[@"st"]);
    if (!self.roam) [rows addObject:@"Free roam with other players is off (the launcher's Settings, Online). Quick chat works in races with other players, the music controls below anyway."];
    else if (!v.length) [rows addObject:@"Drive to a race marker in free roam to open a race lobby there, or to join the one another player opened."];
    else {
        NSString *kind = str(s[@"kind"]), *track = str(s[@"track"]);
        if (kind.length) [rows addObject:[NSString stringWithFormat:@"%@%@%@", kind, track.length ? @" - " : @"", track]];
        if (s[@"laps"]) [rows addObject:[NSString stringWithFormat:@"%@ laps", s[@"laps"]]];
        if ([v isEqual:@"note"]) [rows addObject:str(s[@"text"])];
        if ([v isEqual:@"trip"]) [rows addObject:str(s[@"step"])];
        if ([v isEqual:@"spot"]) [rows addObject:[NSString stringWithFormat:@"Multiplayer only here: %@", str(s[@"why"])]];
        if ([v isEqual:@"join"]) [rows addObject:[NSString stringWithFormat:@"A lobby is open here. Quitting its race costs $%@.", s[@"fee"] ?: @0]];
        if ([v isEqual:@"full"]) [rows addObject:@"The lobby here is full. Open another one here."];
        if ([st isEqual:@"asked"]) [rows addObject:@"Asking to join..."];
        if ([st isEqual:@"count"]) [rows addObject:[NSString stringWithFormat:@"Starting in %@", s[@"t"] ?: @0]];
        NSArray *names = s[@"names"];
        for (NSUInteger i = 0; i < names.count; i++)
            [rows addObject:[NSString stringWithFormat:@"%lu. %@%@%@", (unsigned long)i + 1, names[i], i == 0 ? @" (host)" : @"",
                             s[@"me"] && (NSInteger)i == [s[@"me"] integerValue] ? @" (you)" : @""]];
        if (names.count && s[@"max"]) [rows addObject:[NSString stringWithFormat:@"%lu / %@ players", (unsigned long)names.count, s[@"max"]]];
        if (s[@"away"]) [rows addObject:[NSString stringWithFormat:@"The host seems away: the lobby closes in %@ s", s[@"away"]]];
        if (s[@"closes"]) [rows addObject:[NSString stringWithFormat:@"Closes in %@ s unless someone joins", s[@"closes"]]];
    }
    self.status.stringValue = [rows componentsJoinedByString:@"\n"];
    BOOL host = [st isEqual:@"host"];
    self.engage.title = host ? @"Start race" : [v isEqual:@"join"] ? @"Join lobby" : @"Open lobby";
    self.engage.enabled = self.roam && ([v isEqual:@"spot"] || [v isEqual:@"join"] || [v isEqual:@"full"] || (host && [s[@"names"] count] >= 2));
    self.leave.enabled = self.roam && [v isEqual:@"lobby"];
    self.say.enabled = self.groups.enabled = self.phrase.enabled = net;
    self.collision.enabled = self.apply.enabled = self.joinRoom.enabled = self.roomField.enabled = self.roam;
    /* friends: the front bumpers' offer, and the friends in free roam in another room */
    char fl[200]; int act = 0;
    int line = native_controls_friend_line(fl, sizeof fl, &act);
    pthread_mutex_lock(&mu); NSArray *fr = fFriends; NSArray *where = fWhere; int claimed = fClaimed; NSString *offer = fOfferSt; pthread_mutex_unlock(&mu);
    NSString *mine = room_now();
    NSMutableArray *roam = [NSMutableArray array];
    for (NSDictionary *f in where) if ([f[@"where"] isEqual:@"roam"]) [roam addObject:[NSString stringWithFormat:@"%@ (%@)", f[@"name"], where_text(f, mine)]];
    self.friendStatus.stringValue = !self.roam || !friends_on() ? @"Friends: off (the launcher's Settings, Online)"
        : line ? [NSString stringWithUTF8String:fl]
        : !claimed ? @"Friends need a claimed name: claim yours in the launcher (Settings, Online)"
        : !fr.count ? @"No friends yet: touch front bumpers with another player for 3 s to add one"
        : roam.count ? [@"Friends in free roam: " stringByAppendingString:[roam componentsJoinedByString:@", "]]
        : [NSString stringWithFormat:@"%lu friend(s), none in free roam now", (unsigned long)fr.count];
    self.friendAct.title = [offer isEqual:@"asks"] ? @"Accept friend" : @"Add friend";
    self.friendAct.enabled = act;
    NSArray *join = native_controls_friends_to_join();
    NSMutableArray *titles = [NSMutableArray array];
    for (NSArray *j in join) [titles addObject:[NSString stringWithFormat:@"%@ (%@)", j[0], [j[1] length] ? [NSString stringWithFormat:@"room %@", j[1]] : @"no room"]];
    if (![titles isEqual:self.friendPopup.itemTitles]){ [self.friendPopup removeAllItems]; [self.friendPopup addItemsWithTitles:titles]; }
    self.friendPopup.enabled = self.joinFriend.enabled = self.roam && titles.count > 0;
    for (NSTextField *f in self.crewFields) f.enabled = self.roam;
    for (NSColorWell *w in self.crewWells) w.enabled = self.roam;
    self.chatHint.stringValue = net ? @"Quick chat: 1-4 twice, or the right stick twice" : @"Quick chat is off (in the launcher)";
    NSString *log = [lines componentsJoinedByString:@"\n"] ?: @"";
    if (![log isEqual:self.log.string]){ self.log.string = log; [self.log scrollRangeToVisible:NSMakeRange(log.length, 0)]; }
    /* the music folder */
    RadioNativeSnapshot m; radio_native_snapshot(&m);
    NSString *artist = [NSString stringWithUTF8String:m.artist] ?: @"", *title = [NSString stringWithUTF8String:m.title] ?: @"";
    self.music.stringValue = !m.folder ? @"Music: choose a music folder in the launcher (Settings, Game)"
                           : !m.tracks ? @"Music: no tracks that play in the music folder"
                           : !m.enabled ? @"Music: the game's own soundtrack"
                           : title.length ? [NSString stringWithFormat:@"Music: %@%@%@", artist, artist.length ? @" - " : @"", title] : @"Music: your music folder";
    self.music.toolTip = self.music.stringValue;
    self.musicOn.state = m.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.musicOn.enabled = m.tracks > 0;
    self.pause.title = m.paused ? @"Resume" : @"Pause"; self.pause.enabled = m.enabled;
    self.next.enabled = m.enabled;
    self.shuffle.enabled = m.tracks > 0;
    self.shuffle.state = m.shuffle ? NSControlStateValueOn : NSControlStateValueOff;
}
/* the pump: ~30 times a second on the main thread (an NSTimer of the run loop metal.m turns) */
- (void)tick:(NSTimer *)t {
    (void)t; double now = now_s();
    native_controls_friends_tick(now);
    pthread_mutex_lock(&mu);
    qFocused = g_game.keyWindow && NSApp.active;
    chat_expire(now);
    pthread_mutex_unlock(&mu);
    self.overlay.needsDisplay = YES;
    static double last;
    if (self.panel.visible && now - last >= 0.1){ last = now; [self refresh]; }
    [self testAids];
}
/* Test aids (automated runs only):
 *   GAMETOOLS_KEYS="<frame>:<mac key code>,..."  a key press (down, up 3 frames later) to the game window then, as typed
 *   GAMETOOLS_SHOT="<frame>,..." (DUMPDIR)       gametools_<frame>.png the panel as it shows then, overlay_<frame>.png
 *                                                the overlay (transparent, the window's size; with DUMPFRAME at the same frame)
 *   GAMETOOLS_CLICK="<frame>:<button title>,..." the panel's button whose title starts so pressed then (spaces as _;
 *                                                a check box changes first); before Apply the crews' fields get
 *   GAMETOOLS_CREWS="<name>:<rrggbb>;..."        these names and colours
 *   GAMETOOLS_ROOM="<name>"                      before Join room, the Room box gets it */
- (void)testAids {
    static int init, nk, ns, nc; static long kf[32], sf[8], cf[8]; static unsigned short kc[32]; static int kup[32]; static char ct[8][32];
    if (!init){ init = 1;
        for (const char *p = getenv("GAMETOOLS_KEYS"); p && *p && nk < 32; ){
            kf[nk] = strtol(p, 0, 0); const char *c = strchr(p, ':'); if (!c) break;
            kc[nk++] = (unsigned short)strtoul(c + 1, 0, 0); while (*p && *p != ',') p++; if (*p) p++; }
        for (const char *p = getenv("GAMETOOLS_SHOT"); p && *p && ns < 8; ){ sf[ns++] = strtol(p, 0, 0); while (*p && *p != ',') p++; if (*p) p++; }
        for (const char *p = getenv("GAMETOOLS_CLICK"); p && *p && nc < 8; ){
            cf[nc] = strtol(p, 0, 0); const char *c = strchr(p, ':'); if (!c) break;
            int k = 0; for (c++; *c && *c != ',' && k < 31; c++) ct[nc][k++] = *c == '_' ? ' ' : *c;
            ct[nc++][k] = 0; p = c; if (*p) p++; }
    }
    if (!nk && !ns && !nc) return;
    long f = metal_frames();
    for (int i = 0; i < nk; i++){
        int down = !kup[i] && f >= kf[i], up = kup[i] == 1 && f >= kf[i] + 3;
        if (!down && !up) continue;
        kup[i]++;
        NSString *ch = kc[i] >= 18 && kc[i] <= 21 ? [NSString stringWithFormat:@"%d", kc[i] - 17] : @"";
        NSEvent *e = [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:0
                                  windowNumber:g_game.windowNumber context:nil characters:ch charactersIgnoringModifiers:ch isARepeat:NO keyCode:kc[i]];
        [NSApp postEvent:e atStart:NO];
        fprintf(stderr, "[gametools] f=%ld test key %u %s\n", f, kc[i], down ? "down" : "up");
    }
    static int ci;
    while (ci < nc && f >= cf[ci]){
        NSString *want = [NSString stringWithUTF8String:ct[ci++]]; int hit = 0;
        [self refresh];
        for (NSView *v in self.panel.contentView.subviews){
            NSButton *b = (NSButton *)v;
            if (![v isKindOfClass:NSButton.class] || ![b.title hasPrefix:want] || !b.enabled) continue;
            if (b == self.musicOn || b == self.shuffle) b.state = b.state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
            if (b == self.collision) [self.collision selectItemAtIndex:(self.collision.indexOfSelectedItem + 1) % self.collision.numberOfItems];
            const char *cr = getenv("GAMETOOLS_CREWS");
            const char *rm = getenv("GAMETOOLS_ROOM");
            if (b == self.joinRoom && rm) self.roomField.stringValue = [NSString stringWithUTF8String:rm] ?: @"";
            if (b == self.apply && cr){
                NSArray *rows = [[NSString stringWithUTF8String:cr] componentsSeparatedByString:@";"];
                for (int i = 0; i < 4; i++){
                    NSArray *f = i < (int)rows.count ? [rows[i] componentsSeparatedByString:@":"] : @[@""];
                    self.crewFields[i].stringValue = f[0];
                    unsigned x = crewDefaults[i]; if (f.count > 1) [[NSScanner scannerWithString:f[1]] scanHexInt:&x];
                    self.crewWells[i].color = color_of(x);
                }
            }
            [NSApp sendAction:b.action to:b.target from:b]; hit = 1; break;
        }
        fprintf(stderr, "[gametools] f=%ld test click \"%s\": %s; panel note: %s\n", f, want.UTF8String, hit ? "pressed" : "no such button (or off)",
                self.crewNote.stringValue.UTF8String);
    }
    static int si;
    if (si < ns && f >= sf[si]){
        long at = sf[si++];
        const char *d = getenv("DUMPDIR"); NSString *dir = [NSString stringWithUTF8String:d && *d ? d : "/tmp"];
        [self refresh];                                   /* drawn as it would show, not shown (a test window never is) */
        for (NSView *v in @[self.panel.contentView, self.overlay]){
            NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
            if (v == self.overlay) memset(rep.bitmapData, 0, (size_t)rep.bytesPerRow * (size_t)rep.pixelsHigh);
            [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
            NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:v == self.overlay ? @"overlay_%ld.png" : @"gametools_%ld.png", at]];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
            fprintf(stderr, "[gametools] f=%ld wrote %s\n", f, path.UTF8String);
        }
    }
}
@end

/* the groups from the launcher: NFSU2_QUICKCHAT_GROUPS "name,name,name,name",
 * NFSU2_QUICKCHAT_PHRASES 16 phrase numbers (0-based, by commas); a list
 * that is not right is ignored whole (the defaults hold) */
static void groups_from_env(void){
    const char *g = getenv("NFSU2_QUICKCHAT_GROUPS"), *p = getenv("NFSU2_QUICKCHAT_PHRASES");
    if (g && *g){
        NSArray *n = [[NSString stringWithUTF8String:g] ?: @"" componentsSeparatedByString:@","];
        BOOL okn = n.count == 4;
        for (NSUInteger i = 0; okn && i < 4; i++) okn = group_name_ok(trim(n[i]));
        if (okn) for (int i = 0; i < 4; i++) snprintf(qGroupNames[i], sizeof qGroupNames[i], "%s", [trim(n[i]) UTF8String]);
        else fprintf(stderr, "[gametools] NFSU2_QUICKCHAT_GROUPS ignored (four names of 1-24 characters, by commas)\n");
    }
    if (p && *p){
        int l[16], k = 0; const char *q = p; char *e;
        while (*q && k < 16){ long v = strtol(q, &e, 10); if (e == q || v < 0 || v >= PHRASE_COUNT) break; l[k++] = (int)v; q = e; while (*q == ',' || *q == ' ') q++; }
        if (k == 16 && !*q) native_controls_set_chat_layout(l);
        else fprintf(stderr, "[gametools] NFSU2_QUICKCHAT_PHRASES ignored (16 phrase numbers 0-%d, by commas)\n", PHRASE_COUNT - 1);
    }
}

void native_controls_install(NSWindow *game){
    if (ui || !game) return;
    g_game = game;
    const char *roam = getenv("NFSU2_ROAM");
    { const char *nf = getenv("NOFOCUS"); qTestFocus = nf && *nf && *nf != '0'; }   /* a test window never has focus */
    groups_from_env();
    ui = [GameTools new];
    ui.roam = roam && *roam == '1';
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 855) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                              backing:NSBackingStoreBuffered defer:NO];
    p.title = @"Game Tools"; p.delegate = ui; p.releasedWhenClosed = NO;
    p.hidesOnDeactivate = YES; p.becomesKeyOnlyIfNeeded = NO;
    p.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
    p.contentView = [[GameToolsView alloc] initWithFrame:NSMakeRect(0, 0, 520, 855)];
    ui.panel = p;
    NSView *v = p.contentView;
    ui.friendStatus = label(v, @"", NSMakeRect(20, 810, 350, 36));
    ui.friendStatus.font = [NSFont systemFontOfSize:12];
    ui.friendAct = button(v, @"Add friend", @selector(friendAct:), NSMakeRect(378, 812, 128, 32));
    ui.friendPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 774, 356, 28) pullsDown:NO];
    ui.friendPopup.accessibilityLabel = @"Friends in another room"; [v addSubview:ui.friendPopup];
    ui.joinFriend = button(v, @"Join friend", @selector(joinFriend:), NSMakeRect(378, 772, 128, 32));
    label(v, @"Room", NSMakeRect(20, 738, 50, 22));
    ui.roomField = [[NSTextField alloc] initWithFrame:NSMakeRect(70, 736, 300, 24)];
    ui.roomField.placeholderString = @"Everyone"; ui.roomField.accessibilityLabel = @"Room";
    [v addSubview:ui.roomField];
    ui.joinRoom = button(v, @"Join room", @selector(joinRoom:), NSMakeRect(378, 732, 128, 32));
    ui.groups = button(v, @"Quick chat groups...", @selector(configureChat:), NSMakeRect(16, 690, 190, 30));
    ui.chatHint = label(v, @"", NSMakeRect(214, 694, 290, 24));
    ui.status = label(v, @"", NSMakeRect(20, 500, 480, 175));
    ui.music = label(v, @"Music", NSMakeRect(20, 476, 480, 20));
    ui.music.maximumNumberOfLines = 1; ui.music.lineBreakMode = NSLineBreakByTruncatingTail;
    ui.pause = button(v, @"Pause", @selector(pause:), NSMakeRect(16, 444, 110, 30));
    ui.next = button(v, @"Next track", @selector(next:), NSMakeRect(132, 444, 120, 30));
    ui.musicOn = checkbox(v, @"Music folder (off: the game's own soundtrack)", @selector(musicOn:), NSMakeRect(20, 416, 360, 24));
    ui.shuffle = checkbox(v, @"Shuffle", @selector(shuffle:), NSMakeRect(390, 416, 110, 24));
    ui.engage = button(v, @"Open lobby", @selector(engage:), NSMakeRect(16, 378, 180, 32));
    ui.leave = button(v, @"Leave lobby", @selector(leave:), NSMakeRect(204, 378, 150, 32));
    label(v, @"Cars", NSMakeRect(20, 349, 50, 22));
    ui.collision = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, 345, 436, 28) pullsDown:NO];
    [ui.collision addItemsWithTitles:@[ @"Solid cars", @"Ghost cars: other players drive through yours",
                                        @"Everything ghost: players, traffic and tuners drive through yours" ]];
    ui.collision.target = ui; ui.collision.action = @selector(collision:); ui.collision.accessibilityLabel = @"Cars";
    [v addSubview:ui.collision];
    label(v, @"Crews (up to 4): a name and its colour", NSMakeRect(20, 318, 480, 22));
    NSMutableArray *fields = [NSMutableArray array], *wells = [NSMutableArray array];
    for (int i = 0; i < 4; i++){
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 286 - i * 26, 345, 24)];
        f.placeholderString = [NSString stringWithFormat:@"Crew %d", i + 1]; f.accessibilityLabel = f.placeholderString;
        NSColorWell *w = [[NSColorWell alloc] initWithFrame:NSMakeRect(374, 286 - i * 26, 48, 24)];
        w.accessibilityLabel = [NSString stringWithFormat:@"Crew %d colour", i + 1];
        [v addSubview:f]; [v addSubview:w]; [fields addObject:f]; [wells addObject:w];
    }
    ui.crewFields = fields; ui.crewWells = wells;
    ui.apply = button(v, @"Apply", @selector(applyCrews:), NSMakeRect(430, 206, 76, 30));
    ui.crewNote = label(v, @"The same name is the same crew for everyone. Clear a name to leave that crew.", NSMakeRect(20, 170, 480, 34));
    ui.crewNote.font = [NSFont systemFontOfSize:11];
    ui.phrase = phrase_popup(v, NSMakeRect(16, 139, 380, 28)); ui.phrase.accessibilityLabel = @"Quick chat phrase";
    ui.say = button(v, @"Say", @selector(sayPhrase:), NSMakeRect(402, 138, 100, 30));
    NSScrollView *sc = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 480, 110)];
    sc.hasVerticalScroller = YES; sc.borderType = NSBezelBorder;
    ui.log = [[NSTextView alloc] initWithFrame:sc.bounds]; ui.log.editable = NO; ui.log.font = [NSFont systemFontOfSize:12];
    ui.log.accessibilityLabel = @"Nearby notices and quick chat"; sc.documentView = ui.log; [v addSubview:sc];
    /* what the launcher started with (roam_game.c reads the same variables) */
    const char *crew = getenv("NFSU2_ROAM_CREW"), *rgb = getenv("NFSU2_ROAM_CREW_RGB"), *col = getenv("NFSU2_ROAM_COLLIDE");
    [ui showCrews:crew ? [NSString stringWithUTF8String:crew] ?: @"" : @"" colours:rgb ? [NSString stringWithUTF8String:rgb] ?: @"" : @""];
    [ui.collision selectItemAtIndex:col && !strcasecmp(col, "none") ? 2 : !col || atoi(col) ? 0 : 1];
    const char *room = getenv("NFSU2_ROAM_ROOM");
    ui.roomField.stringValue = room ? [NSString stringWithUTF8String:room] ?: @"" : @"";
    /* the overlay over the game's picture */
    GameToolsOverlay *o = [[GameToolsOverlay alloc] initWithFrame:game.contentView.bounds];
    o.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [game.contentView addSubview:o]; ui.overlay = o;
    for (NSNotificationName n in @[NSWindowDidResignKeyNotification, NSWindowDidBecomeKeyNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:n object:game queue:nil usingBlock:^(NSNotification *note){
            pthread_mutex_lock(&mu);
            qFocused = [note.name isEqual:NSWindowDidBecomeKeyNotification];
            if (!qFocused){ chat_close(); memset(qKeys, 0, sizeof qKeys); }        /* focus lost: the picker closes */
            pthread_mutex_unlock(&mu);
            ui.overlay.needsDisplay = YES;
        }];
    NSTimer *t = [NSTimer timerWithTimeInterval:1.0 / 30 target:ui selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.currentRunLoop addTimer:t forMode:NSRunLoopCommonModes];
    /* the app menu's item, before its last part (Quit) */
    NSMenu *m = NSApp.mainMenu.itemArray.firstObject.submenu;
    if (m){
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:@"Game Tools..." action:@selector(toggle:) keyEquivalent:@"m"];
        it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift; it.target = ui;
        NSInteger at = m.numberOfItems;
        for (NSInteger i = m.numberOfItems - 1; i >= 0; i--) if ([m itemAtIndex:i].isSeparatorItem){ at = i; break; }
        [m insertItem:it atIndex:at];
    }
    [ui refresh];
    fprintf(stderr, "[gametools] Game Tools in the app menu (Cmd+Shift+M)%s; quick chat groups: %s, %s, %s, %s\n",
            ui.roam ? "" : " (free roam with others off: music and quick chat in races)", qGroupNames[0], qGroupNames[1], qGroupNames[2], qGroupNames[3]);
}
