#!/bin/bash
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <app-bundle> <output-dmg> <volume-name> [bundle-name]" >&2
    exit 64
fi

APP_BUNDLE_PATH="$1"
DMG_PATH="$2"
VOLUME_NAME="$3"
BUNDLE_NAME="${4:-$(basename "$APP_BUNDLE_PATH")}"
MAX_HDIUTIL_ATTEMPTS=5

if [ ! -d "$APP_BUNDLE_PATH" ]; then
    echo "❌ App bundle not found: $APP_BUNDLE_PATH" >&2
    exit 66
fi

DMG_ROOT=""
DMG_OUTPUT_ROOT=""
HDIUTIL_LOG=""

cleanup() {
    [ -z "$DMG_ROOT" ] || rm -rf "$DMG_ROOT"
    [ -z "$DMG_OUTPUT_ROOT" ] || rm -rf "$DMG_OUTPUT_ROOT"
    [ -z "$HDIUTIL_LOG" ] || rm -f "$HDIUTIL_LOG"
}
trap cleanup EXIT

DMG_DIRECTORY="$(dirname "$DMG_PATH")"
mkdir -p "$DMG_DIRECTORY"
DMG_ROOT="$(mktemp -d)"
DMG_OUTPUT_ROOT="$(mktemp -d "$DMG_DIRECTORY/.whisperkiller-dmg.XXXXXX")"
HDIUTIL_LOG="$(mktemp -t whisperkiller-hdiutil)"
DMG_CANDIDATE="$DMG_OUTPUT_ROOT/$(basename "$DMG_PATH")"

ditto --norsrc --noextattr "$APP_BUNDLE_PATH" "$DMG_ROOT/$BUNDLE_NAME"
dot_clean -m "$DMG_ROOT/$BUNDLE_NAME" 2>/dev/null || true
find "$DMG_ROOT/$BUNDLE_NAME" -name '._*' -delete
find "$DMG_ROOT/$BUNDLE_NAME" -print0 | xargs -0 xattr -c 2>/dev/null || true
ln -s /Applications "$DMG_ROOT/Applications"

attempt=1
while true; do
    rm -f "$DMG_CANDIDATE"
    if hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$DMG_ROOT" \
        -ov \
        -format UDZO \
        "$DMG_CANDIDATE" >"$HDIUTIL_LOG" 2>&1; then
        cat "$HDIUTIL_LOG"
        break
    else
        exit_code=$?
    fi

    cat "$HDIUTIL_LOG" >&2
    if ! grep -q "Resource busy" "$HDIUTIL_LOG" || [ "$attempt" -ge "$MAX_HDIUTIL_ATTEMPTS" ]; then
        exit "$exit_code"
    fi

    retry_delay=$((2 ** attempt))
    echo "⚠️  hdiutil is busy; retrying in ${retry_delay}s (${attempt}/${MAX_HDIUTIL_ATTEMPTS})..." >&2
    sleep "$retry_delay"
    attempt=$((attempt + 1))
done

hdiutil verify "$DMG_CANDIDATE"
mv -f "$DMG_CANDIDATE" "$DMG_PATH"
echo "✅ DMG created: $DMG_PATH"
