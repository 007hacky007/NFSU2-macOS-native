#!/bin/sh
# The unique visual parts after Caleb (runtime/uniques.c) without the game:
# tests/uniques_unit.c, with Unique parts for every car off and on (NFSU2_UNIQUES).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wextra -Wno-unused-function -fsanitize=address,undefined -Iruntime tests/uniques_unit.c -o "$tmp/uniques_unit"
env -u NFSU2_UNIQUES "$tmp/uniques_unit" off
NFSU2_UNIQUES=0 "$tmp/uniques_unit" off
NFSU2_UNIQUES=1 "$tmp/uniques_unit" on
echo "uniques: all passed"
