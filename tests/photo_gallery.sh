#!/bin/sh
# tests/photo_gallery.sh -- the launcher's Screenshots window (launcher/PhotoGallery.swift) without the launcher:
# listing, bounded decoding, safe export and deleting only the chosen screenshot (tests/photo_gallery.swift).
# Needs swiftc.
set -eu
cd "$(dirname "$0")/.."
output="${TMPDIR:-/tmp}/nfsu2-photo-gallery-tests"
mkdir -p "$output/swift-cache"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -module-cache-path "$output/swift-cache" \
    launcher/PhotoGallery.swift tests/photo_gallery.swift -o "$output/photo_gallery_test"
"$output/photo_gallery_test"
# --preview <dir>: also three made-up screenshots in <dir>/Screenshots, the window open on them and
# its picture as <dir>/photo-gallery.png
if [ "${1:-}" = --preview ] && [ -n "${2:-}" ]; then
    xcrun swiftc -swift-version 5 -target arm64-apple-macosx11 -module-cache-path "$output/swift-cache" \
        launcher/PhotoGallery.swift tests/photo_gallery_preview.swift -o "$output/photo_gallery_preview"
    "$output/photo_gallery_preview" "$2"
fi
