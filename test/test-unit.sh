#!/usr/bin/env bash
# test-unit.sh — Unit tests for script argument parsing and validation logic
# Does NOT require root, hardware, or real block devices.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

assert_exit_nonzero() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        fail "$desc (expected failure, got success)"
    else
        pass "$desc"
    fi
}

assert_exit_zero() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc (expected success, got failure)"
    fi
}

assert_output_contains() {
    local desc="$1" pattern="$2"; shift 2
    local output
    output=$("$@" 2>&1 || true)
    if echo "$output" | grep -q "$pattern"; then
        pass "$desc"
    else
        fail "$desc (output missing '$pattern')"
    fi
}

# ============================================================
echo "=== enroll.sh ==="

assert_output_contains "enroll.sh: no device shows error" "No device specified" \
    "$SCRIPT_DIR/enroll.sh"

assert_output_contains "enroll.sh: --help shows usage" "Usage:" \
    "$SCRIPT_DIR/enroll.sh" --help

assert_output_contains "enroll.sh: non-block device error" "not a block device" \
    "$SCRIPT_DIR/enroll.sh" /tmp/nonexistent-file

assert_output_contains "enroll.sh: unknown option error" "Unknown option" \
    "$SCRIPT_DIR/enroll.sh" --bogus-flag

# ============================================================
echo "=== enroll-tpm-fido2.sh ==="

assert_output_contains "enroll-tpm-fido2.sh: no device shows error" "No device specified" \
    "$SCRIPT_DIR/enroll-tpm-fido2.sh"

assert_output_contains "enroll-tpm-fido2.sh: --help shows usage" "Usage:" \
    "$SCRIPT_DIR/enroll-tpm-fido2.sh" --help

assert_output_contains "enroll-tpm-fido2.sh: --help mentions PCR" "PCR" \
    "$SCRIPT_DIR/enroll-tpm-fido2.sh" --help

assert_output_contains "enroll-tpm-fido2.sh: non-block device error" "not a block device" \
    "$SCRIPT_DIR/enroll-tpm-fido2.sh" /tmp/nonexistent-file

assert_output_contains "enroll-tpm-fido2.sh: unknown option error" "Unknown option" \
    "$SCRIPT_DIR/enroll-tpm-fido2.sh" --bogus

# ============================================================
echo "=== unenroll.sh ==="

assert_output_contains "unenroll.sh: no device shows error" "No device specified" \
    "$SCRIPT_DIR/unenroll.sh"

assert_output_contains "unenroll.sh: --help shows usage" "Usage:" \
    "$SCRIPT_DIR/unenroll.sh" --help

assert_output_contains "unenroll.sh: --help mentions tpm2-fido2" "tpm2-fido2" \
    "$SCRIPT_DIR/unenroll.sh" --help

assert_output_contains "unenroll.sh: non-block device error" "not a block device" \
    "$SCRIPT_DIR/unenroll.sh" /tmp/nonexistent-file

assert_output_contains "unenroll.sh: unknown option error" "Unknown option" \
    "$SCRIPT_DIR/unenroll.sh" --bogus

# ============================================================
echo "=== patch-crypttab.sh ==="

assert_output_contains "patch-crypttab.sh: --help shows usage" "Usage:" \
    "$SCRIPT_DIR/patch-crypttab.sh" --help

assert_output_contains "patch-crypttab.sh: --help mentions mode" "mode" \
    "$SCRIPT_DIR/patch-crypttab.sh" --help

assert_output_contains "patch-crypttab.sh: invalid mode error" "Unknown mode" \
    "$SCRIPT_DIR/patch-crypttab.sh" --mode invalid

assert_output_contains "patch-crypttab.sh: unknown option error" "Unknown option" \
    "$SCRIPT_DIR/patch-crypttab.sh" --bogus

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
