#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Format the root partition as Btrfs
mkfs.btrfs -f /dev/nvme0n1p2

# Create subvolumes on the partition
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt

# Mount the root partition with subvolume @ and specific options
mount -o noatime,compress=zstd,subvol=@,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt

# Create directories for the other subvolumes
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots}

# Mount each subvolume with desired options
mount -o noatime,compress=zstd,subvol=@home,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/home
mount -o noatime,compress=zstd,subvol=@var,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var
mount -o noatime,compress=zstd,subvol=@log,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var/log
mount -o noatime,compress=zstd,subvol=@tmp,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var/tmp
mount -o noatime,compress=zstd,subvol=@pkg,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,subvol=@snapshots,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/.snapshots

# Mount EFI partition
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi
