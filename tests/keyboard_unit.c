/* keyboard_unit.c -- runtime/keyboard.c and runtime/dikeys.c without the game
 * (tests/keyboard_unit.sh): the key state of several sources, the buffered
 * DirectInput event ring (a tap between two polls is not lost, an overrun is
 * reported), the host window-message queue (peek and take, mouse moves
 * coalesced) and the key names of the Controls page.
 * Exit status 0 when every check passes. */
#include "kbd.h"
#include <stdio.h>
#include <string.h>

uint32_t host_ms(void){ static uint32_t t = 1000; return t += 16; }   /* win32.c's clock */
const char *dik_name(unsigned dik);                                    /* dikeys.c */

static int g_fail;
static void check(const char *what, int ok){
    printf("  %s  %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) g_fail++;
}

int main(void){
    printf("key state\n");
    kbd_set_key(KSRC_HOST, 0x24, 1);
    kbd_set_key(KSRC_LEGACY, 0x24, 1);
    kbd_set_key(KSRC_HOST, 0x24, 0);
    check("a key is down while any source holds it", kbd_key_down(0x24));
    kbd_set_key(KSRC_LEGACY, 0x24, 0);
    check("and up once every source lets go", !kbd_key_down(0x24));
    uint8_t st[256];
    kbd_set_key(KSRC_TAP, 0x1c, 1); kbd_state(st, 256);
    check("kbd_state: 0x80 for a key down", st[0x1c] == 0x80 && st[0x1d] == 0);
    kbd_release_source(KSRC_TAP);
    check("a source's keys released together", !kbd_key_down(0x1c));

    printf("buffered events\n");
    uint32_t cur = kbd_ev_head();
    kbd_set_key(KSRC_HOST, 0x39, 1); kbd_set_key(KSRC_HOST, 0x39, 0);   /* a tap between two polls */
    KbdEv e1, e2;
    int g1 = kbd_ev_get(cur, &e1), g2 = kbd_ev_get(cur + 1, &e2);
    check("a quick tap is two events, down then up", g1 == 1 && g2 == 1 && e1.dik == 0x39 && e1.down && !e2.down);
    check("in order, timestamped", e2.seq == e1.seq + 1 && e2.ms > e1.ms);
    check("nothing beyond the head yet", kbd_ev_get(kbd_ev_head(), &e1) == 0);
    for (int i = 0; i < 1100; i++) kbd_set_key(KSRC_HOST, 0x10, i & 1 ? 0 : 1);
    check("a reader 1100 events behind sees the overrun", kbd_ev_get(cur, &e1) == -1);
    kbd_set_key(KSRC_HOST, 0x10, 0);
    uint32_t h = kbd_ev_head();
    kbd_set_key(KSRC_HOST, 0x10, 0);
    check("no event when nothing changes", kbd_ev_head() == h);

    printf("window messages\n");
    uint32_t m, wp, lp;
    kbd_post(0x0100, 0x41, 0x001e0001); kbd_post(0x0102, 'a', 0x001e0001);
    kbd_post_mousemove(0, 5); kbd_post_mousemove(0, 9);
    check("peek leaves the message", kbd_take_msg(0, &m, &wp, &lp) && m == 0x0100 && kbd_take_msg(0, &m, &wp, &lp) && m == 0x0100);
    check("take: WM_KEYDOWN, then WM_CHAR", kbd_take_msg(1, &m, &wp, &lp) && m == 0x0100 && wp == 0x41
          && kbd_take_msg(1, &m, &wp, &lp) && m == 0x0102 && wp == 'a');
    check("mouse moves coalesced into the newest", kbd_take_msg(1, &m, &wp, &lp) && m == 0x0200 && lp == 9
          && !kbd_take_msg(1, &m, &wp, &lp));

    printf("key names\n");
    check("Option, Command, Clear (Mac names)", !strcmp(dik_name(0x38), "Option") && !strcmp(dik_name(0xdb), "Command")
          && !strcmp(dik_name(0x45), "Clear"));
    check("a key a PC keyboard lacks has none", dik_name(0x54) == 0);
    printf("%s\n", g_fail ? "FAILED" : "all passed");
    return g_fail ? 1 : 0;
}
