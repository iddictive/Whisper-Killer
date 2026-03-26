#!/bin/bash

# WhisperKiller Rapid Installer
# This script builds the latest code and performs a clean deploy with permission resets.

set -e

# Move to project root
cd "$(dirname "$0")"

echo "🚀 Starting Rapid Build & Install..."

# 1. Build
echo "🏗️  Building WhisperKiller (Release)..."
swift build -c release

# 2. Update the local .app bundle with the new binary
echo "📦 Updating app bundle..."
APP_BUNDLE="./WhisperKiller.app"
BINARY_SOURCE=".build/release/WhisperKiller"

if [ -d "$APP_BUNDLE" ]; then
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    cp "$BINARY_SOURCE" "$APP_BUNDLE/Contents/MacOS/WhisperKiller"
else
    echo "❌ Error: $APP_BUNDLE structure not found. Please ensure it exists."
    exit 1
fi

# 3. Run the deployment & fix script
# This script handles: killing old app, copying to /Applications, and resetting TCC
echo "🪄 Running deployment and permission fixes..."
chmod +x scripts/fix_accessibility.sh
./scripts/fix_accessibility.sh

echo "✨ Installation complete! Existing permissions were preserved for the current app bundle ID."
