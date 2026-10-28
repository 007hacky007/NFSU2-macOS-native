#import <Cocoa/Cocoa.h>
#include <assert.h>
#include <pthread.h>
#include "native_controls.h"
#include "roam_core.h"
#include "radio_native.h"
#include "roam_plat.h"
static int keys, posts, leaves;
void roam_game_event(int ev,int peer,const char *text) { (void)ev; (void)peer; (void)text; }
static int pauses, nextTracks;
void radio_native_snapshot(RadioNativeSnapshot *out) {
    memset(out,0,sizeof *out); out->tracks=2; out->enabled=1;
    snprintf(out->artist,sizeof out->artist,"Synthetic artist"); snprintf(out->title,sizeof out->title,"Synthetic tune");
}
void radio_native_set_paused(int paused) { pauses=paused; }
void radio_native_next(void) { nextTracks++; }
void kbd_set_key(int src, unsigned dik, int down) { (void)src; assert(dik == 0x1c); keys += down ? 1 : -1; }
void kbd_post(uint32_t m, uint32_t w, uint32_t l) { (void)m; (void)w; (void)l; posts++; }
void roam_game_native_leave(void) { leaves++; }
static void *produce(void *unused) {
    (void)unused;
    for (int i = 0; i < 1000; i++) {
        native_controls_lobby("{\"v\":\"lobby\",\"st\":\"count\",\"kind\":\"Sprint\",\"track\":\"Synthetic\",\"names\":[\"Driver\"],\"t\":3,\"max\":6}");
        native_controls_notice("Driver", " joined");
    }
    return NULL;
}
int main(int argc,char **argv) { @autoreleasepool {
    assert(roam_plat_quickchat()==1);
    assert(roam_plat_lobby("{}") == 1);
    assert(native_controls_lobby("{") == -1);
    assert(native_controls_lobby("[]") == -1);
    assert(native_controls_lobby("{\"names\":[2]}") == -1);
    assert(native_controls_lobby("{\"v\":\"lobby\",\"t\":\"bad\"}") == -1);
    assert(native_controls_lobby("{\"v\":\"unknown\"}") == -1);
    assert(native_controls_lobby("{\"v\":\"lobby\",\"st\":\"unknown\"}") == -1);
    assert(native_controls_lobby("{}") == 1);
    assert(native_controls_said("{\"name\":\"Driver\",\"p\":0}") == 1);
    assert(native_controls_said("{\"name\":\"Driver\",\"p\":999}") == -1);
    assert(native_controls_said("{\"name\":2,\"p\":0}") == -1);
    assert(native_controls_said("{\"name\":\"Driver\",\"p\":0.5}") == -1);
    assert(native_controls_said("{\"name\":\"Driver\",\"p\":true}") == -1);
    assert(native_controls_said("{\"name\":\"Driver\",\"p\":0,\"me\":{}}") == -1);
    assert(native_controls_pick(0)); assert(native_controls_say_pick() == 0);
    assert(native_controls_say_pick() == -1); assert(!native_controls_pick(-1));
    assert(!native_controls_pick(999));
    for (int i=0; i<16; i++) assert(native_controls_pick(i));
    assert(!native_controls_pick(0));
    for (int i=0; i<16; i++) assert(native_controls_say_pick() == i);
    assert(native_controls_solid() == -1);
    native_controls_set_solid(1); assert(native_controls_solid() == 1);
    assert(roam_plat_solid()==1);
    native_controls_set_solid(0); assert(native_controls_solid() == 0);
    char error[160]; uint32_t h[4], rgb[4];
    assert(native_controls_set_crews("Blue Room, Night Owls", "3cd2ff,ff50c8", error, sizeof error));
    uint32_t gen = native_controls_crews(h,rgb); assert(gen && h[0] && h[1] && !h[2]);
    assert(roam_plat_crews(h,rgb)==gen);
    assert(h[0] == rc_room_hash("blueroom"));
    assert(rgb[0] == 0x3cd2ff && rgb[1] == 0xff50c8);
    assert(!native_controls_set_crews("Blue Room, blueroom", "", error, sizeof error));
    assert(!native_controls_set_crews("one,two,three,four,five", "", error, sizeof error));
    assert(!native_controls_set_crews("one", "nothex", error, sizeof error));
    assert(!native_controls_set_crews("name#comment", "", error, sizeof error));
    assert(!native_controls_set_crews("a name with more than twenty four characters", "", error, sizeof error));
    assert(!native_controls_set_crews("nazi", "", error, sizeof error));
    assert(native_controls_crews(h,rgb) == gen);
    assert(native_controls_set_crews("", "", error, sizeof error));
    assert(native_controls_crews(h,rgb) != gen && !h[0]);
    native_controls_action(NATIVE_CONTROL_ENGAGE);
    native_controls_guest_frame(); assert(keys == 1);
    for(int i=0; i<6; i++) native_controls_guest_frame();
    assert(keys == 0 && posts == 3);
    native_controls_action(NATIVE_CONTROL_LEAVE); native_controls_guest_frame(); assert(leaves == 1);
    pthread_t t; assert(!pthread_create(&t,NULL,produce,NULL));
    for (int i=0; i<1000; i++) { native_controls_solid(); native_controls_crews(h,rgb); }
    pthread_join(t,NULL);
    assert(native_controls_lobby("{}") == 1);
    if(argc==3 && !strcmp(argv[1],"--snapshot")) {
        setenv("NFSU2_ROAM_CREW","Blue Room, Night Owls",1);
        setenv("NFSU2_ROAM_CREW_RGB","3cd2ff,ff50c8",1);
        setenv("NFSU2_ROAM_COLLIDE","1",1);
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSWindow *game=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        native_controls_lobby("{\"v\":\"lobby\",\"st\":\"count\",\"kind\":\"Sprint\",\"track\":\"Synthetic track\",\"names\":[\"Driver\",\"Guest\"],\"me\":0,\"t\":3,\"max\":6}");
        native_controls_attach(game);
        NSMenu *menu=[NSMenu new]; native_controls_add_menu(menu); assert(menu.numberOfItems==1);
        NSWindow *panel=nil; for(NSWindow *w in NSApp.windows) if([w.title isEqual:@"Game Tools"]) panel=w;
        assert(panel && panel.contentView.subviews.count>10);
        BOOL sawMusic=NO;
        for(NSView *view in panel.contentView.subviews) {
            if([view isKindOfClass:NSPopUpButton.class]) assert([(NSPopUpButton *)view numberOfItems]==152);
            if([view isKindOfClass:NSTextField.class] && [[(NSTextField *)view stringValue] containsString:@"Synthetic tune"]) sawMusic=YES;
            if([view isKindOfClass:NSButton.class]) {
                NSButton *b=(NSButton *)view;
                if([@[@"Pause",@"Next track",@"Say",@"Leave lobby"] containsObject:b.title]) assert([NSApp sendAction:b.action to:b.target from:b]);
            }
        }
        assert(sawMusic && pauses==1 && nextTracks==1);
        assert(native_controls_say_pick()==0);
        native_controls_guest_frame(); assert(leaves==2);
        [panel.contentView displayIfNeeded];
        NSBitmapImageRep *bitmap=[panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
        [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
        assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES]);
        puts("native AppKit panel snapshot passed");
    }
    puts("native controls state, validation, bounded queue and guest handoff passed");
} }
