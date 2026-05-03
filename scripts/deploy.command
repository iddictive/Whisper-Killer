#!/bin/bash
set -e

# Whisper Free Deploy Script
# Move to the project root (parent of scripts/)
cd "$(dirname "$0")/.."
echo "📂 Project root: $(pwd)"

APP_NAME="WhisperKiller"
BUNDLE_NAME="WhisperKiller.app"
INFO_PLIST="Sources/WhisperFree/Resources/Info.plist"
ICON_FILE="Sources/WhisperFree/Resources/AppIcon.icns"
BUILD_PATH=".build/apple/Products/Release/$APP_NAME"
DIST_DIR="dist"

function resolve_signing_identity() {
    if [ -n "$WHISPERKILLER_CODESIGN_IDENTITY" ]; then
        echo "$WHISPERKILLER_CODESIGN_IDENTITY"
        return
    fi

    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | head -n 1
}

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
bash scripts/swift_build_with_progress.sh swift build -c release --arch arm64

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"

    # 4. Packaging
    echo "🏗️ Packaging into $BUNDLE_NAME..."
    rm -rf "$BUNDLE_NAME"
    mkdir -p "$BUNDLE_NAME/Contents/MacOS"
    mkdir -p "$BUNDLE_NAME/Contents/Resources"

    # Copy binary - find it if path is different
    # Use -not -path to exclude dSYM files which often have the same name as the binary

    echo "🔍 Looking for binary: $APP_NAME in .build/..."

    # Try multiple common patterns
    ACTUAL_BINARY=$(find .build -name "$APP_NAME" -type f -not -path "*.dSYM*" 2>/dev/null | grep -i "/release/" | head -n 1)

    if [ -z "$ACTUAL_BINARY" ]; then
        # Last resort: find any executable with the name
        ACTUAL_BINARY=$(find .build -name "$APP_NAME" -type f -not -path "*.dSYM*" | head -n 1)
    fi

    if [ -z "$ACTUAL_BINARY" ]; then
        echo "❌ Binary not found in .build directory."
        echo "📁 Current .build content (first 20 files):"
        find .build -maxdepth 4 | head -n 20
        exit 1
    fi

    echo "📦 Found binary at: $ACTUAL_BINARY"
    cp "$ACTUAL_BINARY" "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
    chmod +x "$BUNDLE_NAME/Contents/MacOS/$APP_NAME"
    cp "$INFO_PLIST" "$BUNDLE_NAME/Contents/Info.plist"
    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
    fi

    ENTITLEMENTS="Sources/WhisperFree/Resources/WhisperKiller.entitlements"
    echo "🔑 Signing $BUNDLE_NAME with entitlements..."
    rm -rf "$BUNDLE_NAME/Contents/_CodeSignature"
    dot_clean -m "$BUNDLE_NAME" 2>/dev/null || true
    find "$BUNDLE_NAME" -name '._*' -delete
    find "$BUNDLE_NAME" -print0 | xargs -0 xattr -c 2>/dev/null || true
    SIGNING_IDENTITY=$(resolve_signing_identity)
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "✅ Using signing identity: $SIGNING_IDENTITY"
        SIGN_COMMAND=(codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$BUNDLE_NAME")
    else
        echo "⚠️  Developer ID Application identity not found. Falling back to ad-hoc signing."
        echo "⚠️  Ad-hoc signed builds may cause macOS to treat each install as a new app and ask for permissions again."
        SIGN_COMMAND=(codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "-" "$BUNDLE_NAME")
    fi

    if ! "${SIGN_COMMAND[@]}"; then
        echo "⚠️  First signing pass failed after xattr cleanup. Retrying once..."
        rm -rf "$BUNDLE_NAME/Contents/_CodeSignature"
        dot_clean -m "$BUNDLE_NAME" 2>/dev/null || true
        find "$BUNDLE_NAME" -name '._*' -delete
        find "$BUNDLE_NAME" -print0 | xargs -0 xattr -c 2>/dev/null || true
        "${SIGN_COMMAND[@]}"
    fi

    dot_clean -m "$BUNDLE_NAME" 2>/dev/null || true
    find "$BUNDLE_NAME" -name '._*' -delete
    find "$BUNDLE_NAME" -print0 | xargs -0 xattr -c 2>/dev/null || true
    codesign --verify --deep --strict "$BUNDLE_NAME"

    # 5. Build a classic drag-to-Applications DMG for releases
    echo "💿 Creating drag-to-Applications DMG..."
    mkdir -p "$DIST_DIR"
    DMG_ROOT="$(mktemp -d)"
    DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
    ditto --norsrc --noextattr "$BUNDLE_NAME" "$DMG_ROOT/$BUNDLE_NAME"
    dot_clean -m "$DMG_ROOT/$BUNDLE_NAME" 2>/dev/null || true
    find "$DMG_ROOT/$BUNDLE_NAME" -name '._*' -delete
    find "$DMG_ROOT/$BUNDLE_NAME" -print0 | xargs -0 xattr -c 2>/dev/null || true
    ln -s /Applications "$DMG_ROOT/Applications"
    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_ROOT" \
        -ov \
        -format UDZO \
        "$DMG_PATH"
    rm -rf "$DMG_ROOT"
    echo "✅ DMG created: $DMG_PATH"

    # 6. Fix Permissions & Relocate
    echo "🏗️ Relocating to /Applications and fixing permissions..."
    if [ -f "./scripts/fix_accessibility.sh" ]; then
        bash ./scripts/fix_accessibility.sh
    else
        echo "❌ scripts/fix_accessibility.sh not found!"
        exit 1
    fi

    echo "✨ $APP_NAME v$VERSION successfully installed to /Applications."
    exit 0
else
    echo "❌ Build failed."
    exit 1
fi
