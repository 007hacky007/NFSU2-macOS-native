#!/bin/sh
# The stall watchdog (runtime/watchdog.c) without the game: tests/watchdog_unit.c (about 8 s).
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -Iruntime tests/watchdog_unit.c -o "$temp_dir/watchdog_unit"
"$temp_dir/watchdog_unit"
