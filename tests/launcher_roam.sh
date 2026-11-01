#!/bin/sh
# The launcher's later free-roam options (tests/launcher_roam.swift): their first
# values, what Play hands the engine, Restore Original Game.  Builds the launcher's
# sources without main.swift; runs with a private HOME and its own preferences
# domain, removed afterwards.  No network.
#   tests/launcher_roam.sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
src=$(ls launcher/*.swift | grep -v '/main\.swift$')
# shellcheck disable=SC2086
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -import-objc-header runtime/names.h -module-cache-path "$tmp/cache" $src tests/launcher_roam.swift \
    -o "$tmp/nfsu2-launcher-roam-test"
mkdir -p "$tmp/home"
rc=0; HOME="$tmp/home" NFSU2_MODS_STORE="$tmp/mods" "$tmp/nfsu2-launcher-roam-test" || rc=$?
defaults delete nfsu2-launcher-roam-test >/dev/null 2>&1 || true
rm -f "$HOME/Library/Preferences/nfsu2-launcher-roam-test.plist"
exit $rc
