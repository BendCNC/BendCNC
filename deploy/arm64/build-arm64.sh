#!/bin/bash
# Build the BendCNC ARM64 kiosk bundle (bendcnc-qt-arm64.tar) for the
# Orange Pi 3B. Cross-compiles on the host; needs Docker with buildx + binfmt.
#
#   deploy/arm64/build-arm64.sh [OUT_DIR]
#
# The ARM64 Qt 6.11.2 runtime image is built once from the qt-runtime-build
# stage of deploy/arm64/Dockerfile (slow, ~1-2 h under QEMU) and then reused.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:-$REPO/build-arm64}
QT_IMAGE=${QT_IMAGE:-bendcnc/qt-arm64:6.11.2}
# Official images use the BendCNC license server (machine registration). LICENSING=OFF builds an unlicensed app.
LICENSING=${LICENSING:-ON}
LICENSE_SERVER=${LICENSE_SERVER:-https://license.bendcnc.com}
LICENSE_PUBKEY=${LICENSE_PUBKEY:-8wWHEiwJ2wtykgiP9RNIfiZAu5y8CKNA+EmFO3i4Qjc=}
CTX=$(mktemp -d)
trap 'rm -rf "$CTX"' EXIT

mkdir -p "$CTX/qt" "$CTX/deploy-arm64" "$CTX/assets/firmware-catalog"
tar -C "$REPO" --exclude=.git --exclude=node_modules --exclude=__pycache__ \
    --exclude='./build' --exclude='./build-*' --exclude='./deploy' -cf - . | tar -C "$CTX/qt" -xf -
cp "$HERE"/* "$CTX/deploy-arm64/"
cp -r "$REPO/assets/Dies" "$REPO/assets/Punches" "$REPO/assets/Fingers" "$REPO/assets/bcbends" "$CTX/assets/"
cp "$REPO/assets/Finger Side.dxf.bct" "$REPO/assets/Finger Top.dxf.bct" "$CTX/assets/"

# ORIGINAL factory firmware v1.1 (rollback image for the supervised flasher).
FW="$REPO/deploy/firmware/original-v1.1.bin"
FW_SHA=c9c3564be37c300f864b8aab22a6ad2b7a9e9a20a95474504dadb6aaad0b8426
[[ $(sha256sum "$FW" | cut -d' ' -f1) == "$FW_SHA" ]] || { echo "firmware hash mismatch" >&2; exit 2; }
cp "$FW" "$CTX/assets/firmware-catalog/original-v1.1.bin"
# BendCNC press firmware (built from BendCNC/machine-firmware, env v53_smooth_level).
BFW="$REPO/deploy/firmware/bendcnc-v1.3.bin"
BFW_SHA=23298ce3d7ebcb986496b3e4cfc972769f51fb81787bd2b4e12966e9b901720c
[[ $(sha256sum "$BFW" | cut -d' ' -f1) == "$BFW_SHA" ]] || { echo "bendcnc firmware hash mismatch" >&2; exit 2; }
cp "$BFW" "$CTX/assets/firmware-catalog/bendcnc-v1.3.bin"
cat > "$CTX/assets/firmware-catalog/firmware-catalog.json" <<EOF
{"schema":1,"images":[{"id":"original","kind":"original","title":"ORIGINAL","version":"v1.1",
"description":"Factory v1.1 firmware","expectedVersion":"[LS-BEND v1.1]",
"label":"original-v1.1","file":"original-v1.1.bin","sha256":"$FW_SHA",
"size":$(stat -c %s "$FW"),"autoRollback":false},
{"id":"current","kind":"current","title":"BENDCNC","version":"v1.3",
"description":"BendCNC press firmware","expectedVersion":"[BENDCNC v1.3]",
"label":"bendcnc-v1.3","file":"bendcnc-v1.3.bin","sha256":"$BFW_SHA",
"size":$(stat -c %s "$BFW"),"autoRollback":true}]}
EOF
find "$CTX" -type f \( -name '*.sh' -o -name 'Dockerfile*' -o -name 'bendcnc-*' \) ! -name '*.bin' -exec sed -i 's/\r$//' {} +

if ! docker image inspect "$QT_IMAGE" >/dev/null 2>&1; then
    echo "Building ARM64 Qt runtime image $QT_IMAGE (one time)..."
    docker buildx build --platform linux/arm64 --target qt-runtime-build --load \
        -t "$QT_IMAGE" -f "$CTX/deploy-arm64/Dockerfile" "$CTX"
fi
COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
docker buildx build --platform linux/arm64 -f "$CTX/deploy-arm64/Dockerfile.cross" \
    --build-arg QT_ARM_IMAGE="$QT_IMAGE" --build-arg LICENSING="$LICENSING" --build-arg LICENSE_SERVER="$LICENSE_SERVER" \
    --build-arg LICENSE_PUBKEY="$LICENSE_PUBKEY" --build-arg GIT_COMMIT="$COMMIT" \
    --output "type=local,dest=$CTX/cross-out" "$CTX"
mkdir -p "$OUT"
docker buildx build --platform linux/arm64 -f "$CTX/deploy-arm64/Dockerfile" \
    --build-context qt-runtime-build=docker-image://"$QT_IMAGE" \
    --build-context build="$CTX/cross-out" \
    --output "type=local,dest=$OUT" "$CTX"
# First-boot setup wizard (welcome, EULA, email verification, app download).
docker buildx build --platform linux/arm64 -f "$CTX/deploy-arm64/Dockerfile.cross" --target export-setup \
    --build-arg QT_ARM_IMAGE="$QT_IMAGE" --output "type=local,dest=$CTX/setup-out" "$CTX"
rm -rf "$OUT/setup"; cp -r "$CTX/setup-out/out" "$OUT/setup"
# 3D sequence planner (re-run planner): unfold engine next to the app binary
# (UnfoldSequencePlanner looks in <app>/sequence-planner) with its own Node and
# Python packages; the press image provides python3.10 only.
NODE_VER=${NODE_VER:-22.11.0}
PL="$CTX/planner/sequence-planner"
mkdir -p "$PL/runtime/node" "$PL/runtime/python"
cp -r "$REPO/sequence-planner/engine" "$REPO/sequence-planner/tools" "$REPO/sequence-planner/viewer" "$PL/"
cp "$REPO/sequence-planner/LICENSE" "$PL/" 2>/dev/null || true
git -C "$REPO/sequence-planner" rev-parse --short=12 HEAD > "$PL/ENGINE_REVISION" 2>/dev/null || echo unknown > "$PL/ENGINE_REVISION"
find "$PL" \( -name __pycache__ -o -name '*.test.mjs' \) -prune -exec rm -rf {} +
curl -fsSL "https://nodejs.org/dist/v$NODE_VER/node-v$NODE_VER-linux-arm64.tar.xz" \
    | tar -xJ -C "$PL/runtime/node" --strip-components=1
rm -rf "$PL/runtime/node/include" "$PL/runtime/node/share" "$PL/runtime/node/lib/node_modules/npm" "$PL/runtime/node/lib/node_modules/corepack" \
    "$PL/runtime/node/bin/npm" "$PL/runtime/node/bin/npx" "$PL/runtime/node/bin/corepack"
docker run --rm -v "$PL/runtime/python:/t" python:3.10-slim pip install -q --no-cache-dir --target /t \
    --platform manylinux2014_aarch64 --platform manylinux_2_17_aarch64 --python-version 3.10 \
    --implementation cp --only-binary=:all: shapely==2.1.2 numpy==2.2.6 networkx==3.4.2
docker run --rm -v "$PL:/p" alpine chown -R "$(id -u):$(id -g)" /p
tar -rf "$OUT/bendcnc-qt-arm64.tar" -C "$CTX/planner" sequence-planner
tar -tf "$OUT/bendcnc-qt-arm64.tar" > "$CTX/list.txt"
grep -qx prototype "$CTX/list.txt" && grep -q 'assets/Dies/.*\.bct$' "$CTX/list.txt"
grep -qx 'sequence-planner/tools/plan_sequence.mjs' "$CTX/list.txt" && grep -qx 'sequence-planner/runtime/node/bin/node' "$CTX/list.txt"
grep -q '^sequence-planner/runtime/python/shapely/' "$CTX/list.txt"
# bendcnc-deploy-kiosk rejects anything that is not a regular file or directory.
! tar -tvf "$OUT/bendcnc-qt-arm64.tar" | grep -qv '^[-d]' || { echo "bundle contains links/special files" >&2; exit 1; }
sha256sum "$OUT/bendcnc-qt-arm64.tar" | tee "$OUT/bendcnc-qt-arm64.tar.sha256"
