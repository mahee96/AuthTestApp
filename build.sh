#!/usr/bin/env bash

set -euo pipefail

# Default values
SCHEME="AuthTest"
CONFIGURATION="Release"
OUTPUT_IPA=""
ENTITLEMENTS="AuthTest/AuthTest-iOS.entitlements"
DO_CLEAN=false
DO_FAKESIGN=true
BUILD_DIR="build"
PLATFORM="ios"
SDK="iphoneos"

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -s, --scheme <name>          Xcode scheme to build (default: AuthTest)
  -c, --configuration <config> Build configuration: Debug or Release (default: Release)
  -o, --output <file.ipa>      Output IPA filename/path (default: AuthTest-<platform>.ipa)
  -p, --platform <platform>    Target platform: ios, tvos, visionos (default: ios)
  -e, --entitlements <path>    Path to entitlements file (default: AuthTest/AuthTest-iOS.entitlements)
      --clean                  Clean build artifacts before building
      --no-fakesign            Skip ad-hoc/fake-signing with entitlements
  -h, --help                   Display this help message

Examples:
  ./build.sh
  ./build.sh --platform tvos
  ./build.sh --platform visionos --clean --output AuthTest-visionos_v0.1.0.ipa
  ./build.sh --configuration Debug --output build/AuthTest-Debug.ipa
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--scheme)
            SCHEME="$2"
            shift 2
            ;;
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_IPA="$2"
            shift 2
            ;;
        -p|--platform)
            case "$2" in
                ios|iphoneos)
                    PLATFORM="ios"
                    SDK="iphoneos"
                    ;;
                tvos|appletvos)
                    PLATFORM="tvos"
                    SDK="appletvos"
                    ;;
                visionos|xros)
                    PLATFORM="visionos"
                    SDK="xros"
                    ;;
                *)
                    echo "Error: Unknown platform $2. Supported: ios, tvos, visionos" >&2
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        -e|--entitlements)
            ENTITLEMENTS="$2"
            shift 2
            ;;
        --clean)
            DO_CLEAN=true
            shift
            ;;
        --no-fakesign)
            DO_FAKESIGN=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
done

if [ -z "$OUTPUT_IPA" ]; then
    OUTPUT_IPA="AuthTest-${PLATFORM}.ipa"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ARCHIVE_PATH="$BUILD_DIR/$SCHEME-$PLATFORM.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"

if [ "$DO_CLEAN" = true ]; then
    echo "==> Cleaning previous build artifacts for $PLATFORM..."
    rm -rf "$ARCHIVE_PATH" Payload "$OUTPUT_IPA"
fi

mkdir -p "$BUILD_DIR"

echo "==> Archiving $SCHEME for $PLATFORM (SDK: $SDK, $CONFIGURATION)..."
if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild archive \
        -project "$SCHEME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -sdk "$SDK" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        AD_HOC_CODE_SIGNING_ALLOWED=YES | xcbeautify
else
    xcodebuild archive \
        -project "$SCHEME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -sdk "$SDK" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        AD_HOC_CODE_SIGNING_ALLOWED=YES
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Application bundle not found at $APP_PATH" >&2
    exit 1
fi

if [ "$DO_FAKESIGN" = true ]; then
    echo "==> Fake-signing binary with entitlements ($ENTITLEMENTS)..."
    if [ ! -f "$ENTITLEMENTS" ]; then
        echo "Warning: Entitlements file not found at $ENTITLEMENTS, skipping entitlements embedding."
    else
        if command -v ldid >/dev/null 2>&1; then
            echo "  Using ldid..."
            ldid -S"$ENTITLEMENTS" "$APP_PATH/$SCHEME"
        else
            echo "  Using codesign (ad-hoc)..."
            codesign -s - --force --entitlements "$ENTITLEMENTS" "$APP_PATH"
        fi
    fi
fi

echo "==> Packaging into $OUTPUT_IPA..."
rm -rf Payload
mkdir -p Payload
cp -R "$APP_PATH" Payload/

mkdir -p "$(dirname "$OUTPUT_IPA")"
rm -f "$OUTPUT_IPA"
zip -qr "$OUTPUT_IPA" Payload
rm -rf Payload

echo "==> Successfully created $OUTPUT_IPA ($(du -h "$OUTPUT_IPA" | cut -f1))"
