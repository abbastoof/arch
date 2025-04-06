#!/bin/bash
set -e
echo "=== Arch Linux Btrfs Setup (300GiB Partition) ==="
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

# Find unallocated space using parted (unit: MB instead of MiB for better precision)
echo "Checking unallocated space on $SELECTED_DISK..."
parted -s "$SELECTED_DISK" unit MB print free
FREE_LINE=$(parted -s "$SELECTED_DISK" unit MB print free | grep "Free Space" | sort -k3 -n | tail -n 1)
if [ -z "$FREE_LINE" ]; then
    echo "No unallocated space found on $SELECTED_DISK."
    exit 1
fi

# Extract start, end, and size values (strip "MB")
START=$(echo "$FREE_LINE" | awk '{print $1}' | sed 's/MB//g')
END=$(echo "$FREE_LINE" | awk '{print $2}' | sed 's/MB//g')
SIZE=$(echo "$FREE_LINE" | awk '{print $3}' | sed 's/MB//g')

# Calculate the end point for a 300GiB partition (in MB)
TARGET_SIZE=314572.8  # 300GiB in MB (300*1024*1.024)
if (( $(echo "$SIZE < $TARGET_SIZE" | bc -l) )); then
    echo "Warning: Available space (${SIZE} MB) is less than 300GiB (${TARGET_SIZE} MB)"
    read -rp "Continue with the maximum available space? (yes/[no]): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
    NEW_END=$END
else
    NEW_END=$(echo "$START + $TARGET_SIZE" | bc)
    if (( $(echo "$NEW_END > $END" | bc -l) )); then
        NEW_END=$END
    fi
fi

# Subtract a small amount to avoid boundary issues
NEW_END=$(echo "$NEW_END - 1" | bc)
echo "Found free space: ${SIZE} MB (from ${START} MB to ${END} MB)"
echo "Creating a partition from ${START} MB to ${NEW_END} MB"
echo ""
read -rp "Create new partition in this space? (yes/[no]): " CREATE_PART
if [[ "$CREATE_PART" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Create new partition on the selected disk using parted (using MB units)
echo "Creating new partition on $SELECTED_DISK..."
# Use script to interact with parted and use optimal alignment
echo "mkpart primary btrfs ${START}MB ${NEW_END}MB" | parted "$SELECTED_DISK"
partprobe "$SELECTED_DISK"
sleep 2

# Get the newly created partition
NEW_PART=$(lsblk -dpno NAME "$SELECTED_DISK" | grep -v "$SELECTED_DISK$" | sort | tail -n 1)
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
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot/efi}
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@home "$NEW_PART" /mnt/home
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@var "$NEW_PART" /mnt/var
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@log "$NEW_PART" /mnt/var/log
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@tmp "$NEW_PART" /mnt/var/tmp
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@pkg "$NEW_PART" /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@snapshots "$NEW_PART" /mnt/.snapshots

# Mount EFI partition (list vfat partitions first) to /mnt/boot/efi
echo "Available EFI partitions (vfat):"
lsblk -f | grep vfat
read -rp "Enter EFI system partition (e.g., /dev/nvme0n1p1): " EFIPART

# Verify the EFI partition exists
if [ ! -b "$EFIPART" ]; then
    echo "Error: $EFIPART is not a valid block device. Aborting."
    exit 1
fi

# Mount the EFI partition read-only to prevent accidental modification
mount -o ro "$EFIPART" /mnt/boot/efi
echo ""
echo "✅ All set! The new 300GiB partition is ready for Arch installation."
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
echo ""
echo "⚠️ Note: The EFI partition is mounted read-only to prevent accidental modification."
echo "   When you're ready to install the bootloader, remount it with write permissions:"
echo "   # mount -o remount,rw /mnt/boot/efi"
