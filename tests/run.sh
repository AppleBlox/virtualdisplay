#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
BUILD="$ROOT/.build"

ARCH=$(uname -m)
SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="${ARCH}-apple-macos11.0"
XCODE=$(xcode-select -p)
XCTEST_LIB="$XCODE/Platforms/MacOSX.platform/Developer/Library/Frameworks"
XCTEST_SWIFT="$XCODE/Platforms/MacOSX.platform/Developer/usr/lib"

mkdir -p "$BUILD"

SRC_FILES=(
    "$ROOT/src/Resolution.swift"
    "$ROOT/src/Diagnostics.swift"
    "$ROOT/src/App.swift"
)
TEST_FILES=(
    "$ROOT/tests/TestResolution.swift"
    "$ROOT/tests/TestDiagnostics.swift"
    "$ROOT/tests/TestDisplayManager.swift"
)

echo "=== Compiling tests ==="
swiftc \
    -target "$TARGET" \
    -sdk "$SDK" \
    -import-objc-header "$ROOT/src/Bridging-Header.h" \
    -framework Cocoa \
    -F "$XCTEST_LIB" \
    -I "$XCTEST_SWIFT" \
    -L "$XCTEST_SWIFT" \
    -framework XCTest \
    "${SRC_FILES[@]}" \
    "${TEST_FILES[@]}" \
    -Xlinker -rpath -Xlinker "$XCTEST_LIB" \
    -Xlinker -rpath -Xlinker "$XCTEST_SWIFT" \
    -o "$BUILD/tests"

echo "=== Running tests ==="
"$BUILD/tests"
