/* horn.h -- horns between players: the horn key and the horns in the sound
 * output (horn.c).  Free roam (roam_game.c) and network races (racehorn.c)
 * say which horns sound where; the mixer (audio.m) adds them to its mix.
 *
 * Ported from th0mk's nfsu2-web runtime/horn.h (MIT). */
#ifndef HORN_H
#define HORN_H
#include <stdint.h>

#define HORN_VOICES 8                /* the player's horn and 7 others' */
/* the kinds of horn, by number on the wire (roam_game.c's car look,
 * racehorn.c's message): 0 dual, 1 single, 2 truck, 3 train, 4 klaxon,
 * 5 cucaracha, 6 clown, 7 trombone.  A number past them (a newer build's)
 * sounds as the dual horn. */
#define HORN_KINDS  8

/* 1 when horns are on (NFSU2_HORN names a horn: the launcher's Horn
 * picker); off, as in the original game, nothing here sounds or is sent. */
int  horn_on(void);
/* 1 while the horn key (N) is held and horns are on.  Game thread. */
int  horn_held(void);
/* The player's own kind, as NFSU2_HORN names it (a name of none: the dual
 * one), -1 while horns are off.  And a kind's name. */
int  horn_mine(void);
const char *horn_name(int kind);
/* A frame of horns, on the game thread: horn_begin with the listener (the
 * camera's position and forward, and the player's car's velocity, m and
 * m/s; pos 0: nobody else's horn can sound), horn_sound for every horn that
 * sounds now, then horn_end: a horn not sounded since horn_begin fades out.
 * who names the horn's source (one voice each), name picks its pitch (one
 * of five: a player sounds the same on every screen), kind its sound.  p
 * and v: where the car is and how it moves; p 0: the player's own horn.
 * horn_sound returns 1 when that horn starts now, 0 while it goes on, -1
 * when it is out of hearing or out of voices. */
void horn_begin(const float *pos, const float *fwd, const float *vel);
int  horn_sound(uint32_t who, const char *name, int kind, const float *p, const float *v);
void horn_end(void);
/* The player's own horn for a moment (a quarter of a second, or until the
 * next horn_end): how loud the volume makes it.  Game thread. */
void horn_preview(void);
/* How loud every horn is, HORN_VOL_MIN .. 1 (1: as made, the default);
 * a value out of that range is taken as its nearer end.  Any thread. */
#define HORN_VOL_MIN 0.1f
void horn_set_volume(float v);
/* Adds the sounding voices to an interleaved stereo float mix.  Mixer
 * thread. */
void horn_mix(float *acc, unsigned frames, unsigned rate);
#endif
