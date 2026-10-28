/* Native binding checks: clang -fobjc-arc -Iruntime tests/texrep_native_unit.m
 * runtime/texpack.c -lz -framework Cocoa -framework Metal -o /tmp/texrep-native */
#include "../runtime/texrep.m"
#include <assert.h>
#include <zlib.h>

uint8_t *g_mem;
uint8_t g_cbits[1u << 15];
static id<MTLDevice> device;
static id<MTLTexture> original;
id<MTLDevice> metal_device(void){ return device; }
id<MTLTexture> metal_tex_object(unsigned mid){ (void)mid; return original; }
const char *fileio_last_read(void){ return "GLOBAL/InGameCommon.lzc"; }
int fileio_resolve_game(const char *win, char *out, size_t outsz){
    (void)win; (void)out; (void)outsz; return 0;
}
static void put32(uint8_t *p, uint32_t v){ for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i)); }
static void write_dds(const char *dir, unsigned w, char *path, size_t path_size){
    size_t n = (size_t)w * w * 4;
    uint8_t *pixels = calloc(1, n), *dds = calloc(1, 128 + n * 4); assert(pixels && dds);
    uint64_t seed = (uint64_t)w | (uint64_t)w << 16 | (uint64_t)21 << 32;
    uint64_t hash = XXH3_64bits_withSeed(pixels, n, seed);
    snprintf(path, path_size, "%s/test_%016llx.dds", dir, (unsigned long long)hash);
    memcpy(dds, "DDS ", 4); put32(dds + 4, 124); put32(dds + 12, w * 2); put32(dds + 16, w * 2);
    put32(dds + 28, 1); put32(dds + 80, 0x40); put32(dds + 88, 32); put32(dds + 92, 0xff0000);
    FILE *f = fopen(path, "wb"); assert(f); assert(fwrite(dds, 1, 128 + n * 4, f) == 128 + n * 4); fclose(f);
    free(pixels); free(dds);
}
int main(int argc, char **argv){ @autoreleasepool {
    int with_dds = argc > 1 && !strcmp(argv[1], "--dds");
    if (argc > 1 && !with_dds){
        setenv("NFSU2_UI_TEXTURES", "uhud", 1); setenv("NFSU2_UI_TEXPACK", argv[1], 1);
        setenv("NFSU2_TEXTURES", "original", 1); setenv("NFSU2_GRAPHICS", "original", 1);
        device = MTLCreateSystemDefaultDevice();
        if (!device){ puts("SKIP real pack GPU uploads (no Metal device)"); return 77; }
        tr_init(); assert(g_ui_pack.count);
        for (unsigned i = 0; i < g_ui_pack.count; i++){
            const TexpackEntry *e = &g_ui_pack.entries[i];
            load_job(0, argv[1], (int)i, e->ow, e->oh, 1, e->ofmt);
            assert(g_ready_n == 1);
            Ready r = g_ready[0]; g_ready_n = 0;
            assert(!r.fail && !r.k && !r.stacked);
            id<MTLTexture> t = CFBridgingRelease(r.tex);
            assert(t.width == e->w && t.height == e->h && t.mipmapLevelCount == e->levels);
            t = nil; atomic_fetch_sub(&g_bytes, r.bytes);
        }
        printf("PASS real pack GPU uploads: %u textures\n", g_ui_pack.count); return 0;
    }
    uint8_t pixels[256] = {0}, pack[1120] = {0};
    memcpy(pack, "NTXP", 4); put32(pack + 4, 1); put32(pack + 8, 1);
    put32(pack + 16, (uint32_t)crc32(0, pixels, sizeof pixels));
    put32(pack + 20, (uint32_t)adler32(1, pixels, sizeof pixels));
    put32(pack + 24, 0x00080008); put32(pack + 28, 21);
    put32(pack + 32, 0x00100010); put32(pack + 36, 21); put32(pack + 40, 1);
    put32(pack + 44, 96); put32(pack + 48, 1024); put32(pack + 52, 56);
    memcpy(pack + 56, "small-icon", 11);
    char path[] = "/tmp/nfsu2-native-pack-XXXXXX";
    int fd = mkstemp(path); assert(fd >= 0);
    assert(write(fd, pack, sizeof pack) == sizeof pack); close(fd);
    setenv("NFSU2_UI_TEXTURES", "uhud", 1); setenv("NFSU2_UI_TEXPACK", path, 1);
    setenv("NFSU2_TEXTURES", "original", 1); setenv("NFSU2_GRAPHICS", "original", 1);
    char ddsdir[] = "/tmp/nfsu2-native-dds-XXXXXX", dds1[256] = {0}, dds2[256] = {0};
    if (with_dds){
        assert(mkdtemp(ddsdir)); write_dds(ddsdir, 8, dds1, sizeof dds1); write_dds(ddsdir, 64, dds2, sizeof dds2);
        setenv("NFSU2_TEXTURES", "upscaled", 1); setenv("NFSU2_GRAPHICS", "custom", 1);
        setenv("NFSU2_TEXPACK", ddsdir, 1); setenv("NFSU2_TEXPARTS", "all", 1);
    }
    device = MTLCreateSystemDefaultDevice();
    texrep_created(1, 8, 8, 4, 21, 0, 1);
    assert(g_active && g_tr[1].ok && g_tr[1].ui);
    assert(g_tr[1].w == 8 && g_tr[1].h == 8 && g_tr[1].lev == 4);
    texrep_created(2, 8, 8, 1, 21, 0x200, 1); assert(!g_tr[2].ok);
    texrep_created(3, 8, 8, 1, 21, 0, 0); assert(!g_tr[3].ok);
    texrep_uploaded(1, 0, pixels, 32, 8); assert(g_tr[1].state == S_PENDING);
    assert(g_ent[g_tr[1].ent].ui == 0); /* matching UHUD takes precedence over a DDS */
    for (int i = 0; i < NLQ; i++) dispatch_sync(g_lq[i], ^{});
    texrep_frame();
    if (!device){
        assert(g_tr[1].state == S_NONE);
        puts("PASS native UHUD eligibility and safe no-device fallback; SKIP GPU bindings (no Metal device)");
        unlink(path); if (with_dds){ unlink(dds1); unlink(dds2); rmdir(ddsdir); } return 0;
    }
    id<MTLCommandQueue> q = [device newCommandQueue];
    original = [device newTextureWithDescriptor:[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:8 height:8 mipmapped:YES]];
    texrep_main_frame(q);
    assert(g_tr[1].state == S_ACTIVE && g_texrep_tex[1].width == 16 && g_texrep_tex[1].height == 16);
    assert(g_texrep_tex[1].mipmapLevelCount == 1 && g_texrep_k[1] == 0);
    assert(original.width == 8 && original.height == 8 && g_tr[1].w == 8);
    assert(texrep_pick(1, original) == g_texrep_tex[1]);
    texrep_set_shown(0); texrep_main_frame(q); assert(texrep_pick(1, original) == original);
    texrep_set_shown(1); texrep_main_frame(q); assert(texrep_pick(1, original) != original);
    texrep_uploaded(1, 1, pixels, 16, 4); texrep_main_frame(q);
    assert(g_texrep_tex[1].mipmapLevelCount == 1); /* guest mips never overwrite UHUD */
    texrep_created(4, 8, 8, 1, 21, 0, 1); texrep_uploaded(4, 0, pixels, 32, 8);
    texrep_frame(); texrep_main_frame(q);
    assert(g_tr[4].state == S_ACTIVE && g_texrep_tex[4] == g_texrep_tex[1]);
    pixels[0] = 1; texrep_uploaded(1, 0, pixels, 32, 8); texrep_main_frame(q);
    assert(!g_texrep_tex[1] && g_texrep_tex[4]);
    texrep_surface_written(4); texrep_main_frame(q); assert(!g_texrep_tex[4]);
    texrep_released(1); texrep_released(4); texrep_main_frame(q);
    if (with_dds){
        uint8_t other[64 * 64 * 4] = {0};
        texrep_created(5, 64, 64, 1, 21, 0, 1); texrep_uploaded(5, 0, other, 256, 64);
        assert(g_tr[5].state == S_PENDING && g_ent[g_tr[5].ent].ui == -1);
        for (int i = 0; i < NLQ; i++) dispatch_sync(g_lq[i], ^{});
        texrep_frame(); texrep_main_frame(q);
        assert(g_texrep_tex[5].width == 128 && g_texrep_tex[5].height == 128);
        texrep_released(5); texrep_main_frame(q);
        unlink(dds1); unlink(dds2); rmdir(ddsdir);
        puts("PASS existing DDS replacements coexist with UHUD and honor overlap precedence");
    }
    assert(!atomic_load(&g_bytes));
    unlink(path); puts("PASS native UHUD binding, original dimensions, sharing, toggle and dynamic invalidation");
    return 0;
} }
