#!/bin/bash
# scripts/fix_icon_padding.sh

INPUT_ICON="WhisperFree Exports/WhisperFree-iOS-Default-1024x1024@1x.png"
OUTPUT_ICNS="Sources/WhisperFree/Resources/AppIcon.icns"
ICONSET="Sources/WhisperFree/Resources/AppIcon.iconset"

if [ ! -f "$INPUT_ICON" ]; then
    echo "Error: Input icon $INPUT_ICON not found."
    exit 1
fi

echo "Fixing icon padding using Swift CoreGraphics..."

mkdir -p "$ICONSET"

# Function to generate padded size
function generate_size() {
    local base_size=$1
    local scale=$2
    local name="icon_${base_size}x${base_size}${scale}.png"
    
    local actual_size=$base_size
    if [ "$scale" == "@2x" ]; then
        actual_size=$((base_size * 2))
    fi
    
    # Calculate 80% content size (approx 824px for 1024px canvas)
    local content_size=$(echo "$actual_size * 0.8" | bc | cut -d. -f1)
    
    # Use Swift script for transparency-safe padding
    swift scripts/pad_icon.swift "$INPUT_ICON" "$ICONSET/$name" "$content_size"
}

# Generate all standard sizes
generate_size 16 ""
generate_size 16 "@2x"
generate_size 32 ""
generate_size 32 "@2x"
generate_size 128 ""
generate_size 128 "@2x"
generate_size 256 ""
generate_size 256 "@2x"
generate_size 512 ""
generate_size 512 "@2x"

# Compile to .icns
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"

# Cleanup
rm -rf "$ICONSET"

echo "New professional AppIcon.icns created."
