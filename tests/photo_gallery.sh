#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p out/tmp/swift-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -module-cache-path out/tmp/swift-cache \
    launcher/PhotoGallery.swift tests/photo_gallery.swift -o out/tmp/photo_gallery_test
out/tmp/photo_gallery_test
