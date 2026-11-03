/* native_quickchat_test.m -- quick chat's picker without the game: the keys
 * (1-4 twice, Esc, held keys, modifiers), the controller (dinput_pad.c's PadState: right stick flicks,
 * its click, B; the game sees none of what the picker takes), the 4 s
 * timeout, focus loss, offline and racing (the keys and the stick stay the
 * game's), photo mode, the burst limit, the lines over the cars and a player
 * leaving, a race between players (racehorn.c's picks and the race's chat
 * log); with --snapshot <prefix> the groups editor and the overlay.
 * tests/native_controls.sh builds and runs it. */
#import <Cocoa/Cocoa.h>
#include <assert.h>
#include "roam_core.h"
void roam_game_event(int ev, int peer, const char *text){ (void)ev; (void)peer; (void)text; }
static int photo;
int native_scene_active(void){ return photo; }
/* the same translation unit: the picker's state is visible to the checks */
#define NATIVE_CONTROLS_TEST_SCENE 1
#include "../runtime/native_controls.m"
void radio_native_snapshot(RadioNativeSnapshot *o){ memset(o, 0, sizeof *o); }
void radio_native_set_enabled(int e){ (void)e; }
void radio_native_set_paused(int p){ (void)p; }
void radio_native_set_shuffle(int s){ (void)s; }
void radio_native_next(void){}

static NSEvent *key(int code, BOOL down, BOOL repeat){
    return [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:0
                        windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:repeat keyCode:code];
}
static NSEvent *cmdkey(int code){
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0
                        windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
}
/* the controller as dinput_pad.c hands it over */
static PadState ps;
static void pad(float rx, float ry, int b, int rs){
    memset(&ps, 0, sizeof ps); ps.connected = 1;
    ps.axis[PAD_AXIS_RX] = rx; ps.axis[PAD_AXIS_RY] = ry; ps.axis[PAD_AXIS_RT] = 0.6f;   /* the triggers: never touched */
    ps.buttons = 1u << PAD_A | (b ? 1u << PAD_B : 0) | (rs ? 1u << PAD_RS : 0);         /* A: never touched */
    native_controls_filter_pad(&ps);
    assert(ps.axis[PAD_AXIS_RT] == 0.6f && (ps.buttons & 1u << PAD_A));
}
#define AX_RX (ps.axis[PAD_AXIS_RX])
#define AX_RY (ps.axis[PAD_AXIS_RY])
#define HAS_B (ps.buttons & 1u << PAD_B)
#define HAS_RS (ps.buttons & 1u << PAD_RS)
static int press(int code){ int a = native_controls_handle_event(key(code, YES, NO)), b = native_controls_handle_event(key(code, NO, NO)); return a && b; }
int main(int argc, char **argv){ @autoreleasepool {
    int layout[16] = {151,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0};
    assert(native_controls_set_chat_layout(layout));
    layout[15] = 152; assert(!native_controls_set_chat_layout(layout));
    qFocused = 1;
    /* offline (no session, or quick chat off in the launcher): the keys and the stick are the game's */
    roam_plat_driving(1);
    native_controls_set_network(0);
    assert(!native_controls_handle_event(key(18, YES, NO)));
    pad(1, 0, 0, 0); assert(AX_RX == 1);
    /* a race (roam_game.c: not driving in free roam): the game's too */
    native_controls_set_network(1); roam_plat_driving(0);
    assert(!native_controls_handle_event(key(18, YES, NO)));
    pad(1, 0, 0, 0); assert(AX_RX == 1);
    pad(0, 0, 0, 0);
    /* driving in free roam with the session up: 1 opens group 1, 1 again says its first phrase */
    roam_plat_driving(1);
    assert(native_controls_handle_event(key(18, YES, NO)));
    assert(native_controls_handle_event(key(18, YES, YES)));        /* its repeats are ours */
    assert(roam_plat_say_pick() == -1);
    assert(native_controls_handle_event(key(18, NO, NO)));
    assert(native_controls_handle_event(key(18, YES, NO)));
    assert(roam_plat_say_pick() == 151);
    assert(native_controls_handle_event(key(18, NO, NO)));
    assert(!native_controls_handle_event(key(0, YES, NO)));           /* A: the game's */
    assert(!native_controls_handle_event(cmdkey(19)));                /* Cmd+2: the menu's */
    /* the keypad's 2 opens group 2; the timeout closes it, so the next 1 opens a group instead of saying */
    assert(press(84)); assert(qGroup == 1);
    qUntil = now_s() - 1;
    assert(press(18)); assert(roam_plat_say_pick() == -1 && qGroup == 0);
    assert(press(53)); assert(qGroup == -1);                          /* Esc closes */
    assert(!native_controls_handle_event(key(53, YES, NO)));          /* ...and is the game's when closed */
    /* focus lost: closed, and the keys are the game's */
    assert(press(18)); qFocused = 0; chat_expire(now_s()); assert(qGroup == -1);
    assert(!native_controls_handle_event(key(18, YES, NO)));
    qFocused = 1;
    /* the controller: a flick up opens group 1, the stick back to the centre, right says its second phrase */
    pad(0, -1, 0, 0); assert(AX_RY == 0 && qGroup == 0 && qPad == 1);
    pad(0, -0.9f, 0, 0); assert(AX_RY == 0);                           /* still held: the game sees none */
    pad(0, 0, 0, 0);
    pad(1, 0, 0, 0); assert(AX_RX == 0 && roam_plat_say_pick() == 2);
    pad(1, 0, 0, 0); assert(AX_RX == 0);                               /* held after the pick: still ours */
    pad(0, 0, 0, 0);
    /* the click opens group 1, B closes; B is not the game's while it closes, nor until let go */
    pad(0, 0, 0, 1); assert(!HAS_RS && qGroup == 0);
    pad(0, 0, 1, 0); assert(!HAS_B && qGroup == -1);
    pad(0, 0, 1, 0); assert(!HAS_B);
    pad(0, 0, 0, 0);
    pad(0, 0, 1, 0); assert(HAS_B);                            /* closed: B is the game's */
    pad(0, 0, 0, 0);
    /* photo mode: the game's */
    photo = 1; pad(1, 0, 0, 0); assert(AX_RX == 1); photo = 0; pad(0, 0, 0, 0);
    /* the pad went away: the picker closes */
    pad(0, -1, 0, 0); assert(qGroup == 0); ps.connected = 0; native_controls_filter_pad(&ps); assert(qGroup == -1);
    pad(0, 0, 0, 0);
    /* the lines over the cars */
    assert(roam_plat_said("{\"id\":7,\"name\":\"Driver\",\"p\":1}") == 1);
    uint32_t ids[] = {7}; float xy[] = {0.25f, 0.5f, 0.8f}; roam_plat_say_marks(ids, xy, 1);
    assert(qLines[0].id == 7 && qMarksCount == 1 && qMarks[0].x == 0.25f);
    float bad[] = {NAN, 0.5f, 0.8f}; roam_plat_say_marks(ids, bad, 1); assert(qMarksCount == 0);
    float out[] = {1.5f, 0.5f, 0.8f}; roam_plat_say_marks(ids, out, 1); assert(qMarksCount == 0);
    assert(roam_plat_said("{\"id\":8,\"name\":\"Guest\",\"p\":2}") == 1);
    roam_plat_say_marks(ids, xy, 1); native_controls_forget(7); assert(!qLines[0].id);   /* Driver left */
    assert(roam_plat_said("{\"id\":8,\"name\":\"Guest\",\"p\":3}") == 1);
    int same = 0; for (int i = 0; i < CHAT_LINES; i++) same += qLines[i].id == 8; assert(same == 1);   /* one line a player */
    qLines[1].until = now_s() - 1; pad(0, 0, 0, 0); assert(!qLines[1].id);                          /* expired */
    /* the burst: three in six seconds, then the picker says wait */
    native_controls_forget(0);
    for (int i = 0; i < 3; i++){ assert(press(18)); assert(press(18)); assert(roam_plat_say_pick() == 151); }
    assert(press(18)); assert(press(18)); assert(roam_plat_say_pick() == -1);
    for (int i = 0; i < 3; i++) qSent[i] -= 6.1;
    assert(press(18)); assert(press(18)); assert(roam_plat_say_pick() == 151);
    /* bounded: 40 players talking keep 32 lines; the session going down clears them all */
    native_controls_forget(0);
    for (int i = 1; i <= 40; i++){ char json[100]; snprintf(json, sizeof json, "{\"id\":%d,\"name\":\"Driver\",\"p\":0}", i); assert(roam_plat_said(json) == 1); }
    int lines = 0; for (int i = 0; i < CHAT_LINES; i++) lines += qLines[i].id != 0; assert(lines == CHAT_LINES);
    native_controls_set_network(0); for (int i = 0; i < CHAT_LINES; i++) assert(!qLines[i].id); assert(!qMarksCount);
    /* a race between players (racehorn.c: native_controls_set_race), free roam off: the picker is there, driving
     * and on the results, and racehorn.c takes the picks, free roam none */
    native_controls_forget(0); roam_plat_driving(0);
    native_controls_set_race(0);
    assert(!native_controls_handle_event(key(18, YES, NO))); assert(!native_controls_handle_event(key(18, NO, NO)));
    native_controls_set_race(1);
    assert(press(18)); assert(press(18));
    assert(roam_plat_say_pick() == -1 && native_controls_race_pick() == 151 && native_controls_race_pick() == -1);
    pad(0, -1, 0, 0); pad(0, 0, 0, 0); pad(1, 0, 0, 0); assert(AX_RX == 0 && native_controls_race_pick() == 2);   /* the stick too */
    pad(0, 0, 0, 0);
    native_controls_set_race(2);                                        /* the results */
    assert(press(19)); assert(press(19)); assert(native_controls_race_pick() == layout[5]);
    assert(press(19)); assert(press(19)); assert(native_controls_race_pick() == -1);   /* the burst: three in six seconds */
    for (int i = 0; i < qSentCount; i++) qSent[i] -= 6.1;
    assert(press(19)); assert(press(19)); assert(native_controls_race_pick() == layout[5]);
    assert(native_controls_pick(9)); assert(roam_plat_say_pick() == -1);   /* the panel's Say: the race's too */
    native_controls_set_race(0);                                        /* out of the race: what was picked goes */
    assert(native_controls_race_pick() == -1 && roam_plat_say_pick() == -1);
    assert(!native_controls_handle_event(key(18, YES, NO))); assert(!native_controls_handle_event(key(18, NO, NO)));
    native_controls_set_race(1); assert(press(18)); qRaceAt = now_s() - 1;   /* racehorn.c stopped saying so: closed */
    chat_expire(now_s()); assert(qGroup == -1);
    assert(!native_controls_handle_event(key(18, YES, NO))); assert(!native_controls_handle_event(key(18, NO, NO)));
    native_controls_set_race(3); assert(!qRace);                        /* not a state */
    /* what was said in the race: its chat log, not a line over a car; the last RACE_LOG kept */
    native_controls_set_race(1);
    assert(roam_plat_said("{\"id\":9,\"name\":\"Racer\",\"p\":4,\"race\":1}") == 1);
    for (int i = 0; i < CHAT_LINES; i++) assert(qLines[i].id != 9);
    assert(qRaceLogCount == 1 && !strcmp(qRaceLog[0].name, "Racer") && qRaceLog[0].phrase == 4 && !qRaceLog[0].me);
    assert(roam_plat_said("{\"id\":9,\"name\":\"Me\",\"p\":5,\"race\":1,\"me\":1}") == 1);
    assert(qRaceLogCount == 2 && !strcmp(qRaceLog[1].name, "You") && qRaceLog[1].me);
    assert(roam_plat_said("{\"id\":9,\"name\":\"Racer\",\"p\":4,\"race\":2}") == -1);
    assert(roam_plat_said("{\"id\":9,\"name\":\"Racer\",\"p\":200,\"race\":1}") == 1 && qRaceLogCount == 2);   /* a newer game's */
    for (int i = 0; i < 8; i++) assert(roam_plat_said("{\"id\":9,\"name\":\"Racer\",\"p\":7,\"race\":1}") == 1);
    assert(qRaceLogCount == RACE_LOG && qRaceLog[0].phrase == 7);
    native_controls_set_race(0); native_controls_set_race(1); assert(qRaceLogCount == 0);   /* a new race, a new log */
    native_controls_set_race(0);
    /* the groups from the launcher */
    setenv("NFSU2_QUICKCHAT_GROUPS", "Hi,Ok,Go,Race", 1);
    setenv("NFSU2_QUICKCHAT_PHRASES", "16,17,18,19,4,5,30,31,8,9,10,67,12,13,108,114", 1);
    groups_from_env(); assert(!strcmp(qGroupNames[3], "Race") && qLayout[11] == 67 && qLayout[15] == 114);
    setenv("NFSU2_QUICKCHAT_GROUPS", "Hi,Ok,Go", 1); setenv("NFSU2_QUICKCHAT_PHRASES", "1,2,3", 1);
    groups_from_env(); assert(!strcmp(qGroupNames[3], "Race") && qLayout[0] == 16);   /* a wrong list: ignored whole */
    if (argc == 3 && !strcmp(argv[1], "--snapshot")){
        unsetenv("NFSU2_QUICKCHAT_GROUPS"); unsetenv("NFSU2_QUICKCHAT_PHRASES");
        setenv("NFSU2_ROAM", "1", 1);
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSWindow *game = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 540) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        game.contentView.wantsLayer = YES; game.contentView.layer.backgroundColor = NSColor.darkGrayColor.CGColor;
        native_controls_install(game); [ui configureChat:nil];
        assert(ui.groupFields.count == 4 && ui.groupPhrases.count == 16);
        for (NSPopUpButton *p in ui.groupPhrases) assert(p.numberOfItems == NATIVE_PHRASES);
        native_controls_set_network(1); roam_plat_driving(1); qFocused = 1; qGroup = 0; qPad = 0; qUntil = now_s() + 4;
        assert(roam_plat_said("{\"id\":7,\"name\":\"Driver\",\"p\":57}") == 1);
        float at[] = {0.6f, 0.45f, 0.9f}; roam_plat_say_marks(ids, at, 1);
        [ui.chatPanel.contentView displayIfNeeded];
        for (NSView *view in @[ui.overlay, ui.chatPanel.contentView]){
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            NSString *path = [[NSString stringWithUTF8String:argv[2]] stringByAppendingString:view == ui.overlay ? @"-overlay.png" : @"-groups.png"];
            assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
        }
        /* a race between players: the picker and the race's chat log */
        native_controls_set_network(0); roam_plat_driving(0); native_controls_set_race(1); qGroup = 3; qUntil = now_s() + 4;
        assert(roam_plat_said("{\"id\":7,\"name\":\"Driver\",\"p\":21,\"race\":1}") == 1);
        assert(roam_plat_said("{\"id\":8,\"name\":\"Me\",\"p\":2,\"race\":1,\"me\":1}") == 1);
        NSBitmapImageRep *bitmap = [ui.overlay bitmapImageRepForCachingDisplayInRect:ui.overlay.bounds];
        [ui.overlay cacheDisplayInRect:ui.overlay.bounds toBitmapImageRep:bitmap];
        assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                   writeToFile:[[NSString stringWithUTF8String:argv[2]] stringByAppendingString:@"-race-overlay.png"] atomically:YES]);
        puts("quick chat group editor and overlay snapshots passed");
    }
    puts("quick chat layout, key/pad capture, timeout, focus, offline, bounded lines, disconnect and races between players passed");
} }
