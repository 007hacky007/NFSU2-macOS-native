#import <Cocoa/Cocoa.h>
#include <pthread.h>
#include <math.h>
#include "native_controls.h"
#include "roam_core.h"
#include "names.h"
#include "kbd.h"
#include "radio_native.h"
#include "cpu.h"
#include <time.h>
#include <ctype.h>
#ifndef NATIVE_CONTROLS_TEST_SCENE
__attribute__((weak)) int native_scene_active(void) { return 0; }
#endif
/* Standalone controls tests do not start a decoder or read local music. */
__attribute__((weak)) void radio_native_snapshot(RadioNativeSnapshot *out) { memset(out,0,sizeof *out); }
__attribute__((weak)) void radio_native_set_enabled(int enabled) { (void)enabled; }
__attribute__((weak)) void radio_native_set_paused(int paused) { (void)paused; }
__attribute__((weak)) void radio_native_set_shuffle(int shuffle) { (void)shuffle; }
__attribute__((weak)) void radio_native_next(void) {}

/* Own lock only. Session callbacks copy bounded state and never touch AppKit. */
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static NSDictionary *lobby;
static NSMutableArray<NSString *> *messages;
static int picks[16], pickHead, pickCount, solid = -1, action;
static uint32_t crewHashes[4], crewRGB[4], crewGeneration;
static NSString *crewNames = @"", *crewColours = @"";
static const uint32_t defaults[4] = {0x3cd2ff,0xff50c8,0xa078ff,0xff4646};
int native_controls_available(void) { return 1; }
/* Donor phrases.ts wire IDs: append only, never reorder. */
static const char *phrases[] = {
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
/* Guest producers publish fixed-size state; only the main thread draws it. */
#define CHAT_LINES 32
static struct { uint32_t id; int phrase, me; double until; } qLines[CHAT_LINES];
static struct { uint32_t id; float x,y,scale; } qMarks[CHAT_LINES];
static int qMarksCount;
static double qMarksAt;
static int qLayout[16]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
static int qNetworkEnabled, qDriving, qFocused, qGroup=-1, qPad, qArmed=1, qStickHeld;
static double qDriveAt, qUntil, qSent[3];
static int qSentCount;
static uint32_t qPadHeld;
static BOOL qKeys[128]; /* Keep swallowed releases even after closing. */
static double chat_now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static int chat_eligible(double now) { return qNetworkEnabled && qDriving && qFocused && now-qDriveAt<0.25 && !native_scene_active(); }
static void chat_close(void) { qGroup=-1; }
static int chat_enqueue(int phrase) {
    if(pickCount==16) return 0;
    picks[(pickHead+pickCount)%16]=phrase; pickCount++; return 1;
}
static int chat_wait(double now) {
    while(qSentCount && now-qSent[0]>=6) { memmove(qSent,qSent+1,(--qSentCount)*sizeof *qSent); }
    return qSentCount==3;
}
static void chat_expire(double now) {
    if(qGroup>=0 && (now>=qUntil || !chat_eligible(now))) chat_close();
    for(int i=0;i<CHAT_LINES;i++) if(qLines[i].until<=now) qLines[i].id=0;
}
static void chat_choose(int direction,int pad,double now) {
    if(qGroup<0 || qPad!=pad) { qGroup=direction; qPad=pad; qUntil=now+4; }
    else if(!chat_wait(now)) { if(chat_enqueue(qLayout[qGroup*4+direction])) qSent[qSentCount++]=now; chat_close(); }
}
int native_controls_set_chat_layout(const int layout[16]) {
    if(!layout) return 0;
    for(int i=0;i<16;i++) if(layout[i]<0 || layout[i]>=PHRASE_COUNT) return 0;
    pthread_mutex_lock(&mu); memcpy(qLayout,layout,sizeof qLayout); chat_close(); pthread_mutex_unlock(&mu); return 1;
}
void native_controls_forget(uint32_t id) {
    pthread_mutex_lock(&mu);
    for(int i=0;i<CHAT_LINES;i++) if(!id || qLines[i].id==id) qLines[i].id=0;
    if(!id) { qMarksCount=0; pickCount=0; pickHead=0; qSentCount=0; chat_close(); }
    pthread_mutex_unlock(&mu);
}
void native_controls_set_network(int enabled) {
    pthread_mutex_lock(&mu); qNetworkEnabled=!!enabled; pthread_mutex_unlock(&mu);
    if(!enabled) native_controls_forget(0);
}
void native_controls_say_marks(const uint32_t *ids,const float *xy,int count) {
    pthread_mutex_lock(&mu); qMarksCount=0; qMarksAt=chat_now();
    if(ids && xy && count>0) for(int i=0;i<count && i<CHAT_LINES;i++) {
        float x=xy[3*i], y=xy[3*i+1], sc=xy[3*i+2];
        if(!ids[i] || !isfinite(x) || !isfinite(y) || !isfinite(sc) || x<0 || x>1 || y<0 || y>1 || sc<=0) continue;
        int n=qMarksCount++; qMarks[n].id=ids[i]; qMarks[n].x=x; qMarks[n].y=y; qMarks[n].scale=MIN(sc,1);
    }
    pthread_mutex_unlock(&mu);
}
int native_controls_handle_event(NSEvent *event) {
    if(event.type!=NSEventTypeKeyDown && event.type!=NSEventTypeKeyUp) return 0;
    unsigned code=event.keyCode; if(code>=128) return 0;
    pthread_mutex_lock(&mu);
    if(event.type==NSEventTypeKeyUp) { int mine=qKeys[code]; qKeys[code]=NO; pthread_mutex_unlock(&mu); return mine; }
    if(qKeys[code]) { pthread_mutex_unlock(&mu); return 1; }
    double now=chat_now();
    chat_expire(now);
    int direction=-1;
    switch(code) { case 18: case 83: direction=0; break; case 19: case 84: direction=1; break; case 20: case 85: direction=2; break; case 21: case 86: direction=3; break; }
    int mine=chat_eligible(now) && !(event.modifierFlags&(NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption)) && (direction>=0 || (code==53 && qGroup>=0));
    if(mine) { qKeys[code]=YES; if(!event.isARepeat) { if(code==53) chat_close(); else chat_choose(direction,0,now); } }
    pthread_mutex_unlock(&mu); return mine;
}
void native_controls_filter_pad(PadState *state) {
    pthread_mutex_lock(&mu); double now=chat_now();
    if(!state->connected) { chat_close(); qPadHeld=0; qStickHeld=0; qArmed=1; pthread_mutex_unlock(&mu); return; }
    uint32_t buttons=state->buttons; qPadHeld&=buttons;
    float x=state->axis[PAD_AXIS_RX],y=state->axis[PAD_AXIS_RY],r=hypotf(x,y);
    if(r<0.35f) { qArmed=1; qStickHeld=0; }
    chat_expire(now);
    if(chat_eligible(now)) {
        if(qGroup>=0 && (buttons&(1u<<PAD_B))) { qPadHeld|=1u<<PAD_B; chat_close(); }
        else if((buttons&(1u<<PAD_RS)) && !(qPadHeld&(1u<<PAD_RS))) { qPadHeld|=1u<<PAD_RS; qGroup=0; qPad=1; qUntil=now+4; }
        else if(r>=0.8f && qArmed) {
            qArmed=0; qStickHeld=1;
            int d=fabsf(x)>fabsf(y) ? (x>0 ? 1 : 3) : (y<0 ? 0 : 2);
            chat_choose(d,1,now);
        }
    } else qArmed=r<0.35f;
    if(qStickHeld || (qGroup>=0 && qPad)) state->axis[PAD_AXIS_RX]=state->axis[PAD_AXIS_RY]=0;
    state->buttons&=~qPadHeld;
    pthread_mutex_unlock(&mu);
}
static NSString *stringValue(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSDictionary *jsonObject(const char *json) {
    if (!json || strnlen(json,8193)>8192) return nil;
    NSData *data = [[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}
static BOOL integer(id value, double low, double high) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return NO;
    double n = [value doubleValue];
    return isfinite(n) && floor(n)==n && n>=low && n<=high;
}
int native_controls_lobby(const char *json) { @autoreleasepool {
    NSDictionary *state=jsonObject(json); if (!state) return -1;
    NSArray *views=@[@"spot",@"join",@"full",@"lobby",@"trip",@"note"];
    if (state[@"v"] && ![views containsObject:state[@"v"]]) return -1;
    if (state[@"st"] && ![@[@"host",@"asked",@"in",@"count"] containsObject:state[@"st"]]) return -1;
    for (NSString *key in @[@"st",@"kind",@"track",@"text",@"step",@"why"])
        if (state[key] && ![state[key] isKindOfClass:NSString.class]) return -1;
    for (NSString *key in @[@"t",@"away",@"closes",@"laps",@"stage",@"max",@"me"])
        if (state[key] && !integer(state[key],-1,3600)) return -1;
    id names=state[@"names"];
    if (names) {
        if (![names isKindOfClass:NSArray.class] || [names count]>RC_LOBBY_MAX) return -1;
        for (id name in names) if (![name isKindOfClass:NSString.class] || [name length]>128) return -1;
    }
    pthread_mutex_lock(&mu); lobby=state; pthread_mutex_unlock(&mu); return 1;
} }
static void addMessage(NSString *text) {
    pthread_mutex_lock(&mu);
    if (!messages) messages=[NSMutableArray array];
    if (messages.count==32) [messages removeObjectAtIndex:0];
    [messages addObject:text]; pthread_mutex_unlock(&mu);
}
void native_controls_notice(const char *name,const char *what) { @autoreleasepool {
    NSString *a=name ? [[NSString alloc] initWithBytes:name length:strnlen(name,256) encoding:NSUTF8StringEncoding] : @"";
    NSString *b=what ? [[NSString alloc] initWithBytes:what length:strnlen(what,512) encoding:NSUTF8StringEncoding] : @"";
    addMessage([NSString stringWithFormat:@"%@%@",a ?: @"",b ?: @""]);
} }
int native_controls_said(const char *json) { @autoreleasepool {
    NSDictionary *s=jsonObject(json);
    if (!s || !integer(s[@"id"],1,UINT32_MAX) || !integer(s[@"p"],0,PHRASE_COUNT-1) || ![s[@"name"] isKindOfClass:NSString.class] || [s[@"name"] length]>128) return -1;
    if (s[@"me"] && !integer(s[@"me"],0,1)) return -1;
    pthread_mutex_lock(&mu);
    double now=chat_now(); int slot=0;
    uint32_t id=[s[@"id"] unsignedIntValue];
    for(int i=1;i<CHAT_LINES;i++) if(qLines[i].until<qLines[slot].until) slot=i;
    for(int i=0;i<CHAT_LINES;i++) if(!qLines[i].id || qLines[i].until<=now) { slot=i; break; }
    for(int i=0;i<CHAT_LINES;i++) if(qLines[i].id==id) { slot=i; break; }
    qLines[slot].id=id; qLines[slot].phrase=[s[@"p"] intValue]; qLines[slot].me=[s[@"me"] boolValue]; qLines[slot].until=now+5;
    pthread_mutex_unlock(&mu);
    addMessage([NSString stringWithFormat:@"%@: %s",s[@"me"] && [s[@"me"] boolValue] ? @"You" : s[@"name"],phrases[[s[@"p"] intValue]]]);
    return 1;
} }
int native_controls_pick(int phrase) {
    if(phrase<0 || phrase>=PHRASE_COUNT) return 0;
    pthread_mutex_lock(&mu); int ok=chat_enqueue(phrase);
    pthread_mutex_unlock(&mu); return ok;
}
int native_controls_say_pick(void) {
    pthread_mutex_lock(&mu); int p=-1;
    if(pickCount) { p=picks[pickHead]; pickHead=(pickHead+1)%16; pickCount--; }
    pthread_mutex_unlock(&mu); return p;
}
int native_controls_solid(void) { pthread_mutex_lock(&mu); int s=solid; pthread_mutex_unlock(&mu); return s; }
void native_controls_set_solid(int s) { pthread_mutex_lock(&mu); solid=!!s; pthread_mutex_unlock(&mu); }
uint32_t native_controls_crews(uint32_t h[4],uint32_t rgb[4]) {
    pthread_mutex_lock(&mu); memcpy(h,crewHashes,sizeof crewHashes); memcpy(rgb,crewRGB,sizeof crewRGB);
    uint32_t generation=crewGeneration; pthread_mutex_unlock(&mu); return generation;
}
static NSString *trim(NSString *s) { return [s stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\n\v\f\r"]]; }
int native_controls_set_crews(const char *names,const char *colours,char *error,size_t capacity) { @autoreleasepool {
    NSString *value=names ? [NSString stringWithUTF8String:names] : @"";
    NSString *col=colours ? [NSString stringWithUTF8String:colours] : @"";
    NSString *why=nil; uint32_t h[4]={0}, rgb[4]={0};
    NSMutableArray *clean=[NSMutableArray array], *cleanRGB=[NSMutableArray array];
    NSArray *parts=[value componentsSeparatedByString:@","], *colparts=[col componentsSeparatedByString:@","];
    if(!value || !col || parts.count>4 || colparts.count>4) why=@"Use up to four crews and colours.";
    NSCharacterSet *bad=[NSCharacterSet characterSetWithCharactersInString:@";#\x7f"];
    for(NSUInteger i=0; !why && i<parts.count; i++) {
        NSString *name=trim(parts[i]);
        NSArray *words=[[name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\n\v\f\r"]] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        name=[words componentsJoinedByString:@" "];
        NSString *colour=i<colparts.count ? trim(colparts[i]) : @"";
        if(colour.length && (colour.length!=6 || [colour rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location!=NSNotFound)) why=@"Colours must be six hex digits (RRGGBB).";
        if(!name.length) continue;
        NSUInteger length=[name lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding]/4;
        if(length>24 || [name rangeOfCharacterFromSet:bad].location!=NSNotFound || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) why=@"Use at most 24 characters; no #, ; or control characters.";
        uint32_t hash=rc_room_hash(name.UTF8String); NSUInteger n=clean.count;
        if(!hash || name_blocked(name.UTF8String)) why=@"Choose another crew name.";
        for(NSUInteger j=0;j<n;j++) if(h[j]==hash) why=@"That crew is already in the list.";
        if(why) break;
        h[n]=hash; unsigned int x=defaults[n]; if(colour.length) [[NSScanner scannerWithString:colour] scanHexInt:&x]; rgb[n]=x ? x : defaults[n];
        [clean addObject:name]; [cleanRGB addObject:[NSString stringWithFormat:@"%06x",rgb[n]]];
    }
    if(why) { if(error && capacity) snprintf(error,capacity,"%s",why.UTF8String); return 0; }
    pthread_mutex_lock(&mu); memcpy(crewHashes,h,sizeof h); memcpy(crewRGB,rgb,sizeof rgb);
    crewNames=[clean componentsJoinedByString:@", "]; crewColours=[cleanRGB componentsJoinedByString:@", "];
    if(!++crewGeneration) ++crewGeneration; pthread_mutex_unlock(&mu); return 1;
} }
void native_controls_action(int a) { if(a!=NATIVE_CONTROL_ENGAGE && a!=NATIVE_CONTROL_LEAVE) return; pthread_mutex_lock(&mu); action=a; pthread_mutex_unlock(&mu); }
__attribute__((weak)) void roam_game_native_leave(void) {}
static uint32_t chat_rd(uint32_t a) {
    if(!g_mem || a>UINT32_MAX-3 || !mem_is_committed(a) || !mem_is_committed(a+3)) return 0;
    uint32_t v; memcpy(&v,g_mem+a,4); return v;
}
static int chat_guest_driving(void) {
    uint32_t r=chat_rd(0x890118), pl=chat_rd(0x8900ac), fe=chat_rd(0x8384c4);
    if((chat_rd(0x850078)&0x208) || chat_rd(0x863470) || (chat_rd(0x89cf69)&255) || (int32_t)chat_rd(0x8669f4)>0 || (int32_t)chat_rd(0x866a14)>0 ||
       chat_rd(0x8654a4)!=6 || !r || chat_rd(r)!=4 || chat_rd(0x89e7b0) || !pl || !chat_rd(pl+4) || chat_rd(0x838974) ||
       chat_rd(0x827e98) || chat_rd(0x827eb0) || chat_rd(0x827ec8)) return 0;
    uint32_t hud=chat_rd(pl+0x9a4), mg=fe ? chat_rd(fe+8) : 0, top=mg ? chat_rd(mg+0xe4) : 0;
    uint32_t a=top ? chat_rd(top+0xc) : 0, b=hud ? chat_rd(hud+0x10) : 0;
    if(!a || !b) return 0;
    for(unsigned i=0;i<40;i++) {
        if(a>UINT32_MAX-i || b>UINT32_MAX-i || !mem_is_committed(a+i) || !mem_is_committed(b+i)) return 0;
        unsigned char x=g_mem[a+i], y=g_mem[b+i];
        if(tolower(x)!=tolower(y)) return 0;
        if(!x) return i>0;
    }
    return 0;
}
void native_controls_guest_frame(void) {
    int driving=chat_guest_driving();
    pthread_mutex_lock(&mu); qDriving=driving; qDriveAt=chat_now(); if(!driving) { chat_close(); qMarksCount=0; } pthread_mutex_unlock(&mu);
    static int held;
    if(held && !--held) { kbd_set_key(KSRC_LEGACY,0x1c,0); kbd_post(0x101,13,0xc01c0001); }
    pthread_mutex_lock(&mu); int a=action; action=0; pthread_mutex_unlock(&mu);
    if(a==NATIVE_CONTROL_ENGAGE && !held) {
        kbd_set_key(KSRC_LEGACY,0x1c,1); kbd_post(0x100,13,0x001c0001); kbd_post(0x102,13,0x001c0001); held=6;
    }
    if(a==NATIVE_CONTROL_LEAVE) roam_game_native_leave();
}

@interface NativeControls : NSObject <NSWindowDelegate>
@property NSWindow *game;
@property NSPanel *chatSettings;
@property NSView *chatOverlay;
@property NSArray<NSTextField *> *chatNames;
@property NSArray<NSPopUpButton *> *chatPhrases;
@property NSTextField *chatError;
@property NSPanel *panel;
@property NSTextField *status, *error;
@property NSArray<NSTextField *> *crewFields;
@property NSArray<NSColorWell *> *crewWells;
@property NSButton *engage, *leave, *collision;
@property NSPopUpButton *phrase;
@property NSTextView *log;
@property NSTextField *music;
@property NSButton *musicEnabled, *pause, *next, *shuffle;
- (void)toggle:(id)sender;
- (void)configureChat:(id)sender;
- (void)saveChat:(id)sender;
- (void)engage:(id)sender;
- (void)leave:(id)sender;
- (void)send:(id)sender;
- (void)apply:(id)sender;
- (void)collision:(id)sender;
- (void)refresh;
- (void)showCrews:(NSString *)names colours:(NSString *)colours;
- (void)musicEnabled:(id)sender;
- (void)pause:(id)sender;
- (void)next:(id)sender;
- (void)shuffle:(id)sender;
@end
@interface NativeControlsView : NSView @end
@implementation NativeControlsView
- (void)drawRect:(NSRect)rect { [NSColor.windowBackgroundColor setFill]; NSRectFill(rect); }
@end
static NativeControls *ui;
static NSTextField *label(NSView *view,NSString *text,NSRect frame) {
    NSTextField *field=[NSTextField wrappingLabelWithString:text]; field.frame=frame; [view addSubview:field]; return field;
}
static NSButton *button(NSView *view,NSString *title,SEL action,NSRect frame) {
    NSButton *b=[NSButton buttonWithTitle:title target:ui action:action]; b.frame=frame; [view addSubview:b]; return b;
}
static NSArray<NSString *> *chatNames;
@interface NativeChatOverlay : NSView @end
@implementation NativeChatOverlay
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; double now=chat_now();
    pthread_mutex_lock(&mu);
    int group=qGroup, pad=qPad, layout[16]; memcpy(layout,qLayout,sizeof layout);
    BOOL visible=chat_eligible(now), wait=chat_wait(now);
    typeof(qLines) lines; memcpy(lines,qLines,sizeof lines);
    typeof(qMarks) marks; memcpy(marks,qMarks,sizeof marks);
    int count=now-qMarksAt<0.15 ? qMarksCount : 0;
    pthread_mutex_unlock(&mu);
    if(!visible) return;
    NSDictionary *attrs=@{NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.whiteColor};
    if(group>=0) {
        NSRect box=NSMakeRect(20,20,300,155);
        [[NSColor colorWithWhite:0.04 alpha:0.9] setFill]; [[NSBezierPath bezierPathWithRoundedRect:box xRadius:10 yRadius:10] fill];
        [(chatNames.count==4 ? chatNames[group] : @"Quick chat") drawAtPoint:NSMakePoint(34,30) withAttributes:attrs];
        if(wait) [@"Wait a moment" drawAtPoint:NSMakePoint(34,55) withAttributes:attrs];
        NSArray *directions=pad ? @[@"Up",@"Right",@"Down",@"Left"] : @[@"1",@"2",@"3",@"4"];
        for(int i=0;!wait && i<4;i++) [[NSString stringWithFormat:@"%@: %s",directions[i],phrases[layout[group*4+i]]] drawAtPoint:NSMakePoint(34,55+22*i) withAttributes:attrs];
        [@"Esc / B closes" drawAtPoint:NSMakePoint(34,148) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:NSColor.lightGrayColor}];
    }
    NSSize size=self.bounds.size;
    for(int i=0;i<CHAT_LINES;i++) {
        if(!lines[i].id || lines[i].until<=now) continue;
        for(int j=0;j<count;j++) {
            if(marks[j].id!=lines[i].id) continue;
            CGFloat sc=MAX(0.7,marks[j].scale), alpha=MIN(1,(lines[i].until-now)/0.6);
            NSDictionary *textAttrs=@{NSFontAttributeName:[NSFont systemFontOfSize:14*sc weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[NSColor.whiteColor colorWithAlphaComponent:alpha]};
            NSString *text=[NSString stringWithUTF8String:phrases[lines[i].phrase]];
            NSSize ts=[text sizeWithAttributes:textAttrs];
            CGFloat x=marks[j].x*size.width, y=marks[j].y*size.height-(lines[i].me ? 0 : 6.5*MIN(size.width/640,size.height/480)*marks[j].scale);
            NSRect box=NSMakeRect(MAX(2,MIN(x-ts.width/2-9,size.width-ts.width-20)),MAX(2,y-ts.height-14),ts.width+18,ts.height+10);
            [[NSColor colorWithWhite:0.04 alpha:0.85*alpha] setFill]; [[NSBezierPath bezierPathWithRoundedRect:box xRadius:7 yRadius:7] fill];
            [text drawAtPoint:NSMakePoint(box.origin.x+9,box.origin.y+5) withAttributes:textAttrs];
            break;
        }
    }
}
@end
@implementation NativeControls
- (void)configureChat:(id)sender {
    (void)sender; pthread_mutex_lock(&mu); chat_close(); pthread_mutex_unlock(&mu);
    if(!self.chatSettings) {
        self.chatSettings=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,930,290) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        self.chatSettings.title=@"Quick chat groups"; self.chatSettings.releasedWhenClosed=NO;
        self.chatSettings.contentView=[[NativeControlsView alloc] initWithFrame:NSMakeRect(0,0,930,290)];
        NSView *v=self.chatSettings.contentView;
        label(v,@"Press 1-4 twice, or flick the right stick twice. Return the stick to centre between picks. R3 opens group 1.",NSMakeRect(20,252,890,26));
        NSMutableArray *names=[NSMutableArray array],*popups=[NSMutableArray array];
        for(int i=0;i<4;i++) {
            label(v,[NSString stringWithFormat:@"%d",i+1],NSMakeRect(20,202-i*42,20,24));
            NSTextField *name=[[NSTextField alloc] initWithFrame:NSMakeRect(42,202-i*42,170,24)];
            name.accessibilityLabel=[NSString stringWithFormat:@"Quick chat group %d name",i+1];
            [v addSubview:name]; [names addObject:name];
            for(int j=0;j<4;j++) {
                NSPopUpButton *p=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(220+j*174,200-i*42,170,28) pullsDown:NO];
                for(int k=0;k<PHRASE_COUNT;k++) [p addItemWithTitle:[NSString stringWithUTF8String:phrases[k]]];
                p.accessibilityLabel=[NSString stringWithFormat:@"Group %d phrase %d",i+1,j+1]; [v addSubview:p]; [popups addObject:p];
            }
        }
        self.chatNames=names; self.chatPhrases=popups;
        self.chatError=label(v,@"Group names use up to 24 characters.",NSMakeRect(20,20,680,28));
        button(v,@"Save groups",@selector(saveChat:),NSMakeRect(774,18,136,32));
    }
    pthread_mutex_lock(&mu); int layout[16]; memcpy(layout,qLayout,sizeof layout); pthread_mutex_unlock(&mu);
    for(int i=0;i<4;i++) self.chatNames[i].stringValue=chatNames[i];
    for(int i=0;i<16;i++) [self.chatPhrases[i] selectItemAtIndex:layout[i]];
    [self.chatSettings center]; [self.chatSettings makeKeyAndOrderFront:nil];
}
- (void)saveChat:(id)sender {
    (void)sender; NSMutableArray *names=[NSMutableArray array],*layout=[NSMutableArray array]; int ids[16];
    for(int i=0;i<4;i++) {
        NSString *name=trim(self.chatNames[i].stringValue);
        if(!name.length || name.length>24 || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) { self.chatError.stringValue=@"Use a group name with 1-24 characters and no control characters."; return; }
        [names addObject:name];
    }
    for(int i=0;i<16;i++) { ids[i]=(int)self.chatPhrases[i].indexOfSelectedItem; [layout addObject:@(ids[i])]; }
    if(!native_controls_set_chat_layout(ids)) return;
    chatNames=names;
    [NSUserDefaults.standardUserDefaults setObject:layout forKey:@"NativeQuickChatPhrases"];
    [NSUserDefaults.standardUserDefaults setObject:names forKey:@"NativeQuickChatGroups"];
    [self.chatSettings orderOut:nil]; [self.panel makeKeyAndOrderFront:nil];
}
- (void)toggle:(id)sender {
    (void)sender;
    if(self.panel.visible) { [self.panel orderOut:nil]; [self.game makeKeyWindow]; return; }
    [self refresh];
    NSRect f=self.game.frame; [self.panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(f)-self.panel.frame.size.width,NSMaxY(f)-36)];
    NSRect screen=self.game.screen.visibleFrame;
    NSRect panel=self.panel.frame;
    panel.origin.x=MAX(NSMinX(screen),MIN(panel.origin.x,NSMaxX(screen)-panel.size.width));
    panel.origin.y=MAX(NSMinY(screen),MIN(panel.origin.y,NSMaxY(screen)-panel.size.height));
    [self.panel setFrame:panel display:NO];
    [self.game addChildWindow:self.panel ordered:NSWindowAbove];
    [self.panel makeKeyAndOrderFront:nil];
}
- (BOOL)windowShouldClose:(NSWindow *)window { (void)window; [self.panel orderOut:nil]; [self.game makeKeyWindow]; return NO; }
- (void)engage:(id)sender { (void)sender; native_controls_action(NATIVE_CONTROL_ENGAGE); [self.panel orderOut:nil]; [self.game makeKeyWindow]; }
- (void)leave:(id)sender { (void)sender; native_controls_action(NATIVE_CONTROL_LEAVE); }
- (void)send:(id)sender { (void)sender; if(!native_controls_pick((int)self.phrase.indexOfSelectedItem)) self.error.stringValue=@"Quick chat is busy. Wait a moment."; }
- (void)musicEnabled:(id)sender { (void)sender; radio_native_set_enabled(self.musicEnabled.state==NSControlStateValueOn); }
- (void)pause:(id)sender { (void)sender; RadioNativeSnapshot s; radio_native_snapshot(&s); radio_native_set_paused(!s.paused); }
- (void)next:(id)sender { (void)sender; radio_native_next(); }
- (void)shuffle:(id)sender { (void)sender; radio_native_set_shuffle(self.shuffle.state==NSControlStateValueOn); }
- (void)collision:(id)sender {
    (void)sender; BOOL on=self.collision.state==NSControlStateValueOn; native_controls_set_solid(on);
    [NSUserDefaults.standardUserDefaults setBool:on forKey:@"NativeSolidCars"];
}
- (void)apply:(id)sender {
    (void)sender; char error[160];
    NSMutableArray *inputNames=[NSMutableArray array], *inputRGB=[NSMutableArray array];
    for(int i=0;i<4;i++) {
        [inputNames addObject:self.crewFields[i].stringValue];
        NSColor *c=[self.crewWells[i].color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        unsigned rgb=((unsigned)lround(c.redComponent*255)<<16)|((unsigned)lround(c.greenComponent*255)<<8)|(unsigned)lround(c.blueComponent*255);
        [inputRGB addObject:[NSString stringWithFormat:@"%06x",rgb]];
    }
    NSString *namesValue=[inputNames componentsJoinedByString:@","], *rgbValue=[inputRGB componentsJoinedByString:@","];
    if(!native_controls_set_crews(namesValue.UTF8String,rgbValue.UTF8String,error,sizeof error)) { self.error.stringValue=[NSString stringWithUTF8String:error]; return; }
    self.error.stringValue=@"Crews updated. Matching names share a crew; crews are public.";
    pthread_mutex_lock(&mu); NSString *names=crewNames,*rgb=crewColours; pthread_mutex_unlock(&mu);
    [self showCrews:names colours:rgb];
    [NSUserDefaults.standardUserDefaults setObject:names forKey:@"NativeCrewNames"];
    [NSUserDefaults.standardUserDefaults setObject:rgb forKey:@"NativeCrewColours"];
}
- (void)showCrews:(NSString *)names colours:(NSString *)colours {
    NSArray *n=[names componentsSeparatedByString:@","], *rgb=[colours componentsSeparatedByString:@","];
    for(int i=0;i<4;i++) {
        self.crewFields[i].stringValue=i<(int)n.count ? trim(n[i]) : @"";
        unsigned colour=defaults[i];
        if(i<(int)rgb.count && [trim(rgb[i]) length]==6) [[NSScanner scannerWithString:trim(rgb[i])] scanHexInt:&colour];
        self.crewWells[i].color=[NSColor colorWithSRGBRed:((colour>>16)&255)/255.0 green:((colour>>8)&255)/255.0 blue:(colour&255)/255.0 alpha:1];
    }
}
- (void)refresh {
    pthread_mutex_lock(&mu); NSDictionary *s=lobby; NSArray *lines=[messages copy]; pthread_mutex_unlock(&mu);
    NSMutableArray<NSString *> *rows=[NSMutableArray array];
    NSString *v=stringValue(s[@"v"]), *st=stringValue(s[@"st"]);
    if(!v.length) [rows addObject:@"Drive to a multiplayer race marker to open or join a lobby."];
    else {
        NSString *kind=stringValue(s[@"kind"]), *track=stringValue(s[@"track"]);
        if(kind.length) [rows addObject:[NSString stringWithFormat:@"%@%@%@",kind,track.length ? @" - " : @"",track]];
        if(s[@"laps"]) [rows addObject:[NSString stringWithFormat:@"%@ laps",s[@"laps"]]];
        if([v isEqual:@"note"]) [rows addObject:stringValue(s[@"text"])];
        if([v isEqual:@"trip"]) [rows addObject:stringValue(s[@"step"])];
        if([v isEqual:@"spot"]) [rows addObject:[NSString stringWithFormat:@"Multiplayer only here: %@",stringValue(s[@"why"])]];
        if([v isEqual:@"full"]) [rows addObject:@"Lobby full. Open another lobby here."];
        if([st isEqual:@"asked"]) [rows addObject:@"Asking to join..."];
        if([st isEqual:@"count"]) [rows addObject:[NSString stringWithFormat:@"Starting in %@",s[@"t"] ?: @0]];
        NSArray *names=s[@"names"];
        for(NSUInteger i=0;i<names.count;i++) [rows addObject:[NSString stringWithFormat:@"%lu. %@%@%@",(unsigned long)i+1,names[i],i==0 ? @" (host)" : @"",s[@"me"] && (NSInteger)i==[s[@"me"] integerValue] ? @" (you)" : @""]];
        if(names.count && s[@"max"]) [rows addObject:[NSString stringWithFormat:@"%lu / %@ players",(unsigned long)names.count,s[@"max"]]];
        if(s[@"away"]) [rows addObject:[NSString stringWithFormat:@"Host away: closes in %@ s",s[@"away"]]];
        if(s[@"closes"]) [rows addObject:[NSString stringWithFormat:@"Closes in %@ s unless someone joins",s[@"closes"]]];
    }
    self.status.stringValue=[rows componentsJoinedByString:@"\n"];
    BOOL host=[st isEqual:@"host"];
    self.engage.title=host ? @"Start race" : [v isEqual:@"join"] ? @"Join lobby" : @"Open lobby";
    self.engage.enabled=[v isEqual:@"spot"] || [v isEqual:@"join"] || [v isEqual:@"full"] || (host && [s[@"names"] count]>=2);
    self.leave.enabled=[v isEqual:@"lobby"];
    NSString *log=[lines componentsJoinedByString:@"\n"] ?: @"";
    if(![log isEqual:self.log.string]) { self.log.string=log; [self.log scrollRangeToVisible:NSMakeRange(log.length,0)]; }
    RadioNativeSnapshot music; radio_native_snapshot(&music);
    NSString *artist=[NSString stringWithUTF8String:music.artist] ?: @"";
    NSString *title=[NSString stringWithUTF8String:music.title] ?: @"";
    self.music.stringValue=title.length ? [NSString stringWithFormat:@"Music: %@%@%@",artist,artist.length ? @" - " : @"",title] : @"Music: choose a folder in the launcher";
    self.music.toolTip=self.music.stringValue;
    self.musicEnabled.state=music.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.musicEnabled.enabled=music.tracks>0;
    self.pause.title=music.paused ? @"Resume" : @"Pause"; self.pause.enabled=music.enabled;
    self.next.enabled=music.enabled; self.shuffle.enabled=music.tracks>0;
    self.shuffle.state=music.shuffle ? NSControlStateValueOn : NSControlStateValueOff;
}
@end
void native_controls_attach(NSWindow *window) {
    NSCAssert(NSThread.isMainThread,@"Native controls attach on main thread");
    if(ui) return;
    ui=[NativeControls new]; ui.game=window;
    ui.panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,520,735) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    ui.panel.title=@"Game Tools"; ui.panel.delegate=ui; ui.panel.releasedWhenClosed=NO;
    ui.panel.hidesOnDeactivate=YES; ui.panel.becomesKeyOnlyIfNeeded=NO;
    ui.panel.collectionBehavior=NSWindowCollectionBehaviorFullScreenAuxiliary;
    [ui.panel orderOut:nil];
    ui.panel.contentView=[[NativeControlsView alloc] initWithFrame:NSMakeRect(0,0,520,735)];
    NSView *view=ui.panel.contentView;
    button(view,@"Quick chat groups...",@selector(configureChat:),NSMakeRect(16,690,210,30));
    label(view,@"1-4 twice or right stick",NSMakeRect(238,694,260,24));
    ui.status=label(view,@"",NSMakeRect(20,500,480,170));
    ui.music=label(view,@"Music",NSMakeRect(20,476,480,20));
    ui.music.maximumNumberOfLines=1; ui.music.lineBreakMode=NSLineBreakByTruncatingTail;
    ui.pause=button(view,@"Pause",@selector(pause:),NSMakeRect(16,444,110,30));
    ui.next=button(view,@"Next track",@selector(next:),NSMakeRect(132,444,120,30));
    ui.musicEnabled=[NSButton checkboxWithTitle:@"Folder music (off: game soundtrack)" target:ui action:@selector(musicEnabled:)]; ui.musicEnabled.frame=NSMakeRect(20,416,360,24); [view addSubview:ui.musicEnabled];
    ui.shuffle=[NSButton checkboxWithTitle:@"Shuffle" target:ui action:@selector(shuffle:)]; ui.shuffle.frame=NSMakeRect(380,416,120,24); [view addSubview:ui.shuffle];
    ui.engage=button(view,@"Open lobby",@selector(engage:),NSMakeRect(16,378,180,32));
    ui.leave=button(view,@"Leave lobby",@selector(leave:),NSMakeRect(204,378,150,32));
    ui.collision=[NSButton checkboxWithTitle:@"Solid cars (off: ghosts)" target:ui action:@selector(collision:)]; ui.collision.frame=NSMakeRect(20,347,400,24); [view addSubview:ui.collision];
    label(view,@"Crews (up to 4) - choose a name and colour",NSMakeRect(20,318,480,22));
    NSMutableArray *fields=[NSMutableArray array], *wells=[NSMutableArray array];
    for(int i=0;i<4;i++) {
        NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(20,286-i*26,345,24)];
        field.placeholderString=[NSString stringWithFormat:@"Crew %d",i+1]; field.accessibilityLabel=field.placeholderString;
        NSColorWell *well=[[NSColorWell alloc] initWithFrame:NSMakeRect(374,286-i*26,48,24)];
        well.accessibilityLabel=[NSString stringWithFormat:@"Crew %d colour",i+1];
        [view addSubview:field]; [view addSubview:well]; [fields addObject:field]; [wells addObject:well];
    }
    ui.crewFields=fields; ui.crewWells=wells;
    button(view,@"Apply",@selector(apply:),NSMakeRect(430,206,76,30));
    ui.error=label(view,@"Matching names share a public crew. Clear a name to leave.",NSMakeRect(20,170,480,34)); ui.error.font=[NSFont systemFontOfSize:11];
    ui.phrase=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(16,139,380,28) pullsDown:NO];
    for(int i=0;i<PHRASE_COUNT;i++) [ui.phrase addItemWithTitle:[NSString stringWithUTF8String:phrases[i]]];
    ui.phrase.accessibilityLabel=@"Quick chat phrase"; [view addSubview:ui.phrase];
    button(view,@"Say",@selector(send:),NSMakeRect(402,138,100,30));
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(20,20,480,110)]; scroll.hasVerticalScroller=YES; scroll.borderType=NSBezelBorder;
    ui.log=[[NSTextView alloc] initWithFrame:scroll.bounds]; ui.log.editable=NO; ui.log.font=[NSFont systemFontOfSize:12]; ui.log.accessibilityLabel=@"Nearby notices and quick chat"; scroll.documentView=ui.log; [view addSubview:scroll];
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    chatNames=@[@"Greetings",@"Replies",@"Driving",@"Racing"];
    NSArray *savedNames=[prefs arrayForKey:@"NativeQuickChatGroups"], *savedLayout=[prefs arrayForKey:@"NativeQuickChatPhrases"];
    if(savedNames.count==4) {
        BOOL valid=YES; for(id name in savedNames) if(![name isKindOfClass:NSString.class] || ![name length] || [name length]>24 || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) valid=NO;
        if(valid) chatNames=[savedNames copy];
    }
    if(savedLayout.count==16) {
        int ids[16]; BOOL valid=YES;
        for(int i=0;i<16;i++) { if(!integer(savedLayout[i],0,PHRASE_COUNT-1)) { valid=NO; break; } ids[i]=[savedLayout[i] intValue]; }
        if(valid) native_controls_set_chat_layout(ids);
    }
    NativeChatOverlay *overlay=[[NativeChatOverlay alloc] initWithFrame:window.contentView.bounds];
    overlay.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [window.contentView addSubview:overlay]; ui.chatOverlay=overlay;
    for(NSNotificationName notification in @[NSWindowDidResignKeyNotification,NSWindowDidBecomeKeyNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:notification object:window queue:nil usingBlock:^(NSNotification *note) {
            pthread_mutex_lock(&mu); qFocused=[note.name isEqual:NSWindowDidBecomeKeyNotification]; if(!qFocused) { chat_close(); memset(qKeys,0,sizeof qKeys); } pthread_mutex_unlock(&mu);
            ui.chatOverlay.needsDisplay=YES;
        }];
    const char *names=getenv("NFSU2_ROAM_CREW"), *rgb=getenv("NFSU2_ROAM_CREW_RGB"), *collide=getenv("NFSU2_ROAM_COLLIDE");
    NSString *initialNames=names ? [NSString stringWithUTF8String:names] ?: @"" : [prefs stringForKey:@"NativeCrewNames"] ?: @"";
    NSString *initialRGB=rgb ? [NSString stringWithUTF8String:rgb] ?: @"" : names ? @"" : [prefs stringForKey:@"NativeCrewColours"] ?: @"";
    [ui showCrews:initialNames colours:initialRGB];
    /* Preserve environment parsing unless a saved native choice is present. */
    if(!names && [prefs objectForKey:@"NativeCrewNames"]) native_controls_set_crews(initialNames.UTF8String,initialRGB.UTF8String,NULL,0);
    BOOL on=collide ? atoi(collide)!=0 : [prefs objectForKey:@"NativeSolidCars"] ? [prefs boolForKey:@"NativeSolidCars"] : YES;
    if(!collide && [prefs objectForKey:@"NativeSolidCars"]) native_controls_set_solid(on);
    ui.collision.state=on ? NSControlStateValueOn : NSControlStateValueOff;
    [ui refresh];
}
void native_controls_add_menu(NSMenu *menu) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Game Tools..." action:@selector(toggle:) keyEquivalent:@"m"];
    item.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift; item.target=ui; [menu addItem:item];
}
void native_controls_pump(void) {
    if(!ui) return;
    double now=chat_now();
    pthread_mutex_lock(&mu);
    qFocused=ui.game.keyWindow && NSApp.active && !ui.panel.keyWindow && !ui.chatSettings.keyWindow;
    chat_expire(now);
    pthread_mutex_unlock(&mu);
    ui.chatOverlay.needsDisplay=YES;
    static double last;
    if(ui.panel.visible && now-last>=0.1) { last=now; [ui refresh]; }
}
