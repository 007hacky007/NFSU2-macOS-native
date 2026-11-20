/* reverselights.c -- white reverse lights: a car's brake-light glows turn
 * white while it reverses.
 *
 * The game has no reverse lights: its cars know headlights and brake lights
 * only (the light flares LEFT_/RIGHT_/CENTRE_BRAKELIGHT, the lens textures
 * BRAKELIGHT and BRAKELIGHT_OFF), and nothing it does depends on the reverse
 * gear.  So the two rear lamps the cars have, the brake lights, are the
 * reverse lights here: while a car goes backwards in reverse gear, their glows
 * are drawn white and at full strength.  The lens textures stay the game's
 * (both its "on" and "off" are red), and so does the centre brake light, which
 * glows only while braking.
 *
 * The game's code (European v1.2 addresses; the North American ones through
 * GA() and build_na.h):
 *   0x615640 (NA 0x615630) CarRenderInfo::RenderFlares, thiscall (ecx = the
 *     render info, whose +0 is its Car or 0; 6 arguments, ret 0x18): every
 *     light flare of the car (the list at +0x3F0, a flare's +8 its name hash)
 *     through eRenderLightFlare.  Brake lights: the left and right ones always
 *     at 0.85 (the tail lights), 1.0 while the car's brake-light byte (+0x944,
 *     0x5F62C0: the brake pedal held) is set; the centre one only then.  The
 *     headlights pass the car's headlight colour, the brake lights 0 (their
 *     own red).
 *   0x490920 eRenderLightFlare, cdecl (view, flare, matrix, float intensity,
 *     int, int, float, uint32 colour): a colour other than 0 is the glow's RGB
 *     (0x4915F6: alpha from the intensity << 24 | colour), 0 the flare's own.
 *   Car +0x434 its gear (0 reverse, 1 neutral, 2 first ...), +0x42C its speed
 *     along its heading, m/s (negative backwards).  Holding brake to reverse
 *     puts the car in gear 0 and the brake pedal is then its throttle (the
 *     brake-light byte off); letting go puts it back in first while it still
 *     rolls back (measured: a quick race, the chase camera).
 *
 * NFSU2_REVERSE_LIGHTS=1|on (the launcher's "Reverse lights"): on.  Off by
 * default: the game's own red tail lights whatever the gear. */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define CAR_SPEED      0x42cu        /* float, m/s along the heading */
#define CAR_GEAR       0x434u        /* int: 0 reverse */
#define FLARE_NAME     0x8u          /* eLightFlare: name hash */
#define H_LEFT_BRAKE   0x31a66786u   /* bStringHash("LEFT_BRAKELIGHT") */
#define H_RIGHT_BRAKE  0xbf700a79u   /* bStringHash("RIGHT_BRAKELIGHT") */
#define REV_COLOUR     0x00ffffffu   /* the glow's RGB while reversing */
#define REV_SPEED      -0.1f         /* m/s: going backwards */

static unsigned long g_cars, g_glows;  /* reversing cars' flare passes, white glows drawn */
static int g_reversing;              /* the car whose flares are being drawn reverses */

static int rl_on(void){
    static int on = -1;
    if (on < 0){
        const char *e = getenv("NFSU2_REVERSE_LIGHTS");
        on = e && (*e == '1' || !strcasecmp(e, "on") || !strcasecmp(e, "yes") || !strcasecmp(e, "true"));
        if (on) fprintf(stderr, "[reverselights] on: brake-light glows turn white in reverse\n");
    }
    return on;
}

/* the car reverses: in reverse gear and going backwards */
static int reversing(uint32_t car){
    if (!car) return 0;
    float v = MRF32(car + CAR_SPEED);
    return MR32(car + CAR_GEAR) == 0u && v < REV_SPEED;
}

void sub_00615640_orig(CPU *c);
void sub_00615640(CPU *c){                  /* thiscall (CarRenderInfo *ecx, 6 args) */
    if (!rl_on()){ sub_00615640_orig(c); return; }
    uint32_t info = c->ecx, car = info ? MR32(info) : 0u;
    int was = g_reversing;
    g_reversing = reversing(car);
    if (g_reversing) g_cars++;
    sub_00615640_orig(c);
    g_reversing = was;
}

void sub_00490920_orig(CPU *c);
void sub_00490920(CPU *c){                  /* cdecl (view, flare, matrix, intensity, int, int, float, colour) */
    if (g_reversing){
        uint32_t flare = MR32(c->esp + 8u), h = flare ? MR32(flare + FLARE_NAME) : 0u;
        if (h == H_LEFT_BRAKE || h == H_RIGHT_BRAKE){
            MR32(c->esp + 0x20u) = REV_COLOUR;
            if (MRF32(c->esp + 0x10u) < 1.f) MRF32(c->esp + 0x10u) = 1.f;
            g_glows++;
        }
    }
    sub_00490920_orig(c);
}

void rl_report(void){
    if (rl_on())
        fprintf(stderr, "  reverse lights   : %lu reversing car frame(s), %lu white glow(s) drawn\n", g_cars, g_glows);
}
