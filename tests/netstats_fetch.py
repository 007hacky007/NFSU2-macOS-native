#!/usr/bin/env python3
"""The Online statistics panel's /players fetch (runtime/netstats.m) against a
stand-in for the server's /players on 127.0.0.1 only (its answers as
web/server-rs gives them).  Builds tests/netstats_fetch.m with the runtime's
netstats.m, netstats_core.c and net_native.m and runs one process per
scenario:
  counts     the first ask at the start, without room or crews; the panel shows
             the counts; free roam starts and it asks again with ?room= and
             &crews= as the launcher does; User-Agent NFSU2-native, no cookie
             sent back, no other request meanwhile
  redirect   a 302 is the answer, not followed
  big        an answer over the limit (Content-Length)
  bigstream  ...without Content-Length, cut while it is read
  notjson    a 200 that is not counts
  status     a 503
  remote     a server that is not on this Mac in a test run: no request at all
  offline    without Play online the panel is off and asks nothing
Never the public server.  tests/netstats_unit.sh runs it inside the
loopback-only sandbox profile."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

state = {"mode": "counts", "requests": []}
COUNTS = {"players": 14, "online": 3, "roam": 9, "full": False, "queue": 0, "roamBusy": False}


class Players(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def answer(self, code, body, headers=(), length=True):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        for k, v in headers:
            self.send_header(k, v)
        if length:
            self.send_header("Content-Length", str(len(body)))
        else:
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        state["requests"].append((self.path, dict(self.headers.items())))
        mode = state["mode"]
        if mode == "redirect":
            return self.answer(302, b"", [("Location", "http://127.0.0.1:%d/elsewhere" % self.server.server_address[1])])
        if mode in ("big", "bigstream"):
            body = json.dumps(dict(COUNTS, pad="x" * 70000)).encode()
            return self.answer(200, body, length=mode == "big")
        if mode == "notjson":
            return self.answer(200, b"<html>not counts</html>")
        if mode == "status":
            return self.answer(503, json.dumps(COUNTS).encode())
        if self.path == "/players":
            return self.answer(200, json.dumps(COUNTS).encode(), [("Set-Cookie", "seen=1; Path=/")])
        if self.path == "/players?room=111&crews=222,333":
            return self.answer(200, json.dumps(dict(COUNTS, roamBusy=True, room=4, crews=[2, 1])).encode())
        return self.answer(404, b"{}")


def main():
    root = Path(__file__).resolve().parents[1]
    build = Path(tempfile.mkdtemp(prefix="nfsu2-netstats-"))
    binary = str(build / "netstats_fetch")
    subprocess.run(["clang", "-O1", "-fobjc-arc", "-I" + str(root / "runtime"), str(root / "tests/netstats_fetch.m"),
                    str(root / "runtime/netstats.m"), str(root / "runtime/netstats_core.c"), str(root / "runtime/net_native.m"),
                    "-framework", "Foundation", "-framework", "Cocoa", "-framework", "Metal", "-o", binary], check=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Players)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    local = "ws://127.0.0.1:%d/lan" % server.server_address[1]
    failed = 0
    for scenario in ("counts", "redirect", "big", "bigstream", "notjson", "status", "remote", "offline"):
        state["mode"] = scenario
        state["requests"] = []
        url = "wss://nfsu2.invalid/lan" if scenario == "remote" else local
        run = subprocess.run([binary, url, scenario, "12" if scenario == "counts" else "6"], capture_output=True, text=True, timeout=40)
        reqs = state["requests"]
        problems = []
        if run.returncode != 0:
            problems.append("the panel did not show what it should (exit %d)" % run.returncode)
        if scenario == "counts":
            paths = [p for p, _ in reqs]
            if paths != ["/players", "/players?room=111&crews=222,333"]:
                problems.append("asked %s" % paths)
            for _, h in reqs:
                if h.get("User-Agent") != "NFSU2-native":
                    problems.append("User-Agent %r" % h.get("User-Agent"))
                if "Cookie" in h:
                    problems.append("a cookie was sent back")
        elif scenario in ("remote", "offline"):
            if reqs:
                problems.append("%d request(s) made" % len(reqs))
            if scenario == "remote" and "[net] BLOCKED the player counts from nfsu2.invalid" not in run.stderr:
                problems.append("no BLOCKED note")
        elif len(reqs) != 1:
            problems.append("%d requests, not one (a redirect followed, or asked again at once)" % len(reqs))
        if problems:
            failed += 1
            print("FAIL  %s: %s" % (scenario, "; ".join(problems)))
            print(run.stdout + run.stderr)
        else:
            print("PASS  %s" % scenario)
            if scenario == "counts":
                print(run.stdout.rstrip())
    server.shutdown()
    for f in build.iterdir():
        f.unlink()
    build.rmdir()
    print("netstats fetch: all passed" if not failed else "netstats fetch: %d FAILED" % failed)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
