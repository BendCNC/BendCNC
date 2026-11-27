# ToolsView

## Component Overview

`ToolsView` implements the Qt/QML version of the BendCNC Tools tab. It is loaded by `main.qml` as tab index 2 inside the fixed-width left tab content host.

The component mirrors the legacy Punch / Die / Materials screen. It displays three independent tool cards over the darker `#A8A8A8` Tools background. Each card has a colored header, a light grey body, selector/edit controls, detail sections, and bottom action buttons for `NEW`, `SAVE`, and `DUPLICATE`. Selector controls, measurement fields, edit buttons, and action buttons are interactive Qt Quick Controls so the screen can be exercised during visual validation.

## Project Structure and Dependencies

| Item | Description |
|------|-------------|
| Source file | `docs/qt-prototype/qml/ToolsView.qml` |
| Data store | `docs/qt-prototype/qml/DataStore.qml` loads storage JSON copied into `docs/qt-prototype/qml/data/current/`. |
| Loader | `docs/qt-prototype/qml/main.qml` loads it from `tabFiles[2]` into the left tab content area. |
| Imports | `QtQuick`, `QtQuick.Layouts`, and `QtQuick.Controls.Basic`. |
| Icon assets | `docs/qt-prototype/qml/icons/fa-pen.svg`, `fa-trash.svg`, `fa-info-circle.svg`, and `fa-caret-down.svg` provide scalable vectors for the legacy Ikonli icons used by the Tools tab. |

The current data snapshot was copied from the Java application storage under `~/.BendCNC`: `storage/current/punches.json`, `dies.json`, `materials.json`, plus `local-settings.json` and `user-settings.json`. These files are treated as prototype inputs; the original storage files are not mutated by QML.

For local `qmlscene` launches, `QML_XHR_ALLOW_FILE_READ=1` must be set temporarily so `DataStore.qml` can read the copied JSON files.

The component is sized for the same 864 px left tab content host used by the legacy app. It does not interact with the application right column and should remain contained within the left tab area.

## Component Hierarchy and Role

The root type is an `Item` with `objectName: "punch-die-materials-view ..."`. It paints the dark grey Tools background and positions three inline `ToolModule` instances:

| Module | Source | Accent | Role |
|--------|---------------|--------|------|
| `PUNCH` | `PunchView.fxml` | `#A82011` | Displays punch selector, original specs, available segments, and punch action buttons. |
| `DIE` | `DieView.fxml` | `#2D83B2` | Displays die selector, original specs, advanced details, available segments, and die action buttons. |
| `MATERIALS` | `MaterialView.fxml` | `#59A60C` | Displays material selector, material defaults, thickness profile, and material action buttons. |

The current layout uses runtime coordinates: the cards begin at local x positions `7.2`, `292.8`, and `578.4`, with a height of `623.2`. The root vertical scale is based on the legacy local Tools height of `638.4`.

## Properties

### Root Properties

| Property | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `sx` | `real` | `width / 864` | No | Horizontal scale factor for Tools coordinates. |
| `sy` | `real` | `height / 638.4` | No | Vertical scale factor for Tools local coordinates inside the tab content area. |
| `red` | `color` | `#A82011` | No | Punch accent and red action color. |
| `green` | `color` | `#59A60C` | No | Materials accent and action color. |
| `blue` | `color` | `#2D83B2` | No | Die accent and action color. |
| `charcoal` | `color` | `#2B2C2B` | No | Save button color. |
| `lightGrey` | `color` | `#E0E0E0` | No | Module body color. |
| `grey` | `color` | `#A8A8A8` | No | Tools tab background color. |
| `ink` | `color` | `#232323` | No | Main text color. |
| `white` | `color` | `#FFFFFF` | No | Text color for dark buttons and headers. |
| `midGrey` | `color` | `#BCBCBC` | No | Separator color. |
| `softGrey` | `color` | `#D6D6D6` | No | Detail section background. |
| `cardBorder` | `color` | `#C4C4C4` | No | Detail section and segment card border color. |
| `darkGrey` | `color` | `#5E5E5E` | No | Helper text color. |

### Inline Component Properties

| Component | Property | Type | Default | Required | Description |
|-----------|----------|------|---------|----------|-------------|
| `ToolModule` | `moduleWidth` | `real` | `278.4` | No | Width of the module card. Instances bind this to card widths. |
| `ToolModule` | `moduleHeight` | `real` | `623.2` | No | Height of the module card. |
| `ToolModule` | `title` | `string` | `""` | No | Header title text. |
| `ToolModule` | `accent` | `color` | `root.red` | No | Header color. |
| `ToolModule` | `addBase` | `color` | `root.red` | No | Color of the `NEW` button. |
| `ToolModule` | `addClass` | `string` | `""` | No | Object name for the module-specific new button. |
| `ToolModule` | `primaryTitle` | `string` | `""` | No | First detail section heading. |
| `ToolModule` | `primaryRows` | `var` | `[]` | No | Labels shown in the first detail section. |
| `ToolModule` | `primaryTypes` | `var` | `[]` | No | Row render types: `field`, `info-field`, or `combo`. |
| `ToolModule` | `secondaryTitle` | `string` | `""` | No | Second detail section heading. |
| `ToolModule` | `secondaryRows` | `var` | `[]` | No | Labels shown in the second detail section. |
| `ToolModule` | `secondaryTypes` | `var` | `[]` | No | Row render types for the second section. |
| `ToolModule` | `tertiaryTitle` | `string` | `""` | No | Optional third section heading. Die uses this for available segments. |
| `ToolModule` | `helper` | `string` | `""` | No | Optional helper text shown below a section heading. |
| `ToolModule` | `showSegments` | `bool` | `false` | No | Enables the segment-card grid for Punch and Die. |
| `ToolModule` | `materialMode` | `bool` | `false` | No | Uses the Material-specific 45/55 label/value ratio and section heights. |
| `SectionBlock` | `title` | `string` | `""` | No | Section heading text. |
| `SectionBlock` | `helper` | `string` | `""` | No | Optional helper text. |
| `SectionBlock` | `rows` | `var` | `[]` | No | Detail row labels. |
| `SectionBlock` | `rowTypes` | `var` | `[]` | No | Detail row type model. |
| `SectionBlock` | `labelRatio` | `real` | `0.333` | No | Label column width ratio. |
| `SectionBlock` | `showSegments` | `bool` | `false` | No | Selects segment grid rendering instead of detail rows. |
| `SectionBlock` | `materialMode` | `bool` | `false` | No | Applies material-specific row spacing. |
| `DetailRows` | `labels` | `var` | `[]` | No | Labels rendered by the row repeater. |
| `DetailRows` | `rowTypes` | `var` | `[]` | No | Row type for each label. |
| `DetailRows` | `labelRatio` | `real` | `0.333` | No | Horizontal label/value split. |
| `DetailRows` | `materialMode` | `bool` | `false` | No | Enables taller Material rows for wrapped labels. |
| `DetailRows` | `padX` | `real` | `8 * root.sx` | No | Read-only detail-section horizontal padding. |
| `DetailRows` | `gridGap` | `real` | `10 * root.sx` | No | Read-only grid gap between label and value columns. |
| `SegmentGrid` | `gap` | `real` | `8 * root.sx` | No | Read-only segment-card horizontal gap. |
| `SegmentGrid` | `margin` | `real` | `8 * root.sx` | No | Read-only inner margin used to keep segment cards inside the section border. |
| `SegmentGrid` | `cardW` | `real` | Computed | No | Responsive segment-card width derived from the panel width, margins, and gaps. |
| `SegmentGrid` | `cardH` | `real` | `56 * root.sy` | No | Segment-card height. |
| `ButtonRow` | `addBase` | `color` | `red` | No | Color for the `NEW` button. |
| `ButtonRow` | `addClass` | `string` | `""` | No | Object name for the `NEW` button. |
| `ActionButton` | `base` | `color` | `charcoal` | No | Button fill color, darkened while pressed. |
| `ActionButton` | `textColor` | `color` | `white` | No | Button text color. |
| `ActionButton` | `roundedLeft` | `bool` | `false` | No | Preserves rounded left-side corners for the first action button. |
| `ActionButton` | `roundedRight` | `bool` | `false` | No | Preserves rounded right-side corners for the last action button. |
| `MeasurementField` | Inherited `text` | `string` | Control default | No | Editable numeric/display value inside measurement fields. |
| `FieldWithInlineInfo` | `showInfo` | `bool` | `false` | No | Shows the legacy info-circle icon before the measurement field. |
| `FieldWithInlineInfo` | `noIconIndent` | `bool` | `false` | No | Applies the legacy left indent used by no-icon punch/die fields. |
| `FieldWithInlineInfo` | `text` | `alias` | `field.text` | No | Editable text exposed from the nested `MeasurementField`. |
| `FieldWithInlineInfo` | `iconSize` | `real` | `16 * root.sx` | No | Read-only vector icon width. |
| `FieldWithInlineInfo` | `spacing` | `real` | `4 * root.sx` | No | Read-only gap between icon and field. |
| `FieldWithInlineInfo` | `fieldMax` | `real` | Computed | No | Caps punch/die inline-info fields at the legacy maximum width of 120 px. |
| `EditableCombo` | Inherited `model` | `var` | `Default`, `Option 1`, `Option 2` | No | Editable combo-box model used for validation. |
| `EditableCombo` | Popup | `Popup` + `ListView` | No | Constrained dropdown menu with explicit ids, elided delegate text, keyboard escape close, and highlighted rows. |
| `ToolIconButton` | `iconName` | `string` | `pen` | No | Selects the vector icon. Valid values used here are `pen`, `trash`, `info-circle`, and `caret-down`. |
| `ToolIconButton` | `base` | `color` | `white` | No | Button fill color. |
| `ToolIconButton` | `textColor` | `color` | `ink` | No | Icon/text color. |
| `ToolIconButton` | `borderColor` | `color` | `ink` | No | Button border color. |
| `WhiteCombo` | `text` | `string` | `""` | No | Legacy visual shell retained for compatibility with older parity experiments. |
| `WhiteCombo` | `borderColor` | `color` | `ink` | No | Legacy shell border color. |
| `VectorIcon` | `iconName` | `string` | `info-circle` | No | Selects the local SVG asset. Valid values are `pen`, `trash`, `info-circle`, and `caret-down`. |
| `RoundedCorners` | `radiusSize` | `real` | `7` | No | Corner radius used by rounded-side helpers. |
| `RoundedCorners` | `topLeft` | `bool` | `false` | No | Preserves the top-left rounded corner when true. |
| `RoundedCorners` | `topRight` | `bool` | `false` | No | Preserves the top-right rounded corner when true. |
| `RoundedCorners` | `bottomLeft` | `bool` | `false` | No | Preserves the bottom-left rounded corner when true. |
| `RoundedCorners` | `bottomRight` | `bool` | `false` | No | Preserves the bottom-right rounded corner when true. |

## Inter-Component Interactions


`DataStore.qml` provides the copied Java JSON data to ToolsView. The top selectors use real punch, die, and material names. Detail fields are populated from the selected JSON record, including heights, angles, die openings, segment counts, material defaults, and the first material thickness tooling preference.

This prototype does not yet write changes back to storage. Combo boxes, measurement fields, edit buttons, and action buttons are interactive local controls used for validating layout, focus, dropdown behavior, typing, and data display while preserving the legacy control positions and styling.

Editable combo popups are sized to their parent field, cap their height, elide long option labels, and use explicit `comboControl` references for popup/list/delegate state. This keeps the dropdown menus aligned with their fields and avoids null parent lookups while menus open or close.


## Geometry Notes

| Runtime Bound | QML Mapping |
|----------------------|-------------|
| Tools root width `864` | Root horizontal scale base. |
| Tools root height `638.4` | Root vertical scale base. |
| Root padding/gap `7.2` | Module x/y offsets and card spacing. |
| Punch card `x=7.2`, `w=278.4`, `h=623.2` | First `ToolModule`. |
| Die card `x=292.8`, `w=279.2`, `h=623.2` | Second `ToolModule`. |
| Materials card `x=578.4`, `w=278.4`, `h=623.2` | Third `ToolModule`. |
| Header height `33.6` | Colored card header height. |
| Body height `589.6` | Light grey module body height. |
| Action button height `35.2` | Bottom `NEW`, `SAVE`, and `DUPLICATE` buttons. |

The Punch and Die modules include the legacy segment-card grid. Materials uses the legacy Material Defaults and Thickness Profile layout with a 45/55 label/value ratio. Detail fields use classic-style section padding and grid gaps; Punch/Die inline-info measurement fields are capped at the legacy `120` px maximum and align to the right edge of their value column.