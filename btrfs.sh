#!/bin/bash
set -e

# Variables
ROOT_PART="/dev/nvme0n1p2"
EFI_PART="/dev/nvme0n1p1"
MNT="/mnt"
BTRFS_OPTS="noatime,compress=zstd,commit=120,space_cache=v2"

echo "==> Formatting root partition: $ROOT_PART"
mkfs.btrfs -f "$ROOT_PART"

echo "==> Creating subvolumes..."
mount "$ROOT_PART" "$MNT"
btrfs subvolume create "$MNT/@"
btrfs subvolume create "$MNT/@home"
btrfs subvolume create "$MNT/@var"
btrfs subvolume create "$MNT/@log"
btrfs subvolume create "$MNT/@tmp"
btrfs subvolume create "$MNT/@pkg"
btrfs subvolume create "$MNT/@snapshots"
umount "$MNT"

echo "==> Mounting subvolumes..."
mount -o $BTRFS_OPTS,subvol=@ "$ROOT_PART" "$MNT"

# Create mountpoints
mkdir -p "$MNT/home"
mkdir -p "$MNT/var"
mkdir -p "$MNT/.snapshots"

# Mount @var before making nested dirs inside it
mount -o $BTRFS_OPTS,subvol=@var "$ROOT_PART" "$MNT/var"

# Now we can safely create these
mkdir -p "$MNT/var/log"
mkdir -p "$MNT/var/tmp"
mkdir -p "$MNT/var/cache/pacman/pkg"

# Mount nested subvolumes
mount -o $BTRFS_OPTS,subvol=@home       "$ROOT_PART" "$MNT/home"
mount -o $BTRFS_OPTS,subvol=@log        "$ROOT_PART" "$MNT/var/log"
mount -o $BTRFS_OPTS,subvol=@tmp        "$ROOT_PART" "$MNT/var/tmp"
mount -o $BTRFS_OPTS,subvol=@pkg        "$ROOT_PART" "$MNT/var/cache/pacman/pkg"
mount -o $BTRFS_OPTS,subvol=@snapshots  "$ROOT_PART" "$MNT/.snapshots"

# Mount EFI partition with confirmation
echo "==> EFI partition detected at $EFI_PART"
read -rp "Do you want to format the EFI partition? (yes/no): " FORMAT_EFI

if [[ "$FORMAT_EFI" == "yes" ]]; then
    echo "==> Formatting EFI partition as FAT32..."
    mkfs.fat -F32 "$EFI_PART"
else
    echo "==> Skipping EFI format. Checking filesystem type..."
    EFI_TYPE=$(blkid -s TYPE -o value "$EFI_PART")
    if [[ "$EFI_TYPE" != "vfat" ]]; then
        echo "⚠️ EFI partition is not vfat (found: $EFI_TYPE)"
        echo "If this is incorrect, you may need to fix it manually."
    fi
fi

mkdir -p "$MNT/boot"
mount "$EFI_PART" "$MNT/boot"

echo "✅ All subvolumes and EFI are mounted correctly at $MNT"
