#!/bin/bash
# Tags the version in QuietLock/Info.plist and pushes it; GitHub Actions then
# builds the DMG and publishes it as a release (.github/workflows/release.yml).
set -euo pipefail

QUIETLOCK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUIETLOCK_ROOT"

QUIETLOCK_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - QuietLock/Info.plist)
QUIETLOCK_TAG="v$QUIETLOCK_VERSION"

if [ "$(git branch --show-current)" != "main" ]; then
    printf 'Release from the main branch.\n' >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    printf 'Commit or stash changes before releasing.\n' >&2
    exit 1
fi
# A tag that exists only on the remote is caught by the push below, which keeps this to one SSH connection.
if git rev-parse -q --verify "refs/tags/$QUIETLOCK_TAG" >/dev/null; then
    printf '%s already exists. Bump CFBundleShortVersionString in QuietLock/Info.plist first.\n' "$QUIETLOCK_TAG" >&2
    exit 1
fi

# Fail fast locally instead of waiting for CI.
bash scripts/test.sh

git tag -a "$QUIETLOCK_TAG" -m "静锁 QuietLock $QUIETLOCK_TAG"
# One atomic push: main and the tag land together or not at all.
if ! git push --atomic origin main "refs/tags/$QUIETLOCK_TAG"; then
    git tag -d "$QUIETLOCK_TAG" >/dev/null
    printf 'Push failed; removed local %s so the release can be retried.\n' "$QUIETLOCK_TAG" >&2
    exit 1
fi

QUIETLOCK_REPO=$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')
printf '\nPushed %s. Build progress: https://github.com/%s/actions\n' "$QUIETLOCK_TAG" "$QUIETLOCK_REPO"
printf 'Download when finished: https://github.com/%s/releases/latest/download/QuietLock.dmg\n' "$QUIETLOCK_REPO"
