#!/bin/bash
set -euo pipefail

# WhisperFree Application Packaging Constructor
# Assembles, verifies, and codesigns the WhisperKiller.app macOS application bundle.
# Shared by local deployment (scripts/deploy.command) and CI (.github/workflows/release.yml).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WhisperKiller"
OUTPUT_BUNDLE="$ROOT_DIR/$APP_NAME.app"
BINARY=""
SIGN_MODE="local"
SIGN_ID=""

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --output <path>    Destination .app bundle path (default: <root>/WhisperKiller.app)
  --binary <path>    Compiled WhisperKiller Mach-O executable
  --identity <id>    Local signing identity (default: auto-detected, Developer ID / Apple Development)
  --ad-hoc           CI ad-hoc signing mode (no entitlements, no hardened runtime)
  -h, --help         Show this help message
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            OUTPUT_BUNDLE="$2"
            shift 2
            ;;
        --binary)
            BINARY="$2"
            shift 2
            ;;
        --identity)
            if [ "$2" = "-" ]; then
                SIGN_MODE="ci"
            else
                SIGN_MODE="local"
                SIGN_ID="$2"
            fi
            shift 2
            ;;
        --ad-hoc)
            SIGN_MODE="ci"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ "$OUTPUT_BUNDLE" != /* ]]; then
    OUTPUT_BUNDLE="$(pwd)/$OUTPUT_BUNDLE"
fi

if [[ "$OUTPUT_BUNDLE" != *.app ]]; then
    echo "Error: Output path must end in .app: $OUTPUT_BUNDLE" >&2
    exit 1
fi

if [ -L "$OUTPUT_BUNDLE" ]; then
    echo "Error: Output path is a symlink: $OUTPUT_BUNDLE" >&2
    exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_BUNDLE")"
mkdir -p "$OUTPUT_DIR"

if [ -n "$BINARY" ] && [[ "$BINARY" != /* ]]; then
    BINARY="$(pwd)/$BINARY"
fi

if [ -z "$BINARY" ]; then
    BIN_DIR="$(cd "$ROOT_DIR" && swift build -c release --show-bin-path 2>/dev/null || true)"
    if [ -n "$BIN_DIR" ]; then
        BINARY="$BIN_DIR/$APP_NAME"
    fi
fi

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ] || [ ! -s "$BINARY" ]; then
    echo "Error: Executable binary not found: ${BINARY:-<unresolved>}" >&2
    exit 1
fi

FILE_TYPE="$(file -b "$BINARY" 2>/dev/null || true)"
if [[ ! "$FILE_TYPE" =~ "Mach-O" ]]; then
    echo "Error: Binary is not a Mach-O executable: $BINARY ($FILE_TYPE)" >&2
    exit 1
fi

RESOURCES_DIR="$ROOT_DIR/Sources/WhisperFree/Resources"
INFO_PLIST="$RESOURCES_DIR/Info.plist"
ENTITLEMENTS="$RESOURCES_DIR/WhisperKiller.entitlements"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
PROFANITY_DIR="$RESOURCES_DIR/Profanity"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

if [ ! -f "$INFO_PLIST" ]; then
    echo "Error: Info.plist not found: $INFO_PLIST" >&2
    exit 1
fi

EXPECTED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$EXPECTED_BUNDLE_ID" ]; then
    echo "Error: Canonical Info.plist lacks CFBundleIdentifier: $INFO_PLIST" >&2
    exit 1
fi

if [ -e "$OUTPUT_BUNDLE" ]; then
    if [ ! -d "$OUTPUT_BUNDLE" ]; then
        echo "Error: Existing destination is not a bundle directory: $OUTPUT_BUNDLE" >&2
        exit 1
    fi
    EXISTING_PLIST="$OUTPUT_BUNDLE/Contents/Info.plist"
    if [ ! -f "$EXISTING_PLIST" ]; then
        echo "Error: Existing destination lacks Contents/Info.plist: $OUTPUT_BUNDLE" >&2
        exit 1
    fi
    EXISTING_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$EXISTING_PLIST" 2>/dev/null || true)"
    if [ "$EXISTING_ID" != "$EXPECTED_BUNDLE_ID" ]; then
        echo "Error: Existing destination has mismatched bundle identifier: '$EXISTING_ID' (expected '$EXPECTED_BUNDLE_ID')" >&2
        exit 1
    fi
fi

STAGE_DIR="$(mktemp -d "$OUTPUT_DIR/.pkg-stage.XXXXXX")"
cleanup_stage() {
    rm -rf "$STAGE_DIR"
}
trap cleanup_stage EXIT

BUNDLE_BASENAME="$(basename "$OUTPUT_BUNDLE")"
STAGED_BUNDLE="$STAGE_DIR/$BUNDLE_BASENAME"
mkdir -p "$STAGED_BUNDLE/Contents/MacOS" "$STAGED_BUNDLE/Contents/Resources"

cp "$BINARY" "$STAGED_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$STAGED_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$INFO_PLIST" "$STAGED_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$STAGED_BUNDLE/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$STAGED_BUNDLE/Contents/Info.plist"

for lproj in "$RESOURCES_DIR"/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -R "$lproj" "$STAGED_BUNDLE/Contents/Resources/"
    fi
done

if [ -d "$PROFANITY_DIR" ]; then
    mkdir -p "$STAGED_BUNDLE/Contents/Resources/Resources"
    ditto --norsrc --noextattr "$PROFANITY_DIR" "$STAGED_BUNDLE/Contents/Resources/Resources/Profanity"
fi

if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$STAGED_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ -f "$CHANGELOG_FILE" ]; then
    cp "$CHANGELOG_FILE" "$STAGED_BUNDLE/Contents/Resources/CHANGELOG.md"
fi

python3 "$ROOT_DIR/scripts/release.py" verify-bundle --root "$ROOT_DIR" --bundle "$STAGED_BUNDLE"

clean_metadata() {
    local target="$1"
    dot_clean -m "$target" 2>/dev/null || true
    find "$target" -name '._*' -delete 2>/dev/null || true
    find "$target" -print0 2>/dev/null | xargs -0 xattr -c 2>/dev/null || true
}

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
    printf '%s\n' "${identity:--}"
}

clean_metadata "$STAGED_BUNDLE"

if [ "$SIGN_MODE" = "ci" ]; then
    codesign --force --deep --sign - "$STAGED_BUNDLE" || {
        clean_metadata "$STAGED_BUNDLE"
        codesign --force --deep --sign - "$STAGED_BUNDLE"
    }
else
    if [ -z "$SIGN_ID" ]; then
        SIGN_ID="$(resolve_signing_identity)"
    fi
    codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$STAGED_BUNDLE" || {
        clean_metadata "$STAGED_BUNDLE"
        codesign --force --options runtime --deep --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$STAGED_BUNDLE"
    }
fi

clean_metadata "$STAGED_BUNDLE"
codesign --verify --deep --strict "$STAGED_BUNDLE"

BACKUP_BUNDLE=""
if [ -e "$OUTPUT_BUNDLE" ]; then
    BACKUP_BUNDLE="$STAGE_DIR/.prev-$BUNDLE_BASENAME"
    if ! mv "$OUTPUT_BUNDLE" "$BACKUP_BUNDLE"; then
        echo "Error: Failed to move existing bundle to staging backup" >&2
        exit 1
    fi
fi

if ! mv "$STAGED_BUNDLE" "$OUTPUT_BUNDLE"; then
    echo "Error: Failed to promote staged bundle to $OUTPUT_BUNDLE" >&2
    if [ -n "$BACKUP_BUNDLE" ] && [ -e "$BACKUP_BUNDLE" ]; then
        mv "$BACKUP_BUNDLE" "$OUTPUT_BUNDLE" || true
    fi
    exit 1
fi

echo "Packaged and verified: $OUTPUT_BUNDLE"
