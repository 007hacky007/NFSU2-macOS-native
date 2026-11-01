"""NFSU2 Builder's Python side: tools/builder_cli.py, tools/make_builder.py, tools/disc.py and
tools/install_from_discs.py. No game files: everything here is made up.

  python3 -m unittest discover -s tests -t tests -p 'test_*.py'
"""
import contextlib
import hashlib
import io
import json
import os
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
            status, events = self.run_cli('build', '--exe', str(exe), '--game', str(self.tmp / 'g'))
        self.assertEqual(status, 1)
        self.assertEqual(events, [{'error': 'this SPEED2.EXE is not one of the two supported versions'}])
        run.assert_not_called()
        self.assertFalse((self.tmp / 'g').exists())

    def test_missing_exe(self):
        status, events = self.run_cli('build', '--exe', str(self.tmp / 'nope.exe'), '--game', str(self.tmp / 'g'))
        self.assertEqual((status, events[-1]), (1, {'error': 'the chosen SPEED2.EXE is no longer there; choose it again'}))

    def test_prepare_game_from_folder_clones_and_never_writes_the_source(self):
        source = self.tmp / 'My Game'
        (source / 'GLOBAL').mkdir(parents=True)
        (source / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (source / 'SPEED2.EXE').write_text('disc exe')
        (source / '.DS_Store').write_text('x')
        before = tree(source)
        exe = self.tmp / 'program/SPEED2.EXE'
        exe.parent.mkdir()
        exe.write_bytes(b'supported exe')
        game = self.tmp / 'Games/NFSU2'
        with contextlib.redirect_stdout(io.StringIO()):
            builder_cli.prepare_game(game, exe, [source])
        self.assertEqual(tree(source), before)
        self.assertEqual((game / 'SPEED2.EXE').read_bytes(), b'supported exe')
        self.assertEqual((game / 'GLOBAL/GLOBALB.LZC').read_text(), 'global')
        self.assertFalse((game / '.DS_Store').exists())
        marker = json.loads((game / builder_cli.MARKER).read_text())
        self.assertEqual(marker['exe_sha256'], hashlib.sha256(b'supported exe').hexdigest())
        self.assertEqual([p.name for p in game.parent.iterdir()], ['NFSU2'], 'no temporary folders left')
        # The same inputs again: reused untouched.
        stamp = (game / 'GLOBAL/GLOBALB.LZC').stat().st_ino
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            builder_cli.prepare_game(game, exe, [source])
        self.assertIn('Reusing', out.getvalue())
        self.assertEqual((game / 'GLOBAL/GLOBALB.LZC').stat().st_ino, stamp)
        # Another program: made again, still only from the source.
        exe.write_bytes(b'other supported exe')
        with contextlib.redirect_stdout(io.StringIO()):
            builder_cli.prepare_game(game, exe, [source])
        self.assertEqual((game / 'SPEED2.EXE').read_bytes(), b'other supported exe')
        self.assertEqual(sorted(p.name for p in game.parent.iterdir()), ['NFSU2'])

    def test_unverified_files_keep_their_quarantine(self):
        source = self.tmp / 'Downloaded Game'
        (source / 'GLOBAL').mkdir(parents=True)
        (source / 'GLOBAL/GLOBALB.LZC').write_text('global')
        (source / 'Tool.app/Contents/MacOS').mkdir(parents=True)
        (source / 'Tool.app/Contents/MacOS/Tool').write_text('#!/bin/sh\n')
        flag = '0081;00000000;Browser;'
        for extra in ('GLOBAL/GLOBALB.LZC', 'Tool.app/Contents/MacOS/Tool'):
            subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', flag, str(source / extra)], check=True)
        exe = self.tmp / 'SPEED2.EXE'
        exe.write_bytes(b'supported exe')
        subprocess.run(['/usr/bin/xattr', '-w', 'com.apple.quarantine', flag, str(exe)], check=True)
        game = self.tmp / 'Games/NFSU2'
        with contextlib.redirect_stdout(io.StringIO()):
            builder_cli.prepare_game(game, exe, [source])

        def quarantine(path):
            return subprocess.run(['/usr/bin/xattr', '-p', 'com.apple.quarantine', str(path)],
                                  capture_output=True, text=True).stdout.strip()
        self.assertEqual(quarantine(game / 'Tool.app/Contents/MacOS/Tool'), flag)
        self.assertEqual(quarantine(game / 'GLOBAL/GLOBALB.LZC'), flag)
        self.assertEqual(quarantine(game / 'SPEED2.EXE'), '', 'only the verified SPEED2.EXE is cleared')
        self.assertEqual(quarantine(source / 'Tool.app/Contents/MacOS/Tool'), flag)

    def test_prepare_game_refuses_a_folder_it_did_not_make(self):
        game = self.tmp / 'Games/NFSU2'
        game.mkdir(parents=True)
        (game / 'save.dat').write_text('mine')
        exe = self.tmp / 'SPEED2.EXE'
        exe.write_bytes(b'x')
        source = self.tmp / 'src'
        source.mkdir()
        with self.assertRaises(builder_cli.BuildError) as caught:
            builder_cli.prepare_game(game, exe, [source])
        self.assertIn('was not made by NFSU2 Builder', str(caught.exception))
        self.assertEqual((game / 'save.dat').read_text(), 'mine')

    def test_prepare_game_from_discs(self):
        one, two = make_discs(self.tmp)
        before = tree(one), tree(two)
        exe = self.tmp / 'SPEED2.EXE'
        exe.write_bytes(b'supported exe')
        game = self.tmp / 'Games/NFSU2'
        with contextlib.redirect_stdout(io.StringIO()):
            builder_cli.prepare_game(game, exe, [one, two])
        self.assertEqual((tree(one), tree(two)), before)
        self.assertEqual(set(tree(game)), {'TRACKS/TRACKMAP4014.bin', 'GLOBAL/GLOBALB.LZC', 'server.dll',
                                           'MOVIES/intro.vp6', 'SPEED2.EXE'})
        self.assertEqual((game / 'SPEED2.EXE').read_bytes(), b'supported exe')

    def test_supported_list_matches_gen_v2(self):
        gen = (ROOT / 'tools/gen_v2.sh').read_text()
        for sha in builder_cli.SUPPORTED:
            self.assertIn(sha, gen)


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
