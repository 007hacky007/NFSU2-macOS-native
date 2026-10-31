/* hle_unit.c -- runtime/hlefix.c without the game (tests/hle_unit.sh):
 *   tz        GetTimeZoneInformation for Europe/Prague, America/New_York and
 *             UTC: bias, daylight bias, the months of the two switches, the
 *             names, and the zone id (unknown without daylight saving)
 *   format    wsprintfA / wvsprintfA conversions, widths, flags, the cap
 *   features  IsProcessorFeaturePresent: a Pentium 4's answers (no 3DNow!)
 *   raise     RaiseException: a report and exit 5; NFSU2_RAISE=continue returns
 *   disk      GetDiskFreeSpaceExA / GetDiskFreeSpaceA: the saves' volume
 * Prints "PASS ..." / "FAIL ..." lines; exit 1 on a FAIL. */
#include "../runtime/hlefix.c"
#include <sys/mman.h>
#include <sys/wait.h>

uint8_t *g_mem;
uint8_t  g_cbits[1u << 15] = {0};
void mem_commit(uint32_t a, uint32_t n){ (void)a; (void)n; }
void guest_backtrace(CPU *c, int n){ (void)c; (void)n; fprintf(stderr, "    (backtrace)\n"); }
void (*g_report_fn)(void);

static int g_fail;
#define CHECK(cond, ...) do{ if (cond) printf("PASS " __VA_ARGS__); else { printf("FAIL " __VA_ARGS__); g_fail = 1; } \
                             printf("\n"); }while(0)
#define P 0x00100000u

static void tz(const char *zone, int32_t bias, int dst, int std_mon, int dst_mon, const char *sname){
    setenv("TZ", zone, 1); tzset();
    uint32_t id = hle_tz_info(P);
    int32_t b = (int32_t)MR32(P), db = (int32_t)MR32(P + 168);
    int sm = MR16(P + 68 + 2), dm = MR16(P + 152 + 2);
    char nm[32]; int i = 0; for (; i < 31 && MR16(P + 4 + 2*i); i++) nm[i] = (char)MR16(P + 4 + 2*i); nm[i] = 0;
    time_t now = time(0); struct tm lt; localtime_r(&now, &lt);
    uint32_t want = dst ? (lt.tm_isdst > 0 ? 2u : 1u) : 0u;
    CHECK(b == bias && id == want && (!dst || (db == -60 && sm == std_mon && dm == dst_mon)) && !strcmp(nm, sname),
          "tz %s: bias %d, daylight bias %d, standard month %d, daylight month %d, name %s, id %u", zone, b, db, sm, dm, nm, id);
}
static uint32_t put_args(uint32_t at, int n, const uint32_t *a){ for (int i = 0; i < n; i++) MR32(at + 4u*(uint32_t)i) = a[i]; return at; }

int main(void){
    g_mem = mmap(0, 1ull << 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_NORESERVE, -1, 0);
    if (g_mem == MAP_FAILED){ printf("FAIL no guest memory\n"); return 1; }
    memset(g_cbits, 0xff, sizeof g_cbits);
    freopen("/dev/null", "w", stderr);

    tz("Europe/Prague", -60, 1, 10, 3, "CET");
    tz("America/New_York", 300, 1, 11, 3, "EST");
    tz("UTC", 0, 0, 0, 0, "UTC");

    strcpy((char *)g_mem + 0x2000u, "car");
    uint32_t va = put_args(0x3000u, 7, (uint32_t[]){ (uint32_t)-42, 0x2000u, 0xbeefu, 'Z', 7u, 0xABCDu, 0 });
    uint32_t n = hle_vformat(0x4000u, 1025u, "%d|%5s|%-6x|%c|%%|%u|%08X|%s", va);
    const char *want = "-42|  car|beef  |Z|%|7|0000ABCD|(null)";
    CHECK(!strcmp((char *)g_mem + 0x4000u, want) && n == strlen(want), "format: \"%s\" (%u)", (char *)g_mem + 0x4000u, n);
    n = hle_vformat(0x4000u, 6u, "%d%d", put_args(0x3000u, 2, (uint32_t[]){ 1234u, 5678u }));
    CHECK(n == 5 && !strcmp((char *)g_mem + 0x4000u, "12345"), "format: capped at the buffer (%u, \"%s\")", n, (char *)g_mem + 0x4000u);

    CPU c; memset(&c, 0, sizeof c); c.eip = 0x006417d0u;
    CHECK(hle_processor_feature(&c, 7) == 0 && hle_processor_feature(&c, 6) == 1 && hle_processor_feature(&c, 10) == 1
          && hle_processor_feature(&c, 3) == 1 && hle_processor_feature(&c, 0) == 0,
          "features: no 3DNow! (7), SSE (6), SSE2 (10), MMX (3), no FDIV bug flag (0)");

    c.esp = put_args(0x5000u, 4, (uint32_t[]){ 0xE06D7363u, 1u, 0u, 0u });
    setenv("NFSU2_RAISE", "continue", 1);
    CHECK(hle_raise_exception(&c) == 0, "raise: NFSU2_RAISE=continue returns");
    unsetenv("NFSU2_RAISE");
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0){ hle_raise_exception(&c); _exit(0); }
    int st = 0; waitpid(pid, &st, 0);
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 5, "raise: the game stops (exit %d)", WIFEXITED(st) ? WEXITSTATUS(st) : -1);

    setenv("NFSU2_SAVEDIR", "/", 1);
    uint32_t a = put_args(0x6000u, 4, (uint32_t[]){ 0u, 0x6100u, 0x6108u, 0x6110u });
    uint64_t fr = 0, tot = 0;
    uint32_t ok = hle_disk_free(a - 0u, 1);
    memcpy(&fr, g_mem + 0x6100u, 8); memcpy(&tot, g_mem + 0x6108u, 8);
    a = put_args(0x6200u, 5, (uint32_t[]){ 0u, 0x6300u, 0x6304u, 0x6308u, 0x630Cu });
    uint32_t ok2 = hle_disk_free(a, 0);
    CHECK(ok && ok2 && fr > 0 && tot >= fr && MR32(0x6300u) == 8u && MR32(0x6304u) == 512u
          && MR32(0x6308u) && MR32(0x6308u) <= 0x7FFFFu && MR32(0x630Cu) >= MR32(0x6308u),
          "disk: GetDiskFreeSpaceExA %.1f of %.1f GB, GetDiskFreeSpaceA %u of %u clusters (capped)",
          fr / 1073741824.0, tot / 1073741824.0, MR32(0x6308u), MR32(0x630Cu));
    printf(g_fail ? "hle unit tests: FAILED\n" : "hle unit tests: all passed\n");
    return g_fail;
}
