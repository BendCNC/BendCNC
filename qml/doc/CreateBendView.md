# `CreateBendView.qml`

`CreateBendView` is the production Create Bend editor. It mirrors the legacy entity-editing lifecycle rather than mutating persisted bends directly.

## Editing lifecycle

- `beginEdit()` creates an isolated draft and snapshot.
- `createNew()` uses Java-compatible blank tooling, `NaN` thickness/angle, `0.050 in` clearance, and the configured default Back Gauge R.
- `duplicateCurrent()` copies every source field, generates a new ID/name, and remains unsaved until Save.
- `cancelEditing()` restores the source record.
- `resetEditing()` restores Java defaults while preserving identity/name/date.
- `saveEditing()` requires valid tooling, finite fields, a unique name, and a real change/new record.
- `requestDelete()` uses a confirmation callback before removing the record.

`workingBends`, `draftBend`, and `editSnapshot` form the transaction boundary. `AppState.createBendAction()` performs persistence and returns the updated record set.

## Calculations and warnings

`calculation` calls `core/BendCalculator.js`, the Qt port of Java `BendCalculator`. The result supplies safety clearance, clamp/final/retract positions, stroke, tonnage, predicted radius, limits, and warning states. Warning cards are generated from those states; no static mock warning text is used.

The final-position override exposes a numeric editor and locks incompatible tooling/angle fields. Compensation direction explicitly displays `OVERBENT` or `UNDERBENT`.

## Persistence contract

Tool selectors persist canonical Punch/Die/Material IDs. Notes, Back Gauge fields, override fields, original/source metadata, and calculated runtime fields are preserved by `AppState.bendFromCreateDraft()`. Load Into Program validates machine travel, appends a complete bend, and persists the program through the shared storage path.

## Layout

The panel is `modal-previews/v7/V7CreateBendLeftView.qml`, loaded by `CreateBendV7View.qml`. It has a header (bend selector, rename, delete), light input cards on the left (Tooling, Bend Angle, Workpiece & Clearances, Back Gauge, Program Notes), a dark result rail on the right (final ram position, tonnage and status, calculated positions, vertical diagram, Manual Ram Override) and a footer (new, save, duplicate, reset, load into program). Sizes derive from `u = max(0.85, min(width/864, height/638.4))`, so fonts and touch targets grow with the panel. While the calculator reports alerts, the Program Notes card shows them instead of the notes (with an Edit Notes button) and the tonnage tile shows the alert count; the footer hint states why Save is disabled. Program Notes edits the bend's `notes` field; `xAxisNotes` and `rAxisNotes` are preserved in storage but are not editable in this view. See `docs/65-create-bend-cards-and-result-rail.md` and `docs/64-create-bend-layout-redesign.md`.

## Touch input

Text fields use the shared QWERTY OSK. Numeric fields use the compact numeric OSK. Read-only calculator outputs do not open a keyboard.

## Vertical positions diagram

`showVerticalDiagram()` opens the Java-authoritative image packaged at `images/info/create_bend/vertical_diagram.png` together with current calculated positions. The top-level capture harness supports `--popup-snapshot=vertical-diagram` for visual regression proof.

## Tests

- `tests/tst_CreateBendReferenceEdgeStop.qml`: shared profiles, OSKs, defaults, compensation, override, and diagram request.
- `tests/tst_CreateBendLifecycle.qml`: serialization, create/save/duplicate/delete, Load Into Program, and machine travel limits.
