# DataStore

## Component Overview

`DataStore` is a small Qt/QML data loader for the prototype. It reads copied BendCNC Java JSON storage files from `docs/qt-prototype/qml/data/current/` and exposes bend, program, punch, die, material, local-settings, and user-settings data to QML views.

## Project Structure and Dependencies

| Item | Description |
|------|-------------|
| Source file | `docs/qt-prototype/qml/DataStore.qml` |
| Current consumers | `docs/qt-prototype/qml/ToolsView.qml` and `docs/qt-prototype/qml/CreateBendView.qml` instantiate it to populate controls from copied Java storage. |
| Data files | `data/current/bends.json`, `programs.json`, `punches.json`, `dies.json`, `materials.json`, `local-settings.json`, and `user-settings.json`. |
| Imports | `QtQuick`. |

The data files are copies of Java application storage from `~/.BendCNC`. The QML prototype reads these copies and does not mutate the original Java storage.

When launching the prototype directly with `qmlscene`, set `QML_XHR_ALLOW_FILE_READ=1` for that process so `XMLHttpRequest` can read local JSON files. This should be a temporary launch environment variable, not a persisted system setting.

## Component Hierarchy and Role

The root type is `QtObject`. It has no visual output. It centralizes JSON loading so future QML tabs can reuse the same data source instead of implementing per-view file readers.

## Properties

| Property | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `punches` | `var` | `[]` | No | Array loaded from `data/current/punches.json`. |
| `dies` | `var` | `[]` | No | Array loaded from `data/current/dies.json`. |
| `materials` | `var` | `[]` | No | Array loaded from `data/current/materials.json`. |
| `bends` | `var` | `[]` | No | Array loaded from `data/current/bends.json` for the Create Bend selector and fields. |
| `programs` | `var` | `[]` | No | Array loaded from `data/current/programs.json` for future Create/Run Bend program integration. |
| `localSettings` | `var` | `{}` | No | Object loaded from `data/current/local-settings.json`. |
| `userSettings` | `var` | `{}` | No | Object loaded from `data/current/user-settings.json`. |

## Methods

#### loadJson(path, fallback) : var

Loads a JSON file relative to the QML file, replaces Java-style `NaN` values with `null`, parses the result, and returns the parsed value. If loading or parsing fails, it logs a warning and returns `fallback`.

#### reload() : void

Reloads all current JSON data files and updates the public properties. This is called automatically when the component completes and can be called again by a view after refreshing copied data files.

## Inter-Component Interactions

`ToolsView` binds its module selectors and detail fields to the tool arrays exposed by `DataStore`. `CreateBendView` binds the bend selector, PDM selectors, measurement fields, back gauge controls, calculation fields, and notes areas to the copied bend/tool/material arrays.

The store is intentionally read-only for now; save/duplicate/delete/load behavior can later use the same schema once write support is implemented for the copied JSON files. It must not write to the original Java storage under `~/.BendCNC`.