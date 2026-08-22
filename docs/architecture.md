# System Architecture Document

## FIDO2 YubiKey LUKS2 Integration for Fedora Linux

| Field | Value |
|-------|-------|
| Document ID | ARCH-001 |
| Version | 1.0 |
| Status | Approved for Implementation |
| Classification | Technical Architecture |

---

## 1. Purpose and Scope

### 1.1 Purpose

This document defines the system architecture for integrating Yubico YubiKey FIDO2 hardware security tokens with LUKS2 full disk encryption on Fedora Linux. It describes the components, interfaces, data flows, and security boundaries involved in using a YubiKey as a second authentication factor for disk unlock at boot time.

### 1.2 Scope

- FIDO2/CTAP2 credential enrollment into LUKS2 token metadata via `systemd-cryptenroll`
- Boot-time unlock via `systemd-cryptsetup` with FIDO2 device auto-detection
- Multi-key enrollment for operational redundancy
- Passphrase fallback for recovery scenarios

### 1.3 Out of Scope (Planned Future Work)

- TPM2 + FIDO2 combined binding (planned for v2)
- Remote/network-based unlock
- YubiKey HMAC-SHA1 challenge-response mode (legacy approach)

---

## 2. Reference Documents

### 2.1 Vendor Documentation

| Source | Document | URL |
|--------|----------|-----|
| Yubico | YubiKey 5 Series Technical Manual | https://docs.yubico.com/hardware/yubikey-5-overview.html |
| Yubico | FIDO2/WebAuthn Overview | https://developers.yubico.com/FIDO2/ |
| Yubico | CTAP2 Client PIN Specification | https://developers.yubico.com/FIDO2/Concepts/CTAP2_Client_PIN.html |
| Yubico | YubiKey Manager CLI Guide | https://docs.yubico.com/software/yubikey/tools/ykman/ |
| Red Hat | LUKS2 Disk Encryption (RHEL 9) | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/encrypting-block-devices-using-luks |
| Red Hat | systemd-cryptenroll Manual | https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html |
| Red Hat | Configuring LUKS with FIDO2 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/unlocking-a-luks-encrypted-volume-by-a-fido2-key |
| Fedora | Full Disk Encryption Guide | https://docs.fedoraproject.org/en-US/quick-docs/encrypting-drives-using-LUKS/ |
| FIDO Alliance | CTAP2.1 Specification | https://fidoalliance.org/specs/fido-v2.1-ps-20210615/fido-client-to-authenticator-protocol-v2.1-ps-20210615.html |

### 2.2 Standards

| Standard | Description |
|----------|-------------|
| FIDO2 CTAP2.1 | Client to Authenticator Protocol — defines USB/NFC/BLE communication between host and authenticator |
| WebAuthn Level 2 | W3C standard for web authentication using public key credentials |
| LUKS2 On-Disk Format | Linux Unified Key Setup version 2 specification (extensible token metadata) |
| PKCS#5 / PBKDF2 | Password-based key derivation for passphrase keyslots |
| AES-256-XTS | Default cipher for LUKS2 data encryption |

---

## 3. System Context

### 3.1 System Context Diagram

```plantuml
@startuml system-context
!theme plain
skinparam backgroundColor #FFFFFF

title System Context — FIDO2 YubiKey LUKS2 Integration

actor "System Administrator" as admin
rectangle "YubiKey 5\n(FIDO2 Authenticator)" as yubikey #LightBlue
rectangle "Fedora Linux System" as system {
    rectangle "LUKS2 Encrypted\nBlock Device" as luks
    rectangle "systemd-cryptenroll\n& systemd-cryptsetup" as systemd
    rectangle "Enrollment Scripts\n(this project)" as scripts
}

admin --> scripts : Runs enrollment
admin --> yubikey : Touches & enters PIN
yubikey <--> systemd : CTAP2 over USB HID
scripts --> systemd : Invokes enrollment
systemd --> luks : Manages keyslots\n& token metadata
@enduml
```

### 3.2 Stakeholders

| Stakeholder | Role | Concern |
|-------------|------|---------|
| System Administrator | Enrolls keys, manages disk encryption | Usability, key management |
| End User | Boots system daily | Boot speed, fallback availability |
| Security Auditor | Reviews encryption posture | Compliance, key strength, attack surface |
| IT Operations | Manages fleet of machines | Multi-key support, recovery procedures |

---

## 4. Component Architecture

### 4.1 Component Diagram

```plantuml
@startuml component-architecture
!theme plain
skinparam backgroundColor #FFFFFF

title Component Architecture — FIDO2 YubiKey LUKS2

package "User Space — Enrollment" {
    [enroll.sh] as enroll
    [unenroll.sh] as unenroll
    [patch-crypttab.sh] as patchcrypt
}

package "System Services" {
    [systemd-cryptenroll] as cryptenroll
    [systemd-cryptsetup] as cryptsetup_svc
    [dracut initramfs] as dracut
}

package "Kernel / Hardware" {
    [dm-crypt] as dmcrypt
    [USB HID Driver] as usbhid
    [Block Device\n(NVMe/SATA)] as blockdev
}

package "External Hardware" {
    [YubiKey 5\nFIDO2 Authenticator] as yubikey
}

database "LUKS2 Header" as luksheader {
    [Keyslot 0\n(Passphrase)] as ks0
    [Keyslot 1..N\n(FIDO2)] as ks1n
    [Token Metadata\n(fido2 credentials)] as tokenmeta
}

enroll --> cryptenroll : invokes
unenroll --> dmcrypt : luksKillSlot
patchcrypt --> dracut : triggers rebuild

cryptenroll --> yubikey : CTAP2\nmakeCredential
cryptenroll --> luksheader : writes keyslot\n& token metadata
cryptsetup_svc --> yubikey : CTAP2\ngetAssertion
cryptsetup_svc --> luksheader : reads token,\nunlocks keyslot
cryptsetup_svc --> dmcrypt : provides\nmaster key

dmcrypt --> blockdev : encrypted I/O
yubikey <--> usbhid : USB HID

dracut ..> cryptsetup_svc : includes in\ninitramfs
@enduml
```

### 4.2 Component Descriptions

| Component | Type | Responsibility |
|-----------|------|---------------|
| `enroll.sh` | Shell script | Validates device, detects YubiKey, invokes `systemd-cryptenroll` with FIDO2+PIN options |
| `unenroll.sh` | Shell script | Identifies and removes FIDO2 keyslots from LUKS2 header |
| `patch-crypttab.sh` | Shell script | Adds `fido2-device=auto` to `/etc/crypttab` entries, triggers initramfs rebuild |
| `systemd-cryptenroll` | System binary | Creates FIDO2 credentials on the YubiKey and stores the credential ID + salt in LUKS2 token metadata; derives and stores a key in a LUKS2 keyslot |
| `systemd-cryptsetup` | System service | At boot, reads LUKS2 token metadata, performs FIDO2 assertion with YubiKey, derives the keyslot unlock key |
| `dracut` | Initramfs generator | Packages FIDO2 libraries (`libfido2`) and `systemd-cryptsetup` into the initial boot environment |
| `dm-crypt` | Kernel module | Transparent block-level encryption/decryption using the master key |
| YubiKey 5 | Hardware | FIDO2 authenticator; generates and stores private keys in secure element; performs CTAP2 operations |

---

## 5. Data Flow Architecture

### 5.1 Enrollment Sequence

```plantuml
@startuml enrollment-sequence
!theme plain
skinparam backgroundColor #FFFFFF

title Enrollment Sequence — FIDO2 YubiKey into LUKS2

actor "Admin" as admin
participant "enroll.sh" as script
participant "systemd-cryptenroll" as cryptenroll
participant "YubiKey\n(FIDO2)" as yubikey
participant "LUKS2 Header" as luks

admin -> script : sudo ./enroll.sh /dev/nvme0n1p3
activate script

script -> script : Validate: LUKS2, root, block device
script -> script : fido2-token -L (detect YubiKey)

script -> cryptenroll : --fido2-device=auto\n--fido2-with-client-pin=yes
activate cryptenroll

cryptenroll -> admin : Prompt: existing LUKS passphrase
admin -> cryptenroll : enters passphrase
cryptenroll -> luks : Verify passphrase\n(unlock existing keyslot)

cryptenroll -> yubikey : CTAP2 makeCredential\n(relying party = "io.systemd.cryptsetup")
activate yubikey
yubikey -> admin : Prompt: YubiKey PIN
admin -> yubikey : enters PIN
yubikey -> admin : Prompt: touch YubiKey
admin -> yubikey : touches
yubikey -> yubikey : Generate key pair\nin secure element
yubikey --> cryptenroll : credential ID + public key
deactivate yubikey

cryptenroll -> cryptenroll : Derive keyslot key\nfrom FIDO2 hmac-secret
cryptenroll -> luks : Write new keyslot\n(encrypted master key)
cryptenroll -> luks : Write token metadata\n(credential ID, salt, RP ID)

cryptenroll --> script : success
deactivate cryptenroll

script --> admin : Enrollment complete\nNext: patch-crypttab, dracut -f
deactivate script
@enduml
```

### 5.2 Boot Unlock Sequence

```plantuml
@startuml boot-unlock-sequence
!theme plain
skinparam backgroundColor #FFFFFF

title Boot Unlock Sequence — FIDO2 YubiKey LUKS2

participant "UEFI/BIOS" as bios
participant "GRUB2\nBootloader" as grub
participant "dracut\ninitramfs" as initramfs
participant "systemd-cryptsetup" as cryptsetup
participant "YubiKey\n(FIDO2)" as yubikey
participant "LUKS2 Header" as luks
participant "dm-crypt" as dmcrypt
actor "User" as user

bios -> grub : Load bootloader
grub -> initramfs : Load kernel + initramfs

initramfs -> cryptsetup : Start cryptsetup service\n(reads /etc/crypttab)
activate cryptsetup

cryptsetup -> luks : Read LUKS2 header\n& token metadata
cryptsetup -> cryptsetup : Found fido2 token?\nYes — try FIDO2 first

cryptsetup -> yubikey : CTAP2 getAssertion\n(credential ID from token metadata)
activate yubikey

yubikey -> user : Prompt: PIN
user -> yubikey : enters PIN
yubikey -> user : Prompt: touch
user -> yubikey : touches
yubikey -> yubikey : Sign challenge with\nprivate key (secure element)
yubikey --> cryptsetup : assertion + hmac-secret output
deactivate yubikey

cryptsetup -> cryptsetup : Derive keyslot key\nfrom hmac-secret
cryptsetup -> luks : Unlock keyslot\n(decrypt master key)
cryptsetup -> dmcrypt : Provide master key\n(activate dm-crypt mapping)

dmcrypt --> initramfs : Root filesystem available
initramfs -> initramfs : Switch root\nContinue boot

deactivate cryptsetup

note over cryptsetup
  If YubiKey is absent or fails:
  Falls back to passphrase prompt
end note
@enduml
```

### 5.3 Multi-Key Enrollment

```plantuml
@startuml multi-key
!theme plain
skinparam backgroundColor #FFFFFF

title Multi-Key LUKS2 Keyslot Layout

rectangle "LUKS2 Header" {
    rectangle "Keyslot 0\nType: passphrase\nPBKDF: argon2id" as ks0 #LightGreen
    rectangle "Keyslot 1\nType: FIDO2\nYubiKey #1 (Primary)" as ks1 #LightBlue
    rectangle "Keyslot 2\nType: FIDO2\nYubiKey #2 (Backup)" as ks2 #LightBlue
    rectangle "Token 0\nType: systemd-fido2\ncredential_id: <key1_id>\nsalt: <random>" as t0 #LightYellow
    rectangle "Token 1\nType: systemd-fido2\ncredential_id: <key2_id>\nsalt: <random>" as t1 #LightYellow
    rectangle "Master Key\n(AES-256)" as mk #Pink
}

ks0 --> mk : decrypts
ks1 --> mk : decrypts
ks2 --> mk : decrypts
t0 --> ks1 : references
t1 --> ks2 : references

note bottom of ks0
  Recovery: always keep
  at least one passphrase
  keyslot active
end note

note bottom of ks2
  Each YubiKey enrollment
  creates an independent
  keyslot + token pair
end note
@enduml
```

---

## 6. Interface Specifications

### 6.1 External Interfaces

| Interface | Protocol | Direction | Description |
|-----------|----------|-----------|-------------|
| YubiKey USB | CTAP2 over USB HID | Bidirectional | FIDO2 credential creation and assertion |
| LUKS2 Header | On-disk format | Read/Write | Keyslot and token metadata storage |
| `/etc/crypttab` | Text configuration | Read (at boot) | Tells systemd which devices to unlock and how |
| dracut initramfs | Binary image | Generated | Contains all libraries/binaries needed at boot |

### 6.2 CTAP2 Protocol Flow

```plantuml
@startuml ctap2-flow
!theme plain
skinparam backgroundColor #FFFFFF

title CTAP2 Protocol Messages — FIDO2 Enrollment & Unlock

participant "Host\n(systemd-cryptenroll)" as host
participant "YubiKey\n(Authenticator)" as auth

== Enrollment (makeCredential) ==

host -> auth : authenticatorClientPIN\n(getPINToken with PIN)
auth --> host : pinToken

host -> auth : authenticatorMakeCredential\n  rpId: "io.systemd.cryptsetup"\n  user: { id: <device-uuid> }\n  extensions: { hmac-secret: true }\n  options: { rk: false, uv: true }
auth -> auth : Generate P-256 key pair\nStore in secure element
auth --> host : attestation object\n  credentialId\n  publicKey\n  hmac-secret enabled

== Boot Unlock (getAssertion) ==

host -> auth : authenticatorClientPIN\n(getPINToken with PIN)
auth --> host : pinToken

host -> auth : authenticatorGetAssertion\n  rpId: "io.systemd.cryptsetup"\n  allowList: [{ credentialId }]\n  extensions: {\n    hmac-secret: {\n      salt: <from LUKS2 token>\n    }\n  }
auth -> auth : Sign with private key\nCompute HMAC(salt, credential-key)
auth --> host : assertion\n  signature\n  hmac-secret output (32 bytes)

host -> host : Use hmac-secret output\nas LUKS2 keyslot passphrase
@enduml
```

---

## 7. Security Architecture

### 7.1 Threat Model

```plantuml
@startuml threat-model
!theme plain
skinparam backgroundColor #FFFFFF

title Threat Model — FIDO2 YubiKey LUKS2

rectangle "Assets" #LightGreen {
    (Disk Master Key) as mk
    (User Data on Disk) as data
    (YubiKey Private Key) as privkey
    (FIDO2 PIN) as pin
}

rectangle "Threats" #LightCoral {
    (T1: Stolen Laptop\n— disk removed) as t1
    (T2: Stolen YubiKey\n— no PIN) as t2
    (T3: Evil Maid\n— boot tampering) as t3
    (T4: Cold Boot\n— RAM extraction) as t4
    (T5: Keyslot\nBrute Force) as t5
}

rectangle "Mitigations" #LightBlue {
    (M1: AES-256-XTS\ndisk encryption) as m1
    (M2: FIDO2 PIN\nrequirement) as m2
    (M3: Secure Boot +\nTPM binding — v2) as m3
    (M4: RAM encryption\n— kernel support) as m4
    (M5: argon2id PBKDF\nfor passphrase slot) as m5
}

t1 --> m1 : mitigated by
t2 --> m2 : mitigated by
t3 --> m3 : mitigated by (future)
t4 --> m4 : mitigated by
t5 --> m5 : mitigated by

mk --> data : protects
privkey --> mk : unlocks (via FIDO2)
pin --> privkey : gates access to
@enduml
```

### 7.2 Security Boundaries

| Boundary | Inside | Outside | Protection |
|----------|--------|---------|------------|
| YubiKey Secure Element | Private keys, PIN retry counter | Host software | Hardware isolation, tamper resistance |
| LUKS2 Header | Encrypted master key, token metadata | Unencrypted disk | AES key wrapping, argon2id |
| Initramfs | Boot-time unlock logic | User space | Signed kernel + Secure Boot (recommended) |
| PIN | User's knowledge | All other factors | Rate-limited on YubiKey (8 retries, then lockout) |

### 7.3 Authentication Factors

| Factor | Type | Component | Compromise Impact |
|--------|------|-----------|-------------------|
| YubiKey possession | Something you have | Hardware token | Attacker needs PIN to use |
| FIDO2 PIN | Something you know | Entered at boot | Attacker needs the physical key |
| Touch confirmation | Something you do | Capacitive sensor | Prevents remote/malware use of inserted key |
| TPM platform binding (v2) | Something you are (platform) | TPM 2.0 PCR values | Prevents boot from tampered system |

---

## 8. Deployment Architecture

### 8.1 Deployment Diagram

```plantuml
@startuml deployment
!theme plain
skinparam backgroundColor #FFFFFF

title Deployment Architecture — Fedora Linux with FIDO2 LUKS2

node "Fedora Linux Workstation" {
    artifact "/boot/efi\n(EFI System Partition)" as esp
    artifact "/boot\n(ext4, unencrypted)" as boot

    node "LUKS2 Encrypted Partition\n/dev/nvme0n1p3" as lukspart {
        artifact "dm-crypt mapping\n/dev/mapper/luks-<uuid>" as dmmap
        artifact "LVM or Btrfs\nRoot Filesystem" as rootfs
    }

    artifact "/etc/crypttab" as crypttab
    artifact "/etc/dracut.conf.d/" as dracutconf

    component "systemd-cryptsetup\n(in initramfs)" as cryptsetup
    component "libfido2.so\n(in initramfs)" as libfido2
}

node "YubiKey 5 NFC" as yubikey {
    component "FIDO2 App\n(CTAP2)" as fido2app
    component "Secure Element\n(SLE78)" as se
}

cloud "USB Port" as usb

cryptsetup --> crypttab : reads config
cryptsetup --> lukspart : reads header
cryptsetup <--> libfido2 : FIDO2 API
libfido2 <--> usb : USB HID
usb <--> yubikey

esp --> boot : chainloads
boot --> cryptsetup : kernel loads initramfs

note right of se
  Private keys never
  leave the secure element.
  PIN is verified on-device.
end note
@enduml
```

### 8.2 File Layout

```
/
├── etc/
│   ├── crypttab                        # fido2-device=auto entry
│   └── dracut.conf.d/
│       └── fido2.conf                  # (optional) force inclusion
├── usr/
│   └── lib/
│       └── systemd/
│           ├── systemd-cryptsetup      # boot-time unlock binary
│           └── system/
│               └── systemd-cryptsetup@.service
├── boot/
│   └── initramfs-<version>.img         # contains libfido2 + cryptsetup
└── dev/
    ├── nvme0n1p3                       # LUKS2 encrypted partition
    └── mapper/
        └── luks-<uuid>                 # decrypted block device
```

---

## 9. State Machine

### 9.1 LUKS2 Device States

```plantuml
@startuml state-machine
!theme plain
skinparam backgroundColor #FFFFFF

title LUKS2 Device State Machine

[*] --> Locked : System power on

state Locked {
    [*] --> WaitingForToken : cryptsetup reads header
    WaitingForToken --> FIDO2Detected : YubiKey inserted
    WaitingForToken --> PassphrasePrompt : No FIDO2 device\n(timeout)
    FIDO2Detected --> PINEntry : CTAP2 getAssertion
    PINEntry --> TouchWait : PIN verified
    PINEntry --> PINRetry : Wrong PIN\n(max 8 retries)
    PINRetry --> PINEntry : retry
    PINRetry --> PassphrasePrompt : PIN locked out
    TouchWait --> KeyslotUnlock : Touch confirmed
}

state Unlocked {
    [*] --> Active : dm-crypt mapping created
    Active --> Mounted : Root filesystem mounted
}

KeyslotUnlock --> Unlocked : Master key decrypted
PassphrasePrompt --> Unlocked : Correct passphrase

Unlocked --> [*] : System shutdown

note right of PINRetry
  YubiKey locks FIDO2 app
  after 8 consecutive
  wrong PIN attempts.
  Requires reset to recover.
end note
@enduml
```

---

## 10. Future Architecture: TPM + FIDO2

### 10.1 Planned v2 Architecture

```plantuml
@startuml tpm-fido2-future
!theme plain
skinparam backgroundColor #FFFFFF

title Future Architecture — TPM2 + FIDO2 Combined Binding (v2)

rectangle "Three-Factor Unlock" {
    rectangle "Factor 1: Platform\nTPM2 PCR Binding\n(Secure Boot chain)" as f1 #LightGreen
    rectangle "Factor 2: Possession\nYubiKey FIDO2\n(Hardware token)" as f2 #LightBlue
    rectangle "Factor 3: Knowledge\nFIDO2 PIN\n(User secret)" as f3 #LightYellow
}

rectangle "LUKS2 Keyslot\n(combined policy)" as ks #Pink

f1 --> ks : TPM unseal\n(PCR 7,11,14)
f2 --> ks : FIDO2 hmac-secret
f3 --> f2 : gates authenticator

note bottom of ks
  systemd-cryptenroll --tpm2-device=auto --fido2-device=auto
  NOT YET IMPLEMENTED — requires systemd 256+ and
  policy composition support in cryptenroll
end note
@enduml
```

### 10.2 TPM+FIDO2 Design Considerations

| Consideration | Detail |
|---------------|--------|
| PCR Policy | Bind to PCR 7 (Secure Boot), 11 (systemd-stub), 14 (shim MOK) |
| Composition | TPM unseal provides first key half; FIDO2 provides second |
| Fallback | If TPM PCRs change (kernel update), passphrase still works |
| Enrollment | Requires two sequential enrollment steps or combined systemd-cryptenroll call |
| systemd version | Requires systemd 256+ for combined FIDO2+TPM2 in single keyslot |

---

## Appendix A: Glossary

| Term | Definition |
|------|-----------|
| LUKS2 | Linux Unified Key Setup version 2 — on-disk format for encrypted block devices supporting extensible token metadata |
| FIDO2 | Fast Identity Online 2 — authentication standard using public-key cryptography with hardware authenticators |
| CTAP2 | Client to Authenticator Protocol version 2 — defines communication between host and FIDO2 authenticator over USB/NFC/BLE |
| hmac-secret | FIDO2 extension that computes HMAC-SHA-256 of a salt using a per-credential key on the authenticator |
| Keyslot | LUKS2 slot containing an encrypted copy of the master key, protected by a passphrase or other secret |
| Token Metadata | LUKS2 extensible metadata area storing auxiliary data (e.g., FIDO2 credential ID and salt) |
| dm-crypt | Linux kernel module providing transparent block-level encryption |
| PCR | Platform Configuration Register — TPM measurement register reflecting boot chain integrity |
| argon2id | Memory-hard password hashing function used by LUKS2 for passphrase key derivation |
| Secure Element | Tamper-resistant hardware component in YubiKey that stores and operates on private keys |
