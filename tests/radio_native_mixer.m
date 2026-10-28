/* Real system decoder and shared radio hooks, with only the guest game/mixer stubbed. */
#include "cpu.h"
#include "radio_native.h"
#include "radio_native_fixture.h"
#include <stdlib.h>
#include <pthread.h>

uint8_t *g_mem;
static int g_orig_calls;
uint32_t gheap_alloc(int heap, uint32_t n, int zero) { (void)heap; (void)n; (void)zero; return 0x100000; }
#include "../runtime/radio.c"
#define g_page (*host_status_radio())
#define sub_007292bc_orig guest_mixer_original
#include "radio_mixer_stub.h"
#undef sub_007292bc_orig
static int failures;
#define CHECK(c, m) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", m); failures++; } } while (0)
static pthread_t probe_thread;
static int probe_started, probe_finished;
static void *probe_ui_mutex(void *unused) {
    (void)unused;
    RadioNativeSnapshot value; radio_native_snapshot(&value);
    __atomic_store_n(&probe_finished, 1, __ATOMIC_RELEASE);
    return NULL;
}
void sub_007292bc_orig(CPU *c) {
    if (!probe_started) {
        probe_started = 1; pthread_create(&probe_thread, NULL, probe_ui_mutex, NULL);
        for (int i = 0; i < 100 && !__atomic_load_n(&probe_finished, __ATOMIC_ACQUIRE); i++) usleep(1000);
        CHECK(__atomic_load_n(&probe_finished, __ATOMIC_ACQUIRE), "guest calls release the native mutex so another thread can proceed");
    }
    guest_mixer_original(c);
}

static void game_song_starts(unsigned index) {
    g.last_index = (int)index;
    call(sub_004580e0, 0, index, 0, 0);
    call(sub_004ac9f0, 0, 0, 0, 0);
    g.pending = READERS_APPEAR_AFTER;
}
static void tick(void) {
    CPU c = { .esp = CALL_ESP };
    g.in_step = 1; sub_007292bc(&c); g.in_step = 0;
    if (g.restart) { g.restart = 0; game_song_starts((g.last_index + 1) % RADIO_TRACKS); }
    pull_inputs(); usleep(1000);
}
static void ticks(unsigned n) { for (unsigned i = 0; i < n; i++) tick(); }
int main(void) { @autoreleasepool {
    CHECK(in_guest(0x90000000u, 4) && !in_guest(0xffffffffu, 4), "native guest bounds span the full 32-bit address space without wrapping");
    char temp[] = "/tmp/nfsu2-radio-mixer-XXXXXX";
    NSString *folder = [NSString stringWithUTF8String:mkdtemp(temp)];
    fixture_wav([folder stringByAppendingPathComponent:@"Synthetic Artist - Mixer.wav"], 22050, 4);
    setenv("NFSU2_RADIO", "1", 1); setenv("NFSU2_MUSIC_FOLDER", folder.fileSystemRepresentation, 1);
    g_mem = calloc(1, 0x28000000u);
    strcpy((char *)g_mem + NAMES, "game song");
    for (unsigned e = 0; e < RADIO_TRACKS; e++) for (unsigned w = 0; w < 3; w++) MR32(TRAX_TABLE + 16u * e + 4u * w) = NAMES;
    MR32(MIXER_INPUTS) = INPUTS; MR8(SOUND_API_ACTIVE) = 1;
    MR32(SOUND_GROUPS_OWNER) = OWNER; MR32(OWNER + MUSIC_STREAM) = 0; MR8(STREAM_HANDLES) = 1;
    MR32(STREAM_TABLE) = STREAM; MR32(STREAM + STREAM_VOICE) = END_OF_STREAM;
    MR32(VOICE_TABLE) = VOICES; MR16(VOICE_COUNT) = 4; MR32(GAME_FLOW) = FLOW;
    MR32(FLOW + FLOW_MODE) = 2; MR32(GAME_STATE) = 6;
    MR16(MIXER_RATE) = 22050; MRF32(GAME_MUSIC_VOLUME) = 0.5f;
    /* The provider initializes before the game's first song; no Present call is needed. */
    HostStatusRadio *r = host_status_radio();
    for (int i = 0; i < 500; i++) { radio_native_lock(); int on = r->on & 1; radio_native_unlock(); if (on) break; usleep(10000); }
    game_song_starts(3); ticks(30);
    CHECK(g_song.who == SONG_FOLDER, "real decoder becomes the game's music stream");
    CHECK(!strcmp((char *)g_mem + MR32(TRAX_TABLE + 16u * 3u), "Mixer"), "game song table lends the real title for the plaque");
    CHECK(!strcmp((char *)g_mem + MR32(TRAX_TABLE + 16u * 3u + 4u), "Synthetic Artist"), "game song table lends the real artist");
    CHECK(g_song.read[0] > 0 && g_song.read[0] == g_song.read[1], "both mixer readers consume the decoded stereo stream");
    float heard = 0;
    for (unsigned i = 0; i < STEP_FRAMES; i++) heard += fabsf(MRF32(OUT + 4u * i));
    CHECK(heard > 10000 && heard < STEP_FRAMES * 0.4f * PIPELINE_SCALE * 0.5f, "game music slider scales decoded samples");
    uint32_t before = g_song.read[0];
    radio_native_set_paused(1); ticks(20);
    CHECK(g_song.read[0] == before && MRF32(OUT) == 0, "native pause silences the game voice without advancing audio");
    radio_native_set_paused(0); ticks(5);
    CHECK(g_song.read[0] > before, "native resume continues the same decoded track");
    int stops = g.stops;
    radio_native_next(); ticks(30);
    CHECK(g.stops > stops && g_song.who == SONG_FOLDER, "next ends the game song and requests another decoded track");
    radio_native_set_enabled(0); ticks(20);
    CHECK(g_song.who == SONG_GAME && MR32(TRAX_TABLE + 16u * 3u) == NAMES, "disabling returns the game's music and original metadata");
    radio_native_shutdown();
    if (probe_started) pthread_join(probe_thread, NULL);
    free(g_radio.ring); free(g_mem);
    [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    printf("radio_native_mixer: %d failures\n", failures);
    return failures != 0;
} }
