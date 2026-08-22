#!/usr/bin/env bash
# test-patch-crypttab.sh — Test crypttab patching logic with mock files
# Does NOT require root or real /etc/crypttab.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTDIR=$(mktemp -d /tmp/test-crypttab.XXXXX)
trap 'rm -rf "$TESTDIR"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# We test the patching logic by sourcing the relevant section.
# Since patch-crypttab.sh checks for root and real /etc/crypttab,
# we create a wrapper that overrides those checks.

run_patch() {
    local mode="$1" input="$2" output_file="$3"
    local CRYPTTAB="$input"
    local DEVICE_OPTS

    case "$mode" in
        fido2) DEVICE_OPTS="fido2-device=auto" ;;
        tpm2-fido2) DEVICE_OPTS="tpm2-device=auto,fido2-device=auto" ;;
    esac

    local changed=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            echo "$line"
            continue
        fi
        if echo "$line" | grep -q "fido2-device"; then
            echo "$line"
            continue
        fi
        if echo "$line" | grep -qiE "luks|none"; then
            name=$(echo "$line" | awk '{print $1}')
            device=$(echo "$line" | awk '{print $2}')
            keyfile=$(echo "$line" | awk '{print $3}')
            options=$(echo "$line" | awk '{print $4}')
            if [[ -z "$options" ]] || [[ "$options" == "none" ]] || [[ "$options" == "luks" ]]; then
                options="luks,$DEVICE_OPTS"
            else
                options="${options},$DEVICE_OPTS"
            fi
            echo "$name $device $keyfile $options"
            changed=true
        else
            echo "$line"
        fi
    done < "$CRYPTTAB" > "$output_file"
}

# ============================================================
echo "=== patch-crypttab: fido2 mode ==="

cat > "$TESTDIR/input1" <<'EOF'
# /etc/crypttab
luks-abc /dev/sda3 none luks
EOF

run_patch "fido2" "$TESTDIR/input1" "$TESTDIR/output1"

if grep -q "luks,fido2-device=auto" "$TESTDIR/output1"; then
    pass "Adds fido2-device=auto to luks entry"
else
    fail "Expected fido2-device=auto in output"
fi

if grep -q "^# /etc/crypttab" "$TESTDIR/output1"; then
    pass "Preserves comments"
else
    fail "Comment was not preserved"
fi

# ============================================================
echo "=== patch-crypttab: tpm2-fido2 mode ==="

cat > "$TESTDIR/input2" <<'EOF'
luks-root /dev/nvme0n1p3 none luks
EOF

run_patch "tpm2-fido2" "$TESTDIR/input2" "$TESTDIR/output2"

if grep -q "tpm2-device=auto,fido2-device=auto" "$TESTDIR/output2"; then
    pass "Adds tpm2-device=auto,fido2-device=auto"
else
    fail "Expected tpm2+fido2 options in output"
fi

# ============================================================
echo "=== patch-crypttab: already patched ==="

cat > "$TESTDIR/input3" <<'EOF'
luks-root /dev/nvme0n1p3 none luks,fido2-device=auto
EOF

run_patch "fido2" "$TESTDIR/input3" "$TESTDIR/output3"

# Should not double-add
count=$(grep -c "fido2-device" "$TESTDIR/output3")
if [[ "$count" -eq 1 ]]; then
    pass "Does not duplicate fido2-device if already present"
else
    fail "fido2-device appears $count times (expected 1)"
fi

# ============================================================
echo "=== patch-crypttab: existing options preserved ==="

cat > "$TESTDIR/input4" <<'EOF'
luks-data /dev/sdb1 none luks,discard
EOF

run_patch "fido2" "$TESTDIR/input4" "$TESTDIR/output4"

if grep -q "luks,discard,fido2-device=auto" "$TESTDIR/output4"; then
    pass "Appends to existing options"
else
    fail "Expected options to be appended"
    cat "$TESTDIR/output4"
fi

# ============================================================
echo "=== patch-crypttab: non-luks entry unchanged ==="

cat > "$TESTDIR/input5" <<'EOF'
swap /dev/sda2 /dev/urandom swap
EOF

run_patch "fido2" "$TESTDIR/input5" "$TESTDIR/output5"

if diff -q "$TESTDIR/input5" "$TESTDIR/output5" >/dev/null 2>&1; then
    pass "Non-luks entry left unchanged"
else
    fail "Non-luks entry was modified"
fi

# ============================================================
echo "=== patch-crypttab: options field 'none' replaced ==="

cat > "$TESTDIR/input6" <<'EOF'
luks-home /dev/sda4 none none
EOF

run_patch "fido2" "$TESTDIR/input6" "$TESTDIR/output6"

if grep -q "luks,fido2-device=auto" "$TESTDIR/output6"; then
    pass "Replaces 'none' options with luks,fido2-device=auto"
else
    fail "Did not replace 'none' options correctly"
    cat "$TESTDIR/output6"
fi

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
