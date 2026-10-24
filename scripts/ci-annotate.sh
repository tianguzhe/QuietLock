#!/bin/bash
# Usage: bash scripts/ci-annotate.sh <title> <command> [args...]
# Runs the command; on failure, republishes its error lines as one GitHub error
# annotation, because annotations are readable without signing in and raw job logs are not.
set -uo pipefail

QUIETLOCK_TITLE="$1"
shift
QUIETLOCK_LOG=$(mktemp)
trap 'rm -f "$QUIETLOCK_LOG"' EXIT

"$@" 2>&1 | tee "$QUIETLOCK_LOG"
QUIETLOCK_STATUS=${PIPESTATUS[0]}
if [ "$QUIETLOCK_STATUS" -ne 0 ]; then
    QUIETLOCK_LINES=$(grep -E 'error:|failed|Fatal error|fatal error' "$QUIETLOCK_LOG" | tail -n 40)
    [ -n "$QUIETLOCK_LINES" ] || QUIETLOCK_LINES=$(tail -n 40 "$QUIETLOCK_LOG")
    # Workflow commands need %, CR and LF escaped to keep a multi-line message intact.
    QUIETLOCK_LINES=${QUIETLOCK_LINES//'%'/'%25'}
    QUIETLOCK_LINES=${QUIETLOCK_LINES//$'\r'/'%0D'}
    QUIETLOCK_LINES=${QUIETLOCK_LINES//$'\n'/'%0A'}
    printf '::error title=%s failed::%s\n' "$QUIETLOCK_TITLE" "$QUIETLOCK_LINES"
fi
exit "$QUIETLOCK_STATUS"
