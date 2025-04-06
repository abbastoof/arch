#!/bin/bash
set -e
echo "=== Simple Btrfs Setup Script ==="

# List available disks
echo "Available disks:"
lsblk -d
read -rp "Enter disk name (e.g., nvme0n1, sda): " DISK
SELECTED_DISK="/dev/$DISK"

# Create a new partition using fdisk
echo "Creating a new partition on $SELECTED_DISK..."
fdisk "$SELECTED_DISK" <<EOF
n



w
EOF

# Wait for system to recognize new partition
partprobe "$SELECTED_DISK"
sleep 2

# Get the newly created partition
NEW_PART=$(lsblk -pno NAME "$SELECTED_DISK" | grep -v "$SELECTED_DISK$" | tail -n 1)
echo "Created partition: $NEW_PART"

# Format with BTRFS
echo "Formatting $NEW_PART with BTRFS..."
mkfs.btrfs -f "$NEW_PART"

# Create subvolumes
echo "Creating BTRFS subvolumes..."
mount "$NEW_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Mount subvolumes
echo "Mounting BTRFS subvolumes..."
mount -o noatime,compress=zstd,subvol=@ "$NEW_PART" /mnt
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot/efi}
mount -o noatime,compress=zstd,subvol=@home "$NEW_PART" /mnt/home
mount -o noatime,compress=zstd,subvol=@var "$NEW_PART" /mnt/var
mount -o noatime,compress=zstd,subvol=@log "$NEW_PART" /mnt/var/log
mount -o noatime,compress=zstd,subvol=@tmp "$NEW_PART" /mnt/var/tmp
mount -o noatime,compress=zstd,subvol=@pkg "$NEW_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,subvol=@snapshots "$NEW_PART" /mnt/.snapshots

# Mount EFI partition
echo "Available EFI partitions:"
lsblk -f | grep vfat
read -rp "Enter EFI partition (e.g., /dev/nvme0n1p1): " EFIPART
mkdir -p /mnt/boot/efi
mount "$EFIPART" /mnt/boot/efi

echo "✅ Setup complete! Ready for Arch installation."
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
