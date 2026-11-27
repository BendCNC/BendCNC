# BackGaugeControlView

## Status

`BackGaugeControlView.qml` is the production-parity Qt implementation of the legacy Back Gauge tab. It occupies the fixed `864×638.4` left tab area and preserves the separate right column.

## Java authority

The implementation was audited against the production Back Gauge Control, DRO, Homing, Jog Pad, Jog Step, Jog Speed, Move To, Stop, and Status Bar FXML/View/ViewModel/model classes, `DecimalTextField`, `JogPadButton`, `768p.css`, and i18n resources.

## Active controls

- Four press/release jog buttons for X± and R±, plus arrow-key control and `Alt+H` homing. Continuous mode repeats GRBL `$J=` increments and release emits jog-cancel `0x85`; step mode emits one increment.
- Step presets `0.001`, `0.01`, `0.1`, `1`, and `CONTINUOUS`.
- Speed presets `1`, `5`, `10`, `25`, `50`, and `RAPID`.
- Editable, clamped step/speed values backed by persisted local settings.
- Editable X/R Move To targets with finite-number validation and Java-order GRBL commands.
- G54–G59 selection, friendly coordinate names, active offset handling, Work/Machine DRO, and per-axis Set/Zero.
- The selected profile and every popup row resolve explicitly through `backGaugeCoordinateDisplayName(id)`, matching the legacy explicit `CoordinateSystemCell` rendering and preventing blank rows.
- Modal touch input mirrors Java's `VirtualInputManager`: the full ten-column QWERTY popup is used for profile names, while a separate compact four-column keypad is used for Work X/R, jog step/speed, and Move To X/R. `virtualInputMode=NEVER` suppresses it.
- Home readiness/limit precheck, confirmation, progress/cancel lifecycle, and completion state.
- STOP emits Java-parity feed hold `!` and soft reset `0x18`, disables controls during reinitialization, then returns to IDLE. X1/X2/R1/R2 limit feedback and decoded GRBL status remain live.

## State and command contracts

`AppState.qml` owns Back Gauge positions, coordinate offsets, presets, limits, readiness, homing, active direction, and command evidence. `core/machine/BackGauge.js` remains the pure authority for `G20/G21`, `G90/G91`, G54–G59, ordered Move To, bump, `$H`, and status decoding. The implementation is mock-safe: without serial hardware it records exact generated commands and updates simulated state.

The shared `MachinePopupLayer.qml` dispatches the Home confirmation/cancel action through `AppState.performPopupPrimaryAction()`.

## Geometry

| Region | Java-derived mapping |
|---|---:|
| Left content width | `864` |
| Local tab height | `638.4` |
| Main content height | `593.6` |
| Right cards | `x=362.4`, `w=493.6` |
| Status bar | `y=593.6`, `h=44` |

The base parity capture is `visual-artifacts/back-gauge-java-parity-final-20260808.png`. Current keyboard evidence is stored in `back-gauge-qwerty-osk-java-parity-20260808.png` and `back-gauge-numeric-osk-java-parity-20260808.png`. All fields, popup rows, keyboard keys, numeric presets, units, buttons, limits, and status text fit without clipping.

## Verification

- CMake targets `prototype` and `sheetmetal_qml_tests` build successfully.
- `tests/tst_BackGaugeControlView.qml`: 17 focused tests pass.
- Full configured QML suite: 171 passed, 0 failed.
- Runtime capture exits 0 with no QML warnings/errors.

The focused tests cover layout containment, visible G54–G59 profile names, Java's numeric value-display/original-value state, square `89×89` numeric keys, labels centered against each button's full bounds, a two-row OK key, equal full-QWERTY key heights, and a left-aligned title and close control sharing the same vertical center 2 px above the popup header's geometric midpoint. They also cover Java first-key numeric replacement, Shift→Caps cycling, symbol mode, cancel restoration, QWERTY/numeric commit, invalid numeric rejection without target mutation, `NEVER` suppression, coordinate set/Move To, Work/Machine offsets, settings clamp/Continuous/Rapid, repeated `$J` and `0x85` cancellation, STOP `!`/`0x18` recovery, homing/limit lifecycle and cancellation, status decoding, and disconnect reset.