#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include <assert.h>
#include <pthread.h>
#include <math.h>
#include "native_scene.h"
#include "gamepad.h"
static int commands[12], args[12], args2[12], releases;
static PadState pad;
void photo_input(int c,int a,int b) { assert(c>=0 && c<12); commands[c]++; args[c]=a; args2[c]=b; }
void kbdmac_release_all(const char *why) { (void)why; releases++; }
void metal_release_input(void) { releases++; }
int gamepad_read(PadState *out) { *out=pad; return out->connected; }
static void photo(int flags) { int slot=host_status_slot("photo"); double v=flags; host_status_set_n(&slot,&v,1); }
static NSEvent *key(unsigned code,BOOL down,NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
}
static void *produce(void *unused) {
    (void)unused;
    int slots[]={host_status_slot("drift_total"),host_status_slot("drift_best")};
    for(int i=1;i<3000;i++) { double v[]={i,i}; host_status_set_n(slots,v,2); }
    return NULL;
}
int main(int argc,char **argv) { @autoreleasepool {
    /* Catch lost donor status, invalid writes and split snapshots. */
    assert(host_status_slot("photo")>=0); assert(host_status_slot("unknown")==-1);
    int slots[]={host_status_slot("photo"),host_status_slot("photo_fov"),host_status_slot("photo_roll"),host_status_slot("photo_n")};
    double values[]={1,71.5,0,1}; host_status_set_n(slots,values,4);
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    assert(s.photo==1 && s.fov==71.5 && s.opens==1 && !native_scene_active());
    double bad[]={2,NAN,0,2}; host_status_set_n(slots,bad,4); native_scene_snapshot(&s); assert(s.photo==1);
    int invalid[]={slots[0],99}; double v[]={2,0}; host_status_set_n(invalid,v,2); native_scene_snapshot(&s); assert(s.photo==1);
    pthread_t t; assert(!pthread_create(&t,NULL,produce,NULL));
    for(int i=0;i<3000;i++) { native_scene_snapshot(&s); assert(s.total==s.best); }
    pthread_join(t,NULL);
    /* Unsupported driving/menu states capture without requesting a world freeze. */
    photo(0); int opens=commands[1];
    assert(native_scene_handle_event(key(111,YES,0))); assert(commands[1]==opens && native_scene_take_capture());
    photo(1);
    /* F12 requests the donor camera, then captures; swallowed keys release after exit. */
    assert(native_scene_handle_event(key(111,YES,0))); assert(args[1]==1);
    photo(2); native_scene_pump(); assert(native_scene_active() && releases>=2);
    assert(native_scene_handle_event(key(13,YES,0))); native_scene_guest_frame(); assert(args[2]&1);
    assert(native_scene_handle_event(key(48,YES,0))); assert(args[10]==2);
    assert(native_scene_handle_event(key(15,YES,0))); assert(commands[11]);
    assert(native_scene_handle_event(key(111,YES,0))); assert(native_scene_take_capture()); assert(!native_scene_take_capture());
    assert(!native_scene_handle_event(key(12,YES,NSEventModifierFlagCommand)));
    assert(native_scene_handle_event(key(53,YES,0))); assert(args[1]==0);
    photo(1); native_scene_pump(); native_scene_guest_frame(); assert(args[2]==0 && args[3]==0 && args[4]==0);
    assert(native_scene_handle_event(key(13,NO,0))); assert(!native_scene_handle_event(key(13,YES,0)));
    /* A held controller cannot resume accelerating when the camera exits. */
    pad.connected=1; pad.axis[PAD_AXIS_RT]=1; pad.buttons=1u<<PAD_A;
    photo(2); native_scene_guest_frame(); PadState game=pad; native_scene_filter_pad(&game); assert(!game.buttons && !game.axis[PAD_AXIS_RT]);
    photo(1); native_scene_guest_frame(); game=pad; native_scene_filter_pad(&game); assert(!game.buttons && !game.axis[PAD_AXIS_RT]);
    memset(&pad,0,sizeof pad); pad.connected=1; game=pad; native_scene_filter_pad(&game);
    pad.axis[PAD_AXIS_RT]=1; game=pad; native_scene_filter_pad(&game); assert(game.axis[PAD_AXIS_RT]==1);
    /* Disconnect/focus loss clears continuous camera movement and re-arms at rest. */
    photo(2); memset(&pad,0,sizeof pad); pad.connected=1; native_scene_guest_frame();
    pad.axis[PAD_AXIS_LX]=0.5; native_scene_guest_frame(); assert(args[3]!=0);
    pad.connected=0; native_scene_guest_frame(); assert(args[3]==0 && args[4]==0);
    pad.connected=1; native_scene_guest_frame(); assert(args[3]==0);
    pad.axis[PAD_AXIS_LX]=0; native_scene_guest_frame(); pad.axis[PAD_AXIS_LX]=0.5; native_scene_guest_frame(); assert(args[3]!=0);
    native_scene_focus(0); native_scene_guest_frame(); assert(!args[2] && !args[3] && !args[4]); native_scene_focus(1);
    /* Missing key-up while unfocused must not swallow a new driving key release. */
    assert(native_scene_handle_event(key(1,YES,0))); native_scene_focus(0); photo(1); native_scene_pump(); native_scene_focus(1);
    assert(!native_scene_handle_event(key(1,YES,0))); assert(!native_scene_handle_event(key(1,NO,0)));
    /* Bank and collision feedback survive intervening guest frames. */
    int ds[]={host_status_slot("drift"),host_status_slot("drift_total"),host_status_slot("drift_best"),host_status_slot("drift_st"),host_status_slot("drift_pend"),host_status_slot("drift_gain"),host_status_slot("drift_x")};
    double dv[]={3,4000,3000,3,0,100,2}; host_status_set_n(ds,dv,7); native_scene_snapshot(&s); assert(s.feedback==3 && s.banked>0 && s.multiplier==2);
    dv[3]=2; host_status_set_n(ds,dv,7); native_scene_snapshot(&s); assert(s.feedback==3);
    dv[3]=4; host_status_set_n(ds,dv,7); native_scene_snapshot(&s); assert(s.feedback==4);
    /* Encode real pixels and write unique PNGs; reject an unsafe Screenshots link. */
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    setenv("NFSU2_APPSUPPORT",root.fileSystemRepresentation,1);
    uint8_t pixels[]={0,0,255,255, 0,255,0,255, 255,0,0,255, 255,255,255,255}; char first[4096],second[4096];
    assert(native_scene_save_bgra(pixels,2,2,8,first,sizeof first));
    assert(native_scene_save_bgra(pixels,2,2,8,second,sizeof second)); assert(strcmp(first,second));
    NSBitmapImageRep *image=[NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:first]]];
    assert(image.pixelsWide==2 && image.pixelsHigh==2); NSColor *red=[[image colorAtX:0 y:0] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace]; assert(red.redComponent>0.9 && red.blueComponent<0.1);
    assert(!native_scene_save_bgra(pixels,0,2,8,second,sizeof second));
    NSString *shots=[root stringByAppendingPathComponent:@"Screenshots"];
    assert([NSFileManager.defaultManager removeItemAtPath:shots error:NULL]);
    assert(!symlink("/tmp",shots.fileSystemRepresentation)); assert(!native_scene_save_bgra(pixels,2,2,8,second,sizeof second));
    assert([NSFileManager.defaultManager removeItemAtPath:shots error:NULL]);
    /* GPU copy finishes before background PNG encoding; no main/guest lock wait. */
    id<MTLDevice> device=MTLCreateSystemDefaultDevice(); assert(device);
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:2 height:2 mipmapped:NO]; td.storageMode=MTLStorageModeShared;
    id<MTLTexture> texture=[device newTextureWithDescriptor:td]; [texture replaceRegion:MTLRegionMake2D(0,0,2,2) mipmapLevel:0 withBytes:pixels bytesPerRow:8];
    id<MTLCommandQueue> queue=[device newCommandQueue]; id<MTLCommandBuffer> cb=[queue commandBuffer];
    assert(native_scene_encode_capture(cb,texture)); [cb commit];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while(native_scene_capture_busy() && deadline.timeIntervalSinceNow>0) [NSThread sleepForTimeInterval:0.01];
    assert(!native_scene_capture_busy()); NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:shots error:NULL]; assert(files.count==1);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:NULL]);
    if(argc==3 && !strcmp(argv[1],"--snapshot")) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window orderBack:nil];
        NSMenu *menu=[NSMenu new]; native_scene_attach(window,menu); assert(menu.numberOfItems==1);
        photo(2); native_scene_pump(); assert(window.contentView.subviews.count==2);
        NSView *photoView=window.contentView.subviews[0],*driftView=window.contentView.subviews[1];
        assert(!photoView.hidden && driftView.hidden && ![photoView hitTest:NSMakePoint(30,30)]);
        photo(1); native_scene_pump(); assert(photoView.hidden && !driftView.hidden);
        dv[0]=1; host_status_set_n(ds,dv,7); native_scene_pump(); assert(driftView.hidden);
        dv[0]=3; host_status_set_n(ds,dv,7); native_scene_pump();
        [window setContentSize:NSMakeSize(640,480)]; native_scene_pump(); assert(NSMaxX(driftView.frame)<=640);
        photo(2); native_scene_pump();
        [window.contentView displayIfNeeded];
        NSBitmapImageRep *photoBitmap=[window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:photoBitmap];
        NSString *photoPath=[[NSString stringWithUTF8String:argv[2]] stringByAppendingString:@".photo.png"];
        assert([[photoBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:photoPath atomically:YES]);
        photo(1); native_scene_pump();
        [window.contentView displayIfNeeded];
        NSBitmapImageRep *bitmap=[window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:bitmap];
        assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES]);
        puts("native photo/drift overlay visibility, resize and AppKit snapshot passed");
    }
    puts("native scene status, input release, controller quarantine, drift feedback and asynchronous PNG tests passed");
} }
