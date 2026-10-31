/* Protocol-stack regression without a game or a network connection. */
#include "net_relay.h"
#include "net_native.h"
#include <assert.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
NetIdent g_ws_id;
int g_ws_mode = NET_VLAN;
static net_mailbox *mb;
int native_net_enabled(void){ return 1; }
net_mailbox *native_net_mailbox(uint32_t mode){
    if (!mb){ mb = aligned_alloc(64, NET_MAILBOX_BYTES); memset(mb, 0, NET_MAILBOX_BYTES);
        mb->mode = mode; mb->tx_off = NET_HDR_BYTES; mb->rx_off = NET_HDR_BYTES + NET_TX_SLOTS * NET_SLOT_BYTES;
        mb->vip = 0x0a4d0002u; mb->netmask = 0xffffff00u; mb->page_state = NET_PAGE_ONLINE;
        mb->peer_bits[0] = 12;
    }
    return mb;
}
void native_net_wait(int *w, int e, int64_t ns){ (void)w; (void)e; (void)ns; }
void guest_wait_begin(void){}
void guest_wait_end(void){}
int winsock_session_active(void){ return 1; }
uint64_t ws_now_us(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000; }
void ws_log(const char *fmt, ...){ (void)fmt; }
int ws_errno_to_wsa(int e){ return e; }
int relay_vlan_test_pump(void);
static uint32_t ip(unsigned x){ return 0x00004d0au | x << 24; }
static void inject(unsigned kind, unsigned op, uint32_t cid, unsigned sport, unsigned dport, const char *data){
    net_slot *s = (net_slot *)((uint8_t *)mb + mb->rx_off + (mb->rx_head % NET_RX_SLOTS) * NET_SLOT_BYTES);
    memset(s, 0, sizeof *s); s->kind = kind; s->src_ip = 0x0a4d0003; s->dst_ip = mb->vip;
    s->src_port = sport; s->dst_port = dport; s->len = NET_LAN_HDR + (data ? strlen(data) : 0);
    s->data[0] = op; memcpy(s->data + 4, &cid, 4); if (data) memcpy(s->data + NET_LAN_HDR, data, strlen(data));
    mb->rx_head++; relay_vlan_test_pump();
}
static WsSock sock(unsigned type){ WsSock s = {0}; s.type = type; s.fd = -1; s.ip_ttl = 64; assert(!relay_vlan_open(&s)); return s; }
int main(void){
    setenv("NFSU2_LAN_NOTHREAD", "1", 1);
    assert(!relay_vlan_hello("switch", &g_ws_id));
    assert(g_ws_id.ip == ip(2));
    WsSock u = sock(2), u2 = sock(2); int n; uint32_t from; uint16_t port; char buf[100];
    assert(!relay_vlan_bind(&u, 0, 3658)); assert(relay_vlan_bind(&u2, 0, 3658) == WSAEADDRINUSE);
    assert(!relay_vlan_bind(&u2, 0, 3659));
    assert(!relay_vlan_sendto(&u, (uint8_t *)"local", 5, ip(2), 3659, &n) && n == 5);
    assert(!relay_vlan_recvfrom(&u2, (uint8_t *)buf, sizeof buf, 0, &from, &port, &n));
    assert(n == 5 && !memcmp(buf, "local", 5) && port == 3658);
    inject(NET_KIND_LAN_UDP, NET_LAN_UDP_DATA, 0, 7777, 3658, "remote");
    assert(!relay_vlan_recvfrom(&u, (uint8_t *)buf, sizeof buf, 0, &from, &port, &n));
    assert(n == 6 && from == ip(3) && port == 7777);
    WsSock listener = sock(1), client = sock(1), accepted = {.fd = -1};
    assert(!relay_vlan_bind(&listener, 0, 20920)); assert(!relay_vlan_listen(&listener, 4));
    assert(!relay_vlan_connect(&client, ip(2), 20920)); assert(!relay_vlan_accept(&listener, &accepted));
    assert(vfd_send(client.fd, "stream", 6, 0) == 6); assert(vfd_recv(accepted.fd, buf, sizeof buf, 0) == 6 && !memcmp(buf, "stream", 6));
    assert(!vfd_shutdown(client.fd, SHUT_WR)); assert(vfd_recv(accepted.fd, buf, sizeof buf, 0) == 0);
    WsSock remote = sock(1); assert(!relay_vlan_connect(&remote, ip(3), 20922));
    inject(NET_KIND_LAN_TCP, NET_LAN_TCP_SYNACK, remote.conn_id, 20922, remote.lport, NULL);
    relay_vlan_conn_update(&remote); assert(!remote.conn_result);
    inject(NET_KIND_LAN_TCP, NET_LAN_TCP_DATA, remote.conn_id, 20922, remote.lport, "server");
    assert(vfd_recv(remote.fd, buf, sizeof buf, 0) == 6 && !memcmp(buf, "server", 6));
    mb->page_state = NET_PAGE_OFFLINE; relay_vlan_test_pump(); assert(relay_vlan_conn_was_reset(&remote));
    /* Host descriptors keep native semantics when the relay backend is linked. */
    int fd[2]; assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, fd)); assert(vfd_send(fd[0], "fd", 2, 0) == 2); assert(vfd_recv(fd[1], buf, sizeof buf, 0) == 2); vfd_close(fd[0]); vfd_close(fd[1]);
    puts("native relay UDP, local/remote TCP, FIN, link reset and host fds passed");
    return 0;
}
