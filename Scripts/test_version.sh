#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/Config" "$TEST_ROOT/Scripts"
cp "$PROJECT_ROOT/Scripts/update_version.sh" "$TEST_ROOT/Scripts/"
UPDATE="$TEST_ROOT/Scripts/update_version.sh"

# The updater must resolve paths relative to itself, not the caller's directory.
cd /
printf '0.1.0\n' > "$TEST_ROOT/VERSION"
printf 'MARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = 1\n' > "$TEST_ROOT/Config/Version.xcconfig"

assert_version() {
    [ "$(cat "$TEST_ROOT/VERSION")" = "$1" ]
    grep -qx "MARKETING_VERSION = $1" "$TEST_ROOT/Config/Version.xcconfig"
    grep -qx "CURRENT_PROJECT_VERSION = $2" "$TEST_ROOT/Config/Version.xcconfig"
    "$UPDATE" --check
}

reject_without_changes() {
    cp "$TEST_ROOT/Config/Version.xcconfig" "$TEST_ROOT/config.before"
    cp "$TEST_ROOT/VERSION" "$TEST_ROOT/version.before"
    if "$UPDATE" "$@" > "$TEST_ROOT/rejection.log" 2>&1; then
        printf 'Expected rejection: %s\n' "$*" >&2
        exit 1
    fi
    cmp "$TEST_ROOT/config.before" "$TEST_ROOT/Config/Version.xcconfig"
    cmp "$TEST_ROOT/version.before" "$TEST_ROOT/VERSION"
}

assert_version 0.1.0 1
[ "$("$UPDATE" --show)" = "$(printf 'Version: 0.1.0\nBuild: 1')" ]
"$UPDATE" --build-only
assert_version 0.1.0 2
"$UPDATE" 0.2.0
assert_version 0.2.0 3
"$UPDATE" 0.2.0
assert_version 0.2.0 4
"$UPDATE" 0.2.0 42
assert_version 0.2.0 42
"$UPDATE" --build-only
assert_version 0.2.0 43

reject_without_changes
reject_without_changes 0.3
reject_without_changes 01.2.3
reject_without_changes 0.3.0-beta
reject_without_changes 0.3.0 43
reject_without_changes 0.3.0 42
reject_without_changes 0.3.0 0
reject_without_changes 0.3.0 -1
reject_without_changes 0.3.0 01
reject_without_changes 0.3.0 abc
reject_without_changes 0.3.0 1 extra
reject_without_changes --build-only extra
reject_without_changes --show extra
reject_without_changes '$(touch unexpected-file)'

printf '9.9.9\n' > "$TEST_ROOT/VERSION"
reject_without_changes --check
reject_without_changes --build-only
printf '0.2.0\n' > "$TEST_ROOT/VERSION"
printf 'MARKETING_VERSION = 0.2.0\nCURRENT_PROJECT_VERSION = invalid\n' > "$TEST_ROOT/Config/Version.xcconfig"
reject_without_changes --build-only
rm "$TEST_ROOT/VERSION"
if "$UPDATE" --check > "$TEST_ROOT/rejection.log" 2>&1; then
    echo "Missing VERSION must be rejected" >&2
    exit 1
fi

echo "Version tests passed."
