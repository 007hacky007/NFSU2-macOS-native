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


def tree(folder):
    return {str(p.relative_to(folder)): p.read_bytes() for p in sorted(Path(folder).rglob('*'))
            if p.is_file() and not p.name.startswith('.')}


class MakeBuilderTests(unittest.TestCase):
    def test_bundle_sources_cover_the_build_and_nothing_private(self):
        names = {p.as_posix() for p in make_builder.build_sources(ROOT)}
        for required in ('build.sh', 'link.sh', 'pack.sh', 'VERSION', 'requirements.txt', 'tools/gen_v2.sh',
                         'tools/builder_cli.py', 'tools/install_from_discs.py', 'tools/disc.py',
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
                subprocess.run(command, cwd=self.root, env={**os.environ, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
                                                            **(env or {})}, check=True, capture_output=True)
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
                          'SPEED2.EXE': self.EXE})
        self.assertFalse((self.root / builder_cli.STAGING).exists(), 'the staging copy is removed')
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
        (folder / 'GLOBAL/run.command').write_text('#!/bin/sh\n')
        quarantine = '0081;00000000;Test;'
        for f in (folder / 'GLOBAL/GLOBALB.LZC', self.root / 'out/nfsu2_launcher'):
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', quarantine, str(f)], check=True)
        status, events, _ = self.build(folder / 'SPEED2.EXE', folder)
        self.assertEqual(status, 0, events)
        app = self.root / builder_cli.APP
        game = app / 'Contents/Resources/Game'
        self.assertEqual(sorted(tree(game)), ['GLOBAL/GLOBALB.LZC', 'MOVIES/intro.vp6', 'SPEED2.EXE', 'server.dll'])

        def attr(path):
            r = subprocess.run(['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(path)], capture_output=True, text=True)
            return r.stdout.strip() if r.returncode == 0 else None
        self.assertEqual(attr(game / 'GLOBAL/GLOBALB.LZC'), quarantine, 'game data keeps its quarantine')
        self.assertIsNone(attr(app / 'Contents/MacOS/NFSU2'), 'what the build made loses it')
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True,
                       capture_output=True)

    def test_update_from_an_existing_app_keeps_it_as_it_was(self):
        """The new app is made in the workspace from the old app's game; the old app is only read
        (installing it over the old one is BuilderCore's installApp, tested in DestinationTests)."""
        old = self.tmp / 'Applications/NFSU2.app'
        self.game_folder(old / 'Contents/Resources/Game')
        shutil.rmtree(old / 'Contents/Resources/Game/SCRIPTS')
        (old / 'Contents/Resources/Game/dinput8.dll').unlink()
        (old / 'Contents/Resources/Game/.DS_Store').unlink()
        (old / 'Contents/Resources/Game/SPEED2.EXE').write_bytes(self.EXE)
        with open(old / 'Contents/Info.plist', 'wb') as f:
            plistlib.dump({'CFBundleIdentifier': 'org.nfsu2.nativeport', 'NFSBuilderVersion': '1.0.0'}, f)
        before = manifest(old)
        status, events, _ = self.build(old / 'Contents/Resources/Game/SPEED2.EXE', old, version='1.2.0')
        self.assertEqual(status, 0, events)
        self.assertEqual(manifest(old), before, 'the old app is only read')
        app = self.root / builder_cli.APP
        self.assertEqual(tree(app / 'Contents/Resources/Game'), tree(old / 'Contents/Resources/Game'))
        with open(app / 'Contents/Info.plist', 'rb') as f:
            self.assertEqual(plistlib.load(f)['NFSBuilderVersion'], '1.2.0')

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


if __name__ == '__main__':
    unittest.main()
