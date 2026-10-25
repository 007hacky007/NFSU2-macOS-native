#!/bin/bash
# Build the NFSRef Windows kit: out/nfsref_kit/ + out/NFSRef_kit.zip
# Requires: brew install mingw-w64
set -e
H="$(cd "$(dirname "$0")" && pwd)"; ROOT="$H/../.."
K="$ROOT/out/nfsref_kit"; rm -rf "$K"; mkdir -p "$K/SCRIPTS"
i686-w64-mingw32-gcc -O2 -shared -static-libgcc -Wall -Wno-unused-function -Wno-format-truncation \
    -o "$K/SCRIPTS/nfsref.asi" "$H/nfsref.c" -lwinmm
cp "$H/nfsref.ini" "$K/SCRIPTS/nfsref.ini"
cp "$H/nfsref_registry.txt" "$K/SCRIPTS/nfsref_registry.txt"
cp "$H/NFSRef_start.bat" "$H/NFSRef_diagnose.bat" "$H/NFSRef_README.txt" "$K/"
for f in "$K"/*.bat "$K"/*.txt "$K"/SCRIPTS/*.ini "$K"/SCRIPTS/*.txt; do   # Windows line endings
    perl -pi -e 's/\r?\n/\r\n/' "$f"; done
rm -f "$ROOT/out/NFSRef_kit.zip"; (cd "$K" && zip -qr "$ROOT/out/NFSRef_kit.zip" .)
ls -la "$ROOT/out/NFSRef_kit.zip"
