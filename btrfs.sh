#!/bin/bash
set -e

echo "=== Arch Linux LUKS + Btrfs Setup with Snapper + Zram ==="

# Prompt for disk selection
lsblk -dpno NAME,SIZE | grep -v loop
read -rp "Enter the disk where you want to create a partition (e.g., /dev/nvme0n1): " DISK

# Find unallocated space using parted
echo "Checking unallocated space on $DISK..."
# Filter out free space rows that have size > 0
FREE_LINE=$(parted "$DISK" unit MiB print free | awk '/Free Space/ && ($3+0)>0 { print $0 }' | tail -n 1)

# Extract the start, end, and size values, stripping units
START=$(echo "$FREE_LINE" | awk '{print $1}' | sed 's/[^0-9.]//g')
END=$(echo "$FREE_LINE" | awk '{print $2}' | sed 's/[^0-9.]//g')
SIZE=$(echo "$FREE_LINE" | awk '{print $3}' | sed 's/[^0-9.]//g')

if [[ -z "$START" || -z "$END" ]]; then
  echo "No unallocated space found on $DISK."
  exit 1
fi

# Subtract 1 MiB from the end to stay within disk bounds
END=$(echo "$END - 1" | bc)

echo "Last unallocated space: ${SIZE}MiB (from ${START}MiB to ${END}MiB)"

# Ask to create a new partition
read -rp "Create new partition in this space? (yes/[no]): " CREATE_PART
[[ "$CREATE_PART" != "yes" ]] && echo "Aborted." && exit 1

# Create new partition using parted (appending 'MiB' unit)
echo "Creating new partition on $DISK..."
parted -s "$DISK" mkpart primary btrfs "${START}MiB" "${END}MiB"
partprobe "$DISK"
sleep 2

# Get the last partition just created
NEW_PART=$(lsblk -dpno NAME "$DISK" | tail -n 1)
echo "Created: $NEW_PART"

# Setup LUKS encryption interactively with LUKS2
echo "Encrypting $NEW_PART with LUKS2..."
cryptsetup luksFormat --type luks2 "$NEW_PART"
cryptsetup open "$NEW_PART" cryptroot

# Format as Btrfs
mkfs.btrfs -f /dev/mapper/cryptroot

# Create Btrfs subvolumes
mount /dev/mapper/cryptroot /mnt
for sub in @ @home @var @log @tmp @pkg @snapshots; do
  btrfs subvolume create /mnt/$sub
done
umount /mnt

# Mount subvolumes with options
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot}

mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

# EFI Mount
lsblk -f | grep vfat
read -rp "Enter EFI system partition (e.g., /dev/nvme0n1p1): " EFIPART
mount "$EFIPART" /mnt/boot

# Set up zram config for systemd-zram-generator
echo "Installing systemd-zram-generator config..."
mkdir -p /mnt/etc/systemd/zram-generator.conf.d
cat <<EOF > /mnt/etc/systemd/zram-generator.conf.d/zram.conf
[zram0]
zram-size = ram
EOF

# Completion message
echo
echo "✅ All set!"
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
echo "➡ After installation, boot into the new system and install Snapper:"
echo "   sudo pacman -Sy snapper"
echo "   sudo snapper --config root create-config /"
echo "   sudo snapper --config home create-config /home"
echo "   sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer"
