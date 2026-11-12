#!/bin/bash
# Keep the build number increasing across Sparkle releases.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_CONFIG="$PROJECT_ROOT/Config/Version.xcconfig"
VERSION_FILE="$PROJECT_ROOT/VERSION"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf '%s\n' \
        "Usage: $0 <version> [build_number]" \
        "       $0 --build-only | --show | --check" \
        "Build numbers increase across releases, including when the version changes."
}

valid_version() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

valid_build() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 1
fi
if [ "$#" -eq 1 ] && [ "$1" = "--help" ]; then
    usage
    exit 0
fi

[ -f "$VERSION_CONFIG" ] || fail "Missing $VERSION_CONFIG"
[ -f "$VERSION_FILE" ] || fail "Missing $VERSION_FILE"
CURRENT_VERSION=$(awk -F '=' '/^MARKETING_VERSION[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2}' "$VERSION_CONFIG")
CURRENT_BUILD=$(awk -F '=' '/^CURRENT_PROJECT_VERSION[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2}' "$VERSION_CONFIG")
valid_version "$CURRENT_VERSION" || fail "Invalid marketing version in Version.xcconfig"
valid_build "$CURRENT_BUILD" || fail "Invalid build number in Version.xcconfig"
[ "$(cat "$VERSION_FILE")" = "$CURRENT_VERSION" ] || fail "VERSION and Version.xcconfig must match"

case "$1" in
    --check|--show)
        [ "$#" -eq 1 ] || fail "Unexpected arguments"
        if [ "$1" = "--show" ]; then
            printf 'Version: %s\nBuild: %s\n' "$CURRENT_VERSION" "$CURRENT_BUILD"
        fi
        exit 0
        ;;
    --build-only)
        [ "$#" -eq 1 ] || fail "Unexpected arguments"
        NEW_VERSION="$CURRENT_VERSION"
        NEW_BUILD=$((CURRENT_BUILD + 1))
        ;;
    *)
        [ "$#" -le 2 ] || fail "Expected a version and optional build number"
        NEW_VERSION="$1"
        valid_version "$NEW_VERSION" || fail "Version must be X.Y.Z (e.g. 0.2.0)"
        if [ "$#" -eq 2 ]; then
            NEW_BUILD="$2"
        else
            NEW_BUILD=$((CURRENT_BUILD + 1))
        fi
        ;;
esac
valid_build "$NEW_BUILD" || fail "Build number must be a positive integer"
[ "$NEW_BUILD" -gt "$CURRENT_BUILD" ] || fail "Build number must be greater than $CURRENT_BUILD"

CONFIG_TEMP=$(mktemp "$VERSION_CONFIG.XXXXXX")
VERSION_TEMP=""
trap 'rm -f "$CONFIG_TEMP" "$VERSION_TEMP"' EXIT
VERSION_TEMP=$(mktemp "$VERSION_FILE.XXXXXX")
sed -e "s/^MARKETING_VERSION[[:space:]]*=.*/MARKETING_VERSION = $NEW_VERSION/" \
    -e "s/^CURRENT_PROJECT_VERSION[[:space:]]*=.*/CURRENT_PROJECT_VERSION = $NEW_BUILD/" \
    "$VERSION_CONFIG" > "$CONFIG_TEMP"
printf '%s\n' "$NEW_VERSION" > "$VERSION_TEMP"
chmod 644 "$CONFIG_TEMP" "$VERSION_TEMP"
mv "$CONFIG_TEMP" "$VERSION_CONFIG"
mv "$VERSION_TEMP" "$VERSION_FILE"

printf 'Version updated: %s (%s) -> %s (%s)\n' \
    "$CURRENT_VERSION" "$CURRENT_BUILD" "$NEW_VERSION" "$NEW_BUILD"
