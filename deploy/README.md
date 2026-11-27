# BendCNC SD image (Orange Pi 3B)

Builds the kiosk image: BendCNC Qt app connected to the BendCNC license server
(license.bendcnc.com; register the machine once with an email, access
terms are set by the server), the BendCNC press firmware v1.3 (`firmware/bendcnc-v1.3.bin`,
built from BendCNC/machine-firmware env `v53_smooth_level`, SHA-256 `23298ce3…901720c`, banner
`[BENDCNC v1.3]`) plus the original factory firmware v1.1 for rollback,
Channel Bracket demo program, and the 3D sequence planner (`sequence-planner/` in the app
bundle with Node 22 arm64 and shapely/numpy/networkx for Python 3.10). Requires Linux/WSL2 with Docker. For an unlicensed build run
`LICENSING=OFF bash deploy/arm64/build-arm64.sh` (or set your own
`LICENSE_SERVER` / `LICENSE_PUBKEY`).

```bash
# 1. Base Armbian image (Orange Pi 3B, Ubuntu jammy minimal)
bash deploy/kiosk-image/armbian-build.sh            # or download an Armbian img
bash deploy/kiosk-image/prepare-base.sh base.img bendcnc-base.img
bash deploy/kiosk-image/verify-base.sh bendcnc-base.img
# 2. ARM64 app bundle (cross build in Docker)
bash deploy/arm64/build-arm64.sh out-arm64
# 3. Final image
bash deploy/kiosk-image/build-image.sh bendcnc-base.img out-arm64/bendcnc-qt-arm64.tar out
# 4. Read-only verification
docker run --rm --privileged -v /dev:/dev -v "$PWD":/w ubuntu:22.04 \
  bash /w/deploy/kiosk-image/verify-image.sh /w/out/BendCNC-OrangePi3B.img
```

Flash `BendCNC-OrangePi3B.img` with balenaEtcher or `dd`.

First boot: hostname `bendcnc` (`bendcnc.local` via mDNS), SSH enabled,
user `cnc` / password `bendcnc` — **expired, must be changed at first login**.
Root is locked. SSH host keys are generated on first boot; `/data` grows to fill the SD.
The root filesystem is read-only (overlayroot tmpfs); persistent state lives in `/data`.
