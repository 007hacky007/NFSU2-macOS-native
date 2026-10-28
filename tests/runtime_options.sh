#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
swiftc -swift-version 5 -module-cache-path "$temp_dir/cache" launcher/Settings.swift launcher/RuntimeOptions.swift tests/runtime_options.swift -o "$temp_dir/runtime-options"
"$temp_dir/runtime-options"
