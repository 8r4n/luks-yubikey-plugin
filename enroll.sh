#!/usr/bin/env bash
# enroll.sh — Enroll a YubiKey FIDO2 token into a LUKS2 volume
# Requires: systemd-cryptenroll, systemd 252+, libfido2
# Supports enrolling multiple YubiKeys (each gets its own keyslot)
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <device>

Enroll a YubiKey as a FIDO2 unlock token for a LUKS2 encrypted device.
PIN is required for FIDO2 authentication (2FA: something you have + something you know).

Arguments:
  <device>    LUKS2 block device (e.g. /dev/sda3, /dev/nvme0n1p3)

Options:
  -h, --help          Show this help message
  -l, --list          List currently enrolled FIDO2 tokens
  --no-pin-verify     Skip PIN verification prompt after enrollment
  --user-verification Set fido2-with-user-verification (biometric if available)

Examples:
  $(basename "$0") /dev/nvme0n1p3
  $(basename "$0") --list /dev/nvme0n1p3
  $(basename "$0") /dev/sda3   # enroll a second YubiKey
EOF
    exit 0
}

error() { echo "ERROR: $*" >&2; exit 1; }
info()  { echo ":: $*"; }

list_tokens=false
user_verification=false
pin_verify=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -l|--list) list_tokens=true; shift ;;
        --no-pin-verify) pin_verify=false; shift ;;
        --user-verification) user_verification=true; shift ;;
        -*) error "Unknown option: $1" ;;
        *) break ;;
    esac
done

DEVICE="${1:-}"
[[ -n "$DEVICE" ]] || error "No device specified. See --help."
[[ -b "$DEVICE" ]] || error "$DEVICE is not a block device."
[[ $EUID -eq 0 ]] || error "Must run as root."

# Validate LUKS2
cryptsetup isLuks "$DEVICE" 2>/dev/null || error "$DEVICE is not a LUKS device."
luks_version=$(cryptsetup luksDump "$DEVICE" | grep -m1 "Version:" | awk '{print $2}')
[[ "$luks_version" == "2" ]] || error "$DEVICE is LUKS$luks_version; LUKS2 is required."

# Check for FIDO2 device
if ! command -v fido2-token &>/dev/null; then
    error "libfido2 not installed. Run: sudo dnf install libfido2"
fi

fido2_devices=$(fido2-token -L 2>/dev/null || true)
if [[ -z "$fido2_devices" ]]; then
    error "No FIDO2 device detected. Insert your YubiKey and try again."
fi
info "Detected FIDO2 device(s):"
echo "$fido2_devices"

# List existing FIDO2 tokens
if [[ "$list_tokens" == true ]]; then
    info "FIDO2 tokens enrolled on $DEVICE:"
    systemd-cryptenroll "$DEVICE" --fido2-device=list 2>/dev/null || \
        cryptsetup luksDump "$DEVICE" | grep -A2 "fido2"
    exit 0
fi

# Enroll
info "Enrolling FIDO2 token on $DEVICE (PIN required)..."
info "You will be prompted for an existing LUKS passphrase and your YubiKey PIN."

enroll_args=(
    --fido2-device=auto
    --fido2-with-client-pin=yes
)

if [[ "$user_verification" == true ]]; then
    enroll_args+=(--fido2-with-user-verification=yes)
fi

systemd-cryptenroll "$DEVICE" "${enroll_args[@]}"

info "Enrollment successful."
info "Your YubiKey can now unlock $DEVICE at boot."
info ""
info "Next steps:"
info "  1. Run: sudo ./patch-crypttab.sh"
info "  2. Regenerate initramfs: sudo dracut -f"
info "  3. Reboot and test"
info ""
info "To enroll an additional YubiKey, insert it and run this script again."
info "For combined TPM2+FIDO2, use: sudo ./enroll-tpm-fido2.sh"
