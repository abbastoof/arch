#!/bin/bash
set -e

# Format the root partition as Btrfs
mkfs.btrfs -f /dev/nvme0n1p2

# Create subvolumes
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

# Create mount points for subvolumes (if they don't exist)
mkdir -p /mnt/home /mnt/var /mnt/.snapshots /mnt/boot/efi

# Mount each subvolume
mount -o noatime,compress=zstd,subvol=@home,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/home
mount -o noatime,compress=zstd,subvol=@var,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var
mount -o noatime,compress=zstd,subvol=@log,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var/log
mount -o noatime,compress=zstd,subvol=@tmp,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var/tmp
mount -o noatime,compress=zstd,subvol=@pkg,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,subvol=@snapshots,commit=120,space_cache=v2 /dev/nvme0n1p2 /mnt/.snapshots

# Create directories inside /mnt/var subvolume after mounting it
mkdir -p /mnt/var/log /mnt/var/tmp /mnt/var/cache/pacman/pkg

# Mount EFI partition
mount /dev/nvme0n1p1 /mnt/boot/efi
