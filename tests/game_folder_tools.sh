#!/bin/sh
# The two tools behind the "game folder untouched" proof, without the game:
#   tools/writewatch.c  a program that writes into a watched folder is
#                       reported once per write call (open for writing, fopen
#                       "w", mkdir, rename, unlink, chmod, setxattr ...), reads
#                       and writes elsewhere are not
#   tools/manifest.py   two manifests of an unchanged folder are equal; a
#                       changed, added or removed file and a chmod are found
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
fails=0
ok(){ echo "PASS  $1"; }
bad(){ echo "FAIL  $1"; fails=$((fails+1)); }

clang -dynamiclib -O2 -Wall -o "$temp_dir/writewatch.dylib" tools/writewatch.c
cat > "$temp_dir/writer.c" <<'C'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/xattr.h>
/* writer <watched> <elsewhere>: reads and writes as a game run might */
int main(int argc, char **argv){
    char p[2048], q[2048];
    snprintf(p, sizeof p, "%s/data.bin", argv[1]);
    int fd = open(p, O_RDONLY); if (fd >= 0) close(fd);            /* a read: not a write */
    FILE *f = fopen(p, "rb"); if (f) fclose(f);                     /* nor this */
    struct stat st; stat(p, &st);
    if (argc < 3) return 0;                                         /* writer <watched>: reads only */
    f = fopen(p, "r+b"); if (f) fclose(f);                          /* 1: fopen r+ */
    fd = open(p, O_WRONLY | O_APPEND); if (fd >= 0) close(fd);     /* 2: open */
    snprintf(q, sizeof q, "%s/new", argv[1]); mkdir(q, 0700);       /* 3: mkdir */
    snprintf(q, sizeof q, "%s/new.txt", argv[1]);
    f = fopen(q, "w"); if (f){ fputs("x", f); fclose(f); }          /* 4: fopen w */
    chmod(q, 0600);                                                 /* 5: chmod */
    setxattr(q, "com.test", "1", 1, 0, 0);                         /* 6: setxattr */
    snprintf(p, sizeof p, "%s/new2.txt", argv[1]); rename(q, p);    /* 7, 8: rename from, to */
    unlink(p);                                                      /* 9: unlink */
    snprintf(q, sizeof q, "%s/new", argv[1]); rmdir(q);             /* 10: rmdir */
    if (chdir(argv[1]) == 0){ f = fopen("rel.txt", "w"); if (f) fclose(f); unlink("rel.txt"); }   /* 11, 12: relative */
    snprintf(q, sizeof q, "%s/out.txt", argv[2]);
    f = fopen(q, "w"); if (f){ fputs("y", f); fclose(f); }          /* elsewhere: not counted below */
    return 0;
}
C
clang -O1 -o "$temp_dir/writer" "$temp_dir/writer.c"
mkdir -p "$temp_dir/game/GLOBAL" "$temp_dir/elsewhere"
printf 'game data' > "$temp_dir/game/data.bin"
printf 'more data' > "$temp_dir/game/GLOBAL/GlobalB.lzc"
"$PY" -I tools/manifest.py "$temp_dir/game" "$temp_dir/before.tsv" > /dev/null
WRITEWATCH_DIR="$temp_dir/game" WRITEWATCH_LOG="$temp_dir/ww.log" \
    DYLD_INSERT_LIBRARIES="$temp_dir/writewatch.dylib" "$temp_dir/writer" "$temp_dir/game" "$temp_dir/elsewhere"
n=$(grep -c '^WRITE ' "$temp_dir/ww.log" || true)
if [ "$n" = 12 ]; then ok "writewatch: 12 write calls below the watched folder"; else bad "writewatch: $n write calls (12 expected)"; cat "$temp_dir/ww.log"; fi
grep -q "writewatch: 12 write attempts below" "$temp_dir/ww.log" && ok "writewatch: the count at exit" || bad "writewatch: no count at exit"
grep -q "elsewhere" "$temp_dir/ww.log" && bad "writewatch: a write elsewhere reported" || ok "writewatch: writes elsewhere not reported"
grep -q "(13 write attempts anywhere)" "$temp_dir/ww.log" && ok "writewatch: the write elsewhere seen and counted apart" || bad "writewatch: total count"
for c in "fopen" "open" "mkdir" "chmod" "setxattr" "rename(from)" "rename(to)" "unlink" "rmdir"; do
    grep -qF "WRITE $c " "$temp_dir/ww.log" || bad "writewatch: no $c"
done
grep -q "WRITE fopen .*/rel.txt" "$temp_dir/ww.log" && ok "writewatch: a relative path against the cwd" || bad "writewatch: relative path"
# a run that only reads: nothing
WRITEWATCH_DIR="$temp_dir/game" WRITEWATCH_LOG="$temp_dir/ww2.log" \
    DYLD_INSERT_LIBRARIES="$temp_dir/writewatch.dylib" "$temp_dir/writer" "$temp_dir/game"
if grep -q "writewatch: 0 write attempts below" "$temp_dir/ww2.log" && ! grep -q '^WRITE ' "$temp_dir/ww2.log"
then ok "writewatch: a run that only reads: 0 write attempts"; else bad "writewatch: read-only run: $(cat "$temp_dir/ww2.log")"; fi

# manifest: the writer left the files as they were (its new ones are gone)
"$PY" -I tools/manifest.py "$temp_dir/game" "$temp_dir/after.tsv" > /dev/null
if "$PY" -I tools/manifest.py --diff "$temp_dir/before.tsv" "$temp_dir/before.tsv" > /dev/null; then ok "manifest: same manifest, no differences"
else bad "manifest: a manifest differs from itself"; fi
"$PY" -I tools/manifest.py --diff "$temp_dir/before.tsv" "$temp_dir/after.tsv" > "$temp_dir/d1.txt" || true
grep -q "changed  \. " "$temp_dir/d1.txt" && ok "manifest: entries added and removed show on the folder (mtime)" || bad "manifest: folder mtime not caught"
"$PY" -I tools/manifest.py "$temp_dir/game" "$temp_dir/m0.tsv" > /dev/null
printf 'game dat4' > "$temp_dir/game/data.bin"
touch -r "$temp_dir/game/GLOBAL/GlobalB.lzc" "$temp_dir/game/data.bin"
"$PY" -I tools/manifest.py "$temp_dir/game" "$temp_dir/m1.tsv" > /dev/null
if "$PY" -I tools/manifest.py --diff "$temp_dir/m0.tsv" "$temp_dir/m1.tsv" > "$temp_dir/d2.txt"; then bad "manifest: changed content not found"
else grep -q "changed  data.bin .*sha256" "$temp_dir/d2.txt" && ok "manifest: changed content (same size, mtime put back)" || bad "manifest: changed content: $(cat "$temp_dir/d2.txt")"; fi
chmod 600 "$temp_dir/game/GLOBAL/GlobalB.lzc"
"$PY" -I tools/manifest.py "$temp_dir/game" "$temp_dir/m2.tsv" > /dev/null
"$PY" -I tools/manifest.py --diff "$temp_dir/m1.tsv" "$temp_dir/m2.tsv" > "$temp_dir/d3.txt" || true
grep -q "changed  GLOBAL/GlobalB.lzc .*mode" "$temp_dir/d3.txt" && ok "manifest: chmod" || bad "manifest: chmod not found"
printf 'new' > "$temp_dir/game/GLOBAL/extra.txt"; rm "$temp_dir/game/data.bin"
"$PY" -I tools/manifest.py "$temp_dir/game" "$temp_dir/m3.tsv" > /dev/null
"$PY" -I tools/manifest.py --diff "$temp_dir/m2.tsv" "$temp_dir/m3.tsv" > "$temp_dir/d4.txt" || true
grep -q "added    GLOBAL/extra.txt" "$temp_dir/d4.txt" && grep -q "removed  data.bin" "$temp_dir/d4.txt" \
    && ok "manifest: added and removed files" || bad "manifest: added/removed: $(cat "$temp_dir/d4.txt")"
echo
if [ $fails = 0 ]; then echo "RESULT: all passed"; else echo "RESULT: $fails failed"; fi
[ $fails = 0 ]
