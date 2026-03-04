#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════
#  Whisper Free — One-click installer
#  Устанавливает все зависимости, собирает и запускает
# ═══════════════════════════════════════════════════════

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

APP_NAME="WhisperFree"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/WhisperFree"
MODELS_DIR="$APP_SUPPORT_DIR/Models"
BUILD_DIR="$SCRIPT_DIR/.build/release"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🎙️  ${BOLD}Whisper Free Installer${NC}"
echo -e "${CYAN}  Voice-to-Text for macOS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# ─── Step 1: Check macOS version ──────────────────────────
echo -e "${BOLD}[1/7]${NC} Checking macOS version..."
MACOS_VERSION=$(sw_vers -productVersion)
MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
    echo -e "${RED}  ✗ macOS 14 (Sonoma) or later required. You have $MACOS_VERSION${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ macOS $MACOS_VERSION${NC}"

# ─── Step 2: Check/Install Xcode CLI Tools ────────────────
echo -e "${BOLD}[2/7]${NC} Checking Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    echo -e "${YELLOW}  ⟳ Installing Xcode CLI Tools (this may take a while)...${NC}"
    xcode-select --install
    echo -e "${YELLOW}  ⚠ Please complete the Xcode CLI Tools installation, then re-run this script.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Xcode CLI Tools installed${NC}"

# ─── Step 3: Check/Install Homebrew ───────────────────────
echo -e "${BOLD}[3/7]${NC} Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    echo -e "${YELLOW}  ⟳ Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to path for Apple Silicon
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
echo -e "${GREEN}  ✓ Homebrew installed${NC}"

# ─── Step 4: Install whisper-cpp (local engine) ──────────
echo -e "${BOLD}[4/7]${NC} Installing whisper-cpp (local transcription engine)..."
if command -v whisper-cpp &>/dev/null || [ -f "/opt/homebrew/bin/whisper-cpp" ] || [ -f "/usr/local/bin/whisper-cpp" ]; then
    echo -e "${GREEN}  ✓ whisper-cpp already installed${NC}"
else
    echo -e "${YELLOW}  ⟳ Installing whisper-cpp via Homebrew...${NC}"
    brew install whisper-cpp
    echo -e "${GREEN}  ✓ whisper-cpp installed${NC}"
fi

# ─── Step 5: Download default Whisper model ──────────────
echo -e "${BOLD}[5/7]${NC} Downloading Whisper model (Base, ~140MB)..."
mkdir -p "$MODELS_DIR"
MODEL_FILE="$MODELS_DIR/ggml-base.bin"
if [ -f "$MODEL_FILE" ]; then
    echo -e "${GREEN}  ✓ Model already downloaded${NC}"
else
    echo -e "${YELLOW}  ⟳ Downloading ggml-base.bin from HuggingFace...${NC}"
    curl -L --progress-bar \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
        -o "$MODEL_FILE"
    echo -e "${GREEN}  ✓ Model downloaded to $MODELS_DIR${NC}"
fi

# ─── Step 6: Build the app ────────────────────────────────
echo -e "${BOLD}[6/7]${NC} Building WhisperFree..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | grep -E "(Build complete|error:|warning:)" | head -10
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}  ✗ Build failed. Run 'swift build' for details.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Build successful${NC}"

# ─── Step 7: Create .app bundle ──────────────────────────
echo -e "${BOLD}[7/7]${NC} Creating WhisperFree.app bundle..."

APP_BUNDLE="$SCRIPT_DIR/WhisperFree.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/WhisperFree" "$MACOS_DIR/WhisperFree"

# Create Info.plist for the .app bundle
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WhisperFree</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisperfree.app</string>
    <key>CFBundleName</key>
    <string>WhisperFree</string>
    <key>CFBundleDisplayName</key>
    <string>Whisper Free</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whisper Free needs microphone access to record your voice for transcription.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo -e "${GREEN}  ✓ WhisperFree.app created${NC}"

# ─── Done! ─────────────────────────────────────────────────
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ Installation complete!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}To run:${NC}"
echo -e "    open ${APP_BUNDLE}"
echo -e "    ${YELLOW}# or:${NC} swift run WhisperFree"
echo ""
echo -e "  ${BOLD}First-time setup:${NC}"
echo -e "    1. Grant ${YELLOW}Accessibility${NC} permission when prompted"
echo -e "       (System Settings → Privacy & Security → Accessibility)"
echo -e "    2. Grant ${YELLOW}Microphone${NC} permission when prompted"
echo -e "    3. Enter your ${YELLOW}OpenAI API key${NC} in Settings → General"
echo -e "       (needed for Cloud engine & AI post-processing)"
echo ""
echo -e "  ${BOLD}Shortcuts:${NC}"
echo -e "    ⌥+Space  — Start/stop recording"
echo -e "    Esc      — Cancel recording"
echo ""
echo -e "  ${BOLD}Installed components:${NC}"
echo -e "    ${GREEN}✓${NC} whisper-cpp (local transcription, GPU/NPU)"
echo -e "    ${GREEN}✓${NC} ggml-base model (~140MB)"
echo -e "    ${GREEN}✓${NC} WhisperFree.app bundle"
echo ""

# Ask to launch
read -p "  Launch Whisper Free now? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo -e "  ${CYAN}⟳ Launching...${NC}"
    open "$APP_BUNDLE"
fi
