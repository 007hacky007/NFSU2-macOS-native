/* Foundation WebSocket transport shared by free roam and the guest's LAN.
 * The wire format is web/src/net/proto.ts. Advertise raw frames only; the
 * switch retains browser interoperability without requiring its optional
 * bundle, compact, delta and prediction codecs here.
 *
 * The client side of th0mk's nfsu2-web server's switch (its wire format:
 * net_proto.h, MIT). */
#import <Foundation/Foundation.h>
#include "net_native.h"
#include "nettest.h"
#include "netstats.h"
#include <arpa/inet.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

int native_net_enabled(void){
    const char *s = getenv("NFSU2_NET");
    return s && !strcasecmp(s, "online");
}
static BOOL loopback_host(NSString *host){
    host = host.lowercaseString;
    if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"::1"] || [host isEqualToString:@"[::1]"]) return YES;
    struct in_addr a;
    return inet_pton(AF_INET, host.UTF8String, &a) == 1 && (ntohl(a.s_addr) >> 24) == 127;
}
static NSURLComponents *components(const char *text){
    if (!text || !*text || strlen(text) > 4096) return nil;
    NSString *s = [NSString stringWithUTF8String:text];
    if (!s || [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithString:s];
    NSString *scheme = c.scheme.lowercaseString, *host = c.host.lowercaseString;
    if (!host.length || c.user != nil || c.password != nil || c.fragment != nil || !c.URL) return nil;
    if (c.port && (c.port.integerValue < 1 || c.port.integerValue > 65535)) return nil;
    if ([scheme isEqualToString:@"wss"]) return c;
    return [scheme isEqualToString:@"ws"] && loopback_host(host) ? c : nil;
}
int native_net_url_valid(const char *url){ @autoreleasepool { return components(url) != nil; } }
void native_net_wait(int *word, int expected, int64_t ns){
    if (__atomic_load_n(word, __ATOMIC_SEQ_CST) != expected || ns <= 0) return;
    /* Poll the shared mailbox briefly: no guest lock is held by its waiters. */
    if (ns > 2000000) ns = 2000000;
    struct timespec t = { ns / 1000000000, ns % 1000000000 };
    nanosleep(&t, NULL);
}
/* The claimed name's token (launcher/NameClaims.swift): 43 characters of base64url
 * from a pipe the launcher wrote and closed before the engine started
 * (NFSU2_CLAIM_FD).  Read once as the engine loads, the variable dropped; the
 * switch's hello names it ("claim") so the server knows whose claimed name this
 * player may play under.  Never logged. */
static char claim_token[44];
__attribute__((constructor)) static void read_claim_token(void){
    const char *v = getenv("NFSU2_CLAIM_FD");
    if (!v || !*v) return;
    char *end; long fd = strtol(v, &end, 10);
    unsetenv("NFSU2_CLAIM_FD");
    struct stat sb;
    if (*end || fd < 3 || fd > 65535 || fstat((int)fd, &sb) != 0 || !S_ISFIFO(sb.st_mode)) return;
    char b[64]; ssize_t n = read((int)fd, b, sizeof b - 1); close((int)fd);
    if (n > 0 && b[n - 1] == '\n') n--;
    int ok = n == 43;
    for (ssize_t i = 0; ok && i < n; i++){ char c = b[i]; ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'; }
    if (ok){ memcpy(claim_token, b, 43); claim_token[43] = 0; }
    memset(b, 0, sizeof b);
}
int native_net_has_claim(void){ return claim_token[0] != 0; }
/* Free roam's friends (native_controls.m, ported from th0mk's nfsu2-web web/src/app/friends.ts): the server's
 * {"t":"friend",...} messages on this link go there, and so does the news of each welcome; its own go out through
 * native_net_text.  Weak here: the tests that build this file alone have no Game Tools. */
__attribute__((weak)) void native_controls_net_friend(const char *json){ (void)json; }
__attribute__((weak)) void native_controls_net_welcome(int claimed){ (void)claimed; }
static char native_queue_key;
static uint32_t ld(const uint32_t *p){ return __atomic_load_n(p, __ATOMIC_SEQ_CST); }
static void st(uint32_t *p, uint32_t v){ __atomic_store_n(p, v, __ATOMIC_SEQ_CST); }
static uint32_t be32(const uint8_t *p){ return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static void put32(uint8_t *p, uint32_t v){ p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static void put16(uint8_t *p, uint16_t v){ p[0] = v >> 8; p[1] = v; }
static uint64_t now_ms(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000; }
/* the link as the statistics panel shows it (native_net_get_status): written on the transport's queue */
static int st_state = NETSTATS_OFFLINE, st_pos, st_of, st_rtt = -1;
static void st_set(int *p, int v){ __atomic_store_n(p, v, __ATOMIC_RELAXED); }
void native_net_get_status(native_net_status *o){
    o->state = __atomic_load_n(&st_state, __ATOMIC_RELAXED);
    o->queue_pos = __atomic_load_n(&st_pos, __ATOMIC_RELAXED); o->queue_of = __atomic_load_n(&st_of, __ATOMIC_RELAXED);
    o->rtt_ms = __atomic_load_n(&st_rtt, __ATOMIC_RELAXED);
}

@interface NFSNativeNet : NSObject <NSURLSessionWebSocketDelegate> {
@public
    dispatch_queue_t queue;
    net_mailbox *lan, *roam;
    NSURLSession *session;
    NSURLSessionWebSocketTask *socket;
    dispatch_source_t timer;
    NSURLComponents *url;
    NSString *name, *token, *ticket;
    NSMutableSet<NSNumber *> *peers;
    NSMutableArray<NSData *> *pending;
    uint32_t vip, mask, generation;
    uint64_t retryAt, startedAt, idleAt, pingAt;
    unsigned backoff, nextMailbox;
    dispatch_semaphore_t closeWait;
    BOOL connected, welcomed, sending, receiving, stopped, lanSent, queued, dropped;
}
- (void)pump;
- (void)connect;
- (void)receive;
- (void)lost;
- (void)publish:(uint32_t)state;
@end
@implementation NFSNativeNet
- (instancetype)init {
    if ((self = [super init])){
        queue = dispatch_queue_create("nfsu2.native-network", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, &native_queue_key, &native_queue_key, NULL);
        peers = [NSMutableSet new]; pending = [NSMutableArray new]; backoff = 250;
        const char *u = getenv("NFSU2_SERVER_URL"); url = components(u && *u ? u : "wss://nfsu2.xyz/lan");
        const char *n = getenv("NFSU2_ROAM_NAME"); name = n ? [NSString stringWithUTF8String:n] : nil;
        name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL local = url && loopback_host(url.host);
        if (nfsu2_test_run() && !local){ fprintf(stderr, "[network] automated runs require a loopback relay URL\n"); stopped = YES; }
        if (!url || !name.length || name.length > 64){
            fprintf(stderr, "[network] online needs a valid server URL and an explicit player name\n"); stopped = YES;
        }
        if (claim_token[0]) fprintf(stderr, "[network] playing with the keyphrase's claim on the name (from the launcher)\n");
        NSOperationQueue *ops = [NSOperationQueue new]; ops.maxConcurrentOperationCount = 1; ops.underlyingQueue = queue;
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.HTTPShouldSetCookies = NO; cfg.HTTPCookieStorage = nil; cfg.URLCredentialStorage = nil;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"NFSU2-native" };
        session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:ops];
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2000000, 500000);
        __weak NFSNativeNet *weak = self;
        dispatch_source_set_event_handler(timer, ^{ @autoreleasepool { [weak pump]; } });
        dispatch_resume(timer);
    }
    return self;
}
- (void)publish:(uint32_t)state {
    for (unsigned i = 0; i < 2; i++){
        net_mailbox *m = i ? roam : lan; if (!m) continue;
        st(&m->vip, vip); st(&m->netmask, mask); st(&m->generation, generation);
        for (unsigned j = 0; j < NET_PEER_BITS / 32; j++) st(&m->peer_bits[j], 0);
        for (NSNumber *p in peers){ uint32_t h = p.unsignedIntValue & ~mask;
            if (h < NET_PEER_BITS) __atomic_fetch_or(&m->peer_bits[h >> 5], 1u << (h & 31), __ATOMIC_SEQ_CST);
        }
        st(&m->switch_peers, (uint32_t)peers.count); st(&m->page_state, state);
        __atomic_add_fetch(&m->rx_bell, 1, __ATOMIC_SEQ_CST);
    }
    /* the panel's view: in the line while the server says so on this link; a link lost (or a try after one) is
     * "reconnecting" until the next welcome; idle or stopped, offline */
    int s = stopped || state == NET_PAGE_IDLE || state == NET_PAGE_NONE ? NETSTATS_OFFLINE
          : state == NET_PAGE_ONLINE ? NETSTATS_CONNECTED
          : queued && socket ? NETSTATS_QUEUED
          : dropped || state == NET_PAGE_OFFLINE ? NETSTATS_RECONNECTING : NETSTATS_CONNECTING;
    if (state == NET_PAGE_IDLE) dropped = NO;
    if (s != NETSTATS_QUEUED){ st_set(&st_pos, 0); st_set(&st_of, 0); }
    st_set(&st_state, s);
}
- (void)sendJSON:(NSDictionary *)object {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSURLSessionWebSocketTask *s = socket;
    [s sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:text] completionHandler:^(NSError *error){
        if (error) dispatch_async(self->queue, ^{ if (self->socket == s) [self lost]; });
    }];
}
- (void)connect {
    NSURLComponents *u = [url copy]; NSMutableArray *items = [NSMutableArray new];
    for (NSURLQueryItem *item in u.queryItems) if (![item.name isEqualToString:@"queue"] && ![item.name isEqualToString:@"resume"]) [items addObject:item];
    [items addObject:[NSURLQueryItem queryItemWithName:@"queue" value:nil]];
    if ((vip && token.length) || ticket.length) [items addObject:[NSURLQueryItem queryItemWithName:@"resume" value:nil]];
    u.queryItems = items;
    startedAt = now_ms(); queued = NO; st_set(&st_rtt, -1); [self publish:NET_PAGE_CONNECTING];
    /* The peer list with LAN play on names every player on the server (up to 6000, a name up to 32
     * characters): a few hundred KB on a busy server, which a 64 KB cap turned into a reconnect a second. */
    socket = [session webSocketTaskWithURL:u.URL]; socket.maximumMessageSize = 4 << 20;
    [socket resume];
}
- (void)URLSession:(NSURLSession *)s webSocketTask:(NSURLSessionWebSocketTask *)task didOpenWithProtocol:(NSString *)protocol {
    (void)s; (void)protocol; if (socket != task) return;
    connected = YES; lanSent = lan && ld(&lan->want);
    NSMutableDictionary *hello = [@{ @"t": @"hello", @"name": name, @"lan": @((int)lanSent) } mutableCopy];
    if (vip && token.length){ hello[@"vip"] = [NSString stringWithFormat:@"%u.%u.%u.%u", vip >> 24, (vip >> 16) & 255, (vip >> 8) & 255, vip & 255]; hello[@"token"] = token; }
    if (ticket.length) hello[@"ticket"] = ticket;
    if (claim_token[0]) hello[@"claim"] = @(claim_token);
    [self sendJSON:hello]; [self receive];
}
- (void)URLSession:(NSURLSession *)s webSocketTask:(NSURLSessionWebSocketTask *)task didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {
    (void)s; (void)reason; if (closeWait) dispatch_semaphore_signal(closeWait);
    if (socket != task) return;
    if (code == 4001 || code == 4003) stopped = YES;
    [self lost];
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)s; (void)error; if (closeWait) dispatch_semaphore_signal(closeWait);
    if (task == socket) [self lost];
}
- (void)lost {
    NSURLSessionWebSocketTask *old = socket; socket = nil;
    connected = welcomed = sending = receiving = NO;
    [old cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];
    [pending removeAllObjects]; [peers removeAllObjects]; dropped = YES;
    for (unsigned i = 0; i < 2; i++){
        net_mailbox *m = i ? roam : lan; if (!m) continue;
        uint32_t head = ld(&m->tx_head), tail = ld(&m->tx_tail);
        __atomic_add_fetch(&m->tx_offline_drop, head - tail, __ATOMIC_SEQ_CST); st(&m->tx_tail, head);
    }
    [self publish:NET_PAGE_OFFLINE]; retryAt = now_ms() + backoff; if (backoff < 5000) backoff = MIN(backoff * 2, 5000u);
}
- (BOOL)deliver:(NSData *)data {
    if (data.length < 16 || data.length > 16 + NET_MAX_PAYLOAD) return YES;
    const uint8_t *b = data.bytes; unsigned kind = b[0];
    if (kind < NET_KIND_UDP || kind > NET_KIND_LAN_ICMP) return YES;
    net_mailbox *m = kind <= NET_KIND_UDP_LOOP ? roam : lan;
    if (!m || !ld(&m->want)) return YES;
    uint32_t dst = be32(b + 8);
    if (dst != vip && dst != NET_BROADCAST && dst != ((vip & mask) | ~mask)) return YES;
    uint32_t head = ld(&m->rx_head);
    if (head - ld(&m->rx_tail) >= NET_RX_SLOTS){
        if (kind == NET_KIND_LAN_TCP) return NO;
        __atomic_add_fetch(&m->rx_full_drop, 1, __ATOMIC_SEQ_CST); return YES;
    }
    net_slot *p = (net_slot *)((uint8_t *)m + m->rx_off + (head % NET_RX_SLOTS) * NET_SLOT_BYTES);
    p->kind = kind; p->src_ip = be32(b + 4); p->dst_ip = dst;
    p->src_port = (uint16_t)(b[12] << 8 | b[13]); p->dst_port = (uint16_t)(b[14] << 8 | b[15]);
    p->len = (uint32_t)data.length - 16; p->t_ms = (double)now_ms(); memcpy(p->data, b + 16, p->len);
    st(&m->rx_head, head + 1); __atomic_add_fetch(&m->rx_bell, 1, __ATOMIC_SEQ_CST); return YES;
}
- (void)control:(NSString *)text {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
    if (![parsed isKindOfClass:NSDictionary.class]) return; NSDictionary *m = parsed;
    NSString *type = m[@"t"];
    if ([type isEqual:@"welcome"] && [m[@"vip"] isKindOfClass:NSNumber.class]){
        uint32_t v = [m[@"vip"] unsignedIntValue]; struct in_addr a;
        NSString *ms = [m[@"mask"] isKindOfClass:NSString.class] ? m[@"mask"] : @"255.255.255.0";
        if ((v & 0xffff0000u) != 0x0a4d0000u || inet_pton(AF_INET, ms.UTF8String, &a) != 1){ [self lost]; return; }
        vip = v; mask = ntohl(a.s_addr); generation++; welcomed = YES; queued = NO; dropped = NO; backoff = 250;
        token = [m[@"token"] isKindOfClass:NSString.class] ? m[@"token"] : nil; ticket = nil;
        [self publish:NET_PAGE_ONLINE]; fprintf(stderr, "[network] connected to switch as %u.%u.%u.%u\n", vip >> 24, (vip >> 16) & 255, (vip >> 8) & 255, vip & 255);
        native_controls_net_welcome(claim_token[0] != 0);
    } else if ([type isEqual:@"queue"]){
        if ([m[@"ticket"] isKindOfClass:NSString.class]) ticket = m[@"ticket"];
        if (!queued) fprintf(stderr, "[network] waiting in the server queue\n"); queued = YES; [self publish:NET_PAGE_OFFLINE];
        /* {"t":"queue","pos":p,"of":n,...} (the server's lan crate, queue.rs): p 1 is the next in */
        int pos = [m[@"pos"] isKindOfClass:NSNumber.class] ? [m[@"pos"] intValue] : 0, of = [m[@"of"] isKindOfClass:NSNumber.class] ? [m[@"of"] intValue] : 0;
        st_set(&st_pos, pos > 0 && pos < 1000000 ? pos : 0); st_set(&st_of, of > 0 && of < 1000000 ? of : 0);
    } else if ([type isEqual:@"pong"] && [m[@"id"] isKindOfClass:NSNumber.class]){
        /* the answer to our ping ({"t":"ping","id":now_ms}, pump): the round trip to the switch */
        uint64_t now = now_ms(), sent = [m[@"id"] unsignedLongLongValue];
        if (sent <= now && now - sent < 60000){
            double ms = (double)(now - sent);
            for (unsigned i = 0; i < 2; i++){ net_mailbox *x = i ? roam : lan; if (x) __atomic_store(&x->switch_rtt_ms, &ms, __ATOMIC_SEQ_CST); }
            st_set(&st_rtt, (int)(now - sent));
        }
    } else if ([type isEqual:@"friend"] && text.length <= 65536){
        native_controls_net_friend(text.UTF8String);
    } else if ([type isEqual:@"kick"] || [type isEqual:@"ban"]){ stopped = YES; [self lost];
    } else if ([type isEqual:@"peers"] && [m[@"peers"] isKindOfClass:NSArray.class]){
        NSMutableSet *next = [NSMutableSet new];
        for (id p in m[@"peers"]) if ([p isKindOfClass:NSDictionary.class] && [p[@"vip"] isKindOfClass:NSNumber.class]) [next addObject:p[@"vip"]];
        for (NSNumber *p in peers) if (![next containsObject:p] && p.unsignedIntValue != vip){
            uint8_t gone[24] = { NET_KIND_LAN_TCP }; put32(gone + 4, p.unsignedIntValue); put32(gone + 8, vip); gone[16] = NET_LAN_TCP_GONE;
            NSData *d = [NSData dataWithBytes:gone length:sizeof gone];
            if (![self deliver:d]) [pending addObject:d];
        }
        peers = next; [self publish:welcomed ? NET_PAGE_ONLINE : NET_PAGE_OFFLINE];
    }
}
- (void)receive {
    if (!socket || receiving || pending.count) return;
    receiving = YES; NSURLSessionWebSocketTask *s = socket;
    [s receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error){
        dispatch_async(self->queue, ^{
            if (self->socket != s) return; self->receiving = NO;
            if (error){ [self lost]; return; }
            if (message.type == NSURLSessionWebSocketMessageTypeString) [self control:message.string];
            else if (message.data.length > 16 && ((const uint8_t *)message.data.bytes)[0] == NET_KIND_LAN_TCP
                     && ((const uint8_t *)message.data.bytes)[16] == NET_LAN_TCP_GONE){
                /* "that player left" is made here from the server's peer list, never taken from the wire */
            }
            else if (![self deliver:message.data]) [self->pending addObject:message.data];
            [self receive];
        });
    }];
}
- (void)pump {
    uint64_t now = now_ms(); BOOL wanted = (lan && ld(&lan->want)) || (roam && ld(&roam->want));
    if (!wanted){
        if (!idleAt) idleAt = now;
        if (socket && now - idleAt > 5000){
            /* Publish before rechecking want, paired with the guest's want-then-state read. */
            [self publish:NET_PAGE_IDLE];
            if ((lan && ld(&lan->want)) || (roam && ld(&roam->want))){
                idleAt = 0; [self publish:welcomed ? NET_PAGE_ONLINE : NET_PAGE_CONNECTING]; return;
            }
            NSURLSessionWebSocketTask *old = socket; socket = nil;
            [old cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:[@"idle" dataUsingEncoding:NSUTF8StringEncoding]];
            [self lost]; vip = mask = 0; token = ticket = nil; [self publish:NET_PAGE_IDLE];
        }
        if (!socket || !welcomed) return;
        /* Drain the last BYE/FIN frames before returning the switch's place. */
    } else idleAt = 0;
    if (stopped) return;
    if (!socket){ if (now >= retryAt) [self connect]; return; }
    if (!welcomed && !queued && now - startedAt > 15000){ [self lost]; return; }
    while (pending.count && [self deliver:pending.firstObject]) [pending removeObjectAtIndex:0];
    [self receive];
    if (!connected) return;
    BOOL l = lan && ld(&lan->want);
    if (lanSent != l){ lanSent = l; [self sendJSON:@{ @"t": @"lan", @"on": @((int)l) }]; }
    if (now >= pingAt){ pingAt = now + 2000; [self sendJSON:@{ @"t": @"ping", @"id": @(now) }]; }
    if (!welcomed || sending) return;
    for (unsigned i = 0; i < 2; i++){
        unsigned selected = (i + nextMailbox) % 2;
        net_mailbox *m = selected ? roam : lan; if (!m) continue;
        uint32_t tail = ld(&m->tx_tail); if (tail == ld(&m->tx_head)) continue;
        net_slot *p = (net_slot *)((uint8_t *)m + m->tx_off + (tail % NET_TX_SLOTS) * NET_SLOT_BYTES);
        if (p->len > NET_MAX_PAYLOAD || p->kind < NET_KIND_UDP || p->kind > NET_KIND_LAN_ICMP){ st(&m->tx_tail, tail + 1); continue; }
        uint8_t frame[16 + NET_MAX_PAYLOAD] = { 0 }; frame[0] = p->kind;
        put32(frame + 4, vip); put32(frame + 8, p->dst_ip); put16(frame + 12, p->src_port); put16(frame + 14, p->dst_port); memcpy(frame + 16, p->data, p->len);
        NSData *d = [NSData dataWithBytes:frame length:16 + p->len]; sending = YES; nextMailbox = selected ^ 1u; NSURLSessionWebSocketTask *s = socket;
        [s sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithData:d] completionHandler:^(NSError *error){
            dispatch_async(self->queue, ^{ if (self->socket != s) return; self->sending = NO;
                if (error) [self lost]; else { st(&m->tx_tail, tail + 1); [self pump]; }
            });
        }];
        break;
    }
}
@end
static NFSNativeNet *transport;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void create_transport(void){ transport = [NFSNativeNet new]; atexit(native_net_shutdown); }
net_mailbox *native_net_mailbox(uint32_t mode){
    if (!native_net_enabled() || (mode != NET_MODE_LAN && mode != NET_MODE_VLAN)) return NULL;
    pthread_once(&once, create_transport); __block net_mailbox *result;
    dispatch_sync(transport->queue, ^{
        net_mailbox **p = mode == NET_MODE_LAN ? &transport->lan : &transport->roam;
        if (!*p){
            *p = aligned_alloc(64, NET_MAILBOX_BYTES);
            if (*p){ memset(*p, 0, NET_MAILBOX_BYTES); (*p)->magic = NET_MAGIC; (*p)->version = NET_VERSION;
                (*p)->hdr_bytes = NET_HDR_BYTES; (*p)->slot_bytes = NET_SLOT_BYTES; (*p)->tx_slots = NET_TX_SLOTS; (*p)->rx_slots = NET_RX_SLOTS;
                (*p)->tx_off = NET_HDR_BYTES; (*p)->rx_off = NET_HDR_BYTES + NET_TX_SLOTS * NET_SLOT_BYTES; (*p)->mode = mode;
                [transport publish:transport->welcomed ? NET_PAGE_ONLINE : NET_PAGE_CONNECTING];
            }
        }
        result = *p;
    });
    return result;
}
/* a control message of ours on the link ({"t":"friend",...} or {"t":"room",...}: native_controls.m), sent once it is
 * welcomed; 0 when there is no link to send it on (never connected, or not now) */
int native_net_text(const char *json){
    if (!transport || !json) return 0;
    size_t n = strnlen(json, 4097);
    if (!n || n > 4096) return 0;
    NSString *text = [[NSString alloc] initWithBytes:json length:n encoding:NSUTF8StringEncoding];
    if (!text) return 0;
    __block int sent = 0;
    void (^send)(void) = ^{
        NFSNativeNet *t = transport;
        if (!t->socket || !t->welcomed || t->stopped) return;
        NSURLSessionWebSocketTask *s = t->socket;
        [s sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:text] completionHandler:^(NSError *error){
            if (error) dispatch_async(t->queue, ^{ if (t->socket == s) [t lost]; });
        }];
        sent = 1;
    };
    if (dispatch_get_specific(&native_queue_key)) send();       /* (from a message of the link's own: its queue) */
    else dispatch_sync(transport->queue, send);
    return sent;
}
void native_net_shutdown(void){
    if (!transport) return;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL wait = NO;
    void (^closeLink)(void) = ^{
        transport->stopped = YES;
        NSURLSessionWebSocketTask *old = transport->socket; transport->socket = nil;
        if (old){ transport->closeWait = done; wait = YES; }
        [old cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:[@"closed" dataUsingEncoding:NSUTF8StringEncoding]];
        [transport lost];
        [transport->session finishTasksAndInvalidate];
        if (transport->timer){ dispatch_source_cancel(transport->timer); transport->timer = nil; }
    };
    if (dispatch_get_specific(&native_queue_key)) closeLink();
    else {
        dispatch_sync(transport->queue, closeLink);
        /* Give a normal process exit a bounded chance to release its reservation. */
        if (wait) dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 250000000));
    }
}
