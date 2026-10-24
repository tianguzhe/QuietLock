#!/bin/bash
set -euo pipefail

QUIETLOCK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUIETLOCK_ROOT"
mkdir -p .build

if [ ! -f QuietLock/AppIcon.icns ] || [ Tools/GenerateIcon.swift -nt QuietLock/AppIcon.icns ] || [ QuietLock/BrandMark.swift -nt QuietLock/AppIcon.icns ]; then
    CLANG_MODULE_CACHE_PATH="$QUIETLOCK_ROOT/.build/clang-cache" \
    xcrun swiftc -parse-as-library -module-cache-path "$QUIETLOCK_ROOT/.build/swift-cache" \
        QuietLock/BrandMark.swift QuietLock/VisualEffectView.swift Tools/GenerateIcon.swift \
        -o .build/GenerateIcon
    .build/GenerateIcon "$QUIETLOCK_ROOT/.build/AppIcon.iconset"
    /usr/bin/iconutil -c icns .build/AppIcon.iconset -o QuietLock/AppIcon.icns
fi

printf 'Building QuietLock for Apple Silicon and Intel…\n'
if ! xcodebuild -project QuietLock.xcodeproj -scheme QuietLock \
    -configuration Release -derivedDataPath .build/xcode \
    -destination 'generic/platform=macOS' \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO build > .build/build.log 2>&1; then
    tail -n 80 .build/build.log
    exit 1
fi

# Intermediate product: only the DMG in dist/ is distributed.
/bin/rm -rf .build/QuietLock.app
/usr/bin/ditto .build/xcode/Build/Products/Release/QuietLock.app .build/QuietLock.app
/usr/bin/codesign --force --sign - .build/QuietLock.app
/usr/bin/codesign --verify --strict .build/QuietLock.app
printf '\nBuilt: %s/.build/QuietLock.app\n' "$QUIETLOCK_ROOT"
