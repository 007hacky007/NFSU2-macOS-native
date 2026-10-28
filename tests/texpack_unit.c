/* Standalone pack parser checks, no game data or GPU required. */
#include "texpack.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static unsigned char fixture[160];
static void put(unsigned at, unsigned v){
    for (unsigned i = 0; i < 4; i++) fixture[at + i] = (unsigned char)(v >> (8 * i));
}
static void valid(void){
    memset(fixture, 0, sizeof fixture);
    memcpy(fixture, "NTXP", 4); put(4, 1); put(8, 1);
    /* CRC/Adler of the original's four zero bytes. */
    put(16, 0x2144df1c); put(20, 0x00040001);
    put(24, 0x00010001); put(28, 21);
    put(32, 0x00040004); put(36, 21); put(40, 1);
    put(44, 96); put(48, 64); put(52, 56);
    memcpy(fixture + 56, "fixture", 8);
}
static void write_fixture(const char *path, size_t n){
    FILE *f = fopen(path, "wb"); assert(f);
    assert(fwrite(fixture, 1, n, f) == n); assert(!fclose(f));
}
static int open_fixture(const char *path, size_t n){
    write_fixture(path, n);
    Texpack p = {0}; char err[160];
    int ok = texpack_open(&p, path, err, sizeof err);
    if (ok) texpack_close(&p);
    return ok;
}
int main(int argc, char **argv){
    if (argc > 1){
        Texpack p = {0}; char err[160];
        if (!texpack_open(&p, argv[1], err, sizeof err)){ fprintf(stderr, "%s\n", err); return 1; }
        printf("PASS real pack: %u entries\n", p.count); texpack_close(&p); return 0;
    }
    char path[] = "/tmp/nfsu2-texpack-XXXXXX";
    int fd = mkstemp(path); assert(fd >= 0); close(fd);
    valid(); assert(open_fixture(path, sizeof fixture));
    Texpack p = {0}; char err[160]; unsigned char zero[4] = {0};
    assert(texpack_open(&p, path, err, sizeof err));
    assert(texpack_may_match(&p, 1, 1, 21));
    assert(!texpack_may_match(&p, 2, 1, 21));
    assert(texpack_find(&p, zero, sizeof zero, 1, 1, 21) == 0);
    assert(texpack_find(&p, zero, sizeof zero - 1, 1, 1, 21) == -1);
    assert(texpack_find(&p, zero, sizeof zero, 1, 1, 22) == -1);
    zero[0] = 1; assert(texpack_find(&p, zero, sizeof zero, 1, 1, 21) == -1);
    unsigned char pixels[64]; assert(texpack_read(&p, 0, pixels, sizeof pixels));
    assert(!texpack_read(&p, 1, pixels, sizeof pixels));
    assert(!texpack_read(&p, 0, pixels, sizeof pixels - 1));
    write_fixture(path, 100); assert(!texpack_read(&p, 0, pixels, sizeof pixels));
    texpack_close(&p);
    unsigned offsets[] = {4, 8, 12, 24, 28, 32, 36, 40, 44, 48, 52};
    for (unsigned i = 0; i < sizeof offsets / sizeof *offsets; i++){
        valid(); put(offsets[i], 0xffffffffu); assert(!open_fixture(path, sizeof fixture));
    }
    for (unsigned n = 0; n < sizeof fixture; n++){ valid(); assert(!open_fixture(path, n)); }
    valid(); put(40, 4); assert(!open_fixture(path, sizeof fixture)); /* too many mips */
    valid(); put(44, 40); assert(!open_fixture(path, sizeof fixture)); /* payload overlaps table */
    valid(); put(52, 96); assert(!open_fixture(path, sizeof fixture)); /* name in payload */
    valid(); memset(fixture + 56, 'x', 40); assert(!open_fixture(path, sizeof fixture));
    valid(); put(32, 0x00040008); assert(!open_fixture(path, sizeof fixture)); /* aspect ratio */
    /* Sorted duplicate checksum rows are allowed; lookup still checks shape. */
    valid(); put(8, 2); put(36, 0x31545844); put(44, 128); put(48, 8); put(52, 96);
    memcpy(fixture + 56, fixture + 16, 40); memcpy(fixture + 96, "fixture", 8);
    assert(open_fixture(path, sizeof fixture));
    put(56, 0); assert(!open_fixture(path, sizeof fixture)); /* descending CRC */
    put(56, 0x2144df1c); put(60, 1); assert(!open_fixture(path, sizeof fixture)); /* descending Adler */
    valid(); put(36, 0x33545844); put(48, 16); assert(open_fixture(path, sizeof fixture));
    valid(); put(36, 0x35545844); put(48, 16); assert(open_fixture(path, sizeof fixture));
    valid(); put(24, 0); assert(!open_fixture(path, sizeof fixture));
    valid(); put(32, 0); assert(!open_fixture(path, sizeof fixture));
    unlink(path); puts("PASS texpack fixtures, lookup, short reads and malformed input");
    return 0;
}
