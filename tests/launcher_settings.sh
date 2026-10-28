#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
swiftc -swift-version 5 -module-cache-path "$temp_dir/cache" launcher/Settings.swift launcher/RuntimeOptions.swift launcher/Game.swift launcher/Portable.swift tests/launcher_settings.swift -o "$temp_dir/launcher-settings"
"$temp_dir/launcher-settings"
