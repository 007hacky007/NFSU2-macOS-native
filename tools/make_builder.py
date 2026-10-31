#!/usr/bin/env python3
"""Build and assemble NFSU2 Builder.app (ad-hoc signed).

  tools/make_builder.py --version 1.0.0 --output dist     -> dist/NFSU2 Builder.app

The app bundles exactly what the build needs from this checkout (Contents/Resources/
BuildSources): the scripts, tools/, runtime/, launcher/, the two tests/ files link.sh
compiles, requirements.txt and VERSION. Never gen/, out/, docs/ or any game file.
"""
import argparse
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRIES = ('build.sh', 'link.sh', 'pack.sh', 'run.sh', 'VERSION', 'requirements.txt', 'tools', 'runtime',
           'launcher', 'tests/boot.c', 'tests/main_all.c')
# Not needed to build: the Windows-side reference tool (tools/nfsref, includes a built .asi).
EXCLUDE = ('tools/nfsref/',)
MIN_MACOS = '11.0'
SWIFT_TARGET = f'arm64-apple-macos{MIN_MACOS}'


def build_sources(root):
    """Tracked files the Builder bundles, relative to the repo root."""
    out = subprocess.run(['git', 'ls-files', '-z', '--', *ENTRIES], cwd=root, check=True,
                         capture_output=True).stdout.decode()
    return sorted(Path(n) for n in out.split('\0')
                  if n and '__pycache__' not in n and not n.startswith(EXCLUDE))


def parse_minos(otool_output):
    block = otool_output.split('LC_BUILD_VERSION', 1)[1]
    return re.search(r'minos (\S+)', block).group(1)


def build_binary(root):
    """swiftc directly, like pack.sh's launcher: SwiftPM raises the deployment target to macOS 12,
    and the Builder must open on macOS 11 like the game (`swift test` still uses the package)."""
    package = root / 'builder'
    out = package / '.build/swiftc-release'
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    common = ['swiftc', '-swift-version', '5', '-O', '-target', SWIFT_TARGET, '-parse-as-library']
    core = sorted(str(p) for p in (package / 'Sources/BuilderCore').glob('*.swift'))
    app = sorted(str(p) for p in (package / 'Sources/NFSU2Builder').glob('*.swift'))
    subprocess.run(common + ['-module-name', 'BuilderCore', '-emit-module', '-emit-module-path',
                             str(out / 'BuilderCore.swiftmodule'), '-emit-library', '-static',
                             '-o', str(out / 'libBuilderCore.a'), *core], check=True)
    binary = out / 'NFSU2Builder'
    subprocess.run(common + ['-module-name', 'NFSU2Builder', '-I', str(out), '-L', str(out), '-lBuilderCore',
                             '-o', str(binary), *app], check=True)
    minos = parse_minos(subprocess.run(['otool', '-l', str(binary)], check=True, capture_output=True,
                                       text=True).stdout)
    if minos != MIN_MACOS:
        raise SystemExit(f'{binary} targets macOS {minos}, expected {MIN_MACOS}')
    print(f'minos {minos}')
    return binary


def make_icns(png, destination):
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / 'AppIcon.iconset'
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png'
                subprocess.run(['sips', '-z', str(size * scale), str(size * scale), str(png), '--out',
                                str(iconset / name)], check=True, capture_output=True)
        subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(destination)], check=True)


def assemble(binary, version, output, root):
    app = Path(output) / 'NFSU2 Builder.app'
    if app.exists():
        shutil.rmtree(app)
    macos, resources = app / 'Contents/MacOS', app / 'Contents/Resources'
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(binary, macos / 'NFSU2Builder')
    for rel in build_sources(root):
        target = resources / 'BuildSources' / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / rel, target)
    make_icns(root / 'builder/Resources/AppIcon-1024.png', resources / 'AppIcon.icns')
    with open(app / 'Contents/Info.plist', 'wb') as f:
        plistlib.dump({
            'CFBundleIdentifier': 'org.nfsu2.builder', 'CFBundleName': 'NFSU2 Builder',
            'CFBundleDisplayName': 'NFSU2 Builder', 'CFBundleExecutable': 'NFSU2Builder',
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'CFBundleVersion': version,
            'LSMinimumSystemVersion': MIN_MACOS, 'NSHighResolutionCapable': True, 'CFBundleIconFile': 'AppIcon',
            'LSArchitecturePriority': ['arm64'],
            # The game copy may be in these folders; macOS asks once and shows this text.
            **{f'NS{place}UsageDescription': 'To read your game copy. NFSU2 Builder never changes it.'
               for place in ('DesktopFolder', 'DocumentsFolder', 'DownloadsFolder', 'RemovableVolumes',
                             'NetworkVolumes')},
            'NSHumanReadableCopyright':
                'Builds NFSU2.app from your own game copy. No game files are included.',
        }, f)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    return app


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--version', required=True)
    ap.add_argument('--output', default='dist')
    args = ap.parse_args()
    print(assemble(build_binary(ROOT), args.version, Path(args.output), ROOT))


if __name__ == '__main__':
    main()
