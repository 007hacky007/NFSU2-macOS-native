#!/bin/sh
# The other cars' headlights without the game:
#   tests/headlights_unit.c       runtime/headlights.c: modes, exclusions, the
#                                 nearest eight, the projector transform (built
#                                 for the European and the North American
#                                 addresses, runtime/build_na.h)
#   tests/headlights_pool_unit.c  runtime/metal.m's per-frame pool of light sets
#   tests/headlights_shader.m     runtime/vsemu.c's lit pixel shaders on the GPU
#                                 (original and HD output; needs a Metal device)
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
CF="-O1 -g -Wall -Wextra -fsanitize=address,undefined -Iruntime"
clang $CF tests/headlights_unit.c -o "$temp_dir/headlights_unit" -lm 2>&1 | grep -v "reducing alignment" >&2 || true
clang $CF -DNFS_EXE_NA=1 -include runtime/build_na.h tests/headlights_unit.c -o "$temp_dir/headlights_unit_na" -lm 2>&1 | grep -v "reducing alignment" >&2 || true
# their [headlights] log lines are shown only when a case fails
for b in headlights_unit headlights_unit_na; do
    "$temp_dir/$b" 2> "$temp_dir/$b.log" || { cat "$temp_dir/$b.log"; echo "FAIL: $b"; exit 1; }
done
# the pool, cut out of metal.m (it is static there)
sed -n '/^#define HL_POOL /,/^void metal_headlights/p' runtime/metal.m | sed '$d' > "$temp_dir/hlpool.h"
grep -q "hl_pool_put" "$temp_dir/hlpool.h" || { echo "FAIL: the headlight pool is no longer in runtime/metal.m"; exit 1; }
clang $CF -DHLPOOL_SRC="\"$temp_dir/hlpool.h\"" tests/headlights_pool_unit.c -o "$temp_dir/headlights_pool_unit"
"$temp_dir/headlights_pool_unit"
for enhanced in 0 1; do
    clang -O1 -g -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -DNFS_ENHANCED="$enhanced" -Iruntime \
        runtime/vsemu.c tests/headlights_shader.m -framework Foundation -framework Metal -o "$temp_dir/headlights_shader_$enhanced"
    "$temp_dir/headlights_shader_$enhanced"
done
