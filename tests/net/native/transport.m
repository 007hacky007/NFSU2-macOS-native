/* Native WebSocket transport (runtime/net_native.m) on loopback, driven by
 * tests/net/native/loopback.py: URL validation without arguments; with a
 * ws://127.0.0.1 URL, the handshake, the welcome, a UDP datagram each way
 * through the mailbox, and (second argument) relay (also the round trip of
 * a ping), resume, queue (the place in the line), idle, burst, big (a peer
 * list of a full server keeps the link), claim (the launcher's token in the
 * hello), atexit or the second of two clients. */
#import <Foundation/Foundation.h>
#include "net_native.h"
#include "netstats.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv){
    @autoreleasepool {
        assert(native_net_url_valid("wss://example.invalid/lan"));
        assert(native_net_url_valid("ws://127.0.0.1:19091/lan?queue&resume"));
        assert(!native_net_url_valid("https://example.invalid/lan"));
        assert(!native_net_url_valid("wss://user:secret@example.invalid/lan"));
        assert(!native_net_url_valid("wss://example.invalid/lan#fragment"));
        assert(!native_net_url_valid("wss:///lan"));
        assert(!native_net_url_valid("ws://example.invalid/lan"));
        assert(!native_net_enabled());
        if (argc == 1){ puts("native transport URL validation passed"); return 0; }
        setenv("NFSU2_NET", "online", 1);
        setenv("NFSU2_SERVER_URL", argv[1], 1);
        setenv("NFSU2_ROAM_NAME", "fixture-player", 1);
        assert(native_net_enabled());
        if (argc > 2 && !strcmp(argv[2], "lanports")){
            /* LAN play open before the link: the hello says it, with the ports bound so far (9999) */
            net_mailbox *l = native_net_mailbox(NET_MODE_LAN); assert(l);
            __atomic_store_n(&l->udp_ports, NET_UDP_PORTS_SET | 1u << (9999 % 31), __ATOMIC_SEQ_CST);
            __atomic_store_n(&l->want, 1, __ATOMIC_SEQ_CST);
        }
        net_mailbox *m = native_net_mailbox(NET_MODE_VLAN);
        assert(m);
        m->port = 47210;
        __atomic_store_n(&m->want, 1, __ATOMIC_SEQ_CST);
        int queue = argc > 2 && !strcmp(argv[2], "queue"), saw_queue = 0;
        native_net_status ns;
        for (int i = 0; i < 500 && __atomic_load_n(&m->page_state, __ATOMIC_SEQ_CST) != NET_PAGE_ONLINE; i++){
            native_net_get_status(&ns);
            saw_queue |= ns.state == NETSTATS_QUEUED && ns.queue_pos == 1 && ns.queue_of == 2;
            usleep(10000);
        }
        assert(m->page_state == NET_PAGE_ONLINE);
        /* the statistics panel's view of the link (netstats.m): connected, the queue's place seen while in it */
        native_net_get_status(&ns);
        assert(ns.state == NETSTATS_CONNECTED && ns.queue_pos == 0);
        if (queue) assert(saw_queue);
        int second = argc > 2 && !strcmp(argv[2], "second");
        assert(m->vip == (second ? 0x0a4d0003u : 0x0a4d0002u));
        assert(m->netmask == 0xffffff00u);
        net_slot *s = (net_slot *)((uint8_t *)m + m->tx_off);
        s->kind = NET_KIND_UDP; s->dst_ip = second ? 0x0a4d0002u : 0x0a4d0003u; s->src_port = s->dst_port = 47210;
        s->len = 4; memcpy(s->data, second ? "pong" : "ping", 4);
        if (!second) __atomic_store_n(&m->tx_head, 1, __ATOMIC_SEQ_CST);
        for (int i = 0; i < 500 && !__atomic_load_n(&m->rx_head, __ATOMIC_SEQ_CST); i++) usleep(10000);
        assert(m->rx_head == 1);
        s = (net_slot *)((uint8_t *)m + m->rx_off);
        assert(s->kind == NET_KIND_UDP && s->src_ip == (second ? 0x0a4d0002u : 0x0a4d0003u) && s->dst_ip == m->vip);
        assert(s->len == 4 && memcmp(s->data, second ? "ping" : "pong", 4) == 0);
        if (argc > 2 && !strcmp(argv[2], "relay")){
            /* relay: the fixture answers the pings; their round trip in the mailbox and the panel's status */
            double rtt = -1;
            for (int i = 0; i < 500; i++){
                native_net_get_status(&ns);
                __atomic_load(&m->switch_rtt_ms, &rtt, __ATOMIC_SEQ_CST);
                if (ns.rtt_ms >= 0 && rtt >= 0) break;
                usleep(10000);
            }
            assert(ns.rtt_ms >= 0 && ns.rtt_ms < 1000 && rtt >= 0 && rtt < 1000);
            printf("round trip %d ms\n", ns.rtt_ms);
        }
        if (second){
            __atomic_store_n(&m->tx_head, 1, __ATOMIC_SEQ_CST);
            for (int i = 0; i < 500 && !__atomic_load_n(&m->tx_tail, __ATOMIC_SEQ_CST); i++) usleep(10000);
            assert(m->tx_tail == 1);
        }
        if (argc > 2 && !strcmp(argv[2], "resume")){
            for (int i = 0; i < 1000 && __atomic_load_n(&m->generation, __ATOMIC_SEQ_CST) < 2; i++) usleep(10000);
            assert(m->generation == 2);
        }
        if (argc > 2 && !strcmp(argv[2], "big")) assert(m->generation == 1);
        if (argc > 2 && !strcmp(argv[2], "claim")) assert(native_net_has_claim() && !getenv("NFSU2_CLAIM_FD"));
        else assert(!native_net_has_claim());
        if (argc > 2 && !strcmp(argv[2], "burst")){
            net_mailbox *other = native_net_mailbox(NET_MODE_LAN); assert(other);
            __atomic_store_n(&other->want, 1, __ATOMIC_SEQ_CST);
            for (unsigned i = 0; i < NET_TX_SLOTS; i++){
                net_slot *a = (net_slot *)((uint8_t *)m + m->tx_off + ((i + 1) % NET_TX_SLOTS) * NET_SLOT_BYTES);
                net_slot *b = (net_slot *)((uint8_t *)other + other->tx_off + i * NET_SLOT_BYTES);
                memset(a, 0, sizeof *a); a->kind = NET_KIND_UDP; a->dst_ip = 0x0a4d0003u; a->len = 4; memcpy(a->data, "load", 4);
                *b = *a; b->kind = NET_KIND_LAN_UDP;
            }
            __atomic_store_n(&m->tx_head, NET_TX_SLOTS + 1, __ATOMIC_SEQ_CST);
            __atomic_store_n(&other->tx_head, NET_TX_SLOTS, __ATOMIC_SEQ_CST);
            for (int i = 0; i < 500 && (m->tx_tail != NET_TX_SLOTS + 1 || other->tx_tail != NET_TX_SLOTS); i++) usleep(10000);
            assert(m->tx_tail == NET_TX_SLOTS + 1 && other->tx_tail == NET_TX_SLOTS);
        }
        if (argc > 2 && !strcmp(argv[2], "lanports")){
            /* LAN play open with its sockets' ports said (net_relay.c udp_ports): the hello carries them; then the
             * peer list as changes (the fixture's delta) and the ports again in {"t":"lan"} when they change */
            net_mailbox *l = native_net_mailbox(NET_MODE_LAN); assert(l);
            for (int i = 0; i < 500 && __atomic_load_n(&l->page_state, __ATOMIC_SEQ_CST) != NET_PAGE_ONLINE; i++) usleep(10000);
            /* the whole list (2, 3) is there; the delta: 3 gone, 5 in */
            for (int i = 0; i < 500 && !(__atomic_load_n(&l->peer_bits[0], __ATOMIC_SEQ_CST) & (1u << 5)); i++) usleep(10000);
            uint32_t bits = __atomic_load_n(&l->peer_bits[0], __ATOMIC_SEQ_CST);
            assert((bits & (1u << 2)) && !(bits & (1u << 3)) && (bits & (1u << 5)) && l->switch_peers == 2);
            /* 3 left: LAN play's TCP from it is reset (a GONE made here, never taken from the wire) */
            for (int i = 0; i < 500 && !__atomic_load_n(&l->rx_head, __ATOMIC_SEQ_CST); i++) usleep(10000);
            net_slot *g = (net_slot *)((uint8_t *)l + l->rx_off);
            assert(l->rx_head == 1 && g->kind == NET_KIND_LAN_TCP && g->src_ip == 0x0a4d0003u && g->data[0] == NET_LAN_TCP_GONE);
            __atomic_store_n(&l->udp_ports, NET_UDP_PORTS_SET | 1u << (3658 % 31), __ATOMIC_SEQ_CST);
            /* the fixture says when it had the new ports: a peer list naming 9 */
            for (int i = 0; i < 500 && !(__atomic_load_n(&l->peer_bits[0], __ATOMIC_SEQ_CST) & (1u << 9)); i++) usleep(10000);
            assert(__atomic_load_n(&l->peer_bits[0], __ATOMIC_SEQ_CST) & (1u << 9));
        }
        if (argc > 2 && !strcmp(argv[2], "idle")){
            __atomic_store_n(&m->want, 0, __ATOMIC_SEQ_CST);
            for (int i = 0; i < 800 && __atomic_load_n(&m->page_state, __ATOMIC_SEQ_CST) != NET_PAGE_IDLE; i++) usleep(10000);
            assert(m->page_state == NET_PAGE_IDLE);
        }
        puts("native WebSocket handshake and relay passed");
        if (!(argc > 2 && !strcmp(argv[2], "atexit"))) native_net_shutdown();
    }
    return 0;
}
