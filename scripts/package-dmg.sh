#!/bin/bash
set -euo pipefail

QUIETLOCK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUIETLOCK_ROOT"

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--skip-build" ]; }; then
    printf 'Usage: bash scripts/package-dmg.sh [--skip-build]\n' >&2
    exit 2
fi

if [ "${1:-}" != "--skip-build" ]; then
    bash scripts/build.sh
fi

QUIETLOCK_APP="$QUIETLOCK_ROOT/.build/QuietLock.app"
QUIETLOCK_DMG_WORK="$QUIETLOCK_ROOT/.build/dmg"
QUIETLOCK_DMG_VENV="$QUIETLOCK_ROOT/.build/dmg-venv"
if [ ! -d "$QUIETLOCK_APP" ]; then
    printf 'Missing .build/QuietLock.app. Run bash scripts/build.sh first.\n' >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$QUIETLOCK_APP"
QUIETLOCK_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$QUIETLOCK_APP/Contents/Info.plist")
mkdir -p "$QUIETLOCK_DMG_WORK" dist

if [ ! -x "$QUIETLOCK_DMG_VENV/bin/python" ]; then
    python3 -m venv "$QUIETLOCK_DMG_VENV"
fi
# Install only in the project's build directory; the app has no Python dependency.
if ! "$QUIETLOCK_DMG_VENV/bin/python" -c '
from importlib.metadata import version
assert version("dmgbuild") == "1.6.7"
assert version("ds-store") == "1.3.3"
assert version("mac-alias") == "2.2.3"
' >/dev/null 2>&1; then
    "$QUIETLOCK_DMG_VENV/bin/python" -m pip --disable-pip-version-check install \
        --no-cache-dir -r Tools/dmg-requirements.txt
fi

printf 'Rendering Retina installer artwork…\n'
CLANG_MODULE_CACHE_PATH="$QUIETLOCK_ROOT/.build/clang-cache" \
xcrun swiftc -parse-as-library -module-cache-path "$QUIETLOCK_ROOT/.build/swift-cache" \
    QuietLock/BrandMark.swift QuietLock/VisualEffectView.swift Tools/GenerateDMGArtwork.swift \
    -o "$QUIETLOCK_DMG_WORK/GenerateArtwork"
"$QUIETLOCK_DMG_WORK/GenerateArtwork" "$QUIETLOCK_DMG_WORK" "$QUIETLOCK_VERSION"

printf 'Creating drag-to-install disk image…\n'
"$QUIETLOCK_DMG_VENV/bin/dmgbuild" \
    -s Tools/dmg-settings.py \
    -D "app=$QUIETLOCK_APP" \
    -D "icon=$QUIETLOCK_ROOT/QuietLock/AppIcon.icns" \
    -D "background=$QUIETLOCK_DMG_WORK/background.tiff" \
    'QuietLock' "$QUIETLOCK_DMG_WORK/QuietLock.dmg"

/usr/bin/hdiutil verify "$QUIETLOCK_DMG_WORK/QuietLock.dmg"
/bin/mv -f "$QUIETLOCK_DMG_WORK/QuietLock.dmg" "$QUIETLOCK_ROOT/dist/QuietLock.dmg"
(cd dist && /usr/bin/shasum -a 256 QuietLock.dmg > QuietLock.dmg.sha256)
printf '\nInstaller: %s/dist/QuietLock.dmg\nChecksum: %s/dist/QuietLock.dmg.sha256\n' \
    "$QUIETLOCK_ROOT" "$QUIETLOCK_ROOT"
