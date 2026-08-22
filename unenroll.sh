#!/usr/bin/env bash
# unenroll.sh — Remove FIDO2 or TPM2+FIDO2 keyslots from a LUKS2 volume
set -euo pipefail

error() { echo "ERROR: $*" >&2; exit 1; }
info()  { echo ":: $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <device>

Remove FIDO2 or TPM2+FIDO2 keyslot(s) from a LUKS2 encrypted device.

Arguments:
  <device>    LUKS2 block device (e.g. /dev/sda3, /dev/nvme0n1p3)

Options:
  -h, --help        Show this help message
  -s, --slot <N>    Remove a specific keyslot number
  --all             Remove ALL FIDO2 keyslots (keeps passphrase slots)
  --tpm2-fido2      Remove combined TPM2+FIDO2 keyslots (tokens with both bindings)

Examples:
  $(basename "$0") /dev/nvme0n1p3              # interactive: choose which to remove
  $(basename "$0") -s 2 /dev/nvme0n1p3         # remove keyslot 2
  $(basename "$0") --all /dev/nvme0n1p3        # remove all FIDO2 keyslots
  $(basename "$0") --tpm2-fido2 /dev/nvme0n1p3 # remove combined TPM2+FIDO2 keyslots
EOF
    exit 0
}

slot=""
remove_all=false
tpm2_fido2=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -s|--slot) slot="$2"; shift 2 ;;
        --all) remove_all=true; shift ;;
        --tpm2-fido2) tpm2_fido2=true; shift ;;
        -*) error "Unknown option: $1" ;;
        *) break ;;
    esac
done

DEVICE="${1:-}"
[[ -n "$DEVICE" ]] || error "No device specified. See --help."
[[ -b "$DEVICE" ]] || error "$DEVICE is not a block device."
[[ $EUID -eq 0 ]] || error "Must run as root."

cryptsetup isLuks "$DEVICE" 2>/dev/null || error "$DEVICE is not a LUKS device."

if [[ "$tpm2_fido2" == true ]]; then
    # Find keyslots that have both TPM2 and FIDO2 token bindings
    # Combined enrollment creates tokens referencing the same keyslot with both types
    luks_dump=$(cryptsetup luksDump "$DEVICE")

    # Find keyslots associated with tpm2 tokens
    tpm2_slots=$(echo "$luks_dump" | grep -B1 "systemd-tpm2" | grep "Keyslot:" | awk '{print $2}' || true)
    # Find keyslots associated with fido2 tokens
    fido2_slots_raw=$(echo "$luks_dump" | grep -B1 "fido2" | grep "Keyslot:" | awk '{print $2}' || true)

    # Combined slots appear in both lists
    combined_slots=""
    for s in $tpm2_slots; do
        if echo "$fido2_slots_raw" | grep -qw "$s"; then
            combined_slots="$combined_slots $s"
        fi
    done
    combined_slots=$(echo "$combined_slots" | xargs)

    if [[ -z "$combined_slots" ]]; then
        info "No combined TPM2+FIDO2 keyslots found on $DEVICE."
        exit 0
    fi

    info "Combined TPM2+FIDO2 keyslots on $DEVICE: $combined_slots"
    for s in $combined_slots; do
        cryptsetup luksKillSlot "$DEVICE" "$s"
        info "Removed keyslot $s."
    done
    info "All combined TPM2+FIDO2 keyslots removed."
else
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
fi

info "Remember to regenerate initramfs: sudo dracut -f"
