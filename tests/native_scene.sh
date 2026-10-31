#!/bin/sh
# tests/native_scene.sh [--snapshot <png>] -- runtime/native_scene.m without the game (tests/native_scene_test.m):
# photo mode's input, the controller kept from the game, the drift panel, PNG screenshots.  With --snapshot, the
# panels over a window as <png> (drift) and <png>.photo.png (photo mode).  Needs clang and a Metal device.
set -eu
cd "$(dirname "$0")/.."
output="${TMPDIR:-/tmp}/nfsu2-native-scene-tests"
mkdir -p "$output"
clang -O1 -g -Wall -Wextra -Werror -fobjc-arc -mmacosx-version-min=11.0 -fsanitize=address,undefined -Iruntime \
    tests/native_scene_test.m runtime/native_scene.m -framework Cocoa -framework Metal -framework ImageIO -o "$output/native_scene_test"
"$output/native_scene_test" "$@"
