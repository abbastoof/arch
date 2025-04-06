#!/bin/bash
set -e
echo "=== Robust Btrfs Setup Script ==="

# List available disks
echo "Available disks:"
lsblk -d
read -rp "Enter disk name (e.g., nvme0n1, sda): " DISK
SELECTED_DISK="/dev/$DISK"

# Confirm disk selection
read -rp "WARNING: All data on $SELECTED_DISK will be lost! Continue? (y/N): " confirm
if [[ ! $confirm =~ [yY] ]]; then
    echo "Aborting."
    exit 1
fi

# Create partition with parted
echo "Creating a new Btrfs partition on $SELECTED_DISK..."
parted "$SELECTED_DISK" --script mklabel gpt
parted "$SELECTED_DISK" --script mkpart primary btrfs 1MiB 100%

# Wait for partition detection
echo "Waiting for partition creation..."
for _ in {1..10}; do
    if lsblk "$SELECTED_DISK" | grep -q part; then
        break
    fi
    sleep 1
done

# Get largest partition (newly created)
PART=$(lsblk -nlo NAME "$SELECTED_DISK" | tail -1)
NEW_PART="/dev/$PART"

# Verify partition exists
if [ ! -b "$NEW_PART" ]; then
    echo "Error: Failed to detect new partition. Aborting."
    exit 1
fi

# Format with BTRFS
echo "Formatting $NEW_PART with BTRFS..."
mkfs.btrfs -f --label ARCH "$NEW_PART"

# Prepare mount point
umount -R /mnt 2>/dev/null || true
mkdir -p /mnt

# Create base subvolumes
mount "$NEW_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Create directory structure
mkdir -p /mnt/{boot/efi,home,var/{log,tmp,cache/pacman/pkg},.snapshots}

# Mount with optimized options
mount -o noatime,compress=zstd:3,space_cache=v2,subvol=@ "$NEW_PART" /mnt
mount -o noatime,compress=zstd:3,subvol=@home "$NEW_PART" /mnt/home
mount -o noatime,compress=zstd:3,subvol=@var "$NEW_PART" /mnt/var
mount -o noatime,compress=zstd:3,subvol=@log "$NEW_PART" /mnt/var/log
mount -o noatime,subvol=@tmp "$NEW_PART" /mnt/var/tmp
mount -o noatime,subvol=@pkg "$NEW_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd:3,subvol=@snapshots "$NEW_PART" /mnt/.snapshots

# Mount EFI partition
while true; do
    echo "Available EFI partitions:"
    lsblk -f | awk '/vfat/ {print $1,$2,$4}'
    read -rp "Enter EFI partition (e.g., nvme0n1p1): " EFIPART
    EFI_CHECK="/dev/$EFIPART"
    
    if ! lsblk -f "$EFI_CHECK" | grep -q vfat; then
        echo "Error: $EFI_CHECK is not a FAT32 partition."
    else
        mkdir -p /mnt/boot/efi
        mount "$EFI_CHECK" /mnt/boot/efi && break
    fi
done

echo "✅ Setup complete! System ready for installation."
echo "➡ Recommended next steps:"
echo "1. pacstrap /mnt base linux linux-firmware"
echo "2. genfstab -U /mnt >> /mnt/etc/fstab"
echo "3. arch-chroot /mnt"
