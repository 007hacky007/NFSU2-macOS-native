#!/bin/sh
# Game Tools and quick chat without the game (runtime/native_controls.m):
#   tests/native_controls.sh                    the state checks
#   tests/native_controls.sh --snapshot <dir>   and pictures of the panel, the groups editor and the overlay
set -eu
cd "$(dirname "$0")/.."
output="${TMPDIR:-/tmp}/nfsu2-native-controls-tests"
mkdir -p "$output"
shot=""; [ "${1:-}" = "--snapshot" ] && shot="${2:?--snapshot needs a folder}" && mkdir -p "$shot"
clang -O1 -g -fobjc-arc -mmacosx-version-min=11.0 -fsanitize=address,undefined -Wall -Iruntime \
    tests/native_controls_test.m runtime/native_controls.m runtime/roam_core.c \
    -framework Cocoa -framework QuartzCore -o "$output/native_controls_test"
if [ -n "$shot" ]; then "$output/native_controls_test" --snapshot "$shot/gametools.png"; else "$output/native_controls_test"; fi
clang -O1 -g -fobjc-arc -mmacosx-version-min=11.0 -fsanitize=address,undefined -Wall -Iruntime \
    tests/native_quickchat_test.m runtime/roam_core.c -framework Cocoa -framework QuartzCore -o "$output/native_quickchat_test"
if [ -n "$shot" ]; then "$output/native_quickchat_test" --snapshot "$shot/quickchat"; else "$output/native_quickchat_test"; fi
