#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>
#include <stdio.h>
#include <unistd.h>
static void fixture16(FILE *f, uint16_t n) { fputc(n & 255, f); fputc(n >> 8, f); }
static void fixture32(FILE *f, uint32_t n) { fixture16(f, n & 65535); fixture16(f, n >> 16); }
/* Synthesized tone only. Tests never open a personal music library. */
static void fixture_wav(NSString *path, unsigned rate, unsigned seconds) {
    unsigned count = rate * seconds;
    FILE *f = fopen(path.fileSystemRepresentation, "wb");
    fwrite("RIFF", 1, 4, f); fixture32(f, 36 + 2 * count); fwrite("WAVEfmt ", 1, 8, f);
    fixture32(f, 16); fixture16(f, 1); fixture16(f, 1); fixture32(f, rate); fixture32(f, 2 * rate);
    fixture16(f, 2); fixture16(f, 16); fwrite("data", 1, 4, f); fixture32(f, 2 * count);
    for (unsigned i = 0; i < count; i++) fixture16(f, (uint16_t)(int16_t)(12000 * sin(2 * M_PI * 440 * i / rate)));
    fclose(f);
}
static BOOL fixture_tagged_wav(NSString *source, NSString *path) {
    if (![[NSFileManager defaultManager] copyItemAtPath:source toPath:path error:nil]) return NO;
    FILE *f = fopen(path.fileSystemRepresentation, "r+b");
    fseek(f, 0, SEEK_END);
    const char *keys[] = {"IART", "INAM", "IPRD"};
    const char *values[] = {"Synthetic Tagged Artist", "Tagged Tone", "Test Album"};
    uint32_t bytes = 4;
    for (unsigned i = 0; i < 3; i++) bytes += 8 + ((strlen(values[i]) + 2) & ~1u);
    fwrite("LIST", 1, 4, f); fixture32(f, bytes); fwrite("INFO", 1, 4, f);
    for (unsigned i = 0; i < 3; i++) {
        uint32_t size = (uint32_t)strlen(values[i]) + 1;
        fwrite(keys[i], 1, 4, f); fixture32(f, size); fwrite(values[i], 1, size, f);
        if (size & 1) fputc(0, f);
    }
    uint32_t size = (uint32_t)ftell(f) - 8; fseek(f, 4, SEEK_SET); fixture32(f, size); fclose(f);
    return YES;
}
