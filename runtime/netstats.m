/* netstats.m -- the Online statistics panel: a small live panel in the
 * frame's top-left corner (under the frame-rate counter when that is on)
 * while playing online.
 *
 *   NFSU2_NET_STATS=1   on (the launcher's Settings > Online > Online
 *                       statistics, only with Play online).  Off by default, as
 *                       in the original game; without NFSU2_NET=online it stays off.
 *
 * What it shows, from top to bottom:
 *   Connection    the link to the server's switch (net_native.m): connected,
 *                 waiting in the server queue (and the place in it), connecting,
 *                 reconnecting, offline
 *   Round trip    the last ping to the switch and its pong (net_native.m, every 2 s)
 *   Players       the server's /players (the address of NFSU2_SERVER_URL: wss://host
 *                 -> https://host/players, ws:// on this Mac -> http://), with
 *                 ?room= and &crews= as the launcher's Check Player Counts asks
 *                 (launcher/PlayerCounts.swift): on the server, in free roam, in the
 *                 Online lobby, in the player's room and each crew, and "Server busy:
 *                 fewer cars shown" when the server says roamBusy
 *   Free roam     with free roam with other players only (roam_game.c): the friends'
 *                 cars shown near the player and the players the server's hub links
 *                 the player with
 *
 * /players is asked only while the panel is on and the game is online: at the
 * start, then every 30 s, and again (at most every 5 s) when the room or the
 * crews it asks about change (free roam starting, Game Tools).  One request at a
 * time, an ephemeral session: no cookies, credentials or cache, User-Agent
 * NFSU2-native, redirects refused, the answer read up to NETSTATS_ANSWER_MAX bytes.
 * A test run (nettest.h) asks a server on this Mac only.
 *
 * Cost: the numbers are gathered and the text made on a queue of its own, four
 * times a second; the panel's texture is made again only when the text changed
 * (AppKit text, as fpscounter.m); a frame draws one quad into the corner, with a
 * render pass limited to it, after the frame-dump copy (so no dump shows it).
 * No game function is overridden or hooked. */
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include <arpa/inet.h>
#include <os/lock.h>
#include <stdatomic.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include "netstats.h"
#include "net_native.h"
#include "nettest.h"

#define NS_EVERY_MS   30000             /* /players again after */
#define NS_CHANGED_MS 5000              /* ...or after this, for another room or crews */
#define NS_TICK_NS    250000000ull      /* the numbers and the text: four times a second */

int netstats_on(void){
    static int v = -1;
    if (v < 0){
        const char *e = getenv("NFSU2_NET_STATS");
        int on = e && (!strcmp(e, "1") || !strcasecmp(e, "on") || !strcasecmp(e, "yes") || !strcasecmp(e, "true"));
        v = on && native_net_enabled();
        if (on && !v) fprintf(stderr, "[netstats] NFSU2_NET_STATS needs Play online (NFSU2_NET=online): off\n");
    }
    return v;
}
static uint64_t ms_now(void){ return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000ull; }
static BOOL loopback_host(NSString *host){
    host = host.lowercaseString;
    if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"::1"]) return YES;
    struct in_addr a;
    return inet_pton(AF_INET, host.UTF8String, &a) == 1 && (ntohl(a.s_addr) >> 24) == 127;
}

/* ---- state (the queue's; the text also the presenter's, under g_lk) ---------- */
static dispatch_queue_t g_q;
static dispatch_source_t g_timer;
static NSURLSession *g_session;
static NSURLSessionDataTask *g_task;
static uint64_t g_next_at, g_asked_at;
static int g_counts;                      /* netstats_view.counts */
static netstats_counts g_c;
static netstats_roam g_asked;             /* the room and crews the answer is for */
static int g_asked_room, g_asked_crews;
static int g_said;                        /* a note about the address logged: -1 not a valid one, -2 not on this Mac in a test run */
static char g_url[512];                   /* the last address asked (without room and crews: g_base) */
static os_unfair_lock g_lk = OS_UNFAIR_LOCK_INIT;
static char g_text[1024];
static _Atomic unsigned g_text_gen;

@interface NetStatsFetch : NSObject <NSURLSessionDataDelegate> {
@public
    NSMutableData *body; NSInteger status; BOOL tooBig;
}
@end
static void answered(NSURLSessionTask *task, NSData *body, NSInteger status, NSError *error);
@implementation NetStatsFetch
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))done {
    (void)s; (void)task;
    if (![response isKindOfClass:NSHTTPURLResponse.class] || response.expectedContentLength > NETSTATS_ANSWER_MAX){
        tooBig = YES; done(NSURLSessionResponseCancel); return; }
    status = ((NSHTTPURLResponse *)response).statusCode; body = [NSMutableData new];
    done(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)s;
    if (tooBig) return;
    if (body.length + data.length > NETSTATS_ANSWER_MAX){ tooBig = YES; [task cancel]; return; }
    [body appendData:data];
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))done {
    (void)s; (void)task; (void)response; (void)request;
    done(nil);                            /* the counts come from the address asked: the redirect is the answer (not 200) */
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)s;
    NSData *b = tooBig ? nil : body; NSInteger st = status;
    body = nil; status = 0; tooBig = NO;
    answered(task, b, st, error);
}
@end

/* on g_q (the session's delegate queue runs on it) */
static void answered(NSURLSessionTask *task, NSData *body, NSInteger status, NSError *error){
    if (task != g_task) return;
    g_task = nil;
    g_next_at = ms_now() + NS_EVERY_MS;
    netstats_counts c;
    int ok = !error && status == 200 && body && netstats_parse_players(body.bytes, body.length, &c);
    if (ok){ g_c = c; g_counts = 1; }
    else if (g_counts <= 0) g_counts = -1;  /* (a failure after an answer keeps the answer's numbers) */
    static int last = -1;                 /* logged when it changes */
    if (ok != last){
        last = ok;
        if (ok) fprintf(stderr, "[netstats] player counts from %s\n", g_url);
        else fprintf(stderr, "[netstats] no player counts from %s (%s)\n", g_url,
                     error ? error.localizedDescription.UTF8String : body ? "not an answer of counts" : "too large or no answer");
    }
}
static void ask(const netstats_roam *r, int roam){
    const char *server = getenv("NFSU2_SERVER_URL");
    if (!server || !*server) server = "wss://nfsu2.xyz/lan";          /* net_native.m's */
    char url[512];
    if (!netstats_players_url(server, roam ? r->room : 0, roam ? r->crews : NULL, roam ? r->ncrews : 0, url, sizeof url)){
        if (g_said != -1){ fprintf(stderr, "[netstats] no player counts: the server address is not a wss:// one (ws:// only on this Mac)\n"); g_said = -1; }
        g_counts = -1; g_next_at = ms_now() + NS_EVERY_MS; return;
    }
    NSURL *u = [NSURL URLWithString:@(url)];
    if (!u){ g_counts = -1; g_next_at = ms_now() + NS_EVERY_MS; return; }
    if (nfsu2_test_run() && !loopback_host(u.host)){
        if (g_said != -2) fprintf(stderr, "[net] BLOCKED the player counts from %s: a test run asks a server on this Mac only\n", u.host.UTF8String);
        g_said = -2; g_counts = -1; g_next_at = ms_now() + NS_EVERY_MS; return;
    }
    if (!g_session){
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.HTTPShouldSetCookies = NO; cfg.HTTPCookieStorage = nil; cfg.URLCredentialStorage = nil; cfg.URLCache = nil;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        cfg.timeoutIntervalForRequest = 10; cfg.timeoutIntervalForResource = 15; cfg.HTTPMaximumConnectionsPerHost = 1;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"NFSU2-native", @"Accept": @"application/json" };
        NSOperationQueue *ops = [NSOperationQueue new]; ops.maxConcurrentOperationCount = 1; ops.underlyingQueue = g_q;
        g_session = [NSURLSession sessionWithConfiguration:cfg delegate:[NetStatsFetch new] delegateQueue:ops];
    }
    snprintf(g_url, sizeof g_url, "%s", url);
    g_asked = *r; g_asked_room = roam && r->room; g_asked_crews = 0;
    for (int i = 0; roam && i < r->ncrews && i < NETSTATS_CREWS; i++){
        if (!r->crews[i]) continue;
        g_asked.crews[g_asked_crews] = r->crews[i];
        snprintf(g_asked.crew_name[g_asked_crews], sizeof g_asked.crew_name[0], "%s", r->crew_name[i]);
        g_asked_crews++;
    }
    g_asked_at = ms_now();
    g_task = [g_session dataTaskWithURL:u];
    [g_task resume];
}
static int same_ask(const netstats_roam *r, int roam){
    int room = roam && r->room;
    if (room != g_asked_room || (room && r->room != g_asked.room)) return 0;
    int n = 0;
    for (int i = 0; roam && i < r->ncrews; i++) if (r->crews[i]){ if (n >= g_asked_crews || g_asked.crews[n] != r->crews[i]) return 0; n++; }
    return n == g_asked_crews;
}
static void tick(void){
    netstats_view v; memset(&v, 0, sizeof v);
    native_net_status ns; native_net_get_status(&ns);
    v.conn = ns.state; v.queue_pos = ns.queue_pos; v.queue_of = ns.queue_of; v.rtt_ms = ns.rtt_ms;
    netstats_roam r; v.free_roam = roam_game_netstats(&r);
    uint64_t now = ms_now();
    if (!g_task && (!g_asked_at || now >= g_next_at || (!same_ask(&r, v.free_roam) && now - g_asked_at >= NS_CHANGED_MS)))
        ask(&r, v.free_roam);
    v.counts = g_counts; v.c = g_c;
    v.asked_room = g_counts > 0 && g_asked_room; v.asked_crews = g_counts > 0 ? g_asked_crews : 0;
    v.r = r;
    memcpy(v.r.room_name, g_asked.room_name, sizeof v.r.room_name);
    memcpy(v.r.crew_name, g_asked.crew_name, sizeof v.r.crew_name);
    char t[sizeof g_text];
    netstats_text(&v, t, sizeof t);
    os_unfair_lock_lock(&g_lk);
    int changed = strcmp(t, g_text) != 0;
    if (changed) memcpy(g_text, t, sizeof t);
    os_unfair_lock_unlock(&g_lk);
    if (changed){
        atomic_fetch_add(&g_text_gen, 1u);
        static int lg = -1; if (lg < 0){ const char *e = getenv("NFSU2_NET_STATS_LOG"); lg = e && *e == '1'; }
        if (lg){ NSString *one = [(@(t) ?: @"") stringByReplacingOccurrencesOfString:@"\n" withString:@" | "];
                 fprintf(stderr, "[netstats] %s\n", one.UTF8String ?: ""); }
    }
}
void netstats_start(void){
    static dispatch_once_t once;
    if (!netstats_on()) return;
    dispatch_once(&once, ^{
        g_q = dispatch_queue_create("nfsu2.netstats", DISPATCH_QUEUE_SERIAL);
        g_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, g_q);
        dispatch_source_set_timer(g_timer, DISPATCH_TIME_NOW, NS_TICK_NS, NS_TICK_NS / 4);
        dispatch_source_set_event_handler(g_timer, ^{ @autoreleasepool { tick(); } });
        dispatch_resume(g_timer);
        fprintf(stderr, "[netstats] Online statistics on\n");
    });
}
size_t netstats_snapshot(char *out, size_t cap){
    if (!cap) return 0;
    os_unfair_lock_lock(&g_lk);
    snprintf(out, cap, "%s", g_text);
    os_unfair_lock_unlock(&g_lk);
    return strlen(out);
}

/* ---- the panel ----------------------------------------------------------------------------- */
static id<MTLDevice> g_dev;
static id<MTLRenderPipelineState> g_pso;
static id<MTLTexture> g_tex; static NSUInteger g_tw, g_th;
static MTLRenderPassDescriptor *g_rp;
static NSString *kSrc = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct OV { float4 pos [[position]]; float2 uv; };\n"
"vertex OV ns_vs(uint vid [[vertex_id]], constant float4 &R [[buffer(0)]]) {\n"
"  float cx = (vid == 1 || vid == 2 || vid == 4) ? 1.0 : 0.0, cy = (vid == 2 || vid == 4 || vid == 5) ? 1.0 : 0.0;\n"
"  OV o; o.pos = float4(mix(R.x, R.z, cx), mix(R.y, R.w, cy), 0, 1); o.uv = float2(cx, cy); return o; }\n"
"fragment float4 ns_tex(OV i [[stage_in]], texture2d<float> t [[texture(0)]]) {\n"
"  constexpr sampler P(address::clamp_to_edge, filter::nearest); return t.sample(P, i.uv); }\n";
static int pso_init(void){
    if (g_pso) return 1;
    static int failed;
    if (failed || !g_dev) return 0;
    NSError *e = nil;
    id<MTLLibrary> l = [g_dev newLibraryWithSource:kSrc options:nil error:&e];
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [l newFunctionWithName:@"ns_vs"];
    pd.fragmentFunction = [l newFunctionWithName:@"ns_tex"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pd.colorAttachments[0].blendingEnabled = YES;              /* premultiplied */
    pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    if (l) g_pso = [g_dev newRenderPipelineStateWithDescriptor:pd error:&e];
    if (!g_pso){ failed = 1; fprintf(stderr, "[netstats] pipeline: %s\n", e.localizedDescription.UTF8String); return 0; }
    g_rp = [MTLRenderPassDescriptor renderPassDescriptor];
    g_rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
    g_rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    return 1;
}
/* the text into a new texture (frames still on the GPU keep the old one: no half-written panel) */
static void render_panel(const char *text, double ppp){
    CGFloat fs = 11.0 * ppp, lh = ceil(fs * 1.3), pad = ceil(6 * ppp);
    NSFont *font = [NSFont monospacedDigitSystemFontOfSize:fs weight:NSFontWeightSemibold];
    NSDictionary *at = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor whiteColor] };
    NSArray<NSString *> *lines = [(@(text) ?: @"") componentsSeparatedByString:@"\n"];
    CGFloat tw = ceil(150 * ppp);
    for (NSString *l in lines){ NSSize z = [l sizeWithAttributes:at]; if (z.width > tw) tw = ceil(z.width); }
    size_t W = ((size_t)(tw + 2 * pad) + 3) & ~(size_t)3, H = (size_t)(2 * pad + lh * lines.count);
    void *buf = calloc(W * H, 4);
    if (!buf) return;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(buf, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(cg, 0, 0, 0, 0.62);
    CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(0, 0, W, H), 5 * ppp, 5 * ppp, NULL);
    CGContextAddPath(cg, p); CGContextFillPath(cg); CGPathRelease(p);
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:NO];
    [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:gc];
    for (NSUInteger i = 0; i < lines.count; i++)
        [lines[i] drawAtPoint:NSMakePoint(pad, (CGFloat)H - pad - lh * (i + 1) + (lh - fs) * 0.35) withAttributes:at];
    [NSGraphicsContext restoreGraphicsState];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                   width:W height:H mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead; td.storageMode = MTLStorageModeShared;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:td];
    if (t){ [t replaceRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0 withBytes:buf bytesPerRow:W * 4];
            g_tex = t; g_tw = W; g_th = H; }
    CGContextRelease(cg); CGColorSpaceRelease(cs); free(buf);
}
void netstats_init(id<MTLDevice> dev){ g_dev = dev; netstats_start(); }

void netstats_draw(id<MTLCommandBuffer> cb, id<MTLTexture> dst, double px_per_pt, double top){
    if (!netstats_on() || dst.pixelFormat != MTLPixelFormatBGRA8Unorm || !pso_init()) return;
    double ppp = px_per_pt > 0 ? fmax(px_per_pt, 0.75) : 1.0;
    static unsigned drawn_gen = ~0u; static double drawn_ppp;
    unsigned gen = atomic_load(&g_text_gen);
    if (gen && (gen != drawn_gen || ppp != drawn_ppp)){
        char t[sizeof g_text];
        netstats_snapshot(t, sizeof t);
        drawn_gen = gen; drawn_ppp = ppp;
        @autoreleasepool { render_panel(t, ppp); }
    }
    if (!g_tex) return;
    double mg = round(10 * ppp), y0 = top > 0 ? top + round(6 * ppp) : mg;
    if (mg + g_tw > dst.width || y0 + g_th > dst.height) return;      /* the window is too small for it */
    /* the pass covers only the corner down to the panel: W x H from the top-left */
    double W = mg + g_tw, H = y0 + g_th;
    float R[4] = { (float)(-1 + 2 * mg / W), (float)(1 - 2 * y0 / H), (float)(-1 + 2 * (mg + g_tw) / W), (float)(1 - 2 * (y0 + g_th) / H) };
    g_rp.colorAttachments[0].texture = dst;
    g_rp.renderTargetWidth = (NSUInteger)W; g_rp.renderTargetHeight = (NSUInteger)H;
    id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:g_rp];
    e.label = @"online statistics";
    [e setViewport:(MTLViewport){ 0, 0, W, H, 0, 1 }];
    [e setRenderPipelineState:g_pso];
    [e setVertexBytes:R length:sizeof R atIndex:0];
    [e setFragmentTexture:g_tex atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [e endEncoding];
    g_rp.colorAttachments[0].texture = nil;   /* (not kept alive by the descriptor until the next frame) */
}
