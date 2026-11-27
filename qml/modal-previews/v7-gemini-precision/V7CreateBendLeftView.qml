import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "../.."
import "../../core/BendCalculator.js" as BendCalculator
import "../../core/Units.js" as Units

Item {
    id: root
    objectName: "create-bend-view bend-notes body button-append-new button-cancel button-compensation-direction button-create-new button-delete button-duplicate button-edit button-info button-open-vertical-diagram button-reset button-save combo-die combo-material combo-punch create-bend-press-toggle fields highlighted-text-field highlight-left-rounded icon-small item-selection label-overridden label-warning-orange label-warning-red measurement-text-field-override multi-icon panel-empty panel-warning-container pdm second-title small text-bend-notes text-bend-notes-bottom white-combo-box"
    property var appState: null
    readonly property bool metric: appState ? appState.metricUnits === true : false
    function dispLen(val, digits, fb) {
        var n = Number(val)
        if (val === undefined || val === null || !isFinite(n)) return fb || "0"
        return metric ? (n * 25.4).toFixed(2) : n.toFixed(digits)
    }
    function dispSpeed(val, fb) {
        var n = Number(val)
        if (val === undefined || val === null || !isFinite(n)) return fb || "0"
        return metric ? (n * 25.4 / 60).toFixed(1) : n.toFixed(0)
    }
    function fromLen(v) { return Units.inchesFromInput(v, metric) }
    function fromSpeed(v) { return Units.ipmFromInput(v, metric) }
    function lenTxt(val) {
        var n = Number(val)
        return (val === undefined || val === null || !isFinite(n)) ? "\u2014" : Units.len(n, metric, 4)
    }

    readonly property real sx: width / 864
    readonly property real sy: height / 638.4

    // BendCNC Vivid Industrial Palette (matching Tools, Run, and BackGauge)
    readonly property color canvasBg: "#BFC2C5"
    readonly property color cardBg: "#E0E0E0"
    readonly property color cardSurface: "#F1F5F9"
    readonly property color cardHeaderBg: "#2B2C2B"
    readonly property color cardBorderColor: "#8B95A1"
    readonly property color cardDividerColor: "#CBD5E1"
    readonly property color inputBg: "#FFFFFF"
    readonly property color inputBorderColor: "#64748B"
    readonly property color textPrimary: "#0F172A"
    readonly property color textSecondary: "#334155"
    readonly property color textMuted: "#64748B"

    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color charcoal: "#1E232A"
    readonly property color amber: "#D97706"
    readonly property color orange: "#EA580C"
    readonly property color purple: "#6366F1"
    readonly property color slate: "#475569"

    property int selectedBendIndex: 0
    property int selectedPunchIndex: indexById(dataStore.punches, currentBend.punchId)
    property int selectedDieIndex: indexById(dataStore.dies, currentBend.dieId)
    property int selectedMaterialIndex: indexById(dataStore.materials, currentBend.materialId)
    property bool editingName: false
    property bool editing: false
    property bool creatingNew: false
    property var editSnapshot: ({})
    property var draftBend: ({})
    property var workingBends: []
    property bool hasUnsavedChanges: editing && (creatingNew || JSON.stringify(currentBend) !== JSON.stringify(editSnapshot))
    readonly property bool backGaugeEnabled: currentBend.backGaugeRefEdgeStopEnabled === true
    readonly property bool overrideEnabled: currentBend.overrideFinalBendPositionEnabled === true
    readonly property var currentBend: editing
        ? draftBend
        : (workingBends.length > 0 ? workingBends[Math.min(selectedBendIndex, workingBends.length - 1)] : ({}))
    readonly property var currentPunch: selectedPunchIndex >= 0 && selectedPunchIndex < dataStore.punches.length ? dataStore.punches[selectedPunchIndex] : ({})
    readonly property var currentDie: selectedDieIndex >= 0 && selectedDieIndex < dataStore.dies.length ? dataStore.dies[selectedDieIndex] : ({})
    readonly property var currentMaterial: selectedMaterialIndex >= 0 && selectedMaterialIndex < dataStore.materials.length ? dataStore.materials[selectedMaterialIndex] : ({})
    readonly property var backGaugeReferenceStopIds: appState
        ? appState.backGaugeActiveCoordinateSystems
        : ["G54", "G55", "G59"]
    readonly property var punchItems: dataStore.punches
    readonly property var dieItems: dataStore.dies
    readonly property var materialItems: dataStore.materials
    readonly property var calculation: calculateBend()
    readonly property var activeWarnings: warningItems()
    readonly property bool hasBends: workingBends.length > 0 || creatingNew
    readonly property bool canSave: editing && hasUnsavedChanges
        && bendIsValid(currentBend) && isNameUnique(currentBend.name)

    DataStore { id: dataStore }

    Connections {
        target: root.appState
        ignoreUnknownSignals: true
        function onProgramBendsChanged() { if (!root.editing) root.syncWorkingBends() }
        function onActiveProgramChanged() { if (!root.editing) root.syncWorkingBends() }
    }

    Component.onCompleted: syncWorkingBends()
    onAppStateChanged: if (!editing) syncWorkingBends()

    function cloneValue(val) {
        if (val === undefined || val === null) return ({})
        return JSON.parse(JSON.stringify(val))
    }
    function syncWorkingBends() {
        // storedProgramBends excludes the session-only measured thickness
        // override, so saving never persists those runtime values.
        workingBends = cloneValue(appState ? (appState.storedProgramBends !== undefined
            ? appState.storedProgramBends : appState.programBends) || [] : [])
        selectedBendIndex = workingBends.length > 0
            ? Math.max(0, Math.min(selectedBendIndex, workingBends.length - 1)) : -1
        syncSelectedToolIndexes()
    }
    function ensureEditing() {
        if (editing) return
        if (!hasBends) return
        editSnapshot = cloneValue(currentBend)
        draftBend = cloneValue(currentBend)
        editing = true
        creatingNew = false
    }
    function beginEdit(openNameKeyboard) {
        ensureEditing()
        if (!editing) return
        if (openNameKeyboard) beginNameEdit(bendNameEditor)
    }
    function defaultBend() {
        return {
            id: "bend-" + String(Date.now()), name: nextUnusedName("UNTITLED BEND"), stock: false,
            materialThickness: 0.0600, desiredBendAngle: 90.0, angleCompensation: 0.0,
            angleCompensationReversed: false, punchToMaterialClearance: 0.050,
            additionalRetractAfterBend: 0.000, bendWidth: 12.0,
            backGaugeRefEdgeStop: "G54", backGaugeRefEdgeStopEnabled: false,
            backGaugeXPosition: 2.000, backGaugeRPosition: appState ? Number(appState.defaultBackGaugeRPositionInch || 0) : 0,
            backGaugeJogSpeed: 100, overrideFinalBendPositionEnabled: false,
            overriddenFinalBendPosition: 0, notes: "", xAxisNotes: "", rAxisNotes: "",
            punchId: dataStore.punches.length > 0 ? dataStore.punches[0].id : "",
            dieId: dataStore.dies.length > 0 ? dataStore.dies[0].id : "",
            materialId: dataStore.materials.length > 0 ? dataStore.materials[0].id : "",
            dateCreated: new Date().toISOString()
        }
    }
    function nextUnusedName(base) {
        var taken = ({})
        for (var i = 0; i < workingBends.length; i++) taken[String(workingBends[i].name || "")] = true
        if (!taken[base]) return base
        for (var s = 1; s < 1000; s++) {
            var c = base + " " + s
            if (!taken[c]) return c
        }
        return base + " " + Date.now()
    }
    function isNameUnique(name) {
        if (!name || String(name).trim().length === 0) return false
        var trimmed = String(name).trim()
        var curId = currentBend.id
        for (var i = 0; i < workingBends.length; i++) {
            if (workingBends[i].id !== curId && String(workingBends[i].name || "").trim() === trimmed) return false
        }
        return true
    }
    function bendIsValid(b) {
        if (!b) return false
        if (isNaN(Number(b.desiredBendAngle)) || Number(b.desiredBendAngle) < 15 || Number(b.desiredBendAngle) > 170) return false
        if (isNaN(Number(b.materialThickness)) || Number(b.materialThickness) <= 0) return false
        return true
    }
    function syncSelectedToolIndexes() {
        selectedPunchIndex = indexById(dataStore.punches, currentBend.punchId)
        selectedDieIndex = indexById(dataStore.dies, currentBend.dieId)
        selectedMaterialIndex = indexById(dataStore.materials, currentBend.materialId)
    }
    function selectTool(kind, index) {
        ensureEditing()
        if (kind === "Punch" && index >= 0 && index < dataStore.punches.length) {
            setBendValue("punchId", dataStore.punches[index].id)
            selectedPunchIndex = index
        } else if (kind === "Die" && index >= 0 && index < dataStore.dies.length) {
            setBendValue("dieId", dataStore.dies[index].id)
            selectedDieIndex = index
        } else if (kind === "Material" && index >= 0 && index < dataStore.materials.length) {
            setBendValue("materialId", dataStore.materials[index].id)
            selectedMaterialIndex = index
        }
    }
    function stopDatumLabel(id) {
        var name = appState && appState.backGaugeCoordinateDisplayName
            ? appState.backGaugeCoordinateDisplayName(id) : id
        return name && name !== id ? name + " · " + id : id
    }
    function setBendValue(field, value) {
        ensureEditing()
        draftBend[field] = value
        draftBend = cloneValue(draftBend)
    }
    function setNumericValue(field, value, min, max) {
        var num = Number(value)
        if (isNaN(num)) return
        if (min !== undefined && max !== undefined) num = Math.max(min, Math.min(max, num))
        setBendValue(field, num)
    }
    function createNew() {
        draftBend = defaultBend()
        editSnapshot = cloneValue(draftBend)
        editing = true
        creatingNew = true
        selectedBendIndex = workingBends.length
        syncSelectedToolIndexes()
    }
    function duplicateCurrent() {
        if (!hasBends) return
        var dup = cloneValue(currentBend)
        dup.id = "bend-" + String(Date.now())
        dup.name = nextUnusedName((currentBend.name || "BEND") + " COPY")
        dup.dateCreated = new Date().toISOString()
        draftBend = dup
        editSnapshot = cloneValue(draftBend)
        editing = true
        creatingNew = true
        selectedBendIndex = workingBends.length
        syncSelectedToolIndexes()
    }
    function cancelEditing() {
        editing = false
        creatingNew = false
        editingName = false
        draftBend = ({})
        syncWorkingBends()
    }
    // Persists through the selected program in programs.json. AppState has no
    // saveBends(); the previous call threw after the local list was updated,
    // so edits (including MANUAL RAM OVERRIDE) reverted on the next reload.
    function saveEditing() {
        if (!canSave || !appState) return false
        var savedBend = appState.bendFromCreateDraft(
            String(currentBend.name || "").trim(), cloneValue(draftBend),
            currentPunch, currentDie, currentMaterial,
            calculation.inUseFinalBendPosition, calculation.bendTonnage)
        var saved = creatingNew
            ? appState.appendProgramBend(savedBend)
            : appState.replaceProgramBend(selectedBendIndex, savedBend)
        if (!saved) {
            appState.showAlarm("SAVE BEND",
                "Could not write programs.json safely. The selected program was not confirmed as saved.")
            return false
        }
        var savedId = String(savedBend.id || "")
        editing = false
        creatingNew = false
        editingName = false
        syncWorkingBends()
        for (var i = 0; i < workingBends.length; i++) {
            if (String(workingBends[i].id || "") === savedId) {
                selectedBendIndex = i
                break
            }
        }
        syncSelectedToolIndexes()
        return true
    }
    function resetEditing() {
        if (!editing) return
        draftBend = cloneValue(editSnapshot)
        syncSelectedToolIndexes()
    }
    function requestDelete() {
        if (creatingNew) { cancelEditing(); return }
        if (!hasBends || selectedBendIndex < 0 || !appState) return
        var index = selectedBendIndex
        appState.showConfirmation("DELETE BEND MOVE",
            "Delete \u201c" + String(currentBend.name || ("Bend " + (index + 1))) + "\u201d from "
                + appState.activeProgram + "?",
            function() {
                if (!appState.removeProgramBend(index)) {
                    appState.showAlarm("DELETE BEND MOVE",
                        "Could not write programs.json safely. The selected program was not confirmed as saved.")
                    return
                }
                editing = false
                creatingNew = false
                editingName = false
                root.syncWorkingBends()
            }, null)
    }
    // Ram positions are shown in DRO/machine coordinates (negative, as in the
    // original BendCNC app), so the opening must be the controller EEPROM
    // value on hardware. The desktop opening is 0 on the press, which used to
    // produce positive height-stack values here.
    function ramToTableOpening() {
        if (!appState)
            return 8.250
        var opening = typeof appState.authoritativeRamToTableOpening === "function"
            ? Number(appState.authoritativeRamToTableOpening()) : NaN
        if (opening > 0)
            return opening
        return appState.offlineSimulationEnabled ? 8.250 : NaN
    }
    // Stored program values may still use the legacy height-stack convention
    // (positive); convert those to machine coordinates for display/calculation.
    function machineRamPosition(value) {
        var v = Number(value)
        if (!isFinite(v) || (v >= -4.0 && v <= -0.05) || !(v > 0))
            return v
        var opening = ramToTableOpening()
        return opening > 0 ? v - opening : NaN
    }
    function calculateBend() {
        var opening = ramToTableOpening()
        return BendCalculator.computeBend({
            bend: {
                materialThickness: Number(currentBend.materialThickness || 0.060),
                bendWidth: Number(currentBend.bendWidth || 12.0),
                desiredBendAngle: Number(currentBend.desiredBendAngle || 90.0),
                angleCompensation: Number(currentBend.angleCompensation || 0.0),
                angleCompensationReversed: currentBend.angleCompensationReversed === true,
                punchToMaterialClearance: Number(currentBend.punchToMaterialClearance || 0.050),
                additionalRetractAfterBend: Number(currentBend.additionalRetractAfterBend || 0.000),
                overrideFinalBendPositionEnabled: overrideEnabled,
                overriddenFinalBendPosition: machineRamPosition(currentBend.overriddenFinalBendPosition || 0.0)
            },
            punch: { heightInch: Number(currentPunch.heightInch || 4.603) },
            die: { heightInch: Number(currentDie.heightInch || 1.870), vdieOpeningInch: Number(currentDie.vdieOpeningInch || 0.472) },
            material: {
                materialTensileStrengthPsi: Number(currentMaterial.materialTensileStrengthPsi || 60000),
                insideRadiusRuleOfThumb: Number(currentMaterial.insideRadiusRuleOfThumb || 0.16),
                materialSpringback: Number(currentMaterial.materialSpringback || 1.0)
            },
            settings: { materialClampRatePercentage: appState ? appState.materialClampRatePercentage : 5 },
            machine: { ramToTableOpening: opening, validRangeInchMin: -4.0, validRangeInchMax: -0.05, jogStepPaddingInch: 0.01 },
            limits: { tonnageWarningThreshold: 10.0, tonnageErrorThreshold: 12.5, punchToMaterialClearanceWarningThreshold: 0.3 }
        })
    }
    function warningItems() {
        var list = []
        if (calculation.tonnageError) list.push({ level: "error", text: qsTr("TONNAGE EXCEEDED: Calculated force exceeds machine limit (12.5 T)") })
        else if (calculation.tonnageWarning) list.push({ level: "warning", text: qsTr("TONNAGE WARNING: Approaching upper tonnage capacity") })
        // BendCalculator names this flag punchToMaterialClearanceWarning.
        if (calculation.punchToMaterialClearanceWarning) list.push({ level: "warning", text: qsTr("CLEARANCE WARNING: Punch-to-material clearance exceeds") + " " + Units.len(0.3, metric, 3) })
        if (calculation.upperLimitExceededError) list.push({ level: "error", text: qsTr("TRAVEL LIMIT: Ram target exceeds upper physical travel") })
        if (calculation.lowerLimitExceededError) list.push({ level: "error", text: qsTr("TRAVEL LIMIT: Ram target exceeds lower bed limit") })
        return list
    }
    function showVerticalDiagram() {
        if (!appState) return
        appState.showImagePopup("VERTICAL POSITIONS DIAGRAM",
            "START SAFETY CLEARANCE  " + lenTxt(calculation.startSafetyClearance) + "\n\n"
            + "BEND CLAMP POSITION  " + lenTxt(calculation.clampPosition) + "\n\n"
            + "FINAL BEND POSITION  " + lenTxt(calculation.inUseFinalBendPosition) + "\n\n"
            + "RETRACT AFTER BEND  " + lenTxt(calculation.retractAfterBend) + "\n\n"
            + "TOTAL BEND STROKE  " + lenTxt(overrideEnabled ? calculation.overriddenTotalBendStroke : calculation.totalBendStroke),
            "images/info/create_bend/vertical_diagram.png")
    }
    function names(items) {
        var res = []
        for (var i = 0; i < items.length; i++) res.push(items[i].name || ("Bend " + (i + 1)))
        return res
    }
    function indexById(items, id) {
        if (!id) return -1
        for (var i = 0; i < items.length; i++) if (items[i].id === id) return i
        return -1
    }
    function numberText(val, digits, fallback) {
        if (val === undefined || val === null || isNaN(Number(val))) return fallback || "0"
        return Number(val).toFixed(digits)
    }
    function beginNameEdit(editor) {
        ensureEditing()
        editingName = true
        if (editor) Qt.callLater(function() { editor.openKeyboard() })
    }

    // ---- Touch-first sizing --------------------------------------------------
    // The design grid is 864x638. Every text size and control height follows the
    // smaller axis scale so the screen stays legible on the 1366x768 press panel
    // instead of keeping 8-11 px text inside a view that grew.
    readonly property real u: Math.max(0.85, Math.min(sx, sy))
    readonly property int barH: Math.round(48 * u)
    readonly property int ctlH: Math.round(36 * u)
    readonly property int rowH: Math.round(38 * u)
    readonly property int pad: Math.round(10 * u)
    // Every card title row has this height, so fields line up across cards.
    readonly property int titleH: Math.round(28 * u)
    // One look for every input: a white bar on the card surface.
    readonly property color cardFill: "#E9EDF2"
    readonly property color fieldBorder: "#AAB4C0"
    readonly property color fieldOffBg: "#D9DEE5"
    readonly property color fieldOffBorder: "#C3CAD3"
    function fs(px) { return Math.max(11, Math.round(px * u)) }
    function editNotes() {
        if (!appState) return
        var t = { text: (currentBend && currentBend.notes) ? currentBend.notes : "" }
        appState.openOnScreenKeyboard(t, false, qsTr("PROGRAM NOTES"), function(v) {
            root.setBendValue("notes", v)
        })
    }
    readonly property bool hasErrorWarning: {
        for (var i = 0; i < activeWarnings.length; i++)
            if (activeWarnings[i].level === "error") return true
        return false
    }
    // Tells the operator why SAVE is (not) available.
    readonly property string saveHint: {
        if (!editing) return ""
        if (!hasUnsavedChanges) return qsTr("EDITING - NO CHANGES YET")
        if (!isNameUnique(currentBend.name)) return qsTr("NAME EMPTY OR ALREADY USED")
        if (!bendIsValid(currentBend)) return qsTr("ANGLE OR THICKNESS OUT OF RANGE")
        return qsTr("UNSAVED CHANGES")
    }

    // Base industrial canvas
    Rectangle {
        anchors.fill: parent
        color: root.canvasBg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // 1. BEND SEQUENCE HEADER: position, navigation, selector, rename, delete
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.barH
            radius: 7
            color: root.cardHeaderBg
            border.color: "#3F4246"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: stepText.implicitWidth + Math.round(24 * root.u)
                    Layout.preferredHeight: root.ctlH
                    radius: 5
                    color: "#383A3D"
                    border.color: "#475569"
                    border.width: 1
                    Text {
                        id: stepText
                        anchors.centerIn: parent
                        text: qsTr("BEND %1/%2").arg(root.workingBends.length > 0 ? (root.selectedBendIndex + 1) : 0).arg(root.workingBends.length)
                        font.bold: true
                        font.pixelSize: root.fs(12)
                        color: "#FFFFFF"
                    }
                }

                // Prev / next bend (locked while a draft is open)
                BarButton {
                    glyph: "left"
                    fill: "#383A3D"
                    active: root.selectedBendIndex > 0 && !root.editing
                    onTriggered: { root.selectedBendIndex--; root.syncSelectedToolIndexes() }
                }
                BarButton {
                    glyph: "right"
                    fill: "#383A3D"
                    active: root.selectedBendIndex < (root.workingBends.length - 1) && !root.editing
                    onTriggered: { root.selectedBendIndex++; root.syncSelectedToolIndexes() }
                }

                // Sequence dropdown / name input
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.ctlH

                    // Dropdown (when not renaming)
                    Rectangle {
                        objectName: "create-bend-selector-field"
                        readonly property bool menuOpen: bendSelectorMenu.visible
                        visible: !root.editingName
                        anchors.fill: parent
                        radius: 5
                        color: "#1E232A"
                        border.color: bendSelectorMenu.visible ? root.blue : "#475569"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            Text {
                                text: root.currentBend.name || qsTr("Untitled Bend Move")
                                font.bold: true
                                font.pixelSize: root.fs(14)
                                color: "#FFFFFF"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Glyph {
                                kind: bendSelectorMenu.visible ? "up" : "down"
                                tint: "#94A3B8"
                                glyphSize: root.fs(14)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // Toggle; see closePolicy below.
                            onClicked: bendSelectorMenu.visible ? bendSelectorMenu.close() : bendSelectorMenu.open()
                        }

                        Menu {
                            id: bendSelectorMenu
                            // CloseOnPressOutside closed the menu and the same tap
                            // reached the field MouseArea, which reopened it.
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                            // Below the field: at y 0 the menu covered it and a second tap
                            // selected the first bend instead of closing.
                            y: parent.height + 2
                            width: Math.max(implicitWidth, parent.width)
                            Repeater {
                                model: root.names(root.workingBends)
                                MenuItem {
                                    text: modelData
                                    implicitHeight: root.ctlH
                                    font.pixelSize: root.fs(12)
                                    font.bold: index === root.selectedBendIndex
                                    onTriggered: {
                                        root.selectedBendIndex = index
                                        root.syncSelectedToolIndexes()
                                    }
                                }
                            }
                        }
                    }

                    // Name editor (when renaming)
                    Rectangle {
                        id: bendNameEditor
                        visible: root.editingName
                        anchors.fill: parent
                        radius: 5
                        color: "#FFFFFF"
                        border.color: root.blue
                        border.width: 2

                        function openKeyboard() {
                            if (!root.appState) return
                            var t = { text: root.currentBend.name || "" }
                            root.appState.openOnScreenKeyboard(t, false, qsTr("BEND MOVE NAME"), function(v) {
                                root.setBendValue("name", String(v).trim())
                                root.editingName = false
                            })
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            Text {
                                text: root.currentBend.name || ""
                                font.bold: true
                                font.pixelSize: root.fs(14)
                                color: root.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: qsTr("TAP TO EDIT")
                                font.pixelSize: root.fs(10)
                                font.bold: true
                                color: root.blue
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bendNameEditor.openKeyboard()
                        }
                    }
                }

                BarButton {
                    glyph: root.editingName ? "close" : "edit"
                    label: root.editingName ? qsTr("DONE") : qsTr("RENAME")
                    fill: root.editingName ? root.slate : root.blue
                    onTriggered: {
                        if (root.editingName) root.editingName = false
                        else root.beginEdit(true)
                    }
                }

                // Always reachable; requestDelete() asks for confirmation.
                BarButton {
                    glyph: "trash"
                    label: qsTr("DELETE")
                    fill: root.red
                    active: root.hasBends
                    onTriggered: root.requestDelete()
                }
            }
        }

        // 2. BODY: what the operator enters sits on light cards (left); what the
        //    machine will do with it sits on one dark result rail (right).
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // =================================================================
            // INPUTS
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // ---- Row A: tooling + bend angle -----------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Math.round(184 * root.u)
                    spacing: 8

                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.pad
                            anchors.topMargin: Math.round(6 * root.u)
                            spacing: 6

                            SectionTitle { title: qsTr("TOOLING") }

                            ToolSelectorBar {
                                objectName: "create-bend-tool-selector-punch"
                                category: "PUNCH"
                                toolName: root.currentPunch.name || "Default Punch"
                                subSpec: "H " + root.lenTxt(root.currentPunch.heightInch || 4.603) + " · " + (root.currentPunch.punchProfileType || "STANDARD")
                                accent: root.red
                                items: root.punchItems
                                currentIndex: root.selectedPunchIndex
                                onSelected: function(idx) { root.selectTool("Punch", idx) }
                            }

                            ToolSelectorBar {
                                objectName: "create-bend-tool-selector-die"
                                category: "DIE"
                                toolName: root.currentDie.name || "Default Die"
                                subSpec: "V " + root.lenTxt(root.currentDie.vdieOpeningInch || 0.472) + " · H " + root.lenTxt(root.currentDie.heightInch || 1.870)
                                accent: root.blue
                                items: root.dieItems
                                currentIndex: root.selectedDieIndex
                                onSelected: function(idx) { root.selectTool("Die", idx) }
                            }

                            ToolSelectorBar {
                                objectName: "create-bend-tool-selector-material"
                                category: "MATERIAL"
                                toolName: root.currentMaterial.name || "Default Material"
                                subSpec: "Tensile " + (root.currentMaterial.materialTensileStrengthPsi ? Math.round(root.currentMaterial.materialTensileStrengthPsi / 1000) + "k PSI" : "60k PSI") + " · T " + root.lenTxt(root.currentBend.materialThickness || 0.060)
                                accent: root.green
                                items: root.materialItems
                                currentIndex: root.selectedMaterialIndex
                                onSelected: function(idx) { root.selectTool("Material", idx) }
                            }
                        }
                    }

                    Card {
                        Layout.preferredWidth: Math.round(272 * root.sx)
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.pad
                            anchors.topMargin: Math.round(6 * root.u)
                            spacing: 6

                            SectionTitle {
                                title: qsTr("BEND ANGLE")

                                Rectangle {
                                    radius: 3
                                    color: root.overrideEnabled ? "#FEF2F2" : "#EFF6FF"
                                    border.color: root.overrideEnabled ? "#FECACA" : "#BFDBFE"
                                    Layout.preferredWidth: angleTag.implicitWidth + 12
                                    Layout.preferredHeight: angleTag.implicitHeight + 4
                                    Text {
                                        id: angleTag
                                        anchors.centerIn: parent
                                        text: root.overrideEnabled ? qsTr("LOCKED BY RAM OVERRIDE") : qsTr("TARGET")
                                        font.bold: true
                                        font.pixelSize: root.fs(8.5)
                                        color: root.overrideEnabled ? root.red : root.blue
                                    }
                                }
                            }

                            // Large angle readout with half-degree steps
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 6
                                opacity: root.overrideEnabled ? 0.45 : 1.0

                                Rectangle {
                                    Layout.preferredWidth: Math.round(52 * root.u)
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: angleDownMouse.pressed ? "#CBD5E1" : "#FFFFFF"
                                    border.color: root.fieldBorder
                                    Text { anchors.centerIn: parent; text: "-0.5°"; font.bold: true; font.pixelSize: root.fs(13); color: root.textSecondary }
                                    MouseArea {
                                        id: angleDownMouse
                                        anchors.fill: parent
                                        enabled: !root.overrideEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setNumericValue("desiredBendAngle", Number(root.currentBend.desiredBendAngle || 90) - 0.5, 15, 170)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: root.charcoal
                                    border.color: root.blue
                                    border.width: 2

                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: Math.round(6 * root.u)
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: numberText(root.currentBend.desiredBendAngle, 1, "90.0") + "°"
                                        font.bold: true
                                        font.pixelSize: root.fs(44)
                                        fontSizeMode: Text.Fit
                                        minimumPixelSize: 14
                                        font.family: "Monospace"
                                        color: "#FFFFFF"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !root.overrideEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.appState) return
                                            var t = { text: numberText(root.currentBend.desiredBendAngle, 1, "90.0") }
                                            root.appState.openOnScreenKeyboard(t, true, qsTr("DESIRED BEND ANGLE (15° - 170°)"), function(v) {
                                                root.setNumericValue("desiredBendAngle", v, 15, 170)
                                            })
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: Math.round(52 * root.u)
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: angleUpMouse.pressed ? "#CBD5E1" : "#FFFFFF"
                                    border.color: root.fieldBorder
                                    Text { anchors.centerIn: parent; text: "+0.5°"; font.bold: true; font.pixelSize: root.fs(13); color: root.textSecondary }
                                    MouseArea {
                                        id: angleUpMouse
                                        anchors.fill: parent
                                        enabled: !root.overrideEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setNumericValue("desiredBendAngle", Number(root.currentBend.desiredBendAngle || 90) + 0.5, 15, 170)
                                    }
                                }
                            }

                            // Angle compensation: direction + degrees
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.preferredHeight: root.ctlH
                                spacing: 6
                                opacity: root.overrideEnabled ? 0.45 : 1.0

                                Rectangle {
                                    Layout.preferredWidth: Math.round(82 * root.u)
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: root.currentBend.angleCompensationReversed ? root.blue : root.amber
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.currentBend.angleCompensationReversed ? "UNDER" : "OVER"
                                        font.bold: true
                                        font.pixelSize: root.fs(12)
                                        color: "#FFFFFF"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !root.overrideEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setBendValue("angleCompensationReversed", !root.currentBend.angleCompensationReversed)
                                    }
                                }

                                CompactParamRow {
                                    // The row above is already dimmed by the override.
                                    enabled: !root.overrideEnabled
                                    paramLabel: qsTr("Compensation")
                                    paramValue: numberText(root.currentBend.angleCompensation, 1, "0.0") + "°"
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.angleCompensation, 1, "0.0") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("ANGLE COMPENSATION (0° - 90°)"), function(v) {
                                            root.setNumericValue("angleCompensation", v, 0, 90)
                                        })
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Row B: workpiece + back gauge (rows share the free height) --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.pad
                            anchors.topMargin: Math.round(6 * root.u)
                            spacing: 6

                            SectionTitle { title: qsTr("WORKPIECE & CLEARANCES") }

                            CompactParamRow {
                                paramLabel: qsTr("Material Thickness")
                                paramValue: dispLen(root.currentBend.materialThickness, 4, "0.0600")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: !root.overrideEnabled
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.currentBend.materialThickness, 4, "0.0600") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("MATERIAL THICKNESS") + (root.metric ? " (0.25 - 63.5 MM)" : " (0.01 - 2.5 IN)"), function(v) {
                                        root.setNumericValue("materialThickness", root.fromLen(v), 0.01, 2.5)
                                    })
                                }
                            }

                            CompactParamRow {
                                paramLabel: qsTr("Bend Length")
                                paramValue: dispLen(root.currentBend.bendWidth, 4, "12.0000")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: true
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.currentBend.bendWidth, 4, "12.0000") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("BEND WIDTH") + (root.metric ? " (2.5 - 845.8 MM)" : " (0.1 - 33.3 IN)"), function(v) {
                                        root.setNumericValue("bendWidth", root.fromLen(v), 0.1, 33.3)
                                    })
                                }
                            }

                            CompactParamRow {
                                paramLabel: qsTr("Punch-to-Material Gap")
                                paramValue: dispLen(root.currentBend.punchToMaterialClearance, 4, "0.0500")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: true
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.currentBend.punchToMaterialClearance, 4, "0.0500") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("PUNCH TO MATERIAL CLEARANCE"), function(v) {
                                        root.setNumericValue("punchToMaterialClearance", root.fromLen(v), 0.01, 5.0)
                                    })
                                }
                            }

                            CompactParamRow {
                                paramLabel: qsTr("Additional Retract")
                                paramValue: dispLen(root.currentBend.additionalRetractAfterBend, 4, "0.0000")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: true
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.currentBend.additionalRetractAfterBend, 4, "0.0000") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("ADDITIONAL RETRACT") + (root.metric ? " (0 - 95.25 MM)" : " (0 - 3.75 IN)"), function(v) {
                                        root.setNumericValue("additionalRetractAfterBend", root.fromLen(v), 0, 3.75)
                                    })
                                }
                            }
                        }
                    }

                    Card {
                        Layout.preferredWidth: Math.round(272 * root.sx)
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.pad
                            anchors.topMargin: Math.round(6 * root.u)
                            spacing: 6

                            SectionTitle {
                                title: qsTr("BACK GAUGE")

                                Text {
                                    text: root.backGaugeEnabled ? qsTr("Moves to this stop") : qsTr("Off for this bend")
                                    font.pixelSize: root.fs(10)
                                    color: root.textMuted
                                }
                                ToggleSwitch {
                                    checked: root.backGaugeEnabled
                                    onColor: root.green
                                    onToggled: root.setBendValue("backGaugeRefEdgeStopEnabled", !root.backGaugeEnabled)
                                }
                            }

                            // Coordinate stop dropdown; the whole bar is the field.
                            Rectangle {
                                objectName: "create-bend-stop-datum-field"
                                readonly property bool menuOpen: gMenu.visible
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: Math.round(30 * root.u)
                                Layout.preferredHeight: root.rowH
                                Layout.maximumHeight: Math.round(50 * root.u)
                                enabled: root.backGaugeEnabled
                                radius: 6
                                color: !root.backGaugeEnabled ? root.fieldOffBg : (stopDatumMouse.pressed ? "#DBEAFE" : "#FFFFFF")
                                border.color: !root.backGaugeEnabled ? root.fieldOffBorder : (gMenu.visible ? root.green : root.fieldBorder)
                                border.width: gMenu.visible ? 2 : 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 6
                                    Text {
                                        text: qsTr("Stop Datum")
                                        font.bold: true; font.pixelSize: root.fs(11.5)
                                        color: root.backGaugeEnabled ? root.textSecondary : root.textMuted
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                        text: root.stopDatumLabel(root.currentBend.backGaugeRefEdgeStop || "G54")
                                        font.bold: true; font.pixelSize: root.fs(12.5)
                                        color: root.backGaugeEnabled ? root.textPrimary : root.textMuted
                                    }
                                    Glyph { kind: gMenu.visible ? "up" : "down"; tint: root.textMuted; glyphSize: root.fs(12) }
                                }
                                MouseArea {
                                    id: stopDatumMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: gMenu.visible ? gMenu.close() : gMenu.open()
                                }
                                Menu {
                                    id: gMenu
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                    y: parent.height + 2
                                    width: Math.max(implicitWidth, parent.width)
                                    Repeater {
                                        model: root.backGaugeReferenceStopIds
                                        MenuItem {
                                            text: root.stopDatumLabel(modelData)
                                            implicitHeight: root.ctlH
                                            font.pixelSize: root.fs(12)
                                            onTriggered: {
                                                root.setBendValue("backGaugeRefEdgeStop", modelData)
                                                // Face references need the finger lowered (R -0.25 in default).
                                                if (root.appState && root.appState.backGaugeReferencePoint)
                                                    root.setNumericValue("backGaugeRPosition",
                                                        String(root.appState.backGaugeReferencePoint(modelData).r))
                                            }
                                        }
                                    }
                                }
                            }

                            CompactParamRow {
                                enabled: root.backGaugeEnabled
                                paramLabel: qsTr("X Axis Stop")
                                paramValue: dispLen(root.currentBend.backGaugeXPosition, 4, "0.0000")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: root.backGaugeEnabled
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.currentBend.backGaugeXPosition, 4, "0.0000") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("BACK GAUGE X POSITION"), function(v) {
                                        root.setNumericValue("backGaugeXPosition", root.fromLen(v))
                                    })
                                }
                            }

                            CompactParamRow {
                                enabled: root.backGaugeEnabled
                                paramLabel: qsTr("R Axis Elevation")
                                paramValue: dispLen(root.currentBend.backGaugeRPosition, 4, "0.0000")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: root.backGaugeEnabled
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.currentBend.backGaugeRPosition, 4, "0.0000") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("BACK GAUGE R ELEVATION"), function(v) {
                                        root.setNumericValue("backGaugeRPosition", root.fromLen(v))
                                    })
                                }
                            }

                            CompactParamRow {
                                enabled: root.backGaugeEnabled
                                paramLabel: qsTr("Jog Speed")
                                paramValue: dispSpeed(root.currentBend.backGaugeJogSpeed, "100")
                                paramUnit: root.metric ? "mm/s" : "IPM"
                                editable: root.backGaugeEnabled
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispSpeed(root.currentBend.backGaugeJogSpeed, "100") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("BACK GAUGE JOG SPEED") + (root.metric ? " (0.4 - 211.7 MM/S)" : " (1 - 500 IPM)"), function(v) {
                                        root.setNumericValue("backGaugeJogSpeed", root.fromSpeed(v), 1, 500)
                                    })
                                }
                            }
                        }
                    }
                }

                // ---- Row C: program notes (the bend's `notes` field) ------------
                // While the calculator reports alerts they take this strip over;
                // the notes come back as soon as the alerts clear.
                Card {
                    id: notesCard
                    readonly property bool alerting: root.activeWarnings.length > 0
                    readonly property int inset: Math.round(8 * root.u)
                    readonly property color alertInk: root.hasErrorWarning ? root.red : "#8A4B00"
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    // Grows only when the alert text needs more lines than fit.
                    Layout.preferredHeight: Math.max(Math.round(88 * root.u),
                                                     alerting ? alertList.implicitHeight + 2 * inset : 0)
                    color: !alerting ? root.cardFill : (root.hasErrorWarning ? "#FBE3E0" : "#FCEFCF")
                    border.color: !alerting ? "#98A2AE" : (root.hasErrorWarning ? root.red : root.amber)
                    border.width: alerting ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: notesCard.inset
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: false
                            Layout.preferredWidth: Math.round(126 * root.u)
                            Layout.fillHeight: true
                            spacing: 2

                            SectionTitle {
                                title: !notesCard.alerting ? qsTr("PROGRAM NOTES")
                                     : (root.activeWarnings.length === 1 ? qsTr("1 ALERT") : qsTr("%1 ALERTS").arg(root.activeWarnings.length))
                                ink: notesCard.alerting ? notesCard.alertInk : "#3B4756"
                            }

                            Row {
                                visible: !notesCard.alerting
                                spacing: 5
                                Glyph { kind: "edit"; tint: root.textMuted; glyphSize: root.fs(11) }
                                Text { text: qsTr("Tap the text to edit"); font.pixelSize: root.fs(9.5); color: root.textMuted }
                            }

                            // Notes stay editable while the alerts cover them.
                            Rectangle {
                                visible: notesCard.alerting
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(30 * root.u)
                                radius: 6
                                color: editNotesMouse.pressed ? "#DBEAFE" : "#FFFFFF"
                                border.color: root.fieldBorder
                                border.width: 1
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Glyph { kind: "edit"; tint: root.textSecondary; glyphSize: root.fs(12); anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: qsTr("EDIT NOTES")
                                        font.bold: true
                                        font.pixelSize: root.fs(10.5)
                                        color: root.textSecondary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    id: editNotesMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.editNotes()
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }

                        ColumnLayout {
                            id: alertList
                            visible: notesCard.alerting
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Math.round(5 * root.u)

                            Repeater {
                                model: root.activeWarnings
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: 8
                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: Math.round(4 * root.u)
                                        Layout.preferredWidth: Math.round(8 * root.u)
                                        Layout.preferredHeight: Math.round(8 * root.u)
                                        radius: width / 2
                                        color: modelData.level === "error" ? root.red : root.amber
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.text
                                        font.bold: true
                                        font.pixelSize: root.fs(11.5)
                                        color: modelData.level === "error" ? root.red : "#8A4B00"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: !notesCard.alerting
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: notesMouse.pressed ? "#DBEAFE" : "#FFFFFF"
                            border.color: root.fieldBorder
                            border.width: 1
                            clip: true

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.topMargin: 5
                                anchors.bottomMargin: 5
                                text: (root.currentBend && root.currentBend.notes) ? root.currentBend.notes : qsTr("Tap to write notes for this bend...")
                                font.pixelSize: root.fs(11)
                                color: (root.currentBend && root.currentBend.notes) ? root.textPrimary : "#94A3B8"
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: notesMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editNotes()
                            }
                        }
                    }
                }
            }

            // =================================================================
            // RESULT RAIL: final position, load and limits, positions, override
            // =================================================================
            Rectangle {
                Layout.preferredWidth: Math.round(264 * root.sx)
                Layout.fillHeight: true
                radius: 8
                color: root.charcoal
                border.color: "#0B0E12"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.pad
                    anchors.topMargin: Math.round(6 * root.u)
                    spacing: 6

                    SectionTitle { title: qsTr("CALCULATED RESULT"); onDark: true }

                    // The value that drives the stroke gets the emphasis
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(64 * root.u)
                        radius: 8
                        color: root.overrideEnabled ? root.red : root.blue

                        Text {
                            id: heroLabel
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: 10
                            anchors.topMargin: Math.round(7 * root.u)
                            text: qsTr("FINAL RAM POSITION")
                            font.bold: true
                            font.pixelSize: root.fs(10.5)
                            font.letterSpacing: 0.4
                            color: "#FFFFFF"
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: heroLabel.verticalCenter
                            width: heroTag.implicitWidth + 10
                            height: heroTag.implicitHeight + 4
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.22)
                            Text {
                                id: heroTag
                                anchors.centerIn: parent
                                text: root.overrideEnabled ? qsTr("OVERRIDE") : qsTr("CALCULATED")
                                font.bold: true
                                font.pixelSize: root.fs(8.5)
                                color: "#FFFFFF"
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.bottomMargin: Math.round(4 * root.u)
                            horizontalAlignment: Text.AlignRight
                            text: lenTxt(root.calculation.inUseFinalBendPosition)
                            font.bold: true
                            font.pixelSize: root.fs(26)
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 14
                            font.family: "Monospace"
                            color: "#FFFFFF"
                        }
                    }

                    // Load against the 12.5 T limit, with every active warning below it
                    Rectangle {
                        id: loadTile
                        readonly property bool warn: root.activeWarnings.length > 0
                        readonly property color tone: root.calculation.tonnageError ? "#F87171" : (root.calculation.tonnageWarning ? "#FBBF24" : "#84CC16")
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: loadCol.implicitHeight + 2 * loadCol.anchors.margins
                        radius: 6
                        clip: true
                        color: !warn ? "#2A313A" : (root.hasErrorWarning ? "#4A1F1F" : "#453512")
                        border.color: !warn ? "#3A424D" : (root.hasErrorWarning ? "#F87171" : "#FBBF24")
                        border.width: warn ? 1.5 : 1

                        ColumnLayout {
                            id: loadCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Math.round(8 * root.u)
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Text { text: qsTr("BEND TONNAGE"); font.bold: true; font.pixelSize: root.fs(10.5); color: "#CBD5E1" }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: numberText(root.calculation.bendTonnage, 1, "0.0") + " T / 12.5 T"
                                    font.bold: true; font.pixelSize: root.fs(13); font.family: "Monospace"
                                    color: loadTile.tone
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(8 * root.u)
                                radius: height / 2
                                color: "#11151A"
                                Rectangle {
                                    width: Math.min(parent.width, Math.max(4, parent.width * (Number(root.calculation.bendTonnage || 0) / 12.5)))
                                    height: parent.height
                                    radius: height / 2
                                    color: loadTile.tone
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                visible: !loadTile.warn
                                spacing: 5
                                Glyph { kind: "check"; tint: "#84CC16"; glyphSize: root.fs(12) }
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("GEOMETRY & TONNAGE VERIFIED")
                                    font.bold: true; font.pixelSize: root.fs(10)
                                    color: "#A3E635"
                                    elide: Text.ElideRight
                                }
                            }
                            // The alert texts are shown in the notes strip.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                visible: loadTile.warn
                                spacing: 5
                                Glyph { kind: "alert"; tint: root.hasErrorWarning ? "#FCA5A5" : "#FCD34D"; glyphSize: root.fs(12) }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.activeWarnings.length === 1 ? qsTr("1 ALERT ACTIVE") : qsTr("%1 ALERTS ACTIVE").arg(root.activeWarnings.length)
                                    font.bold: true; font.pixelSize: root.fs(10)
                                    color: root.hasErrorWarning ? "#FCA5A5" : "#FCD34D"
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // Positions the calculator derives from the inputs
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        CompactDroRow {
                            label: qsTr("Clamp Position")
                            value: lenTxt(root.calculation.clampPosition)
                        }
                        CompactDroRow {
                            label: qsTr("Start Safety Clearance")
                            value: lenTxt(root.calculation.startSafetyClearance)
                        }
                        CompactDroRow {
                            label: qsTr("Retract After Bend")
                            value: lenTxt(root.calculation.retractAfterBend)
                        }
                        CompactDroRow {
                            label: qsTr("Total Bend Stroke")
                            value: lenTxt(root.overrideEnabled ? root.calculation.overriddenTotalBendStroke : root.calculation.totalBendStroke)
                        }
                        CompactDroRow {
                            label: qsTr("Inside Bend Radius")
                            value: lenTxt(root.calculation.predictedInsideBendRadius)
                            divider: false
                        }
                    }

                    // The diagram explains the positions listed above.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: Math.round(34 * root.u)
                        radius: 6
                        color: diagramMouse.pressed ? "#33404D" : "transparent"
                        border.color: "#5FB4E0"
                        border.width: 1.5
                        Row {
                            anchors.centerIn: parent
                            spacing: Math.round(6 * root.u)
                            Glyph { kind: "diagram"; tint: "#8FD0F2"; glyphSize: root.fs(13); anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: qsTr("VERTICAL POSITION DIAGRAM")
                                font.bold: true
                                font.pixelSize: root.fs(10.5)
                                color: "#8FD0F2"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: diagramMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showVerticalDiagram()
                        }
                    }

                    // Final bend override, next to the position it replaces
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: Math.round(92 * root.u)
                        radius: 6
                        color: "#2A313A"
                        border.color: root.overrideEnabled ? "#F87171" : "#3A424D"
                        border.width: root.overrideEnabled ? 1.5 : 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Math.round(8 * root.u)
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                Layout.preferredHeight: Math.round(34 * root.u)
                                Column {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: qsTr("MANUAL RAM OVERRIDE"); font.bold: true; font.pixelSize: root.fs(10.5); font.letterSpacing: 0.4; color: root.overrideEnabled ? "#FCA5A5" : "#E2E8F0" }
                                    Text { text: root.overrideEnabled ? qsTr("Formula bypassed") : qsTr("Automatic formula active"); font.pixelSize: root.fs(10); color: "#94A3B8" }
                                }
                                ToggleSwitch {
                                    checked: root.overrideEnabled
                                    onColor: root.red
                                    offColor: "#566070"
                                    onToggled: {
                                        var next = !root.overrideEnabled
                                        if (next) {
                                            // Without the controller opening there is no valid
                                            // machine position to seed; never seed 0.000.
                                            var calc = Number(root.calculation.calculatedFinalBendPosition)
                                            if (!isFinite(calc)) return
                                            root.setBendValue("overriddenFinalBendPosition", calc)
                                        }
                                        root.setBendValue("overrideFinalBendPositionEnabled", next)
                                    }
                                }
                            }

                            CompactParamRow {
                                dark: true
                                enabled: root.overrideEnabled
                                paramLabel: qsTr("Forced Position")
                                paramValue: dispLen(root.machineRamPosition(root.currentBend.overriddenFinalBendPosition), 4, "—")
                                paramUnit: root.metric ? "mm" : "in"
                                editable: root.overrideEnabled
                                onEditTriggered: {
                                    if (!root.appState) return
                                    var t = { text: dispLen(root.machineRamPosition(root.currentBend.overriddenFinalBendPosition), 4, "0.0000") }
                                    root.appState.openOnScreenKeyboard(t, true, qsTr("FORCED RAM POSITION"), function(v) {
                                        root.setNumericValue("overriddenFinalBendPosition", root.fromLen(v))
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. FOOTER ACTIONS
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.barH
            radius: 7
            color: root.cardBg
            border.color: root.cardBorderColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                BarButton {
                    Layout.preferredWidth: Math.round(120 * root.sx)
                    glyph: root.editing ? "close" : "plus"
                    label: root.editing ? qsTr("CANCEL") : qsTr("NEW BEND")
                    fill: root.editing ? root.red : root.blue
                    onTriggered: root.editing ? root.cancelEditing() : root.createNew()
                }

                BarButton {
                    Layout.preferredWidth: Math.round(90 * root.sx)
                    glyph: "check"
                    label: qsTr("SAVE")
                    fill: root.green
                    active: root.canSave
                    onTriggered: root.saveEditing()
                }

                BarButton {
                    Layout.preferredWidth: Math.round(100 * root.sx)
                    label: qsTr("DUPLICATE")
                    fill: root.orange
                    active: root.hasBends && !root.creatingNew
                    onTriggered: root.duplicateCurrent()
                }

                BarButton {
                    Layout.preferredWidth: Math.round(80 * root.sx)
                    label: qsTr("RESET")
                    fill: root.slate
                    active: root.editing && root.hasBends
                    onTriggered: root.resetEditing()
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.saveHint
                    font.bold: true
                    font.pixelSize: root.fs(10)
                    color: root.canSave ? root.amber : (root.hasUnsavedChanges ? root.red : root.textMuted)
                    elide: Text.ElideRight
                }

                BarButton {
                    Layout.preferredWidth: Math.round(220 * root.sx)
                    glyph: "load"
                    label: qsTr("LOAD BEND INTO PROGRAM")
                    fill: root.charcoal
                    active: root.hasBends && !root.editing
                    onTriggered: {
                        if (root.appState) {
                            root.appState.createBendAction("load",
                                root.currentBend.name || "Bend",
                                root.currentBend,
                                root.currentPunch,
                                root.currentDie,
                                root.currentMaterial,
                                Number(root.calculation.inUseFinalBendPosition),
                                Number(root.calculation.bendTonnage))
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // REUSABLE SUBCOMPONENTS
    // =========================================================================

    // Stroke icons on a 16x16 grid. The press image has no emoji font, so
    // pictographs are drawn instead of typed.
    component Glyph: Canvas {
        id: glyphCanvas
        property string kind: "down"
        property color tint: "#FFFFFF"
        property real glyphSize: 16
        implicitWidth: glyphSize
        implicitHeight: glyphSize
        antialiasing: true
        onKindChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d")
            c.reset()
            var k = Math.min(width, height) / 16
            c.scale(k, k)
            c.strokeStyle = glyphCanvas.tint
            c.lineWidth = 1.9
            c.lineCap = "round"
            c.lineJoin = "round"
            var strokes = []
            switch (glyphCanvas.kind) {
            case "up": strokes = [[3, 10.5, 8, 5.5, 13, 10.5]]; break
            case "left": strokes = [[10.5, 3, 5.5, 8, 10.5, 13]]; break
            case "right": strokes = [[5.5, 3, 10.5, 8, 5.5, 13]]; break
            case "close": strokes = [[4, 4, 12, 12], [12, 4, 4, 12]]; break
            case "plus": strokes = [[8, 3, 8, 13], [3, 8, 13, 8]]; break
            case "check": strokes = [[3, 8.5, 6.5, 12, 13, 4.5]]; break
            case "edit": strokes = [[3, 13, 3.7, 10.1, 10.8, 3, 13, 5.2, 5.9, 12.3, 3, 13], [9.4, 4.4, 11.6, 6.6]]; break
            case "trash": strokes = [[2.5, 4.5, 13.5, 4.5], [6.2, 4.5, 6.2, 2.5, 9.8, 2.5, 9.8, 4.5],
                                     [4.2, 4.5, 5, 13.5, 11, 13.5, 11.8, 4.5], [6.8, 7, 6.8, 11], [9.2, 7, 9.2, 11]]; break
            case "load": strokes = [[8, 2, 8, 10], [4.5, 6.5, 8, 10, 11.5, 6.5], [2.5, 11, 2.5, 13.5, 13.5, 13.5, 13.5, 11]]; break
            case "alert": strokes = [[8, 2.5, 14, 13, 2, 13, 8, 2.5], [8, 6.5, 8, 9.3], [8, 11.2, 8, 11.3]]; break
            case "diagram": strokes = [[3, 2, 13, 2], [3, 14, 13, 14], [8, 4.5, 8, 11.5],
                                       [6, 6.5, 8, 4.5, 10, 6.5], [6, 9.5, 8, 11.5, 10, 9.5]]; break
            default: strokes = [[3, 5.5, 8, 10.5, 13, 5.5]]
            }
            c.beginPath()
            for (var s = 0; s < strokes.length; s++) {
                var p = strokes[s]
                c.moveTo(p[0], p[1])
                for (var i = 2; i < p.length; i += 2) c.lineTo(p[i], p[i + 1])
            }
            c.stroke()
        }
    }

    component BarButton: Rectangle {
        id: bb
        property string label: ""
        property string glyph: ""
        property color fill: root.blue
        property bool active: true
        signal triggered()

        implicitHeight: root.ctlH
        implicitWidth: Math.max(implicitHeight, bbRow.implicitWidth + Math.round(22 * root.u))
        radius: 5
        color: !active ? "#94A3B8" : (bbMouse.pressed ? Qt.darker(fill, 1.3) : fill)
        border.color: active ? Qt.darker(fill, 1.25) : "#8B95A1"
        border.width: 1
        opacity: active ? 1.0 : 0.6

        Row {
            id: bbRow
            anchors.centerIn: parent
            spacing: Math.round(6 * root.u)
            Glyph {
                visible: bb.glyph.length > 0
                kind: bb.glyph
                glyphSize: root.fs(14)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: bb.label.length > 0
                text: bb.label
                font.bold: true
                font.pixelSize: root.fs(11)
                color: "#FFFFFF"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: bbMouse
            anchors.fill: parent
            enabled: bb.active
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: bb.triggered()
        }
    }

    component ToggleSwitch: Rectangle {
        id: sw
        property bool checked: false
        property color onColor: root.green
        property color offColor: "#94A3B8"
        signal toggled()

        implicitWidth: Math.round(56 * root.u)
        implicitHeight: Math.round(28 * root.u)
        radius: height / 2
        color: checked ? onColor : offColor

        Rectangle {
            width: sw.height - 6
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? (sw.width - width - 3) : 3
            color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 150 } }
        }

        MouseArea {
            anchors.fill: parent
            // Finger-sized target around the visible switch.
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    // One level of surface only: a card holds its fields directly.
    component Card: Rectangle {
        radius: 8
        color: root.cardFill
        border.color: "#98A2AE"
        border.width: 1
    }

    // Plain caption in a fixed-height row. Children declared on an instance
    // are appended to the right of the caption (a state tag, a switch).
    component SectionTitle: RowLayout {
        id: st
        property string title: ""
        property bool onDark: false
        property color ink: onDark ? "#AEB8C4" : "#3B4756"

        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: root.titleH
        Layout.maximumHeight: root.titleH
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: st.title
            font.bold: true
            font.pixelSize: root.fs(11)
            font.letterSpacing: 1.0
            color: st.ink
            elide: Text.ElideRight
        }
    }

    component ToolSelectorBar: Rectangle {
        id: bar
        property string category: "PUNCH"
        property string toolName: ""
        property string subSpec: ""
        property color accent: root.red
        property var items: []
        property int currentIndex: 0
        readonly property bool menuOpen: toolPopup.visible
        signal selected(int index)

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Math.round(36 * root.u)
        Layout.preferredHeight: Math.round(44 * root.u)
        radius: 6
        color: barMouse.containsMouse || toolPopup.opened ? "#F1F5F9" : "#FFFFFF"
        border.color: toolPopup.opened ? accent : (barMouse.containsMouse ? accent : root.fieldBorder)
        border.width: toolPopup.opened ? 2 : 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            // Category + spec on the first line, tool name on the second
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: bar.category
                        font.bold: true
                        font.pixelSize: root.fs(9.5)
                        color: bar.accent
                        font.letterSpacing: 0.6
                    }
                    Text {
                        Layout.fillWidth: true
                        text: bar.subSpec
                        font.pixelSize: root.fs(9.5)
                        color: root.textMuted
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: bar.toolName.length > 0 ? bar.toolName : ("Select " + bar.category)
                    font.bold: true
                    font.pixelSize: root.fs(13)
                    color: root.textPrimary
                    elide: Text.ElideRight
                }
            }

            Glyph {
                kind: toolPopup.opened ? "up" : "down"
                tint: bar.accent
                glyphSize: root.fs(14)
            }
        }

        MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (toolPopup.opened) toolPopup.close()
                else toolPopup.open()
            }
        }

        // Popup matching the exact width of the selector bar
        Popup {
            id: toolPopup
            y: bar.height + 2
            x: 0
            width: bar.width
            implicitHeight: Math.min(Math.round(236 * root.u), (toolList.contentHeight > 0 ? toolList.contentHeight : 160) + 8)
            padding: 3
            modal: false
            focus: true
            // PressOutside (not Parent) closed on the bar press and the click
            // toggle then reopened it.
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

            background: Rectangle {
                radius: 6
                color: "#FFFFFF"
                border.color: bar.accent
                border.width: 2
            }

            contentItem: ListView {
                id: toolList
                clip: true
                model: bar.items
                spacing: 2

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 6
                    contentItem: Rectangle { radius: 3; color: "#94A3B8" }
                }

                delegate: Rectangle {
                    id: itemDelegate
                    width: ListView.view.width
                    height: Math.round(42 * root.u)
                    radius: 4
                    color: {
                        if (index === bar.currentIndex) return Qt.alpha(bar.accent, 0.12)
                        if (itemMouse.containsMouse) return "#F1F5F9"
                        return "transparent"
                    }
                    border.color: index === bar.currentIndex ? bar.accent : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            Layout.preferredWidth: root.fs(14)
                            Layout.preferredHeight: root.fs(14)
                            Glyph {
                                anchors.centerIn: parent
                                visible: index === bar.currentIndex
                                kind: "check"
                                tint: bar.accent
                                glyphSize: root.fs(14)
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: index !== bar.currentIndex
                                width: 5; height: 5; radius: 2.5
                                color: "#94A3B8"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || ("Tool " + (index + 1))
                                font.bold: index === bar.currentIndex
                                font.pixelSize: root.fs(12)
                                color: index === bar.currentIndex ? bar.accent : root.textPrimary
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (bar.category === "PUNCH") {
                                        return "Height: " + root.lenTxt(Number(modelData.heightInch || 0)) + " · " + (modelData.punchAngleDegree ? modelData.punchAngleDegree + "°" : "") + " · " + (modelData.punchProfileType || "PUNCH")
                                    } else if (bar.category === "DIE") {
                                        return "V-Opening: " + root.lenTxt(Number(modelData.vdieOpeningInch || 0)) + " · Height: " + root.lenTxt(Number(modelData.heightInch || 0))
                                    } else {
                                        return "Tensile: " + (modelData.materialTensileStrengthPsi ? Math.round(modelData.materialTensileStrengthPsi / 1000) + "k PSI" : "60k PSI") + " · Springback: " + (modelData.materialSpringback || 1.0) + "°"
                                    }
                                }
                                font.pixelSize: root.fs(9.5)
                                color: root.textMuted
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            bar.selected(index)
                            toolPopup.close()
                        }
                    }
                }
            }
        }
    }

    // One input: a full-width bar with the label on the left and the value on
    // the right. The whole bar is the touch target. Bars share the free height
    // of their card. `dark` is the variant used on the result rail.
    component CompactParamRow: Rectangle {
        id: pr
        property string paramLabel: ""
        property string paramValue: ""
        property string paramUnit: ""
        property bool editable: true
        property bool dark: false
        signal editTriggered()

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Math.round(30 * root.u)
        Layout.preferredHeight: root.rowH
        Layout.maximumHeight: Math.round(50 * root.u)
        radius: 6
        color: pr.dark
            ? (pr.editable ? (prMouse.pressed ? "#33404D" : "#11151A") : "#232931")
            : (pr.editable ? (prMouse.pressed ? "#DBEAFE" : "#FFFFFF") : root.fieldOffBg)
        border.color: pr.dark
            ? (pr.editable ? "#F87171" : "#3A424D")
            : (pr.editable ? root.fieldBorder : root.fieldOffBorder)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 5

            Text {
                text: pr.paramLabel
                font.bold: true; font.pixelSize: root.fs(11.5)
                color: pr.dark
                    ? (pr.editable ? "#E2E8F0" : "#7C8796")
                    : (pr.editable ? root.textSecondary : root.textMuted)
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: pr.paramValue
                font.bold: true; font.pixelSize: root.fs(15); font.family: "Monospace"
                color: pr.dark
                    ? (pr.editable ? "#FFFFFF" : "#7C8796")
                    : (pr.editable ? root.textPrimary : root.textMuted)
            }
            // Fixed slot, so values line up when units differ (in / IPM).
            Text {
                visible: pr.paramUnit.length > 0
                Layout.minimumWidth: root.fs(22)
                text: pr.paramUnit
                font.pixelSize: root.fs(10)
                color: pr.dark ? "#94A3B8" : root.textMuted
            }
        }

        MouseArea {
            id: prMouse
            anchors.fill: parent
            enabled: pr.editable
            cursorShape: pr.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: pr.editTriggered()
        }
    }

    // Read-only calculated value on the result rail.
    component CompactDroRow: Item {
        id: dr
        property string label: ""
        property string value: ""
        property bool divider: true

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Math.round(20 * root.u)
        Layout.preferredHeight: Math.round(30 * root.u)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 2; anchors.rightMargin: 2
            spacing: 8
            Text {
                text: dr.label
                font.pixelSize: root.fs(11)
                color: "#CBD5E1"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: dr.value
                font.bold: true; font.pixelSize: root.fs(13); font.family: "Monospace"
                color: "#FFFFFF"
            }
        }

        Rectangle {
            visible: dr.divider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "#343C47"
        }
    }
}
