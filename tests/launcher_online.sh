#!/bin/sh
# The launcher's free-roam name rules, player counts and quick chat groups (tests/launcher_online.swift).
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
swiftc -swift-version 5 -parse-as-library -import-objc-header runtime/names.h -module-cache-path "$temp_dir/cache" \
    $(ls launcher/*.swift | grep -v '/main.swift$') tests/launcher_online.swift -o "$temp_dir/launcher-online"
"$temp_dir/launcher-online"
