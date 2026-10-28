#import <Foundation/Foundation.h>
#include "net_native.h"
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
        net_mailbox *m = native_net_mailbox(NET_MODE_VLAN);
        assert(m);
        m->port = 47210;
        __atomic_store_n(&m->want, 1, __ATOMIC_SEQ_CST);
        for (int i = 0; i < 500 && __atomic_load_n(&m->page_state, __ATOMIC_SEQ_CST) != NET_PAGE_ONLINE; i++) usleep(10000);
        assert(m->page_state == NET_PAGE_ONLINE);
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
        if (second){
            __atomic_store_n(&m->tx_head, 1, __ATOMIC_SEQ_CST);
            for (int i = 0; i < 500 && !__atomic_load_n(&m->tx_tail, __ATOMIC_SEQ_CST); i++) usleep(10000);
            assert(m->tx_tail == 1);
        }
        if (argc > 2 && !strcmp(argv[2], "resume")){
            for (int i = 0; i < 1000 && __atomic_load_n(&m->generation, __ATOMIC_SEQ_CST) < 2; i++) usleep(10000);
            assert(m->generation == 2);
        }
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
