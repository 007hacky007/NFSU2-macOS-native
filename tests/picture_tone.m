// tests/picture_tone.m - Exposure and White Level (runtime/picture.m pic_tone) on the GPU:
// a row of grey levels drawn, the pass run over it in place, read back and compared with
// the curve on the CPU (nfsu2-web's TONE); the settings as NFSU2_EXPOSURE and
// NFSU2_WHITE_LEVEL give them.  Needs a Metal device (SKIP without one).
//   picture_tone <stops> <percent> <want mult> <want white>
#import <Metal/Metal.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

int pic_tone_params(float *mult, float *white, float *knee);
void pic_tone(id<MTLDevice> dev, id<MTLCommandBuffer> cb, id<MTLTexture> scr);

static float curve(float c, float mult, float white, float knee){
    float y = fminf(c * mult, 1.f), s = knee * white;
    if (y <= s) return y;
    float m = (1.f - s) / (white - s), t = (y - s) / (1.f - s);
    return s + (white - s) * (m * t) / (1.f + (m - 1.f) * t);
}

int main(int argc, char **argv){
    @autoreleasepool {
        if (argc < 5){ fprintf(stderr, "usage: picture_tone <stops> <percent> <mult> <white>\n"); return 2; }
        if (argv[1][0]) setenv("NFSU2_EXPOSURE", argv[1], 1); else unsetenv("NFSU2_EXPOSURE");
        if (argv[2][0]) setenv("NFSU2_WHITE_LEVEL", argv[2], 1); else unsetenv("NFSU2_WHITE_LEVEL");
        float want_mult = (float)atof(argv[3]), want_white = (float)atof(argv[4]);
        float mult, white, knee;
        int on = pic_tone_params(&mult, &white, &knee);
        int fails = 0;
        int want_on = fabsf(want_mult - 1.f) > 1e-4f || want_white < 0.9999f;
        if (fabsf(mult - want_mult) > 1e-4f || fabsf(white - want_white) > 1e-4f || on != want_on){
            printf("FAIL  settings '%s' '%s': x%.4f white %.2f %s (want x%.4f white %.2f %s)\n", argv[1], argv[2],
                   mult, white, on ? "on" : "off", want_mult, want_white, want_on ? "on" : "off");
            return 1;
        }
        printf("PASS  settings '%s' '%s': x%.4f, white %.0f %%, the pass %s\n", argv[1], argv[2], mult, white * 100.f, on ? "on" : "off");
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev){ printf("SKIP  no Metal device\n"); return 0; }
        enum { W = 64 };
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:W height:1 mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModeShared;
        id<MTLTexture> t = [dev newTextureWithDescriptor:td];
        uint8_t px[W * 4], out[W * 4];
        for (int i = 0; i < W; i++){ uint8_t v = (uint8_t)lrintf(255.f * (float)i / (W - 1));
            px[4 * i] = v; px[4 * i + 1] = (uint8_t)(255 - v); px[4 * i + 2] = v; px[4 * i + 3] = 200; }
        [t replaceRegion:MTLRegionMake2D(0, 0, W, 1) mipmapLevel:0 withBytes:px bytesPerRow:W * 4];
        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        pic_tone(dev, cb, t);
        [cb commit]; [cb waitUntilCompleted];
        [t getBytes:out bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, 1) mipmapLevel:0];
        int worst = 0, alpha = 1, top = 0;
        for (int i = 0; i < W * 4; i++){
            if (i % 4 == 3){ alpha &= out[i] == px[i]; continue; }
            int want = on ? (int)lrintf(255.f * curve((float)px[i] / 255.f, mult, white, knee)) : px[i];
            int d = abs((int)out[i] - want);
            if (d > worst) worst = d;
            if (out[i] > top) top = out[i];
        }
        if (worst <= 1) printf("PASS  %d channels as the curve has them (worst %d of 255)\n", W * 3, worst);
        else { printf("FAIL  a channel %d of 255 off the curve\n", worst); fails++; }
        if (alpha) printf("PASS  alpha as drawn\n"); else { printf("FAIL  alpha changed\n"); fails++; }
        int cap = (int)lrintf(255.f * (on ? white : 1.f));
        if (top <= cap + 1) printf("PASS  the brightest %d, at most the white level's %d\n", top, cap);
        else { printf("FAIL  the brightest %d over the white level's %d\n", top, cap); fails++; }
        return fails != 0;
    }
}
