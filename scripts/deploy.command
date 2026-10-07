#!/bin/bash
set -e

# Whisper Free Deploy Script
# Move to the project root (parent of scripts/)
cd "$(dirname "$0")/.."
echo "📂 Project root: $(pwd)"

APP_NAME="WhisperKiller"
BUNDLE_NAME="WhisperKiller.app"
INFO_PLIST="Sources/WhisperFree/Resources/Info.plist"
DIST_DIR="dist"


# 1. Versioning
source "scripts/version.sh"
VERSION="$(resolve_whisperkiller_version "$INFO_PLIST")"
echo "🔢 Version: $VERSION"

echo "🚀 Starting deployment v$VERSION..."

# 2. Kill existing process
echo "🔪 Cleaning up old instances..."
pkill -9 -x "WhisperKiller" || true
pkill -9 -x "WhisperFree" || true
rm -rf "WhisperFree.app"
sleep 1

# 3. Build release
echo "📦 Building release version $VERSION..."
bash scripts/swift_build_with_progress.sh swift build -c release --arch arm64 --disable-keychain --disable-netrc

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"

    # 4. Packaging
    echo "🏗️ Packaging into $BUNDLE_NAME..."
    bash scripts/package_app.sh --output "$BUNDLE_NAME"
    APP_BUNDLE_PATH="$BUNDLE_NAME"

    # 5. Build a classic drag-to-Applications DMG for releases
    echo "💿 Creating drag-to-Applications DMG..."
    mkdir -p "$DIST_DIR"
    DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
    bash scripts/create_dmg.sh "$APP_BUNDLE_PATH" "$DMG_PATH" "$APP_NAME" "$BUNDLE_NAME"

    # 6. Fix Permissions & Relocate
    echo "🏗️ Relocating to /Applications and fixing permissions..."
    if [ "$APP_BUNDLE_PATH" != "$BUNDLE_NAME" ]; then
        rm -rf "$BUNDLE_NAME"
        ditto --norsrc --noextattr "$APP_BUNDLE_PATH" "$BUNDLE_NAME"
        rm -rf "$(dirname "$APP_BUNDLE_PATH")"
    fi
    if [ -f "./scripts/fix_accessibility.sh" ]; then
        bash ./scripts/fix_accessibility.sh
    else
        echo "❌ scripts/fix_accessibility.sh not found!"
        exit 1
    fi
    rm -rf "$BUNDLE_NAME"

    echo "✨ $APP_NAME v$VERSION successfully installed to /Applications."
    exit 0
else
    echo "❌ Build failed."
    exit 1
fi
