// tests/keyboard_mac_unit.m - runtime/keyboard_mac.m's delivery rules without the game
// (tests/keyboard_unit.sh): keys held through a focus loss.  kbdmac_release_all() lets
// every held key go (nothing sticks), and a key still down is pressed again by its next
// autorepeat; a key up or a fresh press clears that, a key pressed with Command never
// reaches the game, not even by its repeats, and a lost key's repeats with Command are
// no shortcut and press nothing.  The kbd.h side is a stub that keeps the keys' state.
#import <Cocoa/Cocoa.h>
#include "kbd.h"
#include <stdio.h>

static int g_key[256], g_posts;
void kbd_set_key(int src, unsigned dik, int down){ (void)src; if (dik < 256) g_key[dik] = down; }
void kbd_release_source(int src){ (void)src; memset(g_key, 0, sizeof g_key); }
void kbd_post(uint32_t msg, uint32_t wp, uint32_t lp){ (void)msg; (void)wp; (void)lp; g_posts++; }
int kbd_log(void){ return getenv("KBD_LOG") != NULL; }
const char *kbd_msg_name(uint32_t msg){ (void)msg; return "msg"; }
int kbdmac_handle(NSEvent *ev);

static int fails;
static void check(int ok, const char *what){ printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails++; }

static int key(NSEventType t, uint16_t kc, int repeat, NSEventModifierFlags fl){
    NSEvent *ev = [NSEvent keyEventWithType:t location:NSZeroPoint modifierFlags:fl timestamp:0 windowNumber:0
                                    context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:repeat keyCode:kc];
    return kbdmac_handle(ev);
}
#define KC_UP    0x7E
#define KC_LEFT  0x7B
#define KC_W     0x0D
#define DIK_UP   0xC8
#define DIK_LEFT 0xCB
#define DIK_W    0x11
#define CMD      NSEventModifierFlagCommand

int main(void){
    @autoreleasepool {
        [NSApplication sharedApplication];
        key(NSEventTypeKeyDown, KC_UP, 0, 0); key(NSEventTypeKeyDown, KC_LEFT, 0, 0);
        check(g_key[DIK_UP] && g_key[DIK_LEFT], "Up and Left held");
        kbdmac_release_all("test: focus loss");
        check(!g_key[DIK_UP] && !g_key[DIK_LEFT], "a focus loss lets both go");
        key(NSEventTypeKeyDown, KC_UP, 1, 0); key(NSEventTypeKeyDown, KC_LEFT, 1, 0);
        check(g_key[DIK_UP] && g_key[DIK_LEFT], "focus back, still down: their next autorepeats press them again");
        key(NSEventTypeKeyUp, KC_UP, 0, 0); key(NSEventTypeKeyUp, KC_LEFT, 0, 0);
        check(!g_key[DIK_UP] && !g_key[DIK_LEFT], "their key ups let them go");
        key(NSEventTypeKeyDown, KC_UP, 1, 0);
        check(!g_key[DIK_UP], "a stray autorepeat after the key up presses nothing");
        // released while the focus was away (its key up comes to the app all the same)
        key(NSEventTypeKeyDown, KC_LEFT, 0, 0);
        kbdmac_release_all("test: focus loss");
        key(NSEventTypeKeyUp, KC_LEFT, 0, 0);
        key(NSEventTypeKeyDown, KC_LEFT, 1, 0);
        check(!g_key[DIK_LEFT], "a key released after the focus loss stays up");
        // pressed with Command: the app's, never the game's, not even by its repeats after Command
        int to_app = !key(NSEventTypeKeyDown, KC_W, 0, CMD);
        key(NSEventTypeKeyDown, KC_W, 1, 0);
        check(to_app && !g_key[DIK_W], "a key pressed with Command reaches the app, and its repeats nothing");
        key(NSEventTypeKeyUp, KC_W, 0, 0);
        // held through a focus loss, then Command: its repeats with Command are no shortcut, the next one without presses it
        key(NSEventTypeKeyDown, KC_UP, 0, 0);
        kbdmac_release_all("test: focus loss");
        int dropped = key(NSEventTypeKeyDown, KC_UP, 1, CMD);
        check(dropped && !g_key[DIK_UP], "a lost key's repeat with Command: dropped, no shortcut, not pressed");
        key(NSEventTypeKeyDown, KC_UP, 1, 0);
        check(g_key[DIK_UP], "... and its first repeat without Command presses it again");
        key(NSEventTypeKeyUp, KC_UP, 0, 0);
        // a fresh press after a focus loss is a press as ever
        key(NSEventTypeKeyDown, KC_LEFT, 0, 0);
        kbdmac_release_all("test: focus loss");
        key(NSEventTypeKeyDown, KC_LEFT, 0, 0);
        check(g_key[DIK_LEFT], "a fresh press after a focus loss");
        key(NSEventTypeKeyUp, KC_LEFT, 0, 0);
        check(!g_key[DIK_LEFT], "and its key up");
        printf(fails ? "keyboard_mac_unit: %d FAILED\n" : "keyboard_mac_unit: all passed\n", fails);
        return fails != 0;
    }
}
