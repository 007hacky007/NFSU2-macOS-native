#!/usr/bin/env python3
"""Loopback-only WebSocket fixture, using no third-party packages.

A relay server of its own on 127.0.0.1 and tests/net/native/transport.m as the
client (runtime/net_native.m): relay (and the round trip of a ping), resume,
queue (and the place in it), two clients, idle, burst, a peer list of a full
server, the launcher's claim token, LAN play's ports (lanports) and exit at
process end.  tests/net_harness.sh runs it inside the
loopback-only sandbox profile (tests/net/loopback-only.sb).
"""
import base64
import hashlib
import os
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import parse_qs, urlsplit


CLAIM = "fixture-claim-token-0123456789abcdefABCDEF_"
CLAIM_EXPECTED = [None]


def exact(conn, size):
    result = b""
    while len(result) < size:
        chunk = conn.recv(size - len(result))
        if not chunk:
            raise EOFError("WebSocket closed")
        result += chunk
    return result


def receive(conn):
    a, b = exact(conn, 2)
    size = b & 127
    if size == 126:
        size = struct.unpack("!H", exact(conn, 2))[0]
    elif size == 127:
        size = struct.unpack("!Q", exact(conn, 8))[0]
    assert size <= 65536
    mask = exact(conn, 4) if b & 128 else None
    data = exact(conn, size)
    if mask:
        data = bytes(x ^ mask[i % 4] for i, x in enumerate(data))
    return a & 15, data


def send(conn, data, binary=False):
    if not binary:
        data = json.dumps(data).encode()
    head = bytes([0x82 if binary else 0x81])
    if len(data) < 126:
        head += bytes([len(data)])
    elif len(data) < 65536:
        head += b"\x7e" + struct.pack("!H", len(data))
    else:
        head += b"\x7f" + struct.pack("!Q", len(data))
    conn.sendall(head + data)


def handshake(conn):
    request = b""
    while not request.endswith(b"\r\n\r\n"):
        request += exact(conn, 1)
        assert len(request) < 16384
    lines = request.decode().split("\r\n")
    path = lines[0].split()[1]
    assert "queue" in parse_qs(urlsplit(path).query, keep_blank_values=True)
    headers = dict(line.split(": ", 1) for line in lines[1:] if ": " in line)
    key = next(v for k, v in headers.items() if k.lower() == "sec-websocket-key")
    assert "NFSU2-native" in next(v for k, v in headers.items() if k.lower() == "user-agent")
    digest = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
    conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + digest + b"\r\n\r\n")
    kind, data = receive(conn)
    hello = json.loads(data)
    assert kind == 1 and hello["t"] == "hello" and hello["name"] == "fixture-player"
    assert not hello.get("bundle") and not hello.get("compact")
    assert hello.get("claim") == CLAIM_EXPECTED[0], "the hello names the launcher's claim token, and only then"
    return hello, path


SET = 0x80000000


def serve(listener, resume=False, queued=False, idle=False, burst=False, big=False, lanports=False):
    if queued:
        conn, _ = listener.accept()
        with conn:
            conn.settimeout(10)
            handshake(conn)
            send(conn, {"t": "queue", "pos": 1, "of": 2, "ticket": "fixture-only-ticket"})
            # a while in the line, so the client sees its place (native_net_get_status)
            time.sleep(0.4)
    conn, address = listener.accept()
    with conn:
        conn.settimeout(10)
        hello, path = handshake(conn)
        if lanports:
            # LAN play open, its UDP sockets' ports said (9999: the server list's adverts)
            assert hello.get("lan") == 1 and hello.get("udp") == SET | 1 << (9999 % 31), hello
        else:
            assert "udp" not in hello, "no ports without LAN play"
        if queued:
            assert hello["ticket"] == "fixture-only-ticket"
            assert "resume" in parse_qs(urlsplit(path).query, keep_blank_values=True)
        send(conn, {"t": "welcome", "vip": 0x0A4D0002, "mask": "255.255.255.0", "token": "fixture-only-token"})
        if big:
            # The whole list as the public server sends it with LAN play on: one message of every player.
            crowd = [{"vip": 0x0A4D0100 + i, "name": f"player-{i:05}-with-a-long-name"} for i in range(4500)]
            send(conn, {"t": "peers", "peers": crowd})
        send(conn, {"t": "peers", "peers": [{"vip": 0x0A4D0002}, {"vip": 0x0A4D0003}]})
        while True:
            kind, data = receive(conn)
            if kind == 1:
                # the switch answers pings: the client's round trip (switch_rtt_ms)
                control = json.loads(data)
                if control.get("t") == "ping":
                    send(conn, {"t": "pong", "id": control["id"]})
                continue
            assert kind == 2
            protocol, source, destination, sport, dport = struct.unpack("!B3xIIHH", data[:16])
            assert (protocol, source, destination, sport, dport, data[16:]) == (1, 0x0A4D0002, 0x0A4D0003, 47210, 47210, b"ping")
            reply = struct.pack("!B3xIIHH", 1, destination, source, dport, sport) + b"pong"
            send(conn, reply, binary=True)
            break
        if lanports:
            # the new ports in {"t":"lan"} (LAN play still on), then a list that names 9 so the client knows
            while True:
                kind, data = receive(conn)
                if kind != 1:
                    continue
                control = json.loads(data)
                if control.get("t") == "ping":
                    send(conn, {"t": "pong", "id": control["id"]})
                    continue
                assert control == {"t": "lan", "on": 1, "udp": SET | 1 << (3658 % 31)}, control
                break
            send(conn, {"t": "peers", "peers": [{"vip": 0x0A4D0002}, {"vip": 0x0A4D0003}, {"vip": 0x0A4D0009}]})
        if burst:
            counts = {1: 0, 3: 0}
            previous = None
            run = 0
            for _ in range(256):
                kind, payload = receive(conn)
                while kind != 2:
                    kind, payload = receive(conn)
                assert payload[16:] == b"load"
                counts[payload[0]] += 1
                run = run + 1 if previous == payload[0] else 1
                previous = payload[0]
                assert run <= 4, "one mailbox starved the other during a queued burst"
            assert counts == {1: 128, 3: 128}
        if not resume:
            try:
                while True:
                    kind, payload = receive(conn)
                    if kind == 8:
                        assert payload == struct.pack("!H", 1000) + (b"idle" if idle else b"closed")
                        conn.sendall(b"\x88" + bytes([len(payload)]) + payload)
                        break
            except (EOFError, ConnectionResetError):
                pass
    if resume:
        conn, _ = listener.accept()
        with conn:
            conn.settimeout(10)
            hello, path = handshake(conn)
            assert "resume" in parse_qs(urlsplit(path).query, keep_blank_values=True)
            assert hello["vip"] == "10.77.0.2" and hello["token"] == "fixture-only-token"
            send(conn, {"t": "welcome", "vip": 0x0A4D0002, "mask": "255.255.255.0", "token": "fixture-next-token"})
            try:
                while receive(conn)[0] != 8:
                    pass
            except (EOFError, ConnectionResetError):
                pass


def serve_two(listener):
    clients = []
    try:
        for vip in (0x0A4D0002, 0x0A4D0003):
            conn, _ = listener.accept()
            conn.settimeout(10)
            handshake(conn)
            clients.append(conn)
        # Both native clients have joined before either receives a welcome.
        for index, conn in enumerate(clients):
            send(conn, {"t": "welcome", "vip": 0x0A4D0002 + index, "mask": "255.255.255.0", "token": "fixture-token"})
        for sender, receiver, payload in ((0, 1, b"ping"), (1, 0, b"pong")):
            while True:
                kind, data = receive(clients[sender])
                if kind == 2:
                    break
            assert data[16:] == payload
            assert struct.unpack("!I", data[8:12])[0] == 0x0A4D0002 + receiver
            send(clients[receiver], data, binary=True)
        for conn in clients:
            try:
                while receive(conn)[0] != 8:
                    pass
            except (EOFError, ConnectionResetError):
                pass
    finally:
        for conn in clients:
            conn.close()


def main():
    root = Path(__file__).resolve().parents[3]
    build = tempfile.mkdtemp(prefix="nfsu2-transport-")
    binary = str(Path(build) / "transport")
    subprocess.run(["clang", "-fobjc-arc", "-I" + str(root / "runtime"), str(root / "tests/net/native/transport.m"), str(root / "runtime/net_native.m"), "-framework", "Foundation", "-o", binary], check=True)
    subprocess.run([binary], check=True)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(2)
        for scenario in ("relay", "resume", "queue", "two", "idle", "burst", "big", "claim", "lanports", "atexit"):
            failure = []
            def worker():
                try:
                    serve_two(listener) if scenario == "two" else serve(listener, resume=scenario == "resume", queued=scenario == "queue", idle=scenario == "idle", burst=scenario == "burst", big=scenario == "big", lanports=scenario == "lanports")
                except BaseException as error:
                    failure.append(error)
            CLAIM_EXPECTED[0] = CLAIM if scenario == "claim" else None
            thread = threading.Thread(target=worker, daemon=True)
            thread.start()
            url = f"ws://127.0.0.1:{listener.getsockname()[1]}/lan"
            if scenario == "two":
                first = subprocess.Popen([binary, url])
                # The first connection is accepted before the second is started.
                time.sleep(0.1)
                second = subprocess.Popen([binary, url, "second"])
                assert first.wait(timeout=20) == 0
                assert second.wait(timeout=20) == 0
            elif scenario == "claim":
                # the launcher's pipe: written and its write end closed before the engine starts
                read_end, write_end = os.pipe()
                os.write(write_end, (CLAIM + "\n").encode())
                os.close(write_end)
                result = subprocess.run([binary, url, "claim"], timeout=20, pass_fds=(read_end,), env={**os.environ, "NFSU2_CLAIM_FD": str(read_end)})
                os.close(read_end)
                assert result.returncode == 0
            else:
                result = subprocess.run([binary, url] + ([scenario] if scenario in ("relay", "resume", "queue", "idle", "burst", "big", "lanports", "atexit") else []), timeout=20)
                assert result.returncode == 0
            thread.join(timeout=5)
            if failure:
                raise failure[0]
            assert not thread.is_alive()
            print(f"Loopback {scenario} passed")
    print("Loopback native WebSocket fixture passed")
    for name in Path(build).iterdir():
        name.unlink()
    Path(build).rmdir()


if __name__ == "__main__":
    main()
