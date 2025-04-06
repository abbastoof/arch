#!/bin/bash
set -e

# Variables (change these if needed)
ROOT_PART="/dev/nvme0n1p4"
EFI_PART="/dev/nvme0n1p1"
MOUNTPOINT="/mnt"
BTRFS_OPTS="noatime,compress=zstd,commit=120,space_cache=v2"

# WARNING: This will erase all data on ${ROOT_PART}
echo "Formatting ${ROOT_PART} as Btrfs..."
mkfs.btrfs -f "$ROOT_PART"

# Mount the partition temporarily to create subvolumes
echo "Mounting ${ROOT_PART} temporarily to create subvolumes..."
mount "$ROOT_PART" "$MOUNTPOINT"

echo "Creating Btrfs subvolumes..."
btrfs subvolume create "$MOUNTPOINT/@"
btrfs subvolume create "$MOUNTPOINT/@home"
btrfs subvolume create "$MOUNTPOINT/@var"
btrfs subvolume create "$MOUNTPOINT/@log"
btrfs subvolume create "$MOUNTPOINT/@tmp"
btrfs subvolume create "$MOUNTPOINT/@pkg"
btrfs subvolume create "$MOUNTPOINT/@snapshots"

# Unmount the temporary mount
umount "$MOUNTPOINT"

# Mount the subvolumes using our desired options
echo "Mounting the Btrfs subvolumes..."

# Mount root subvolume
mount -o $BTRFS_OPTS,subvol=@ "$ROOT_PART" "$MOUNTPOINT"

# Create all needed directories BEFORE mounting nested subvolumes
mkdir -p "$MOUNTPOINT"/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot}

# Mount each subvolume
mount -o $BTRFS_OPTS,subvol=@home "$ROOT_PART" "$MOUNTPOINT/home"
mount -o $BTRFS_OPTS,subvol=@var "$ROOT_PART" "$MOUNTPOINT/var"
mount -o $BTRFS_OPTS,subvol=@log "$ROOT_PART" "$MOUNTPOINT/var/log"
mount -o $BTRFS_OPTS,subvol=@tmp "$ROOT_PART" "$MOUNTPOINT/var/tmp"
mount -o $BTRFS_OPTS,subvol=@pkg "$ROOT_PART" "$MOUNTPOINT/var/cache/pacman/pkg"
mount -o $BTRFS_OPTS,subvol=@snapshots "$ROOT_PART" "$MOUNTPOINT/.snapshots"

# Mount the EFI partition (shared EFI)
mount "$EFI_PART" "$MOUNTPOINT/boot"

echo "All done. Your subvolumes are mounted as follows:"
mount | grep "$ROOT_PART"
