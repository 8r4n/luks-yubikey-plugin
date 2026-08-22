#!/usr/bin/env bash
# unenroll.sh — Remove a FIDO2 keyslot from a LUKS2 volume
set -euo pipefail

error() { echo "ERROR: $*" >&2; exit 1; }
info()  { echo ":: $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <device>

Remove a FIDO2 (YubiKey) keyslot from a LUKS2 encrypted device.

Arguments:
  <device>    LUKS2 block device (e.g. /dev/sda3, /dev/nvme0n1p3)

Options:
  -h, --help        Show this help message
  -s, --slot <N>    Remove a specific keyslot number
  --all             Remove ALL FIDO2 keyslots (keeps passphrase slots)

Examples:
  $(basename "$0") /dev/nvme0n1p3          # interactive: choose which to remove
  $(basename "$0") -s 2 /dev/nvme0n1p3     # remove keyslot 2
  $(basename "$0") --all /dev/nvme0n1p3    # remove all FIDO2 keyslots
EOF
    exit 0
}

slot=""
remove_all=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -s|--slot) slot="$2"; shift 2 ;;
        --all) remove_all=true; shift ;;
        -*) error "Unknown option: $1" ;;
        *) break ;;
    esac
done

DEVICE="${1:-}"
[[ -n "$DEVICE" ]] || error "No device specified. See --help."
[[ -b "$DEVICE" ]] || error "$DEVICE is not a block device."
[[ $EUID -eq 0 ]] || error "Must run as root."

cryptsetup isLuks "$DEVICE" 2>/dev/null || error "$DEVICE is not a LUKS device."

# Find FIDO2 keyslots
fido2_slots=$(cryptsetup luksDump "$DEVICE" | grep -B1 "fido2" | grep "Keyslot:" | awk '{print $2}' || true)

if [[ -z "$fido2_slots" ]]; then
    # Try alternative detection via token dump
    fido2_slots=$(cryptsetup luksDump "$DEVICE" | awk '/Tokens:/{found=1} found && /fido2/{getline; print}' | grep -oP '\d+' || true)
fi

if [[ -z "$fido2_slots" ]]; then
    info "No FIDO2 keyslots found on $DEVICE."
    exit 0
fi

info "FIDO2 keyslots on $DEVICE: $fido2_slots"

if [[ -n "$slot" ]]; then
    cryptsetup luksKillSlot "$DEVICE" "$slot"
    info "Removed keyslot $slot."
elif [[ "$remove_all" == true ]]; then
    for s in $fido2_slots; do
        cryptsetup luksKillSlot "$DEVICE" "$s"
        info "Removed keyslot $s."
    done
    info "All FIDO2 keyslots removed."
else
    info "Specify --slot <N> or --all to remove keyslots."
    info "Use 'cryptsetup luksDump $DEVICE' to inspect slots."
    exit 1
fi

info "Remember to regenerate initramfs: sudo dracut -f"
