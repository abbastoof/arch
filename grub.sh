#!/bin/bash

# Exit immediately if any command fails
set -e

echo "Installing grub, efibootmgr, os-prober..."
pacman -S --noconfirm grub efibootmgr os-prober

echo "Enabling os-prober detection in GRUB..."
if ! grep -q "GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
    echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
fi

echo "Making sure /boot/grub directory exists..."
mkdir -p /boot/grub

echo "Installing GRUB to EFI partition..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch --recheck

echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "Done! GRUB is installed and configured with OS detection."
