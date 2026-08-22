#!/usr/bin/env bash
# patch-crypttab.sh — Add fido2-device=auto to /etc/crypttab for LUKS2 FIDO2 unlock at boot
set -euo pipefail

CRYPTTAB="/etc/crypttab"

error() { echo "ERROR: $*" >&2; exit 1; }
info()  { echo ":: $*"; }

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

    # If line already has fido2-device, leave it alone
    if echo "$line" | grep -q "fido2-device"; then
        echo "$line"
        continue
    fi

    # Check if this entry uses a LUKS device (has luks in options or no options)
    if echo "$line" | grep -qiE "luks|none"; then
        # Append fido2-device=auto,fido2-with-client-pin=yes to the options field
        # crypttab format: name device keyfile options
        name=$(echo "$line" | awk '{print $1}')
        device=$(echo "$line" | awk '{print $2}')
        keyfile=$(echo "$line" | awk '{print $3}')
        options=$(echo "$line" | awk '{print $4}')

        if [[ -z "$options" ]] || [[ "$options" == "none" ]] || [[ "$options" == "luks" ]]; then
            options="luks,fido2-device=auto"
        else
            options="${options},fido2-device=auto"
        fi

        echo "$name $device $keyfile $options"
        changed=true
    else
        echo "$line"
    fi
done < "$CRYPTTAB" > "${CRYPTTAB}.new"

mv "${CRYPTTAB}.new" "$CRYPTTAB"

if [[ "$changed" == true ]]; then
    info "Updated $CRYPTTAB with fido2-device=auto"
    info "Current contents:"
    cat "$CRYPTTAB"
    info ""
    info "Now regenerate initramfs: sudo dracut -f"
else
    info "No changes needed — fido2-device already configured or no LUKS entries found."
fi
