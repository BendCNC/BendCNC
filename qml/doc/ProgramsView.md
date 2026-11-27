# ProgramsView

## Component Overview

`ProgramsView` is the PROGRAMS tab: a library for the programs that the RUN tab
executes. It is loaded by `main.qml` as tab index 7 and shown second in the
header strip (`LayoutMetrics.tabOrder`). Design notes and data format:
`docs/63-programs-tab.md`.

## Structure

| Item | Description |
|------|-------------|
| `qml/ProgramsView.qml` | `FocusScope` wrapper. Properties `appState`; signal `openInRunRequested()`. |
| `qml/modal-previews/v7-gemini-precision/V7ProgramsLeftView.qml` | The panel (`objectName: "programs-left-panel-v7"`, 864 x 638, v7 tokens shared with the Tools tab). |
| `qml/AppState.qml` | Owns the data and every mutation. The view never edits `programs` directly. |

`main.qml` connects `openInRunRequested` to `requestTabChange(0)`.

## Panel state

| Property | Meaning |
|----------|---------|
| `filterMode`, `filterFolder` | `"all"`, `"unfiled"` or `"folder"` + folder name |
| `searchText` | Case-insensitive name filter |
| `sortKey`, `sortDescending` | Persisted via `appState.persistLocalSetting` |
| `pickedIndex` | Index into `appState.programs` of the highlighted row |
| `rows` | Filtered + sorted view model |
| `railEntries` | Folder rail model with counts |
| `canEdit`, `busyReason` | From `appState.programLibraryBusyReason()` |

Functions: `selectFilter`, `chooseSort`, `openPicked`, `renamePicked`,
`duplicatePicked`, `deletePicked`, `movePickedTo`, `newFolder`,
`renameSelectedFolder`, `deleteSelectedFolder`.

## Object names (tests / automation)

`programs-search`, `programs-sort-<name|created|updated|bends>`,
`programs-new-folder`, `programs-list`, `programs-row-<index>`,
`programs-open-run`, `programs-rename`, `programs-move`, `programs-duplicate`,
`programs-delete`, `programs-move-picker`. Header tab: `left-tab-7`.

## Behaviour notes

- Text entry (search, names) uses the app on-screen keyboard.
- Delete asks through `appState.showConfirmation`.
- When the library is locked (run active or program loading) actions are
  disabled and a strip states the reason.
- Rows keep `appState.programs` indices, so sorting and filtering never change
  which program an action targets.

## Tests

`tests/tst_ProgramLibrary.qml` (AppState rules, in-memory storage),
`tests/tst_ProgramsView.qml` (sort, filter, search, counts, open, lock, move),
`tests/tst_ProgramsOpenInRun.qml` (hand-off to a RunView mounted after the request).
