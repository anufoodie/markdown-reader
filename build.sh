#!/bin/bash
set -e

APP_NAME="Markdown Reader"
BUNDLE_DIR="$APP_NAME.app"
EXEC_NAME="MarkdownReader"
MIN_OS="13.0"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Building $APP_NAME..."

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macos$MIN_OS"
else
    TARGET="x86_64-apple-macos$MIN_OS"
fi

# ── 1. Generate icon ──
if [ ! -f "AppIcon.icns" ] || [ "makeicon.swift" -nt "AppIcon.icns" ]; then
    echo "Generating app icon..."
    swift makeicon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    echo "Icon created: AppIcon.icns"
fi

# ── 2. Clean previous build ──
rm -rf "$BUNDLE_DIR" "$EXEC_NAME"

# ── 3. Compile ──
swiftc \
    -parse-as-library \
    -target "$TARGET" \
    -framework SwiftUI \
    -framework WebKit \
    -framework AppKit \
    -sdk "$(xcrun --show-sdk-path)" \
    -O \
    Sources/*.swift \
    -o "$EXEC_NAME"

echo "Compilation successful."

# ── 4. Assemble bundle ──
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$EXEC_NAME"  "$BUNDLE_DIR/Contents/MacOS/"
cp Info.plist    "$BUNDLE_DIR/Contents/"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$BUNDLE_DIR/Contents/Resources/"
fi

rm "$EXEC_NAME"

# ── 5. Register with Launch Services ──
echo "Registering with Launch Services..."
"$LSREGISTER" -f "$BUNDLE_DIR"

echo ""
echo "✅ Built: $BUNDLE_DIR"
echo "   Run with: open \"$BUNDLE_DIR\""
echo ""
echo "   To set as default .md handler system-wide:"
echo "   Right-click any .md file → Get Info → Open With → select"
echo "   'Markdown Reader' → click 'Change All'"
echo ""
