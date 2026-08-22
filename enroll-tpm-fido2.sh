#!/usr/bin/env bash
# enroll-tpm-fido2.sh — Enroll a combined TPM2 + YubiKey FIDO2 token into a LUKS2 volume
# Requires: systemd-cryptenroll, systemd 253+, libfido2, TPM2
# Creates a single keyslot requiring BOTH TPM2 unsealing AND FIDO2 assertion to unlock.
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <device>

Enroll a combined TPM2 + FIDO2 (YubiKey) unlock token for a LUKS2 encrypted device.
Both factors are required simultaneously to unlock (3-factor: platform + possession + PIN).

Arguments:
  <device>    LUKS2 block device (e.g. /dev/sda3, /dev/nvme0n1p3)

Options:
  -h, --help              Show this help message
  --tpm2-pcrs <list>      PCR registers to bind (default: 7 = Secure Boot state)
  --tpm2-with-pin         Also require a TPM2 PIN (4-factor authentication)
  --user-verification     Set fido2-with-user-verification (biometric if available)

PCR Reference:
  0   - Core BIOS/firmware
  7   - Secure Boot state (recommended default)
  11  - Unified kernel image hash (breaks on kernel updates)
  7+14 - Secure Boot + shim/MOK policy

Examples:
  $(basename "$0") /dev/nvme0n1p3
  $(basename "$0") --tpm2-pcrs 7+14 /dev/nvme0n1p3
  $(basename "$0") --tpm2-with-pin /dev/nvme0n1p3
EOF
    exit 0
}

error() { echo "ERROR: $*" >&2; exit 1; }
info()  { echo ":: $*"; }

tpm2_pcrs="7"
tpm2_with_pin=false
user_verification=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --tpm2-pcrs) tpm2_pcrs="$2"; shift 2 ;;
        --tpm2-with-pin) tpm2_with_pin=true; shift ;;
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

# Check systemd version (253+ required for combined TPM2+FIDO2)
systemd_version=$(systemd-cryptenroll --version 2>/dev/null | head -1 | grep -oP '\d+' | head -1 || echo "0")
if [[ "$systemd_version" -lt 253 ]]; then
    error "systemd $systemd_version detected; version 253+ is required for combined TPM2+FIDO2 enrollment."
fi
info "systemd version: $systemd_version (253+ required — OK)"

# Check for TPM2 device
if [[ ! -e /dev/tpmrm0 ]]; then
    error "No TPM2 device found (/dev/tpmrm0 missing). Ensure TPM2 is enabled in BIOS and kernel module is loaded (modprobe tpm_crb)."
fi
info "TPM2 device: /dev/tpmrm0"

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

# Build enrollment command
enroll_args=(
    --tpm2-device=auto
    "--tpm2-pcrs=$tpm2_pcrs"
    --fido2-device=auto
    --fido2-with-client-pin=yes
)

if [[ "$tpm2_with_pin" == true ]]; then
    enroll_args+=(--tpm2-with-pin=yes)
fi

if [[ "$user_verification" == true ]]; then
    enroll_args+=(--fido2-with-user-verification=yes)
fi

info "Enrolling combined TPM2+FIDO2 token on $DEVICE..."
info "TPM2 PCR policy: $tpm2_pcrs"
info "You will be prompted for an existing LUKS passphrase and your YubiKey PIN."

systemd-cryptenroll "$DEVICE" "${enroll_args[@]}"

info "Enrollment successful."
info "Your disk now requires BOTH TPM2 + YubiKey to unlock."
info ""
info "Next steps:"
info "  1. Run: sudo ./patch-crypttab.sh --mode tpm2-fido2"
info "  2. Regenerate initramfs: sudo dracut -f"
info "  3. Reboot and test"
info ""
info "WARNING: If TPM2 PCRs change (firmware update, Secure Boot policy change),"
info "         the combined keyslot will stop working. Keep a passphrase slot active."
