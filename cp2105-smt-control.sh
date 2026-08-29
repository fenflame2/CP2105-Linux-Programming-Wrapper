#!/usr/bin/env bash

set -euo pipefail

VERSION="v0.2a"
EXPECTED_VID="10c4"
EXPECTED_PID="ea70"
EXPECTED_SMT_SHA256="d9f002fb1b890e294fc23ac4e7ce4fc2965fc7f2411ca315fcbf68a69fc6d745"
EXPECTED_VIRGIN_CONFIG_SHA256="d40ac873b1a097a14c634a2764e1b3259c9ab7bfa9c3ed9429ffa4a757d21fc0"
EXPECTED_TARGET_CONFIG_SHA256="8ce174b5dad1af1d51e6c655b0207da1454e1314d3dc8605a18d498c9ae77991"
EXPECTED_ENVELOPE_SHA256="A5CF6A6FCFD97D2B99E97FEAE88B68FCAACA9A6F14BDAD346E1C732E170F7722"
EXPECTED_ENVELOPE="01 01 5F 5D F0 FE F0 FE 10 10 10 00"

EXPECTED_REFERENCE_CORRECTION_RECORD_SHA256="8db0d5602678b711318f2ad4a2bb3c1ef0ad70c784c00c3a872a9de7e1560722"
EXPECTED_V01C_MARKER_SHA256="c20512ddccd5fd54229d1e04f1855ea2612b8c12ef12d6b3a6827c111d031e12"
EXPECTED_V01C_PROGRAM_LOG_SHA256="4fbb235898a8cc69a96bfb73c86fba3333c5152c9356f2b9f8e007d98393fb1c"
EXPECTED_POST_CORRECTION_INSPECT_SHA256="4cad4cde7eedc15f00762e52084ece51961dcf52b4f26a396323503355068b6e"
EXPECTED_POST_CORRECTION_PREFLIGHT_SHA256="c7ccb31df0e62458f0b8df2fda4b952e6fa7103bad51b64772d07deef91287b2"

EXPECTED_V01D_README_SHA256="fc53dc595cceb2c777f6becaeaa6b42430cfd2fb2e991a6073834e8dd153197a"
EXPECTED_V01D_PROGRAM_LOG_SHA256="3d62a8f6b615c06347d773608d1a749c9b28a9d3cb72ccc856f76d42d56a7131"
EXPECTED_V01D_GDB_LOG_SHA256="a666012e1ecece5c327bc9bff9b718b58a964dd05f808a63fbdba7cfcc2072ac"
EXPECTED_V01D_MARKER_SHA256="73a77a16af5e527fb2a463454958fee013652c138c5f2fec9d05ebbd59cc46f7"
EXPECTED_V01D_WINDOWS_READBACK_SHA256="2cb8692053bacf88a18354956e54f2674be94ef2a5a99a8c0ad6367c61f23919"
EXPECTED_V01D_WINDOWS_SCREENSHOT_SHA256="1ab8f33a150953d0e7208a49895b01c033761428106f9bc01a248d8b5bc1f4c0"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SMT_BINARY="$SCRIPT_DIR/vendor/cp210xsmt"
VIRGIN_CONFIG="$SCRIPT_DIR/CP2105-virgin-baseline.cfg"
TARGET_CONFIG="$SCRIPT_DIR/CP2105-five-gpio-target.cfg"
LOG_DIR="$SCRIPT_DIR/logs"
STATE_DIR="$SCRIPT_DIR/state"
DEVICE_STATE_ROOT="$STATE_DIR/devices"

REFERENCE_CORRECTION_RECORD="$SCRIPT_DIR/evidence/reference-device-hardware-correction/J6-HARDWARE-CORRECTION-RECORD.txt"

V01C_EVIDENCE_DIR="$SCRIPT_DIR/evidence/v0.1c-failed-attempt"
V01C_MARKER="$V01C_EVIDENCE_DIR/state/OTP_ATTEMPT_CONSUMED_DO_NOT_RETRY"
V01C_PROGRAM_LOG="$V01C_EVIDENCE_DIR/logs/20260829T114759Z-program.log"
POST_CORRECTION_INSPECT_LOG="$V01C_EVIDENCE_DIR/logs/20260829T132919Z-inspect.log"
POST_CORRECTION_PREFLIGHT_LOG="$V01C_EVIDENCE_DIR/logs/20260829T132919Z-preflight.log"

V01D_EVIDENCE_DIR="$SCRIPT_DIR/evidence/v0.1d-hardware-proven-attempt"
V01D_README="$V01D_EVIDENCE_DIR/README-EVIDENCE.txt"
V01D_PROGRAM_LOG="$V01D_EVIDENCE_DIR/logs/20260829T134923Z-program.log"
V01D_GDB_LOG="$V01D_EVIDENCE_DIR/logs/20260829T135623Z-exact-readback-gdb.log"
V01D_MARKER="$V01D_EVIDENCE_DIR/state/OTP_ATTEMPT_V01D_CONSUMED_DO_NOT_RETRY"
V01D_WINDOWS_READBACK="$V01D_EVIDENCE_DIR/POST-POWER-CYCLE-WINDOWS-READBACK.txt"
V01D_WINDOWS_SCREENSHOT="$V01D_EVIDENCE_DIR/post-power-cycle-windows-readback.png"

usage() {
    cat <<EOF
CP2105 cp210xsmt controlled wrapper $VERSION

Usage:
  sudo ./cp2105-smt-control.sh inspect
  sudo ./cp2105-smt-control.sh list
  sudo ./cp2105-smt-control.sh preflight
  sudo ./cp2105-smt-control.sh verify-target
  sudo ./cp2105-smt-control.sh program
  sudo ./cp2105-smt-control.sh verify-programmed

Modes:
  inspect            Verify files, preserved evidence, dependencies, USB
                     identity, ModemManager state, open serial-port handles,
                     and absence of another cp210xsmt process. Does not invoke
                     cp210xsmt.
  list               Run the manufacturer's read-only --list operation.
  preflight          Run inspect, --list, and read-only verification of the
                     exact virgin CP2105 baseline.
  verify-target      Unconditional read-only verification of the exact target.
                     This is the recovery/forensic mode for an earlier attempt.
  program            Detect and cross-check the attached CP2105 serial, verify
                     the virgin baseline, consume that serial's v0.2a one-shot
                     marker, and invoke --set-config exactly once.
  verify-programmed  Rediscover the attached serial, require that same serial's
                     v0.2a consumed marker and explicit confirmation of complete
                     power removal/reconnection, then invoke only read-only
                     --verify-config against the exact target.

The irreversible and read-only phases are deliberately separate. A successful
program command means only that the manufacturer reported the write transaction
successful. It is NOT final verification. Fully remove CP2105 power, reconnect
the same physical device, and run verify-programmed. State is isolated by the
detected serial so multiple new CP2105 devices can be processed independently.
No verification path invokes a setter.
EOF
}

fail() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

lowercase_file_value() {
    tr '[:upper:]' '[:lower:]' < "$1" | tr -d '[:space:]'
}

verify_file_hash() {
    local path="$1"
    local expected="$2"
    local label="$3"
    local actual

    [[ -f "$path" ]] || fail "$label is missing: $path"
    actual="$(sha256sum -- "$path" | awk '{print $1}')"
    if [[ "${actual,,}" != "${expected,,}" ]]; then
        fail "$label SHA-256 mismatch. Expected $expected; found $actual. File: $path"
    fi
    printf 'VERIFIED %-44s %s\n' "$label" "${actual^^}"
}

verify_static_files() {
    require_command sha256sum
    require_command awk
    require_command grep
    require_command ldd

    verify_file_hash "$SMT_BINARY" "$EXPECTED_SMT_SHA256" "Silicon Labs cp210xsmt"
    [[ -x "$SMT_BINARY" ]] || fail "cp210xsmt is not executable: $SMT_BINARY"
    verify_file_hash "$VIRGIN_CONFIG" "$EXPECTED_VIRGIN_CONFIG_SHA256" "Virgin baseline config"
    verify_file_hash "$TARGET_CONFIG" "$EXPECTED_TARGET_CONFIG_SHA256" "Five-GPIO target config"
    verify_file_hash "$REFERENCE_CORRECTION_RECORD" "$EXPECTED_REFERENCE_CORRECTION_RECORD_SHA256" "Reference-device J6 correction record"
    verify_file_hash "$V01C_MARKER" "$EXPECTED_V01C_MARKER_SHA256" "Preserved v0.1c consumed marker"
    verify_file_hash "$V01C_PROGRAM_LOG" "$EXPECTED_V01C_PROGRAM_LOG_SHA256" "Preserved v0.1c program log"
    verify_file_hash "$POST_CORRECTION_INSPECT_LOG" "$EXPECTED_POST_CORRECTION_INSPECT_SHA256" "Post-correction inspect evidence"
    verify_file_hash "$POST_CORRECTION_PREFLIGHT_LOG" "$EXPECTED_POST_CORRECTION_PREFLIGHT_SHA256" "Post-correction preflight evidence"

    verify_file_hash "$V01D_README" "$EXPECTED_V01D_README_SHA256" "Preserved v0.1d evidence record"
    verify_file_hash "$V01D_PROGRAM_LOG" "$EXPECTED_V01D_PROGRAM_LOG_SHA256" "Preserved v0.1d program log"
    verify_file_hash "$V01D_GDB_LOG" "$EXPECTED_V01D_GDB_LOG_SHA256" "Preserved v0.1d exact-readback log"
    verify_file_hash "$V01D_MARKER" "$EXPECTED_V01D_MARKER_SHA256" "Preserved v0.1d consumed marker"
    verify_file_hash "$V01D_WINDOWS_READBACK" "$EXPECTED_V01D_WINDOWS_READBACK_SHA256" "Post-power-cycle readback record"
    verify_file_hash "$V01D_WINDOWS_SCREENSHOT" "$EXPECTED_V01D_WINDOWS_SCREENSHOT_SHA256" "Post-power-cycle readback screenshot"

    local envelope_hash
    envelope_hash="$(printf '\x01\x01\x5F\x5D\xF0\xFE\xF0\xFE\x10\x10\x10\x00' | sha256sum | awk '{print $1}')"
    if [[ "${envelope_hash^^}" != "$EXPECTED_ENVELOPE_SHA256" ]]; then
        fail "Internal programming-envelope hash check failed."
    fi
    printf 'VERIFIED %-44s %s\n' "Programming envelope" "${envelope_hash^^}"

    local dependency_report
    dependency_report="$(ldd "$SMT_BINARY" 2>&1)" || fail "ldd could not inspect cp210xsmt."
    if grep -q 'not found' <<<"$dependency_report"; then
        printf '%s\n' "$dependency_report" >&2
        fail "cp210xsmt has missing runtime dependencies."
    fi
    printf 'VERIFIED %-44s PASS\n' "Dynamic dependencies"
}

verify_no_live_smt_process() {
    require_command pgrep
    local process_report
    if process_report="$(pgrep -a -x cp210xsmt 2>/dev/null)"; then
        printf '%s\n' "$process_report" >&2
        fail "Another cp210xsmt process is already present. Resolve it before continuing."
    fi
    printf 'VERIFIED %-44s PASS\n' "No existing cp210xsmt process"
}

bind_device_state_paths() {
    [[ -n "${CURRENT_SERIAL:-}" ]] || fail "Cannot bind state without a detected serial number."

    SERIAL_STATE_KEY="$(printf '%s' "$CURRENT_SERIAL" | sha256sum | awk '{print $1}')"
    [[ "$SERIAL_STATE_KEY" =~ ^[0-9a-f]{64}$ ]] || fail "Could not derive a safe serial state key."

    DEVICE_STATE_DIR="$DEVICE_STATE_ROOT/$SERIAL_STATE_KEY"
    CONSUMED_MARKER="$DEVICE_STATE_DIR/OTP_ATTEMPT_V02A_CONSUMED_DO_NOT_RETRY"
    PROGRAM_SUCCESS_MARKER="$DEVICE_STATE_DIR/OTP_V02A_PROGRAM_REPORTED_SUCCESS_AWAITING_POWER_CYCLE_VERIFY"
    PROGRAM_AMBIGUOUS_MARKER="$DEVICE_STATE_DIR/OTP_V02A_PROGRAM_RESULT_AMBIGUOUS_READBACK_REQUIRED"
    VERIFIED_MARKER="$DEVICE_STATE_DIR/OTP_V02A_POWER_CYCLE_TARGET_VERIFIED"
}

find_exact_usb_device() {
    require_command readlink
    require_command sed
    require_command sort

    USB_MATCHES=()
    local device_dir vid pid serial
    for device_dir in /sys/bus/usb/devices/*; do
        [[ -f "$device_dir/idVendor" && -f "$device_dir/idProduct" ]] || continue
        vid="$(lowercase_file_value "$device_dir/idVendor")"
        pid="$(lowercase_file_value "$device_dir/idProduct")"
        if [[ "$vid" == "$EXPECTED_VID" && "$pid" == "$EXPECTED_PID" ]]; then
            USB_MATCHES+=("$device_dir")
        fi
    done

    if [[ ${#USB_MATCHES[@]} -ne 1 ]]; then
        fail "Expected exactly one USB ${EXPECTED_VID}:${EXPECTED_PID} device; found ${#USB_MATCHES[@]}."
    fi

    USB_DEVICE_DIR="${USB_MATCHES[0]}"
    [[ -f "$USB_DEVICE_DIR/serial" ]] || fail "The matching CP2105 has no readable USB serial number."
    serial="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' < "$USB_DEVICE_DIR/serial")"
    [[ -n "$serial" ]] || fail "The matching CP2105 has an empty USB serial number."
    [[ "$serial" != *$'\n'* ]] || fail "The matching CP2105 serial contains an unsupported newline."
    [[ ${#serial} -le 256 ]] || fail "The matching CP2105 serial exceeds 256 characters."
    CURRENT_SERIAL="$serial"
    bind_device_state_paths

    USB_BUS="unknown"
    USB_DEVICE_NUMBER="unknown"
    [[ -f "$USB_DEVICE_DIR/busnum" ]] && USB_BUS="$(tr -d '[:space:]' < "$USB_DEVICE_DIR/busnum")"
    [[ -f "$USB_DEVICE_DIR/devnum" ]] && USB_DEVICE_NUMBER="$(tr -d '[:space:]' < "$USB_DEVICE_DIR/devnum")"

    TTY_NODES=()
    local usb_device_real tty_class tty_real tty_node
    usb_device_real="$(readlink -f -- "$USB_DEVICE_DIR")"
    [[ -n "$usb_device_real" ]] || fail "Could not resolve the CP2105 sysfs device path."
    for tty_class in /sys/class/tty/ttyUSB*; do
        [[ -e "$tty_class" ]] || continue
        tty_real="$(readlink -f -- "$tty_class")"
        if [[ "$tty_real" == "$usb_device_real/"* ]]; then
            tty_node="/dev/$(basename -- "$tty_class")"
            [[ -e "$tty_node" ]] && TTY_NODES+=("$tty_node")
        fi
    done

    mapfile -t TTY_NODES < <(printf '%s\n' "${TTY_NODES[@]}" | sed '/^$/d' | sort -u)
    if [[ ${#TTY_NODES[@]} -ne 2 ]]; then
        fail "Expected two CP2105 ttyUSB interfaces; found ${#TTY_NODES[@]}."
    fi
}

verify_modemmanager_inactive() {
    require_command systemctl
    if systemctl is-active --quiet ModemManager.service; then
        fail "ModemManager is active. Stop and runtime-mask it before continuing."
    fi
    printf 'VERIFIED %-44s PASS\n' "ModemManager inactive"
}

verify_tty_handles_closed() {
    require_command fuser
    local handle_report
    if handle_report="$(fuser -v "${TTY_NODES[@]}" 2>&1)"; then
        printf '%s\n' "$handle_report" >&2
        fail "A process has one or more CP2105 tty devices open."
    fi
    printf 'VERIFIED %-44s PASS (%s)\n' "CP2105 tty handles closed" "${TTY_NODES[*]}"
}

inspect_environment() {
    printf 'CP2105 CONTROLLED SMT INSPECTION\n'
    printf '================================\n\n'
    printf 'Wrapper version       : %s\n' "$VERSION"
    printf 'Serial selection      : detected at runtime; exactly one CP2105 required\n'
    printf 'Expected VID:PID      : %s:%s\n' "$EXPECTED_VID" "$EXPECTED_PID"
    printf 'Expected envelope     : %s\n' "$EXPECTED_ENVELOPE"
    printf 'Envelope SHA-256      : %s\n' "$EXPECTED_ENVELOPE_SHA256"
    printf 'Hardware correction   : J6 pins 9-10 removed; operator verification required\n\n'

    verify_static_files
    verify_no_live_smt_process
    find_exact_usb_device
    verify_modemmanager_inactive
    verify_tty_handles_closed

    printf '\nUSB identity\n'
    printf '  Sysfs device        : %s\n' "$USB_DEVICE_DIR"
    printf '  USB bus/device      : %s/%s\n' "$USB_BUS" "$USB_DEVICE_NUMBER"
    printf '  Detected serial     : %s\n' "$CURRENT_SERIAL"
    printf '  Serial state key    : %s\n' "$SERIAL_STATE_KEY"
    printf '  Serial interfaces   : %s\n' "${TTY_NODES[*]}"
    printf '\nINSPECTION PASSED.\n'
    printf 'No cp210xsmt command was invoked by this inspection.\n'
}

run_smt_logged() {
    local description="$1"
    shift
    printf '\n===== %s =====\n' "$description"
    printf 'Command:'
    printf ' %q' "$SMT_BINARY" "$@"
    printf '\n\n'

    set +e
    "$SMT_BINARY" "$@" 2>&1
    local status=$?
    set -e
    printf '\ncp210xsmt exit code: %d\n' "$status"
    return "$status"
}

verify_list_identity() {
    local list_output list_status serial_count
    printf '\n===== SILICON LABS READ-ONLY DEVICE LIST =====\n'
    printf 'Command: %q --list %q\n\n' "$SMT_BINARY" "$TARGET_CONFIG"

    set +e
    list_output="$($SMT_BINARY --list "$TARGET_CONFIG" 2>&1)"
    list_status=$?
    set -e
    printf '%s\n' "$list_output"
    printf '\ncp210xsmt exit code: %d\n' "$list_status"
    [[ $list_status -eq 0 ]] || fail "The Silicon Labs --list operation failed."
    serial_count="$(awk -v expected="$CURRENT_SERIAL" '
        {
            marker = "Ser #: "
            position = index($0, marker)
            if (position) {
                value = substr($0, position + length(marker))
                sub(/^[[:space:]]+/, "", value)
                sub(/[[:space:]]+$/, "", value)
                if (value == expected) {
                    count++
                }
            }
        }
        END { print count + 0 }
    ' <<<"$list_output")"
    [[ "$serial_count" == "1" ]] || fail \
        "The --list output did not contain exactly one match for detected serial: $CURRENT_SERIAL"
    printf 'VERIFIED %-44s PASS (%s)\n' "cp210xsmt/sysfs serial identity" "$CURRENT_SERIAL"
}

run_preflight() {
    inspect_environment
    verify_list_identity
    if ! run_smt_logged "READ-ONLY VIRGIN BASELINE VERIFICATION" --device-count 1 --verify-config "$VIRGIN_CONFIG"; then
        fail "Virgin baseline verification failed. No programming command will be executed."
    fi
    printf '\nPRE-PROGRAMMING PREFLIGHT PASSED.\n'
    printf 'The exact CP2105 virgin baseline was verified using manufacturer reads.\n'
    printf 'No setter, lock, or programming command was invoked.\n'
}

run_programming_boundary_recheck() {
    local authorized_serial="$1"

    printf '\nFINAL PRE-SETTER IDENTITY AND VIRGIN-STATE RECHECK\n'
    printf '================================================\n'
    inspect_environment
    [[ "$CURRENT_SERIAL" == "$authorized_serial" ]] || fail \
        "The attached CP2105 changed after authorization. Authorized $authorized_serial; now detected $CURRENT_SERIAL. No programming command was executed."
    verify_list_identity

    if ! run_smt_logged \
        "FINAL READ-ONLY VIRGIN BASELINE RECHECK" \
        --device-count 1 \
        --verify-config "$VIRGIN_CONFIG"; then
        fail "The final virgin baseline recheck failed. No programming command will be executed."
    fi

    ensure_no_active_attempt_marker
    printf '\nFINAL PROGRAMMING-BOUNDARY RECHECK PASSED FOR SERIAL %s.\n' "$CURRENT_SERIAL"
    printf 'No setter, lock, or programming command was invoked by the recheck.\n'
}

run_target_verification() {
    inspect_environment
    verify_list_identity
    if ! run_smt_logged "READ-ONLY FIVE-GPIO TARGET VERIFICATION" --device-count 1 --verify-config "$TARGET_CONFIG"; then
        fail "The device did not verify against the complete five-GPIO target configuration."
    fi
    printf '\nTARGET CONFIGURATION VERIFIED.\n'
    printf 'The exact target fields matched using manufacturer reads.\n'
    printf 'No setter, lock, or programming command was invoked by this action.\n'
}

show_existing_marker_and_fail() {
    local marker="$1"
    printf '\nExisting active one-shot marker:\n' >&2
    sed -n '1,160p' "$marker" >&2 || true
    fail "A programming attempt has already been consumed for detected serial $CURRENT_SERIAL. Do not retry that device."
}

ensure_no_active_attempt_marker() {
    [[ -n "${DEVICE_STATE_DIR:-}" ]] || fail "Device state paths have not been bound."
    if [[ -f "$CONSUMED_MARKER" ]]; then
        show_existing_marker_and_fail "$CONSUMED_MARKER"
    fi
}

write_immutable_marker() {
    local path="$1"
    shift
    if [[ -e "$path" ]]; then
        return 2
    fi
    if ! (set -o noclobber; printf '%s\n' "$@" > "$path") 2>/dev/null; then
        return 1
    fi
    chmod 0444 -- "$path"
}

consume_attempt_marker() {
    mkdir -p -- "$DEVICE_STATE_DIR"
    ensure_no_active_attempt_marker
    if ! write_immutable_marker "$CONSUMED_MARKER" \
        "CP2105 OTP v0.2a SERIAL-SCOPED TWO-PHASE ATTEMPT CONSUMED" \
        "UTC time: $(date -u --iso-8601=seconds)" \
        "Host: $(hostname)" \
        "Serial: $CURRENT_SERIAL" \
        "Serial state key: $SERIAL_STATE_KEY" \
        "Pre-program USB bus/device: $USB_BUS/$USB_DEVICE_NUMBER" \
        "Envelope: $EXPECTED_ENVELOPE" \
        "Envelope SHA-256: $EXPECTED_ENVELOPE_SHA256" \
        "Programming operation: cp210xsmt --device-count 1 --set-config target" \
        "Hardware correction: J6 pins 9-10 shorting block removed and operator-verified open." \
        "J4 state: pins 1-2 and pins 3-4 operator-confirmed installed." \
        "Prior v0.1d marker SHA-256: ${EXPECTED_V01D_MARKER_SHA256^^}" \
        "This marker was created before entering the Silicon Labs programming boundary." \
        "Do not remove it after success, failure, interruption, or an ambiguous result."; then
        fail "Could not create the v0.2a one-shot attempt marker for serial $CURRENT_SERIAL."
    fi
}

require_v02a_attempt_marker() {
    [[ -f "$CONSUMED_MARKER" ]] || fail \
        "verify-programmed found no v0.2a consumed marker for detected serial $CURRENT_SERIAL. Use verify-target for read-only recovery of an earlier-version attempt."
    grep -Fxq "CP2105 OTP v0.2a SERIAL-SCOPED TWO-PHASE ATTEMPT CONSUMED" "$CONSUMED_MARKER" || fail "The v0.2a consumed marker heading is invalid."
    grep -Fxq "Serial: $CURRENT_SERIAL" "$CONSUMED_MARKER" || fail "The v0.2a consumed marker serial does not match the attached device."
    grep -Fxq "Serial state key: $SERIAL_STATE_KEY" "$CONSUMED_MARKER" || fail "The v0.2a consumed marker state key does not match."
    grep -Fxq "Envelope SHA-256: $EXPECTED_ENVELOPE_SHA256" "$CONSUMED_MARKER" || fail "The v0.2a consumed marker envelope does not match."
    printf 'VERIFIED %-44s PASS (%s)\n' "v0.2a consumed marker" "$CURRENT_SERIAL"
}

confirm_programming() {
    [[ -t 0 ]] || fail "Programming requires an interactive input terminal."
    printf '\nIRREVERSIBLE PROGRAMMING AUTHORIZATION\n'
    printf '======================================\n'
    printf 'Manufacturer tool     : audited Silicon Labs cp210xsmt\n'
    printf 'Detected serial       : %s\n' "$CURRENT_SERIAL"
    printf 'Programming envelope  : %s\n' "$EXPECTED_ENVELOPE"
    printf 'Envelope SHA-256      : %s\n' "$EXPECTED_ENVELOPE_SHA256"
    printf 'Hardware correction   : J6 pins 9-10 must be electrically open\n'
    printf 'Required power state  : J4 1-2 and J4 3-4 installed\n'
    printf 'Lock option           : NOT USED\n'
    printf 'Setter execution count: ONE --set-config transaction only\n'
    printf 'Verification timing   : only after complete power removal\n\n'

    local entered_serial entered_hash entered_j6 entered_j4 entered_phrase entered_ack
    read -r -p "Re-enter physical serial number: " entered_serial
    [[ "$entered_serial" == "$CURRENT_SERIAL" ]] || fail "Serial confirmation did not match the attached CP2105."
    read -r -p "Re-enter envelope SHA-256: " entered_hash
    [[ "${entered_hash^^}" == "$EXPECTED_ENVELOPE_SHA256" ]] || fail "Envelope SHA-256 confirmation did not match."
    read -r -p "Type J6 9-10 IS OPEN AND VERIFIED: " entered_j6
    [[ "$entered_j6" == "J6 9-10 IS OPEN AND VERIFIED" ]] || fail "J6 hardware confirmation did not match."
    read -r -p "Type J4 1-2 AND 3-4 ARE INSTALLED: " entered_j4
    [[ "$entered_j4" == "J4 1-2 AND 3-4 ARE INSTALLED" ]] || fail "J4 power-jumper confirmation did not match."
    read -r -p "Type PROGRAM CP2105 PERMANENTLY: " entered_phrase
    [[ "$entered_phrase" == "PROGRAM CP2105 PERMANENTLY" ]] || fail "Permanent-programming phrase did not match."
    read -r -p "Type I ACCEPT ONE IRREVERSIBLE ATTEMPT: " entered_ack
    [[ "$entered_ack" == "I ACCEPT ONE IRREVERSIBLE ATTEMPT" ]] || fail "Irreversible-attempt acknowledgement did not match."
}

confirm_power_cycle() {
    [[ -t 0 ]] || fail "Power-cycle verification requires an interactive input terminal."
    printf '\nPOST-POWER-CYCLE READ-ONLY AUTHORIZATION\n'
    printf '========================================\n'
    printf 'This phase contains no setter or lock command.\n'
    printf 'Confirm that all CP2105 power was physically removed after the program\n'
    printf 'process ended, then the device was reconnected with J6 pins 9-10 open.\n\n'

    local removed reconnected
    read -r -p "Type CP2105 POWER WAS FULLY REMOVED: " removed
    [[ "$removed" == "CP2105 POWER WAS FULLY REMOVED" ]] || fail "Complete-power-removal confirmation did not match."
    read -r -p "Type CP2105 IS RECONNECTED FOR READ-ONLY VERIFY: " reconnected
    [[ "$reconnected" == "CP2105 IS RECONNECTED FOR READ-ONLY VERIFY" ]] || fail "Read-only reconnection confirmation did not match."
}

record_program_result() {
    local marker="$1"
    local heading="$2"
    local tool_status="$3"
    if ! write_immutable_marker "$marker" \
        "$heading" \
        "UTC time: $(date -u --iso-8601=seconds)" \
        "Serial: $CURRENT_SERIAL" \
        "Serial state key: $SERIAL_STATE_KEY" \
        "cp210xsmt exit code: $tool_status" \
        "Envelope SHA-256: $EXPECTED_ENVELOPE_SHA256" \
        "The irreversible attempt marker remains permanent." \
        "No automatic setter retry is authorized." \
        "Fully remove CP2105 power before any target verification."; then
        fail "Could not create the v0.2a program-result marker. The consumed marker remains authoritative."
    fi
}

record_verified_result() {
    local consumed_hash
    consumed_hash="$(sha256sum -- "$CONSUMED_MARKER" | awk '{print $1}')"
    if [[ -f "$VERIFIED_MARKER" ]]; then
        printf 'NOTICE: The immutable power-cycle verification marker already exists.\n'
        return 0
    fi
    if ! write_immutable_marker "$VERIFIED_MARKER" \
        "CP2105 OTP v0.2a POST-POWER-CYCLE TARGET VERIFIED" \
        "UTC time: $(date -u --iso-8601=seconds)" \
        "Host: $(hostname)" \
        "Serial: $CURRENT_SERIAL" \
        "Serial state key: $SERIAL_STATE_KEY" \
        "Verification USB bus/device: $USB_BUS/$USB_DEVICE_NUMBER" \
        "Envelope: $EXPECTED_ENVELOPE" \
        "Envelope SHA-256: $EXPECTED_ENVELOPE_SHA256" \
        "Consumed marker SHA-256: ${consumed_hash^^}" \
        "Verification operation: cp210xsmt --device-count 1 --verify-config target" \
        "Operator confirmed complete power removal and reconnection." \
        "No setter, lock, or programming command was invoked by verification."; then
        fail "Target verified, but the immutable verification marker could not be created. Preserve this log."
    fi
}

print_power_cycle_instructions() {
    printf '\nPROGRAM PHASE COMPLETE; TARGET IS NOT YET VERIFIED.\n'
    printf '===================================================\n'
    printf '1. Confirm that no cp210xsmt process remains.\n'
    printf '2. Fully remove ALL power from the CP2105 and board; a USB reset is not enough.\n'
    printf '3. Wait for the board rails to discharge, then reconnect serial %s with J6 9-10 open.\n' "$CURRENT_SERIAL"
    printf '4. Reattach the USB device to the Linux VM if passthrough requires it.\n'
    printf '5. Run: sudo ./cp2105-smt-control.sh verify-programmed\n'
    printf '\nDo not run program again for serial %s. Its marker remains permanent.\n' "$CURRENT_SERIAL"
}

program_once() {
    run_preflight
    ensure_no_active_attempt_marker
    local authorized_serial="$CURRENT_SERIAL"
    confirm_programming
    run_programming_boundary_recheck "$authorized_serial"
    consume_attempt_marker

    printf '\nONE-SHOT v0.2a AUTHORIZATION CONSUMED FOR SERIAL %s.\n' "$CURRENT_SERIAL"
    printf 'The corrected J6 condition has been operator-confirmed.\n'
    printf 'The manufacturer --set-config command will be invoked exactly once.\n'
    printf 'No same-powered-session verification, timeout, or programming retry is present.\n'

    local tool_status
    if run_smt_logged "SILICON LABS ONE-SHOT SET ONLY" --device-count 1 --set-config "$TARGET_CONFIG"; then
        tool_status=0
    else
        tool_status=$?
    fi

    if [[ $tool_status -eq 0 ]]; then
        record_program_result "$PROGRAM_SUCCESS_MARKER" "CP2105 v0.2a PROGRAM PHASE REPORTED SUCCESS; POWER-CYCLE VERIFY REQUIRED" "$tool_status"
        printf '\nMANUFACTURER SET-CONFIG REPORTED SUCCESS.\n'
        printf 'This is a programming-phase result, not final target verification.\n'
        print_power_cycle_instructions
        return 0
    fi

    record_program_result "$PROGRAM_AMBIGUOUS_MARKER" "CP2105 v0.2a PROGRAM RESULT AMBIGUOUS; READBACK REQUIRED" "$tool_status"
    printf '\nCP2105 PROGRAMMING COMMAND FAILED OR RETURNED AN AMBIGUOUS RESULT.\n' >&2
    printf 'The v0.2a marker for serial %s remains in place. DO NOT RETRY THAT DEVICE.\n' "$CURRENT_SERIAL" >&2
    printf 'After the process has ended, fully remove power and perform read-only verification.\n' >&2
    print_power_cycle_instructions >&2
    return 1
}

verify_programmed_after_power_cycle() {
    inspect_environment
    require_v02a_attempt_marker
    verify_list_identity
    confirm_power_cycle
    if ! run_smt_logged "POST-POWER-CYCLE READ-ONLY TARGET VERIFICATION" --device-count 1 --verify-config "$TARGET_CONFIG"; then
        printf '\nPOST-POWER-CYCLE TARGET VERIFICATION FAILED.\n' >&2
        printf 'No setter was invoked. Preserve this log and do not rerun program.\n' >&2
        printf 'Because verification is read-only, it may be repeated after correcting\n' >&2
        printf 'a connection, passthrough, power-cycle, or process-interference problem.\n' >&2
        return 1
    fi
    record_verified_result
    printf '\nPOST-POWER-CYCLE TARGET CONFIGURATION VERIFIED.\n'
    printf 'The exact five-GPIO target matched after complete power removal.\n'
    printf 'No setter, lock, or programming command was invoked by this phase.\n'
}

main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 2
    fi
    local mode="$1"
    case "$mode" in
        inspect|list|preflight|verify-target|program|verify-programmed) ;;
        -h|--help|help) usage; exit 0 ;;
        *) usage; fail "Unknown mode: $mode" ;;
    esac

    [[ $EUID -eq 0 ]] || fail "Run this wrapper with sudo so USB access is deterministic."
    mkdir -p -- "$LOG_DIR"
    local timestamp log_file
    timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
    log_file="$LOG_DIR/${timestamp}-${mode}.log"
    exec > >(tee -a "$log_file") 2>&1
    printf 'Log file: %s\n\n' "$log_file"

    case "$mode" in
        inspect) inspect_environment ;;
        list) inspect_environment; verify_list_identity; printf '\nREAD-ONLY LIST PASSED.\n' ;;
        preflight) run_preflight ;;
        verify-target) run_target_verification ;;
        program) program_once ;;
        verify-programmed) verify_programmed_after_power_cycle ;;
    esac
}

main "$@"
