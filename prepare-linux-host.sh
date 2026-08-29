#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-check}"

usage() {
    cat <<'EOF'
CP2105 Linux host preparation

Usage:
  ./prepare-linux-host.sh check
  sudo ./prepare-linux-host.sh install

Modes:
  check    Read-only check of the host architecture, required commands,
           runtime libraries, and ModemManager state.
  install  On Debian or Ubuntu x86_64, install the required distribution
           packages and stop/runtime-mask ModemManager for the current boot.

No mode opens a CP2105 device or invokes cp210xsmt.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

check_architecture() {
    local architecture
    architecture="$(uname -m)"
    [[ "$architecture" == "x86_64" ]] || fail \
        "This audited cp210xsmt release requires x86_64; found $architecture."
    printf 'PASS  Architecture: x86_64\n'
}

check_commands() {
    local command_name
    local missing=0
    local required_commands=(
        awk basename bash chmod date find fuser grep hostname ldd mkdir pgrep
        readlink sed sha256sum sort systemctl tar tee tr uname
    )

    for command_name in "${required_commands[@]}"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'FAIL  Missing command: %s\n' "$command_name" >&2
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || fail "One or more required commands are missing."
    printf 'PASS  Required host commands\n'
}

check_libraries() {
    command -v ldconfig >/dev/null 2>&1 || fail "Required command is missing: ldconfig"

    local library_name
    local missing=0
    local cache
    cache="$(ldconfig -p 2>/dev/null)" || fail "Could not read the dynamic-library cache."
    local required_libraries=(
        libcap.so.2
        libstdc++.so.6
        libudev.so.1
        libusb-1.0.so.0
        libuuid.so.1
    )

    for library_name in "${required_libraries[@]}"; do
        if ! grep -Fq "$library_name" <<<"$cache"; then
            printf 'FAIL  Missing runtime library: %s\n' "$library_name" >&2
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || fail "One or more cp210xsmt runtime libraries are missing."
    printf 'PASS  Required cp210xsmt runtime libraries\n'
}

check_systemd() {
    [[ -d /run/systemd/system ]] || fail \
        "systemd is not running as PID 1; this release requires a systemd host."
    printf 'PASS  systemd service manager is running\n'
}

check_modemmanager() {
    if systemctl is-active --quiet ModemManager.service; then
        fail "ModemManager is active. Run the install mode or stop it before CP2105 access."
    fi
    printf 'PASS  ModemManager is inactive or not installed\n'
}

check_no_smt_process() {
    local process_report
    if process_report="$(pgrep -a -x cp210xsmt 2>/dev/null)"; then
        printf '%s\n' "$process_report" >&2
        fail "An existing cp210xsmt process must be resolved before continuing."
    fi
    printf 'PASS  No existing cp210xsmt process\n'
}

run_checks() {
    printf 'CP2105 LINUX HOST CHECK\n'
    printf '=======================\n'
    check_architecture
    check_commands
    check_libraries
    check_systemd
    check_modemmanager
    check_no_smt_process
    printf '\nHOST CHECK PASSED.\n'
    printf 'No CP2105 device was opened and cp210xsmt was not invoked.\n'
}

install_packages() {
    [[ $EUID -eq 0 ]] || fail "Run install mode with sudo."
    [[ -r /etc/os-release ]] || fail "Cannot identify this Linux distribution."

    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}" in
        debian|ubuntu)
            ;;
        *)
            fail "Automatic package installation supports Debian and Ubuntu only; found ${ID:-unknown}."
            ;;
    esac

    command -v apt-get >/dev/null 2>&1 || fail "apt-get is unavailable."

    printf 'Installing required Debian/Ubuntu packages...\n'
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        coreutils \
        findutils \
        gawk \
        grep \
        gzip \
        hostname \
        libc-bin \
        libcap2 \
        libstdc++6 \
        libudev1 \
        libusb-1.0-0 \
        libuuid1 \
        psmisc \
        procps \
        sed \
        systemd \
        tar

    if systemctl cat ModemManager.service >/dev/null 2>&1; then
        printf 'Stopping and runtime-masking ModemManager for this boot...\n'
        systemctl stop ModemManager.service
        systemctl mask --runtime ModemManager.service
    else
        printf 'ModemManager is not installed; no service change is needed.\n'
    fi
}

case "$MODE" in
    check)
        [[ $EUID -ne 0 ]] || printf 'NOTICE: check mode does not require sudo.\n'
        run_checks
        ;;
    install)
        install_packages
        run_checks
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        fail "Unknown mode: $MODE"
        ;;
esac
