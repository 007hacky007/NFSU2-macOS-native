#!/bin/sh
# The guest heap (runtime/gheap.c) without the game: tests/heap_stress.c.
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wno-unused-function -fsanitize=address,undefined -Iruntime tests/heap_stress.c runtime/gheap.c -o "$temp_dir/heap_stress"
ASAN_OPTIONS=detect_leaks=0 "$temp_dir/heap_stress"
