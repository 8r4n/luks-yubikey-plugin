#!/usr/bin/env bash
# patch-crypttab.sh — Add FIDO2/TPM2 device options to /etc/crypttab for LUKS2 unlock at boot
set -euo pipefail

CRYPTTAB="/etc/crypttab"

error() { echo "ERROR: $*" >&2; exit 1; }
info()  { echo ":: $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Patch /etc/crypttab to enable FIDO2 or TPM2+FIDO2 unlock at boot.

Options:
  -h, --help            Show this help message
  --mode <mode>         Unlock mode: fido2 (default) or tpm2-fido2
EOF
    exit 0
}

MODE="fido2"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --mode) MODE="$2"; shift 2 ;;
        -*) error "Unknown option: $1" ;;
        *) break ;;
    esac
done

case "$MODE" in
    fido2) DEVICE_OPTS="fido2-device=auto" ;;
    tpm2-fido2) DEVICE_OPTS="tpm2-device=auto,fido2-device=auto" ;;
    *) error "Unknown mode: $MODE. Use 'fido2' or 'tpm2-fido2'." ;;
esac

[[ $EUID -eq 0 ]] || error "Must run as root."
[[ -f "$CRYPTTAB" ]] || error "$CRYPTTAB not found."

# Backup
cp "$CRYPTTAB" "${CRYPTTAB}.bak.$(date +%s)"
info "Backed up $CRYPTTAB"

changed=false
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
        echo "$line"
        continue
    fi

    # If line already has the target device options, leave it alone
    if echo "$line" | grep -q "fido2-device"; then
        echo "$line"
        continue
    fi

    # Check if this entry uses a LUKS device (has luks in options or no options)
    if echo "$line" | grep -qiE "luks|none"; then
        # Append device options to the options field
        # crypttab format: name device keyfile options
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
done < "$CRYPTTAB" > "${CRYPTTAB}.new"

mv "${CRYPTTAB}.new" "$CRYPTTAB"

if [[ "$changed" == true ]]; then
    info "Updated $CRYPTTAB with $DEVICE_OPTS"
    info "Current contents:"
    cat "$CRYPTTAB"
    info ""
    info "Now regenerate initramfs: sudo dracut -f"
else
    info "No changes needed — fido2-device already configured or no LUKS entries found."
fi
