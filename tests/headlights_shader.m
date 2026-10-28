#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "vsemu.h"
#include "headlights.h"
#include <assert.h>

static const uint32_t light_shader[] = {
    0xffff0101,
    66, 0xb00f0000, 66, 0xb00f0001, 66, 0xb00f0002,
    5, 0x80070001, 0xb0e40001, 0xb0e40002,
    4, 0x80070001, 0x80e40001, 0xa0e40000, 0x90e40000,
    5, 0x800f0000, 0x80e40001, 0xb0e40000,
    0xffff
};
static const char *prelude =
    "#include <metal_stdlib>\nusing namespace metal;\n"
    "struct VOut { float4 pos [[position]]; float4 col0; float4 col1; float4 uv0; float4 uv1; float4 uv2; float4 uv3; float fog; };\n"
    "struct PSPar { float aref, usec, pad0, pad1; float4 proj; float4 c[32]; float4 fog; };\n"
#if NFS_ENHANCED
    "struct PSOut { float4 c0 [[color(0)]]; float4 c1 [[color(1)]]; float4 c2 [[color(2)]]; float4 c3 [[color(3)]]; };\n"
#endif
    "vertex VOut vertex_main(uint id [[vertex_id]]) { float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; VOut o; o.pos=float4(p[id],0,1); o.col0=float4(0.1,0.1,0.1,1); o.col1=0; o.uv0=o.uv1=o.uv2=o.uv3=float4(0.5,0.5,0,1); o.fog=1; return o; }\n";

static id<MTLRenderPipelineState> pipeline(id<MTLDevice> device, const uint32_t *code, size_t length, unsigned cubemask) {
    VSProg *program = vs_compile(code, length); assert(program && !vs_unknown(program));
    char source[32768]; assert(ps_to_msl_ex(program, 1, source, sizeof source, cubemask));
    vs_free(program);
    NSError *error = nil;
    NSString *msl = [[NSString stringWithUTF8String:prelude] stringByAppendingString:[NSString stringWithUTF8String:source]];
    id<MTLLibrary> library = [device newLibraryWithSource:msl options:nil error:&error];
    if (!library) { fprintf(stderr, "%s\n%s\n", error.localizedDescription.UTF8String, source); abort(); }
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [library newFunctionWithName:@"vertex_main"];
    desc.fragmentFunction = [library newFunctionWithName:@"ps_1"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> result = [device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!result) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); abort(); }
    return result;
}
static void pixel(id<MTLDevice> device, id<MTLRenderPipelineState> pso, HeadlightsBlock block, const float expected[3], int patterned) {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; desc.storageMode = MTLStorageModeShared;
    id<MTLTexture> target = [device newTextureWithDescriptor:desc];
    desc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> white = [device newTextureWithDescriptor:desc];
    uint8_t value[4] = {255,255,255,255};
    [white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:value bytesPerRow:4];
    id<MTLTexture> mask = white, ramp = white;
    if (patterned) {
        desc.width = 2;
        mask = [device newTextureWithDescriptor:desc]; ramp = [device newTextureWithDescriptor:desc];
        uint8_t steps[8] = {0,0,0,255,255,255,255,255};
        [mask replaceRegion:MTLRegionMake2D(0,0,2,1) mipmapLevel:0 withBytes:steps bytesPerRow:8];
        [ramp replaceRegion:MTLRegionMake2D(0,0,2,1) mipmapLevel:0 withBytes:steps bytesPerRow:8];
    }
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target; pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandQueue> queue = [device newCommandQueue]; id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [command renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:pso];
    MTLSamplerDescriptor *samplerDesc = [MTLSamplerDescriptor new];
    samplerDesc.sAddressMode = samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor:samplerDesc];
    for (int i = 0; i < 4; i++) { [enc setFragmentTexture:white atIndex:i]; [enc setFragmentSamplerState:sampler atIndex:i]; }
    [enc setFragmentTexture:mask atIndex:1]; [enc setFragmentTexture:ramp atIndex:2];
    struct { float aref, usec, pad0, pad1, proj[4], c[32][4], fog[4]; } params = {0};
    params.c[0][0] = params.c[0][1] = params.c[0][2] = 0.2f; params.c[0][3] = 1;
    [enc setFragmentBytes:&params length:sizeof params atIndex:0];
    [enc setFragmentBytes:&block length:sizeof block atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [enc endEncoding];
    [command commit]; [command waitUntilCompleted]; assert(command.status == MTLCommandBufferStatusCompleted);
    uint8_t actual[4]; [target getBytes:actual bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
    for (int i = 0; i < 3; i++) {
        if (abs(actual[i] - (int)lroundf(expected[i] * 255)) > 2) {
            fprintf(stderr, "headlight pixel channel %d: got %u, expected %.3f\n", i, actual[i], expected[i]); abort();
        }
    }
}
int main(void) { @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); assert(device);
    id<MTLRenderPipelineState> lit = pipeline(device, light_shader, sizeof light_shader / 4, 0);
    HeadlightsBlock block = {0};
    const float base[3] = {0.3f,0.3f,0.3f}, more[3] = {0.6f,0.7f,0.8f};
    pixel(device, lit, block, base, 0);
    block.n = 1; block.s = 0.005f; block.o = 0.5f;
    for (int i = 0; i < 4; i++) block.l[0].t[i * 5] = 1;
    block.l[0].col[0] = 0.3f; block.l[0].col[1] = 0.4f; block.l[0].col[2] = 0.5f;
    pixel(device, lit, block, more, 0);
    block.l[0].t[15] = -1; pixel(device, lit, block, base, 0);
    uint32_t unrelated[sizeof light_shader / 4]; memcpy(unrelated, light_shader, sizeof unrelated);
    unrelated[14] = 0xa0e40001; /* c1 is not the world-headlight colour c0. */
    id<MTLRenderPipelineState> plain = pipeline(device, unrelated, sizeof unrelated / 4, 0);
    const float diffuse[3] = {0.1f,0.1f,0.1f};
    block.l[0].t[15] = 1; pixel(device, plain, block, diffuse, 0);
    block.s = 0; block.o = 0.75f;
    pixel(device, lit, block, more, 1);
    block.l[0].t[3] = -0.5f;
    pixel(device, lit, block, base, 1);
    block.l[0].t[3] = 0; block.o = 0.25f;
    pixel(device, lit, block, base, 1);
    memset(&block, 0, sizeof block); block.n = 100;
    for (int light = 0; light < 8; light++) {
        for (int i = 0; i < 4; i++) block.l[light].t[i * 5] = 1;
        for (int i = 0; i < 3; i++) block.l[light].col[i] = 0.01f;
    }
    const float bounded[3] = {0.38f, 0.38f, 0.38f};
    pixel(device, lit, block, bounded, 0);
    puts("headlights_shader: GPU pixels preserve off/unrelated shaders, add bounded lights with projector transform/falloff and reject behind-projector light");
} }
