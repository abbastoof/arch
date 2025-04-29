#!/bin/bash
set -e

# Variables
EFI_DIR="/boot/efi"
BOOTLOADER_ID="arch"

echo "==> Installing required packages (grub, efibootmgr, os-prober)..."
pacman -Sy --noconfirm grub efibootmgr os-prober

echo "==> Enabling os-prober in GRUB configuration..."
if ! grep -q 'GRUB_DISABLE_OS_PROBER=false' /etc/default/grub; then
    echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
fi

echo "==> Creating /boot/grub directory if it doesn't exist..."
mkdir -p /boot/grub

echo "==> Installing GRUB to EFI partition..."
grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" --bootloader-id="$BOOTLOADER_ID" --recheck

echo "==> Generating grub.cfg..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Done! GRUB setup complete. Multiboot ready."
