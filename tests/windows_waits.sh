#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wno-unused-parameter -Wno-unused-function -fsanitize=address,undefined -Iruntime \
    tests/objtable_unit.c -o "$temp_dir/windows-waits"
"$temp_dir/windows-waits" "$@"
