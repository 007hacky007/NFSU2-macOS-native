#!/usr/bin/env python3
"""Non-interactive entry points for NFSU2 Builder (builder/). Prints NFSU2-EVENT JSON lines.

  python3 tools/builder_cli.py setup
      .venv with requirements.txt, for the Python that runs it (the Builder's private one)
  .venv/bin/python tools/builder_cli.py build --exe SPEED2.EXE --game DIR [--data PATH ...]
      the same steps as the Terminal build: tools/gen_v2.sh, build.sh, link.sh, pack.sh
      (README, "Build from Terminal") for the one region SPEED2.EXE belongs to.
      With --data, DIR is made first: from a game folder (APFS clones) or the two disc
      images (tools/install_from_discs.py), with SPEED2.EXE put in. Without, DIR is the
      player's own folder and must already hold a supported SPEED2.EXE. The sources are
      never written to.

Every other output line is plain log text. Events: {"step": ID, "title": TEXT} before each
step (prepare, lift, compile, link, package, sign), {"progress": 0..1} within a step,
{"done": APP, "game": DIR} at the end, {"error": TEXT} on failure (exit 1).
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
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'NFSU2-EVENT '
MARKER = '.nfsu2-builder.json'
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

def setup():
    if sys.platform != 'darwin' or os.uname().machine != 'arm64':
        raise BuildError('building needs an Apple Silicon Mac')
    if sys.version_info < (3, 10):
        raise BuildError('Python 3.10 or newer is needed')
    venv = ROOT / '.venv'
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


# --- the game folder -----------------------------------------------------------------------

def same_volume(a, b):
    a = Path(a)
    while not a.exists():
        a = a.parent
    return os.stat(a).st_dev == os.stat(b).st_dev


def copy_tree(source, target):
    """APFS clones on the same volume (no extra space), a normal copy otherwise."""
    target.mkdir(parents=True)
    for name in sorted(os.listdir(source)):
        if name.startswith('.') or name.lower() == 'speed2.exe':
            continue
        src = Path(source) / name
        flags = ['-c'] if same_volume(target, source) else []
        result = subprocess.run(['/bin/cp', *flags, '-R', str(src), str(target / name)],
                                capture_output=True, text=True)
        if result.returncode and flags:
            result = subprocess.run(['/bin/cp', '-R', str(src), str(target / name)], capture_output=True, text=True)
        if result.returncode:
            raise BuildError(f'could not copy {name} from the game folder: {result.stderr.strip()}')


def remove_quarantine(folder):
    subprocess.run(['/usr/bin/xattr', '-dr', 'com.apple.quarantine', str(folder)], capture_output=True)


def prepare_game(game, exe, data):
    """Makes `game` from `data` with `exe` as SPEED2.EXE, or reuses an identical earlier one."""
    exe_sha = sha256(exe)
    record = {'sources': [str(Path(p).resolve()) for p in data], 'exe_sha256': exe_sha, 'version': 1}
    marker = game / MARKER
    if game.exists():
        if not marker.is_file():
            if any(not n.startswith('.') for n in os.listdir(game)):
                raise BuildError(f'{game} already exists and was not made by NFSU2 Builder. '
                                 'Choose another place for the game folder.')
        else:
            try:
                saved = json.loads(marker.read_text())
            except ValueError:
                saved = {}
            current = find_exe(game)
            if saved == record and current and sha256(current) == exe_sha:
                print(f'Reusing the game folder made earlier: {game}', flush=True)
                return
    parent = game.parent
    parent.mkdir(parents=True, exist_ok=True)
    work = parent / f'.{game.name}.tmp-{uuid.uuid4().hex}'
    try:
        if len(data) == 1 and Path(data[0]).is_dir() and not any(
                n.lower() == 'compressed.zip' for n in os.listdir(data[0])):
            print(f'Copying the game folder (APFS clones where possible): {data[0]}', flush=True)
            copy_tree(Path(data[0]), work)
        else:
            print('Unpacking the discs with tools/install_from_discs.py', flush=True)
            work.mkdir()
            subprocess.run([sys.executable, str(ROOT / 'tools/install_from_discs.py'), str(work), *map(str, data)],
                           check=True)
            emit({'progress': 0.9})
        old = find_exe(work)
        if old:
            old.unlink()
        shutil.copyfile(exe, work / 'SPEED2.EXE')
        if sha256(work / 'SPEED2.EXE') != exe_sha:
            raise BuildError('SPEED2.EXE did not copy correctly')
        remove_quarantine(work)
        (work / MARKER).write_text(json.dumps(record, indent=2) + '\n')
        trash = None
        if game.exists():
            trash = parent / f'.{game.name}.trash-{uuid.uuid4().hex}'
            game.rename(trash)
        work.rename(game)
        if trash:
            shutil.rmtree(trash, ignore_errors=True)
        print(f'Game folder ready: {game}', flush=True)
    finally:
        if work.exists():
            shutil.rmtree(work, ignore_errors=True)


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
    exe, game = Path(args.exe).resolve(), Path(args.game).expanduser().absolute()
    if not exe.is_file():
        raise BuildError('the chosen SPEED2.EXE is no longer there; choose it again')
    region = SUPPORTED.get(sha256(exe))
    if not region:
        raise BuildError('this SPEED2.EXE is not one of the two supported versions')
    if not shutil.which('clang') or not shutil.which('swiftc'):
        raise BuildError('the Xcode command line tools are missing; install them and try again')

    step('prepare', 'Preparing the game folder')
    if args.data:
        prepare_game(game, exe, [Path(p) for p in args.data])
    else:
        current = find_exe(game) if game.is_dir() else None
        if not current or SUPPORTED.get(sha256(current)) != region:
            raise BuildError('the game folder no longer holds the supported SPEED2.EXE; choose it again')
        print(f'Using your game folder as it is: {game}', flush=True)
    game_exe = find_exe(game)
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

    step('package', 'Building the launcher and the app (pack.sh)')
    run(['./pack.sh', '--region', region], {'ICON_EXE': str(game_exe)})

    step('sign', 'Checking the signature')
    app = ROOT / 'out/NFSU2.app'
    macos = app / 'Contents/MacOS'
    engines = ['nfsu2-engine', 'nfsu2-engine-hd'] if region == 'eu' else ['nfsu2-engine-na', 'nfsu2-engine-na-hd']
    missing = [e for e in engines if not (macos / e).is_file()]
    if missing or not (ROOT / 'out/nfsu2_launcher').is_file():
        raise BuildError('the app is incomplete: ' + ', '.join(missing or ['the launcher']) + ' missing')
    remove_quarantine(app)
    result = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)],
                            capture_output=True, text=True)
    if result.returncode:
        raise BuildError('the app signature does not verify: ' + result.stderr.strip())
    print(f'\nReady: {app}\nGame folder: {game}', flush=True)
    emit({'done': str(app), 'game': str(game)})


def main(argv=None):
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))  # Cancel: unwind temporary folders
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('setup', help='create .venv and install requirements.txt')
    b = commands.add_parser('build', help='build out/NFSU2.app')
    b.add_argument('--exe', required=True, help='a supported SPEED2.EXE')
    b.add_argument('--game', required=True, help='the game folder the launcher will use')
    b.add_argument('--data', action='append', help='make --game from this folder or disc image (twice for two discs)')
    args = parser.parse_args(argv)
    try:
        if args.command == 'setup':
            setup()
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
