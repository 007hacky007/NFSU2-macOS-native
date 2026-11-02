#!/bin/sh
# The career's kept spot (runtime/carspot.c) without the game: tests/carspot_unit.c.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wextra -fsanitize=address,undefined -Iruntime tests/carspot_unit.c -o "$tmp/carspot_unit"
"$tmp/carspot_unit"
