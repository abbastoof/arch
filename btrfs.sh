#!/bin/bash
set -e

DISK="/dev/nvme0n1"
EFI_DISK="/dev/nvme1n1p1"

echo "==> Wiping $DISK..."
sudo wipefs -a "$DISK"
sudo sgdisk --zap-all "$DISK"

echo "==> Creating GPT and Btrfs partition on $DISK..."
sudo parted "$DISK" mklabel gpt
sudo parted "$DISK" mkpart primary btrfs 1MiB 100%

echo "==> Formatting $DISK partition as Btrfs..."
sudo mkfs.btrfs -f "${DISK}p1"

echo "==> Mounting $DISK partition temporarily..."
sudo mount "${DISK}p1" /mnt

echo "==> Creating Btrfs subvolumes..."
for subvol in @ @home @pkg @log @tmp @snapshots; do
    sudo btrfs subvolume create "/mnt/$subvol"
done

echo "==> Unmounting temporary mount..."
sudo umount /mnt

echo "==> Mounting subvolumes..."
sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,discard=async,subvol=@ "${DISK}p1" /mnt

sudo mkdir -p /mnt/{boot/efi,home,var/cache/pacman/pkg,var/log,tmp,.snapshots}

sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,discard=async,subvol=@home "${DISK}p1" /mnt/home
sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,discard=async,subvol=@pkg "${DISK}p1" /mnt/var/cache/pacman/pkg
sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,discard=async,subvol=@log "${DISK}p1" /mnt/var/log
sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,discard=async,subvol=@tmp "${DISK}p1" /mnt/tmp
sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,discard=async,subvol=@snapshots "${DISK}p1" /mnt/.snapshots

echo "==> Mounting existing EFI partition..."
sudo mount "$EFI_DISK" /mnt/boot/efi

echo "==> Done! Ready for archinstall."
