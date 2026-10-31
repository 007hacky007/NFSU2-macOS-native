#!/bin/sh
# Win32 answers of runtime/hlefix.c without the game: tests/hle_unit.c.
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wno-unused-function -fsanitize=address,undefined -Iruntime tests/hle_unit.c -o "$temp_dir/hle_unit"
"$temp_dir/hle_unit"
