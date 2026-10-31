#!/bin/sh
# The launcher's settings without a window or an engine (tests/launcher_settings.swift):
# defaults, persistence, invalid stored values, what Play hands the engine (no stale
# variable, hand-set ones win), Restore Original Game, input validation.  Builds the
# launcher's sources without main.swift; runs with a private HOME and its own
# preferences domain, removed afterwards.
#   tests/launcher_settings.sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
src=$(ls launcher/*.swift | grep -v '/main\.swift$')
# shellcheck disable=SC2086
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -import-objc-header runtime/names.h -module-cache-path "$tmp/cache" $src tests/launcher_settings.swift \
    -o "$tmp/nfsu2-launcher-settings-test"
mkdir -p "$tmp/home"
rc=0; HOME="$tmp/home" NFSU2_MODS_STORE="$tmp/mods" "$tmp/nfsu2-launcher-settings-test" || rc=$?
# no preferences domain left behind (removing it leaves an empty plist that defaults delete does not see)
defaults delete nfsu2-launcher-settings-test >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/nfsu2-launcher-settings-test.plist"
exit $rc
