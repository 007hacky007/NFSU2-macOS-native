/* native_scene.m -- the Mac side of photo mode (photo.c) and drift mode (drift.c).
 *
 * Photo mode (NFSU2_PHOTO=1).  F12 opens it where photo.c says it can (the
 * status bit "photo" & 1) and saves a screenshot everywhere else; in photo mode
 * F12 or Space saves one.  The app menu's Photo Mode has the same (Cmd+Shift+P
 * opens it).  While it is on, the keys, the mouse and the controller drive the
 * camera and the game gets none of them (a key or button let go still reaches
 * it, so nothing held before stays held):
 *   WASD move, E / Q up / down, arrows turn, Shift faster, [ / ] field of view,
 *   Z / C tilt, Tab orbit / free, R reset, Esc closes; the mouse: drag turns,
 *   right drag pans, the wheel moves closer.  Controller: left stick moves,
 *   right stick turns, RB / LB up / down, the triggers closer / further, LS
 *   faster, d-pad up / down field of view, left / right tilt, A saves, B or
 *   Start closes, X orbit / free, Y reset.
 * The keys are read by their place on the keyboard (macOS key codes), as the
 * game's own are (metal.m mac_to_dik).  The controller is the game's own
 * DirectInput pad (gamepad.m), read here on the guest thread; after photo mode,
 * a focus change or a pad that was held, the game gets it again only once it is
 * at rest (native_scene_filter_pad), so a trigger held for the camera does not
 * become the throttle.
 *
 * Screenshots: the frame the presenter is about to show (metal.m, before the
 * frame-rate counter is drawn) is copied on the GPU, read back once the command
 * buffer is done and written as a PNG on a background queue: the game never
 * waits for it, in menus or a race over the network too.  Each gets a new name
 * (NFSU2-<UUID>.png, never an existing file), in
 * ~/Library/Application Support/NFSU2/Screenshots (NFSU2_APPSUPPORT=<dir> puts
 * it in <dir>/Screenshots; tests), a folder that is never a link.  The
 * launcher's Screenshots... window shows them (launcher/PhotoGallery.swift).
 *
 * The panels: AppKit views over the game's Metal view, so they are in no
 * screenshot and no DUMPFRAME dump.  The photo help panel shows while photo mode
 * is on; the drift panel (NFSU2_DRIFT=1) while drift mode's handling is on and
 * photo mode is not: the drift's points and multiplier, the points to the next
 * multiplier with a bar, the total and the best, and for two seconds after a
 * drift "Banked +N" or "Drift lost!".
 *
 * The status it reads is what th0mk's nfsu2-web runtime/photo.c and drift.c (MIT)
 * publish for that project's web page; photo.c and drift.c here publish it the same way. */
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#include <pthread.h>
#include <stdatomic.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include "native_scene.h"
#include "gamepad.h"

void photo_input(int command, int a, int b);       /* photo.c */
void gamepad_fill(unsigned char *dst);             /* gamepad.m: DIJOYSTATE2 */
enum { PH_HELLO, PH_OPEN, PH_HOLD, PH_MOVE, PH_TURN, PH_DRAG, PH_PAN, PH_DOLLY, PH_FOV, PH_ROLL, PH_MODE, PH_RESET };
enum { HB_FAST = 65536 };

#define NSTATUS 12
static pthread_mutex_t statusLock = PTHREAD_MUTEX_INITIALIZER;
static const char *const names[NSTATUS] = { "photo", "photo_fov", "photo_roll", "photo_n", "drift", "drift_key",
    "drift_x", "drift_gain", "drift_total", "drift_best", "drift_st", "drift_pend" };
static double status[NSTATUS];
static int feedback;
static double banked, feedbackUntil;
static atomic_int active, focused = 1, captureRequest, captureBusy, keyboardHold;
static atomic_uint inputEpoch;
static NSString *captureNotice;
static pthread_mutex_t noticeLock = PTHREAD_MUTEX_INITIALIZER;
static NSWindow *gameWindow;
static double now(void) { return NSProcessInfo.processInfo.systemUptime; }

int host_status_slot(const char *name) {
    if (name) for (int i = 0; i < NSTATUS; i++) if (!strcmp(name, names[i])) return i;
    return -1;
}
void host_status_set_n(const int *slots, const double *values, int count) {
    if (!slots || !values || count < 1 || count > NSTATUS) return;
    for (int i = 0; i < count; i++) if (slots[i] < 0 || slots[i] >= NSTATUS || !isfinite(values[i]) || fabs(values[i]) > 1e12) return;
    pthread_mutex_lock(&statusLock);
    double oldTotal = status[8], oldState = status[10];
    for (int i = 0; i < count; i++) status[slots[i]] = values[i];
    if (status[8] > oldTotal) { banked = status[8] - oldTotal; feedback = 3; feedbackUntil = now() + 2.0; }
    if (status[10] != oldState && (status[10] == 3 || status[10] == 4)) { feedback = (int)status[10]; feedbackUntil = now() + 2.0; }
    int on = ((int)status[0] & 2) != 0;
    if (atomic_exchange(&active, on) != on) atomic_fetch_add(&inputEpoch, 1);
    pthread_mutex_unlock(&statusLock);
}
void native_scene_snapshot(NativeSceneSnapshot *out) {
    if (!out) return;
    pthread_mutex_lock(&statusLock);
    *out = (NativeSceneSnapshot){ .photo = (int)status[0], .fov = status[1], .roll = status[2], .opens = (int)status[3],
        .drift = (int)status[4], .multiplier = (int)status[6], .gain = status[7], .total = status[8], .best = status[9],
        .state = (int)status[10], .pending = status[11], .feedback = feedback, .banked = banked, .feedback_until = feedbackUntil };
    pthread_mutex_unlock(&statusLock);
}
int native_scene_active(void) { return atomic_load(&active); }
static void clearCamera(void) {
    atomic_store(&keyboardHold, 0); photo_input(PH_HOLD, 0, 0); photo_input(PH_MOVE, 0, 0); photo_input(PH_TURN, 0, 0);
}
void native_scene_focus(int focus) {
    if (atomic_exchange(&focused, !!focus) != !!focus) atomic_fetch_add(&inputEpoch, 1);
    if (!focus) clearCamera();
}

/* DIJOYSTATE2 (gamepad.m): lX lY lZ (LT +, RT -) lRx lRy, POV 0 at +0x20 (centidegrees, -1 centred), buttons at
 * +0x30: A B X Y LB RB Back Start LS RS */
void native_scene_pad_parse(const unsigned char *d, NativePad *p) {
    memset(p, 0, sizeof *p);
    int32_t a[5]; memcpy(a, d, sizeof a);
    p->lx = a[0] / 10000.f; p->ly = a[1] / 10000.f; p->rx = a[3] / 10000.f; p->ry = a[4] / 10000.f;
    p->lt = a[2] > 0 ? a[2] / 10000.f : 0; p->rt = a[2] < 0 ? -a[2] / 10000.f : 0;
    for (int i = 0; i < 10; i++) if (d[0x30 + i] & 0x80) p->buttons |= 1u << i;
    uint32_t pov; memcpy(&pov, d + 0x20, 4);
    if (pov < 36000u) {
        if (pov >= 31500u || pov <= 4500u) p->buttons |= 1u << NPAD_DUP;
        if (pov >= 4500u && pov <= 13500u) p->buttons |= 1u << NPAD_DRIGHT;
        if (pov >= 13500u && pov <= 22500u) p->buttons |= 1u << NPAD_DDOWN;
        if (pov >= 22500u && pov <= 31500u) p->buttons |= 1u << NPAD_DLEFT;
    }
}
static int padAtRest(const NativePad *s) {
    if (s->buttons) return 0;
    const float ax[6] = { s->lx, s->ly, s->rx, s->ry, s->lt, s->rt };
    for (int i = 0; i < 6; i++) if (fabsf(ax[i]) > 0.08f) return 0;
    return 1;
}
/* The pad the game gets: nothing while photo mode is on or the window has no focus, nor afterwards until it is at
 * rest.  native_scene_filter_raw works on a DIJOYSTATE2 (tests); the game's pad (dinput_pad.c) goes through
 * native_scene_filter_pad below. */
void native_scene_filter_raw(unsigned char *d) {
    static unsigned epoch; static int quarantine;
    if (!photo_enabled()) return;
    unsigned next = atomic_load(&inputEpoch);
    if (next != epoch) { epoch = next; quarantine = 1; }
    NativePad s; native_scene_pad_parse(d, &s);
    if (native_scene_active() || !atomic_load(&focused)) quarantine = 1;
    else if (padAtRest(&s)) quarantine = 0;
    if (quarantine) {
        memset(d, 0, 0x20); memset(d + 0x30, 0, 0x80);
        uint32_t c = 0xffffffffu; for (int i = 0; i < 4; i++) memcpy(d + 0x20 + 4 * i, &c, 4);
    }
}
static int padStateAtRest(const PadState *s) {
    if (!s->connected) return 1;
    if (s->buttons) return 0;
    for (int i = 0; i < PAD_NAXES; i++) if (fabsf(s->axis[i]) > 0.08f) return 0;
    return 1;
}
void native_scene_filter_pad(PadState *s) {            /* dinput_pad.c, before the game reads the pad */
    static unsigned epoch; static int quarantine;
    if (!photo_enabled()) return;
    unsigned next = atomic_load(&inputEpoch);
    if (next != epoch) { epoch = next; quarantine = 1; }
    if (native_scene_active() || !atomic_load(&focused)) quarantine = 1;
    else if (padStateAtRest(s)) quarantine = 0;
    if (quarantine) { s->buttons = 0; memset(s->axis, 0, sizeof s->axis); }
}
static int pack(float x, float y) {
    int16_t a = (int16_t)lrintf(fmaxf(-1, fminf(1, x)) * 32767), b = (int16_t)lrintf(fmaxf(-1, fminf(1, y)) * 32767);
    return (int)((uint16_t)a | ((uint32_t)(uint16_t)b << 16));
}
void native_scene_request_capture(void) { if (!atomic_load(&captureBusy)) atomic_store(&captureRequest, 1); }
int native_scene_take_capture(void) { return atomic_exchange(&captureRequest, 0); }
int native_scene_capture_busy(void) { return atomic_load(&captureBusy); }
void native_scene_f12(void) {
    if (native_scene_active()) { native_scene_request_capture(); return; }
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    if (s.photo & 1) photo_input(PH_OPEN, 1, 0); else native_scene_request_capture();
}

/* the controller for the camera (guest thread, every frame) */
void native_scene_guest_frame(void) {
    static unsigned epoch; static uint32_t previous; static int armed;
    photo_input(PH_HELLO, 0, 0);
    unsigned char raw[272]; gamepad_fill(raw);
    NativePad pad; native_scene_pad_parse(raw, &pad);
    unsigned next = atomic_load(&inputEpoch);
    if (epoch != next) { epoch = next; armed = 0; previous = pad.buttons; photo_input(PH_MOVE, 0, 0); photo_input(PH_TURN, 0, 0); }
    if (!native_scene_active() || !atomic_load(&focused)) { clearCamera(); armed = 0; previous = pad.buttons; return; }
    if (!armed && padAtRest(&pad)) armed = 1;          /* a pad held as photo mode opened does nothing until let go */
    if (!armed) { photo_input(PH_HOLD, atomic_load(&keyboardHold), 0); photo_input(PH_MOVE, 0, 0); photo_input(PH_TURN, 0, 0); previous = pad.buttons; return; }
    uint32_t pressed = pad.buttons & ~previous; previous = pad.buttons;
    if (pressed & (1u << NPAD_A)) native_scene_request_capture();
    if (pressed & ((1u << NPAD_B) | (1u << NPAD_START))) { clearCamera(); photo_input(PH_OPEN, 0, 0); return; }
    if (pressed & (1u << NPAD_X)) photo_input(PH_MODE, 2, 0);
    if (pressed & (1u << NPAD_Y)) photo_input(PH_RESET, 0, 0);
    int hold = atomic_load(&keyboardHold);
    if (pad.buttons & (1u << NPAD_LB)) hold |= 32;
    if (pad.buttons & (1u << NPAD_RB)) hold |= 16;
    if (pad.buttons & (1u << NPAD_LS)) hold |= HB_FAST;
    if (pad.buttons & (1u << NPAD_DUP)) hold |= 4096;
    if (pad.buttons & (1u << NPAD_DDOWN)) hold |= 8192;
    if (pad.buttons & (1u << NPAD_DLEFT)) hold |= 16384;
    if (pad.buttons & (1u << NPAD_DRIGHT)) hold |= 32768;
    photo_input(PH_HOLD, hold, 0);
    photo_input(PH_MOVE, pack(pad.lx, -pad.ly), pack(0, pad.rt - pad.lt));
    photo_input(PH_TURN, pack(pad.rx, pad.ry), 0);
}
/* photo.c's held bits of a key (macOS key code) */
static int holdBit(unsigned key) {
    switch (key) {
    case 13: return 1; case 1: return 2; case 0: return 4; case 2: return 8; case 14: return 16; case 12: return 32;   /* W S A D E Q */
    case 123: return 64; case 124: return 128; case 126: return 256; case 125: return 512;                             /* arrows */
    case 33: return 4096; case 30: return 8192; case 6: return 16384; case 8: return 32768;                             /* [ ] Z C */
    default: return 0;
    }
}
/* metal.m's event loop, before its own handling: 1 when photo mode took the event */
int native_scene_handle_event(NSEvent *event) {
    if (!photo_enabled()) return 0;
    if (event.window && gameWindow && event.window != gameWindow) return 0;
    NSEventType type = event.type;
    if (type == NSEventTypeKeyDown || type == NSEventTypeKeyUp) {
        unsigned key = event.keyCode; int down = type == NSEventTypeKeyDown;
        if (event.modifierFlags & NSEventModifierFlagCommand) return 0;   /* the app menu's */
        if (key == 111) {                                               /* F12: the game has no use for it */
            if (down && !event.isARepeat) native_scene_f12();
            return 1;
        }
        if (!native_scene_active()) return 0;
        int bit = holdBit(key);
        if (!down) { atomic_fetch_and(&keyboardHold, ~bit); return 0; }   /* let go: to the game too */
        if (!event.isARepeat) switch (key) {
        case 53: clearCamera(); photo_input(PH_OPEN, 0, 0); break;        /* Esc */
        case 48: photo_input(PH_MODE, 2, 0); break;                       /* Tab */
        case 15: photo_input(PH_RESET, 0, 0); break;                      /* R */
        case 49: native_scene_request_capture(); break;                   /* Space */
        default: break;
        }
        atomic_fetch_or(&keyboardHold, bit);
        return 1;
    }
    if (!native_scene_active()) return 0;
    if (type == NSEventTypeFlagsChanged) {                              /* Shift: faster (the game sees it too) */
        if (event.modifierFlags & NSEventModifierFlagShift) atomic_fetch_or(&keyboardHold, HB_FAST);
        else atomic_fetch_and(&keyboardHold, ~HB_FAST);
        return 0;
    }
    BOOL inside = !gameWindow || (event.window == gameWindow && NSPointInRect(event.locationInWindow, gameWindow.contentView.frame));
    if (!inside) return 0;
    if (type == NSEventTypeLeftMouseDragged || type == NSEventTypeRightMouseDragged || type == NSEventTypeOtherMouseDragged) {
        CGFloat height = gameWindow ? MAX(1, gameWindow.contentView.bounds.size.height) : 720;
        photo_input(type == NSEventTypeLeftMouseDragged ? PH_DRAG : PH_PAN, (int)(event.deltaX * 10000 / height), (int)(event.deltaY * 10000 / height));
        return 1;
    }
    if (type == NSEventTypeScrollWheel) { photo_input(PH_DOLLY, (int)(event.scrollingDeltaY * 200), 0); return 1; }
    return type == NSEventTypeMouseMoved || type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown ||
           type == NSEventTypeOtherMouseDown;                           /* a button let go: to the game too */
}

static void notice(NSString *message) { pthread_mutex_lock(&noticeLock); captureNotice = message; pthread_mutex_unlock(&noticeLock); }
/* BGRA pixels as a new PNG in the Screenshots folder; path: where (may be NULL) */
int native_scene_save_bgra(const void *pixels, size_t width, size_t height, size_t stride, char *path, size_t capacity) { @autoreleasepool {
    if (path && capacity) path[0] = 0;
    if (!pixels || !width || !height || width > 16384 || height > 16384 || stride < width * 4 || stride > SIZE_MAX / height) return 0;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate((void *)pixels, width, height, 8, stride, space, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space); if (!context) return 0;
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context); if (!image) return 0;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    BOOL encoded = NO;
    if (destination) { CGImageDestinationAddImage(destination, image, NULL); encoded = CGImageDestinationFinalize(destination); CFRelease(destination); }
    CGImageRelease(image); if (!encoded) return 0;
    const char *env = getenv("NFSU2_APPSUPPORT");
    NSString *base = env && *env ? [NSString stringWithUTF8String:env] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/NFSU2"];
    if (!base.isAbsolutePath || ![NSFileManager.defaultManager createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:NULL]) return 0;
    int parent = open(base.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); if (parent < 0) return 0;
    if (mkdirat(parent, "Screenshots", 0700) && errno != EEXIST) { close(parent); return 0; }
    int folder = openat(parent, "Screenshots", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC); close(parent); if (folder < 0) return 0;
    NSString *name = [NSString stringWithFormat:@"NFSU2-%@.png", NSUUID.UUID.UUIDString];
    int fd = openat(folder, name.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) { close(folder); return 0; }
    const uint8_t *bytes = data.bytes; size_t remaining = data.length; BOOL success = YES;
    while (remaining) {
        ssize_t written = write(fd, bytes, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { success = NO; break; }
        remaining -= (size_t)written; bytes += written;
    }
    if (close(fd)) success = NO;
    if (!success) unlinkat(folder, name.fileSystemRepresentation, 0);
    close(folder);
    if (success && path && capacity) snprintf(path, capacity, "%s", [[base stringByAppendingPathComponent:[@"Screenshots" stringByAppendingPathComponent:name]] fileSystemRepresentation]);
    return success;
} }
/* the presenter (metal.m): a copy of source in the frame's command buffer; read back and saved once it is done */
int native_scene_encode_capture(id<MTLCommandBuffer> command, id<MTLTexture> source) {
    if (!command || !source || (source.pixelFormat != MTLPixelFormatBGRA8Unorm && source.pixelFormat != MTLPixelFormatBGRA8Unorm_sRGB)) return 0;
    int expected = 0; if (!atomic_compare_exchange_strong(&captureBusy, &expected, 1)) return 0;
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:source.pixelFormat width:source.width height:source.height mipmapped:NO];
    descriptor.storageMode = MTLStorageModeShared; descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> copy = [source.device newTextureWithDescriptor:descriptor];
    if (!copy) { atomic_store(&captureBusy, 0); notice(@"The photo could not be taken. Try again."); return 0; }
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    if (!blit) { atomic_store(&captureBusy, 0); return 0; }
    [blit copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(source.width, source.height, 1)
                toTexture:copy destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding]; notice(@"Saving the photo...");
    [command addCompletedHandler:^(id<MTLCommandBuffer> finished) {
        /* user-initiated: off the game's threads, but not left to wait behind background work */
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
            BOOL saved = NO; char where[2048] = ""; double t0 = now();
            if (finished.status == MTLCommandBufferStatusCompleted) {
                size_t stride = copy.width * 4, bytes = stride * copy.height; void *pixels = malloc(bytes);
                if (pixels) {
                    [copy getBytes:pixels bytesPerRow:stride fromRegion:MTLRegionMake2D(0, 0, copy.width, copy.height) mipmapLevel:0];
                    saved = native_scene_save_bgra(pixels, copy.width, copy.height, stride, where, sizeof where); free(pixels);
                }
            }
            notice(saved ? @"Photo saved to Screenshots." : @"The photo could not be saved. Check the Screenshots folder.");
            fprintf(stderr, "[photo] screenshot %s%s%s (%lux%lu, %.0f ms)\n", saved ? "saved" : "failed", saved ? ": " : "", where,
                    (unsigned long)copy.width, (unsigned long)copy.height, (now() - t0) * 1000);
            atomic_store(&captureBusy, 0);
        } });
    }];
    return 1;
}

@interface NativeSceneView : NSView
@property NSString *text;
@property double progress;
@end
@implementation NativeSceneView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }   /* the mouse goes to the game */
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    if (!self.text.length) return;
    [[NSColor colorWithWhite:0.04 alpha:0.8] setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10] fill];
    [self.text drawInRect:NSInsetRect(self.bounds, 14, 10) withAttributes:@{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium],
                                                                             NSForegroundColorAttributeName: NSColor.whiteColor }];
    if (self.progress >= 0) {
        NSRect bar = NSMakeRect(14, 6, MAX(0, (self.bounds.size.width - 28) * MIN(1, self.progress)), 3);
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
- (void)open:(id)sender { (void)sender; NativeSceneSnapshot s; native_scene_snapshot(&s); if (s.photo & 1) photo_input(PH_OPEN, 1, 0); }
- (void)capture:(id)sender { (void)sender; native_scene_request_capture(); }
- (void)mode:(id)sender { (void)sender; photo_input(PH_MODE, 2, 0); }
- (void)reset:(id)sender { (void)sender; photo_input(PH_RESET, 0, 0); }
- (void)exit:(id)sender { (void)sender; clearCamera(); photo_input(PH_OPEN, 0, 0); }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    return item.action == @selector(capture:) || (item.action == @selector(open:) ? (s.photo & 1) != 0 : native_scene_active());
}
- (void)focusLost:(NSNotification *)notification { (void)notification; native_scene_focus(0); }
- (void)focusGained:(NSNotification *)notification { (void)notification; native_scene_focus(gameWindow.isKeyWindow && NSApp.active); }
@end

/* metal.m's menu setup: Photo Mode, before the app menu's Quit */
void native_scene_add_menu(NSMenu *menu) {
    if (!photo_enabled() || !menu) return;
    if (!ui) ui = [NativeScene new];
    NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:@"Photo Mode" action:nil keyEquivalent:@""];
    NSMenu *photoMenu = [[NSMenu alloc] initWithTitle:@"Photo Mode"];
    NSArray *titles = @[@"Enter Photo Mode", @"Capture Photo (F12)", @"Switch Orbit / Free Camera", @"Reset Camera", @"Exit Photo Mode"];
    SEL actions[] = { @selector(open:), @selector(capture:), @selector(mode:), @selector(reset:), @selector(exit:) };
    for (int i = 0; i < 5; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i] action:actions[i] keyEquivalent:i == 0 ? @"p" : @""];
        item.target = ui; if (i == 0) item.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
        [photoMenu addItem:item];
    }
    entry.submenu = photoMenu;
    NSInteger at = menu.numberOfItems;
    for (NSInteger i = 0; i < menu.numberOfItems; i++) if ([menu itemAtIndex:i].action == @selector(terminate:)) at = i;
    if (at > 0 && at < menu.numberOfItems && [menu itemAtIndex:at - 1].isSeparatorItem) at--;
    [menu insertItem:entry atIndex:at];
}
/* metal.m, once the game window is up: the panels and the focus */
void native_scene_attach(NSWindow *window) {
    NSCAssert(NSThread.isMainThread, @"native_scene_attach on the main thread");
    if (!(photo_enabled() || drift_enabled()) || !window || gameWindow) return;
    gameWindow = window; if (!ui) ui = [NativeScene new];
    ui.photoView = [[NativeSceneView alloc] initWithFrame:NSZeroRect]; ui.driftView = [[NativeSceneView alloc] initWithFrame:NSZeroRect];
    ui.photoView.progress = ui.driftView.progress = -1;
    ui.photoView.hidden = ui.driftView.hidden = YES;
    [window.contentView addSubview:ui.photoView]; [window.contentView addSubview:ui.driftView];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:ui selector:@selector(focusLost:) name:NSWindowDidResignKeyNotification object:window];
    [nc addObserver:ui selector:@selector(focusLost:) name:NSApplicationDidResignActiveNotification object:nil];
    [nc addObserver:ui selector:@selector(focusGained:) name:NSWindowDidBecomeKeyNotification object:window];
    [nc addObserver:ui selector:@selector(focusGained:) name:NSApplicationDidBecomeActiveNotification object:nil];
}
/* metal.m's main loop: the panels */
void native_scene_pump(void) {
    static int wasActive;
    int on = native_scene_active();
    if (on != wasActive) { wasActive = on; clearCamera(); }
    if (!ui || !gameWindow) return;
    NativeSceneSnapshot s; native_scene_snapshot(&s);
    NSRect bounds = gameWindow.contentView.bounds;
    CGFloat width = MAX(0, MIN(650, bounds.size.width - 32));
    ui.photoView.frame = NSMakeRect(16, 16, width, 142);
    ui.driftView.frame = NSMakeRect(MAX(16, (bounds.size.width - 350) / 2), MAX(16, bounds.size.height - 126), MAX(0, MIN(350, bounds.size.width - 32)), 110);
    BOOL photoHidden = !on || !gameWindow.isVisible, driftHidden = !(s.drift & 2) || on || !gameWindow.isVisible;
    if (ui.photoView.hidden != photoHidden){
        ui.photoView.hidden = photoHidden;
        fprintf(stderr, "[scene] the photo panel %s\n", photoHidden ? "hidden" : "shown");
    }
    if (ui.driftView.hidden != driftHidden){
        ui.driftView.hidden = driftHidden;
        fprintf(stderr, "[scene] the drift panel %s\n", !driftHidden ? "shown" : on ? "hidden (photo mode)" : "hidden");
    }
    if (on) {
        pthread_mutex_lock(&noticeLock); NSString *message = captureNotice; pthread_mutex_unlock(&noticeLock);
        NSString *text = [NSString stringWithFormat:@"PHOTO - %@ camera     FOV %.1f     Tilt %.1f\nWASD move | E/Q up/down | arrows turn | drag turn / right drag pan\nScroll closer | [ / ] FOV | Z/C tilt | Shift faster\nTab camera | R reset | F12 / Space save | Esc exit\nPad: sticks move / turn | RB/LB up/down | triggers closer / further\nA save | B exit | X camera | Y reset | D-pad FOV / tilt\n%@",
                          (s.photo & 4) ? @"Free" : @"Orbit", s.fov, s.roll, message ?: @""];
        if (![text isEqualToString:ui.photoView.text]) { ui.photoView.text = text; ui.photoView.needsDisplay = YES; }
    }
    if (!driftHidden) {
        NSString *result = @"";
        if (s.feedback_until > now()) result = s.feedback == 4 ? @"Drift lost!" : [NSString stringWithFormat:@"Banked +%.0f", s.banked];
        NSString *next = s.multiplier >= 5 ? @"Maximum multiplier" : [NSString stringWithFormat:@"Next x%d: %.0f points", MAX(1, s.multiplier) + 1, MAX(0, s.gain)];
        NSString *text = [NSString stringWithFormat:@"DRIFT  %.0f points   x%d\n%@\nTotal %.0f   Best %.0f\n%@", s.pending, MAX(1, s.multiplier), next, s.total, s.best, result];
        double progress = s.multiplier >= 5 ? 1 : s.gain > 0 ? MIN(1, s.pending / s.gain) : 0;
        if (result.length && ![ui.driftView.text hasSuffix:result])
            fprintf(stderr, "[scene] the drift panel: %s\n", [[text stringByReplacingOccurrencesOfString:@"\n" withString:@" | "] UTF8String]);
        if (![text isEqualToString:ui.driftView.text] || progress != ui.driftView.progress) {
            ui.driftView.text = text; ui.driftView.progress = progress; ui.driftView.needsDisplay = YES;
        }
    }
}
