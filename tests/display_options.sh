#!/bin/sh
# tests/display_options.sh -- the launcher's Display card: which environment the
# engine gets for each choice, and that the original game's values set none.
# Needs swiftc; no game files.
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_display.XXXXXX")
trap 'rm -rf "$T"' EXIT
swiftc -swift-version 5 -module-cache-path "$T/cache" launcher/DisplayOptions.swift tests/display_options.swift -o "$T/display-options"
"$T/display-options"
