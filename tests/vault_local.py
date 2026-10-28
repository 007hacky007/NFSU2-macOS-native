#!/usr/bin/env python3
"""Exercise the native vault against the donor server using disposable synthetic saves."""
import http.server
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parent.parent
donor = Path(os.environ.get('NFSU2_WEB_DONOR', root.parent / 'nfsu2-web'))
server = root / 'out/server-rs-target/debug/nfsu2-server'
client = root / 'out/tmp/vault_http'
assert server.is_file() and client.is_file(), 'Build the donor server and run tests/vault.sh first'

with tempfile.TemporaryDirectory(prefix='vault-local-', dir=root / 'out/tmp') as temp:
    temp = Path(temp)
    for name in ['data', 'dist', 'state']:
        (temp / name).mkdir()
    (temp / 'data/SPEED2.EXE').write_bytes(b'')
    (temp / 'game.wasm').write_bytes(b'')
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    endpoint = f'http://localhost:{port}/vault'
    with (temp / 'server.log').open('wb') as log:
        process = subprocess.Popen([str(server), '--data', str(temp / 'data'), '--dist', str(temp / 'dist'),
                                    '--wasm', str(temp / 'game.wasm'), '--state', str(temp / 'state'),
                                    '--http-port', str(port), '--online', 'off', '--roam-hub', 'off', '--vault-gb', '0.01'],
                                   cwd=root, stdout=log, stderr=log)
        try:
            for _ in range(100):
                assert process.poll() is None, 'Local donor server exited'
                try:
                    urllib.request.urlopen(endpoint, timeout=0.2)
                except urllib.error.HTTPError as error:
                    if error.code == 401:
                        break
                except urllib.error.URLError:
                    pass
                time.sleep(0.05)
            else:
                raise AssertionError('Local donor server did not start')
            fixture = temp / 'exchange.json'
            subprocess.run([str(client), 'seed', str(fixture), endpoint], check=True)
            subprocess.run(['node', str(root / 'tests/vault_browser.mjs'), str(fixture), str(donor / 'web/src/app/zip.ts')], check=True)
            subprocess.run([str(client), 'verify', str(fixture)], check=True)
        finally:
            process.terminate()
            process.wait(timeout=5)

    class UnsafeServer(http.server.BaseHTTPRequestHandler):
        leaked = False
        def log_message(self, *_):
            pass
        def do_GET(self):
            if self.path == '/redirect':
                self.send_response(302)
                self.send_header('Location', f'http://localhost:{self.server.server_port}/leak')
                self.send_header('Content-Length', '0')
                self.end_headers()
            elif self.path == '/leak':
                UnsafeServer.leaked = True
                self.send_response(500)
                self.end_headers()
            else:
                self.send_response(200)
                if self.path == '/declared':
                    self.send_header('Content-Length', str(2**30))
                self.end_headers()
                try:
                    for _ in range(10):
                        self.wfile.write(bytes(65536))
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
    fake = http.server.HTTPServer(('127.0.0.1', 0), UnsafeServer)
    thread = threading.Thread(target=fake.serve_forever, daemon=True)
    thread.start()
    try:
        for path, expected in [('redirect', 'HTTP 302'), ('declared', 'too large'), ('streamed', 'too large')]:
            subprocess.run([str(client), 'reject', str(temp / 'unused'), f'http://localhost:{fake.server_port}/{path}', expected], check=True)
        assert not UnsafeServer.leaked, 'Authorization followed a redirect'
    finally:
        fake.shutdown()
        fake.server_close()
print('vault_local: donor/browser/native round trip, optimistic conflicts, redirect refusal and bounded responses passed')
