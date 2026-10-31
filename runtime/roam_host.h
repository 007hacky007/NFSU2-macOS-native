/* roam_host.h -- free-roam multiplayer: what roam_game.c needs from its host
 * (the guest's memory is the 4 GB arena at g_mem, guest code is the lifted
 * C, called through dispatch_indirect).
 *
 *   MR8/MR16/MR32/MRF32(a)  guest memory as lvalues;  GPTR(a)  a host pointer
 *   rh_committed(a)         1 when guest address a is readable and writable
 *   rh_call(c, fn, ecx, edx, n, args)
 *                           call guest function fn with ecx/edx and n stack
 *                           arguments (any convention: the stack is restored
 *                           afterwards); returns eax.  Only from the main-loop
 *                           hook, on the game's thread
 *   rlog(fmt, ...)          one log line (printf format)
 *   rh_opt(name)            an option (NFSU2_ROAM_*), or NULL
 *   rh_frame()              the frame number (logs)
 *   rh_heap_mb()            guest heap in use, MB (0: not known here)
 *   rh_ns()                 a monotonic clock in ns (frame cost)
 *   rh_file, rh_fopen/rh_fprintf/rh_fflush   the pose log (test aid)
 *   rh_hud_marker(&x, &y)   a HUD marker's position (640x480 units from the
 *                           view's pixels) as the screen shows the HUD
 *   rh_no_profile(name)     1 when a profile name is the game's "No Profile"
 *                           (in the game's language)
 *   RH_FE_NODES             the most objects FEng draws of one package (its
 *                           level sorter's nodes)
 *   rh_horn_on()            horns are on (horn.h's horn_on)
 *   rh_horn_held()          1 while the horn key is held (horn.h's horn_held)
 *   rh_horn_mine()          the player's horn (horn.h's horn_mine), -1: none
 *   rh_horn_name(kind)      a horn's name (horn.h's horn_name)
 *   rh_horn_begin/rh_horn_sound/rh_horn_end
 *                           a frame of horns (horn.h's horn_begin, ...)
 *   rh_carsfx_begin/rh_carsfx_car/rh_carsfx_end
 *                           a frame of friends' engines, nitrous and hydraulics
 *                           (carsfx.h's carsfx_begin, ...)
 *
 * Ported from th0mk's nfsu2-web runtime/roam_host.h (MIT).
 */
#ifndef ROAM_HOST_H
#define ROAM_HOST_H
#include "cpu.h"
#include "horn.h"
#include "carsfx.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <mach/mach_time.h>

void dispatch_indirect(CPU *c, uint32_t addr);
long metal_frames(void);
void roam_hud_marker(float *x, float *y);    /* roam.c */
int  roam_no_profile(const char *name);      /* roam.c */

#define ROAM_HOOK_RET    GA(0x00581485u)     /* the return address guest calls see: the main-loop hook (roam.c) */
#define RH_FE_NODES      512                 /* objects FEng draws of one package: the game's level sorter */
#define GPTR(a)          (g_mem + (uint32_t)(a))
#define rh_committed(a)  mem_is_committed(a)
#define rlog(...)        fprintf(stderr, __VA_ARGS__)
#define rh_opt(k)        getenv(k)
#define rh_frame()       metal_frames()
#define rh_heap_mb()     0u
#define rh_hud_marker(x, y) roam_hud_marker((x), (y))
#define rh_no_profile(n) roam_no_profile(n)
#define rh_horn_on()     horn_on()
#define rh_horn_held()   horn_held()
#define rh_horn_mine()   horn_mine()
#define rh_horn_name(k)  horn_name(k)
#define rh_horn_begin(pos, fwd, vel)   horn_begin((pos), (fwd), (vel))
#define rh_horn_sound(who, name, kind, p, v) horn_sound((who), (name), (kind), (p), (v))
#define rh_horn_end()    horn_end()
#define rh_carsfx_begin(pos, fwd, vel)    carsfx_begin((pos), (fwd), (vel))
#define rh_carsfx_car(who, name, p, v, st) carsfx_car((who), (name), (p), (v), (st))
#define rh_carsfx_end()  carsfx_end()
typedef FILE rh_file;
#define rh_fopen(p)      fopen((p), "w")
#define rh_fprintf       fprintf
#define rh_fflush        fflush

static inline uint64_t rh_ns(void){
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return mach_absolute_time() * tb.numer / tb.denom;
}
/* call a guest function (any convention) from the main-loop hook; the CPU
 * state is restored afterwards */
static inline uint32_t rh_call(CPU *c, uint32_t fn, uint32_t ecx, uint32_t edx, int n, const uint32_t *arg){
    CPU save = *c;
    c->esp = (c->esp - 1024u) & ~15u;
    for (int i = n - 1; i >= 0; i--) PUSH32(arg[i]);
    c->ecx = ecx; c->edx = edx;
    PUSH32(ROAM_HOOK_RET);
    dispatch_indirect(c, fn);
    uint32_t r = c->eax;
    *c = save;
    return r;
}
#endif
