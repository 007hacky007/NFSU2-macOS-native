/* native_controls_test.m -- Game Tools' state without the game: the lobby and
 * phrase JSON checks, the Say queue, solid cars, the crews' rules, the
 * buttons' hand-off to roam_game.c, a producer thread against the panel's
 * reader, and (--snapshot out.png) the panel itself with its music controls.
 * tests/native_controls.sh builds and runs it. */
#import <Cocoa/Cocoa.h>
#include <assert.h>
#include <pthread.h>
#include "native_controls.h"
#include "roam_core.h"
#include "roam_plat.h"
#include "radio_native.h"

void roam_game_event(int ev, int peer, const char *text){ (void)ev; (void)peer; (void)text; }
/* the music folder, as radio_native.m would answer */
static int paused, shuffled, nexts, enabled = 1;
void radio_native_snapshot(RadioNativeSnapshot *o){
    memset(o, 0, sizeof *o); o->folder = 1; o->tracks = 2; o->enabled = enabled; o->paused = paused; o->shuffle = shuffled;
    snprintf(o->artist, sizeof o->artist, "Synthetic artist"); snprintf(o->title, sizeof o->title, "Synthetic tune");
}
void radio_native_set_enabled(int e){ enabled = e; }
void radio_native_set_paused(int p){ paused = p; }
void radio_native_set_shuffle(int s){ shuffled = s; }
void radio_native_next(void){ nexts++; }

/* the link to the server (net_native.m): what Game Tools sends on it, and whether it is up */
static char sent[16][256]; static int nsent, linkUp = 1;
int native_net_text(const char *json){
    if (!linkUp) return 0;
    if (nsent < 16) snprintf(sent[nsent++], sizeof sent[0], "%s", json);
    return 1;
}
static int sent_has(const char *what){ for (int i = 0; i < nsent; i++) if (strstr(sent[i], what)) return 1; return 0; }
static void *produce(void *unused){
    (void)unused;
    for (int i = 0; i < 1000; i++){
        roam_plat_lobby("{\"v\":\"lobby\",\"st\":\"count\",\"kind\":\"Sprint\",\"track\":\"Synthetic\",\"names\":[\"Driver\"],\"t\":3,\"max\":6}");
        native_controls_notice("Driver", " joined");
        roam_plat_said("{\"id\":9,\"name\":\"Driver\",\"p\":3}");
    }
    return NULL;
}
int main(int argc, char **argv){ @autoreleasepool {
    assert(roam_plat_quickchat() == 1);
    /* the lobby: whole JSON objects of known views and fields only */
    assert(roam_plat_lobby("{}") == 1);
    assert(roam_plat_lobby("{") == -1);
    assert(roam_plat_lobby("[]") == -1);
    assert(roam_plat_lobby("{\"names\":[2]}") == -1);
    assert(roam_plat_lobby("{\"v\":\"lobby\",\"t\":\"bad\"}") == -1);
    assert(roam_plat_lobby("{\"v\":\"unknown\"}") == -1);
    assert(roam_plat_lobby("{\"v\":3}") == -1);
    assert(roam_plat_lobby("{\"v\":\"lobby\",\"st\":\"unknown\"}") == -1);
    assert(roam_plat_lobby("{\"v\":\"join\",\"fee\":75,\"even\":1,\"names\":[\"a\",\"b\",\"c\",\"d\",\"e\",\"f\"]}") == 1);
    assert(roam_plat_lobby("{\"v\":\"join\",\"names\":[\"a\",\"b\",\"c\",\"d\",\"e\",\"f\",\"g\"]}") == -1);
    /* a phrase said */
    assert(roam_plat_said("{\"id\":42,\"name\":\"Driver\",\"p\":0}") == 1);
    assert(roam_plat_said("{\"id\":42,\"name\":\"Driver\",\"p\":200}") == 1);    /* a newer game's: taken, not shown */
    assert(roam_plat_said("{\"id\":-1,\"name\":\"Driver\",\"p\":0}") == -1);
    assert(roam_plat_said("{\"id\":4294967296,\"name\":\"Driver\",\"p\":0}") == -1);
    assert(roam_plat_said("{\"id\":1,\"name\":\"Driver\",\"p\":999}") == -1);
    assert(roam_plat_said("{\"name\":\"Driver\",\"p\":0}") == -1);
    assert(roam_plat_said("{\"id\":1,\"name\":2,\"p\":0}") == -1);
    assert(roam_plat_said("{\"id\":1,\"name\":\"Driver\",\"p\":0.5}") == -1);
    assert(roam_plat_said("{\"id\":1,\"name\":\"Driver\",\"p\":true}") == -1);
    assert(roam_plat_said("{\"id\":1,\"name\":\"Driver\",\"p\":0,\"me\":{}}") == -1);
    /* the Say queue: 16 at most, phrases of the list only */
    assert(native_controls_pick(0)); assert(roam_plat_say_pick() == 0);
    assert(roam_plat_say_pick() == -1); assert(!native_controls_pick(-1));
    assert(!native_controls_pick(NATIVE_PHRASES));
    for (int i = 0; i < 16; i++) assert(native_controls_pick(i));
    assert(!native_controls_pick(0));
    for (int i = 0; i < 16; i++) assert(roam_plat_say_pick() == i);
    /* the phrase list is the donor's: its first, its last */
    assert(!strcmp(native_controls_phrase(0), "Hey!") && !strcmp(native_controls_phrase(151), "On my phone!") && !native_controls_phrase(152));
    /* solid cars */
    assert(roam_plat_solid() == -1);
    native_controls_set_solid(1); assert(roam_plat_solid() == 1);
    native_controls_set_solid(0); assert(roam_plat_solid() == 0);
    native_controls_set_solid(2); assert(roam_plat_solid() == 2);   /* Ghost mode Everything */
    native_controls_set_solid(5); assert(roam_plat_solid() == 1);
    /* crews: the whole list or nothing */
    char error[160]; uint32_t h[RC_CREW_MAX], rgb[RC_CREW_MAX];
    assert(roam_plat_crews(h, rgb) == 0);
    assert(native_controls_set_crews("Blue Room, Night Owls", "3cd2ff,ff50c8", error, sizeof error));
    uint32_t gen = roam_plat_crews(h, rgb); assert(gen && h[0] && h[1] && !h[2]);
    assert(h[0] == rc_room_hash("blueroom"));
    assert(rgb[0] == 0x3cd2ff && rgb[1] == 0xff50c8);
    assert(native_controls_set_crews("Ostrava Ölwagen", "", error, sizeof error));         /* UTF-8 names */
    gen = roam_plat_crews(h, rgb); assert(h[0] == rc_room_hash("Ostrava Ölwagen") && rgb[0] == 0x3cd2ff);
    assert(!native_controls_set_crews("Blue Room, blueroom", "", error, sizeof error) && strstr(error, "twice"));
    assert(!native_controls_set_crews("one,two,three,four,five", "", error, sizeof error));
    assert(!native_controls_set_crews("one", "nothex", error, sizeof error));
    assert(!native_controls_set_crews("name#comment", "", error, sizeof error));
    assert(!native_controls_set_crews("a name with more than twenty four characters", "", error, sizeof error));
    assert(!native_controls_set_crews("nazi", "", error, sizeof error));
    assert(roam_plat_crews(h, rgb) == gen);
    assert(native_controls_set_crews("", "", error, sizeof error));
    assert(roam_plat_crews(h, rgb) != gen && !h[0]);
    /* the room: tidied and checked as the launcher's Room box, a new number each change */
    char room[64];
    assert(roam_plat_room(room) == 0);
    assert(native_controls_set_room("  Blue\xc2\xa0  Room\xe2\x80\x8b ", error, sizeof error));
    uint32_t rg = roam_plat_room(room); assert(rg && !strcmp(room, "Blue Room"));
    assert(rc_room_hash(room) == rc_room_hash("blueroom"));
    assert(native_controls_set_room("\xd0\x9a\xd0\xbe\xd0\xbc\xd0\xbd\xd0\xb0\xd1\x82\xd0\xb0", error, sizeof error));   /* UTF-8 */
    assert(roam_plat_room(room) != rg && !strcmp(room, "\xd0\x9a\xd0\xbe\xd0\xbc\xd0\xbd\xd0\xb0\xd1\x82\xd0\xb0"));
    rg = roam_plat_room(room);
    assert(!native_controls_set_room("Blue #comment", error, sizeof error) && strstr(error, "after a space"));
    assert(!native_controls_set_room("1488", error, sizeof error));
    { char big[80]; memset(big, 'a', 64); big[64] = 0; assert(!native_controls_set_room(big, error, sizeof error) && strstr(error, "63")); }
    assert(roam_plat_room(room) == rg);
    assert(native_controls_set_room("   ", error, sizeof error) && roam_plat_room(room) != rg && room[0] == 0);   /* no room */
    /* friends: the list asked on the link once it is up with a claimed name, the room and where once there are
     * friends, the front bumpers' line from the server's answers, F's request */
    setenv("NFSU2_ROAM", "1", 1); unsetenv("NFSU2_ROAM_FRIENDS"); unsetenv("NFSU2_ROAM_ROOM");
    native_controls_set_room("", error, sizeof error);
    char fl[200]; int act = 0;
    native_controls_friends_tick(100); assert(nsent == 0);                       /* no link yet: nothing */
    linkUp = 0; native_controls_net_welcome(1);
    native_controls_friends_tick(100); assert(nsent == 0);                       /* the link went again: tried later */
    linkUp = 1; native_controls_friends_tick(101); assert(nsent == 0);
    native_controls_friends_tick(102.5); assert(nsent == 1 && sent_has("\"op\":\"list\""));
    native_controls_friends_tick(110); assert(nsent == 1);                       /* asked once, until the next welcome */
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"list\",\"me\":\"Ann\",\"friends\":[\"Bo\"],\"asks\":[\"Cy\"],"
                               "\"mail\":[{\"from\":\"Bo\",\"body\":\"hi\",\"at\":1}]}");
    nsent = 0; native_controls_friends_tick(111);
    assert(nsent == 2 && sent_has("{\"t\":\"room\",\"name\":\"\"}") && sent_has("\"op\":\"where\""));   /* everyone's room, where */
    nsent = 0; native_controls_friends_tick(112); assert(nsent == 0);
    /* the cars touch: what the player is to us is asked, then the line offers it */
    assert(roam_plat_friend("{") == -1 && roam_plat_friend("{\"id\":7,\"name\":\"Dee\"}") == -1);
    assert(roam_plat_friend("{\"id\":7,\"name\":\"Dee\",\"on\":1}") == 1);
    assert(!native_controls_friend_line(fl, sizeof fl, &act));                   /* (waiting for the answer) */
    native_controls_friends_tick(113); assert(nsent == 1 && sent_has("\"op\":\"can\"") && sent_has("\"name\":\"Dee\""));
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"can\",\"name\":\"dee\",\"st\":\"new\"}");   /* (its claimed name) */
    assert(native_controls_friend_line(fl, sizeof fl, &act) && act && strstr(fl, "add dee as a friend"));
    assert(native_controls_friend_act() && !native_controls_friend_act());
    nsent = 0; native_controls_friends_tick(114); assert(nsent == 1 && sent_has("\"op\":\"add\""));
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"add\",\"name\":\"dee\",\"done\":\"asked\"}");
    assert(native_controls_friend_line(fl, sizeof fl, &act) && !act && strstr(fl, "request sent"));
    assert(roam_plat_friend("{\"id\":7,\"name\":\"Dee\",\"on\":0}") == 1 && !native_controls_friend_line(fl, sizeof fl, &act));
    /* the other one pressed first: accept */
    roam_plat_friend("{\"id\":8,\"name\":\"Eve\",\"on\":1}"); nsent = 0; native_controls_friends_tick(115);
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"asks\",\"name\":\"Eve\"}");
    assert(native_controls_friend_line(fl, sizeof fl, &act) && act && strstr(fl, "Eve wants to be friends"));   /* (before "can": theirs) */
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"can\",\"name\":\"Eve\",\"st\":\"asks\"}");
    assert(native_controls_friend_line(fl, sizeof fl, &act) && act && strstr(fl, "wants to be friends"));
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"can\",\"name\":\"Eve\",\"st\":\"far\"}");
    assert(!native_controls_friend_line(fl, sizeof fl, &act));                   /* not linked now: no line */
    /* a friend comes into free roam in another room: a toast, and a Join */
    native_controls_net_friend("{\"t\":\"friend\",\"op\":\"where\",\"friends\":[{\"name\":\"Bo\",\"where\":\"roam\",\"room\":\"Red\"},"
                               "{\"name\":\"Al\",\"where\":\"online\"}]}");
    assert(native_controls_friend_toast(fl, sizeof fl) && strstr(fl, "Bo is in free roam, room Red"));
    NSArray *join = native_controls_friends_to_join();
    assert(join.count == 1 && [join[0][0] isEqual:@"Bo"] && [join[0][1] isEqual:@"Red"]);
    assert(native_controls_set_room("red", error, sizeof error));                  /* joined: Bo's room (any case) */
    assert(native_controls_friends_to_join().count == 0);
    nsent = 0; native_controls_friends_tick(116); assert(nsent == 1 && sent_has("{\"t\":\"room\",\"name\":\"red\"}"));
    /* a name not claimed: the line says how to have one, nothing asked */
    native_controls_net_welcome(0); nsent = 0;
    roam_plat_friend("{\"id\":9,\"name\":\"Fay\",\"on\":1}"); native_controls_friends_tick(200);
    assert(nsent == 0 && native_controls_friend_line(fl, sizeof fl, &act) && !act && strstr(fl, "Claim your name"));
    roam_plat_friend("{\"id\":9,\"name\":\"Fay\",\"on\":0}");
    native_controls_set_room("", error, sizeof error);
    /* the buttons: one action, taken once */
    assert(roam_plat_action() == ROAM_ACTION_NONE);
    native_controls_action(NATIVE_CONTROL_ENGAGE); assert(roam_plat_action() == ROAM_ACTION_ENGAGE); assert(roam_plat_action() == 0);
    native_controls_action(NATIVE_CONTROL_LEAVE); assert(roam_plat_action() == ROAM_ACTION_LEAVE);
    native_controls_action(7); assert(roam_plat_action() == 0);
    /* the quick chat groups: 16 phrases of the list, or nothing */
    int layout[16]; for (int i = 0; i < 16; i++) layout[i] = 151 - i;
    assert(native_controls_set_chat_layout(layout));
    layout[3] = 152; assert(!native_controls_set_chat_layout(layout));
    /* a producer on another thread against the reader */
    pthread_t t; assert(!pthread_create(&t, NULL, produce, NULL));
    for (int i = 0; i < 1000; i++){ roam_plat_solid(); roam_plat_crews(h, rgb); roam_plat_say_pick(); }
    pthread_join(t, NULL);
    assert(roam_plat_lobby("{}") == 1);
    if (argc == 3 && !strcmp(argv[1], "--snapshot")){
        setenv("NFSU2_ROAM", "1", 1);
        setenv("NFSU2_ROAM_CREW", "Blue Room, Night Owls", 1);
        setenv("NFSU2_ROAM_CREW_RGB", "3cd2ff,ff50c8", 1);
        setenv("NFSU2_ROAM_COLLIDE", "1", 1);
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSMenu *bar = [NSMenu new], *app = [NSMenu new]; NSMenuItem *ai = [NSMenuItem new]; [bar addItem:ai]; ai.submenu = app;
        [app addItem:[NSMenuItem separatorItem]]; [app addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        NSApp.mainMenu = bar;
        NSWindow *game = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        roam_plat_lobby("{\"v\":\"lobby\",\"st\":\"host\",\"kind\":\"Sprint\",\"track\":\"Synthetic track\",\"laps\":2,\"names\":[\"Driver\",\"Guest\"],\"me\":0,\"max\":6}");
        native_controls_set_network(1);
        roam_plat_said("{\"id\":7,\"name\":\"Guest\",\"p\":57}");
        native_controls_notice("Guest", " joined the room");
        native_controls_install(game);
        assert(app.numberOfItems == 3 && [[app itemAtIndex:0].title isEqual:@"Game Tools..."] && [[app itemAtIndex:0].keyEquivalent isEqual:@"m"]);
        NSWindow *panel = nil; for (NSWindow *w in NSApp.windows) if ([w.title isEqual:@"Game Tools"]) panel = w;
        assert(panel && panel.contentView.subviews.count > 10);
        BOOL sawMusic = NO, sawLobby = NO, sawStart = NO;
        for (NSView *view in panel.contentView.subviews){
            if ([view isKindOfClass:NSPopUpButton.class] && [view.accessibilityLabel isEqual:@"Friends in another room"])
                assert([[(NSPopUpButton *)view itemTitles] isEqual:@[@"Bo (room Red)"]]);                      /* (the friends' tests above) */
            else if ([view isKindOfClass:NSPopUpButton.class]) assert([(NSPopUpButton *)view numberOfItems] == NATIVE_PHRASES);
            if ([view isKindOfClass:NSTextField.class] && [[(NSTextField *)view stringValue] containsString:@"Synthetic tune"]) sawMusic = YES;
            if ([view isKindOfClass:NSTextField.class] && [[(NSTextField *)view stringValue] containsString:@"2. Guest"]) sawLobby = YES;
            if ([view isKindOfClass:NSButton.class]){
                NSButton *b = (NSButton *)view;
                if ([b.title isEqual:@"Start race"] && b.enabled) sawStart = YES;
                if ([@[@"Pause", @"Next track", @"Say", @"Leave lobby"] containsObject:b.title]) assert([NSApp sendAction:b.action to:b.target from:b]);
            }
        }
        assert(sawMusic && sawLobby && sawStart && paused == 1 && nexts == 1);
        assert(roam_plat_say_pick() == 0);                        /* Say: the popup's first phrase */
        assert(roam_plat_action() == ROAM_ACTION_LEAVE);
        for (NSView *view in panel.contentView.subviews)
            if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title hasPrefix:@"Music folder"]){
                ((NSButton *)view).state = NSControlStateValueOff;
                assert([NSApp sendAction:((NSButton *)view).action to:((NSButton *)view).target from:view]); }
        assert(enabled == 0);                                     /* back to the game's soundtrack */
        enabled = 1; paused = 0;
        roam_plat_lobby("{\"v\":\"lobby\",\"st\":\"host\",\"kind\":\"Sprint\",\"track\":\"Synthetic track\",\"laps\":2,\"names\":[\"Driver\",\"Guest\"],\"me\":0,\"max\":6}");
        [panel makeKeyAndOrderFront:nil];
        [NSApp sendAction:NSSelectorFromString(@"refresh") to:panel.delegate from:nil];
        [panel.contentView displayIfNeeded];
        NSBitmapImageRep *bitmap = [panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
        [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
        assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES]);
        puts("native AppKit panel snapshot passed");
    }
    puts("native controls state, validation, bounded queue and guest handoff passed");
} }
