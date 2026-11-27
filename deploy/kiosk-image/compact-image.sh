#!/bin/bash
set -euo pipefail

SOURCE_IMAGE=${SOURCE_IMAGE:-/work/customized.img}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-/output/BendCNC-Qt-Kiosk-Minimal-OrangePi3B.img}
ROOT_MNT=${ROOT_MNT:-/mnt/bendcnc-root}
DATA_MNT=${DATA_MNT:-/mnt/bendcnc-data}

ROOT_USED=$(du -sx --block-size=1 "$ROOT_MNT" | awk '{print $1}')
DATA_USED=$(du -sx --block-size=1 "$DATA_MNT" | awk '{print $1}')
MIB=$((1024 * 1024))
ROOT_HEADROOM=$((512 * MIB))
DATA_HEADROOM=$((384 * MIB))
ROOT_MIB=$(( (ROOT_USED + ROOT_HEADROOM + MIB - 1) / MIB ))
DATA_MIB=$(( (DATA_USED + DATA_HEADROOM + MIB - 1) / MIB ))
# Round to 128 MiB boundaries and retain practical lower bounds.
ROOT_MIB=$(( (ROOT_MIB + 127) / 128 * 128 ))
DATA_MIB=$(( (DATA_MIB + 127) / 128 * 128 ))
(( ROOT_MIB < 2048 )) && ROOT_MIB=2048
(( DATA_MIB < 512 )) && DATA_MIB=512

P1_START=32768
P1_SECTORS=$((ROOT_MIB * 2048))
P1_END=$((P1_START + P1_SECTORS - 1))
P2_START=$(( (P1_END + 2048) / 2048 * 2048 ))
P2_SECTORS=$((DATA_MIB * 2048))
P2_END=$((P2_START + P2_SECTORS - 1))
IMAGE_MIB=$(( (P2_END + 1 + 2048 + 2047) / 2048 ))

rm -f "$OUTPUT_IMAGE"
truncate -s "${IMAGE_MIB}M" "$OUTPUT_IMAGE"
# Preserve the RK3566 loader/SPL region before the first partition. sgdisk
# then replaces only GPT metadata while leaving the board boot payload intact.
dd if="$SOURCE_IMAGE" of="$OUTPUT_IMAGE" bs=1M count=16 conv=notrunc status=none
sgdisk --zap-all "$OUTPUT_IMAGE" >/dev/null
sgdisk -n "1:${P1_START}:${P1_END}" -t 1:8300 -c 1:system "$OUTPUT_IMAGE" >/dev/null
sgdisk -n "2:${P2_START}:${P2_END}" -t 2:8300 -c 2:data "$OUTPUT_IMAGE" >/dev/null

# A separately flashed SD must never reuse the production card's filesystem
# identities. Otherwise U-Boot's root=UUID selector can boot the old card/eMMC
# when both media are visible, leaving the machine at the legacy tty login.
ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
DATA_UUID=$(cat /proc/sys/kernel/random/uuid)
sgdisk -G "$OUTPUT_IMAGE" >/dev/null
NEW_ROOT=$(losetup --find --show --offset "$((P1_START*512))" --sizelimit "$((P1_SECTORS*512))" "$OUTPUT_IMAGE")
NEW_DATA=$(losetup --find --show --offset "$((P2_START*512))" --sizelimit "$((P2_SECTORS*512))" "$OUTPUT_IMAGE")
NEW_ROOT_MNT=/mnt/bendcnc-new-root
NEW_DATA_MNT=/mnt/bendcnc-new-data
cleanup_compact() {
    set +e
    mountpoint -q "$NEW_DATA_MNT" && umount "$NEW_DATA_MNT"
    mountpoint -q "$NEW_ROOT_MNT" && umount "$NEW_ROOT_MNT"
    losetup -d "$NEW_DATA" 2>/dev/null
    losetup -d "$NEW_ROOT" 2>/dev/null
}
trap cleanup_compact EXIT
mkfs.ext4 -F -L system -U "$ROOT_UUID" "$NEW_ROOT" >/dev/null
mkfs.ext4 -F -L data -U "$DATA_UUID" "$NEW_DATA" >/dev/null
mkdir -p "$NEW_ROOT_MNT" "$NEW_DATA_MNT"
mount "$NEW_ROOT" "$NEW_ROOT_MNT"
mount "$NEW_DATA" "$NEW_DATA_MNT"
rsync -aHAX --numeric-ids "$ROOT_MNT/" "$NEW_ROOT_MNT/"
rsync -aHAX --numeric-ids "$DATA_MNT/" "$NEW_DATA_MNT/"

# Point both U-Boot and Linux at the new, unambiguous filesystems. Replace the
# complete fstab entries rather than depending on the base image's source form.
ARMBIAN_ENV="$NEW_ROOT_MNT/boot/armbianEnv.txt"
if grep -q '^rootdev=' "$ARMBIAN_ENV"; then
    sed -i "s#^rootdev=.*#rootdev=UUID=$ROOT_UUID#" "$ARMBIAN_ENV"
else
    echo "rootdev=UUID=$ROOT_UUID" >> "$ARMBIAN_ENV"
fi
FSTAB="$NEW_ROOT_MNT/etc/fstab"
sed -i -E '\#^[^#[:space:]]+[[:space:]]+/[[:space:]]+#d; \#^[^#[:space:]]+[[:space:]]+/data[[:space:]]+#d' "$FSTAB"
{
    echo "UUID=$ROOT_UUID / ext4 defaults,noatime,commit=120,errors=remount-ro 0 1"
    echo "UUID=$DATA_UUID /data ext4 defaults 0 2"
} >> "$FSTAB"
sync

ROOT_FINAL=$(du -sx --block-size=1 "$NEW_ROOT_MNT" | awk '{print $1}')
DATA_FINAL=$(du -sx --block-size=1 "$NEW_DATA_MNT" | awk '{print $1}')
DISK_GUID=$(sgdisk -p "$OUTPUT_IMAGE" | awk -F': ' '/Disk identifier \(GUID\):/{print $2}')
ROOT_PARTUUID=$(sgdisk -i 1 "$OUTPUT_IMAGE" | awk -F': ' '/Partition unique GUID:/{print $2}')
DATA_PARTUUID=$(sgdisk -i 2 "$OUTPUT_IMAGE" | awk -F': ' '/Partition unique GUID:/{print $2}')
echo "COMPACT-IMAGE root_used=$ROOT_FINAL root_mib=$ROOT_MIB data_used=$DATA_FINAL data_mib=$DATA_MIB image_mib=$IMAGE_MIB root_uuid=$ROOT_UUID data_uuid=$DATA_UUID disk_guid=$DISK_GUID root_partuuid=$ROOT_PARTUUID data_partuuid=$DATA_PARTUUID"
cleanup_compact
trap - EXIT
sgdisk -v "$OUTPUT_IMAGE"