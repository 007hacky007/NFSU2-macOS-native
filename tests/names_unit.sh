#!/bin/sh
# Names that read as a slur (runtime/names.h) without the game: tests/names_unit.c.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wextra -fsanitize=address,undefined -Iruntime tests/names_unit.c -o "$tmp/names_unit"
"$tmp/names_unit"
