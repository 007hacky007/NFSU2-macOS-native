/* sndlead.c -- after a load the game's sound is back to its usual delay in a
 * few seconds, not half a minute.
 *
 * The game mixes all its sound into one looping DirectSound buffer, which
 * runtime/audio.m plays.  A thread of its own (0x7263c7:
 * timeBeginPeriod(1), then a wake-up every 10 ms) writes the next part each
 * time (0x7260f7): up to the buffer's WRITE cursor (it asks for no play
 * cursor) plus 30 ms (float [0x8183dc]) plus a margin (float [0x8183ec]; int
 * copy word [0x8183e0]; 15 ms at the start, 10..200 ms: [0x784560],
 * [0x8183e8]).  Everything written ahead of the mixer is heard that much later:
 * a menu click, the engine, a crash.
 *
 * The margin is how late the thread has been: the longest it went between two
 * wake-ups (gaps over 300 ms not counted) raises it at once, and every 3000
 * wake-ups (word [0x8183e4] counts them down; 1000 the first time) it falls
 * to the longest gap of those (int [0x8183f4], 10 at the window's start).  On
 * Windows the thread runs beside the game's and the margin stays near
 * 10-15 ms.  Here it waits for the guest lock behind the game's thread, and a
 * load holds that for long stretches: in a quick race (2026-10-24) the boot's
 * 84 ms gap kept every sound 84 ms later for the first 40 s, the race's load
 * 35 ms for a minute.
 *
 * Here the window is 300 wake-ups (3 s).  A late wake-up still raises the
 * margin at once.  Original: 3000 (30 s).  The addresses are the same in the
 * European and the North American build; GA() keeps them in step anyway.
 * Ported from th0mk's nfsu2-web runtime/sndlead.c (MIT). */
#include "cpu.h"

#define WINDOW_TICKS 300

/* Called from guest_hook (debug.c); tools/gen_v2.sh lifts the hook site. */
int sndlead_hook(CPU *c, uint32_t ip){
    (void)c;
    /* after mov word [0x8183e4], 0xbb8: the next window, shorter */
    if (ip != GA(0x00726336u)) return 0;
    MR16(GA(0x008183e4u)) = WINDOW_TICKS;
    return 1;
}
