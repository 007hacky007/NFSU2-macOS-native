#!/usr/bin/env python3
"""Write tools/known_releases.tsv: the game files of the known releases, for NFSU2 Builder.

  tools/release_manifest.py OUT.tsv --release ID NAME FOLDER [--release ...] [--exclude TOP ...]

One line per distinct file content: path, size, SHA-256, CRC-32 (what a disc's
compressed.zip records), the releases that have it, and whether it is a core file
(opened when the game starts, checked by name; see CORE). SPEED2.EXE and server.dll
are left out: the Builder checks them against its own lists. Only paths, sizes and
checksums are written; no game file goes into the repository.

The manifest in the repository was made from the European discs unpacked with
tools/install_from_discs.py (eu-disc), the same with EA's official v1.2 patch
applied (eu-v12) and a North American v1.2 installation (na-v12), with the
launcher-made LANGPACKS and TEXPACKS folders excluded.
"""
import argparse
import hashlib
import os
import zlib

# The files the game opens from its start to the main menu and the Quick Race menus
# (FILEOPLOG=1 boot run of tools/autorun.sh with tests/scripts/quickrace.txt, European
# v1.2), without the menu car's own files, the language-specific ones and the ones not
# every release has (the European discs have no PFData/ and speech/ folders). The Builder
# refuses a copy without them.
CORE = [
    'CARS/AUDIO/GEOMETRY.bin', 'CARS/BRAKES/GEOMETRY.BIN', 'CARS/EXHAUST/GEOMETRY.BIN',
    'CARS/SPOILER/GEOMETRY.BIN', 'CARS/TEXTURES.BIN', 'CARS/WHEELS/GEOMETRY_RACINGHART.BIN',
    'CARS/WHEELS/TEXTURES.BIN', 'FRONTEND/FrontB.lzc', 'FRONTEND/PLATFORMS/SHOWROOM.BIN',
    'GLOBAL/CarHeadersMemoryFile.bin', 'GLOBAL/FrontEndMemoryFile.bin', 'GLOBAL/GLOBALA.BUN',
    'GLOBAL/GLOBALB.LZC', 'GLOBAL/GlobalMemoryFile.bin', 'GLOBAL/GLOBALTEXTURESROW.BIN',
    'LANGUAGES/LANGUAGETEXTURES.BIN', 'SOUND/FE/FE_MB.abk', 'SOUND/GLOBAL/FE_COMMON_MB.abk',
    'SOUND/MixMaps/MAPOUTPUT.mxb', 'SOUND/NOS/Nitrous_00_MB.abk', 'TRACKS/TRACKMAP4014.bin',
]
SKIP = {'speed2.exe', 'server.dll'}


def files(folder, exclude):
    for base, dirs, names in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for name in sorted(names):
            if name.startswith('.'):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, folder).replace(os.sep, '/')
            top = rel.split('/')[0].lower()
            if top in exclude or rel.lower() in SKIP:
                continue
            sha, crc, size = hashlib.sha256(), 0, 0
            with open(path, 'rb') as f:
                for block in iter(lambda: f.read(1 << 20), b''):
                    sha.update(block)
                    crc = zlib.crc32(block, crc)
                    size += len(block)
            yield rel, size, sha.hexdigest(), crc


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('out')
    ap.add_argument('--release', nargs=3, action='append', required=True, metavar=('ID', 'NAME', 'FOLDER'))
    ap.add_argument('--exclude', action='append', default=[], help='top-level folder to leave out')
    args = ap.parse_args()
    exclude = {e.lower() for e in args.exclude}
    entries = {}   # (lower path, size, sha) -> [path, crc, releases]
    paths = {}     # lower path -> set of releases
    for ident, _name, folder in args.release:
        for rel, size, sha, crc in files(folder, exclude):
            key = (rel.lower(), size, sha)
            entry = entries.setdefault(key, [rel, crc, []])
            entry[2].append(ident)
            paths.setdefault(rel.lower(), set()).add(ident)
    every = {ident for ident, _, _ in args.release}
    core = {p.lower() for p in CORE}
    missing = [p for p in CORE if paths.get(p.lower()) != every]
    if missing:
        raise SystemExit(f'core files not in every release: {missing}')
    with open(args.out, 'w', newline='\n') as out:
        out.write('# Known NFSU2 releases for NFSU2 Builder, written by tools/release_manifest.py.\n'
                  '# release <id> <name>; file <path> <size> <sha256> <crc32> <releases> <core>\n')
        for ident, name, _folder in args.release:
            out.write(f'release\t{ident}\t{name}\n')
        for (low, size, sha), (rel, crc, releases) in sorted(entries.items()):
            out.write(f'file\t{rel}\t{size}\t{sha}\t{crc:08x}\t{",".join(releases)}\t{int(low in core)}\n')
    print(f'{args.out}: {len(entries)} entries, {len(paths)} paths, {len(core)} core files')


if __name__ == '__main__':
    main()
