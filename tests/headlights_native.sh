#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tmp
xcrun clang -std=c11 -Wall -Wextra -Werror -fno-common -DNFSU2_NATIVE_HEADLIGHTS -I runtime \
    runtime/headlights.c tests/headlights_unit.c -o out/tmp/headlights_unit
out/tmp/headlights_unit
xcrun clang -std=c11 -Wall -Wextra -Werror -I runtime \
    tests/headlights_snapshot_test.c -o out/tmp/headlights_snapshot_test
out/tmp/headlights_snapshot_test
for enhanced in 0 1; do
    xcrun clang -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -DNFSU2_NATIVE_HEADLIGHTS -DNFS_ENHANCED="$enhanced" -I runtime \
        runtime/vsemu.c tests/headlights_shader.m -framework Foundation -framework Metal \
        -o "out/tmp/headlights_shader_$enhanced"
    "out/tmp/headlights_shader_$enhanced"
done
