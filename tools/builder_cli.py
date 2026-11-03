#!/usr/bin/env python3
"""Non-interactive entry points for NFSU2 Builder (builder/). Prints NFSU2-EVENT JSON lines.

  python3 tools/builder_cli.py setup [--venv DIR]
      .venv (or DIR: the Builder's shared one, linked from .venv) with requirements.txt, for
      the Python that runs it (the Builder's private one)
  .venv/bin/python tools/builder_cli.py build --exe SPEED2.EXE --data PATH [--data PATH] [--version V]
      the same steps as the Terminal build: tools/gen_v2.sh, build.sh, link.sh, pack.sh --embed
      (README, "Build from Terminal") for the one region SPEED2.EXE belongs to. The app has
      the game inside (Contents/Resources/Game). The game data (--data) is a game folder, an
      NFSU2.app with the game inside (an update), or the two disc images. It is staged in
      out/game first (APFS clones of a folder, tools/install_from_discs.py for discs) with
      SPEED2.EXE put in, cloned into the app by pack.sh, and the staging copy is removed.
      The sources are never written to. --version goes into the app's Info.plist
      (NFSBuilderVersion).

Every other output line is plain log text. Events: {"step": ID, "title": TEXT} before each
step (prepare, lift, compile, link, package, sign), {"progress": 0..1} within a step,
{"done": APP} at the end, {"error": TEXT} on failure (exit 1).
"""
import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import quarantine  # noqa: E402
PREFIX = 'NFSU2-EVENT '
# Where the game data is staged while building, and where pack.sh --embed puts the app.
STAGING = 'out/game'
APP = 'out/personal/NFSU2.app'
# The two executables tools/gen_v2.sh accepts (README, "Game versions").
SUPPORTED = {
    '8f6a9ae2c4cfa01181d2fd755d99c6f4b7103f60273908ea1de1e719dfe2a297': 'eu',
    'f9dd86c054878ce6276beb07c1fd61874f7a1e4bf1f241b084c65b73e24168a7': 'na',
}
STEP_FAILED = 'This step stopped with an error. Click Copy log and include it in a bug report.'


class BuildError(Exception):
    pass


def emit(event):
    print(PREFIX + json.dumps(event), flush=True)


def step(ident, title):
    print(f'\n{title}', flush=True)
    emit({'step': ident, 'title': title})


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def find_exe(folder):
    for name in os.listdir(folder):
        if name.lower() == 'speed2.exe':
            return Path(folder) / name
    return None


# --- setup -------------------------------------------------------------------------------

def setup(venv=None):
    if sys.platform != 'darwin' or os.uname().machine != 'arm64':
        raise BuildError('building needs an Apple Silicon Mac')
    if sys.version_info < (3, 10):
        raise BuildError('Python 3.10 or newer is needed')
    venv = Path(venv) if venv else ROOT / '.venv'
    python = venv / 'bin/python'
    stamp = venv / '.build-requirements-sha256'
    digest = sha256(ROOT / 'requirements.txt')
    if python.is_file() and stamp.is_file() and stamp.read_text().strip() == digest:
        print('build tools are already set up', flush=True)
        return
    print('Setting up the build tools in .venv', flush=True)
    if not python.is_file():
        subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True)
    subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check', '--no-input',
                    '-r', str(ROOT / 'requirements.txt')], check=True)
    stamp.write_text(digest)


# --- the game data -------------------------------------------------------------------------

def same_volume(a, b):
    a = Path(a)
    while not a.exists():
        a = a.parent
    return os.stat(a).st_dev == os.stat(b).st_dev


def game_source(path):
    """The game folder inside an NFSU2.app (Contents/Resources/Game), or `path` itself."""
    path = Path(path)
    if path.suffix.lower() == '.app':
        inner = path / 'Contents/Resources/Game'
        if not inner.is_dir():
            raise BuildError(f'{path.name} has no game inside it; choose your game folder or the discs')
        return inner
    return path


def copy_tree(source, target):
    """APFS clones on the same volume (no extra space), a normal copy otherwise (macOS's cp -R
    keeps the extended attributes; -X would drop them). Either way the game data keeps its
    quarantine: a copy that lost it fails the build."""
    target.mkdir(parents=True)
    for name in sorted(os.listdir(source)):
        if name.startswith('.') or name.lower() == 'speed2.exe':
            continue
        src = Path(source) / name
        flags = ['-c'] if same_volume(target, source) else []
        result = subprocess.run(['/bin/cp', *flags, '-R', str(src), str(target / name)],
                                capture_output=True, text=True)
        if result.returncode and flags:
            shutil.rmtree(target / name, ignore_errors=True)
            result = subprocess.run(['/bin/cp', '-R', str(src), str(target / name)], capture_output=True, text=True)
        if result.returncode:
            raise BuildError(f'could not copy {name} from the game data: {result.stderr.strip()}')
        try:
            quarantine.check_kept(src, target / name)
        except OSError as e:
            raise BuildError(str(e)) from e


def remove_quarantine(path):
    """Only for what the Builder verified or produced itself: the SPEED2.EXE that matched a
    supported checksum and the built NFSU2.app."""
    subprocess.run(['/usr/bin/xattr', '-dr', 'com.apple.quarantine', str(path)], capture_output=True)


def remove_quarantine_from_app(app):
    """Everything the build made loses quarantine; Contents/Resources/Game keeps it on the files
    copied from the player's copy (the game only reads them). Its SPEED2.EXE was verified and
    cleared in the staging copy already."""
    game = app / 'Contents/Resources/Game'
    subprocess.run(['/usr/bin/xattr', '-d', 'com.apple.quarantine', str(app), str(app / 'Contents'),
                    str(app / 'Contents/Resources')], capture_output=True)
    for parent in (app / 'Contents', app / 'Contents/Resources'):
        for child in parent.iterdir():
            if child not in (app / 'Contents/Resources', game):
                remove_quarantine(child)


def stage_game(staging, exe, data):
    """Makes `staging` from `data` (a game folder, an NFSU2.app or the discs) with `exe` as
    its SPEED2.EXE. The data is only read; `staging` is made anew."""
    exe_sha = sha256(exe)
    if staging.is_dir() and not staging.is_symlink():
        shutil.rmtree(staging)
    elif staging.exists() or staging.is_symlink():
        staging.unlink()
    staging.parent.mkdir(parents=True, exist_ok=True)
    sources = [game_source(p) for p in data]
    if len(sources) == 1 and sources[0].is_dir() and not any(
            n.lower() == 'compressed.zip' for n in os.listdir(sources[0])):
        print(f'Copying the game data (APFS clones where possible): {sources[0]}', flush=True)
        copy_tree(sources[0], staging)
    else:
        print('Unpacking the discs with tools/install_from_discs.py', flush=True)
        staging.mkdir()
        subprocess.run([sys.executable, str(ROOT / 'tools/install_from_discs.py'), str(staging), *map(str, sources)],
                       check=True)
        emit({'progress': 0.9})
    old = find_exe(staging)
    if old:
        old.unlink()
    shutil.copyfile(exe, staging / 'SPEED2.EXE')
    if sha256(staging / 'SPEED2.EXE') != exe_sha:
        raise BuildError('SPEED2.EXE did not copy correctly')
    remove_quarantine(staging / 'SPEED2.EXE')   # verified against the supported checksums
    print(f'Game data ready: {staging}', flush=True)


# --- running the scripts -------------------------------------------------------------------

def count_new(folder, pattern, since):
    try:
        return sum(1 for p in Path(folder).glob(pattern) if p.stat().st_mtime >= since)
    except OSError:
        return 0


def run(command, env=None, progress=None):
    """Runs one build script from the repository root. `progress` () -> 0..1 is polled."""
    print('$ ' + ' '.join(command), flush=True)
    process = subprocess.Popen(command, cwd=ROOT, env={**os.environ, **(env or {})})
    stop = threading.Event()

    def poll():
        last = -1
        while not stop.wait(2):
            value = round(min(0.99, progress()), 2)
            if value != last:
                emit({'progress': value})
                last = value
    watcher = threading.Thread(target=poll, daemon=True) if progress else None
    if watcher:
        watcher.start()
    try:
        status = process.wait()
    finally:
        stop.set()
        if process.poll() is None:
            process.terminate()
            process.wait()
    if status:
        raise subprocess.CalledProcessError(status, command)


def build(args):
    exe = Path(args.exe).resolve()
    if not exe.is_file():
        raise BuildError('the chosen SPEED2.EXE is no longer there; choose it again')
    exe_sha = sha256(exe)
    region = SUPPORTED.get(exe_sha)
    if not region:
        raise BuildError('this SPEED2.EXE is not one of the two supported versions')
    if args.version and not all(c.isalnum() or c in '.+-' for c in args.version):
        raise BuildError('the Builder version is not a version number')
    if not shutil.which('clang') or not shutil.which('swiftc'):
        raise BuildError('the Xcode command line tools are missing; install them and try again')
    data = [Path(p).expanduser().absolute() for p in args.data]
    missing = [p for p in data if not p.exists()]
    if missing:
        raise BuildError(f'{missing[0].name} is no longer there; choose your game data again')

    staging = ROOT / STAGING
    try:
        step('prepare', 'Preparing the game data')
        stage_game(staging, exe, data)
        game_exe = staging / 'SPEED2.EXE'
        env = {'BUILD': region}
        gen, obj = ('gen/all', 'out/obj') if region == 'eu' else ('gen/na', 'out/obj_na')

        step('lift', 'Translating SPEED2.EXE to C (tools/gen_v2.sh)')
        started = time.time()
        run(['tools/gen_v2.sh', str(game_exe)], env,
            progress=lambda: count_new(ROOT / gen, 'shard_*.c', started) / 136)

        step('compile', 'Compiling the translated code (build.sh)')
        started = time.time()
        shards = max(1, len(list((ROOT / gen).glob('shard_*.c'))) + 2)
        run(['./build.sh'], env, progress=lambda: count_new(ROOT / obj, '*.o', started) / shards)

        step('link', 'Building the original and HD engines (link.sh)')
        run(['./link.sh'], env)

        step('package', 'Building the launcher and the app with the game inside (pack.sh)')
        run(['./pack.sh', '--region', region, '--embed'],
            {'ICON_EXE': str(game_exe), 'GAME_DIR': str(staging), 'BUILDER_VERSION': args.version or ''})
    finally:
        # The app holds its own clones now; the staging copy goes in every case (also on Cancel).
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)

    step('sign', 'Checking the signature')
    app = ROOT / APP
    macos = app / 'Contents/MacOS'
    engines = ['nfsu2-engine', 'nfsu2-engine-hd'] if region == 'eu' else ['nfsu2-engine-na', 'nfsu2-engine-na-hd']
    missing = [e for e in engines if not (macos / e).is_file()]
    if missing:
        raise BuildError('the app is incomplete: ' + ', '.join(missing) + ' missing')
    # pack.sh only warns and packs the game without its launcher window when swiftc fails
    if not (ROOT / 'out/nfsu2_launcher').is_file():
        raise BuildError("the launcher did not compile with this Mac's Swift. Install the latest "
                         'Command Line Tools in System Settings > General > Software Update and try '
                         'again. If it still fails, report it with Copy log.')
    inside = find_exe(app / 'Contents/Resources/Game') if (app / 'Contents/Resources/Game').is_dir() else None
    if not inside or sha256(inside) != exe_sha:
        raise BuildError('the game did not go into the app completely')
    remove_quarantine_from_app(app)
    result = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)],
                            capture_output=True, text=True)
    if result.returncode:
        raise BuildError('the app signature does not verify: ' + result.stderr.strip())
    print(f'\nReady: {app} (the game is inside it)', flush=True)
    emit({'done': str(app)})


def main(argv=None):
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))  # Cancel: unwind temporary folders
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    setup_args = commands.add_parser('setup', help='create .venv and install requirements.txt')
    setup_args.add_argument('--venv', help='the venv to set up (default: .venv)')
    b = commands.add_parser('build', help='build out/personal/NFSU2.app with the game inside')
    b.add_argument('--exe', required=True, help='a supported SPEED2.EXE')
    b.add_argument('--data', action='append', required=True,
                   help='the game folder, an NFSU2.app with the game inside, or a disc image (twice for two discs)')
    b.add_argument('--version', default='', help='the Builder version, for the app\'s Info.plist')
    args = parser.parse_args(argv)
    try:
        if args.command == 'setup':
            setup(args.venv)
        else:
            build(args)
    except (BuildError, OSError, ValueError) as error:
        print(f'Build failed: {error}', file=sys.stderr, flush=True)
        emit({'error': str(error)})
        return 1
    except subprocess.CalledProcessError as error:
        print(f'Build failed: {error}', file=sys.stderr, flush=True)
        emit({'error': STEP_FAILED})
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
