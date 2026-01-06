# Arch Install Scripts (Legacy BIOS + UEFI / LUKS / Desktop)

This repository contains repeatable Arch Linux installation scripts and Flipper Zero BadUSB (DuckyScript) payloads for different hardware/boot scenarios.

The goal is a predictable “wipe-and-reinstall” workflow for disposable systems.

## WARNING

These scripts **WIPE THE TARGET DISK**. They are destructive by design.

- Double-check the target disk (`/dev/sda`, `/dev/nvme0n1`, etc.) before running.
- These scripts are intended for machines where data is disposable or backed up.
- Use at your own risk.

---

## What’s in this repo

Typical layout (adjust to match your filenames):

---


---

## Choose the right installer

### 1) Legacy BIOS machines (no UEFI)
Use this when the device is **Legacy-only** (or you intentionally want BIOS boot).

- Script: `scripts/archinstall-legacy.sh`
- Ducky:  `ducky/flipper-legacy.txt`

Notes:
- Boot the Arch ISO in **Legacy** mode.
- Bootloader setup will be BIOS/MBR-style (or BIOS GRUB on GPT depending on script).

### 2) UEFI machines (recommended) — UEFI + LUKS + Desktop
Use this when the device supports UEFI. This is the most reliable modern install pattern.

- Script: `scripts/archinstall-uefi-luks-xfce.sh`
- Ducky:  `ducky/flipper-uefi-luks-xfce.txt`

Boot flow:
**BIOS → GRUB (UEFI) → LUKS passphrase → LightDM → XFCE desktop**

ThinkPad T420 note:
- Older firmware can ignore NVRAM boot entries.
- The UEFI script installs GRUB to the **fallback path** (`EFI/BOOT/BOOTX64.EFI`) using `--removable` + `--no-nvram` so it boots reliably.

---

## Prerequisites

### Hardware / BIOS
- Secure Boot: **Disabled** (recommended for simplicity)
- If the machine has both UEFI + Legacy options:
  - Set **UEFI first** if using the UEFI installers.
- For ThinkPad T420 specifically:
  - `UEFI/Legacy Boot: Both`
  - `UEFI/Legacy Priority: UEFI First`

### Arch ISO environment
- Boot the Arch ISO in the same mode as your installer:
  - UEFI installer → boot ISO as **UEFI**
  - Legacy installer → boot ISO as **Legacy**
- Network access (Ethernet is easiest). If using Wi-Fi, connect first with `iwctl`.

---

## Running the shell scripts (manual)

1. Boot into the Arch ISO
2. (Optional) Confirm the target disk:
   ```sh
   lsblk

---


chmod +x ./archinstall-*.sh
./archinstall-*.sh


