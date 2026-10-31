#!/bin/sh
# ps_2_0 pixel shader translation (runtime/vsemu.c) without the game:
# tests/shader_ps20.c, for the original and the HD shader output.
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
for enhanced in 0 1; do
    clang -O1 -g -Wno-unused-variable -Wno-unused-but-set-variable -fsanitize=address,undefined -DNFS_ENHANCED="$enhanced" \
        -Iruntime runtime/vsemu.c tests/shader_ps20.c -o "$temp_dir/shader_ps20_$enhanced" -lm
    "$temp_dir/shader_ps20_$enhanced"
done
