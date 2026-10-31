#!/bin/sh
# Where saves go (runtime/bundle.m app_save_dir) without the game:
# tests/save_paths.m, with HOME a private temp folder.
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
clang -O1 -g -fobjc-arc -fsanitize=address,undefined -Iruntime tests/save_paths.m runtime/bundle.m \
    -framework Cocoa -o "$temp_dir/save_paths"
"$temp_dir/save_paths"
