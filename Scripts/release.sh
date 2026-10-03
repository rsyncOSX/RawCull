#!/bin/bash
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: ./Scripts/release.sh internal|appstore [--dry-run]

Archive, sign, and upload RawCull using the AppStore configuration.
internal: internal TestFlight testing only.
appstore: TestFlight and later App Store submission; does not submit for review.
--dry-run: print commands without building or uploading.

Sign in through Xcode Settings > Accounts, or set all three API credentials:
ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.
Optional BUILD_NUMBER overrides app and extension build numbers and disables
Xcode's automatic upload build-number management.
HELP
}
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
mode=${1:-}
case "$mode" in
    internal) internal_only=true ;;
    appstore) internal_only=false ;;
    *) usage >&2; exit 2 ;;
esac
shift
dry_run=false
if [[ ${1:-} == --dry-run ]]; then dry_run=true; shift; fi
if [[ $# -ne 0 ]]; then usage >&2; exit 2; fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
auth=(-allowProvisioningUpdates)
if [[ -n ${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-} ]]; then
    if [[ -z ${ASC_KEY_PATH:-} || -z ${ASC_KEY_ID:-} || -z ${ASC_ISSUER_ID:-} ]]; then
        echo 'Set all three: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID.' >&2
        exit 2
    fi
    if [[ ! -f "$ASC_KEY_PATH" ]]; then
        echo 'ASC_KEY_PATH must point to an existing .p8 authentication key.' >&2
        exit 2
    fi
    auth+=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
archive_args=("${auth[@]}")
manage_build=true
if [[ -n ${BUILD_NUMBER:-} ]]; then
    if [[ ! $BUILD_NUMBER =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        echo 'BUILD_NUMBER must contain one to three numeric components.' >&2
        exit 2
    fi
    archive_args+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
    manage_build=false
fi
# Preserve each archive and export diagnostics, including failed uploads.
run_dir="$root/build/releases/$mode-$(date -u +%Y%m%dT%H%M%SZ)-$$"
archive="$run_dir/RawCull.xcarchive"
options="$run_dir/ExportOptions.plist"
run() {
    if "$dry_run"; then printf '%q ' "$@"; printf '\n'; else "$@"; fi
}
echo "Release mode: $mode (internal TestFlight only: $internal_only)"
echo "Archive and export diagnostics: $run_dir"
if "$dry_run"; then
    echo "Export options: method=app-store-connect destination=upload testFlightInternalTestingOnly=$internal_only manageAppVersionAndBuildNumber=$manage_build"
else
    mkdir -p "$run_dir"
    cp exportOptionsAppStore.plist "$options"
    /usr/libexec/PlistBuddy -c 'Add :destination string upload' "$options"
    /usr/libexec/PlistBuddy -c "Add :testFlightInternalTestingOnly bool $internal_only" "$options"
    /usr/libexec/PlistBuddy -c "Add :manageAppVersionAndBuildNumber bool $manage_build" "$options"
    plutil -lint "$options"
fi
run xcodebuild -project RawCull.xcodeproj -scheme RawCull \
    -configuration AppStore -destination 'generic/platform=macOS' \
    -onlyUsePackageVersionsFromResolvedFile -archivePath "$archive" \
    "${archive_args[@]}" archive
run xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$options" -exportPath "$run_dir/upload" "${auth[@]}"
if ! "$dry_run"; then
    echo 'Upload finished. Wait for Apple processing, then check App Store Connect.'
    echo 'Assign the build to an internal TestFlight group if automatic distribution is not enabled.'
fi
