#!/bin/bash
set -euo pipefail
QUIETLOCK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUIETLOCK_ROOT"
CLANG_MODULE_CACHE_PATH="$QUIETLOCK_ROOT/.build/clang-cache" \
    swift test --cache-path "$QUIETLOCK_ROOT/.build/package-cache" \
    -Xswiftc -module-cache-path -Xswiftc "$QUIETLOCK_ROOT/.build/swift-cache"
