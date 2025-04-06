#!/bin/bash
set -e

echo "=== Arch Linux LUKS + Btrfs Setup with Snapper + Zram ==="

# List available disks (filtering common types: sd*, nvme*)
echo "Available disks:"
declare -a disk_array
index=1
while read -r disk; do
    # disk is like: sda 465.8G
    disk_array+=("$disk")
    echo "$index) $disk"
    index=$((index+1))
done < <(lsblk -d -n -o NAME,SIZE | grep -E '^(sd|nvme)')

if [ ${#disk_array[@]} -eq 0 ]; then
    echo "No disks found."
    exit 1
fi

read -rp "Enter the disk number to use (e.g., 1): " disknum
if ! [[ "$disknum" =~ ^[0-9]+$ ]] || [ "$disknum" -lt 1 ] || [ "$disknum" -gt "${#disk_array[@]}" ]; then
    echo "Invalid disk number."
    exit 1
fi

# Extract the selected disk name and create full path (e.g., /dev/sda or /dev/nvme0n1)
selected_disk_name=$(echo "${disk_array[$((disknum-1))]}" | awk '{print $1}')
DISK="/dev/$selected_disk_name"
echo "Selected disk: $DISK"

# Find unallocated space using parted in MiB
echo "Checking unallocated space on $DISK..."
FREE_LINE=$(parted "$DISK" unit MiB print free | awk '/Free Space/ && ($3+0)>0 { print $0 }' | tail -n 1)

if [ -z "$FREE_LINE" ]; then
    echo "No unallocated space found on $DISK."
    exit 1
fi

# Extract start, end, and size values; remove any non-numeric characters
START=$(echo "$FREE_LINE" | awk '{print $1}' | sed 's/[^0-9.]//g')
END=$(echo "$FREE_LINE" | awk '{print $2}' | sed 's/[^0-9.]//g')
SIZE=$(echo "$FREE_LINE" | awk '{print $3}' | sed 's/[^0-9.]//g')

# Subtract 1 MiB from END to stay within disk bounds
END=$(echo "$END - 1" | bc)

echo "Last unallocated space: ${SIZE}MiB (from ${START}MiB to ${END}MiB)"

# Ask to create a new partition
read -rp "Create new partition in this space? (yes/[no]): " CREATE_PART
[[ "$CREATE_PART" != "yes" ]] && echo "Aborted." && exit 1

# Create new partition with parted (units appended explicitly)
echo "Creating new partition on $DISK..."
parted -s "$DISK" mkpart primary btrfs "${START}MiB" "${END}MiB"
partprobe "$DISK"
sleep 2

# Get the last partition on the disk (assumes it is the one just created)
NEW_PART=$(lsblk -dpno NAME "$DISK" | tail -n 1)
echo "Created partition: $NEW_PART"

# Setup LUKS encryption interactively with LUKS2
echo "Encrypting $NEW_PART with LUKS2..."
cryptsetup luksFormat --type luks2 "$NEW_PART"
cryptsetup open "$NEW_PART" cryptroot

# Format the LUKS container with Btrfs
mkfs.btrfs -f /dev/mapper/cryptroot

# Create Btrfs subvolumes
mount /dev/mapper/cryptroot /mnt
for sub in @ @home @var @log @tmp @pkg @snapshots; do
  echo "Creating subvolume $sub..."
  btrfs subvolume create /mnt/"$sub"
done
umount /mnt

# Mount the Btrfs subvolumes with options
echo "Mounting subvolumes..."
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var,var/log,var/tmp,var/cache/pacman/pkg,.snapshots,boot}

mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,commit=120,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

# EFI partition mount (list available vfat partitions for convenience)
echo "Available EFI partitions:"
lsblk -f | grep vfat
read -rp "Enter EFI system partition (e.g., /dev/sda1): " EFIPART
mount "$EFIPART" /mnt/boot

# Set up zram config for systemd-zram-generator
echo "Installing systemd-zram-generator config..."
mkdir -p /mnt/etc/systemd/zram-generator.conf.d
cat <<EOF > /mnt/etc/systemd/zram-generator.conf.d/zram.conf
[zram0]
zram-size = ram
EOF

echo
echo "✅ Setup complete!"
echo "➡ Now run 'archinstall' and choose 'Use current mount points'."
echo "➡ After installation, boot into the new system and install Snapper with:"
echo "   sudo pacman -Sy snapper"
echo "   sudo snapper --config root create-config /"
echo "   sudo snapper --config home create-config /home"
echo "   sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer"
