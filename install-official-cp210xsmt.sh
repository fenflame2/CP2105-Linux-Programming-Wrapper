#!/usr/bin/env bash

set -euo pipefail

EXPECTED_SDK_ARCHIVE_SHA256="b37661c5b1cd6c6e7751443ea0aa2bf4b410e4f6f5e063ca7554b4083cab6c76"
EXPECTED_SMT_SHA256="d9f002fb1b890e294fc23ac4e7ce4fc2965fc7f2411ca315fcbf68a69fc6d745"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
VENDOR_DIR="$SCRIPT_DIR/vendor"
DESTINATION="$VENDOR_DIR/cp210xsmt"
TEMP_DIR=""

usage() {
    cat <<'EOF'
Usage:
  ./install-official-cp210xsmt.sh SDK_ARCHIVE_OR_SEARCH_ROOT

The argument may be either:

1. The official Silicon Labs USBXpressHostSDK-6.7.7-Linux.tar.gz archive; or
2. A directory containing the extracted official SDK 6.7.7 Linux files.

For an archive, the script first verifies the complete official archive SHA-256.
It then searches for the audited x86_64 cp210xsmt binary, verifies the binary
SHA-256, and installs it into this wrapper's vendor directory.

The Silicon Labs SDK and binary are not redistributed by this wrapper.
No CP2105 device is opened and no USB I/O is performed.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

for required in awk chmod cp find grep ldd mkdir mktemp readlink rm sha256sum tar; do
    require_command "$required"
done

SOURCE="$1"
SEARCH_ROOT=""

if [[ -f "$SOURCE" ]]; then
    archive_hash="$(sha256sum -- "$SOURCE" | awk '{print $1}')"
    if [[ "$archive_hash" != "$EXPECTED_SDK_ARCHIVE_SHA256" ]]; then
        fail "Official SDK archive SHA-256 mismatch. Expected $EXPECTED_SDK_ARCHIVE_SHA256; found $archive_hash."
    fi
    printf 'Verified official Silicon Labs SDK archive SHA-256:\n'
    printf '  %s\n' "$archive_hash"

    tar -tzf "$SOURCE" >/dev/null || fail "The verified SDK archive could not be listed."
    TEMP_DIR="$(mktemp -d -t cp2105-sdk.XXXXXXXX)"
    [[ "$TEMP_DIR" == /tmp/cp2105-sdk.* ]] || fail "Unexpected temporary directory path."
    trap cleanup EXIT
    tar --no-same-owner -xzf "$SOURCE" -C "$TEMP_DIR"
    SEARCH_ROOT="$TEMP_DIR"
elif [[ -d "$SOURCE" ]]; then
    SEARCH_ROOT="$(cd -- "$SOURCE" && pwd -P)"
else
    fail "SDK archive or search directory does not exist: $SOURCE"
fi

mapfile -d '' -t CANDIDATES < <(find "$SEARCH_ROOT" -type f -name cp210xsmt -print0)

MATCHES=()
for candidate in "${CANDIDATES[@]}"; do
    candidate_hash="$(sha256sum -- "$candidate" | awk '{print $1}')"
    if [[ "$candidate_hash" == "$EXPECTED_SMT_SHA256" ]]; then
        MATCHES+=("$candidate")
    fi
done

if [[ ${#MATCHES[@]} -eq 0 ]]; then
    fail "The audited SDK 6.7.7 x86_64 cp210xsmt binary was not found below: $SEARCH_ROOT"
fi

if [[ ${#MATCHES[@]} -ne 1 ]]; then
    printf 'Matching audited binaries found:\n' >&2
    printf '  %s\n' "${MATCHES[@]}" >&2
    fail "Expected exactly one matching x86_64 cp210xsmt binary."
fi

mkdir -p -- "$VENDOR_DIR"

if [[ -e "$DESTINATION" ]]; then
    existing_hash="$(sha256sum -- "$DESTINATION" | awk '{print $1}')"
    if [[ "$existing_hash" != "$EXPECTED_SMT_SHA256" ]]; then
        fail "Refusing to overwrite an unexpected existing file: $DESTINATION"
    fi
fi

source_binary="${MATCHES[0]}"
source_real="$(readlink -f -- "$source_binary")"
destination_real="$(readlink -f -- "$DESTINATION" 2>/dev/null || true)"
if [[ -z "$destination_real" || "$source_real" != "$destination_real" ]]; then
    cp -- "$source_binary" "$DESTINATION"
fi
chmod 0755 -- "$DESTINATION"

installed_hash="$(sha256sum -- "$DESTINATION" | awk '{print $1}')"
[[ "$installed_hash" == "$EXPECTED_SMT_SHA256" ]] || fail "Post-copy SHA-256 verification failed."

printf 'Installed audited Silicon Labs cp210xsmt:\n'
printf '  Target : %s\n' "$DESTINATION"
printf '  SHA-256: %s\n' "$installed_hash"

printf '\nDynamic dependency check:\n'
dependency_report="$(ldd "$DESTINATION" 2>&1)" || fail "ldd could not inspect cp210xsmt."
printf '%s\n' "$dependency_report"
if grep -q 'not found' <<<"$dependency_report"; then
    fail "One or more runtime dependencies are missing."
fi

printf '\nInstallation verification passed.\n'
printf 'No CP2105 device was opened and no USB I/O was performed.\n'
