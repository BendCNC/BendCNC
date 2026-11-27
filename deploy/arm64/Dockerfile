FROM ubuntu:22.04 AS qt-build

ARG QT_VERSION=6.11.2
ARG QT_DOWNLOAD_ROOT=https://download.qt.io/official_releases/qt/6.11/6.11.2/submodules

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        gperf \
        libdbus-1-dev \
        libdrm-dev \
        libegl1-mesa-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libgbm-dev \
        libgl-dev \
        libharfbuzz-dev \
        libinput-dev \
        libjpeg-dev \
        libpng-dev \
        libwayland-dev \
        libxkbcommon-dev \
        libxkbcommon-x11-dev \
        libwayland-bin \
        ninja-build \
        perl \
        pkg-config \
        python3 \
        wayland-protocols \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /qt-src
RUN for module in qtbase qtshadertools qtdeclarative qtsvg qtserialport qtcanvaspainter; do \
        curl --fail --location --retry 5 \
            "$QT_DOWNLOAD_ROOT/${module}-everywhere-src-$QT_VERSION.tar.xz" \
            --output "$module.tar.xz"; \
        mkdir "$module"; \
        tar -xJf "$module.tar.xz" --strip-components=1 -C "$module"; \
        rm "$module.tar.xz"; \
    done

RUN cmake -S /qt-src/qtbase -B /qt-build/qtbase -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/qt \
        -DQT_BUILD_EXAMPLES=OFF \
        -DQT_BUILD_TESTS=OFF \
        -DFEATURE_eglfs=ON \
        -DFEATURE_wayland_client=ON \
        -DFEATURE_xcb=OFF \
        -DFEATURE_opengl=ON \
    && cmake --build /qt-build/qtbase --parallel 2 \
    && cmake --install /qt-build/qtbase

RUN mkdir -p /qt-build/qtshadertools \
    && cd /qt-build/qtshadertools \
    && /opt/qt/bin/qt-configure-module /qt-src/qtshadertools \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    && cmake --build . --parallel 2 \
    && cmake --install .

RUN mkdir -p /qt-build/qtdeclarative \
    && cd /qt-build/qtdeclarative \
    && /opt/qt/bin/qt-configure-module /qt-src/qtdeclarative \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    && cmake --build . --parallel 12 \
    && cmake --install .

RUN mkdir -p /qt-build/qtsvg \
    && cd /qt-build/qtsvg \
    && /opt/qt/bin/qt-configure-module /qt-src/qtsvg \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    && cmake --build . --parallel 12 \
    && cmake --install .

RUN mkdir -p /qt-build/qtserialport \
    && cd /qt-build/qtserialport \
    && /opt/qt/bin/qt-configure-module /qt-src/qtserialport \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    && cmake --build . --parallel 12 \
    && cmake --install .

RUN mkdir -p /qt-build/qtcanvaspainter \
    && cd /qt-build/qtcanvaspainter \
    && /opt/qt/bin/qt-configure-module /qt-src/qtcanvaspainter \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    && cmake --build . --parallel 12 \
    && cmake --install . \
    && /opt/qt/bin/qtpaths --query QT_VERSION | grep -Fx "$QT_VERSION" \
    && test -f /opt/qt/lib/libQt6Core.so.$QT_VERSION \
    && test -f /opt/qt/lib/libQt6CanvasPainter.so.$QT_VERSION

FROM qt-build AS qt-runtime-build

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libwayland-dev \
        libxkbcommon-x11-dev \
        libwayland-bin \
        wayland-protocols \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --retry 5 \
        "$QT_DOWNLOAD_ROOT/qtwayland-everywhere-src-$QT_VERSION.tar.xz" \
        --output /tmp/qtwayland.tar.xz \
    && mkdir /qt-src/qtwayland \
    && tar -xJf /tmp/qtwayland.tar.xz --strip-components=1 -C /qt-src/qtwayland \
    && rm /tmp/qtwayland.tar.xz \
    && mkdir -p /qt-build/qtwayland \
    && cd /qt-build/qtwayland \
    && /opt/qt/bin/qt-configure-module /qt-src/qtwayland \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
        -DQT_FEATURE_wayland_client=ON -DQT_FEATURE_wayland_server=OFF \
    && cmake --build /qt-build/qtwayland --parallel 12 \
    && cmake --install /qt-build/qtwayland \
    && test -f /opt/qt/plugins/platforms/libqwayland.so

# LIVE 3D view (qml/LiveScene3D.qml). Separate layer so earlier Qt layers stay cached.
RUN curl --fail --location --retry 5 \
        "$QT_DOWNLOAD_ROOT/qtquick3d-everywhere-src-$QT_VERSION.tar.xz" \
        --output /tmp/qtquick3d.tar.xz \
    && mkdir /qt-src/qtquick3d \
    && tar -xJf /tmp/qtquick3d.tar.xz --strip-components=1 -C /qt-src/qtquick3d \
    && rm /tmp/qtquick3d.tar.xz \
    && mkdir -p /qt-build/qtquick3d \
    && cd /qt-build/qtquick3d \
    && /opt/qt/bin/qt-configure-module /qt-src/qtquick3d \
        -- -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
        -DQT_FEATURE_quick3d_assimp=OFF -DQT_FEATURE_quick3dxr_openxr=OFF \
    && cmake --build /qt-build/qtquick3d --parallel 12 \
    && cmake --install /qt-build/qtquick3d \
    && rm -rf /qt-build/qtquick3d /qt-src/qtquick3d \
    && test -f /opt/qt/lib/libQt6Quick3D.so.$QT_VERSION

FROM ubuntu:22.04 AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        libdbus-1-dev \
        libdrm-dev \
        libegl1-mesa-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libgbm-dev \
        libgl-dev \
        libharfbuzz-dev \
        libinput-dev \
        libjpeg-dev \
        libpng-dev \
        libxkbcommon-dev \
        ninja-build \
    && rm -rf /var/lib/apt/lists/*

COPY --from=qt-runtime-build /opt/qt /opt/qt

WORKDIR /src
COPY qt/ .
RUN cmake -S . -B /build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DCMAKE_PREFIX_PATH=/opt/qt -DBENDCNC_REQUIRE_CANVAS_PAINTER=ON \
    && cmake --build /build --target prototype --parallel 12 \
    && install -D -m 0755 /build/prototype /out/prototype \
    && readelf -d /out/prototype | grep -F 'libQt6CanvasPainter.so.6' \
    && readelf -d /out/prototype | grep -F 'libQt6Quick3D.so.6'

FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && mkdir -p /packages /runtime \
    && cd /packages \
    && apt-get download \
        libb2-1 \
        libblkid1 \
        libbsd0 \
        libbrotli1 \
        libdbus-1-3 \
        libdouble-conversion3 \
        libdrm2 \
        libegl1 \
        libexpat1 \
        libevdev2 \
        libffi8 \
        libfontconfig1 \
        fontconfig-config \
        fonts-dejavu-core \
        libfreetype6 \
        libgbm1 \
        libgl1 \
        libglx0 \
        libglvnd0 \
        libglib2.0-0 \
        libgomp1 \
        libgcrypt20 \
        libgpg-error0 \
        libgraphite2-3 \
        libgudev-1.0-0 \
        libharfbuzz0b \
        libicu70 \
        libinput10 \
        libjpeg-turbo8 \
        liblz4-1 \
        liblzma5 \
        libmd4c0 \
        libmd0 \
        libmtdev1 \
        libmount1 \
        libopengl0 \
        libpcre2-16-0 \
        libpcre2-8-0 \
        libpng16-16 \
        libproxy1v5 \
        libpcre3 \
        libselinux1 \
        libsm6 \
        libsystemd0 \
        libcap2 \
        libts0 \
        libx11-6 \
        libx11-xcb1 \
        libxau6 \
        libxdmcp6 \
        libxcb1 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-shm0 \
        libxcb-sync1 \
        libxcb-xfixes0 \
        libxcb-xinput0 \
        libxcb-xkb1 \
        libxkbcommon0 \
        libxkbcommon-x11-0 \
        libice6 \
        libwayland-client0 \
        libwayland-cursor0 \
        libwayland-egl1 \
        libwayland-server0 \
        libudev1 \
        libuuid1 \
        libwacom9 \
        libxcb-util1 \
        zlib1g \
        libzstd1 \
        libssl3 \
    && for package in /packages/*.deb; do \
        dpkg-deb -x "$package" /runtime; \
    done \
    && rm -rf /runtime/usr/share/doc /runtime/usr/share/lintian /runtime/usr/share/man

FROM ubuntu:22.04 AS package

RUN apt-get update \
    && apt-get install -y --no-install-recommends binutils python3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/prototype /package/prototype
COPY --from=runtime /runtime/ /package/runtime/
COPY --from=qt-runtime-build /opt/qt/lib/ /package/runtime/usr/lib/aarch64-linux-gnu/
COPY --from=qt-runtime-build /opt/qt/plugins/ /package/runtime/usr/lib/aarch64-linux-gnu/qt6/plugins/
COPY --from=qt-runtime-build /opt/qt/qml/ /package/runtime/usr/lib/aarch64-linux-gnu/qt6/qml/
COPY --chmod=0755 deploy-arm64/launch-offline.sh /package/launch-offline.sh
COPY --chmod=0755 deploy-arm64/switch-to-qt.sh /package/switch-to-qt.sh
COPY --chmod=0755 deploy-arm64/launch-normal.sh /package/launch-normal.sh
COPY --chmod=0755 deploy-arm64/switch-to-qt-normal.sh /package/switch-to-qt-normal.sh
COPY --chmod=0755 deploy-arm64/import-bcbend.sh /package/import-bcbend.sh
COPY --chmod=0755 deploy-arm64/deploy-kiosk-bundle.sh /package/deploy-kiosk-bundle.sh
COPY --chmod=0755 deploy-arm64/install-passwordless-deploy.sh /package/install-passwordless-deploy.sh
COPY --chmod=0755 deploy-arm64/recover-press-usb.sh /package/recover-press-usb.sh
COPY --chmod=0755 deploy-arm64/restore-java.sh /package/restore-java.sh
COPY --chmod=0644 deploy-arm64/bendcnc-qt.desktop /package/bendcnc-qt.desktop
COPY assets/Dies/ /package/assets/Dies/
COPY assets/Punches/ /package/assets/Punches/
COPY ["assets/Finger Side.dxf.bct", "/package/assets/Finger Side.dxf.bct"]
COPY ["assets/Finger Top.dxf.bct", "/package/assets/Finger Top.dxf.bct"]
COPY assets/Fingers/ /package/assets/Fingers/
COPY assets/firmware-catalog/ /package/assets/firmware-catalog/
COPY assets/bcbends/ /package/assets/bcbends/
RUN sed -i 's/\r$//' \
    /package/*.sh \
    && chmod 0755 /package/prototype \
        /package/launch-offline.sh \
    /package/switch-to-qt.sh \
    /package/launch-normal.sh \
    /package/switch-to-qt-normal.sh \
    /package/import-bcbend.sh \
    /package/deploy-kiosk-bundle.sh \
    /package/install-passwordless-deploy.sh \
    /package/recover-press-usb.sh \
    /package/restore-java.sh \
    && test -f /package/runtime/usr/lib/aarch64-linux-gnu/libQt6Core.so.6.11.2 \
    && test -f /package/runtime/usr/lib/aarch64-linux-gnu/libQt6CanvasPainter.so.6.11.2 \
    && test -f /package/runtime/usr/lib/aarch64-linux-gnu/qt6/plugins/platforms/libqeglfs.so \
    && test -f /package/runtime/usr/lib/aarch64-linux-gnu/qt6/plugins/platforms/libqwayland.so \
    && rm -rf /package/runtime/usr/lib/aarch64-linux-gnu/cmake \
        /package/runtime/usr/lib/aarch64-linux-gnu/pkgconfig \
    && find /package/runtime/usr/lib/aarch64-linux-gnu -maxdepth 1 -type f \
        \( -name '*.a' -o -name '*.la' -o -name '*.prl' \) -delete \
    && rm -f /package/runtime/usr/lib/aarch64-linux-gnu/libgbm.so* \
    && ! find /package/runtime -type f \
        \( -name 'libgbm.so*' -o -name 'libEGL_mesa.so*' -o -name 'libGLX_mesa.so*' \
           -o -path '*/dri/*.so' \) -print -quit | grep -q . \
    && strip --strip-unneeded /package/prototype \
    && find /package/runtime/usr/lib/aarch64-linux-gnu -type f \
        \( -name '*.so' -o -name '*.so.*' \) \
        -exec strip --strip-unneeded {} + \
    && python3 - <<'PY'
import os
import re
import shutil
import subprocess

root = "/package"
# Replace each ELF symlink family with exactly one regular file named after its
# SONAME. The final archive deliberately contains no links; retaining .so,
# .so.6 and .so.6.x as dereferenced members would otherwise store the same
# payload two or three times on the small /data partition.
elf_groups = {}
for directory, _, names in os.walk(root):
    for name in names:
        path = os.path.join(directory, name)
        try:
            with open(path, "rb") as stream:
                if stream.read(4) != b"\x7fELF":
                    continue
            dynamic = subprocess.run(
                ["readelf", "-d", path], check=True, text=True,
                stdout=subprocess.PIPE,
            ).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        sonames = re.findall(r"\(SONAME\).*?\[(.*?)\]", dynamic)
        if sonames:
            elf_groups.setdefault(os.path.realpath(path), (sonames[0], set()))[1].add(path)

for real_path, (soname, aliases) in elf_groups.items():
    canonical = os.path.join(os.path.dirname(real_path), soname)
    temporary = canonical + ".bundle-copy"
    shutil.copyfile(real_path, temporary)
    for path in aliases | {real_path, canonical}:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    os.replace(temporary, canonical)

system_contract = {
    "ld-linux-aarch64.so.1", "libc.so.6", "libdl.so.2", "libgcc_s.so.1",
    "libm.so.6", "libpthread.so.0", "libresolv.so.2", "librt.so.1",
    "libstdc++.so.6", "libutil.so.1",
    # The RK3566 image owns GBM/Mesa/Panfrost as one coherent graphics stack.
    "libgbm.so.1", "libEGL_mesa.so.0", "libGLX_mesa.so.0",
}
elfs = []
provided = set()
needed_by = {}
for directory, _, names in os.walk(root):
    for name in names:
        path = os.path.join(directory, name)
        try:
            with open(path, "rb") as stream:
                if stream.read(4) != b"\x7fELF":
                    continue
            dynamic = subprocess.run(
                ["readelf", "-d", path], check=True, text=True,
                stdout=subprocess.PIPE,
            ).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        elfs.append(path)
        sonames = re.findall(r"\(SONAME\).*?\[(.*?)\]", dynamic)
        provided.update(sonames)
        dependencies = re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic)
        needed_by[path] = dependencies

missing = {}
for path, dependencies in needed_by.items():
    unresolved = sorted(set(dependencies) - provided - system_contract)
    if unresolved:
        missing[path] = unresolved
if missing:
    for path, dependencies in sorted(missing.items()):
        print(f"UNRESOLVED {path}: {', '.join(dependencies)}")
    raise SystemExit("Bundle has dependencies outside its explicit runtime/system contract")
print(f"ELF-CLOSURE-OK files={len(elfs)} provided={len(provided)}")
PY
RUN mkdir -p /out \
    && tar --numeric-owner --dereference --hard-dereference \
        -C /package -cf /out/bendcnc-qt-arm64.raw.tar \
        prototype runtime assets launch-offline.sh switch-to-qt.sh \
        launch-normal.sh switch-to-qt-normal.sh import-bcbend.sh \
        deploy-kiosk-bundle.sh install-passwordless-deploy.sh \
        recover-press-usb.sh \
        restore-java.sh bendcnc-qt.desktop \
    && python3 - <<'PY'
import tarfile

source = "/out/bendcnc-qt-arm64.raw.tar"
destination = "/out/bendcnc-qt-arm64.tar"
with tarfile.open(source, "r:") as incoming, tarfile.open(destination, "w:") as outgoing:
    for member in incoming:
        if member.isdir() and not member.name.endswith("/"):
            member.name += "/"
        payload = incoming.extractfile(member) if member.isfile() else None
        outgoing.addfile(member, payload)
PY
RUN rm -f /out/bendcnc-qt-arm64.raw.tar

FROM scratch AS export
COPY --from=package /out/ /
