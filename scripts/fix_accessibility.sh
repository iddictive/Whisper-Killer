#!/bin/bash

# WhisperKiller TCC/Permissions Fix Script
# Move to project root
cd "$(dirname "$0")/.."

echo "🔍 Starting Permissions & Deployment Fix..."

APP_NAME="WhisperKiller"
BUNDLE_ID="com.whisperkiller.app"
DEST_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Helper for non-sudo operations with sudo fallbacks
safe_rm() {
    rm -rf "$1" 2>/dev/null || sudo rm -rf "$1"
}

safe_cp() {
    ditto --norsrc --noextattr "$1" "$2/$(basename "$1")" 2>/dev/null || sudo ditto --norsrc --noextattr "$1" "$2/$(basename "$1")"
}

safe_chown() {
    chown -R "$1" "$2" 2>/dev/null || sudo chown -R "$1" "$2"
}

safe_xattr() {
    dot_clean -m "$1" 2>/dev/null || true
    find "$1" -name '._*' -delete 2>/dev/null || true
    find "$1" -print0 | xargs -0 xattr -c 2>/dev/null || sudo find "$1" -print0 | xargs -0 xattr -c 2>/dev/null
}

safe_codesign() {
    local app_path="$1"
    local entitlements="Sources/WhisperFree/Resources/WhisperKiller.entitlements"

    if [ ! -f "$entitlements" ]; then
        return 0
    fi

    rm -rf "$app_path/Contents/_CodeSignature" 2>/dev/null || sudo rm -rf "$app_path/Contents/_CodeSignature"
    codesign --force --options runtime --deep --entitlements "$entitlements" --sign - "$app_path" >/dev/null 2>&1 || \
        sudo codesign --force --options runtime --deep --entitlements "$entitlements" --sign - "$app_path" >/dev/null 2>&1
}

unregister_app_bundle() {
    local app_path="$1"

    if [ -x "$LSREGISTER" ] && [ -d "$app_path" ]; then
        "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
    fi
}

register_app_bundle() {
    local app_path="$1"

    if [ -x "$LSREGISTER" ] && [ -d "$app_path" ]; then
        "$LSREGISTER" -f "$app_path" >/dev/null 2>&1 || true
    fi
}

# 1. Preserve TCC permissions during install/update.
# Do not reset current or legacy bundle IDs here; users may keep valid grants
# while testing migration builds side by side.
echo "🛡️ Preserving existing TCC permissions..."

# 2. Kill all existing instances
echo "🔪 Killing old processes..."
pkill -9 -x "WhisperKiller" 2>/dev/null
pkill -9 -x "WhisperFree" 2>/dev/null
pkill -9 -x "WhisperFlow" 2>/dev/null

# 3. Clean up /Applications
echo "🧹 Cleaning up /Applications folder..."
unregister_app_bundle "$DEST_DIR/WhisperKiller.app"
unregister_app_bundle "$DEST_DIR/WhisperFree.app"
unregister_app_bundle "$DEST_DIR/WhisperFlow.app"
safe_rm "$DEST_DIR/WhisperKiller.app"
safe_rm "$DEST_DIR/WhisperFree.app"
safe_rm "$DEST_DIR/WhisperFlow.app"

# 4. Migrate data from old containers if they exist
echo "🚚 Migrating data from old containers..."
OLD_CONTAINER_DIR="$HOME/Library/Containers/com.whisperfree.app/Data/Library/Application Support"
NEW_CONTAINER_DIR="$HOME/Library/Containers/com.whisperkiller.app/Data/Library/Application Support"

# Ensure new container structure exists (open might have created it, but let's be sure)
mkdir -p "$NEW_CONTAINER_DIR/WhisperKiller/Models"

# Move models from all possible old locations
MIGRATE_PATHS=(
    "$OLD_CONTAINER_DIR/WhisperKiller/Models"
    "$OLD_CONTAINER_DIR/WhisperFree/Models"
    "$HOME/Library/Application Support/WhisperFree/Models"
    "$HOME/Library/Application Support/superwhisper/Models"
)

for path in "${MIGRATE_PATHS[@]}"; do
    if [ -d "$path" ] && [ "$(ls -A "$path")" ]; then
        echo "  - Found models in "$path", moving to new container..."
        cp -n "$path"/*.bin "$NEW_CONTAINER_DIR/WhisperKiller/Models/" 2>/dev/null
    fi
done

# Migrate Preferences (UserDefaults)
OLD_PREFS="$HOME/Library/Containers/com.whisperfree.app/Data/Library/Preferences/com.whisperfree.app.plist"
NEW_PREFS_DIR="$HOME/Library/Containers/com.whisperkiller.app/Data/Library/Preferences"
if [ -f "$OLD_PREFS" ]; then
    echo "  - Migrating preferences..."
    mkdir -p "$NEW_PREFS_DIR"
    cp -n "$OLD_PREFS" "$NEW_PREFS_DIR/com.whisperkiller.app.plist" 2>/dev/null
fi

# 5. If we are running from a build, copy to /Applications
SOURCE_APP="./WhisperKiller.app"
if [ -d "$SOURCE_APP" ]; then
    echo "📦 Installing new version to $DEST_DIR..."
    safe_cp "$SOURCE_APP" "$DEST_DIR/"
    safe_chown "$(whoami):admin" "$DEST_DIR/$APP_NAME.app"
    safe_xattr "$DEST_DIR/$APP_NAME.app"
    safe_codesign "$DEST_DIR/$APP_NAME.app"
    register_app_bundle "$DEST_DIR/$APP_NAME.app"
    unregister_app_bundle "$SOURCE_APP"

    echo "🏃 Launching from /Applications..."
    open "$DEST_DIR/$APP_NAME.app"
else
    echo "⚠️  No built app found in current directory. Just resetting permissions."
fi

echo "✅ Done! Existing permissions for $BUNDLE_ID were preserved."
