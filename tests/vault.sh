#!/bin/sh
# Cloud saves (launcher/Vault*.swift): tests/vault.swift (keyphrase, keys, box,
# what is sent, what a download replaces), tests/vault_interop.mjs (the browser's
# WebCrypto and zlib agree with the Swift code byte for byte, needs node), and
# builds out/tmp/vault_http for tests/vault_local.py (the donor server and the
# browser's code on this Mac only; never the public vault).
#   tests/vault.sh [--local]    --local: also run tests/vault_local.py
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tmp/swift-cache
L="launcher/SaveArchive.swift launcher/SaveStore.swift launcher/VaultWords.swift launcher/VaultCrypto.swift launcher/VaultPayload.swift launcher/VaultAPI.swift"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -import-objc-header runtime/names.h -module-cache-path out/tmp/swift-cache $L tests/vault.swift -o out/tmp/vault_test
out/tmp/vault_test out/tmp/vault-vectors.json
node tests/vault_interop.mjs out/tmp/vault-vectors.json
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -import-objc-header runtime/names.h -module-cache-path out/tmp/swift-cache $L tests/vault_http.swift -o out/tmp/vault_http
if [ "${1:-}" = "--local" ]; then /usr/bin/python3 -I tests/vault_local.py; fi
