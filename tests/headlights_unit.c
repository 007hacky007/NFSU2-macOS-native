#include "cpu.h"
#include "headlights.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
static HeadlightsBlock block;
static int original_calls;
void metal_headlights(const HeadlightsBlock *value) { block = *value; }
void sub_005d6d20_orig(CPU *c) { (void)c; original_calls++; }
int roam_game_friend_car(uint32_t car) { return car == 0x21000; }
void headlights_view(uint32_t id, const float *plat);
void headlights_vs_ramp(float s, float o);
int headlights_set(const char *mode);
void sub_005d6d20(CPU *c);

static void car(uint32_t at, uint32_t next, int driver, uint32_t color, float x) {
    MR32(at) = next; MR32(at + 0x24) = driver; MRF32(at + 0x50) = x;
    for (int i = 0; i < 3; i++) MRF32(at + 0xd0 + i * 20) = 1;
    MR8(at + 0x550) = 1; MR32(at + 0x554) = at + 0x1000;
    MR32(at + 0x1000 + 0x380) = color;
}
int main(void) {
    g_mem = calloc(1, 16 * 1024 * 1024); assert(g_mem);
    memset(g_cbits, 255, sizeof g_cbits);
    CPU cpu = {0}; cpu.esp = 0x1000; cpu.ecx = 0x12000;
    MR32(cpu.esp + 4) = 0x008331d0; MR32(cpu.esp + 8) = 0x00488b90;
    MR32(0x008900b4) = 0x10000; MR32(0x10004) = 0x20000;
    MR32(0x00890080) = 0x11000; MR32(0x11000) = 0x20000;
    MR32(0x00870cc4) = 1;
    car(0x20000, 0x21000, 1, 0xffffff, 0);
    car(0x21000, 0x23000, 3, 0x0000ff, 2);
    car(0x23000, 0x11000, 4, 0x00ff00, 4);
    float plat[48] = {0}; for (int i = 0; i < 4; i++) plat[32 + 5 * i] = 1;
    headlights_view(9, plat); headlights_vs_ramp(0.01f, 0.25f);
    assert(headlights_set("players")); sub_005d6d20(&cpu);
    assert(block.n == 1 && fabsf(block.l[0].col[0] - 0.6f) < 1e-6f && block.l[0].col[1] == 0);
    assert(block.s == 0.01f && block.o == 0.25f);
    assert(block.l[0].t[3] == -2 && block.l[0].t[0] == 1);
    assert(headlights_set("all")); sub_005d6d20(&cpu);
    assert(block.n == 2 && block.l[1].col[1] > 0.59f);
    assert(headlights_set("off")); sub_005d6d20(&cpu); assert(block.n == 0);
    assert(headlights_set("all")); MR32(0x00870cc4) = 0; sub_005d6d20(&cpu); assert(block.n == 0);
    MR32(0x00870cc4) = 1; MR8(0x21000 + 0x998) = 1;
    sub_005d6d20(&cpu); assert(block.n == 1 && block.l[0].col[1] > 0.59f);
    assert(!headlights_set("invalid"));
    assert(original_calls == 5);
    MR8(0x21000 + 0x998) = 0;
    MRF32(0x21000 + 0x50) = 200;
    sub_005d6d20(&cpu); assert(block.n == 1 && block.l[0].col[1] > 0.59f);
    assert(headlights_set("players"));
    MR32(0x00850078) = 0x200;
    MRF32(0x21000 + 0x50) = 2;
    sub_005d6d20(&cpu); assert(block.n == 1 && block.l[0].col[0] > 0.59f);
    MR32(0x11000) = 0x40000;
    for (unsigned i = 0; i < 12; i++) {
        uint32_t at = 0x40000 + 0x2000 * i;
        car(at, i == 11 ? 0x11000 : at + 0x2000, 3, 0xffffff, (float)(12 - i));
    }
    assert(headlights_set("all")); sub_005d6d20(&cpu); assert(block.n == 8);
    assert(block.l[0].t[3] == -1 && block.l[7].t[3] == -8);

    free(g_mem);
    puts("headlights_unit: players/all/off selection, disabled/blink/far exclusions, nearest eight and projector transform passed");
}
