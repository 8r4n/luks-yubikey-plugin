#!/usr/bin/env bash
# run-all.sh — Run all tests that can execute in the current environment
# Tests that need hardware gracefully skip. Unit tests always run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

run_test() {
    local name="$1" script="$2"
    echo ""
    echo "━━━ $name ━━━"
    local rc=0
    bash "$script" || rc=$?
    if [[ $rc -eq 0 ]]; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        echo "  ^^^ $name FAILED (exit $rc)"
    fi
}

run_test "Unit tests (argument parsing)" "$SCRIPT_DIR/test-unit.sh"
run_test "Crypttab patching logic" "$SCRIPT_DIR/test-patch-crypttab.sh"

# Hardware-dependent tests — run only if conditions are met
if [[ $EUID -eq 0 ]] && command -v cryptsetup &>/dev/null; then
    run_test "Loopback LUKS2 test" "$SCRIPT_DIR/test-loopback.sh"

    if [[ -e /dev/tpmrm0 ]] && command -v fido2-token &>/dev/null; then
        run_test "TPM2+FIDO2 combined test" "$SCRIPT_DIR/test-tpm-fido2.sh"
    else
        echo ""
        echo "━━━ TPM2+FIDO2 combined test ━━━"
        echo "  SKIP: requires root + TPM2 + FIDO2 device"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
    fi
else
    echo ""
    echo "━━━ Loopback LUKS2 test ━━━"
    echo "  SKIP: requires root and cryptsetup"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
    echo ""
    echo "━━━ TPM2+FIDO2 combined test ━━━"
    echo "  SKIP: requires root + TPM2 + FIDO2 device"
    TOTAL_SKIP=$((TOTAL_SKIP + 1))
fi

echo ""
echo "════════════════════════════════"
echo "Test suites: $TOTAL_PASS passed, $TOTAL_FAIL failed, $TOTAL_SKIP skipped"
echo "════════════════════════════════"
[[ $TOTAL_FAIL -eq 0 ]] || exit 1
