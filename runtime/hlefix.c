/* hlefix.c -- Win32 answers made closer to Windows' (win32.c, win32_ext.c):
 *
 *   GetTimeZoneInformation  the host's real zone: bias, names, and this
 *                           year's daylight saving dates (only the bias was
 *                           filled before)
 *   wsprintfA / wvsprintfA  the guest's printf: %[-0+ #][width][.prec][hlI]
 *                           d i u x X o c s % (wvsprintfA was not handled,
 *                           wsprintfA left its buffer as it was)
 *   IsProcessorFeaturePresent  true only for what a Pentium 4 class CPU has
 *                           (it said yes to everything)
 *   RaiseException          the game stops with a report of the exception,
 *                           as there is no guest exception dispatch to
 *                           continue into (it returned silently before)
 *   GetDiskFreeSpace(Ex)A   the volume that holds the saves (they failed)
 *
 * Ported from th0mk's nfsu2-web runtime/win32.c and runtime/win32_ext.c (MIT). */
#include "cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/mount.h>

void guest_backtrace(CPU *, int);

/* GetTimeZoneInformation: TIME_ZONE_INFORMATION (172 bytes): Bias@0,
 * StandardName[32 WCHAR]@4, StandardDate@68, StandardBias@84,
 * DaylightName@88, DaylightDate@152, DaylightBias@168.  Transition dates are
 * this year's, as absolute dates (wYear != 0), which the CRT's
 * tzset/_isindst accept; found by scanning the year hour by hour.  Returns
 * TIME_ZONE_ID_UNKNOWN (0) without daylight saving, else STANDARD (1) or
 * DAYLIGHT (2). */
static void put_systime(uint32_t p, time_t t){
    struct tm g; gmtime_r(&t, &g);
    MR16(p+0)=(uint16_t)(g.tm_year+1900); MR16(p+2)=(uint16_t)(g.tm_mon+1); MR16(p+4)=(uint16_t)g.tm_wday;
    MR16(p+6)=(uint16_t)g.tm_mday; MR16(p+8)=(uint16_t)g.tm_hour; MR16(p+10)=(uint16_t)g.tm_min;
    MR16(p+12)=0; MR16(p+14)=0;
}
uint32_t hle_tz_info(uint32_t p){
    tzset();
    time_t now = time(0); struct tm lt; localtime_r(&now, &lt);
    struct tm y0 = {0}; y0.tm_year = lt.tm_year; y0.tm_mday = 1; y0.tm_isdst = -1;
    time_t t0 = mktime(&y0);
    long std_off = lt.tm_isdst > 0 ? 0 : lt.tm_gmtoff, dst_off = lt.tm_isdst > 0 ? lt.tm_gmtoff : 0;
    time_t to_dst = 0, to_std = 0;
    struct tm a; localtime_r(&t0, &a);
    int prev = a.tm_isdst > 0;
    for (time_t t = t0 + 3600; t < t0 + 366 * 86400; t += 3600){
        struct tm b; localtime_r(&t, &b);
        int d = b.tm_isdst > 0;
        if (d) dst_off = b.tm_gmtoff; else std_off = b.tm_gmtoff;
        if (d != prev){
            time_t lo = t - 3600, hi = t;                 /* to the minute */
            while (hi - lo > 60){ time_t m = lo + (hi - lo) / 2; struct tm x; localtime_r(&m, &x);
                                  if ((x.tm_isdst > 0) == d) hi = m; else lo = m; }
            if (d) to_dst = hi; else to_std = hi;
            prev = d;
        }
    }
    if (!std_off && !dst_off) std_off = lt.tm_gmtoff;
    if (p){
        mem_commit(p, 172); memset(g_mem + p, 0, 172);
        MR32(p) = (uint32_t)(int32_t)(-std_off / 60);
        const char *sn = tzname[0] ? tzname[0] : "", *dn = tzname[1] ? tzname[1] : "";
        for (int i = 0; i < 31 && sn[i]; i++) MR16(p + 4 + 2*i) = (uint8_t)sn[i];
        for (int i = 0; i < 31 && dn[i]; i++) MR16(p + 88 + 2*i) = (uint8_t)dn[i];
        if (to_dst && to_std){
            put_systime(p + 152, to_dst + std_off);       /* the wall clock before the switch */
            put_systime(p + 68,  to_std + dst_off);
            MR32(p + 168) = (uint32_t)(int32_t)(-(dst_off - std_off) / 60);
        }
    }
    { static int shown; if (!shown++){
        struct tm da, sa; time_t td = to_dst + std_off, ts = to_std + dst_off; gmtime_r(&td, &da); gmtime_r(&ts, &sa);
        if (to_dst && to_std)
            fprintf(stderr, "[hle] GetTimeZoneInformation: bias %ld min, \"%s\" / \"%s\", daylight %04d-%02d-%02d %02d:%02d,"
                    " standard %04d-%02d-%02d %02d:%02d (local) -> %s\n", -std_off / 60, tzname[0], tzname[1],
                    da.tm_year + 1900, da.tm_mon + 1, da.tm_mday, da.tm_hour, da.tm_min, sa.tm_year + 1900, sa.tm_mon + 1,
                    sa.tm_mday, sa.tm_hour, sa.tm_min, lt.tm_isdst > 0 ? "daylight" : "standard");
        else fprintf(stderr, "[hle] GetTimeZoneInformation: bias %ld min, \"%s\", no daylight saving -> unknown\n",
                     -std_off / 60, tzname[0]); } }
    if (!to_dst || !to_std) return 0;
    return lt.tm_isdst > 0 ? 2u : 1u;
}

/* The guest's printf (wvsprintfA / wsprintfA): %[-0+ #][width][.prec][hlI]
 * d i u x X o c s % ; arguments are 32-bit stack slots (va = a guest
 * pointer to the first).  At most cap - 1 characters (wsprintf: 1024). */
uint32_t hle_vformat(uint32_t out, uint32_t cap, const char *fmt, uint32_t va){
    char tmp[1100]; uint32_t n = 0;
    for (const char *p = fmt; *p && n < sizeof tmp - 64; p++){
        if (*p != '%'){ tmp[n++] = *p; continue; }
        char spec[32]; int k = 0; spec[k++] = '%'; p++;
        while (*p && strchr("-+ #0", *p) && k < 20) spec[k++] = *p++;
        while (*p >= '0' && *p <= '9' && k < 24) spec[k++] = *p++;
        if (*p == '.'){ spec[k++] = *p++; while (*p >= '0' && *p <= '9' && k < 28) spec[k++] = *p++; }
        while (*p == 'l' || *p == 'h' || *p == 'I') p++;
        char cv = *p; if (!cv) break;
        spec[k++] = cv; spec[k] = 0;
        int w = 0;
        if (cv == '%'){ tmp[n++] = '%'; continue; }
        uint32_t a = mem_is_committed(va + 3) ? MR32(va) : 0u; va += 4;
        if (cv == 's'){
            const char *sv = (a && mem_is_committed(a)) ? (const char *)(g_mem + a) : "(null)";
            char sv2[512]; snprintf(sv2, sizeof sv2, "%s", sv);
            w = snprintf(tmp + n, sizeof tmp - n, spec, sv2);
        } else if (cv == 'c') w = snprintf(tmp + n, sizeof tmp - n, spec, (int)(a & 0xFF));
        else if (cv == 'd' || cv == 'i') w = snprintf(tmp + n, sizeof tmp - n, spec, (int)(int32_t)a);
        else if (cv == 'u' || cv == 'x' || cv == 'X' || cv == 'o') w = snprintf(tmp + n, sizeof tmp - n, spec, (unsigned)a);
        else { tmp[n++] = '%'; tmp[n++] = cv; continue; }
        if (w > 0) n += (uint32_t)w < sizeof tmp - n ? (uint32_t)w : (uint32_t)(sizeof tmp - n - 1);
    }
    tmp[n] = 0;
    if (n >= cap) n = cap ? cap - 1 : 0;
    mem_commit(out, n + 1); memcpy(g_mem + out, tmp, n); MR8(out + n) = 0;
    { static int shown; if (shown++ < 4) fprintf(stderr, "[hle] wsprintf(\"%.60s\") -> \"%.80s\"\n", fmt, (const char *)(g_mem + out)); }
    return n;
}

/* IsProcessorFeaturePresent: true for a Pentium 4 class CPU:
 * PF_COMPARE_EXCHANGE_DOUBLE (2), PF_MMX (3), PF_XMMI (6), PF_RDTSC (8),
 * PF_XMMI64 (10).  It used to be true for everything, so D3DX's PSGP
 * selector (0x641790, the only caller) installed its 3DNow! kernels (PF 7),
 * which no Intel CPU has.  NFSU2_PF_ALL=1 (test aid): the old answer. */
uint32_t hle_processor_feature(CPU *c, uint32_t f){
    uint32_t r = (f == 2u || f == 3u || f == 6u || f == 8u || f == 10u) ? 1u : 0u;
    const char *e = getenv("NFSU2_PF_ALL");
    if (e && *e == '1') r = 1;
    static uint32_t seen = 0;
    if (f < 32u && !(seen & (1u << f))){ seen |= 1u << f;
        fprintf(stderr, "[hle] IsProcessorFeaturePresent(%u) -> %u (from 0x%08x)\n", f, r, c->eip); }
    return r;
}

/* RaiseException(code, flags, nargs, args): there is no guest exception
 * dispatch, so continuing after a raise is undefined behaviour.  Report
 * everything useful and stop; NFSU2_RAISE=continue (test aid) returns as
 * before. */
uint32_t hle_raise_exception(CPU *c){
    uint32_t code = MR32(c->esp), fl = MR32(c->esp + 4u), na = MR32(c->esp + 8u), pa = MR32(c->esp + 12u);   /* the return address is in eip */
    const char *what = code == 0xE06D7363u ? "C++ exception (throw)"
                     : code == 0xC000008Eu ? "float divide by zero" : code == 0xC000008Fu ? "float inexact result"
                     : code == 0xC0000090u ? "float invalid operation" : code == 0xC0000091u ? "float overflow"
                     : code == 0xC0000093u ? "float underflow" : code == 0xC000008Du ? "float denormal operand"
                     : code == 0xC0000092u ? "float stack check" : "?";
    fprintf(stderr, "\n*** GUEST RAISEEXCEPTION: code 0x%08x (%s), flags 0x%x, %u args, from 0x%08x (thread %u)\n",
            code, what, fl, na, c->eip,
            (c->fs_base && mem_is_committed(c->fs_base + 0x24u)) ? MR32(c->fs_base + 0x24u) : 0u);
    fprintf(stderr, "    x87 control word 0x%04x (exception mask 0x%02x%s, PC %u, RC %u)\n",
            c->fcw, c->fcw & 0x3Fu, (c->fcw & 0x3Fu) == 0x3Fu ? " = all masked" : " -- UNMASKED exceptions",
            (c->fcw >> 8) & 3u, (c->fcw >> 10) & 3u);
    for (uint32_t i = 0; i < na && i < 8 && pa && mem_is_committed(pa + 4u * i + 3u); i++)
        fprintf(stderr, "    arg[%u] = 0x%08x\n", i, MR32(pa + 4u * i));
    /* MSVC C++ throw: args = { magic, object, ThrowInfo* }; name the type */
    if (code == 0xE06D7363u && na >= 3 && pa && mem_is_committed(pa + 11)){
        uint32_t ti = MR32(pa + 8);
        uint32_t cta = (ti && mem_is_committed(ti + 15)) ? MR32(ti + 12) : 0;
        uint32_t ct  = (cta && mem_is_committed(cta + 7)) ? MR32(cta + 4) : 0;
        uint32_t td  = (ct && mem_is_committed(ct + 7)) ? MR32(ct + 4) : 0;
        if (td && mem_is_committed(td + 8)) fprintf(stderr, "    thrown type %.80s\n", (const char *)(g_mem + td + 8));
        else if (!ti) fprintf(stderr, "    rethrow (throw;) of the current exception\n");
    }
    guest_backtrace(c, 16);
    const char *e = getenv("NFSU2_RAISE");
    if (e && !strcmp(e, "continue")) return 0;
    fprintf(stderr, "*** the game cannot go on after an exception it raised (NFSU2_RAISE=continue returns instead)\n");
    extern void (*g_report_fn)(void);
    if (g_report_fn) g_report_fn();
    fflush(stderr);
    _exit(5);
}

/* GetDiskFreeSpaceExA (dir, &freeToCaller, &total, &totalFree) and
 * GetDiskFreeSpaceA (root, &sectorsPerCluster, &bytesPerSector, &freeClusters,
 * &totalClusters): the volume that holds the saves (NFSU2_SAVEDIR, else
 * HOME).  RealCore's drive object (0x6FAEB3) reads the free bytes as a 64-bit
 * value; the old call gets 4 KB clusters with both counts capped below 2 GB,
 * so 32-bit products (the CRT's _getdiskfree, old game code) cannot overflow.
 * args: the import's arguments (esp after the return address). */
uint32_t hle_disk_free(uint32_t args, int ex){
    uint64_t fr = 8ull << 30, tot = 64ull << 30;
    struct statfs sf; const char *d = getenv("NFSU2_SAVEDIR");
    if (!d || !*d) d = getenv("HOME");
    if (d && statfs(d, &sf) == 0){ fr = (uint64_t)sf.f_bavail * sf.f_bsize; tot = (uint64_t)sf.f_blocks * sf.f_bsize; }
    if (ex){
        uint32_t q[3] = { MR32(args + 4), MR32(args + 8), MR32(args + 12) };
        uint64_t v[3] = { fr, tot, fr };
        for (int i = 0; i < 3; i++) if (q[i]){ mem_commit(q[i], 8); MR32(q[i]) = (uint32_t)v[i]; MR32(q[i] + 4) = (uint32_t)(v[i] >> 32); }
    } else {
        uint32_t cf = (uint32_t)((fr >> 12) > 0x7FFFFu ? 0x7FFFFu : (fr >> 12));
        uint32_t ct = (uint32_t)((tot >> 12) > 0x7FFFFu ? 0x7FFFFu : (tot >> 12));
        uint32_t v[4] = { 8u, 512u, cf, ct };
        for (int i = 0; i < 4; i++){ uint32_t pp = MR32(args + 4u + 4u * (uint32_t)i); if (pp){ mem_commit(pp, 4); MR32(pp) = v[i]; } }
    }
    static int shown;
    if (!shown++) fprintf(stderr, "[hle] GetDiskFreeSpace%s: %.1f GB free of %.1f GB (the saves' volume)\n",
                          ex ? "ExA" : "A", fr / 1073741824.0, tot / 1073741824.0);
    return 1;
}
