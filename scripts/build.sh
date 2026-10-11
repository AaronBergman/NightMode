#!/bin/bash
# Builds build/NightMode.app (universal: Apple Silicon + Intel).
#
#   scripts/build.sh                 # signs with your Developer ID if you have one, otherwise ad hoc
#   SIGN_IDENTITY=- scripts/build.sh # force ad hoc signing (fine for running on your own Mac)
#   ARCHS=arm64 scripts/build.sh     # Apple Silicon only (faster)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-arm64 x86_64}"
APP="build/NightMode.app"

remove() {
    # Prefer the recoverable Trash when available.
    if command -v trash >/dev/null 2>&1; then trash "$@"; else rm -rf "$@"; fi
}

arch_flags=()
for arch in $ARCHS; do arch_flags+=(--arch "$arch"); done

echo "==> Compiling NightMode $VERSION ($BUILD_NUMBER) for: $ARCHS"
swift build -c release "${arch_flags[@]}" --product NightMode
BIN_DIR="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

echo "==> Assembling $APP"
[ -e "$APP" ] && remove "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NightMode" "$APP/Contents/MacOS/NightMode"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
    [ -z "$SIGN_IDENTITY" ] && SIGN_IDENTITY="-"
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Signing ad hoc"
    codesign --force --sign - "$APP"
else
    echo "==> Signing with: $SIGN_IDENTITY (hardened runtime, secure timestamp)"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"
lipo -archs "$APP/Contents/MacOS/NightMode"
echo "==> Built $APP"
