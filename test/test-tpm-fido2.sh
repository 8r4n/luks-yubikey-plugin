#!/usr/bin/env bash
# test-tpm-fido2.sh — Test combined TPM2+FIDO2 enrollment on a loopback LUKS2 device
# Requires: swtpm (software TPM) for TPM emulation, or real TPM hardware
# Safe to run — does NOT touch real disks.
set -euo pipefail

error() { echo "FAIL: $*" >&2; exit 1; }
info()  { echo ":: $*"; }
pass()  { echo "PASS: $*"; }
skip()  { echo "SKIP: $*"; exit 0; }

TESTDIR=$(mktemp -d /tmp/luks-tpm-fido2-test.XXXXX)
IMGFILE="$TESTDIR/test.img"
LOOPDEV=""
MAPPED_NAME="test-tpm-fido2-luks"
TEST_PASSPHRASE="test-passphrase-tpm-fido2"

cleanup() {
    set +e
    [[ -e "/dev/mapper/$MAPPED_NAME" ]] && cryptsetup close "$MAPPED_NAME"
    [[ -n "$LOOPDEV" ]] && losetup -d "$LOOPDEV"
    rm -rf "$TESTDIR"
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || error "Must run as root."

# Check systemd version
systemd_version=$(systemd-cryptenroll --version 2>/dev/null | head -1 | grep -oP '\d+' | head -1 || echo "0")
if [[ "$systemd_version" -lt 253 ]]; then
    skip "systemd $systemd_version < 253; combined TPM2+FIDO2 not supported"
fi
pass "systemd version $systemd_version (253+ required)"

# Check for TPM2 device (real or swtpm)
has_tpm=false
if [[ -e /dev/tpmrm0 ]]; then
    has_tpm=true
    info "Real TPM2 device detected"
fi

# Check for FIDO2 device
has_fido2=false
if command -v fido2-token &>/dev/null && fido2-token -L 2>/dev/null | grep -q .; then
    has_fido2=true
    info "FIDO2 device detected"
fi

if [[ "$has_tpm" == false ]] || [[ "$has_fido2" == false ]]; then
    skip "Combined TPM2+FIDO2 test requires both TPM2 (/dev/tpmrm0) and a FIDO2 device"
fi

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

info "Testing combined TPM2+FIDO2 enrollment..."
echo -n "$TEST_PASSPHRASE" | systemd-cryptenroll "$LOOPDEV" \
    --tpm2-device=auto \
    --tpm2-pcrs=7 \
    --fido2-device=auto \
    --fido2-with-client-pin=yes
pass "Combined TPM2+FIDO2 enrollment succeeded"

info "Verifying token metadata..."
luks_dump=$(cryptsetup luksDump "$LOOPDEV")
echo "$luks_dump" | grep -q "tpm2" || error "No TPM2 token found in dump"
echo "$luks_dump" | grep -q "fido2" || error "No FIDO2 token found in dump"
pass "Both TPM2 and FIDO2 tokens visible in luksDump"

info ""
pass "All TPM2+FIDO2 tests passed."
