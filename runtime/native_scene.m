#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#include <pthread.h>
#include <stdatomic.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include "native_scene.h"
void photo_input(int command,int a,int b);
void kbdmac_release_all(const char *reason);
void metal_release_input(void);
enum { PH_HELLO,PH_OPEN,PH_HOLD,PH_MOVE,PH_TURN,PH_DRAG,PH_PAN,PH_DOLLY,PH_FOV,PH_ROLL,PH_MODE,PH_RESET };
static pthread_mutex_t statusLock=PTHREAD_MUTEX_INITIALIZER;
static const char *const names[]={"photo","photo_fov","photo_roll","photo_n","drift","drift_key","drift_x","drift_gain","drift_total","drift_best","drift_st","drift_pend"};
static double status[12];
static int feedback;
static double banked,feedbackUntil;
static atomic_int active,focused=1,captureRequest,captureBusy,keyboardHold;
static atomic_uint inputEpoch;
static unsigned char swallowed[128];             /* main thread only */
static NSString *captureNotice;
static pthread_mutex_t noticeLock=PTHREAD_MUTEX_INITIALIZER;
static NSWindow *gameWindow;
static double now(void) { return NSProcessInfo.processInfo.systemUptime; }
int host_status_slot(const char *name) {
    if(name) for(int i=0;i<12;i++) if(!strcmp(name,names[i])) return i;
    return -1;
}
void host_status_set_n(const int *slots,const double *values,int count) {
    if(!slots || !values || count<1 || count>12) return;
    for(int i=0;i<count;i++) if(slots[i]<0 || slots[i]>=12 || !isfinite(values[i]) || fabs(values[i])>1e12) return;
    pthread_mutex_lock(&statusLock);
    double oldTotal=status[8],oldState=status[10];
    for(int i=0;i<count;i++) status[slots[i]]=values[i];
    if(status[8]>oldTotal) { banked=status[8]-oldTotal; feedback=3; feedbackUntil=now()+2.0; }
    if(status[10]!=oldState && (status[10]==3 || status[10]==4)) { feedback=(int)status[10]; feedbackUntil=now()+2.0; }
    int on=((int)status[0]&2)!=0;
    if(atomic_exchange(&active,on)!=on) atomic_fetch_add(&inputEpoch,1);
    pthread_mutex_unlock(&statusLock);
}
void native_scene_snapshot(NativeSceneSnapshot *out) {
    if(!out) return;
    pthread_mutex_lock(&statusLock);
    *out=(NativeSceneSnapshot){.photo=(int)status[0],.fov=status[1],.roll=status[2],.opens=(int)status[3],
        .drift=(int)status[4],.multiplier=(int)status[6],.gain=status[7],.total=status[8],.best=status[9],
        .state=(int)status[10],.pending=status[11],.feedback=feedback,.banked=banked,.feedback_until=feedbackUntil};
    pthread_mutex_unlock(&statusLock);
}
int native_scene_active(void) { return atomic_load(&active); }
static void clearCamera(void) {
    atomic_store(&keyboardHold,0); photo_input(PH_HOLD,0,0); photo_input(PH_MOVE,0,0); photo_input(PH_TURN,0,0);
}
void native_scene_focus(int focus) {
    if(atomic_exchange(&focused,!!focus)!=!!focus) atomic_fetch_add(&inputEpoch,1);
    if(!focus) { memset(swallowed,0,sizeof swallowed); clearCamera(); }
}
static int padAtRest(const PadState *s) {
    if(!s->connected) return 1;
    if(s->buttons) return 0;
    for(int i=0;i<PAD_NAXES;i++) if(fabsf(s->axis[i])>0.08f) return 0;
    return 1;
}
void native_scene_filter_pad(PadState *s) {
    static unsigned epoch; static int quarantine;
    unsigned next=atomic_load(&inputEpoch);
    if(next!=epoch) { epoch=next; quarantine=1; }
    if(native_scene_active() || !atomic_load(&focused)) quarantine=1;
    else if(padAtRest(s)) quarantine=0;
    if(quarantine) { s->buttons=0; memset(s->axis,0,sizeof s->axis); }
}
static int pack(float x,float y) {
    int16_t a=(int16_t)lrintf(fmaxf(-1,fminf(1,x))*32767),b=(int16_t)lrintf(fmaxf(-1,fminf(1,y))*32767);
    return (int)((uint16_t)a | ((uint32_t)(uint16_t)b<<16));
}
static void requestCapture(void) { if(!atomic_load(&captureBusy)) atomic_store(&captureRequest,1); }
int native_scene_take_capture(void) { return atomic_exchange(&captureRequest,0); }
int native_scene_capture_busy(void) { return atomic_load(&captureBusy); }
void native_scene_guest_frame(void) {
    static unsigned epoch; static uint32_t previous; static int armed;
    photo_input(PH_HELLO,0,0);
    PadState pad; gamepad_read(&pad);
    unsigned next=atomic_load(&inputEpoch);
    if(epoch!=next) { epoch=next; armed=0; previous=pad.buttons; photo_input(PH_MOVE,0,0); photo_input(PH_TURN,0,0); }
    if(!native_scene_active() || !atomic_load(&focused)) { clearCamera(); armed=0; previous=pad.buttons; return; }
    if(!armed && padAtRest(&pad)) armed=1;
    if(!pad.connected) armed=0;
    if(!pad.connected || !armed) { photo_input(PH_HOLD,atomic_load(&keyboardHold),0); photo_input(PH_MOVE,0,0); photo_input(PH_TURN,0,0); previous=pad.buttons; return; }
    uint32_t pressed=pad.buttons & ~previous; previous=pad.buttons;
    if(pressed&(1u<<PAD_A)) requestCapture();
    if(pressed&((1u<<PAD_B)|(1u<<PAD_START))) { clearCamera(); photo_input(PH_OPEN,0,0); return; }
    if(pressed&(1u<<PAD_X)) photo_input(PH_MODE,2,0);
    if(pressed&(1u<<PAD_Y)) photo_input(PH_RESET,0,0);
    int hold=atomic_load(&keyboardHold);
    if(pad.buttons&(1u<<PAD_LB)) hold|=32;
    if(pad.buttons&(1u<<PAD_RB)) hold|=16;
    if(pad.buttons&(1u<<PAD_LS)) hold|=65536;
    if(pad.buttons&(1u<<PAD_DUP)) hold|=4096;
    if(pad.buttons&(1u<<PAD_DDOWN)) hold|=8192;
    if(pad.buttons&(1u<<PAD_DLEFT)) hold|=16384;
    if(pad.buttons&(1u<<PAD_DRIGHT)) hold|=32768;
    photo_input(PH_HOLD,hold,0);
    photo_input(PH_MOVE,pack(pad.axis[PAD_AXIS_LX],-pad.axis[PAD_AXIS_LY]),pack(0,pad.axis[PAD_AXIS_RT]-pad.axis[PAD_AXIS_LT]));
    photo_input(PH_TURN,pack(pad.axis[PAD_AXIS_RX],pad.axis[PAD_AXIS_RY]),0);
}
static int holdBit(unsigned key) {
    switch(key) {
    case 13:return 1; case 1:return 2; case 0:return 4; case 2:return 8; case 14:return 16; case 12:return 32;
    case 123:return 64; case 124:return 128; case 126:return 256; case 125:return 512;
    case 33:return 4096; case 30:return 8192; case 6:return 16384; case 8:return 32768;
    default:return 0;
    }
}
int native_scene_handle_event(NSEvent *event) {
    if(event.window && gameWindow && event.window!=gameWindow) return 0;
    NSEventType type=event.type;
    if(type==NSEventTypeKeyDown || type==NSEventTypeKeyUp) {
        unsigned key=event.keyCode; int down=type==NSEventTypeKeyDown;
        if(key<128 && swallowed[key] && !down) {
            swallowed[key]=0; atomic_fetch_and(&keyboardHold,~holdBit(key)); return 1;
        }
        if(event.modifierFlags&NSEventModifierFlagCommand) return 0;
        if(key==111) {
            if(down && !event.isARepeat) {
                if(native_scene_active()) requestCapture();
                else { NativeSceneSnapshot s; native_scene_snapshot(&s); if(s.photo&1) photo_input(PH_OPEN,1,0); else requestCapture(); }
            }
            if(key<128) swallowed[key]=(unsigned char)down; return 1;
        }
        if(!native_scene_active()) { if(down && key<128) swallowed[key]=0; return 0; }
        if(key<128) swallowed[key]=(unsigned char)down;
        if(down && !event.isARepeat) switch(key) {
        case 53:clearCamera(); photo_input(PH_OPEN,0,0); break;
        case 48:photo_input(PH_MODE,2,0); break;
        case 15:photo_input(PH_RESET,0,0); break;
        case 49:requestCapture(); break;
        default:break;
        }
        int bit=holdBit(key);
        if(down) atomic_fetch_or(&keyboardHold,bit); else atomic_fetch_and(&keyboardHold,~bit);
        return 1;
    }
    if(!native_scene_active()) return 0;
    if(type==NSEventTypeFlagsChanged) {
        if(event.modifierFlags&NSEventModifierFlagShift) atomic_fetch_or(&keyboardHold,65536);
        else atomic_fetch_and(&keyboardHold,~65536);
        return 1;
    }
    BOOL inside=!gameWindow || (event.window==gameWindow && NSPointInRect(event.locationInWindow,gameWindow.contentView.frame));
    if(!inside) return 0;
    if(type==NSEventTypeLeftMouseDragged || type==NSEventTypeRightMouseDragged || type==NSEventTypeOtherMouseDragged) {
        CGFloat height=gameWindow ? MAX(1,gameWindow.contentView.bounds.size.height) : 720;
        photo_input(type==NSEventTypeLeftMouseDragged ? PH_DRAG : PH_PAN,(int)(event.deltaX*10000/height),(int)(event.deltaY*10000/height)); return 1;
    }
    if(type==NSEventTypeScrollWheel) { photo_input(PH_DOLLY,(int)(event.scrollingDeltaY*200),0); return 1; }
    return type==NSEventTypeMouseMoved || type==NSEventTypeLeftMouseDown || type==NSEventTypeLeftMouseUp || type==NSEventTypeRightMouseDown || type==NSEventTypeRightMouseUp || type==NSEventTypeOtherMouseDown || type==NSEventTypeOtherMouseUp;
}
static void notice(NSString *message) { pthread_mutex_lock(&noticeLock); captureNotice=message; pthread_mutex_unlock(&noticeLock); }
int native_scene_save_bgra(const void *pixels,size_t width,size_t height,size_t stride,char *path,size_t capacity) { @autoreleasepool {
    if(path && capacity) path[0]=0;
    if(!pixels || !width || !height || width>16384 || height>16384 || stride<width*4 || stride>SIZE_MAX/height) return 0;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate((void *)pixels,width,height,8,stride,space,kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space); if(!context) return 0;
    CGImageRef image=CGBitmapContextCreateImage(context); CGContextRelease(context); if(!image) return 0;
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.png"),1,NULL);
    BOOL encoded=NO;
    if(destination) { CGImageDestinationAddImage(destination,image,NULL); encoded=CGImageDestinationFinalize(destination); CFRelease(destination); }
    CGImageRelease(image); if(!encoded) return 0;
    const char *env=getenv("NFSU2_APPSUPPORT");
    NSString *base=env && *env ? [NSString stringWithUTF8String:env] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/NFSU2"];
    if(!base.isAbsolutePath || ![NSFileManager.defaultManager createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:NULL]) return 0;
    int parent=open(base.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC); if(parent<0) return 0;
    if(mkdirat(parent,"Screenshots",0700) && errno!=EEXIST) { close(parent); return 0; }
    int folder=openat(parent,"Screenshots",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC); close(parent); if(folder<0) return 0;
    NSString *name=[NSString stringWithFormat:@"NFSU2-%@.png",NSUUID.UUID.UUIDString];
    int fd=openat(folder,name.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0) { close(folder); return 0; }
    const uint8_t *bytes=data.bytes; size_t remaining=data.length; BOOL success=YES;
    while(remaining) {
        ssize_t written=write(fd,bytes,remaining);
        if(written<0 && errno==EINTR) continue;
        if(written<=0) { success=NO; break; }
        remaining-=(size_t)written; bytes+=written;
    }
    if(close(fd)) success=NO;
    if(!success) unlinkat(folder,name.fileSystemRepresentation,0);
    close(folder);
    if(success && path && capacity) snprintf(path,capacity,"%s",[[base stringByAppendingPathComponent:[@"Screenshots" stringByAppendingPathComponent:name]] fileSystemRepresentation]);
    return success;
} }
int native_scene_encode_capture(id<MTLCommandBuffer> command,id<MTLTexture> source) {
    if(!command || !source || (source.pixelFormat!=MTLPixelFormatBGRA8Unorm && source.pixelFormat!=MTLPixelFormatBGRA8Unorm_sRGB)) return 0;
    int expected=0; if(!atomic_compare_exchange_strong(&captureBusy,&expected,1)) return 0;
    MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:source.pixelFormat width:source.width height:source.height mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared; descriptor.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> copy=[source.device newTextureWithDescriptor:descriptor];
    if(!copy) { atomic_store(&captureBusy,0); notice(@"Photo could not be captured. Try again."); return 0; }
    id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    if(!blit) { atomic_store(&captureBusy,0); return 0; }
    [blit copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(source.width,source.height,1) toTexture:copy destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding]; notice(@"Saving photo...");
    [command addCompletedHandler:^(id<MTLCommandBuffer> finished) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ @autoreleasepool {
            BOOL saved=NO;
            if(finished.status==MTLCommandBufferStatusCompleted) {
                size_t stride=copy.width*4,bytes=stride*copy.height; void *pixels=malloc(bytes);
                if(pixels) {
                    [copy getBytes:pixels bytesPerRow:stride fromRegion:MTLRegionMake2D(0,0,copy.width,copy.height) mipmapLevel:0];
                    saved=native_scene_save_bgra(pixels,copy.width,copy.height,stride,NULL,0); free(pixels);
                }
            }
            notice(saved ? @"Photo saved to Screenshots." : @"Photo could not be saved. Check the Screenshots folder.");
            fprintf(stderr,"[photo] screenshot %s\n",saved ? "saved" : "failed");
            atomic_store(&captureBusy,0);
        } });
    }]; return 1;
}

@interface NativeSceneView : NSView
@property NSString *text;
@property double progress;
@end
@implementation NativeSceneView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    if(!self.text.length) return;
    [[NSColor colorWithWhite:0.04 alpha:0.8] setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10] fill];
    [self.text drawInRect:NSInsetRect(self.bounds,14,10) withAttributes:@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium],NSForegroundColorAttributeName:NSColor.whiteColor}];
    if(self.progress>=0) {
        NSRect bar=NSMakeRect(14,6,MAX(0,(self.bounds.size.width-28)*MIN(1,self.progress)),3);
        [[NSColor colorWithSRGBRed:0.3 green:0.85 blue:1 alpha:1] setFill]; NSRectFill(bar);
    }
}
@end
@interface NativeScene : NSObject <NSMenuItemValidation>
@property NativeSceneView *photoView;
@property NativeSceneView *driftView;
@end
static NativeScene *ui;
@implementation NativeScene
- (void)open:(id)sender { (void)sender; NativeSceneSnapshot s; native_scene_snapshot(&s); if(s.photo&1) photo_input(PH_OPEN,1,0); }
- (void)capture:(id)sender { (void)sender; requestCapture(); }
- (void)mode:(id)sender { (void)sender; photo_input(PH_MODE,2,0); }
- (void)reset:(id)sender { (void)sender; photo_input(PH_RESET,0,0); }
- (void)exit:(id)sender { (void)sender; clearCamera(); photo_input(PH_OPEN,0,0); }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    return item.action==@selector(capture:) || (item.action==@selector(open:) ? (s.photo&1)!=0 : native_scene_active());
}
- (void)focusLost:(NSNotification *)notification { (void)notification; native_scene_focus(0); }
- (void)focusGained:(NSNotification *)notification { (void)notification; native_scene_focus(gameWindow.isKeyWindow && NSApp.active); }
@end
void native_scene_attach(NSWindow *window,NSMenu *menu) {
    NSCAssert(NSThread.isMainThread,@"Native scene attach on main thread");
    if(ui) return;
    gameWindow=window; ui=[NativeScene new];
    ui.photoView=[[NativeSceneView alloc] initWithFrame:NSZeroRect]; ui.driftView=[[NativeSceneView alloc] initWithFrame:NSZeroRect];
    ui.photoView.progress=ui.driftView.progress=-1;
    [window.contentView addSubview:ui.photoView]; [window.contentView addSubview:ui.driftView];
    NSMenuItem *entry=[[NSMenuItem alloc] initWithTitle:@"Photo Mode" action:nil keyEquivalent:@""];
    NSMenu *photoMenu=[[NSMenu alloc] initWithTitle:@"Photo Mode"];
    NSArray *titles=@[@"Enter Photo Mode",@"Capture Photo (F12)",@"Switch Orbit / Free Camera",@"Reset Camera",@"Exit Photo Mode"];
    SEL actions[]={@selector(open:),@selector(capture:),@selector(mode:),@selector(reset:),@selector(exit:)};
    for(int i=0;i<5;i++) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:titles[i] action:actions[i] keyEquivalent:i==0 ? @"p" : @""];
        item.target=ui; if(i==0) item.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
        [photoMenu addItem:item];
    }
    entry.submenu=photoMenu; [menu addItem:entry];
    NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
    [nc addObserver:ui selector:@selector(focusLost:) name:NSWindowDidResignKeyNotification object:window];
    [nc addObserver:ui selector:@selector(focusLost:) name:NSApplicationDidResignActiveNotification object:nil];
    [nc addObserver:ui selector:@selector(focusGained:) name:NSWindowDidBecomeKeyNotification object:window];
    [nc addObserver:ui selector:@selector(focusGained:) name:NSApplicationDidBecomeActiveNotification object:nil];
    photo_input(PH_HELLO,0,0);
}
void native_scene_pump(void) {
    static int wasActive;
    int on=native_scene_active();
    if(on!=wasActive) {
        wasActive=on; clearCamera(); kbdmac_release_all("photo transition"); metal_release_input();
    }
    if(!ui) return;
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    NSRect bounds=gameWindow.contentView.bounds;
    CGFloat width=MAX(0,MIN(650,bounds.size.width-32));
    ui.photoView.frame=NSMakeRect(16,16,width,142);
    ui.driftView.frame=NSMakeRect(MAX(16,(bounds.size.width-350)/2),MAX(16,bounds.size.height-126),MIN(350,bounds.size.width-32),110);
    ui.photoView.hidden=!on || !gameWindow.isVisible;
    ui.driftView.hidden=!(s.drift&2) || on || !gameWindow.isVisible;
    if(on) {
        pthread_mutex_lock(&noticeLock); NSString *message=captureNotice; pthread_mutex_unlock(&noticeLock);
        ui.photoView.text=[NSString stringWithFormat:@"PHOTO - %@ camera     FOV %.1f     Roll %.1f\nWASD move | Q/E height | arrows turn | drag orbit / right drag pan\nScroll distance | [ / ] FOV | Z/C roll | Shift fast\nTab camera | R reset | F12 / Space capture | Esc exit\nPad: sticks move / turn | LB/RB height | triggers distance\nA capture | B exit | X camera | Y reset | D-pad FOV / roll\n%@",(s.photo&4) ? @"Free" : @"Orbit",s.fov,s.roll,message ?: @""];
        ui.photoView.needsDisplay=YES;
    }
    if(!ui.driftView.hidden) {
        NSString *result=@"";
        if(s.feedback_until>now()) result=s.feedback==4 ? @"Drift lost!" : [NSString stringWithFormat:@"Banked +%.0f",s.banked];
        NSString *next=s.multiplier>=5 ? @"Maximum multiplier" : [NSString stringWithFormat:@"Next x%d: %.0f points",s.multiplier+1,MAX(0,s.gain)];
        ui.driftView.text=[NSString stringWithFormat:@"DRIFT  %.0f points   x%d\n%@\nTotal %.0f   Best %.0f\n%@",s.pending,MAX(1,s.multiplier),next,s.total,s.best,result];
        ui.driftView.progress=s.multiplier>=5 ? 1 : s.gain>0 ? MIN(1,s.pending/s.gain) : 0;
        ui.driftView.needsDisplay=YES;
    }
}
