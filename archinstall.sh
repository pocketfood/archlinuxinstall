#!/bin/bash
set -e

# === USER CONFIG ===
DISK="/dev/sda"
CRYPT_NAME="cryptroot"
HOSTNAME="archbox"
LOCALE="en_US.UTF-8"
TIMEZONE="UTC"
KEYMAP="us"

# === PROMPT FOR USERNAME ===
read -p "Enter username to create: " USERNAME

# === PACKAGE LIST ===
MY_PACKAGES=(
  base linux linux-firmware
  bash curl openssh mc git wget
  vim nano nmap openvpn openssl
  p7zip rsync vlc which whois
  xclip xarchiver sudo ufw
  networkmanager grub efibootmgr
  xorg xorg-xinit xfce4 xfce4-goodies
  lightdm lightdm-gtk-greeter firefox
)

# === PARTITIONING ===
echo "[+] Wiping disk ${DISK}"
sgdisk --zap-all "$DISK"
sgdisk -o "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"Linux LUKS" "$DISK"
sleep 2

# === FORMATTING ===
echo "[+] Formatting partitions"
mkfs.fat -F32 "${DISK}1"

echo "[+] Setting up LUKS (you will be prompted)"
cryptsetup luksFormat "${DISK}2"
cryptsetup open "${DISK}2" "${CRYPT_NAME}"
mkfs.ext4 /dev/mapper/${CRYPT_NAME}

# === MOUNTING ===
echo "[+] Mounting filesystem"
mount /dev/mapper/${CRYPT_NAME} /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# === INSTALL BASE SYSTEM ===
echo "[+] Installing base system and desktop"
pacstrap /mnt "${MY_PACKAGES[@]}"

# === FSTAB ===
echo "[+] Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# === CONFIGURATION INSIDE CHROOT ===
echo "[+] Configuring system"
arch-chroot /mnt /bin/bash <<EOF
# Timezone and Clock
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locale
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# Root password
echo "[+] Set root password"
passwd root

# User account
echo "[+] Create user: ${USERNAME}"
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo "[+] Set password for ${USERNAME}"
passwd ${USERNAME}
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# mkinitcpio with LUKS
echo "[+] Configure mkinitcpio for LUKS"
sed -i 's/^HOOKS=(.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB with cryptdevice
UUID=\$(blkid -s UUID -o value ${DISK}2)
sed -i "s/GRUB_CMDLINE_LINUX=\".*\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$UUID:${CRYPT_NAME}\"/" /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable NetworkManager
systemctl enable lightdm

# Set XFCE as default session
echo "exec startxfce4" > /home/${USERNAME}/.xinitrc
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.xinitrc

# UFW paranoid firewall + DNS leak protection
echo "[+] Configuring UFW (Paranoid Mode)"
ufw default deny incoming
ufw default allow outgoing
ufw deny proto icmp

# Static DNS (Cloudflare) + make resolv.conf immutable
echo "[+] Setting static DNS"
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 1.0.0.1" >> /etc/resolv.conf
chattr +i /etc/resolv.conf

# Kill switch: allow VPN only
ufw allow out on tun0
ufw deny out from any to any

ufw enable
systemctl enable ufw
EOF

# === CLEANUP ===
echo "[+] Cleanup"
umount -R /mnt
cryptsetup close "${CRYPT_NAME}"
echo "[✓] Installation complete. You may now reboot into your encrypted Arch desktop!"
