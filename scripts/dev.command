#!/bin/bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Sources/WhisperFree"
DEV_ROOT="$ROOT_DIR/.build/dev-runtime"
APP_BUNDLE="$DEV_ROOT/WhisperKiller Dev.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/WhisperKiller"
INFO_PLIST="$SOURCE_DIR/Resources/Info.plist"
ENTITLEMENTS="$SOURCE_DIR/Resources/WhisperKiller.entitlements"
ICON_FILE="$SOURCE_DIR/Resources/AppIcon.icns"
PROFANITY_DIR="$SOURCE_DIR/Resources/Profanity"
LOCK_DIR="$DEV_ROOT/.watcher"
POLL_INTERVAL="${WHISPERKILLER_DEV_POLL_INTERVAL:-0.5}"
APP_PID=""

source_fingerprint() {
    find "$ROOT_DIR/Package.swift" "$SOURCE_DIR" \
        -type f \
        ! -name '.DS_Store' \
        -exec stat -f '%m:%z:%N' {} + \
        | LC_ALL=C sort \
        | shasum -a 256 \
        | awk '{ print $1 }'
}

resolve_signing_identity() {
    if [ -n "${WHISPERKILLER_CODESIGN_IDENTITY:-}" ]; then
        printf '%s\n' "$WHISPERKILLER_CODESIGN_IDENTITY"
        return
    fi

    local identities identity
    identities="$(security find-identity -v -p codesigning 2>/dev/null)"
    identity="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' | head -n 1)"
    printf '%s\n' "$identity"
}

prepare_bundle() {
    local binary_path="$1"
    local signing_identity

    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    cp "$binary_path" "$APP_EXECUTABLE"
    chmod +x "$APP_EXECUTABLE"
    cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.whisperkiller.app.dev" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName WhisperKiller Dev" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName WhisperKiller Dev" "$APP_BUNDLE/Contents/Info.plist"

    if [ -d "$PROFANITY_DIR" ]; then
        mkdir -p "$APP_BUNDLE/Contents/Resources/Resources"
        rm -rf "$APP_BUNDLE/Contents/Resources/Resources/Profanity"
        ditto --norsrc --noextattr "$PROFANITY_DIR" "$APP_BUNDLE/Contents/Resources/Resources/Profanity"
    fi

    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    fi

    rm -rf "$APP_BUNDLE/Contents/_CodeSignature"
    dot_clean -m "$APP_BUNDLE" 2>/dev/null || true
    find "$APP_BUNDLE" -name '._*' -delete
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true

    signing_identity="$(resolve_signing_identity)"
    if [ -n "$signing_identity" ]; then
        codesign \
            --force \
            --options runtime \
            --deep \
            --entitlements "$ENTITLEMENTS" \
            --sign "$signing_identity" \
            "$APP_BUNDLE"
    else
        echo "⚠️  Apple Development identity not found; using stable-path ad-hoc signing."
        codesign \
            --force \
            --deep \
            --entitlements "$ENTITLEMENTS" \
            --sign - \
            "$APP_BUNDLE"
    fi

    codesign --verify --deep --strict "$APP_BUNDLE"
}

build_bundle() {
    local bin_dir binary_path

    echo ""
    echo "🔨 Building incremental debug app..."
    if ! (cd "$ROOT_DIR" && swift build -c debug --product WhisperKiller); then
        echo "❌ Build failed. The last working dev instance is still running."
        return 1
    fi

    if ! bin_dir="$(cd "$ROOT_DIR" && swift build -c debug --show-bin-path)"; then
        echo "❌ Could not resolve the SwiftPM debug output path."
        return 1
    fi

    binary_path="$bin_dir/WhisperKiller"
    if [ ! -x "$binary_path" ]; then
        echo "❌ Debug executable not found at $binary_path"
        return 1
    fi

    if ! prepare_bundle "$binary_path"; then
        echo "❌ Bundle preparation failed. The last working dev instance is still running."
        return 1
    fi
}

stop_dev_app() {
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true

        local attempt
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
            if ! kill -0 "$APP_PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done

        if kill -0 "$APP_PID" 2>/dev/null; then
            kill -9 "$APP_PID" 2>/dev/null || true
        fi
        wait "$APP_PID" 2>/dev/null || true
    fi
    APP_PID=""
}

launch_dev_app() {
    stop_dev_app
    echo "🚀 Launching $APP_BUNDLE"
    WHISPERKILLER_DEV=1 "$APP_EXECUTABLE" &
    APP_PID="$!"
    echo "✅ WhisperKiller Dev is running (PID $APP_PID)"
}

cleanup() {
    echo ""
    echo "🛑 Stopping WhisperKiller Dev..."
    stop_dev_app
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

request_exit() {
    exit 0
}

acquire_watcher_lock() {
    mkdir -p "$DEV_ROOT"

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        return
    fi

    local existing_pid=""
    if [ -f "$LOCK_DIR/pid" ]; then
        existing_pid="$(sed -n '1p' "$LOCK_DIR/pid")"
    fi

    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "❌ Dev watcher is already running (PID $existing_pid)."
        exit 1
    fi

    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "❌ Could not acquire dev watcher lock at $LOCK_DIR"
        exit 1
    fi
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

main() {
    local last_fingerprint current_fingerprint

    acquire_watcher_lock
    trap cleanup EXIT
    trap request_exit INT TERM

    echo "👀 Watching Package.swift and Sources/WhisperFree"
    echo "📦 Persistent dev bundle: $APP_BUNDLE"
    echo "⌨️  Press Ctrl+C to stop"

    last_fingerprint="$(source_fingerprint)"
    if build_bundle; then
        launch_dev_app
    fi

    while true; do
        sleep "$POLL_INTERVAL"
        current_fingerprint="$(source_fingerprint)"
        if [ "$current_fingerprint" = "$last_fingerprint" ]; then
            continue
        fi

        sleep 0.2
        last_fingerprint="$(source_fingerprint)"
        echo "♻️  Source change detected"
        if build_bundle; then
            launch_dev_app
        fi
    done
}

main "$@"
