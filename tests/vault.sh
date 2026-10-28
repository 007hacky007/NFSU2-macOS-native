#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tmp/swift-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -module-cache-path out/tmp/swift-cache \
    launcher/SaveArchive.swift launcher/SaveStore.swift launcher/VaultWords.swift launcher/VaultCrypto.swift launcher/VaultPayload.swift tests/vault.swift -o out/tmp/vault_test
out/tmp/vault_test out/tmp/vault-vectors.json
node tests/vault_interop.mjs out/tmp/vault-vectors.json
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -module-cache-path out/tmp/swift-cache \
    launcher/SaveArchive.swift launcher/SaveStore.swift launcher/VaultWords.swift launcher/VaultCrypto.swift launcher/VaultAPI.swift tests/vault_http.swift -o out/tmp/vault_http
