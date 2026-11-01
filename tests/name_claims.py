#!/usr/bin/env python3
"""Claimed names (launcher/NameClaims.swift) against a stand-in for the server's
/names on 127.0.0.1 only (its answers as web/server-rs/src/app/names.rs gives
them): the check with and without a keyphrase's token, the claim refused until
the keyphrase has cloud saves, the claim, and the model playing with the claim
once the name is the keyphrase's.  Builds tests/name_claims.swift with the
launcher's sources.  Never the public server."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

TOKEN = sys.argv[1] if len(sys.argv) > 1 else None
state = {"vault": False, "claimed": {}, "gets": [], "posts": []}


class Names(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def token(self):
        a = self.headers.get("Authorization", "")
        return a[7:] if a.startswith("Bearer ") and len(a) == 50 else None

    def answer(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def status(self, name, owner):
        low = name.lower()
        if low in ("name", "player"):
            return {"name": name, "state": "default"}
        if low == "hitler":
            return {"name": name, "state": "blocked"}
        holder = state["claimed"].get(low) or ({"hacky": "someone-else"}.get(low))
        if holder is None:
            return {"name": name, "state": "free"}
        if owner and holder == owner:
            return {"name": name, "state": "yours", "until": 1893456000000}
        return {"name": name, "state": "taken"}

    def do_GET(self):
        u = urlsplit(self.path)
        assert self.headers.get("Origin") is None and self.headers.get("User-Agent") == "NFSU2-Launcher"
        if u.path != "/names":
            return self.answer(404, {})
        q = parse_qs(u.query)
        state["gets"].append((q["name"][0], self.token()))
        v = self.status(q["name"][0], self.token())
        if "alt" in q:
            v["alt"] = self.status(q["alt"][0], self.token())
        self.answer(200, v)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n))
        t = self.token()
        state["posts"].append((body.get("name"), t))
        if not t:
            return self.answer(401, {"error": "keyphrase"})
        s = self.status(body["name"], t)["state"]
        if s == "taken":
            return self.answer(409, {"error": "taken"})
        if not state["vault"]:
            return self.answer(404, {"error": "keyphrase"})
        state["claimed"][body["name"].lower()] = t
        self.answer(200, {"state": "yours", "mine": {"name": body["name"], "until": 1893456000000, "next": 1770000000000}})

    def do_PUT(self):
        n = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(n)
        state["vault"] = True
        self.send_response(201)
        self.send_header("ETag", '"0123456789abcdef"')
        self.send_header("X-Vault-Saved", "1770000000000")
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    root = Path(__file__).resolve().parents[1]
    tmp = tempfile.mkdtemp(prefix="nfsu2-names-")
    binary = str(Path(tmp) / "name_claims")
    sources = [str(p) for p in sorted((root / "launcher").glob("*.swift")) if p.name != "main.swift"]
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-import-objc-header", str(root / "runtime/names.h"),
                    "-module-cache-path", str(Path(tmp) / "cache")] + sources + [str(root / "tests/name_claims.swift"), "-o", binary], check=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Names)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    # step 1: checks and a claim refused without cloud saves
    r = subprocess.run([binary, f"ws://127.0.0.1:{port}/lan", "before"], timeout=60)
    assert r.returncode == 0
    assert state["posts"] and state["posts"][-1][1], "the claim carried the keyphrase's token"
    assert not state["claimed"], "no claim without cloud saves"
    # step 2: the keyphrase's saves are in the cloud: the claim goes through and the name is its own
    state["vault"] = True
    r = subprocess.run([binary, f"ws://127.0.0.1:{port}/lan", "after"], timeout=60)
    assert r.returncode == 0
    assert "mine" in state["claimed"]
    assert all(t is None or len(t) == 43 for _, t in state["gets"])
    server.shutdown()
    print("name claims: check, refused claim, claim and the model's claim flag passed")


if __name__ == "__main__":
    main()
