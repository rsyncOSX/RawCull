#!/bin/bash
# Copies the app target's MARKETING_VERSION and CURRENT_PROJECT_VERSION from the
# Xcode project into README.md: the "Current project version" line, the release
# tag commands, and the DMG example. ReleaseMetadataTests checks these match.
# Usage: ./Scripts/SyncReadmeVersion.sh [--check]
#   --check: change nothing; exit 1 if README.md is out of date.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

check=false
if [[ ${1:-} == --check ]]; then check=true; fi

# Ask Xcode for the app scheme's settings: test targets have their own
# MARKETING_VERSION, so grepping project.pbxproj could pick the wrong one.
settings=$(xcodebuild -showBuildSettings -project RawCull.xcodeproj -scheme RawCull \
    -configuration Release 2>/dev/null)
version=$(awk '/^ +MARKETING_VERSION = / {print $3; exit}' <<<"$settings")
build=$(awk '/^ +CURRENT_PROJECT_VERSION = / {print $3; exit}' <<<"$settings")

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! $build =~ ^[0-9]+$ ]]; then
    echo "Could not read version ('$version') and build ('$build') from RawCull.xcodeproj" >&2
    exit 1
fi

updated=$(VERSION="$version" BUILD="$build" perl -pe '
    s/^Current project version: \*\*[^*]+\*\*\. Build \*\*[^*]+\*\*\./Current project version: **$ENV{VERSION}**. Build **$ENV{BUILD}**./;
    s/\bv[0-9]+\.[0-9]+\.[0-9]+\b/v$ENV{VERSION}/g;
    s/"RawCull [0-9]+\.[0-9]+\.[0-9]+"/"RawCull $ENV{VERSION}"/g;
    s/\bRawCull\.[0-9]+\.[0-9]+\.[0-9]+\.dmg\b/RawCull.$ENV{VERSION}.dmg/g;
' README.md)

if [[ $updated == "$(cat README.md)" ]]; then
    echo "README.md already shows version $version, build $build"
    exit 0
fi
if $check; then
    echo "README.md is out of date: run ./Scripts/SyncReadmeVersion.sh (version $version, build $build)" >&2
    exit 1
fi
printf '%s\n' "$updated" > README.md
echo "Updated README.md to version $version, build $build"
