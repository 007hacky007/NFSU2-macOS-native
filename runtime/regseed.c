/* regseed.c -- the highest graphics settings on the first launch.
 *
 * NFSU2_SEED_REGISTRY=1 (the launcher's "Highest graphics on first launch"):
 * when there is no registry file yet (~/.nfsu2_registry, win32_ext.c), it
 * starts with the values below instead of the game's own first-run check.
 * They are what that check writes on this runtime (it always picks
 * performance level 4: the GPU is reported as a GeForce 6800 and rdtsc runs
 * at 3 GHz, so the check is deterministic), raised to the highest the game's
 * options go: performance level 5, car reflections 3, world detail 3,
 * texture filtering 2, 4x anti-aliasing off (-1), and racing resolution row
 * 3.  NotFirstTime=1 is part of that state, so the game takes them as its
 * own.
 *
 * How it lives with the first-run repair in win32_ext.c (PortSettingsRepaired):
 * the seed only acts when the file does not exist; the repair only acts on an
 * existing file whose g_PerformanceLevel, g_WorldLodLevel, g_CarLodLevel and
 * g_CrowdEnable are all 0 (the old broken detection), and marks the file
 * done.  A seeded file is not that signature, so the repair only adds its
 * mark; an existing registry is never seeded over.  Without the option (the
 * original game) the game runs its first-run check.
 *
 * Ported from th0mk's nfsu2-web app/registry-defaults.txt (MIT). */
#include <stdlib.h>
#include <string.h>

static const char *const g_seed[] = {
    "d NotFirstTime=1",
    "d VERSION=1",
    "d SIZE=0",
    "d g_CarEnvironmentMapEnable=3",
    "d g_CarEnvironmentMapUpdateData=1",
    "d g_CarShadowEnable=2",
    "d g_CarHeadlightEnable=1",
    "d g_CarLightingEnable=0",
    "d g_CarDamageEnable=0",
    "d g_CrowdEnable=1",
    "d g_RoadReflectionEnable=3",
    "d g_FogEnable=1",
    "d g_MotionBlurEnable=1",
    "d g_LightStreaksEnable=1",
    "d g_LightGlowEnable=1",
    "d g_AnimatedTextureEnable=1",
    "d g_ParticleSystemEnable=1",
    "d g_DepthOfFieldEnable=1",
    "d g_WorldLodLevel=3",
    "d g_CarLodLevel=1",
    "d g_OverBrightEnable=1",
    "d g_BleachByPassEnable=1",
    "d g_TintingEnable=1",
    "d g_FSAALevel=4294967295",
    "d g_HorizonFogEnable=1",
    "d g_RainEnable=1",
    "d g_TextureFiltering=2",
    "d g_RacingResolution=3",
    "d g_PerformanceLevel=5",
    "d g_VSyncOn=0",
};

/* The seed's lines ("d name=value", the registry file's format), or 0 when
 * NFSU2_SEED_REGISTRY is not set. */
const char *const *regseed_lines(int *n){
    const char *e = getenv("NFSU2_SEED_REGISTRY");
    if (!e || strcmp(e, "1")){ *n = 0; return 0; }
    *n = (int)(sizeof g_seed / sizeof g_seed[0]);
    return g_seed;
}
