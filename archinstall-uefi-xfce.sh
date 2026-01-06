#!/bin/bash
set -euo pipefail

# ==============================================================================
# Arch Linux: UEFI + LUKS (root) + GRUB (ThinkPad-safe) + XFCE desktop
#
# Boot flow on ThinkPad T420:
#   BIOS -> GRUB (UEFI fallback path) -> LUKS passphrase -> XFCE desktop (LightDM)
#
# WARNING: This wipes the target DISK.
# ==============================================================================

# ---- CONFIG (edit if needed) ----
DISK="/dev/sda"                 # ThinkPad T420 internal bay is usually /dev/sda
CRYPT_NAME="cryptroot"
HOSTNAME="archbox"
LOCALE="en_US.UTF-8"
TIMEZONE="America/New_York"
KEYMAP="us"

# Desktop + common tools (based on your original package list) :contentReference[oaicite:1]{index=1}
PACKAGES=(
  base linux linux-firmware
  bash curl openssh mc git wget
  vim nano
  p7zip rsync which
  sudo networkmanager
  grub efibootmgr
  intel-ucode

  # Desktop stack
  xorg xorg-xinit
  xfce4 xfce4-goodies
  lightdm lightdm-gtk-greeter
  firefox

  # Optional utilities (safe defaults)
  ufw
  pipewire pipewire-pulse wireplumber
)

# ---- SAFETY CHECKS ----
if [[ ! -d /sys/firmware/efi ]]; then
  echo "[!] Not booted in UEFI mode."
  echo "    Reboot and choose the UEFI entry for your USB installer (F12)."
  exit 1
fi

if [[ ! -b "$DISK" ]]; then
  echo "[!] DISK '$DISK' not found. Edit DISK=... at top."
  lsblk
  exit 1
fi

# Partition naming helper (nvme0n1p1 vs sda1)
part() {
  local n="$1"
  if [[ "$DISK" =~ nvme|mmcblk ]]; then
    echo "${DISK}p${n}"
  else
    echo "${DISK}${n}"
  fi
}

EFI_PART="$(part 1)"
LUKS_PART="$(part 2)"

echo
echo "[+] Target disk: $DISK"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT "$DISK" || true
echo

read -rp "This will WIPE ${DISK}. Type YES to continue: " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

read -rp "Enter username to create: " USERNAME

# One password entry with confirm loop: used for BOTH root and user (reliable for installs)
while true; do
  read -rsp "Enter password for ${USERNAME} (and root): " PASS1; echo
  read -rsp "Retype password: " PASS2; echo
  [[ "$PASS1" == "$PASS2" ]] && break
  echo "[!] Passwords did not match. Try again."
done

echo "[+] Partitioning (GPT + ESP + LUKS)"
sgdisk --zap-all "$DISK"
sgdisk -o "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" "$DISK"
sgdisk -n 2:0:0     -t 2:8309 -c 2:"Linux LUKS"           "$DISK"
sleep 2

echo "[+] Formatting ESP (FAT32): $EFI_PART"
mkfs.fat -F32 "$EFI_PART"

echo "[+] Setting up LUKS on: $LUKS_PART"
cryptsetup luksFormat "$LUKS_PART"
cryptsetup open "$LUKS_PART" "$CRYPT_NAME"
mkfs.ext4 "/dev/mapper/${CRYPT_NAME}"

echo "[+] Mounting root + ESP"
mount "/dev/mapper/${CRYPT_NAME}" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

echo "[+] Installing packages (base + XFCE)"
pacstrap /mnt "${PACKAGES[@]}"

echo "[+] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "[+] Configuring system in chroot"
env \
  TIMEZONE="$TIMEZONE" \
  LOCALE="$LOCALE" \
  KEYMAP="$KEYMAP" \
  HOSTNAME="$HOSTNAME" \
  USERNAME="$USERNAME" \
  PASS1="$PASS1" \
  CRYPT_NAME="$CRYPT_NAME" \
  LUKS_PART="$LUKS_PART" \
  arch-chroot /mnt /bin/bash -euo pipefail <<'CHROOT'
# ---- Time / locale / keymap ----
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

grep -q "^${LOCALE} UTF-8" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# ---- Hostname ----
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
::1       localhost
127.0.1.1 archbox.localdomain archbox
HOSTS
sed -i "s/\<archbox\>/${HOSTNAME}/g" /etc/hosts

# ---- Users / sudo ----
echo "root:${PASS1}" | chpasswd
useradd -m -G wheel -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${PASS1}" | chpasswd

# Safer than editing /etc/sudoers directly
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# ---- Network + Display Manager ----
systemctl enable NetworkManager
systemctl enable lightdm

# ---- mkinitcpio: ensure LUKS prompt exists ----
# encrypt MUST be before filesystems
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# ---- GRUB cmdline: cryptdevice + root ----
UUID="$(blkid -s UUID -o value "${LUKS_PART}")"
if [[ -z "${UUID}" ]]; then
  echo "[!] Could not read UUID for ${LUKS_PART}"
  exit 1
fi
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${UUID}:${CRYPT_NAME} root=/dev/mapper/${CRYPT_NAME}\"|" /etc/default/grub

# ---- GRUB install: ThinkPad-safe fallback path ----
# This avoids unreliable NVRAM entries on older firmware.
mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
mkdir -p /boot/EFI
grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot \
  --bootloader-id=BOOT \
  --removable \
  --recheck \
  --no-nvram

grub-mkconfig -o /boot/grub/grub.cfg

# ---- Firewall (safe default) ----
ufw default deny incoming
ufw default allow outgoing
ufw enable
systemctl enable ufw

# ---- Proof output (helps debug if needed) ----
echo "[+] EFI loader path should exist:"
ls -l /boot/EFI/BOOT/BOOTX64.EFI || true
CHROOT

echo "[+] Cleanup"
umount -R /mnt
cryptsetup close "${CRYPT_NAME}"

echo "[✓] Done."
echo "    BIOS suggestion (T420): UEFI/Legacy Boot=Both, Priority=UEFI First, Secure Boot=Disabled."
echo "    Boot should go: GRUB -> LUKS prompt -> LightDM -> XFCE."
