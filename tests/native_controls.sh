#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output="${TMPDIR:-/tmp}/nfsu2-native-controls-tests"
mkdir -p "$output"
clang -O1 -g -fobjc-arc -mmacosx-version-min=11.0 -fsanitize=address,undefined -Iruntime \
    tests/native_controls_test.m runtime/native_controls.m runtime/roam_core.c runtime/roam_bsd.c runtime/net_native.m \
    -framework Cocoa -o "$output/native_controls_test"
"$output/native_controls_test" "$@"
