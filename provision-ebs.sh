#!/usr/bin/env bash
set -e

# provision-ebs.sh <device> <filesystem> <mountpoint>

DEVICE="${1}"
FILESYSTEM="${2}"
MOUNTPOINT="${3}"

if file -s ${DEVICE} | grep -qE 'data$'; then
    echo "Creating ${FILESYSTEM} on ${DEVICE}"
    mkfs -t ${FILESYSTEM} /dev/nvme1n1
fi

mkdir -p ${MOUNTPOINT}

echo "Updating fstab..."
echo "${DEVICE} ${MOUNTPOINT} ${FILESYSTEM} defaults,nofail 0 0" >> /etc/fstab

echo "Mounting ${DEVICE} to ${MOUNTPOINT}..."
mount ${DEVICE} ${MOUNTPOINT} -t ${FILESYSTEM} -o defaults,nofail

