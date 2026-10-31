/* radio_native.h -- a music folder through EA Trax: the words radio.c and the decoder (radio_native.m) share,
 * and the music controls (the app menu's Music submenu, and any other panel that wants them).
 *
 * radio.c runs on the game's sound thread and asks for a track when the game starts an EA Trax song; the
 * decoder thread answers with the track's tags and writes its sound into two rings.  Every word of RadioStatus
 * is read and written under radio_native_lock or with the atomics noted.
 *
 * The status words are from th0mk's nfsu2-web runtime/web/radio_proto.h (MIT). */
#ifndef NFSU2_RADIO_NATIVE_H
#define NFSU2_RADIO_NATIVE_H
#include <stdint.h>

#define RADIO_TRACKS 27            /* the game's EA Trax table */
#define RADIO_PLACES 2             /* 0 menus, 1 driving */
#define RADIO_TAG    44            /* bytes of one line of text: the plaque's 40 characters and the NUL, in whole words */
#define RADIO_RATE   44100         /* the rings' rate */

typedef struct {
    uint32_t on;                   /* odd: on.  Every switch adds one, so radio.c starts afresh at each switch-on; it adds one itself when it cannot go on */
    struct {                       /* written by the decoder: the next track of each place */
        uint32_t tag_seq;          /* sequence lock of offer_text, odd while the decoder writes; 0: no text yet */
        uint32_t places;           /* bit k: the decoder has a track for place k */
    } offer;
    struct {                       /* written by radio.c: the game started a song */
        uint32_t req_seq;          /* counts the requests */
        uint32_t req_index;        /* the place */
    } request;
    struct {                       /* written by the decoder: the track of request req_seq */
        uint32_t ready_seq;        /* the decoder serves track req_seq: total is set and written counts from 0 */
        uint32_t failed_seq;       /* the decoder cannot serve track req_seq */
        uint32_t total;            /* frames of the track; lowered to `read` to end the track early (Next Track) */
        uint32_t written;          /* frames written since the track began */
    } reply;
    struct {                       /* two rings of floats (left, then right), RADIO_RATE */
        uint32_t ring;             /* nonzero once radio.c has bound its rings (radio_native_bind_ring) */
        uint32_t ring_frames;      /* a power of two */
        uint32_t read;             /* frames taken by radio.c */
    } rings;
    char offer_text[RADIO_PLACES][3][RADIO_TAG];   /* per place: artist, title, album, NUL-padded ASCII */
} RadioStatus;

/* ---- the music controls: they only change state, the decoder and radio.c follow ----
 * folder: a music folder was chosen in the launcher (NFSU2_RADIO=1, NFSU2_MUSIC_FOLDER=<absolute path>);
 * enabled: EA Trax plays the folder now (0: the game's own soundtrack); tracks: the folder's tracks that play;
 * artist, title: the track playing or last played. */
typedef struct {
    int folder, enabled, paused, shuffle, tracks;
    char artist[RADIO_TAG], title[RADIO_TAG];
} RadioNativeSnapshot;

void radio_native_snapshot(RadioNativeSnapshot *out);
void radio_native_set_enabled(int enabled);     /* 1: the music folder, 0: back to the game soundtrack */
void radio_native_set_paused(int paused);       /* the folder's track; the game's own pause applies as well */
void radio_native_set_shuffle(int shuffle);
void radio_native_next(void);                   /* ends the track playing, EA Trax starts the next one */
static inline void radio_native_toggle_pause(void){ RadioNativeSnapshot s; radio_native_snapshot(&s); radio_native_set_paused(!s.paused); }
static inline void radio_native_toggle_shuffle(void){ RadioNativeSnapshot s; radio_native_snapshot(&s); radio_native_set_shuffle(!s.shuffle); }

/* ---- the decoder's life ---- */
int radio_native_wanted(void);                  /* a music folder was chosen: radio.c's wrappers do their work */
void radio_native_init(void);                   /* starts the decoder (radio_native_status does it the first time) */
void radio_native_shutdown(void);               /* stops it; a later init reads the environment again (tests) */

/* ---- radio.c's side ---- */
RadioStatus *radio_native_status(void);
void radio_native_lock(void);
void radio_native_unlock(void);
void radio_native_bind_ring(float *ring, uint32_t frames);
int radio_native_paused(void);
void radio_native_track_tags(uint32_t seq, char tags[3][RADIO_TAG]);
#endif
