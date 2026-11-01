#!/bin/sh
# Free roam's friends in the launcher (launcher/Friends.swift) against a stand-in
# for the server's /friends on 127.0.0.1 (tests/friends_api.py).  Never the public
# server.
set -eu
cd "$(dirname "$0")/.."
exec /usr/bin/python3 -I tests/friends_api.py
