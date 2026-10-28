#import <Foundation/Foundation.h>
#include "radio_native.h"
#include <math.h>
#include <unistd.h>
#include "radio_native_fixture.h"

static int failures;
#define CHECK(c, m) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", m); failures++; } } while (0)
static int wait_for(int (*condition)(void)) {
    for (int i = 0; i < 500; i++) { if (condition()) return 1; usleep(10000); }
    return 0;
}
static int enabled(void) { radio_native_lock(); int yes = host_status_radio()->on & 1; radio_native_unlock(); return yes; }
static int ready(void) { radio_native_lock(); HostStatusRadio *r = host_status_radio(); int yes = r->reply.ready_seq == r->request.req_seq; radio_native_unlock(); return yes; }
static int full(void) { radio_native_lock(); HostStatusRadio *r = host_status_radio(); int yes = r->reply.written - r->rings.read >= r->rings.ring_frames - 8192; radio_native_unlock(); return yes; }
int main(void) { @autoreleasepool {
    char temp[] = "/tmp/nfsu2-radio-test-XXXXXX";
    NSString *folder = [NSString stringWithUTF8String:mkdtemp(temp)];
    fixture_wav([folder stringByAppendingPathComponent:@"Synthetic Artist - Tone.wav"], 22050, 1);
    fixture_wav([folder stringByAppendingPathComponent:@"Synthetic Artist - Tone2.wav"], 48000, 10);
    CHECK(fixture_tagged_wav([folder stringByAppendingPathComponent:@"Synthetic Artist - Tone.wav"], [folder stringByAppendingPathComponent:@"Z-Tagged.wav"]), "synthetic fixture carries embedded RIFF metadata");
    [@"invalid audio" writeToFile:[folder stringByAppendingPathComponent:@"00-corrupt.wav"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:[folder stringByAppendingPathComponent:@"01-symlink.wav"] withDestinationPath:[folder stringByAppendingPathComponent:@"Synthetic Artist - Tone.wav"] error:nil];
    setenv("NFSU2_RADIO", "1", 1); setenv("NFSU2_MUSIC_FOLDER", folder.fileSystemRepresentation, 1);
    radio_native_init();
    CHECK(wait_for(enabled), "valid local folder enables playback after skipping corrupt audio");
    float *rings = calloc(2 * (1 << 17), sizeof(float));
    radio_native_lock();
    radio_native_bind_ring(rings, 1 << 17);
    HostStatusRadio *r = host_status_radio();
    r->rings.ring_frames = 1 << 17; r->rings.ring = 1;
    CHECK(!strcmp(r->offer_text[0][0], "Synthetic Artist"), "filename artist is offered");
    CHECK(!strcmp(r->offer_text[0][1], "Tone"), "filename title is offered");
    r->request.req_index = 0; r->request.req_seq = 1;
    radio_native_unlock();
    CHECK(wait_for(ready), "decoder answers the game request");
    usleep(100000);
    radio_native_lock();
    CHECK(r->reply.total >= 44098 && r->reply.total <= 44102, "22.05 kHz fixture converts to one second at 44.1 kHz");
    CHECK(r->reply.written == r->reply.total, "EOF publishes the exact decoded duration");
    double energy = 0, difference = 0;
    for (unsigned i = 0; i < r->reply.written && i < 44102; i++) { energy += rings[i] * rings[i]; difference += fabs(rings[i] - rings[(1 << 17) + i]); }
    CHECK(energy > 1000, "decoded ring contains the synthetic tone");
    CHECK(difference < 0.01, "mono source feeds both stereo channels");
    radio_native_unlock();
    radio_native_lock(); r->rings.read = 0; r->request.req_seq = 2; radio_native_unlock();
    CHECK(wait_for(ready) && wait_for(full), "48 kHz source fills the bounded ring");
    radio_native_lock();
    CHECK(r->reply.written <= r->rings.ring_frames, "decoder never overwrites unread samples");
    uint32_t before = r->reply.written;
    r->rings.read += 16384;
    radio_native_unlock();
    usleep(100000);
    radio_native_lock();
    CHECK(r->reply.written > before && r->reply.written - r->rings.read <= r->rings.ring_frames, "decoder refills after wrapping without overwriting unread frames");
    radio_native_unlock();
    radio_native_set_paused(1); radio_native_frame();
    CHECK(radio_native_paused(), "native pause is visible to mixer hooks");
    radio_native_set_paused(0); radio_native_set_shuffle(1); radio_native_frame();
    RadioNativeSnapshot snapshot; radio_native_snapshot(&snapshot);
    CHECK(!snapshot.paused && snapshot.shuffle, "transport state is readable by native UI");
    CHECK(snapshot.tracks == 3, "playlist excludes corrupt files and symbolic links");
    radio_native_lock(); before = r->reply.written; r->rings.read += 16384; radio_native_unlock();
    usleep(100000);
    radio_native_lock(); CHECK(r->reply.written > before, "shuffle changes the next offer without cancelling the playing decoder"); radio_native_unlock();
    radio_native_next(); radio_native_frame();
    radio_native_lock(); CHECK(r->reply.total <= r->rings.read, "next cuts the current song through the shared protocol"); radio_native_unlock();
    radio_native_set_shuffle(0);
    usleep(100000);
    radio_native_lock();
    CHECK(!strcmp(r->offer_text[0][0], "Synthetic Tagged Artist") && !strcmp(r->offer_text[0][1], "Tagged Tone"), "embedded artist and title override the filename for the next offer");
    r->rings.read = 0; r->request.req_seq = 3;
    radio_native_unlock();
    CHECK(wait_for(ready), "decoder serves the tagged local track");
    radio_native_set_enabled(0); radio_native_frame();
    CHECK(!enabled(), "switch off restores the soundtrack selection");
    for (int i = 0; i < 20; i++) { radio_native_set_enabled(1); radio_native_set_enabled(0); }
    usleep(50000);
    CHECK(!enabled(), "rapid switches cannot publish stale playback");
    radio_native_shutdown(); radio_native_shutdown();
    setenv("NFSU2_MUSIC_FOLDER", "relative/path", 1); radio_native_init(); usleep(30000);
    CHECK(!enabled(), "relative folder paths cannot enable playback");
    radio_native_shutdown();
    setenv("NFSU2_MUSIC_FOLDER", folder.fileSystemRepresentation, 1); setenv("NFSU2_RADIO", "0", 1);
    radio_native_init(); usleep(30000); radio_native_snapshot(&snapshot);
    CHECK(!enabled() && snapshot.tracks == 0, "soundtrack mode does not scan or decode the selected folder");
    radio_native_shutdown();
    NSString *empty = [folder stringByAppendingPathComponent:@"empty"];
    [[NSFileManager defaultManager] createDirectoryAtPath:empty withIntermediateDirectories:NO attributes:nil error:nil];
    setenv("NFSU2_MUSIC_FOLDER", empty.fileSystemRepresentation, 1); setenv("NFSU2_RADIO", "1", 1);
    radio_native_init(); usleep(100000);
    CHECK(!enabled(), "an empty folder safely leaves the soundtrack available");
    radio_native_shutdown();
    free(rings);
    [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    printf("radio_native_unit: %d failures\n", failures);
    return failures != 0;
} }
