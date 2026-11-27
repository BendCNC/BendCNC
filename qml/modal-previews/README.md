# Modal design versions

`current/` renders the actual production popup components with simulated state.
It is the exact visual reference and should not contain alternate designs.

Every other subdirectory is an isolated, editable design candidate. Production
QML does not import those candidates. A selected version must be deliberately
ported into the production components after review.

The Design Lab discovers every direct child folder that contains a
`PreviewScene.qml` and shows each version as a button in the top bar. Creating a
new valid version folder therefore requires no manual registry edit. Press
**RELOAD DESIGN / F5** to refresh both the open scene and the visible version
list; select the new version button to open it.

A candidate must replace only the modal it proposes. Every other selector must
instantiate the corresponding production component directly rather than a
detached approximation. Keep previews in the full `1366 × 768` production
coordinate space; the Design Lab rail is an overlay and must not shift modal
centering.

The `Right panel` selector renders the complete production
`ColumnRightView` at its native `462 × 668` geometry, including `LIVE REPORT`
and `USER CONTROLS` as one unit. Use it as the unchanged production reference
when evaluating a right-panel candidate; proposals should remain isolated in
their version folder until explicitly promoted.

## Create a candidate

1. Compare against `current/`, then copy `v1/` to a new folder such as
	`v2-specialist-name/`.
2. Keep `PreviewScene.qml` as the entry point.
3. Edit any QML inside that version folder without changing production QML.
4. Launch the reference with `qt/tools/launch-modal-previewer.ps1` or the
	candidate with `qt/tools/launch-modal-previewer.ps1 -Version v2-specialist-name`.
5. Tell the implementation agent which folder is approved.

The previewer loads source files directly on PC, so ordinary candidate edits only
require pressing **RELOAD DESIGN** (or `F5`); they do not require rebuilding the
embedded QML resources. The launcher configures the known Qt runtime paths and
only closes another Modal Design Lab instance, leaving the normal Qt app open.

Use `-Rebuild` only after changing the designer shell, C++, CMake, or production
QML. That option closes all `prototype.exe` processes because Windows locks the
executable during linking, rebuilds `prototype`, and opens the requested version:

`qt/tools/launch-modal-previewer.ps1 -Version current -Rebuild`

Standard production geometry:

- Operational: `950 × 600`
- Critical: `850 × 500`
- Notification: `550 × 300`