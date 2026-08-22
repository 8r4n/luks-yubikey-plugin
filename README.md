# luks-yubikey-plugin

FIDO2-based YubiKey unlock for LUKS2 full disk encryption on Fedora Linux.

## Overview

This plugin uses `systemd-cryptenroll` to register YubiKey FIDO2 tokens as LUKS2 keyslots. At boot, the system prompts for your YubiKey touch and PIN to unlock the encrypted disk.

**Security model:** 2FA — something you have (YubiKey) + something you know (PIN).

## Requirements

- Fedora 38+ (systemd 252+)
- LUKS2 encrypted root partition
- YubiKey 5 series (or any FIDO2-capable key)
- Packages: `libfido2`, `systemd` (cryptenroll is part of systemd)

```bash
sudo dnf install libfido2 libfido2-devel
```

## Quick Start

```bash
# 1. Enroll your first YubiKey
sudo ./enroll.sh /dev/nvme0n1p3

# 2. Patch crypttab for boot unlock
sudo ./patch-crypttab.sh

# 3. Regenerate initramfs
sudo dracut -f

# 4. Reboot and test
```

## Multiple YubiKeys

Each YubiKey enrollment creates a separate LUKS2 keyslot. Enroll backup keys by inserting a different YubiKey and running `enroll.sh` again:

```bash
# Insert second YubiKey
sudo ./enroll.sh /dev/nvme0n1p3
```

Both keys can independently unlock the volume. If one is lost, remove its keyslot and the other continues to work.

## Removing a YubiKey

```bash
# List FIDO2 keyslots
sudo ./unenroll.sh /dev/nvme0n1p3

# Remove a specific slot
sudo ./unenroll.sh -s 2 /dev/nvme0n1p3

# Remove all FIDO2 keyslots
sudo ./unenroll.sh --all /dev/nvme0n1p3

# Regenerate initramfs after changes
sudo dracut -f
```

## Recovery

If your YubiKey is unavailable at boot, the system falls back to the standard LUKS passphrase prompt. **Always keep a passphrase keyslot active.**

To verify you have a passphrase slot:
```bash
cryptsetup luksDump /dev/nvme0n1p3 | grep -A1 "Keyslot"
```

## Scripts

| Script | Purpose |
|--------|---------|
| `enroll.sh` | Enroll a YubiKey FIDO2 token into LUKS2 |
| `enroll-tpm-fido2.sh` | Enroll combined TPM2 + FIDO2 token (3-factor) |
| `unenroll.sh` | Remove FIDO2 or TPM2+FIDO2 keyslot(s) |
| `patch-crypttab.sh` | Add device options to `/etc/crypttab` (supports `--mode tpm2-fido2`) |
| `test/test-loopback.sh` | Non-destructive FIDO2 test on a loopback device |
| `test/test-tpm-fido2.sh` | Non-destructive TPM2+FIDO2 test on a loopback device |

## How It Works

1. `systemd-cryptenroll` registers a FIDO2 credential in a LUKS2 token metadata slot
2. `fido2-device=auto` in crypttab tells `systemd-cryptsetup` to try FIDO2 at boot
3. The initramfs (dracut) includes FIDO2 libraries and prompts for YubiKey touch + PIN
4. On success, the LUKS volume unlocks; on failure/timeout, falls back to passphrase

## Documentation

Comprehensive system engineering documentation is available in the [`docs/`](docs/) directory:

| Document | Description |
|----------|-------------|
| [System Architecture](docs/architecture.md) | Component architecture, data flows, security boundaries, UML diagrams, vendor references, threat model, and future TPM+FIDO2 design |
| [Encryption Fundamentals](docs/encryption-fundamentals.md) | Cryptographic principles (AES-256-XTS, argon2id, ECDSA P-256, FIDO2 hmac-secret), LUKS2 on-disk format, trust chain analysis |
| [Operations Guide](docs/operations-guide.md) | Step-by-step enrollment/unenrollment procedures, boot operations, key management, recovery, troubleshooting, verification checklists |

All diagrams use [PlantUML](https://plantuml.com/) notation and can be rendered with any PlantUML-compatible tool.

## TPM2 + YubiKey (Combined 3-Factor)

For maximum security, bind both TPM2 and FIDO2 into a single keyslot. This requires all three factors simultaneously: platform integrity (TPM2), physical possession (YubiKey), and knowledge (PIN).

**Additional requirements:** systemd 253+, TPM2 hardware enabled in BIOS, `tpm2-tss` package.

```bash
sudo dnf install tpm2-tss tpm2-tools

# 1. Enroll combined TPM2 + YubiKey
sudo ./enroll-tpm-fido2.sh /dev/nvme0n1p3

# 2. Patch crypttab for combined mode
sudo ./patch-crypttab.sh --mode tpm2-fido2

# 3. Regenerate initramfs
sudo dracut -f

# 4. Reboot and test
```

Options:
```bash
# Custom PCR policy (bind to Secure Boot + shim)
sudo ./enroll-tpm-fido2.sh --tpm2-pcrs 7+14 /dev/nvme0n1p3

# Add TPM2 PIN for 4-factor authentication
sudo ./enroll-tpm-fido2.sh --tpm2-with-pin /dev/nvme0n1p3
```

**Note:** If TPM2 PCRs change (firmware update, Secure Boot policy change), the keyslot stops working. Always keep a passphrase slot as fallback. Re-enroll after such changes.

To remove combined keyslots:
```bash
sudo ./unenroll.sh --tpm2-fido2 /dev/nvme0n1p3
sudo dracut -f
```

## License

MIT
