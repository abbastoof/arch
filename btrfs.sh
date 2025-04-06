#!/bin/bash
set -e

echo "=== Arch Linux Btrfs Setup (New Partition Only) ==="
echo ""

# List available disks (only physical disks, not partitions)
echo "Available disks:"
DISKS=($(lsblk -dn -o NAME))
COUNTER=1
for disk in "${DISKS[@]}"; do
    SIZE=$(lsblk -dn -o SIZE /dev/"$disk")
    echo "  $COUNTER) /dev/$disk ($SIZE)"
    COUNTER=$((COUNTER+1))
done

read -rp "Select disk by number: " DISK_NUM
INDEX=$((DISK_NUM-1))
SELECTED_DISK="/dev/${DISKS[$INDEX]}"
echo "Selected disk: $SELECTED_DISK"
echo ""

# Check that the disk has a GPT partition table
if ! parted -s "$SELECTED_DISK" print | grep -q "Partition Table: gpt"; then
    echo "Error: Selected disk does not have a GPT partition table. Aborting."
    exit 1
fi

# Find unallocated space using parted (unit: MiB)
echo "Checking unallocated space on $SELECTED_DISK..."
FREE_LINE=$(parted "$SELECTED_DISK" unit MiB print free | awk '/Free Space/ && ($3+0)>0 { print $0 }' | tail -n 1)

if [ -z "$FREE_LINE" ]; then
    echo "No unallocated space found on $SELECTED_DISK."
    exit 1
fi

# Extract start, end, and size values (strip "MiB")
START=$(echo "$FREE_LINE" | awk '{print $1}' | sed 's/[^0-9.]//g')
END=$(echo "$FREE_LINE" | awk '{print $2}' | sed 's/[^0-9.]//g')
SIZE=$(echo "$FREE_LINE" | awk '{print $3}' | sed 's/[^0-9.]//g')

# Subtract 1 MiB from the END to avoid GPT boundary issues
END=$(echo "$END - 1" | bc)

echo "Found free space: ${SIZE} MiB (from ${START} MiB to ${END} MiB)"
echo ""
read -rp "Create new partition in this space? (yes/[no]): " CREATE_PART
if [[ "$CREATE_PART" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Create new partition on the selected disk using parted (using MiB units)
echo "Creating new partition on $SELECTED_DISK..."
parted -s "$SELECTED_DISK" mkpart primary btrfs "${START}MiB" "${END}MiB"
partprobe "$SELECTED_DISK"
sleep 2

# Get the newly created partition (assumes it's the last partition)
NEW_PART=$(lsblk -dpno NAME "$SELECTED_DISK" | tail -n 1)
echo "Created partition: $NEW_PART"
echo ""

# Format the new partition as Btrfs
echo "Formatting $NEW_PART as Btrfs..."
mkfs.btrfs -f "$NEW_PART"

# Mount the Btrfs partition and create subvolumes
echo "Creating Btrfs subvolumes..."
mount "$NEW_PART" /mnt
for sub in @ @home @var @log @tmp @pkg @snapshots; do
    btrfs subvolume create /mnt/"$sub"
done
umount /mnt

# Prepare the mount points for Arch Linux installation
echo "Mounting Btrfs subvolumes..."
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@ "$NEW_PART" /mnt
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot}
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@home "$NEW_PART" /mnt/home
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@var "$NEW_PART" /mnt/var
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@log "$NEW_PART" /mnt/var/log
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@tmp "$NEW_PART" /mnt/var/tmp
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@pkg "$NEW_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@snapshots "$NEW_PART" /mnt/.snapshots

# Mount EFI partition (list vfat partitions first) to /mnt/boot/efi
lsblk -f | grep vfat
read -rp "Enter EFI system partition (e.g., /dev/nvme0n1p1): " EFIPART
mount "$EFIPART" /mnt/boot/efi

echo ""
echo "✅ All set! The new partition is ready for Arch installation."
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
