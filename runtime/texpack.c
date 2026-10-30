/* texpack.c -- reading NTXP texture packs, versions 1 and 2 (texpack.h) */
#include "texpack.h"
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <zlib.h>

static uint32_t u32(const uint8_t *p){
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static unsigned u16(const uint8_t *p){ return p[0] | (unsigned)p[1] << 8; }
static int read_at(int fd, void *dst, size_t size, off_t off){
    uint8_t *p = dst;
    while (size){
        ssize_t n = pread(fd, p, size, off);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        p += n; size -= (size_t)n; off += n;
    }
    return 1;
}
static size_t level_size(unsigned w, unsigned h, unsigned fmt){
    switch (fmt){
    case 21: case 22: return (size_t)w * h * 4;
    case 0x31545844u: return (size_t)((w + 3) / 4) * ((h + 3) / 4) * 8;
    case 0x33545844u: case 0x35545844u:
        return (size_t)((w + 3) / 4) * ((h + 3) / 4) * 16;
    default: return 0;
    }
}
static int keyed(const TexpackEntry *e){ return !e->ow && !e->oh; }   /* a TexMod or name key */
static uint64_t shape(unsigned w, unsigned h, unsigned fmt){
    return (uint64_t)w | (uint64_t)h << 16 | (uint64_t)fmt << 32;
}
static int shape_cmp(const void *a, const void *b){
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return x < y ? -1 : x > y;
}
void texpack_close(Texpack *p){
    if (p->fd >= 0) close(p->fd);
    free(p->entries); free(p->names); free(p->shapes);
    memset(p, 0, sizeof *p); p->fd = -1;
}
int texpack_open(Texpack *p, const char *path, char *err, size_t err_size){
    memset(p, 0, sizeof *p); p->fd = -1;
    const char *why = "unreadable pack";
    struct stat st; uint8_t hd[16];
    p->fd = open(path, O_RDONLY);
    if (p->fd < 0 || fstat(p->fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 16 ||
        (uint64_t)st.st_size > UINT32_MAX || !read_at(p->fd, hd, sizeof hd, 0)) goto fail;
    why = "invalid NTXP header";
    unsigned version = u32(hd + 4);
    if (memcmp(hd, "NTXP", 4) || (version != 1 && version != 2) || u32(hd + 12)) goto fail;
    p->count = u32(hd + 8);
    if (!p->count || p->count > 65536u || 16ull + 40ull * p->count > (uint64_t)st.st_size) goto fail;
    p->names_at = 16 + 40 * p->count;
    p->entries = calloc(p->count, sizeof *p->entries);
    p->shapes = calloc(p->count, sizeof *p->shapes);
    why = "out of memory";
    if (!p->entries || !p->shapes) goto fail;
    uint32_t first = (uint32_t)st.st_size;
    unsigned nshapes = 0;
    for (unsigned i = 0; i < p->count; i++){
        uint8_t b[40]; TexpackEntry *e = &p->entries[i];
        why = "truncated entry table";
        if (!read_at(p->fd, b, sizeof b, 16 + (off_t)i * 40)) goto fail;
        e->crc = u32(b); e->adler = u32(b + 4); e->ow = u16(b + 8); e->oh = u16(b + 10);
        e->ofmt = u32(b + 12); e->w = u16(b + 16); e->h = u16(b + 18);
        e->fmt = u32(b + 20); e->levels = u32(b + 24); e->off = u32(b + 28);
        e->size = u32(b + 32); e->name = u32(b + 36);
        why = "invalid texture dimensions or format";
        if (!e->w || !e->h || e->w > 16384 || e->h > 16384 || !level_size(e->w, e->h, e->fmt)) goto fail;
        if (version >= 2 && keyed(e)){
            if (e->ofmt == TEXPACK_KEY_TEXMOD) p->texmod_count++;
            else if (e->ofmt == TEXPACK_KEY_NAME) p->name_count++;
            else goto fail;
        } else {
            if (!e->ow || !e->oh || e->ow > 4096 || e->oh > 4096 || !level_size(e->ow, e->oh, e->ofmt)) goto fail;
            /* version 1 (UHUD): the same picture, larger */
            if (version == 1 && (e->w < e->ow || e->h < e->oh ||
                                 (uint64_t)e->w * e->oh != (uint64_t)e->h * e->ow)) goto fail;
            p->shapes[nshapes++] = shape(e->ow, e->oh, e->ofmt);
        }
        unsigned max_levels = 1;
        for (unsigned d = e->w > e->h ? e->w : e->h; d > 1; d >>= 1) max_levels++;
        why = "invalid mip levels or payload range";
        if (!e->levels || e->levels > max_levels) goto fail;
        size_t need = 0;
        for (unsigned l = 0, w = e->w, h = e->h; l < e->levels; l++, w = w > 1 ? w / 2 : 1, h = h > 1 ? h / 2 : 1)
            need += level_size(w, h, e->fmt);
        if (need != e->size || e->off < p->names_at || e->off > (uint64_t)st.st_size ||
            e->size > (uint64_t)st.st_size - e->off) goto fail;
        why = "unsorted texture keys";
        if (i && (p->entries[i - 1].crc > e->crc ||
            (p->entries[i - 1].crc == e->crc && p->entries[i - 1].adler > e->adler))) goto fail;
        if (e->off < first) first = e->off;
    }
    why = "invalid texture names";
    if (first <= p->names_at || first - p->names_at > (8u << 20)) goto fail;
    size_t names_size = first - p->names_at;
    p->names = malloc(names_size);
    if (!p->names || !read_at(p->fd, p->names, names_size, p->names_at)) goto fail;
    for (unsigned i = 0; i < p->count; i++){
        uint32_t at = p->entries[i].name;
        if (at < p->names_at || at >= first) goto fail;
        size_t limit = first - at; if (limit > 1024) limit = 1024;
        if (!memchr(p->names + at - p->names_at, 0, limit)) goto fail;
    }
    qsort(p->shapes, nshapes, sizeof *p->shapes, shape_cmp);
    for (unsigned i = 0; i < nshapes; i++)
        if (!p->shape_count || p->shapes[i] != p->shapes[p->shape_count - 1]) p->shapes[p->shape_count++] = p->shapes[i];
    if (err_size) *err = 0;
    return 1;
fail:
    if (err_size) snprintf(err, err_size, "%s", why);
    texpack_close(p); return 0;
}
int texpack_may_match(const Texpack *p, unsigned w, unsigned h, unsigned fmt){
    if (!w || !h || w > 4096 || h > 4096) return 0;
    uint64_t s = shape(w, h, fmt);
    return p->shape_count && bsearch(&s, p->shapes, p->shape_count, sizeof s, shape_cmp) != NULL;
}
/* the first entry whose key is crc */
static unsigned first_of(const Texpack *p, uint32_t crc){
    unsigned lo = 0, hi = p->count;
    while (lo < hi){
        unsigned m = lo + (hi - lo) / 2;
        if (p->entries[m].crc < crc) lo = m + 1; else hi = m;
    }
    return lo;
}
int texpack_find(const Texpack *p, const uint8_t *data, size_t size, uint32_t crc,
                 unsigned w, unsigned h, unsigned fmt){
    if (texpack_may_match(p, w, h, fmt) && size == level_size(w, h, fmt)){
        uint32_t adler = 0; int have = 0;
        for (unsigned i = first_of(p, crc); i < p->count && p->entries[i].crc == crc; i++){
            const TexpackEntry *e = &p->entries[i];
            if (keyed(e)) continue;
            if (!have){ adler = (uint32_t)adler32(1, data, (uInt)size); have = 1; }
            if (e->adler == adler && e->ow == w && e->oh == h && e->ofmt == fmt) return (int)i;
        }
    }
    if (p->texmod_count){
        uint32_t tm = ~crc;          /* TexMod leaves out CRC-32's final inversion */
        for (unsigned i = first_of(p, tm); i < p->count && p->entries[i].crc == tm; i++)
            if (keyed(&p->entries[i]) && p->entries[i].ofmt == TEXPACK_KEY_TEXMOD) return (int)i;
    }
    return -1;
}
int texpack_find_name(const Texpack *p, uint32_t name_hash){
    if (!p->name_count) return -1;
    for (unsigned i = first_of(p, name_hash); i < p->count && p->entries[i].crc == name_hash; i++)
        if (keyed(&p->entries[i]) && p->entries[i].ofmt == TEXPACK_KEY_NAME) return (int)i;
    return -1;
}
int texpack_read(const Texpack *p, unsigned index, void *data, size_t size){
    return index < p->count && size == p->entries[index].size && read_at(p->fd, data, size, p->entries[index].off);
}
const char *texpack_name(const Texpack *p, unsigned index){
    return index < p->count ? p->names + p->entries[index].name - p->names_at : "?";
}
