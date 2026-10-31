#!/bin/bash
# tests/upscale_pack.sh -- the launcher's upscaled texture pack builder (launcher/Upscale*.swift).
#   - XXH3-64 in Swift = runtime/xxhash.h for every length to 4 kB (the pack's file names are
#     the hash the engine computes);
#   - a made-up game folder with one TPK (DXT1, DXT5, a P8 texture, a small one, a one-colour
#     one, a smooth one): the scan finds them with the right hashes and sorts out the three;
#   - Import Model... refuses a file that is not the tested release, and the builder never
#     loads such a file;
#   - with the model (NFSU2_UPSCALE_MODEL=<4x-PBRify_UpscalerSPANV4.pth>, or the launcher's own
#     copy): the pack of the made-up folder, then of 6 textures of the real game when
#     NFSU2_DATA points at it; every file's 4x4 averages are the original texture again
#     (back-projection, at least 30 dB PSNR after block compression); Build as the button
#     does it (UpscaleStore), and in a folder with no game textures.
# Needs swiftc, clang and python3 (for the fixture); no internet.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_upscale.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fails=0
pass(){ echo "PASS  $1"; }
fail(){ echo "FAIL  $1"; fails=$((fails+1)); }

# --- XXH3 ---
cp "$ROOT/tests/upscale_hash.swift" "$T/main.swift"            # top-level code: main.swift
swiftc -swift-version 5 -O -module-cache-path "$T/cache" -o "$T/xs" "$ROOT/launcher/UpscaleHash.swift" "$T/main.swift" || { echo "FAIL: swiftc"; exit 1; }
cat > "$T/xc.c" <<'C'
#define XXH_INLINE_ALL
#include "xxhash.h"
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv){
    static unsigned char b[1 << 20];
    if (argc > 1){                        /* hash a file: xc <file> <seed> */
        FILE *f = fopen(argv[1], "rb"); size_t n = f ? fread(b, 1, sizeof b, f) : 0; if (f) fclose(f);
        unsigned long long s = strtoull(argv[2], 0, 0);
        printf("%016llx\n", (unsigned long long)XXH3_64bits_withSeed(b, n, s)); return 0;
    }
    for (int i = 0; i < 5000; i++) b[i] = (unsigned char)((i * 131 + 7) >> 3);
    unsigned long long seeds[3] = { 0, 0x1234567890ull, 64ull | 64ull << 16 | 0x31545844ull << 32 };
    for (int s = 0; s < 3; s++) for (int n = 0; n <= 4100; n++)
        printf("%llx\n", (unsigned long long)XXH3_64bits_withSeed(b, n, seeds[s]));
    return 0;
}
C
clang -O2 -I"$ROOT/runtime" -o "$T/xc" "$T/xc.c" || { echo "FAIL: clang"; exit 1; }
if cmp -s <("$T/xs") <("$T/xc"); then pass "XXH3-64 in Swift = runtime/xxhash.h (lengths 0-4100, 3 seeds)"
else fail "XXH3-64 differs from runtime/xxhash.h"; fi

# --- the launcher ---
swiftc -swift-version 5 -O -target arm64-apple-macos11.0 -import-objc-header "$ROOT/runtime/names.h" \
    -module-cache-path "$T/cache" -o "$T/launcher" "$ROOT"/launcher/*.swift || { echo "FAIL: launcher build"; exit 1; }
run(){ HOME="$T/home" NFSU2_LAUNCHER_TEST="$1" "$T/launcher" 2>&1; }
mkdir -p "$T/home"

# --- a made-up game folder: TRACKS/TEST.BUN with one TPK ---
mkdir -p "$T/game/TRACKS" "$T/lv0"
python3 -I - "$T/game/TRACKS/TEST.BUN" "$T/lv0" <<'PY'
import struct, sys, random
random.seed(7)
out, lv0 = sys.argv[1], sys.argv[2]
import math
def c565(r, g, b): return (int(r) >> 3) << 11 | (int(g) >> 2) << 5 | (int(b) >> 3)
def tex_dxt1(w, h, small=False):       # texture-like: endpoints follow a pattern, grain inside a block
    b = bytearray()
    for by in range(h // 4):
        for bx in range(w // 4):
            v = 128 + 70 * math.sin(bx / 2.0) * math.cos(by / 3.0)
            c0 = c565(v + 12, v + 6, v - 20); c1 = c565(v - 12, v - 10, v - 30)
            if c0 <= c1: c0, c1 = c1 + 1, c0
            b += struct.pack('<HH', c0, c1) + bytes(random.getrandbits(8) for _ in range(4))
    return bytes(b)
def flat_dxt1(w, h):
    return bytes([0x10, 0x84, 0x10, 0x84, 0, 0, 0, 0]) * ((w // 4) * (h // 4))   # one grey
def dxt5(w, h):
    b = bytearray()
    for by in range(h // 4):
        for bx in range(w // 4):
            v = 128 + 60 * math.cos(bx / 2.5) * math.sin(by / 2.0)
            b += bytes([200, 40]) + bytes(random.getrandbits(8) for _ in range(6))
            b += struct.pack('<HH', c565(v + 10, v + 10, v), c565(v - 10, v - 8, v - 12)) + bytes(random.getrandbits(8) for _ in range(4))
    return bytes(b)
def smooth_p8(w, h):                       # a gentle ramp through a grey palette: "smooth"
    return bytes((x + y) // 2 for y in range(h) for x in range(w))
def pattern_p8(w, h):                      # bricks: rows and joints with a little grain
    return bytes(min(255, max(0, int((40 if (y % 8 == 0 or (x + (y // 8) * 8) % 16 == 0) else 150)
                                     + 25 * math.sin(x / 5.0) + random.randint(-6, 6))))
                 for y in range(h) for x in range(w))
grey = b''.join(bytes([i, i, i, 255]) for i in range(256))
colour = b''.join(bytes([i, i * 3 // 4, i // 2, 255]) for i in range(256))     # brown
# name, w, h, fourcc (or None: P8), pixels, palette
tex = [("TEST_GRAIN_DXT1", 64, 64, b'DXT1', tex_dxt1(64, 64), None),
       ("TEST_ALPHA_DXT5", 64, 32, b'DXT5', dxt5(64, 32), None),
       ("TEST_BRICKS_P8", 64, 64, None, pattern_p8(64, 64), colour),
       ("TEST_SMALL", 32, 32, b'DXT1', tex_dxt1(32, 32), None),
       ("TEST_FLAT", 64, 64, b'DXT1', flat_dxt1(64, 64), None),
       ("TEST_SMOOTH", 64, 64, None, smooth_p8(64, 64), grey)]
pix = bytearray(); infos = bytearray(); plats = bytearray()
for name, w, h, four, px, pal in tex:
    img = len(pix); pix += px; pix += b'\0' * (-len(pix) % 128)
    palo = 0
    if pal: palo = len(pix); pix += pal; pix += b'\0' * (-len(pix) % 128)
    e = bytearray(0x7C)
    e[0x0C:0x0C + len(name)] = name.encode()
    struct.pack_into('<5I', e, 0x30, img, palo, len(px), len(pal) if pal else 0, len(px))
    struct.pack_into('<HH', e, 0x44, w, h)
    e[0x4A] = 0x08 if pal is not None else 0x24
    e[0x4E] = 1
    infos += e
    p = bytearray(0x20); p[0x14:0x18] = four if four else b'\0\0\0\0'; plats += p
    if pal is None: data = px
    else: data = b''.join(pal[i * 4:i * 4 + 4] for i in px)
    fmt = {b'DXT1': 0x31545844, b'DXT5': 0x35545844, None: 21}[four]
    open(f"{lv0}/{name}_{w | h << 16 | fmt << 32}", 'wb').write(data)
def chunk(cid, body): return struct.pack('<II', cid, len(body)) + body
info = chunk(0xB3310000, chunk(0x33310004, bytes(infos)) + chunk(0x33310005, bytes(plats)))
# pixels: 128-byte aligned after the chunk header (the scan rounds up)
hdr_at = 8 + len(info) + 8 + 8                   # TPK hdr + info + data hdr + pixel chunk hdr
pad = -hdr_at % 128
data = chunk(0xB3320000, chunk(0x33320002, b'\0' * pad + bytes(pix)))
open(out, 'wb').write(chunk(0xB3300000, info + data))
PY
scan="$(run "upscale-scan:$T/game")"
ok=1
for f in "$T"/lv0/*; do
    nm="$(basename "$f")"; name="${nm%_*}"; seed="${nm##*_}"
    want="$("$T/xc" "$f" "$seed")"
    echo "$scan" | grep -q "^$want $name " || { ok=0; echo "  $name: no $want in the scan"; }
done
[ $ok = 1 ] && echo "$scan" | grep -q "^6 textures in 1 files" && echo "$scan" | grep -q " TEST_SMALL world 32x32 DXT1 small" \
    && pass "scan of a made-up TPK: 6 textures with the engine's hashes, the small one sorted out" \
    || { fail "scan of a made-up TPK"; echo "$scan"; }

# --- Import Model... refuses another file ---
head -c 9016813 /dev/zero > "$T/fake.pth"
out="$(run "upscale-import:$T/fake.pth:$T/store")"
echo "$out" | grep -q "not the model release this was tested with" && [ ! -e "$T/store/Models" -o -z "$(ls "$T/store/Models" 2>/dev/null)" ] \
    && pass "Import Model… refuses a file that is not the tested release" || fail "Import Model… took another file ($out)"
out="$(HOME="$T/home" NFSU2_UPSCALE_MODEL="$T/fake.pth" NFSU2_LAUNCHER_TEST="upscale:$T/game:$T/fakepack" "$T/launcher" 2>&1)"
echo "$out" | grep -q "not the release this was tested with" && pass "the builder never loads a model file with another SHA-256" \
    || fail "the builder used another model file ($out)"

# --- with the model ---
MODEL="${NFSU2_UPSCALE_MODEL:-$HOME/Library/Application Support/NFSU2/TexturePacks/Models/4x-PBRify_UpscalerSPANV4.pth}"
if [ -f "$MODEL" ]; then
    out="$(HOME="$T/home" NFSU2_UPSCALE_MODEL="$MODEL" NFSU2_UPSCALE_SCALE=4 NFSU2_LAUNCHER_TEST="upscale:$T/game:$T/pack" "$T/launcher" 2>&1)"
    if echo "$out" | grep -q "done: 3 made, 1 single-colour and 1 smooth skipped, 0 failed"; then
        pass "made-up folder: 3 textures made, the one-colour and the smooth one left out"
    else fail "made-up folder build"; echo "$out" | tail -5; fi
    v="$(run "upscale-verify:$T/game:$T/pack")" && pass "made-up folder: $(echo "$v" | tail -1)" || { fail "made-up folder verify"; echo "$v"; }
    # the Build button's way (UpscaleStore): the model already in the store, so no download
    mkdir -p "$T/store/Models"; cp "$MODEL" "$T/store/Models/"
    out="$(HOME="$T/home" NFSU2_UPSCALE_SCALE=4 NFSU2_LAUNCHER_TEST="upscale-build:$T/game:$T/store" "$T/launcher" 2>&1)"
    echo "$out" | grep -q "^pack: 3 textures" && [ -f "$T/store/Upscaled/pack.ini" ] && pass "Build (as the button): $(echo "$out" | grep '^pack:')" \
        || { fail "Build (as the button)"; echo "$out" | tail -3; }
    mkdir -p "$T/empty" "$T/store2/Models"; cp "$MODEL" "$T/store2/Models/"
    out="$(HOME="$T/home" NFSU2_LAUNCHER_TEST="upscale-build:$T/empty:$T/store2" "$T/launcher" 2>&1)"
    echo "$out" | grep -q "No texture of the game could be read" && pass "Build in a folder that is not the game's says so" \
        || { fail "Build in an empty folder"; echo "$out" | tail -3; }
    if [ -n "${NFSU2_DATA:-}" ]; then
        G="$(dirname "$NFSU2_DATA")"
        out="$(HOME="$T/home" NFSU2_UPSCALE_MODEL="$MODEL" NFSU2_UPSCALE_SCALE=4 NFSU2_LAUNCHER_TEST="upscale:$G:$T/real:6" "$T/launcher" 2>&1)"
        echo "$out" | grep -q ", 0 failed" && pass "real game: $(echo "$out" | grep '^done' | cut -d';' -f1)" || { fail "real game build"; echo "$out" | tail -3; }
        v="$(run "upscale-verify:$G:$T/real")" && pass "real game: $(echo "$v" | tail -1)" || { fail "real game verify"; echo "$v"; }
    else echo "SKIP  real game (set NFSU2_DATA to SPEED2.EXE)"; fi
else echo "SKIP  building (no model: set NFSU2_UPSCALE_MODEL to 4x-PBRify_UpscalerSPANV4.pth)"; fi
[ $fails -eq 0 ] && echo "RESULT: all passed" || { echo "RESULT: $fails failed"; exit 1; }
