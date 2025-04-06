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

# Check for at least 300GiB of free space
FREE_SPACE=$(fdisk -l "$SELECTED_DISK" | grep -i "free space" | awk '{print $4}')
if [ -z "$FREE_SPACE" ] || [ "$FREE_SPACE" -lt 314572800 ]; then  # 300GiB in KB
    echo "Warning: Insufficient free space on $SELECTED_DISK"
    echo "Available free space: $(($FREE_SPACE / 1048576)) GiB"
    read -rp "Continue anyway? (yes/[no]): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "Creating new 300GiB partition on $SELECTED_DISK..."
# Use fdisk to create a new partition with the desired size
fdisk "$SELECTED_DISK" <<EOF
n
p


+300G
t
$(fdisk -l "$SELECTED_DISK" | grep -i "number of partitions" | awk '{print $NF}')
83
w
EOF

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
