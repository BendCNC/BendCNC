#!/bin/bash
# Public base image for BendCNC: Armbian v25.2.1 (last stable with Jammy support),
# Orange Pi 3B, vendor 6.1 kernel, minimal CLI. No vendor software is used.
set -euo pipefail
ARMBIAN_TAG=${ARMBIAN_TAG:-v25.2.1}
DIR=~/armbian-build-${ARMBIAN_TAG}
[[ -d "$DIR" ]] || git clone -q --depth=1 --branch "$ARMBIAN_TAG" https://github.com/armbian/build "$DIR"
cd "$DIR"
git log --oneline -1
./compile.sh \
    BOARD=orangepi3b BRANCH=vendor RELEASE=jammy \
    BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
    COMPRESS_OUTPUTIMAGE=sha SHARE_LOG=no PESTER_TERMINAL=no < /dev/null 2>&1 | tee ~/armbian-build-${ARMBIAN_TAG}.log
ls -la output/images/
