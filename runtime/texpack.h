/* texpack.h -- NTXP texture packs (texrep.m).  The launcher writes them (UHUDPack.swift,
 * after th0mk's nfsu2-web tools/texpacks.py, and TexturePacks.swift).  Immutable
 * metadata, thread-safe payload reads.
 *
 * Each entry says which of the game's textures it replaces, by one of three keys:
 *   content  CRC-32 and Adler-32 of level 0 as the game uploads it, with its size and
 *            format (versions 1 and 2)
 *   TexMod   TexMod's hash of level 0 (CRC-32 without the final inversion), any size
 *            and format (version 2: ow = oh = 0, ofmt = TEXPACK_KEY_TEXMOD)
 *   name     the game's name hash of the texture (bStringHash), as TexWizard and the
 *            game's own files name it (version 2: ow = oh = 0, ofmt = TEXPACK_KEY_NAME) */
#ifndef TEXPACK_H
#define TEXPACK_H
#include <stddef.h>
#include <stdint.h>

enum { TEXPACK_KEY_TEXMOD = 1, TEXPACK_KEY_NAME = 2 };

typedef struct {
    uint32_t crc, adler;          /* content: CRC-32, Adler-32; TexMod: its hash, 0; name: the hash, 0 */
    uint16_t ow, oh;              /* the game's texture; 0, 0: a TexMod or name key */
    uint32_t ofmt;                /* its D3DFORMAT, or TEXPACK_KEY_* */
    uint16_t w, h;
    uint32_t fmt, levels, off, size, name;
} TexpackEntry;
typedef struct {
    int fd;
    unsigned count, shape_count;
    unsigned texmod_count, name_count;   /* entries with those keys */
    TexpackEntry *entries;
    uint64_t *shapes;
    char *names;
    uint32_t names_at;
} Texpack;

int texpack_open(Texpack *p, const char *path, char *err, size_t err_size);
void texpack_close(Texpack *p);
/* a texture of this size and format may have a content entry */
int texpack_may_match(const Texpack *p, unsigned w, unsigned h, unsigned fmt);
/* the entry for level 0 of a texture (size bytes; crc: zlib's CRC-32 of them), or -1:
 * a content entry, otherwise a TexMod one */
int texpack_find(const Texpack *p, const uint8_t *data, size_t size, uint32_t crc,
                 unsigned w, unsigned h, unsigned fmt);
/* the entry for a texture's name hash, or -1 */
int texpack_find_name(const Texpack *p, uint32_t name_hash);
int texpack_read(const Texpack *p, unsigned index, void *data, size_t size);
const char *texpack_name(const Texpack *p, unsigned index);
#endif
