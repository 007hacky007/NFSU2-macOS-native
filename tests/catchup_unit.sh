#!/bin/sh
# The career's rubberbanding (runtime/catchup.c) without the game:
# tests/catchup_unit.c with each setting of Rubberbanding (NFSU2_CATCHUP).
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
clang -O1 -g -Wall -Wextra -Wno-unused-function -fsanitize=address,undefined -Iruntime tests/catchup_unit.c -o "$tmp/catchup_unit"
env -u NFSU2_CATCHUP "$tmp/catchup_unit" original
NFSU2_CATCHUP=original "$tmp/catchup_unit" original
NFSU2_CATCHUP=bogus "$tmp/catchup_unit" original
NFSU2_CATCHUP=noboost "$tmp/catchup_unit" noboost
NFSU2_CATCHUP=off "$tmp/catchup_unit" off
echo "catchup: all passed"
