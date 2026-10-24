#!/bin/bash
set -euo pipefail
QUIETLOCK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUIETLOCK_ROOT"
mkdir -p .build/previews

# Build once with test.sh (or build.sh) before rendering.
QUIETLOCK_PRODUCTS="$QUIETLOCK_ROOT/.build/xcode/Build/Products/Release"
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 \
    -module-cache-path "$QUIETLOCK_ROOT/.build/swift-cache" \
    -I "$QUIETLOCK_PRODUCTS" \
    QuietLock/BrandMark.swift QuietLock/TimeDial.swift QuietLock/VisualEffectView.swift \
    QuietLock/PresetSlider.swift QuietLock/ScreenSaverControls.swift QuietLock/QuietLockPanel.swift \
    Tools/RenderPreviews.swift "$QUIETLOCK_PRODUCTS/QuietLockCore.o" \
    -o .build/RenderPreviews
# One set per UI language; -AppleLanguages overrides the system preference for this process.
.build/RenderPreviews "$QUIETLOCK_ROOT/.build/previews/en" -AppleLanguages '(en)'
.build/RenderPreviews "$QUIETLOCK_ROOT/.build/previews/zh-Hans" -AppleLanguages '(zh-Hans)'
