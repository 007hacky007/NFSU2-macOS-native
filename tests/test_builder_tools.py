"""NFSU2 Builder's Python side: tools/builder_cli.py, tools/make_builder.py, tools/disc.py and
tools/install_from_discs.py. No game files: everything here is made up.

  python3 -m unittest discover -s tests -t tests -p 'test_*.py'
"""
import contextlib
import hashlib
import io
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools import builder_cli, make_builder  # noqa: E402
from tools.disc import Disc  # noqa: E402


def make_discs(base):
    """Two disc folders laid out like the PC discs."""
    one, two = base / 'Disc 1', base / 'Disc 2'
    for d in (one, two):
        d.mkdir(parents=True)
    with zipfile.ZipFile(one / 'compressed.zip', 'w') as z:
        z.writestr('TRACKS\\TRACKMAP4014.bin', 'trackmap')
    (one / 'autorun.inf').write_text('[autorun]')
    (one / 'Support').mkdir()
    (one / 'Support/readme.txt').write_text('help')
    with zipfile.ZipFile(two / 'compressed.zip', 'w') as z:
        z.writestr('GLOBAL\\GLOBALB.LZC', 'global')
        z.writestr('server.dll', 'server')
    (two / 'MOVIES').mkdir()
    (two / 'MOVIES/intro.vp6').write_text('movie')
    (two / 'speed2.exe').write_text('disc exe')
    (two / '00000001.TMP').write_text('x')
    return one, two


def manifest(folder):
    """Every entry under `folder` with its type, size, contents, mode and times: what "never
    written to" means."""
    out = {}
    for p in sorted(Path(folder).rglob('*')):
        st = p.lstat()
        out[str(p.relative_to(folder))] = (st.st_mode, st.st_size, st.st_mtime_ns, st.st_ino,
                                           p.read_bytes() if p.is_file() and not p.is_symlink() else None)
    return out


def quarantine_of(path):
    r = subprocess.run(['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(path)], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def set_quarantine(path, value):
    subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', value, str(path)], check=True)


def tree(folder):
    return {str(p.relative_to(folder)): p.read_bytes() for p in sorted(Path(folder).rglob('*'))
            if p.is_file() and not p.name.startswith('.')}


class MakeBuilderTests(unittest.TestCase):
    def test_bundle_sources_cover_the_build_and_nothing_private(self):
        names = {p.as_posix() for p in make_builder.build_sources(ROOT)}
        for required in ('build.sh', 'link.sh', 'pack.sh', 'VERSION', 'requirements.txt', 'tools/gen_v2.sh',
                         'tools/builder_cli.py', 'tools/install_from_discs.py', 'tools/disc.py', 'tools/quarantine.py',
                         'tools/known_releases.tsv', 'tools/genall.py', 'runtime/cpu.h', 'launcher/Game.swift',
                         'tests/boot.c', 'tests/main_all.c'):
            self.assertIn(required, names)
        self.assertFalse(any(n.split('/')[0] in ('docs', 'gen', 'out', 'builder', 'screenshots') for n in names))
        self.assertEqual({n for n in names if n.startswith('tests/')}, {'tests/boot.c', 'tests/main_all.c'})
        self.assertFalse(any(n.startswith('tools/nfsref/') or '__pycache__' in n for n in names))
        self.assertFalse(any(n.lower().endswith(('.exe', '.dll', '.asi')) for n in names))

    def test_top_level_entries_match_swift_bundled_source_entries(self):
        swift = (ROOT / 'builder/Sources/BuilderCore/Workspace.swift').read_text()
        match = re.search(r'bundledSourceEntries\s*=\s*\[([^\]]*)\]', swift)
        declared = set(re.findall(r'"([^"]+)"', match.group(1)))
        self.assertEqual({p.parts[0] for p in make_builder.build_sources(ROOT)}, declared)

    def test_minos_parser(self):
        out = 'Load command 9\n      cmd LC_BUILD_VERSION\n    platform 1\n       minos 11.0\n         sdk 15.0\n'
        self.assertEqual(make_builder.parse_minos(out), '11.0')


class BuilderCliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='nfsu2 cli "q" '))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def run_cli(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            status = builder_cli.main(list(args))
        events = [json.loads(line[len(builder_cli.PREFIX):]) for line in out.getvalue().splitlines()
                  if line.startswith(builder_cli.PREFIX)]
        return status, events

    def test_unsupported_exe_is_refused_before_anything_runs(self):
        exe = self.tmp / 'SPEED2.EXE'
        exe.write_bytes(b'MZ not the game')
        with mock.patch.object(builder_cli, 'run') as run:
            status, events = self.run_cli('build', '--exe', str(exe), '--data', str(self.tmp / 'g'))
        self.assertEqual(status, 1)
        self.assertEqual(events, [{'error': 'this SPEED2.EXE is not one of the two supported versions'}])
        run.assert_not_called()
        self.assertFalse((self.tmp / 'g').exists())

    def test_missing_exe(self):
        status, events = self.run_cli('build', '--exe', str(self.tmp / 'nope.exe'), '--data', str(self.tmp / 'g'))
        self.assertEqual((status, events[-1]), (1, {'error': 'the chosen SPEED2.EXE is no longer there; choose it again'}))

    def stage(self, data, exe_bytes=b'supported exe'):
        exe = self.tmp / 'program/SPEED2.EXE'
        exe.parent.mkdir(exist_ok=True)
        exe.write_bytes(exe_bytes)
        staging = self.tmp / 'workspace/out/game'
        with contextlib.redirect_stdout(io.StringIO()):
            builder_cli.stage_game(staging, exe, data)
        return staging

    def test_stage_game_from_folder_clones_and_never_writes_the_source(self):
        source = self.tmp / 'My Game'
        (source / 'GLOBAL').mkdir(parents=True)
        (source / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (source / 'SPEED2.EXE').write_text('disc exe')
        (source / '.DS_Store').write_text('x')
        before = manifest(source)
        staging = self.stage([source])
        self.assertEqual(manifest(source), before)
        self.assertEqual((staging / 'SPEED2.EXE').read_bytes(), b'supported exe')
        self.assertEqual((staging / 'GLOBAL/GLOBALB.LZC').read_text(), 'global')
        self.assertFalse((staging / '.DS_Store').exists())
        # Staged anew every time, still only from the source.
        (staging / 'stale').write_text('x')
        staging = self.stage([source], b'other supported exe')
        self.assertEqual((staging / 'SPEED2.EXE').read_bytes(), b'other supported exe')
        self.assertFalse((staging / 'stale').exists())
        self.assertEqual(manifest(source), before)

    def test_stage_game_from_an_existing_app(self):
        """The update path: an NFSU2.app with the game inside is the game data."""
        app = self.tmp / 'Applications/NFSU2.app'
        game = app / 'Contents/Resources/Game'
        (game / 'GLOBAL').mkdir(parents=True)
        (game / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (game / 'SPEED2.EXE').write_bytes(b'supported exe')
        (app / 'Contents/Info.plist').write_text('plist')
        before = manifest(app)
        staging = self.stage([app])
        self.assertEqual(manifest(app), before)
        self.assertEqual(tree(staging), {'GLOBAL/GLOBALB.LZC': b'global', 'SPEED2.EXE': b'supported exe'})
        empty = self.tmp / 'Old/NFSU2.app'
        (empty / 'Contents').mkdir(parents=True)
        with self.assertRaises(builder_cli.BuildError) as caught:
            self.stage([empty])
        self.assertIn('has no game inside it', str(caught.exception))

    def test_unverified_files_keep_their_quarantine(self):
        source = self.tmp / 'Downloaded Game'
        (source / 'GLOBAL').mkdir(parents=True)
        (source / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (source / 'Tool.app/Contents/MacOS').mkdir(parents=True)
        (source / 'Tool.app/Contents/MacOS/Tool').write_text('#!/bin/sh\n')
        flag = '0081;00000000;Browser;'
        for extra in ('GLOBAL/GLOBALB.LZC', 'Tool.app/Contents/MacOS/Tool'):
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', flag, str(source / extra)], check=True)
        staging = self.stage([source])

        def quarantine(path):
            return subprocess.run(['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(path)],
                                  capture_output=True, text=True).stdout.strip()
        self.assertEqual(quarantine(staging / 'Tool.app/Contents/MacOS/Tool'), flag)
        self.assertEqual(quarantine(staging / 'GLOBAL/GLOBALB.LZC'), flag)
        self.assertEqual(quarantine(staging / 'SPEED2.EXE'), '', 'only the verified SPEED2.EXE is cleared')
        self.assertEqual(quarantine(source / 'Tool.app/Contents/MacOS/Tool'), flag)

    def test_a_copy_instead_of_clones_keeps_the_quarantine_or_stops(self):
        """Game data on another disk is copied (cp -R), not cloned: the copies keep the
        quarantine, and a copy that lost it stops the build instead of going on."""
        source = self.tmp / 'Downloaded Game'
        (source / 'GLOBAL').mkdir(parents=True)
        (source / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (source / 'server.dll').write_text('server')
        flag = '0081;00000000;Browser;'
        for name in ('GLOBAL/GLOBALB.LZC', 'server.dll'):
            set_quarantine(source / name, flag)
        copies = []
        real_run = subprocess.run

        def run(command, *a, **k):
            if command[0] == '/bin/cp':
                copies.append(command[1:-2])
            return real_run(command, *a, **k)
        with mock.patch.object(builder_cli, 'same_volume', return_value=False), \
                mock.patch.object(builder_cli.subprocess, 'run', run):
            staging = self.stage([source])
        self.assertEqual(copies, [['-R'], ['-R']], 'no clones were tried')
        for name in ('GLOBAL/GLOBALB.LZC', 'server.dll'):
            self.assertTrue((quarantine_of(staging / name) or '').startswith('0081;'), name)

        def loses_quarantine(command, *a, **k):    # even cp -X keeps it on macOS, so remove it
            result = real_run(command, *a, **k)
            if command[0] == '/bin/cp':
                real_run(['/usr/bin/xattr', '-dr', 'com.apple.quarantine', command[-1]], check=True)
            return result
        with mock.patch.object(builder_cli, 'same_volume', return_value=False), \
                mock.patch.object(builder_cli.subprocess, 'run', loses_quarantine), \
                self.assertRaises(builder_cli.BuildError) as caught:
            self.stage([source])
        self.assertIn('lost the quarantine', str(caught.exception))

    def test_stage_game_from_quarantined_discs(self):
        """Files unpacked from a downloaded disc image or zip are new files; they get the
        quarantine of what they came from."""
        one, two = make_discs(self.tmp)
        flag = '0081;00000000;Browser;'
        set_quarantine(two / 'compressed.zip', flag)
        set_quarantine(two / 'MOVIES/intro.vp6', flag)
        staging = self.stage([one, two])
        for name in ('GLOBAL/GLOBALB.LZC', 'server.dll', 'MOVIES/intro.vp6'):
            self.assertEqual(quarantine_of(staging / name), flag, name)
        self.assertIsNone(quarantine_of(staging / 'TRACKS/TRACKMAP4014.bin'), 'disc 1 was not quarantined')

    def test_stage_game_from_discs(self):
        one, two = make_discs(self.tmp)
        before = manifest(one), manifest(two)
        staging = self.stage([one, two])
        self.assertEqual((manifest(one), manifest(two)), before)
        self.assertEqual(set(tree(staging)), {'TRACKS/TRACKMAP4014.bin', 'GLOBAL/GLOBALB.LZC', 'server.dll',
                                              'MOVIES/intro.vp6', 'SPEED2.EXE'})
        self.assertEqual((staging / 'SPEED2.EXE').read_bytes(), b'supported exe')

    def test_supported_list_matches_gen_v2(self):
        gen = (ROOT / 'tools/gen_v2.sh').read_text()
        for sha in builder_cli.SUPPORTED:
            self.assertIn(sha, gen)


def game_record(app):
    """Contents/Resources/game-files.tsv read the way BuilderCore's GameRecord reads it:
    {path: (size, sha256)}, after checking the header and the format of every line."""
    lines = (Path(app) / 'Contents/Resources/game-files.tsv').read_text(encoding='utf-8').split('\n')
    assert lines[0] == '# nfsu2-game-files 1' and lines[-1] == '', lines[:1]
    escapes = {'\\\\': '\\', '\\t': '\t', '\\n': '\n', '\\r': '\r'}
    out = {}
    for line in lines[1:-1]:
        name, size, sha = line.split('\t')
        assert re.fullmatch(r'[0-9a-f]{64}', sha) and re.fullmatch(r'[0-9]+', size), line
        path = re.sub(r'\\.', lambda m: escapes[m.group(0)], name)
        assert path not in out, path
        out[path] = (int(size), sha)
    return out


def game_files(game):
    """Every regular file under `game` (hidden ones too) with its size and SHA-256."""
    return {str(p.relative_to(game)): (p.stat().st_size, hashlib.sha256(p.read_bytes()).hexdigest())
            for p in Path(game).rglob('*') if p.is_file() and not p.is_symlink()}


class EmbeddedBuildTests(unittest.TestCase):
    """builder_cli.py build through the real pack.sh --embed in a made-up workspace: the
    engines and the launcher are copies of /usr/bin/true, the lift, compile and link steps are
    skipped. Checks what the app gets and that the game data is only read."""

    EXE = b'MZ a supported test SPEED2.EXE'

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='nfsu2 embed '))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = self.tmp / 'workspace'
        (self.root / 'out').mkdir(parents=True)
        (self.root / 'launcher').mkdir()
        shutil.copy(ROOT / 'pack.sh', self.root / 'pack.sh')
        shutil.copy(ROOT / 'VERSION', self.root / 'VERSION')
        shutil.copy(ROOT / 'launcher/texture-packs.json', self.root / 'launcher/texture-packs.json')
        for name in ('nfsu2_boot', 'nfsu2_hd_boot', 'nfsu2_launcher'):
            shutil.copy('/usr/bin/true', self.root / 'out' / name)

    def game_folder(self, folder):
        (folder / 'GLOBAL').mkdir(parents=True)
        (folder / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (folder / 'MOVIES').mkdir()
        (folder / 'MOVIES/intro.vp6').write_text('movie')
        (folder / 'server.dll').write_text('server')
        (folder / 'SCRIPTS').mkdir()
        (folder / 'SCRIPTS/mod.asi').write_text('windows plugin')
        (folder / 'dinput8.dll').write_text('windows plugin')
        (folder / '.DS_Store').write_text('finder')
        return folder

    def build(self, exe, *data, version='1.1.0'):
        runs = []

        def run(command, env=None, progress=None):
            runs.append(command[0])
            if command[0] == './pack.sh':
                done = subprocess.run(command, cwd=self.root, env={**os.environ, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
                                                                   **(env or {})}, check=True, capture_output=True,
                                      text=True)
                self.pack_log = done.stdout
        out = io.StringIO()
        with mock.patch.object(builder_cli, 'ROOT', self.root), \
                mock.patch.object(builder_cli, 'run', run), \
                mock.patch.dict(builder_cli.SUPPORTED, {hashlib.sha256(self.EXE).hexdigest(): 'eu'}), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            status = builder_cli.main(['build', '--exe', str(exe), *[a for d in data for a in ('--data', str(d))],
                                       '--version', version])
        events = [json.loads(line[len(builder_cli.PREFIX):]) for line in out.getvalue().splitlines()
                  if line.startswith(builder_cli.PREFIX)]
        return status, events, runs

    def test_the_app_has_the_game_inside_and_the_folder_is_only_read(self):
        folder = self.game_folder(self.tmp / 'My Game')
        (folder / 'SPEED2.EXE').write_bytes(b'disc exe')
        exe = self.tmp / 'Downloads/SPEED2.EXE'
        exe.parent.mkdir()
        exe.write_bytes(self.EXE)
        before = manifest(folder)
        status, events, runs = self.build(exe, folder)
        self.assertEqual(status, 0, events)
        app = self.root / builder_cli.APP
        self.assertEqual(events[-1], {'done': str(app)})
        self.assertEqual(runs, ['tools/gen_v2.sh', './build.sh', './link.sh', './pack.sh'])
        self.assertEqual(manifest(folder), before, 'the game folder is only read')
        self.assertEqual(tree(app / 'Contents/Resources/Game'),
                         {'GLOBAL/GLOBALB.LZC': b'global', 'MOVIES/intro.vp6': b'movie', 'server.dll': b'server',
                          'SCRIPTS/mod.asi': b'windows plugin', 'dinput8.dll': b'windows plugin',
                          'SPEED2.EXE': self.EXE}, 'the whole game goes in, Windows extras too; .DS_Store stays out')
        self.assertFalse((self.root / builder_cli.STAGING).exists(), 'the staging copy is removed')
        record = game_record(app)
        self.assertEqual(record, game_files(app / 'Contents/Resources/Game'), 'the record lists every game file')
        self.assertEqual(sorted(record), ['GLOBAL/GLOBALB.LZC', 'MOVIES/intro.vp6', 'SCRIPTS/mod.asi', 'SPEED2.EXE',
                                          'dinput8.dll', 'server.dll'])
        self.assertEqual(record['SPEED2.EXE'], (len(self.EXE), hashlib.sha256(self.EXE).hexdigest()))
        with open(app / 'Contents/Info.plist', 'rb') as f:
            info = plistlib.load(f)
        self.assertEqual(info['NFSBuilderVersion'], '1.1.0')
        self.assertIn('inside this bundle', info['NSHumanReadableCopyright'])
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)

    def test_no_macos_code_from_the_copy_and_its_quarantine_stays(self):
        """A downloaded repack may hide a Mac program: it never goes into the app, and the
        game files keep the download's quarantine (only what the build made loses it)."""
        folder = self.game_folder(self.tmp / 'Repack')
        (folder / 'SPEED2.EXE').write_bytes(self.EXE)
        shutil.copy('/usr/bin/true', folder / 'readme.txt')                 # a Mach-O under another name
        (folder / 'Tool.app/Contents/MacOS').mkdir(parents=True)
        shutil.copy('/usr/bin/true', folder / 'Tool.app/Contents/MacOS/Tool')
        (folder / 'Helper/Contents/MacOS').mkdir(parents=True)              # a bundle without an extension
        (folder / 'Helper/Contents/Info.plist').write_text('<plist/>')
        (folder / 'Helper/Contents/MacOS/Helper').write_text('data')
        (folder / 'GLOBAL/run.command').write_text('#!/bin/sh\n')
        (folder / 'readme.dat').write_text('#!/bin/sh\necho hi\n')        # a script under a game-like name
        (folder / 'GLOBAL/tool.JAR').write_text('PK jar')
        (folder / 'Open.terminal').write_text('<plist/>')
        (folder / 'MOVIES/fat64.bin').write_bytes(bytes.fromhex('cafebabf') + bytes(12))  # 64-bit universal binary head
        (folder / 'MOVIES/intro.vp6').chmod(0o755)
        quarantine = '0081;00000000;Test;'
        for f in (folder / 'GLOBAL/GLOBALB.LZC', self.root / 'out/nfsu2_launcher'):
            set_quarantine(f, quarantine)
        status, events, _ = self.build(folder / 'SPEED2.EXE', folder)
        self.assertEqual(status, 0, events)
        app = self.root / builder_cli.APP
        game = app / 'Contents/Resources/Game'
        self.assertEqual(sorted(tree(game)), ['GLOBAL/GLOBALB.LZC', 'MOVIES/intro.vp6', 'SCRIPTS/mod.asi', 'SPEED2.EXE',
                                              'dinput8.dll', 'server.dll'])
        self.assertFalse((game / 'Helper').exists())
        for name in ('readme.txt', 'Tool.app', 'Helper', 'run.command', 'readme.dat', 'tool.JAR', 'Open.terminal',
                     'fat64.bin'):
            self.assertIn(f'/{name}\n', self.pack_log, f'{name} is named in the build log')
        self.assertEqual(game_record(app), game_files(game), 'the record lists what is left, nothing that was left out')
        executable = [p for p in game.rglob('*') if p.is_file() and p.stat().st_mode & 0o111]
        self.assertEqual(executable, [], 'no game file stays executable')
        self.assertEqual((folder / 'MOVIES/intro.vp6').stat().st_mode & 0o777, 0o755, 'the copy is only read')
        self.assertEqual(quarantine_of(game / 'GLOBAL/GLOBALB.LZC'), quarantine, 'game data keeps its quarantine')
        self.assertIsNone(quarantine_of(app / 'Contents/MacOS/NFSU2'), 'what the build made loses it')
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)

    def test_game_data_on_another_disk_is_copied_with_its_quarantine(self):
        """No clones from another disk: builder_cli.py and pack.sh copy, and the copies keep
        the quarantine (an HFS+ disk image stands in for the other disk)."""
        image, mount = self.tmp / 'disk.dmg', self.tmp / 'Other Disk'
        mount.mkdir()
        subprocess.run(['/usr/bin/hdiutil', 'create', '-quiet', '-size', '8m', '-fs', 'HFS+', '-volname', 'Other',
                        '-o', str(image)], check=True)
        subprocess.run(['/usr/bin/hdiutil', 'attach', '-quiet', '-nobrowse', '-noverify', '-mountpoint', str(mount),
                        str(image)], check=True)
        self.addCleanup(subprocess.run, ['/usr/bin/hdiutil', 'detach', '-quiet', '-force', str(mount)])
        folder = self.game_folder(mount / 'Game')
        (folder / 'SPEED2.EXE').write_bytes(self.EXE)
        flag = '0081;00000000;Browser;'
        set_quarantine(folder / 'GLOBAL/GLOBALB.LZC', flag)
        set_quarantine(folder / 'server.dll', flag)
        status, events, _ = self.build(folder / 'SPEED2.EXE', folder)
        self.assertEqual(status, 0, events)
        app = self.root / builder_cli.APP
        for name in ('GLOBAL/GLOBALB.LZC', 'server.dll'):
            self.assertTrue((quarantine_of(app / 'Contents/Resources/Game' / name) or '').startswith('0081;'), name)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)
        # pack.sh on its own, straight from the other disk.
        shutil.rmtree(app)
        subprocess.run(['./pack.sh', '--region', 'eu', '--embed'], cwd=self.root, check=True, capture_output=True,
                       env={**os.environ, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'GAME_DIR': str(folder)})
        for name in ('GLOBAL/GLOBALB.LZC', 'server.dll'):
            self.assertTrue((quarantine_of(app / 'Contents/Resources/Game' / name) or '').startswith('0081;'), name)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)

    def test_update_from_an_existing_app_keeps_it_as_it_was(self):
        """The new app is made in the workspace from the old app's game; the old app is only read
        (installing it over the old one is BuilderCore's installApp, tested in DestinationTests)
        and the new app's record is the old one's."""
        folder = self.game_folder(self.tmp / 'My Game')
        (folder / 'SPEED2.EXE').write_bytes(self.EXE)
        status, events, _ = self.build(folder / 'SPEED2.EXE', folder, version='1.1.0')
        self.assertEqual(status, 0, events)
        old = self.tmp / 'Applications/NFSU2.app'
        old.parent.mkdir()
        (self.root / builder_cli.APP).rename(old)
        old_game = old / 'Contents/Resources/Game'
        self.assertEqual(game_record(old), game_files(old_game))
        before = manifest(old)
        status, events, _ = self.build(old_game / 'SPEED2.EXE', old, version='1.2.0')
        self.assertEqual(status, 0, events)
        self.assertEqual(manifest(old), before, 'the old app is only read')
        app = self.root / builder_cli.APP
        self.assertEqual(tree(app / 'Contents/Resources/Game'), tree(old_game))
        self.assertEqual((app / 'Contents/Resources/game-files.tsv').read_bytes(),
                         (old / 'Contents/Resources/game-files.tsv').read_bytes(), 'the same game, the same record')
        self.assertEqual(game_record(app), game_files(app / 'Contents/Resources/Game'))
        with open(app / 'Contents/Info.plist', 'rb') as f:
            self.assertEqual(plistlib.load(f)['NFSBuilderVersion'], '1.2.0')
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)

    def test_the_record_writes_any_file_name_as_builder_core_reads_it(self):
        """The line for a name with a tab, a backslash and a non-ASCII letter, exactly as
        GameCopyTests.testRecordFormat parses it."""
        folder = self.game_folder(self.tmp / 'My Game')
        (folder / 'SPEED2.EXE').write_bytes(self.EXE)
        (folder / 'GLOBAL/a\tb\\c \u00f6.txt').write_bytes(b'abc')
        (folder / 'GLOBAL/line\nbreak.txt').write_bytes(b'')
        status, events, _ = self.build(folder / 'SPEED2.EXE', folder)
        self.assertEqual(status, 0, events)
        app = self.root / builder_cli.APP
        lines = (app / 'Contents/Resources/game-files.tsv').read_text(encoding='utf-8').splitlines()
        self.assertEqual(lines[0], '# nfsu2-game-files 1')
        self.assertIn('GLOBAL/a\\tb\\\\c \u00f6.txt\t3\t' + hashlib.sha256(b'abc').hexdigest(), lines)
        self.assertIn('GLOBAL/line\\nbreak.txt\t0\t' + hashlib.sha256(b'').hexdigest(), lines)
        self.assertEqual(list(game_record(app)), sorted(game_record(app), key=str.encode), 'sorted by path')
        self.assertEqual(game_record(app), game_files(app / 'Contents/Resources/Game'))

    def test_a_failed_package_step_leaves_no_staging_copy(self):
        folder = self.game_folder(self.tmp / 'My Game')
        exe = self.tmp / 'SPEED2.EXE'
        exe.write_bytes(self.EXE)
        (self.root / 'pack.sh').write_text('#!/bin/sh\nexit 1\n')
        before = manifest(folder)
        status, events, _ = self.build(exe, folder)
        self.assertEqual((status, events[-1]), (1, {'error': builder_cli.STEP_FAILED}))
        self.assertFalse((self.root / builder_cli.STAGING).exists())
        self.assertEqual(manifest(folder), before)


class DiscTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='nfsu2 disc '))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def iso(self, folder):
        out = self.tmp / f'{folder.name}.iso'
        subprocess.run(['/usr/bin/hdiutil', 'makehybrid', '-iso', '-joliet', '-quiet', '-default-volume-name',
                        'NFSUG2', '-o', str(out), str(folder)], check=True)
        return out

    def test_images_install_like_disc_folders_without_7zip(self):
        one, two = make_discs(self.tmp / 'discs')
        images = [self.iso(one), self.iso(two)]
        with Disc(images[1]) as disc:
            self.assertIn('compressed.zip', {str(e.path) for e in disc.entries()})
        env = {**os.environ, 'PATH': '/usr/bin:/bin'}   # no 7-Zip
        script = str(ROOT / 'tools/install_from_discs.py')
        subprocess.run([sys.executable, script, str(self.tmp / 'from_images'), *map(str, images)],
                       check=True, env=env, capture_output=True)
        subprocess.run([sys.executable, script, str(self.tmp / 'from_folders'), str(one), str(two)],
                       check=True, env=env, capture_output=True)
        self.assertEqual(tree(self.tmp / 'from_images'), tree(self.tmp / 'from_folders'))
        self.assertIn('SPEED2.EXE', tree(self.tmp / 'from_images'))

    def test_files_from_a_quarantined_image_carry_its_quarantine(self):
        one, two = make_discs(self.tmp / 'discs')
        images = [self.iso(one), self.iso(two)]
        flags = ['0081;00000000;Browser;', '0083;00000001;Other;']
        for image, flag in zip(images, flags):
            set_quarantine(image, flag)
        out = self.tmp / 'from_images'
        subprocess.run([sys.executable, str(ROOT / 'tools/install_from_discs.py'), str(out), *map(str, images)],
                       check=True, env={**os.environ, 'PATH': '/usr/bin:/bin'}, capture_output=True)
        self.assertEqual({name: quarantine_of(out / name) for name in tree(out)},
                         {'TRACKS/TRACKMAP4014.bin': flags[0], 'GLOBAL/GLOBALB.LZC': flags[1],
                          'server.dll': flags[1], 'MOVIES/intro.vp6': flags[1], 'SPEED2.EXE': flags[1]})
        # tools/disc.py on its own
        subprocess.run([sys.executable, str(ROOT / 'tools/disc.py'), str(images[1]), str(self.tmp / 'disc2')],
                       check=True, capture_output=True)
        self.assertEqual({quarantine_of(self.tmp / 'disc2' / name) for name in tree(self.tmp / 'disc2')}, {flags[1]})


if __name__ == '__main__':
    unittest.main()
