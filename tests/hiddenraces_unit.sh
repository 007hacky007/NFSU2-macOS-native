#!/bin/sh
# The career's hidden races on the map (runtime/hiddenraces.c) without the game:
# tests/hiddenraces_unit.c, with Show hidden races off and on (NFSU2_SHOW_HIDDEN_RACES).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wextra -Wno-unused-function -fsanitize=address,undefined -Iruntime tests/hiddenraces_unit.c -o "$tmp/hiddenraces_unit"
env -u NFSU2_SHOW_HIDDEN_RACES "$tmp/hiddenraces_unit" off
NFSU2_SHOW_HIDDEN_RACES=off "$tmp/hiddenraces_unit" off
NFSU2_SHOW_HIDDEN_RACES=1 "$tmp/hiddenraces_unit" on
echo "hiddenraces: all passed"
