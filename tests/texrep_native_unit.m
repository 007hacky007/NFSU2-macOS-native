/* tests/texrep_native_unit.m -- runtime/texrep.m with a real Metal device and no game:
 *   - an NTXP pack (UHUD-style) replaces a texture by content, shares one texture between
 *     ids, Cmd-T hides it, a new upload of other content or a surface write takes it away;
 *   - the DDS pack (the upscaled texture pack): a whole replacement, and a stacked one whose
 *     levels stop above the original's (the game's own levels blitted under them, the LOD
 *     clamp in the sampler key), shared between ids with the same content, given back on the
 *     last release (GPU memory back to 0), dropped when the content changes;
 *   - an NTXP pack wins over the DDS pack for the same texture;
 *   - parts left out are not used; collected textures (NFSU2_TEXDUMP) are written;
 *   - with --budget, a GPU memory budget too small for a file: the game's own stays.
 * Build and run: tests/texture_unit.sh.  Old fork's tests/texrep_native_unit.m, adapted. */
#include "../runtime/texrep.m"
#include <assert.h>
#include <zlib.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15] = {0};
static id<MTLDevice> device;
static id<MTLTexture> originals[64];
id<MTLDevice> metal_device(void){ return device; }
id<MTLTexture> metal_tex_object(unsigned mid){ return mid < 64 ? originals[mid] : nil; }
int fileio_game_path(const char *win, char *out, size_t outsz){ (void)win; (void)out; (void)outsz; return 0; }

static void put32(uint8_t *p, uint32_t v){ for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i)); }
static uint64_t seed_of(unsigned w, unsigned h, unsigned fmt){ return (uint64_t)w | (uint64_t)h << 16 | (uint64_t)fmt << 32; }
/* a DDS of w x h, levels levels, format fmt (21 or DXT1) named after the hash of `content` */
static void write_dds(const char *dir, const char *part, unsigned ow, unsigned oh, unsigned ofmt,
                      const uint8_t *content, size_t clen, unsigned w, unsigned h, unsigned levels){
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, part); mkdir(path, 0755);
    uint64_t hash = XXH3_64bits_withSeed(content, clen, seed_of(ow, oh, ofmt));
    snprintf(path, sizeof path, "%s/%s/test_%016llx.dds", dir, part, (unsigned long long)hash);
    size_t n = 0;
    for (unsigned l = 0; l < levels; l++){
        unsigned lw = w >> l, lh = h >> l;
        n += ofmt == 21 ? (size_t)lw * lh * 4 : (size_t)((lw + 3) / 4) * ((lh + 3) / 4) * 8;
    }
    uint8_t *dds = calloc(1, 128 + n); assert(dds);
    memcpy(dds, "DDS ", 4); put32(dds + 4, 124); put32(dds + 12, h); put32(dds + 16, w); put32(dds + 28, levels);
    if (ofmt == 21){ put32(dds + 80, 0x41); put32(dds + 88, 32); put32(dds + 92, 0xff0000); }
    else { put32(dds + 80, 4); put32(dds + 84, ofmt); }
    memset(dds + 128, 0x5a, n);
    FILE *f = fopen(path, "wb"); assert(f); assert(fwrite(dds, 1, 128 + n, f) == 128 + n); fclose(f);
    free(dds);
}
static void drain(void){
    for (int i = 0; i < NLQ; i++) if (g_dlq[i]) dispatch_sync(g_dlq[i], ^{});
    if (g_lq) dispatch_sync(g_lq, ^{});
}
static id<MTLTexture> make_original(unsigned mid, MTLPixelFormat pf, unsigned w, unsigned h, unsigned levels){
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf width:w height:h mipmapped:levels > 1];
    td.mipmapLevelCount = levels; td.storageMode = MTLStorageModeShared;
    originals[mid] = [device newTextureWithDescriptor:td];
    return originals[mid];
}

int main(int argc, char **argv){ @autoreleasepool {
    int budget = argc > 1 && !strcmp(argv[1], "--budget");
    device = MTLCreateSystemDefaultDevice();
    if (!device){ puts("SKIP texrep native (no Metal device)"); return 77; }
    id<MTLCommandQueue> q = [device newCommandQueue];
    char tmpl[1024]; snprintf(tmpl, sizeof tmpl, "%s/nfsu2-texrep-XXXXXX", getenv("TMPDIR") ? getenv("TMPDIR") : "/tmp");
    char *root = mkdtemp(tmpl); assert(root);
    char ddsdir[1100], dumpdir[1100], packpath[1100];
    snprintf(ddsdir, sizeof ddsdir, "%s/pack", root); mkdir(ddsdir, 0755);
    snprintf(dumpdir, sizeof dumpdir, "%s/collected", root);
    snprintf(packpath, sizeof packpath, "%s/ui.ntxp", root);

    /* NTXP v1: a 40x40 A8R8G8B8 texture of zeros -> 80x80 */
    static uint8_t pixels[40 * 40 * 4], pack[96 + 80 * 80 * 4];
    memcpy(pack, "NTXP", 4); put32(pack + 4, 1); put32(pack + 8, 1);
    put32(pack + 16, (uint32_t)crc32(0, pixels, sizeof pixels));
    put32(pack + 20, (uint32_t)adler32(1, pixels, sizeof pixels));
    put32(pack + 24, 0x00280028); put32(pack + 28, 21);
    put32(pack + 32, 0x00500050); put32(pack + 36, 21); put32(pack + 40, 1);
    put32(pack + 44, 96); put32(pack + 48, 80 * 80 * 4); put32(pack + 52, 56);
    memcpy(pack + 56, "small-icon", 11);
    FILE *f = fopen(packpath, "wb"); assert(f); assert(fwrite(pack, 1, sizeof pack, f) == sizeof pack); fclose(f);

    /* DDS pack: (a) 64x64 A8R8G8B8 of zeros -> 128x128 with its own 64x64 level (whole);
     * (b) 64x64 DXT1, 7 levels -> 256x256 DXT1, 2 levels (stacked, k = 2);
     * (c) the NTXP texture's content (40x40) as DDS too (the NTXP pack must win);
     * (d) a 64x64 one in "sky", a part that is not used */
    static uint8_t argb64[64 * 64 * 4], dxt64[16 * 16 * 8], sky64[64 * 64 * 4];
    for (size_t i = 0; i < sizeof dxt64; i++) dxt64[i] = (uint8_t)(i * 37 + 11);
    memset(sky64, 7, sizeof sky64);
    write_dds(ddsdir, "world", 64, 64, 21, argb64, sizeof argb64, 128, 128, 2);
    write_dds(ddsdir, "cars", 64, 64, FMT_DXT1, dxt64, sizeof dxt64, 256, 256, 2);
    write_dds(ddsdir, "world", 40, 40, 21, pixels, sizeof pixels, 80, 80, 1);
    write_dds(ddsdir, "sky", 64, 64, 21, sky64, sizeof sky64, 128, 128, 1);

    setenv("NFSU2_TEXPACKS", packpath, 1);
    setenv("NFSU2_TEXTURES", "upscaled", 1); setenv("NFSU2_TEXPACK", ddsdir, 1);
    setenv("NFSU2_TEXPARTS", "world,cars", 1); setenv("NFSU2_TEXDUMP", dumpdir, 1);
    if (budget) setenv("NFSU2_TEXBUDGET", "0.01", 1);
    texrep_note_read("/game/TRACKS/STREAML4RA.BUN");

    if (budget){
        make_original(5, MTLPixelFormatBGRA8Unorm, 64, 64, 1);
        texrep_created(5, 64, 64, 1, 21, 0, 1, 0); texrep_uploaded(5, 0, argb64, 256, 64);
        drain(); texrep_frame(); texrep_main_frame(q);
        assert(!g_texrep_tex[5] && g_tr[5].state == S_NONE && g_n_budget == 1 && !atomic_load(&g_bytes));
        puts("PASS DDS pack: a file over the GPU memory budget leaves the game's own texture");
        return 0;
    }

    /* --- NTXP: id 1 and 4 share, Cmd-T, dynamic content, surface writes --- */
    make_original(1, MTLPixelFormatBGRA8Unorm, 40, 40, 4);
    texrep_created(1, 40, 40, 4, 21, 0, 1, 0);
    assert(g_t[1].ok && g_dds_on && g_npack == 1);
    texrep_created(2, 40, 40, 1, 21, 0x200, 1, 0); assert(!g_t[2].ok && !g_tr[2].ok);   /* dynamic usage */
    texrep_created(3, 40, 40, 1, 21, 0, 0, 0); assert(!g_t[3].ok && !g_tr[3].ok);       /* default pool */
    texrep_uploaded(1, 0, pixels, 160, 40);
    assert(g_t[1].want == 0 && g_tr[1].state == S_NONE);    /* the NTXP pack wins; the DDS (c) is not loaded */
    drain(); texrep_frame(); texrep_main_frame(q);
    assert(g_texrep_tex[1].width == 80 && g_texrep_tex[1].height == 80 && g_texrep_k[1] == 0);
    assert(texrep_pick(1, originals[1]) == g_texrep_tex[1]);
    texrep_set_shown(0); texrep_main_frame(q); assert(texrep_pick(1, originals[1]) == originals[1]);
    texrep_set_shown(1); texrep_main_frame(q); assert(texrep_pick(1, originals[1]) != originals[1]);
    texrep_uploaded(1, 1, pixels, 80, 20); texrep_main_frame(q);
    assert(g_texrep_tex[1].mipmapLevelCount == 1);           /* the game's mips never overwrite an NTXP texture */
    texrep_created(4, 40, 40, 1, 21, 0, 1, 0); texrep_uploaded(4, 0, pixels, 160, 40);
    texrep_frame(); texrep_main_frame(q);
    assert(g_texrep_tex[4] == g_texrep_tex[1]);
    pixels[0] = 1; texrep_uploaded(1, 0, pixels, 160, 40); texrep_main_frame(q);
    assert(!g_texrep_tex[1] && g_texrep_tex[4]);
    texrep_surface_written(4); texrep_main_frame(q); assert(!g_texrep_tex[4]);
    puts("PASS NTXP pack: binding, original dimensions, sharing, Cmd-T, dynamic content, surface writes");

    /* --- DDS (a): a whole replacement, shared by ids 10 and 11 --- */
    make_original(10, MTLPixelFormatBGRA8Unorm, 64, 64, 1);
    make_original(11, MTLPixelFormatBGRA8Unorm, 64, 64, 1);
    texrep_created(10, 64, 64, 1, 21, 0, 1, 0); texrep_uploaded(10, 0, argb64, 256, 64);
    assert(g_tr[10].ok && g_tr[10].state == S_PENDING);
    drain(); texrep_frame(); texrep_main_frame(q);
    assert(g_tr[10].state == S_ACTIVE && g_texrep_tex[10].width == 128 && g_texrep_tex[10].mipmapLevelCount == 2);
    assert(g_texrep_k[10] == 1);                              /* 2x: the clamp is at level 1 */
    assert(texrep_skey(10, 0x25u) == 0x25u && texrep_skey(10, 0x05u) == (0x25u | (1u << 15)));   /* mip filter linear / none */
    texrep_created(11, 64, 64, 1, 21, 0, 1, 0); texrep_uploaded(11, 0, argb64, 256, 64);
    texrep_frame(); texrep_main_frame(q);
    assert(g_texrep_tex[11] == g_texrep_tex[10] && g_n_shared == 1 && g_n_tex_live == 1);
    unsigned long long held = atomic_load(&g_bytes); assert(held > 0);
    puts("PASS DDS pack: whole replacement, LOD clamp in the sampler key, two ids share one texture");

    /* --- DDS (b): stacked, the game's own levels under the pack's --- */
    id<MTLTexture> o20 = make_original(20, MTLPixelFormatBC1_RGBA, 64, 64, 7);
    static uint8_t lv[2048];
    for (unsigned l = 0; l < 7; l++){
        unsigned lw = 64 >> l; if (!lw) lw = 1;
        size_t row = (size_t)((lw + 3) / 4) * 8, rows = (lw + 3) / 4;
        memset(lv, 0x30 + (int)l, row * rows);
        [o20 replaceRegion:MTLRegionMake2D(0, 0, lw, lw) mipmapLevel:l withBytes:lv bytesPerRow:row];
    }
    texrep_created(20, 64, 64, 7, FMT_DXT1, 0, 1, 0);
    texrep_uploaded(20, 0, dxt64, 16 * 8, 16);
    drain(); texrep_frame(); texrep_main_frame(q);
    assert(g_tr[20].state == S_PENDING);                      /* waits for the game's lower levels */
    for (unsigned l = 1; l < 7; l++){
        unsigned lw = 64 >> l; size_t row = (size_t)((lw + 3) / 4) * 8, rows = (lw + 3) / 4;
        memset(lv, 0x30 + (int)l, row * rows);
        texrep_uploaded(20, l, lv, (unsigned)row, (unsigned)rows);
    }
    texrep_frame(); texrep_main_frame(q);
    id<MTLTexture> r20 = g_texrep_tex[20];
    assert(g_tr[20].state == S_ACTIVE && r20.width == 256 && r20.mipmapLevelCount == 9 && g_texrep_k[20] == 2);
    id<MTLCommandBuffer> cb = [q commandBuffer]; [cb commit]; [cb waitUntilCompleted];   /* after texrep's blit */
    uint8_t got[8];
    [r20 getBytes:got bytesPerRow:8 fromRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:3];   /* = the game's level 1 */
    assert(got[0] == 0x31 && got[7] == 0x31);
    [r20 getBytes:got bytesPerRow:8 fromRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0];   /* the pack's */
    assert(got[0] == 0x5a);
    puts("PASS DDS pack: stacked replacement, the game's own levels under the pack's two");

    /* --- the part left out, collected textures, release, dynamic --- */
    make_original(30, MTLPixelFormatBGRA8Unorm, 64, 64, 1);
    texrep_created(30, 64, 64, 1, 21, 0, 1, 0); texrep_uploaded(30, 0, sky64, 256, 64);
    assert(g_tr[30].state == S_NONE && g_idx_skipped == 1);
    argb64[0] = 9; texrep_uploaded(10, 0, argb64, 256, 64); texrep_main_frame(q);   /* other content: dynamic */
    assert(g_tr[10].dyn && !g_texrep_tex[10] && g_texrep_tex[11]);
    texrep_released(11); texrep_released(20); texrep_frame(); texrep_main_frame(q);
    assert(!g_texrep_tex[11] && !g_texrep_tex[20] && !g_n_tex_live && !atomic_load(&g_bytes));
    texrep_report();
    char ix[1200]; snprintf(ix, sizeof ix, "%s/index.csv", dumpdir);
    FILE *x = fopen(ix, "r"); assert(x);
    char line[512]; int rows = 0, track = 0;
    while (fgets(line, sizeof line, x)){ rows++; if (strstr(line, ",world,TRACKS/STREAML4RA.BUN")) track++; }
    fclose(x);
    assert(rows == 5 && track == 4);              /* the header and four contents, each once */
    printf("PASS DDS pack: a part left out, %d textures collected, dynamic content dropped, memory given back (held %llu bytes)\n",
           rows - 1, held);
    return 0;
} }
