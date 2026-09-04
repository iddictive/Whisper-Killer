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
PROFANITY_RESOURCE_DIR="Sources/WhisperFree/Resources/Profanity"
BUILD_PATH=".build/apple/Products/Release/$APP_NAME"
DIST_DIR="dist"

function resolve_signing_identity() {
    if [ -n "$WHISPERKILLER_CODESIGN_IDENTITY" ]; then
        echo "$WHISPERKILLER_CODESIGN_IDENTITY"
        return
    fi

    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null)"
    local identity
    identity="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
    if [ -z "$identity" ]; then
        identity="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' | head -n 1)"
    fi
    echo "$identity"
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
bash scripts/swift_build_with_progress.sh swift build -c release --arch arm64 --disable-keychain --disable-netrc

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
    if [ -d "$PROFANITY_RESOURCE_DIR" ]; then
        mkdir -p "$BUNDLE_NAME/Contents/Resources/Resources"
        ditto --norsrc --noextattr "$PROFANITY_RESOURCE_DIR" "$BUNDLE_NAME/Contents/Resources/Resources/Profanity"
    fi
    if [ -f "$ICON_FILE" ]; then
        cp "$ICON_FILE" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
    fi

    APP_BUNDLE_PATH="$BUNDLE_NAME"
    ENTITLEMENTS="Sources/WhisperFree/Resources/WhisperKiller.entitlements"
    echo "🔑 Signing $APP_BUNDLE_PATH with entitlements..."
    rm -rf "$APP_BUNDLE_PATH/Contents/_CodeSignature"
    dot_clean -m "$APP_BUNDLE_PATH" 2>/dev/null || true
    find "$APP_BUNDLE_PATH" -name '._*' -delete
    find "$APP_BUNDLE_PATH" -print0 | xargs -0 xattr -c 2>/dev/null || true
    SIGNING_IDENTITY=$(resolve_signing_identity)
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "✅ Using signing identity: $SIGNING_IDENTITY"
        SIGN_COMMAND=(codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE_PATH")
    else
        echo "⚠️  Stable code-signing identity not found. Falling back to ad-hoc signing."
        echo "⚠️  Ad-hoc signed builds may cause macOS to treat each install as a new app and ask for permissions again."
        SIGN_COMMAND=(codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "-" "$APP_BUNDLE_PATH")
    fi

    if ! "${SIGN_COMMAND[@]}"; then
        echo "⚠️  First signing pass failed after xattr cleanup. Retrying once..."
        rm -rf "$APP_BUNDLE_PATH/Contents/_CodeSignature"
        dot_clean -m "$APP_BUNDLE_PATH" 2>/dev/null || true
        find "$APP_BUNDLE_PATH" -name '._*' -delete
        find "$APP_BUNDLE_PATH" -print0 | xargs -0 xattr -c 2>/dev/null || true
        if ! "${SIGN_COMMAND[@]}"; then
            echo "⚠️  Repo-root signing still failed. Retrying from clean temp staging..."
            STAGE_ROOT="$(mktemp -d)"
            STAGED_BUNDLE="$STAGE_ROOT/$BUNDLE_NAME"
            ditto --norsrc --noextattr "$APP_BUNDLE_PATH" "$STAGED_BUNDLE"
            rm -rf "$STAGED_BUNDLE/Contents/_CodeSignature"
            dot_clean -m "$STAGED_BUNDLE" 2>/dev/null || true
            find "$STAGED_BUNDLE" -name '._*' -delete
            find "$STAGED_BUNDLE" -print0 | xargs -0 xattr -c 2>/dev/null || true
            if [ -n "$SIGNING_IDENTITY" ]; then
                codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$STAGED_BUNDLE"
            else
                codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "-" "$STAGED_BUNDLE"
            fi
            codesign --verify --deep --strict "$STAGED_BUNDLE"
            APP_BUNDLE_PATH="$STAGED_BUNDLE"
        fi
    fi

    dot_clean -m "$APP_BUNDLE_PATH" 2>/dev/null || true
    find "$APP_BUNDLE_PATH" -name '._*' -delete
    find "$APP_BUNDLE_PATH" -print0 | xargs -0 xattr -c 2>/dev/null || true
    codesign --verify --deep --strict "$APP_BUNDLE_PATH"

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
