#!/bin/bash
# tests/texture_packs.sh -- the launcher's texture pack builder (launcher/TexturePackBuilder.swift)
# refuses a mod that holds a symbolic link, in an archive or in a folder, so it never reads
# a file outside the mod; a plain mod still works.  Needs swiftc; no game files.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/nfsu2_texpacks.XXXXXX")"
trap 'rm -rf "$T"' EXIT
swiftc -swift-version 5 -target arm64-apple-macos11.0 -o "$T/launcher" "$ROOT"/launcher/*.swift || { echo "FAIL: launcher build"; exit 1; }
mkdir -p "$T/game/GLOBAL" "$T/plain" "$T/linked/GLOBAL" "$T/dirlink"
echo "not the mod's" > "$T/outside.txt"
# a 4x4 DXT1 DDS named after a game texture
perl -e 'print "DDS ", pack("V7", 124, 0x1007, 4, 4, 0, 0, 1), "\0" x 44,
               pack("V2", 32, 4), "DXT1", "\0" x 20, pack("V", 0x1000), "\0" x 16, "\xff\xff\0\0", "\0" x 4' > "$T/plain/CARBONFIBRE.dds"
cp "$T/plain/CARBONFIBRE.dds" "$T/linked/"
ln -s "$T/outside.txt" "$T/linked/GLOBAL/GlobalB.lzc"
ln -s / "$T/dirlink/root"
cp "$T/plain/CARBONFIBRE.dds" "$T/dirlink/"
(cd "$T/linked" && zip -qry "$T/linked.zip" .)
fails=0
run(){ NFSU2_LAUNCHER_TEST="texpack:$1:$T/game:$T/out.ntxp" "$T/launcher" 2>&1; }
expect_refused(){
    out="$(run "$1")"; rc=$?
    if [ $rc -ne 0 ] && echo "$out" | grep -q "contains a link"; then echo "PASS  refused: $2"
    else echo "FAIL  not refused: $2 ($out)"; fails=$((fails+1)); fi
}
expect_refused "$T/linked.zip" "archive with a link to a file outside"
expect_refused "$T/linked" "folder with a link to a file outside"
expect_refused "$T/dirlink" "folder with a link to a folder outside"
out="$(run "$T/plain")"
if [ $? -eq 0 ] && [ -s "$T/out.ntxp" ]; then echo "PASS  plain mod made into a pack"; else echo "FAIL  plain mod ($out)"; fails=$((fails+1)); fi
[ $fails -eq 0 ] && echo "RESULT: all passed" || { echo "RESULT: $fails failed"; exit 1; }
