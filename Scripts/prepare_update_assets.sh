#!/bin/bash
set -euo pipefail

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 3 ] || fail "Usage: $0 <notarized-dmg> <sparkle-bin-dir> <output-dir>"
DMG="$1"
SPARKLE_BIN="$2"
OUTPUT="$3"
ACCOUNT="com.nissy.KeyDuty"

[ -f "$DMG" ] || fail "Build and notarize the DMG first: $DMG"
xcrun stapler validate "$DMG"
codesign --verify --strict "$DMG"

mkdir -p "$OUTPUT"
WORK=$(mktemp -d "$OUTPUT/.update.XXXXXX")
MOUNT="$WORK/mount"
ASSETS="$WORK/assets"
MOUNTED=false
cleanup() {
    if $MOUNTED; then
        hdiutil detach "$MOUNT" >/dev/null || return
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir "$MOUNT" "$ASSETS"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
MOUNTED=true

APP="$MOUNT/KeyDuty.app"
PLIST="$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
plist_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$PLIST"
}

[ "$(plist_value CFBundleIdentifier)" = "$ACCOUNT" ] || fail "Unexpected app bundle identifier"
VERSION=$(plist_value CFBundleShortVersionString)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid release version: $VERSION"
FEED=$(plist_value SUFeedURL)
[[ "$FEED" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/latest/download/appcast\.xml$ ]] \
    || fail "The app must use a GitHub Releases appcast URL"
REPO="${FEED%/releases/latest/download/appcast.xml}"
PUBLIC_KEY=$(plist_value SUPublicEDKey)
[ "$(plist_value SURequireSignedFeed)" = "true" ] || fail "The app must require a signed feed"
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=false

TAG="v$VERSION"
DESTINATION="$OUTPUT/$TAG"
[ ! -e "$DESTINATION" ] || fail "Release assets already exist: $DESTINATION"
[ "$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)" = "$PUBLIC_KEY" ] \
    || fail "The Keychain signing key does not match the public key embedded in the app"

ASSET="$ASSETS/KeyDuty-$VERSION.dmg"
cp "$DMG" "$ASSET"
"$SPARKLE_BIN/generate_appcast" --account "$ACCOUNT" \
    --download-url-prefix "$REPO/releases/download/$TAG/" \
    --link "$REPO/releases/tag/$TAG" --full-release-notes-url "$REPO/releases" "$ASSETS"

APPCAST="$ASSETS/appcast.xml"
SIGNATURE=$(/usr/bin/xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$APPCAST")
[ -n "$SIGNATURE" ] || fail "Appcast does not contain a DMG signature"
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$ASSET" "$SIGNATURE"
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$APPCAST"

mv "$ASSETS" "$DESTINATION"
printf 'Attach %s/KeyDuty-%s.dmg and %s/appcast.xml to release %s.\n' \
    "$DESTINATION" "$VERSION" "$DESTINATION" "$TAG"
