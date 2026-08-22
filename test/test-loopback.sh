#!/usr/bin/env bash
# test-loopback.sh — Non-destructive test using a loopback LUKS2 device
# This does NOT touch real disks. Safe to run for development/CI.
set -euo pipefail

error() { echo "FAIL: $*" >&2; exit 1; }
info()  { echo ":: $*"; }
pass()  { echo "PASS: $*"; }

TESTDIR=$(mktemp -d /tmp/luks-yubikey-test.XXXXX)
IMGFILE="$TESTDIR/test.img"
LOOPDEV=""
MAPPED_NAME="test-yubikey-luks"
TEST_PASSPHRASE="test-passphrase-12345"

cleanup() {
    set +e
    [[ -e "/dev/mapper/$MAPPED_NAME" ]] && cryptsetup close "$MAPPED_NAME"
    [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV"
    rm -rf "$TESTDIR"
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || error "Must run as root."

info "Creating 64MB test image..."
dd if=/dev/zero of="$IMGFILE" bs=1M count=64 status=none

info "Setting up loop device..."
LOOPDEV=$(losetup --find --show "$IMGFILE")
info "Loop device: $LOOPDEV"

info "Formatting as LUKS2..."
echo -n "$TEST_PASSPHRASE" | cryptsetup luksFormat --type luks2 --batch-mode "$LOOPDEV" -

info "Verifying LUKS2..."
cryptsetup isLuks "$LOOPDEV" || error "Not a valid LUKS device"
version=$(cryptsetup luksDump "$LOOPDEV" | grep -m1 "Version:" | awk '{print $2}')
[[ "$version" == "2" ]] || error "Expected LUKS2, got LUKS$version"
pass "LUKS2 volume created on loopback"

info "Testing passphrase unlock..."
echo -n "$TEST_PASSPHRASE" | cryptsetup open --type luks "$LOOPDEV" "$MAPPED_NAME" -
[[ -e "/dev/mapper/$MAPPED_NAME" ]] || error "Failed to open LUKS device"
cryptsetup close "$MAPPED_NAME"
pass "Passphrase unlock works"

# FIDO2 enrollment test (only if a YubiKey is present)
if command -v fido2-token &>/dev/null && fido2-token -L 2>/dev/null | grep -q .; then
    info "YubiKey detected — testing FIDO2 enrollment..."
    echo -n "$TEST_PASSPHRASE" | systemd-cryptenroll "$LOOPDEV" \
        --fido2-device=auto \
        --fido2-with-client-pin=yes \
        --unlock-fido2-device=auto 2>/dev/null || \
    echo -n "$TEST_PASSPHRASE" | systemd-cryptenroll "$LOOPDEV" \
        --fido2-device=auto \
        --fido2-with-client-pin=yes
    pass "FIDO2 enrollment succeeded"

    info "Verifying FIDO2 keyslot exists..."
    cryptsetup luksDump "$LOOPDEV" | grep -q "fido2" || error "No FIDO2 token found in dump"
    pass "FIDO2 token visible in luksDump"
else
    info "No YubiKey detected — skipping FIDO2 enrollment test (passphrase-only validated)"
fi

info ""
pass "All tests passed."
