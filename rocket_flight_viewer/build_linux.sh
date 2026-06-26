#!/bin/bash
# Build Rocket Flight Viewer for Linux (x86_64 or ARM64).
# Run this script on the target platform (WSL2 Ubuntu for x64, Pi 4 for arm64).
#
# Usage:
#   ./build_linux.sh          # release build
#   ./build_linux.sh --clean  # wipe build/ first

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$1" = "--clean" ]; then
    echo "Cleaning build folder..."
    rm -rf "$PROJECT_DIR/build"
fi

# Flutter's cmake_install.cmake requires this directory to exist before the build.
mkdir -p "$PROJECT_DIR/build/native_assets/linux"

flutter build linux --release

# Determine output paths from host architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
        ZIP_SUFFIX="linux-x64"
        ;;
    aarch64)
        BUNDLE_DIR="$PROJECT_DIR/build/linux/arm64/release/bundle"
        ZIP_SUFFIX="linux-arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

VERSION=$(grep '^version:' "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//')
ZIP_NAME="RocketFlightViewer-v${VERSION}-${ZIP_SUFFIX}.zip"

cp "$PROJECT_DIR/LINUX-README.txt" "$BUNDLE_DIR/"

cd "$(dirname "$BUNDLE_DIR")"
zip -r "$PROJECT_DIR/$ZIP_NAME" bundle/

echo ""
echo "Output: $PROJECT_DIR/$ZIP_NAME"
