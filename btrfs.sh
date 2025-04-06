#!/bin/bash
set -e
echo "=== Simple Btrfs Setup Script ==="
# List available disks
echo "Available disks:"
lsblk -d
read -rp "Enter disk name (e.g., nvme0n1, sda): " DISK
SELECTED_DISK="/dev/$DISK"
# Create a new partition interactively using fdisk
echo "Creating a new partition on $SELECTED_DISK..."
echo "Please complete the fdisk prompts to create your partition"
fdisk "$SELECTED_DISK"
# Wait for system to recognize new partition
echo "Waiting for partition changes to be recognized..."
partprobe "$SELECTED_DISK"
sleep 3
# Let user select the newly created partition
echo "Available partitions on $SELECTED_DISK:"
lsblk "$SELECTED_DISK"
read -rp "Enter the partition you just created (e.g., nvme0n1p3): " PART
NEW_PART="/dev/$PART"
# Verify the partition exists
if [ ! -b "$NEW_PART" ]; then
    echo "Error: $NEW_PART is not a valid block device. Aborting."
    exit 1
fi
# Format with BTRFS
echo "Formatting $NEW_PART with BTRFS..."
mkfs.btrfs -f "$NEW_PART"
# First check if /mnt is being used
if mountpoint -q /mnt; then
    echo "/mnt is already mounted. Unmounting..."
    umount -R /mnt 2>/dev/null || true
fi
# Create directories if they don't exist
mkdir -p /mnt
# Create subvolumes
echo "Creating BTRFS subvolumes..."
mount "$NEW_PART" /mnt

# Function to safely create subvolumes
create_subvol() {
    if [ ! -d "/mnt/$1" ]; then
        mkdir -p "/mnt/$1"
    fi
    
    if btrfs subvolume list /mnt | grep -q "$1"; then
        echo "Subvolume $1 already exists, skipping..."
    else
        btrfs subvolume create "/mnt/$1"
    fi
}

# Create subvolumes with error handling
create_subvol @
create_subvol @home
create_subvol @var
create_subvol @log
create_subvol @tmp
create_subvol @pkg
create_subvol @snapshots

umount /mnt
# Create mount points
mkdir -p /mnt
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot/efi}
# Mount subvolumes
echo "Mounting BTRFS subvolumes..."
mount -o noatime,compress=zstd,subvol=@ "$NEW_PART" /mnt
mount -o noatime,compress=zstd,subvol=@home "$NEW_PART" /mnt/home
mount -o noatime,compress=zstd,subvol=@var "$NEW_PART" /mnt/var
mount -o noatime,compress=zstd,subvol=@log "$NEW_PART" /mnt/var/log
mount -o noatime,compress=zstd,subvol=@tmp "$NEW_PART" /mnt/var/tmp
mount -o noatime,compress=zstd,subvol=@pkg "$NEW_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,subvol=@snapshots "$NEW_PART" /mnt/.snapshots
# Mount EFI partition
echo "Available EFI partitions:"
lsblk -f | grep vfat
read -rp "Enter EFI partition (e.g., nvme0n1p1): " EFIPART
mkdir -p /mnt/boot/efi
mount "/dev/$EFIPART" /mnt/boot/efi
echo "✅ Setup complete! Ready for Arch installation."
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
