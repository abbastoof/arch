#!/bin/bash
set -e

echo "=== Arch Linux LUKS + Btrfs Setup with Snapper + Zram ==="
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

# Confirm the partition is not formatted or overwritten by checking existing filesystem
if lsblk -f "$NEW_PART" | grep -q "PART"; then
    echo "Error: The selected partition already has a filesystem. Aborting."
    exit 1
fi

# Set up LUKS encryption interactively (using LUKS2)
echo "Encrypting $NEW_PART with LUKS2..."
cryptsetup luksFormat --type luks2 "$NEW_PART"
cryptsetup open "$NEW_PART" cryptroot

# Format the opened LUKS container as Btrfs
mkfs.btrfs -f /dev/mapper/cryptroot

# Create Btrfs subvolumes
mount /dev/mapper/cryptroot /mnt
for sub in @ @home @var @log @tmp @pkg @snapshots; do
    btrfs subvolume create /mnt/"$sub"
done
umount /mnt

# Mount subvolumes with desired options
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot}
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

# Mount EFI partition (list vfat partitions first)
lsblk -f | grep vfat
read -rp "Enter EFI system partition (e.g., /dev/nvme0n1p1): " EFIPART
mount "$EFIPART" /mnt/boot

# Configure zram for systemd-zram-generator
echo "Installing systemd-zram-generator config..."
mkdir -p /mnt/etc/systemd/zram-generator.conf.d
cat <<EOF > /mnt/etc/systemd/zram-generator.conf.d/zram.conf
[zram0]
zram-size = ram
EOF

echo ""
echo "✅ All set!"
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
echo "➡ After installation, boot into the new system and install Snapper:"
echo "   sudo pacman -Sy snapper"
echo "   sudo snapper --config root create-config /"
echo "   sudo snapper --config home create-config /home"
echo "   sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer"
