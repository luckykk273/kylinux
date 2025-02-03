#!/bin/bash
# This script aims to create a bootable USB drive with Linux and EFI support.

# Exit immediately if a command exits with a non-zero status
# set -e

# Specify the device (e.g., /dev/sdb)
DEVICE="/dev/sdb"

# Check if the device exists as a block device
if [ -b "$DEVICE" ]; then
  echo -e "$DEVICE exists as a block device.\n"
  echo "Unmount all partitions from $DEVICE before formatting:"
  sudo umount $DEVICE*
  echo

  echo "Wipe all filesystem signatures:"
  sudo wipefs --all $DEVICE*
  echo
else
  echo "$DEVICE does not exist or is not a block device."
  exit 1
fi

# Create a named pipe (FIFO) for simulating interactive input
PIPE=$(mktemp -u) # Create a unique temporary file name
mkfifo $PIPE      # Create a named pipe with the temporary file name

# Run gdisk in the background with input redirected from the named pipe and output displayed on the console
sudo gdisk $DEVICE <$PIPE &
# Take the PID of gdisk
GDISK_PID=$!

counter=5

# Write commands to the named pipe with delays
{
  sleep 1; echo o # Create a new empty GUID partition table(GPT)
  sleep 1; echo y # Confirm
  sleep 1; echo n # Add a new partition for ESP
  sleep 1; echo 1 # Partition number
  sleep 1; echo # Press Enter for default first sector
  sleep 1; echo +100M # Size: 100MB is usually sufficient
  sleep 1; echo EF00 # Type code: EFI System Partition
  sleep 1; echo n # Add a new partition for Linux filesystem
  sleep 1; echo 2 # Partition number
  sleep 1; echo # Press Enter for default first sector
  sleep 1; echo # Press Enter for default last sector - uses remaining space
  sleep 1; echo 8300 # Type code: Linux filesystem
  sleep 1; echo w # Write table to disk and exit
  sleep 3; echo y # Confirm
  sleep 3 # Wait for gdisk to finish
} | tee $PIPE # Use "tee" to duplicate the input commands to both the console and the named pipe

# fdisk timeout and error handling
TIMEOUT=10
SECONDS_PASSED=0
while kill -0 $GDISK_PID 2>/dev/null; do # "kill -0" is to check if a process exists without sending any signal
  sleep 1
  SECONDS_PASSED=$((SECONDS_PASSED + 1))

  if [ $SECONDS_PASSED -ge $TIMEOUT ]; then
    echo "Error: gdisk command timed out."
    kill -9 $GDISK_PID
    rm $PIPE
    exit 1
  fi
done

# Remove the named pipe
rm $PIPE
echo
echo
echo

# Format the partitions
echo "Make sure the filesystem type is empty:"
sudo parted $DEVICE print
echo "Format the partition for ESP:"
sudo mkfs.fat -F 32 ${DEVICE}1
echo
echo "Format the partition for Linux filesystem:"
sudo mkfs.ext4 ${DEVICE}2
echo

echo "Check the partitions and filesystem types are correct:"
sudo parted $DEVICE print
echo
echo
echo

EFI_MOUNT_POINT="/mnt/boot/efi"
BOOT_MOUNT_POINT="/mnt/boot"

echo "Mount the Linux filesystem and create the directory tree:"
if [ ! -e $BOOT_MOUNT_POINT ]; then
  echo "$BOOT_MOUNT_POINT doesn't exist. Create it."
  # Perform actions like creating a directory
  sudo mkdir -p $BOOT_MOUNT_POINT
else
  echo "$BOOT_MOUNT_POINT exists."
  sudo umount "$BOOT_MOUNT_POINT"
fi
sudo mount ${DEVICE}2 $BOOT_MOUNT_POINT

echo "Mount the EFI system and create the directory tree:"
if [ ! -e $EFI_MOUNT_POINT ]; then
  echo "$EFI_MOUNT_POINT doesn't exist. Create it."
  # Perform actions like creating a directory
  sudo mkdir -p $EFI_MOUNT_POINT
else
  echo "$EFI_MOUNT_POINT exists."
  sudo umount "$EFI_MOUNT_POINT"
fi
sudo mount ${DEVICE}1 $EFI_MOUNT_POINT

# Check the mount points
df
