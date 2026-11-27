# BendCNC

Operator HMI for the **Titan 25T** CNC hydraulic press brake, written in **Qt 6 / QML / C++**.

The same code base runs on:

- the machine panel — ARM64 Linux single-board computer (e.g. Orange Pi 3B) with a touch screen,
- Windows / Linux PCs — for offline programming and simulation,
- Android tablets — USB serial to the controller.

It talks to the [BendCNC machine firmware](https://github.com/BendCNC/machine-firmware) over a
serial port and imports parts exported by the
[BendCNC Fusion add-in](https://github.com/BendCNC/fusion-addin).

> ⚠️ **SAFETY WARNING**
> This software commands a hydraulic press brake. Use it only with the machine's hardware
> safety systems in place. You use this software entirely at your own risk (see the GPL-3.0
> "no warranty" clauses).

---

## Features

- **Run** — execute programs bend by bend with live ram/back-gauge DRO, tonnage and a 3D
  simulation of each bend (part, punch, die and back-gauge fingers).
- **Programs** — library of saved bend programs.
- **Create bend** — edit bends: angle, material, thickness, flange length, back-gauge position,
  dwell, tonnage.
- **Tools** — punch and die catalog.
- **Back gauge** — back-gauge jog and positioning.
- **Manual** — manual ram/back-gauge jog, measurement and calibration.
- **CAD import** — open `.bend` files from the Fusion add-in; automatic bend sequence,
  orientation and gauging.
- **Settings** — units (inch/mm), speeds, safety, serial port, display sleep, Wi-Fi (panel).
- **Firmware** — firmware version check / update from the panel.
- **Simulation mode** — without a press connected the app runs in simulation, so every screen can
  be used on a PC.

---

## Repository layout

| Path | Contents |
|---|---|
| `src/main.cpp` | Application entry point |
| `src/MachineControlBackend.*`, `src/MachineProtocolParsers.*` | Machine state, command dispatch and serial protocol parsing |
| `src/SerialMachineTransport.*`, `src/SerialDeviceDiscovery.*`, `src/NullMachineTransport.*`, `src/AndroidUsbSerialPort.*` | Serial transports (desktop, Android USB, simulation) |
| `src/MachineFirmwareBackend.*` | Firmware version check / update |
| `src/HostSystemBackend.*`, `src/DisplaySleepController.*` | Panel OS integration (Wi-Fi, display sleep, restart) |
| `src/NativeRunRenderer.*`, `src/CanvasPainterRunRenderer.*`, `live3d/` | Run-view 2D/3D renderers |
| `src/UnfoldSequencePlanner.*` | Bridge to the bend-sequence planner |
| `sequence-planner/` | Git submodule: [BendCNC/sequence-planner](https://github.com/BendCNC/sequence-planner) |
| `src/PressTelemetryRecorder.*`, `src/RunFrameTiming.*` | Telemetry recording and frame timing |
| `src/LicenseManager.*` | Optional license client (disabled by default, see below) |
| `qml/` | All views (`*View.qml`), popups and `AppState.qml` |
| `qml/core/` | Pure-JS engines: sheet-metal fold solver, pose graph, sequence mapping |
| `qml/data/current/` | Initial (empty) catalogs and settings |
| `qml/fonts/`, `qml/icons/`, `assets/` | Fonts and images |
| `viewer3d/` | Stand-alone 3D scene viewer (`unfold3d_viewer`) |
| `tests/` | Qt Quick Test (`tst_*.qml`) and C++ unit tests (`tst_*.cpp`) |
| `cmake/`, `tools/feature-guard.txt` | Build-time feature regression guard |

---

## Requirements

| | Version |
|---|---|
| Qt | **6.8 or newer** (developed with 6.11). Modules: Quick, QuickControls2, SerialPort, Network, Concurrent. Optional: Quick3D, CanvasPainter |
| CMake | 3.16+ |
| Build tool | Ninja (recommended) |
| Compiler | C++17: MinGW 13 / MSVC 2022 (Windows), GCC 11+ / Clang 14+ (Linux) |
| Node.js | 18+ (sequence planner and JS tests) |
| Python | 3.10+ with Shapely 2.1+ and NumPy (sequence planner import step) |

Install Qt with the [Qt Online Installer](https://www.qt.io/download-qt-installer-oss) and select,
for your kit: **Qt Quick 3D**, **Qt Serial Port** and **Qt Shader Tools** (plus **Android** if needed).

### Quick setup (CAD import runtime)

One script installs Python, the Python packages and Node.js, and initializes the submodule:

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File setup.ps1
```

```sh
# Linux / macOS
./setup.sh
```

On Windows it uses `winget` when Python or Node.js are missing and sets `UNFOLD_PYTHON` so the app
always uses the interpreter that has Shapely. FreeCAD is not required.

### Sequence planner (submodule)

Automatic bend sequencing on CAD import uses the
[sequence-planner](https://github.com/BendCNC/sequence-planner) submodule. If you cloned without
`--recurse-submodules`, run:

```sh
git submodule update --init
pip install shapely numpy networkx
```

The app finds it in the source checkout automatically. For an installed copy, place a
`sequence-planner/` folder next to the executable, or set `BENDCNC_UNFOLD_DIR`. Without the
planner, everything else works; you can still sequence bends manually.

---

## Building

### Windows (MinGW)

```powershell
git clone --recurse-submodules https://github.com/BendCNC/BendCNC.git
cd BendCNC
$env:Path = "C:\Qt\Tools\mingw1310_64\bin;C:\Qt\Tools\Ninja;C:\Qt\Tools\CMake_64\bin;$env:Path"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=C:/Qt/6.11.2/mingw_64
cmake --build build --target prototype
C:\Qt\6.11.2\mingw_64\bin\windeployqt.exe --qmldir qml build\prototype.exe   # copy Qt DLLs next to the exe
.\build\prototype.exe
```

Adjust the Qt version and kit paths to your installation.
You can also open `CMakeLists.txt` directly in **Qt Creator** or VS Code (CMake Tools).

### Linux (desktop)

```sh
sudo apt install build-essential ninja-build cmake libgl1-mesa-dev   # Debian/Ubuntu
git clone --recurse-submodules https://github.com/BendCNC/BendCNC.git
cd BendCNC
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$HOME/Qt/6.11.2/gcc_64
cmake --build build --target prototype
./build/prototype
```

Serial access needs your user in the `dialout` group: `sudo usermod -aG dialout $USER`.

### ARM64 panel (Orange Pi / Raspberry Pi class boards)

Either build natively on the board with Qt 6.8+ for `linux-aarch64` (same commands as Linux), or
cross-compile from a PC with a Qt for aarch64 sysroot:

```sh
cmake -S . -B build-arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=<your-aarch64-toolchain>.cmake \
      -DQT_HOST_PATH=$HOME/Qt/6.11.2/gcc_64 \
      -DCMAKE_PREFIX_PATH=<sysroot>/opt/Qt/6.11.2
cmake --build build-arm64 --target prototype
```

On a kiosk panel without a desktop, run with `-platform eglfs` (or `linuxfb`), for example
`QT_QPA_PLATFORM=eglfs ./prototype`.

### Android

Install the Qt *Android arm64-v8a* kit, Android SDK/NDK (via Qt Creator → Preferences → Devices →
Android), then:

```sh
<Qt>/6.11.2/android_arm64_v8a/bin/qt-cmake -S . -B build-android -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DANDROID_SDK_ROOT=<sdk> -DANDROID_NDK_ROOT=<ndk>
cmake --build build-android --target apk
```

USB serial on Android uses `src/AndroidUsbSerialPort.cpp`. An optional custom Android package
directory (manifest, icons) can be passed with `-DBENDCNC_ANDROID_PACKAGE_DIR=<dir>`.

### Build options

| Option | Default | Meaning |
|---|---|---|
| `BENDCNC_LICENSING` | `OFF` | Enables the license client. Requires `BENDCNC_LICENSE_SERVER` and `BENDCNC_LICENSE_PUBKEY` (Ed25519, base64) and OpenSSL. Leave OFF for normal builds — no server or keys are part of this repository. |
| `BENDCNC_REQUIRE_CANVAS_PAINTER` | `OFF` | Fail configuration if the Qt CanvasPainter module is missing (otherwise it is used when available). |

---

## Running

- Without a controller connected the app starts in **simulation**; all screens work.
- To connect to a press, plug in the controller's USB cable and choose the serial port in
  **Settings**. The firmware uses 115200 baud.
- User data (programs, tools, settings) is stored in the platform's application-data folder.
  The app starts with empty tool, material and program catalogs; add your punches, dies and
  materials in **Tools** / **Settings**.

### Environment variables

| Variable | Purpose |
|---|---|
| `BENDCNC_UNFOLD_DIR` | Override the sequence-planner folder |
| `UNFOLD_PYTHON` | Python interpreter used by the planner |
| `BENDCNC_UNFOLD_BUDGET_MS` | Time budget for the planner |
| `BENDCNC_FIRMWARE_CATALOG_DIR`, `BENDCNC_FIRMWARE_UPDATES` | Location / enablement of firmware update images |
| `BENDCNC_QT_HOME` | Override the data directory |

---

## Tests

```sh
cmake --build build                         # builds the app and all test executables
ctest --test-dir build --output-on-failure
```

QML tests use Qt Quick Test (`tests/tst_*.qml`, runner `tests/qmltest_main.cpp`); C++ tests use
Qt Test. A feature regression guard (`cmake/FeatureGuard.cmake` + `tools/feature-guard.txt`) runs on
every build and fails if a required feature marker disappears from the sources.

---

## Related projects

- [machine-firmware](https://github.com/BendCNC/machine-firmware) — press controller firmware (Arduino UNO R4)
- [fusion-addin](https://github.com/BendCNC/fusion-addin) — Autodesk Fusion add-in that exports `.bend` files

## Contributing

Issues and pull requests are welcome. Please run `ctest` before submitting and describe how
machine-facing changes were tested.

## License

Copyright (C) 2026 BendCNC — <support@bendcnc.com>

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE).

Bundled fonts (Fira Sans, Noto) are licensed under the SIL Open Font License.
