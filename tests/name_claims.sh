#!/bin/sh
# Claimed names in the launcher (launcher/NameClaims.swift) against a stand-in
# for the server's /names on 127.0.0.1 (tests/name_claims.py).
set -eu
cd "$(dirname "$0")/.."
exec /usr/bin/python3 -I tests/name_claims.py
