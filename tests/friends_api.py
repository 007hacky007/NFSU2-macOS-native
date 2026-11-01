#!/usr/bin/env python3
"""Free roam's friends (launcher/Friends.swift) against a stand-in for the
server's /friends on 127.0.0.1 only, its answers as nfsu2-web's
web/server-rs/src/app/friends.rs gives them: the lists with the keyphrase's
token, a request by name, accept, decline, remove (a friend, or a request taken
back), 401 for a keyphrase the server does not know, 404 for a server without
friends.  Builds tests/friends_api.swift with the launcher's sources."""
import json
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

state = {"owner": None, "friends": [{"name": "Bo", "where": "roam", "room": "Blue Room"}, {"name": "Al", "where": "online"},
                                    {"name": "Cy", "where": ""}],
         "asks": ["Dee"], "sent": ["Eve"], "mail": [{"from": "Bo", "body": "hi there", "at": 1}], "calls": [], "off": False}
CLAIMED = {"fay": "Fay_", "dee": "Dee", "eve": "Eve"}


class Friends(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def answer(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def lists(self, done=None):
        mail, state["mail"] = state["mail"], []          # read once: gone from the server
        v = {"me": "Ann", "friends": state["friends"], "asks": state["asks"], "sent": state["sent"], "mail": mail}
        if done is not None:
            v["done"] = done
        # and something of a kind the page leaves out
        v["friends"] = v["friends"] + [{"name": 7}, "x"]
        return v

    def check(self):
        assert self.headers.get("Origin") is None and self.headers.get("User-Agent") == "NFSU2-Launcher"
        if self.path != "/friends" or state["off"]:
            self.answer(404, {})
            return None
        a = self.headers.get("Authorization", "")
        tok = a[7:] if a.startswith("Bearer ") and len(a) == 50 else None
        state["calls"].append((self.command, tok))
        if not tok or (state["owner"] and tok != state["owner"]):
            self.answer(401, {"error": "keyphrase"})
            return None
        state["owner"] = state["owner"] or tok
        return tok

    def do_GET(self):
        if self.check():
            self.answer(200, self.lists())

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n))
        if not self.check():
            return
        op, name = body.get("op"), body.get("name", "")
        done = "none"
        if op == "ask":
            claimed = CLAIMED.get(name.lower())
            if not claimed:
                done = "claim"
            elif claimed.lower() in [a.lower() for a in state["asks"]]:
                state["asks"] = [a for a in state["asks"] if a.lower() != claimed.lower()]
                state["friends"].append({"name": claimed, "where": ""}); done = "friends"
            else:
                state["sent"].append(claimed); done = "asked"
        elif op == "accept" and name in state["asks"]:
            state["asks"].remove(name); state["friends"].append({"name": name, "where": ""}); done = "friends"
        elif op == "decline" and name in state["asks"]:
            state["asks"].remove(name); done = "declined"
        elif op == "remove":
            state["friends"] = [f for f in state["friends"] if f["name"] != name]
            state["sent"] = [s for s in state["sent"] if s != name]; done = "removed"
        else:
            return self.answer(400, {"error": "invalid"})
        self.answer(200, self.lists(done))


def main():
    root = Path(__file__).resolve().parents[1]
    tmp = tempfile.mkdtemp(prefix="nfsu2-friends-")
    binary = str(Path(tmp) / "friends_api")
    sources = [str(p) for p in sorted((root / "launcher").glob("*.swift")) if p.name != "main.swift"]
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-import-objc-header", str(root / "runtime/names.h"),
                    "-module-cache-path", str(Path(tmp) / "cache")] + sources + [str(root / "tests/friends_api.swift"), "-o", binary], check=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Friends)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    r = subprocess.run([binary, f"ws://127.0.0.1:{port}/lan"], timeout=120)
    assert r.returncode == 0, "the launcher's checks"
    assert all(t is None or len(t) == 43 for _, t in state["calls"]), "only the keyphrase's token, as /names takes it"
    assert state["calls"] and state["calls"][0] == ("GET", state["owner"])
    state["off"] = True
    r = subprocess.run([binary, f"ws://127.0.0.1:{port}/lan", "off"], timeout=60)
    assert r.returncode == 0, "a server without friends"
    server.shutdown()
    print("friends api: lists, request by name, accept, decline, remove, take back, keyphrase and no-friends answers passed")


if __name__ == "__main__":
    main()
