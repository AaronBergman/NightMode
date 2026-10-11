#!/bin/bash
# Builds, signs, notarizes and staples dist/NightMode.dmg (version in the volume name and the app).
#
# Needs a "Developer ID Application" certificate and notarization credentials, one of:
#   NOTARY_PROFILE=<keychain profile made with `xcrun notarytool store-credentials`>
#   NOTARY_APPLE_ID + NOTARY_TEAM_ID + NOTARY_PASSWORD (an app-specific password)
#   NOTARY_CREDS_FILE=<file containing: --apple-id "..." --team-id "..." --password "...">
# Without credentials it still produces a signed (not notarized) DMG and says so.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="dist"
STAGE="build/dmg"
DMG="$DIST/NightMode.dmg"   # stable name, so releases/latest/download/NightMode.dmg always works

remove() {
    if command -v trash >/dev/null 2>&1; then trash "$@"; else rm -rf "$@"; fi
}

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity found."; exit 1; }
export SIGN_IDENTITY="$IDENTITY"

notary_args=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    notary_args=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
elif [ -n "${NOTARY_CREDS_FILE:-}" ] && [ -f "$NOTARY_CREDS_FILE" ]; then
    aid=$(grep -oE -- '--apple-id "[^"]+"' "$NOTARY_CREDS_FILE" | cut -d'"' -f2)
    tid=$(grep -oE -- '--team-id "[^"]+"' "$NOTARY_CREDS_FILE" | cut -d'"' -f2)
    pw=$(grep -oE -- '--password "[^"]+"' "$NOTARY_CREDS_FILE" | cut -d'"' -f2)
    notary_args=(--apple-id "$aid" --team-id "$tid" --password "$pw")
fi

notarize() {
    # $1: file to submit. Prints only notarytool's own output (never the credentials).
    xcrun notarytool submit "$1" "${notary_args[@]}" --wait --timeout 30m
}

scripts/build.sh

NOTARIZED=0
if [ ${#notary_args[@]} -gt 0 ]; then
    echo "==> Notarizing the app"
    mkdir -p build
    [ -e build/NightMode-notarize.zip ] && remove build/NightMode-notarize.zip
    ditto -c -k --keepParent build/NightMode.app build/NightMode-notarize.zip
    notarize build/NightMode-notarize.zip > build/notary-app.log 2>&1 || true
    cat build/notary-app.log
    if grep -q "status: Accepted" build/notary-app.log; then
        xcrun stapler staple build/NightMode.app
        NOTARIZED=1
    else
        echo "   App notarization was not accepted; see build/notary-app.log."
    fi
else
    echo "==> No notarization credentials: the DMG will be signed but not notarized."
fi

echo "==> Building $DMG"
[ -e "$STAGE" ] && remove "$STAGE"
mkdir -p "$STAGE" "$DIST"
ditto build/NightMode.app "$STAGE/NightMode.app"
ln -s /Applications "$STAGE/Applications"
[ -e "$DMG" ] && remove "$DMG"
hdiutil create -volname "NightMode $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$NOTARIZED" = "1" ]; then
    echo "==> Notarizing the DMG"
    notarize "$DMG" > build/notary-dmg.log 2>&1 || true
    cat build/notary-dmg.log
    if grep -q "status: Accepted" build/notary-dmg.log; then
        xcrun stapler staple "$DMG"
    else
        echo "   DMG notarization was not accepted; see build/notary-dmg.log."
        NOTARIZED=0
    fi
fi

echo "==> Verifying"
spctl -a -t open --context context:primary-signature -v "$DMG" || true
xcrun stapler validate "$DMG" || true
( cd "$DIST" && shasum -a 256 "NightMode.dmg" > "NightMode.dmg.sha256" )
cat "$DIST/NightMode.dmg.sha256"
if [ "$NOTARIZED" = "1" ]; then echo "Done: signed, notarized and stapled."; else echo "Done: signed but NOT notarized."; fi
