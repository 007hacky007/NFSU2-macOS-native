/* native_scene_test.m -- runtime/native_scene.m without the game (tests/native_scene.sh): the status table,
 * photo mode's keys, mouse and controller, the controller kept from the game, the drift panel's feedback, PNGs
 * saved under unique names and never through a link, the GPU read back off the main thread, and with
 * --snapshot <png> the panels drawn over a window. */
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include <assert.h>
#include <pthread.h>
#include <math.h>
#include "native_scene.h"

static int commands[12], args[12], args2[12];
static unsigned char pad[272];                       /* the controller as gamepad.m fills it (DIJOYSTATE2) */
void photo_input(int c, int a, int b) { assert(c >= 0 && c < 12); commands[c]++; args[c] = a; args2[c] = b; }
void gamepad_fill(unsigned char *dst) { memcpy(dst, pad, sizeof pad); }
int photo_enabled(void) { return 1; }
int drift_enabled(void) { return 1; }

static void pad_rest(void) {
    memset(pad, 0, sizeof pad);
    uint32_t c = 0xffffffffu; for (int i = 0; i < 4; i++) memcpy(pad + 0x20 + 4 * i, &c, 4);
}
static void pad_axis(int i, float v) { int32_t a = (int32_t)lrintf(v * 10000.f); memcpy(pad + 4 * i, &a, 4); }
static void pad_button(int i, int down) { pad[0x30 + i] = down ? 0x80 : 0; }
static void photo(int flags) { int slot = host_status_slot("photo"); double v = flags; host_status_set_n(&slot, &v, 1); }
static NSEvent *key(unsigned code, BOOL down, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
}
static void *produce(void *unused) {
    (void)unused;
    int slots[] = { host_status_slot("drift_total"), host_status_slot("drift_best") };
    for (int i = 1; i < 3000; i++) { double v[] = { i, i }; host_status_set_n(slots, v, 2); }
    return NULL;
}
int main(int argc, char **argv) { @autoreleasepool {
    /* The status: named slots, invalid writes refused whole, no split snapshot under a writer thread. */
    assert(host_status_slot("photo") >= 0); assert(host_status_slot("unknown") == -1);
    int slots[] = { host_status_slot("photo"), host_status_slot("photo_fov"), host_status_slot("photo_roll"), host_status_slot("photo_n") };
    double values[] = { 1, 71.5, 0, 1 }; host_status_set_n(slots, values, 4);
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    assert(s.photo == 1 && s.fov == 71.5 && s.opens == 1 && !native_scene_active());
    double bad[] = { 2, NAN, 0, 2 }; host_status_set_n(slots, bad, 4); native_scene_snapshot(&s); assert(s.photo == 1);
    int invalid[] = { slots[0], 99 }; double v[] = { 2, 0 }; host_status_set_n(invalid, v, 2); native_scene_snapshot(&s); assert(s.photo == 1);
    pthread_t t; assert(!pthread_create(&t, NULL, produce, NULL));
    for (int i = 0; i < 3000; i++) { native_scene_snapshot(&s); assert(s.total == s.best); }
    pthread_join(t, NULL);
    /* F12 where photo mode cannot open (menus, a network race): a screenshot, no photo mode. */
    photo(0); int opens = commands[1];
    assert(native_scene_handle_event(key(111, YES, 0))); assert(commands[1] == opens && native_scene_take_capture());
    assert(native_scene_handle_event(key(111, NO, 0)));
    /* Where it can: F12 asks photo.c to open it. */
    photo(1);
    assert(native_scene_handle_event(key(111, YES, 0))); assert(args[1] == 1 && !native_scene_take_capture());
    /* On: the keys drive the camera and the game gets none of them; a key let go reaches the game too. */
    photo(2); native_scene_pump(); assert(native_scene_active());
    pad_rest();
    assert(native_scene_handle_event(key(13, YES, 0))); native_scene_guest_frame(); assert(args[2] & 1);        /* W */
    assert(!native_scene_handle_event(key(13, NO, 0))); native_scene_guest_frame(); assert(!(args[2] & 1));
    assert(native_scene_handle_event(key(33, YES, 0))); native_scene_guest_frame(); assert(args[2] & 4096);    /* [ */
    assert(!native_scene_handle_event(key(33, NO, 0)));
    assert(native_scene_handle_event(key(48, YES, 0))); assert(args[10] == 2);                                 /* Tab */
    assert(native_scene_handle_event(key(15, YES, 0))); assert(commands[11]);                                  /* R */
    assert(native_scene_handle_event(key(49, YES, 0))); assert(native_scene_take_capture());                   /* Space */
    assert(native_scene_handle_event(key(111, YES, 0))); assert(native_scene_take_capture()); assert(!native_scene_take_capture());
    assert(!native_scene_handle_event(key(12, YES, NSEventModifierFlagCommand)));                              /* the menu's */
    assert(native_scene_handle_event(key(53, YES, 0))); assert(args[1] == 0);                                  /* Esc */
    photo(1); native_scene_pump(); native_scene_guest_frame(); assert(args[2] == 0 && args[3] == 0 && args[4] == 0);
    assert(!native_scene_handle_event(key(13, YES, 0))); assert(!native_scene_handle_event(key(13, NO, 0)));  /* the game's again */
    /* The controller as DirectInput reads it: sticks, triggers (one axis), buttons, the d-pad. */
    NativePad p;
    pad_rest(); pad_axis(0, 0.5f); pad_axis(1, -1); pad_axis(2, -0.75f); pad_button(5, 1); { uint32_t pov = 9000; memcpy(pad + 0x20, &pov, 4); }
    native_scene_pad_parse(pad, &p);
    assert(fabsf(p.lx - 0.5f) < 1e-4f && p.ly == -1 && fabsf(p.rt - 0.75f) < 1e-4f && p.lt == 0);
    assert(p.buttons == ((1u << NPAD_RB) | (1u << NPAD_DRIGHT)));
    /* A controller held as photo mode opens does nothing until let go, and the game gets nothing of it, nor after
     * photo mode until it is at rest (a trigger held for the camera is no throttle). */
    pad_rest(); pad_axis(2, -1); pad_button(0, 1);
    photo(2); native_scene_guest_frame(); assert(args[3] == 0);
    unsigned char game[272]; memcpy(game, pad, sizeof game); native_scene_filter_pad(game);
    native_scene_pad_parse(game, &p); assert(!p.buttons && p.rt == 0);
    photo(1); native_scene_guest_frame(); memcpy(game, pad, sizeof game); native_scene_filter_pad(game);
    native_scene_pad_parse(game, &p); assert(!p.buttons && p.rt == 0);
    pad_rest(); memcpy(game, pad, sizeof game); native_scene_filter_pad(game);
    pad_axis(2, -1); memcpy(game, pad, sizeof game); native_scene_filter_pad(game); native_scene_pad_parse(game, &p); assert(p.rt == 1);
    /* On, a pad at rest arms it: the left stick moves the camera, B closes. */
    photo(2); pad_rest(); native_scene_guest_frame();
    pad_axis(0, 0.5f); native_scene_guest_frame(); assert(args[3] != 0);
    pad_rest(); pad_button(5, 1); native_scene_guest_frame(); assert(args[2] & 16);                          /* RB: up */
    pad_rest(); { uint32_t pov = 0; memcpy(pad + 0x20, &pov, 4); } native_scene_guest_frame(); assert(args[2] & 4096);  /* d-pad up: FOV */
    pad_rest(); pad_button(0, 1); native_scene_guest_frame(); assert(native_scene_take_capture());              /* A */
    pad_rest(); native_scene_guest_frame(); pad_button(1, 1); native_scene_guest_frame(); assert(args[1] == 0); /* B */
    /* Focus lost: no camera movement, the controller kept from the game. */
    pad_rest(); native_scene_guest_frame(); pad_axis(0, 0.5f); native_scene_guest_frame(); assert(args[3] != 0);
    native_scene_focus(0); native_scene_guest_frame(); assert(!args[2] && !args[3] && !args[4]); native_scene_focus(1);
    photo(1); native_scene_pump();
    /* The drift panel's feedback: a bank and a drift lost to a wall outlive the frames after them. */
    int ds[] = { host_status_slot("drift"), host_status_slot("drift_total"), host_status_slot("drift_best"), host_status_slot("drift_st"),
                 host_status_slot("drift_pend"), host_status_slot("drift_gain"), host_status_slot("drift_x") };
    double dv[] = { 3, 4000, 3000, 3, 0, 100, 2 }; host_status_set_n(ds, dv, 7); native_scene_snapshot(&s); assert(s.feedback == 3 && s.banked > 0 && s.multiplier == 2);
    dv[3] = 2; host_status_set_n(ds, dv, 7); native_scene_snapshot(&s); assert(s.feedback == 3);
    dv[3] = 4; host_status_set_n(ds, dv, 7); native_scene_snapshot(&s); assert(s.feedback == 4);
    /* Real pixels as unique PNGs; never through a linked Screenshots folder. */
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    setenv("NFSU2_APPSUPPORT", root.fileSystemRepresentation, 1);
    uint8_t pixels[] = { 0,0,255,255, 0,255,0,255, 255,0,0,255, 255,255,255,255 }; char first[4096], second[4096];
    assert(native_scene_save_bgra(pixels, 2, 2, 8, first, sizeof first));
    assert(native_scene_save_bgra(pixels, 2, 2, 8, second, sizeof second)); assert(strcmp(first, second));
    NSBitmapImageRep *image = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:first]]];
    assert(image.pixelsWide == 2 && image.pixelsHigh == 2);
    NSColor *red = [[image colorAtX:0 y:0] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace]; assert(red.redComponent > 0.9 && red.blueComponent < 0.1);
    assert(!native_scene_save_bgra(pixels, 0, 2, 8, second, sizeof second));
    NSString *shots = [root stringByAppendingPathComponent:@"Screenshots"];
    assert([NSFileManager.defaultManager removeItemAtPath:shots error:NULL]);
    assert(!symlink("/tmp", shots.fileSystemRepresentation)); assert(!native_scene_save_bgra(pixels, 2, 2, 8, second, sizeof second));
    assert([NSFileManager.defaultManager removeItemAtPath:shots error:NULL]);
    /* The GPU copy is done before the PNG is written on a background queue; nothing waits on the main thread. */
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); assert(device);
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:2 height:2 mipmapped:NO];
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device newTextureWithDescriptor:td];
    [texture replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:pixels bytesPerRow:8];
    id<MTLCommandQueue> queue = [device newCommandQueue]; id<MTLCommandBuffer> cb = [queue commandBuffer];
    assert(native_scene_encode_capture(cb, texture)); assert(!native_scene_encode_capture([queue commandBuffer], texture));  /* one at a time */
    [cb commit];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (native_scene_capture_busy() && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.01];
    assert(!native_scene_capture_busy());
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:shots error:NULL]; assert(files.count == 1);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:NULL]);
    if (argc == 3 && !strcmp(argv[1], "--snapshot")) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.contentView.wantsLayer = YES; window.contentView.layer.backgroundColor = NSColor.darkGrayColor.CGColor;
        [window orderBack:nil];
        NSMenu *menu = [NSMenu new]; [menu addItem:NSMenuItem.separatorItem];
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"]];
        native_scene_add_menu(menu); assert(menu.numberOfItems == 3 && [menu itemAtIndex:0].submenu.numberOfItems == 5);  /* before Quit */
        native_scene_attach(window); assert(window.contentView.subviews.count == 2);
        photo(2); native_scene_pump();
        NSView *photoView = window.contentView.subviews[0], *driftView = window.contentView.subviews[1];
        assert(!photoView.hidden && driftView.hidden && ![photoView hitTest:NSMakePoint(30, 30)]);
        photo(1); native_scene_pump(); assert(photoView.hidden && !driftView.hidden);
        dv[0] = 1; host_status_set_n(ds, dv, 7); native_scene_pump(); assert(driftView.hidden);       /* chosen, not on now */
        double live[] = { 3, 4081, 3081, 0, 140, 200, 1 }; host_status_set_n(ds, live, 7); native_scene_pump();
        [window setContentSize:NSMakeSize(640, 480)]; native_scene_pump(); assert(NSMaxX(driftView.frame) <= 640);
        photo(2); native_scene_pump();
        [window.contentView displayIfNeeded];
        NSBitmapImageRep *photoBitmap = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:photoBitmap];
        NSString *photoPath = [[NSString stringWithUTF8String:argv[2]] stringByAppendingString:@".photo.png"];
        assert([[photoBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:photoPath atomically:YES]);
        photo(1); native_scene_pump();
        [window.contentView displayIfNeeded];
        NSBitmapImageRep *bitmap = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:bitmap];
        assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES]);
        puts("native_scene: the app menu, the panels' visibility, a resize and an AppKit snapshot passed");
    }
    puts("native_scene: status, photo keys and controller, controller kept from the game, drift feedback and asynchronous PNGs passed");
} }
