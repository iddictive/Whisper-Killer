#!/bin/bash
set -euo pipefail

# WhisperFree Shared Application Packaging Constructor
# Packages the compiled executable into a signed macOS application bundle (.app)
# Shared by local deploy (scripts/deploy.command) and CI (.github/workflows/release.yml).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WhisperKiller"
OUTPUT_BUNDLE=""
BINARY=""
BIN_DIR=""
IDENTITY="auto"
SKIP_VERIFY=0

usage() {
    cat <<EOFU
Usage: $0 [options]

Options:
  --output, --bundle <path>  Target .app bundle path (default: <root>/WhisperKiller.app)
  --binary <path>            Path to compiled executable (default: resolved via swift build)
  --bin-dir <path>           Directory containing <app-name> executable
  --app-name <name>          Executable/app name (default: WhisperKiller)
  --identity <id>            Signing identity, '-' for ad-hoc, or 'auto' (default: auto)
  --ad-hoc                   Sign ad-hoc ('-')
  --root <path>              Project root directory (default: parent of scripts/)
  --skip-verify              Skip contract verification via release.py verify-bundle
  -h, --help                 Show this help message
EOFU
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|--bundle)
            OUTPUT_BUNDLE="$2"
            shift 2
            ;;
        --binary)
            BINARY="$2"
            shift 2
            ;;
        --bin-dir)
            BIN_DIR="$2"
            shift 2
            ;;
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --identity)
            IDENTITY="$2"
            shift 2
            ;;
        --ad-hoc)
            IDENTITY="-"
            shift
            ;;
        --root)
            ROOT_DIR="$2"
            shift 2
            ;;
        --skip-verify)
            SKIP_VERIFY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "'L Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

if [ -z "$OUTPUT_BUNDLE" ]; then
    OUTPUT_BUNDLE="$ROOT_DIR/$APP_NAME.app"
elif [[ "$OUTPUT_BUNDLE" != /* ]]; then
    OUTPUT_BUNDLE="$(pwd)/$OUTPUT_BUNDLE"
fi

if [ -n "$BINARY" ] && [[ "$BINARY" != /* ]]; then
    BINARY="$(pwd)/$BINARY"
fi

if [ -z "$BINARY" ]; then
    if [ -n "$BIN_DIR" ]; then
        if [[ "$BIN_DIR" != /* ]]; then
            BIN_DIR="$(pwd)/$BIN_DIR"
        fi
        BINARY="$BIN_DIR/$APP_NAME"
    else
        echo "Ø=Ý Resolving SwiftPM release binary directory..."
        RESOLVED_BIN_DIR="$(cd "$ROOT_DIR" && swift build -c release --show-bin-path 2>/dev/null || true)"
        if [ -n "$RESOLVED_BIN_DIR" ]; then
            BINARY="$RESOLVED_BIN_DIR/$APP_NAME"
        fi
    fi
fi

if [ -z "$BINARY" ] || [ ! -e "$BINARY" ]; then
    echo "'L Executable binary not found: ${BINARY:-<unresolved>}" >&2
    echo "Build the release product first (e.g. swift build -c release) or specify --binary <path>" >&2
    exit 1
fi

if [ ! -f "$BINARY" ]; then
    echo "'L Binary path is not a regular file: $BINARY" >&2
    exit 1
fi

if [ ! -s "$BINARY" ]; then
    echo "'L Binary file is empty: $BINARY" >&2
    exit 1
fi

FILE_TYPE="$(file -b "$BINARY" 2>/dev/null || true)"
if [[ ! "$FILE_TYPE" =~ "Mach-O" ]]; then
    echo "'L Binary is not a Mach-O executable: $BINARY ($FILE_TYPE)" >&2
    exit 1
fi

echo "Ø=Üæ Using binary: $BINARY ($FILE_TYPE)"

RESOURCE_SRC="$ROOT_DIR/Sources/WhisperFree/Resources"
INFO_PLIST="$RESOURCE_SRC/Info.plist"
ENTITLEMENTS="$RESOURCE_SRC/WhisperKiller.entitlements"
ICON_FILE="$RESOURCE_SRC/AppIcon.icns"
PROFANITY_DIR="$RESOURCE_SRC/Profanity"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

if [ ! -f "$INFO_PLIST" ]; then
    echo "'L Info.plist not found: $INFO_PLIST" >&2
    exit 1
fi

resolve_signing_identity() {
    if [ -n "${WHISPERKILLER_CODESIGN_IDENTITY:-}" ]; then
        printf '%s\n' "$WHISPERKILLER_CODESIGN_IDENTITY"
        return
    fi

    local identities identity
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    identity="$(printf '%s\n' "$identities" | grep 'Developer ID Application:' | cut -d'"' -f2 | head -n 1)"
    if [ -z "$identity" ]; then
        identity="$(printf '%s\n' "$identities" | grep 'Apple Development:' | cut -d'"' -f2 | head -n 1)"
    fi
    if [ -z "$identity" ]; then
        identity="-"
    fi
    printf '%s\n' "$identity"
}

if [ "$IDENTITY" = "auto" ]; then
    SIGN_IDENTITY="$(resolve_signing_identity)"
elif [ "$IDENTITY" = "ad-hoc" ]; then
    SIGN_IDENTITY="-"
else
    SIGN_IDENTITY="$IDENTITY"
fi

BUNDLE_NAME="$(basename "$OUTPUT_BUNDLE")"
echo "Ø<ß×þ Constructing $BUNDLE_NAME at: $OUTPUT_BUNDLE"

rm -rf "$OUTPUT_BUNDLE"
mkdir -p "$OUTPUT_BUNDLE/Contents/MacOS"
mkdir -p "$OUTPUT_BUNDLE/Contents/Resources"

# 1. Copy binary and set executable permission
cp "$BINARY" "$OUTPUT_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$OUTPUT_BUNDLE/Contents/MacOS/$APP_NAME"

# 2. Copy and configure Info.plist
cp "$INFO_PLIST" "$OUTPUT_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$OUTPUT_BUNDLE/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$OUTPUT_BUNDLE/Contents/Info.plist"

# 3. Copy localization files (*.lproj)
for lproj in "$RESOURCE_SRC"/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -R "$lproj" "$OUTPUT_BUNDLE/Contents/Resources/"
    fi
done

# 4. Copy profanity resources
if [ -d "$PROFANITY_DIR" ]; then
    mkdir -p "$OUTPUT_BUNDLE/Contents/Resources/Resources"
    ditto --norsrc --noextattr "$PROFANITY_DIR" "$OUTPUT_BUNDLE/Contents/Resources/Resources/Profanity"
fi

# 5. Copy app icon
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$OUTPUT_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 6. Copy changelog
if [ -f "$CHANGELOG_FILE" ]; then
    cp "$CHANGELOG_FILE" "$OUTPUT_BUNDLE/Contents/Resources/CHANGELOG.md"
fi

# 7. Release contract verification
if [ "$SKIP_VERIFY" -eq 0 ] && [ -f "$ROOT_DIR/scripts/release.py" ]; then
    echo "Ø=Ý Verifying bundle metadata against release contract..."
    python3 "$ROOT_DIR/scripts/release.py" verify-bundle --root "$ROOT_DIR" --bundle "$OUTPUT_BUNDLE"
fi

# 8. Code signing
strip_code_signature() {
    local target="$1"
    rm -rf "$target/Contents/_CodeSignature"
}

clean_bundle_metadata() {
    local target="$1"
    dot_clean -m "$target" 2>/dev/null || true
    find "$target" -name '._*' -delete 2>/dev/null || true
    find "$target" -print0 2>/dev/null | xargs -0 xattr -c 2>/dev/null || true
}

cleanup_temp_dir() {
    local target="$1"
    if [ -x "/Users/md/.codex/bin/codex-delete-temp" ]; then
        /Users/md/.codex/bin/codex-delete-temp "$target"
    else
        rm -rf "$target"
    fi
}

echo "Ø=Ý Code signing $BUNDLE_NAME..."
strip_code_signature "$OUTPUT_BUNDLE"
clean_bundle_metadata "$OUTPUT_BUNDLE"

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "& þ  Using ad-hoc signing (-)..."
    SIGN_CMD=(codesign --force --deep)
    if [ -f "$ENTITLEMENTS" ]; then
        SIGN_CMD+=(--entitlements "$ENTITLEMENTS")
    fi
    SIGN_CMD+=(--sign "-" "$OUTPUT_BUNDLE")
else
    echo "' Using signing identity: $SIGN_IDENTITY"
    SIGN_CMD=(codesign --force --options runtime --deep)
    if [ -f "$ENTITLEMENTS" ]; then
        SIGN_CMD+=(--entitlements "$ENTITLEMENTS")
    fi
    SIGN_CMD+=(--sign "$SIGN_IDENTITY" "$OUTPUT_BUNDLE")
fi

if ! "${SIGN_CMD[@]}"; then
    echo "& þ  First signing pass failed. Retrying once after metadata cleanup..." >&2
    strip_code_signature "$OUTPUT_BUNDLE"
    clean_bundle_metadata "$OUTPUT_BUNDLE"
    if ! "${SIGN_CMD[@]}"; then
        echo "& þ  In-place signing failed. Retrying from clean temp staging..." >&2
        STAGE_ROOT="$(mktemp -d)"
        STAGED_BUNDLE="$STAGE_ROOT/$BUNDLE_NAME"
        ditto --norsrc --noextattr "$OUTPUT_BUNDLE" "$STAGED_BUNDLE"
        strip_code_signature "$STAGED_BUNDLE"
        clean_bundle_metadata "$STAGED_BUNDLE"
        STAGED_CMD=("${SIGN_CMD[@]}")
        STAGED_CMD[${#STAGED_CMD[@]}-1]="$STAGED_BUNDLE"
        "${STAGED_CMD[@]}"
        codesign --verify --deep --strict "$STAGED_BUNDLE"
        rm -rf "$OUTPUT_BUNDLE"
        ditto --norsrc --noextattr "$STAGED_BUNDLE" "$OUTPUT_BUNDLE"
        cleanup_temp_dir "$STAGE_ROOT"
    fi
fi

dot_clean -m "$OUTPUT_BUNDLE" 2>/dev/null || true
find "$OUTPUT_BUNDLE" -name '._*' -delete 2>/dev/null || true
find "$OUTPUT_BUNDLE" -print0 2>/dev/null | xargs -0 xattr -c 2>/dev/null || true
codesign --verify --deep --strict "$OUTPUT_BUNDLE"

echo "' App bundle successfully packaged and verified: $OUTPUT_BUNDLE"
