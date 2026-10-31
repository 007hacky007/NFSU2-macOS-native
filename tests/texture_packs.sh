#!/bin/bash
# tests/texture_packs.sh -- the launcher's texture packs.  The builder (TexturePackBuilder.swift)
# refuses a mod that holds a symbolic link, in an archive or in a folder, so it never reads a
# file outside the mod; a plain mod still works.  The list (TexturePackCatalog.swift): the app's
# own copy without a network, a valid fetched copy used and kept, invalid ones not used, and
# Download refusing a file with another SHA-256.  Needs swiftc (and python3 for a local
# server); no game files, no internet.
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

# --- the list of packs (launcher/TexturePackCatalog.swift): the app's own copy, a valid fetched
# one (kept for the next start), invalid ones (not used), and Download refusing another file
LIST="$ROOT/launcher/texture-packs.json"
catalog(){   # catalog <store> <list url>: prints "before: ..." and "list: <source> <date>, ..."
    NFSU2_TEXPACKS_BUNDLED="$LIST" NFSU2_TEXPACKS_CATALOG_URL="$2" NFSU2_LAUNCHER_TEST="texpack-catalog:$1" "$T/launcher" 2>/dev/null
}
check(){ if echo "$1" | grep -q "$2"; then echo "PASS  $3"; else echo "FAIL  $3 ($1)"; fails=$((fails+1)); fi; }
variant(){   # variant <out> <python statement on the list d>
    python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); $2; json.dump(d,open(sys.argv[2],'w'))" "$LIST" "$1"
}
check "$(catalog "$T/s1" "http://127.0.0.1:9/none.json")" "list: built in" "no network: the app's own list"
variant "$T/newer.json" "d['updated']='2099-01-01'; d['packs'][0]['name']='Fetched name'"
check "$(catalog "$T/s2" "file://$T/newer.json")" "list: online 2099-01-01" "a valid fetched list is used"
check "$(catalog "$T/s2" "off")" "before: saved online copy 2099-01-01" "the fetched list is kept for the next start"
n=0
for bad in "d['packs'][0]['sha256']='1234'" "d['packs'][0]['download']='http://nfsmods.xyz/x.zip'" \
           "d['packs'][0]['download']='https://example.com/x.zip'" "d['version']=2" "d['packs'][1]['page']='https://evil.example/'"; do
    n=$((n+1)); variant "$T/bad$n.json" "d['updated']='2099-01-01'; $bad"
    check "$(catalog "$T/b$n" "file://$T/bad$n.json")" "list: built in" "invalid list not used: $bad"
done
# Download from a server on this Mac (allowed only in test mode): the right file installs, another is refused
if command -v python3 >/dev/null; then
    mkdir -p "$T/www"; (cd "$T/plain" && zip -qr "$T/www/pack.zip" .)
    PORT=$((20000 + RANDOM % 20000))
    (cd "$T/www" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) & SRV=$!
    sleep 1
    SUM="$(shasum -a 256 "$T/www/pack.zip" | cut -c1-64)"; SIZE=$(wc -c < "$T/www/pack.zip" | tr -d " ")
    for case in right wrong; do
        H="$SUM"; [ $case = wrong ] && H="$(printf '%064d' 0)"
        variant "$T/dl-$case.json" "d['updated']='2099-01-01'; p=d['packs'][0]; p['download']='http://127.0.0.1:$PORT/pack.zip'; p['sha256']='$H'; p['size']=$SIZE; p.pop('exclude',None)"
        out="$(NFSU2_TEXPACKS_BUNDLED="$LIST" NFSU2_TEXPACKS_CATALOG_URL="file://$T/dl-$case.json" \
               NFSU2_LAUNCHER_TEST="texpack-download:scout-ui:$T/game:$T/d-$case" "$T/launcher" 2>&1)"
        if [ $case = right ]; then check "$out" "installed: scout-ui on=true" "Download installs the file with the list's SHA-256"
        else check "$out" "not the release this was tested with" "Download refuses a file with another SHA-256"; fi
    done
    kill $SRV 2>/dev/null; wait $SRV 2>/dev/null
else echo "SKIP  Download tests (no python3 for a local server)"; fi
[ $fails -eq 0 ] && echo "RESULT: all passed" || { echo "RESULT: $fails failed"; exit 1; }
