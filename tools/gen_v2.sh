#!/bin/bash
# Compatibility entry point for the NA native generator.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/gen.sh" "$@"
