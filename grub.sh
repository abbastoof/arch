#!/bin/bash
set -e

echo "==> Installing GRUB, efibootmgr, os-prober..."
pacman -Sy --noconfirm grub efibootmgr os-prober

# Make sure /boot/grub exists
if [ ! -d /boot/grub ]; then
    echo "==> Creating /boot/grub..."
    mkdir -p /boot/grub
fi

# Clean up invalid /boot/efi/grub if present
if [ -d /boot/efi/grub ]; then
    echo "==> Removing unnecessary /boot/efi/grub..."
    rm -rf /boot/efi/grub
fi

# Enable os-prober support in GRUB
echo "==> Enabling os-prober support..."
GRUB_CONFIG="/etc/default/grub"
if grep -q "^#?GRUB_DISABLE_OS_PROBER=.*" "$GRUB_CONFIG"; then
    sudo sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_CONFIG"
else
    echo "GRUB_DISABLE_OS_PROBER=false" >> "$GRUB_CONFIG"
fi

# Reinstall GRUB to the EFI partition
echo "==> Installing GRUB bootloader to /boot/efi/EFI/Arch..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch --recheck

# Generate GRUB config with OS detection
echo "==> Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Done! GRUB is installed, os-prober enabled, and config generated."
