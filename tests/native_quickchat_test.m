#import <Cocoa/Cocoa.h>
#include <assert.h>
#include "native_controls.h"
#include "gamepad.h"
#include "cpu.h"
uint8_t *g_mem;
uint8_t g_cbits[1u<<15] __attribute__((aligned(16)));
static int photo;
int native_scene_active(void) { return photo; }
void kbd_set_key(int src,unsigned dik,int down) { (void)src; (void)dik; (void)down; }
void kbd_post(uint32_t m,uint32_t w,uint32_t l) { (void)m; (void)w; (void)l; }
/* Same translation unit exposes the bounded producer snapshot to assertions. */
#define NATIVE_CONTROLS_TEST_SCENE 1
#include "../runtime/native_controls.m"
static NSEvent *key(int code,BOOL down,BOOL repeat) {
    return [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:repeat keyCode:code];
}
int main(int argc,char **argv) { @autoreleasepool {
    g_mem=calloc(1,0x900000); assert(g_mem); memset(g_cbits,255,0x900000/0x4000/8);
    MR32(0x8654a4)=6; MR32(0x890118)=0x10000; MR32(0x10000)=4;
    MR32(0x8900ac)=0x20000; MR32(0x20004)=0x1234; MR32(0x209a4)=0x60000;
    MR32(0x8384c4)=0x30000; MR32(0x30008)=0x40000; MR32(0x400e4)=0x50000;
    MR32(0x5000c)=0x70000; MR32(0x60010)=0x71000;
    strcpy((char *)g_mem+0x70000,"HUD_SingleRace.fng"); strcpy((char *)g_mem+0x71000,"HUD_SingleRace.fng");
    assert(chat_guest_driving());
    MR32(0x827e98)=1; assert(!chat_guest_driving()); MR32(0x827e98)=0;
    strcpy((char *)g_mem+0x70000,"UI_pause.fng"); assert(!chat_guest_driving());
    strcpy((char *)g_mem+0x70000,"HUD_SingleRace.fng");
    MR32(0x89e7b0)=2; assert(!chat_guest_driving()); MR32(0x89e7b0)=0;
    native_controls_guest_frame(); assert(qDriving);
    free(g_mem); g_mem=NULL; memset(g_cbits,0,sizeof g_cbits);
    int layout[16]={151,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0};
    assert(native_controls_set_chat_layout(layout));
    layout[15]=152; assert(!native_controls_set_chat_layout(layout));
    qDriving=1; qFocused=1; qDriveAt=chat_now();
    native_controls_set_network(0);
    assert(!native_controls_handle_event(key(18,YES,NO)));
    PadState offline={.connected=1}; offline.axis[PAD_AXIS_RX]=1;
    native_controls_filter_pad(&offline); assert(offline.axis[PAD_AXIS_RX]==1);
    native_controls_set_network(1);
    offline.axis[PAD_AXIS_RX]=0; native_controls_filter_pad(&offline);
    assert(native_controls_handle_event(key(18,YES,NO)));
    assert(native_controls_handle_event(key(18,YES,YES)));
    assert(native_controls_say_pick()==-1);
    assert(native_controls_handle_event(key(18,NO,NO)));
    assert(native_controls_handle_event(key(18,YES,NO)));
    assert(native_controls_say_pick()==151);
    assert(native_controls_handle_event(key(18,NO,NO)));
    assert(!native_controls_handle_event(key(0,YES,NO)));
    assert(native_controls_handle_event(key(19,YES,NO)));
    assert(native_controls_handle_event(key(19,NO,NO)));
    qUntil=chat_now()-1;
    assert(native_controls_handle_event(key(18,YES,NO)));
    assert(native_controls_say_pick()==-1); /* timeout opens a group instead of saying */
    assert(native_controls_handle_event(key(18,NO,NO)));
    assert(native_controls_handle_event(key(53,YES,NO)));
    assert(native_controls_handle_event(key(53,NO,NO)));
    PadState pad={.connected=1}; pad.axis[PAD_AXIS_RY]=-1; pad.axis[PAD_AXIS_RT]=0.6;
    native_controls_filter_pad(&pad); assert(!pad.axis[PAD_AXIS_RY] && pad.axis[PAD_AXIS_RT]==0.6f);
    pad.axis[PAD_AXIS_RY]=0; native_controls_filter_pad(&pad);
    pad.axis[PAD_AXIS_RX]=1; native_controls_filter_pad(&pad); assert(!pad.axis[PAD_AXIS_RX]);
    assert(native_controls_say_pick()==2);
    pad.axis[PAD_AXIS_RX]=1; native_controls_filter_pad(&pad); assert(!pad.axis[PAD_AXIS_RX]);
    pad.axis[PAD_AXIS_RX]=0; native_controls_filter_pad(&pad);
    photo=1; pad.axis[PAD_AXIS_RX]=1; native_controls_filter_pad(&pad); assert(pad.axis[PAD_AXIS_RX]==1);
    photo=0; pad.connected=0; native_controls_filter_pad(&pad); assert(qGroup==-1);
    assert(native_controls_said("{\"id\":7,\"name\":\"Driver\",\"p\":1}")==1);
    uint32_t ids[]={7}; float xy[]={0.25,0.5,0.8}; native_controls_say_marks(ids,xy,1);
    assert(qLines[0].id==7 && qMarksCount==1 && qMarks[0].x==0.25f);
    float bad[]={NAN,0.5,0.8}; native_controls_say_marks(ids,bad,1); assert(qMarksCount==0);
    assert(native_controls_said("{\"id\":8,\"name\":\"Guest\",\"p\":2}")==1);
    native_controls_say_marks(ids,xy,1); native_controls_forget(7); assert(!qLines[0].id);
    assert(native_controls_said("{\"id\":8,\"name\":\"Guest\",\"p\":3}")==1);
    int same=0; for(int i=0;i<CHAT_LINES;i++) same+=qLines[i].id==8; assert(same==1);
    qLines[1].until=chat_now()-1; pad.connected=1; pad.axis[PAD_AXIS_RX]=0;
    native_controls_filter_pad(&pad); assert(!qLines[1].id);
    pad.buttons=1u<<PAD_RS; native_controls_filter_pad(&pad); assert(!pad.buttons && qGroup==0);
    pad.buttons=1u<<PAD_B; native_controls_filter_pad(&pad); assert(!pad.buttons && qGroup==-1);
    pad.buttons=1u<<PAD_B; native_controls_filter_pad(&pad); assert(!pad.buttons);
    pad.buttons=0; native_controls_filter_pad(&pad);
    qFocused=0; pad.buttons=1u<<PAD_B; native_controls_filter_pad(&pad); assert(pad.buttons==(1u<<PAD_B));
    assert(!native_controls_handle_event(key(18,YES,NO)));
    qFocused=1; native_controls_forget(0);
    for(int i=0;i<3;i++) {
        assert(native_controls_handle_event(key(18,YES,NO))); assert(native_controls_handle_event(key(18,NO,NO)));
        assert(native_controls_handle_event(key(18,YES,NO))); assert(native_controls_handle_event(key(18,NO,NO)));
        assert(native_controls_say_pick()==151);
    }
    assert(native_controls_handle_event(key(18,YES,NO))); assert(native_controls_handle_event(key(18,NO,NO)));
    assert(native_controls_handle_event(key(18,YES,NO))); assert(native_controls_handle_event(key(18,NO,NO)));
    assert(native_controls_say_pick()==-1);
    for(int i=0;i<3;i++) qSent[i]-=6.1;
    assert(native_controls_handle_event(key(18,YES,NO))); assert(native_controls_handle_event(key(18,NO,NO)));
    assert(native_controls_say_pick()==151);
    native_controls_forget(0);
    for(int i=1;i<=40;i++) { char json[100]; snprintf(json,sizeof json,"{\"id\":%d,\"name\":\"Driver\",\"p\":0}",i); assert(native_controls_said(json)==1); }
    int lines=0; for(int i=0;i<CHAT_LINES;i++) lines+=qLines[i].id!=0; assert(lines==CHAT_LINES);
    native_controls_forget(0); for(int i=0;i<CHAT_LINES;i++) assert(!qLines[i].id); assert(!qMarksCount);
    if(argc==3 && !strcmp(argv[1],"--snapshot")) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSWindow *game=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        native_controls_attach(game); [ui configureChat:nil];
        assert(ui.chatNames.count==4 && ui.chatPhrases.count==16);
        for(NSPopUpButton *popup in ui.chatPhrases) assert(popup.numberOfItems==152);
        qDriving=1; qFocused=1; qDriveAt=chat_now(); qGroup=0; qUntil=chat_now()+4;
        assert(native_controls_said("{\"id\":7,\"name\":\"Driver\",\"p\":57}")==1);
        native_controls_say_marks(ids,xy,1);
        [ui.chatSettings.contentView displayIfNeeded];
        for(NSView *view in @[ui.chatOverlay,ui.chatSettings.contentView]) {
            NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            NSString *path=[[NSString stringWithUTF8String:argv[2]] stringByAppendingString:view==ui.chatOverlay ? @"-overlay.png" : @"-groups.png"];
            assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
        }
        puts("quick chat native group editor and overlay snapshots passed");
    }
    puts("quick chat layout, key/pad capture, timeout, bounded bubbles and disconnect passed");
} }
