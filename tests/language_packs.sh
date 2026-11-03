#!/bin/sh
# tests/language_packs.sh -- the launcher's language pack builder (LanguagePacks.swift,
# RarArchive.swift) on made-up data.  Needs swiftc; no game files, no internet.
# The packs from the real mods were checked byte for byte against the ones
# th0mk's nfsu2-web tools/langpacks.py builds (NFSU2_LAUNCHER_TEST=langpack:...).
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_langpacks.XXXXXX")
trap 'rm -rf "$T"' EXIT
swiftc -swift-version 5 -module-cache-path "$T/cache" launcher/LanguagePacks.swift launcher/RarArchive.swift \
    launcher/Mega.swift launcher/UHUDPack.swift launcher/InnoSetup.swift tests/language_packs.swift -o "$T/language-packs"
"$T/language-packs"
