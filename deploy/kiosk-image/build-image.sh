#!/bin/bash
# Build the flashable BendCNC SD image for the Orange Pi 3B.
#
#   1. armbian-build.sh                -> Armbian Jammy minimal (vendor 6.1)
#   2. prepare-base.sh  (in docker)    -> bendcnc-base.img
#   3. ../arm64/build-arm64.sh         -> bendcnc-qt-arm64.tar
#   4. build-image.sh BASE.img BUNDLE.tar OUT_DIR
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPLOY=$(cd "$HERE/.." && pwd)
BASE=$(realpath "${1:?base image}"); BUNDLE=$(realpath "${2:?qt bundle tar}")
OUT=$(mkdir -p "${3:-$HERE/out}" && realpath "${3:-$HERE/out}")
# First-boot wizard built by build-arm64.sh next to the bundle.
SETUP=$(realpath "${SETUP_DIR:-$(dirname "$BUNDLE")/setup}")
[[ -x "$SETUP/bendcnc-setup" ]] || { echo "missing $SETUP/bendcnc-setup" >&2; exit 2; }
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT

# Docker sees these as Linux files: force LF.
cp -r "$HERE" "$STAGE/source"
find "$STAGE/source" -type f ! -name '*.png' ! -name '*.bmp' ! -name '*.z' ! -name '*.deb' ! -name '*.bcbend' \
    -exec sed -i 's/\r$//' {} +
mkdir "$STAGE/flasher"
cp "$DEPLOY/firmware/original-v1.1.bin" "$STAGE/flasher/approved-original-v1.1.bin"
cp "$DEPLOY/firmware/bendcnc-v1.3.bin" "$STAGE/flasher/bendcnc-v1.3.bin"
cp "$HERE/dfu-util_0.9-1_arm64.deb" "$STAGE/flasher/"
for h in bendcnc-flash-firmware bendcnc-app-update bendcnc-import-shell bendcnc-import-keys; do
    tr -d '\r' < "$DEPLOY/arm64/$h" > "$STAGE/flasher/$h"
done

docker run --rm --privileged -v /dev:/dev \
    --mount type=bind,source="$BASE",target=/input/bendcnc-base.img,readonly \
    --mount type=bind,source="$BUNDLE",target=/input/bendcnc-qt-arm64.tar,readonly \
    --mount type=bind,source="$STAGE/source",target=/source,readonly \
    --mount type=bind,source="$STAGE/flasher",target=/input/flasher,readonly \
    --mount type=bind,source="$SETUP",target=/input/setup,readonly \
    --mount type=bind,source="$OUT",target=/output \
    --tmpfs /work:size=10g \
    -e OUTPUT_IMAGE=/output/BendCNC-OrangePi3B.img \
    -e MANIFEST=/output/BendCNC-OrangePi3B.manifest.txt \
    ubuntu:22.04 bash /source/customize-image.sh
sha256sum "$OUT/BendCNC-OrangePi3B.img" | tee "$OUT/BendCNC-OrangePi3B.img.sha256"
