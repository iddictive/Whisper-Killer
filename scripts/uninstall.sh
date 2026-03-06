#!/bin/bash

# Whisper Free Uninstaller (Clean Version)
# This script removes Whisper Free settings and data.

echo "⚠️  Whisper Free Uninstaller"
echo "---------------------------"

# 1. Kill the app
echo "🔪 Killing WhisperKiller..."
pkill -9 -x "WhisperKiller" || true
sleep 1

# 2. Reset UserDefaults
echo "🧹 Resetting Settings and History..."
defaults delete com.whisperkiller.app || true

# 3. Remove Application Support data
echo "📂 Removing local data (~/Library/Application Support/WhisperKiller)..."
rm -rf "$HOME/Library/Application Support/WhisperKiller"

# 4. Try removing the app bundles without sudo
echo "🗑️  Cleaning up app bundles..."
rm -rf "/Applications/WhisperKiller.app" 2>/dev/null || echo "ℹ️  Could not remove /Applications/WhisperKiller.app (permissions). Please remove it manually if needed."
rm -rf "WhisperKiller.app" 2>/dev/null

echo "✅ Local configuration and data cleared."
exit 0
