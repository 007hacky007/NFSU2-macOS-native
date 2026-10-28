#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output="${TMPDIR:-/tmp}/nfsu2-native-scene-tests"
mkdir -p "$output"
clang -O1 -g -Wall -Wextra -Werror -fobjc-arc -mmacosx-version-min=11.0 -fsanitize=address,undefined -Iruntime \
    tests/native_scene_test.m runtime/native_scene.m -framework Cocoa -framework Metal -framework ImageIO -o "$output/native_scene_test"
"$output/native_scene_test" "$@"
