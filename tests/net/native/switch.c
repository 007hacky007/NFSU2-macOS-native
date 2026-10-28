/* Run against the donor Rust relay on loopback: actual Online host login. */
#include "net_relay.h"
#include "net_native.h"
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
NetIdent g_ws_id;
int g_ws_mode = NET_VLAN;
void guest_wait_begin(void){}
void guest_wait_end(void){}
int winsock_session_active(void){ return 1; }
uint64_t ws_now_us(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000 + t.tv_nsec / 1000; }
void ws_log(const char *fmt, ...){ va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap); fputc('\n', stderr); }
int ws_errno_to_wsa(int e){ return e; }
static void message(int fd, const char *kind, const char *body){
    uint8_t frame[1024] = {0}; size_t len = strlen(body) + 13; assert(len <= sizeof frame);
    memcpy(frame, kind, 4); memcpy(frame + 12, body, len - 13); uint32_t n = htonl((uint32_t)len); memcpy(frame + 8, &n, 4);
    assert(vfd_send(fd, frame, len, 0) == (ssize_t)len);
}
int main(int argc, char **argv){
    assert(argc == 2); assert(native_net_url_valid(argv[1]));
    setenv("NFSU2_NET", "online", 1); setenv("NFSU2_SERVER_URL", argv[1], 1); setenv("NFSU2_ROAM_NAME", "FixtureNative", 1);
    assert(!relay_vlan_hello("switch", &g_ws_id));
    net_mailbox *m = native_net_mailbox(NET_MODE_LAN);
    for (int i = 0; i < 500 && !(m->peer_bits[0] & 2); i++) usleep(10000);
    assert(m->peer_bits[0] & 2);       /* The actual Online host is on the list. */
    WsSock s = { .type = 1, .fd = -1, .ip_ttl = 64 };
    assert(!relay_vlan_open(&s)); assert(!relay_vlan_connect(&s, htonl(0x0a4d0001), 20922));
    for (int i = 0; i < 500; i++){ relay_vlan_conn_update(&s); if (s.conn_ready_us <= ws_now_us()) break; usleep(10000); }
    assert(s.conn_ready_us <= ws_now_us() && !s.conn_result);
    message(s.fd, "auth", "NAME=FixtureNative\nPASS=x\n");
    message(s.fd, "pers", "PERS=FixtureNative\n");
    uint8_t data[16384]; size_t len = 0; int auth = 0, persona = 0;
    for (int i = 0; i < 500 && !persona; i++){
        ssize_t n = vfd_recv(s.fd, data + len, sizeof data - len, 0);
        if (n < 0){ assert(errno == EAGAIN); usleep(10000); continue; }
        assert(n > 0); len += (size_t)n;
        while (len >= 12){
            uint32_t size; memcpy(&size, data + 8, 4); size = ntohl(size); assert(size >= 12 && size < sizeof data);
            if (len < size) break;
            if (!memcmp(data, "auth", 4)){ assert(!memcmp(data + 4, "\0\0\0\0", 4)); auth = 1; }
            if (!memcmp(data, "pers", 4)){ assert(!memcmp(data + 4, "\0\0\0\0", 4)); persona = 1; }
            len -= size; memmove(data, data + size, len);
        }
    }
    assert(auth && persona);
    relay_vlan_close(&s, 0); vfd_close(s.fd); relay_vlan_session_end(); native_net_shutdown();
    puts("native transport and guest TCP authenticated to the real local Rust Online lobby");
    return 0;
}
