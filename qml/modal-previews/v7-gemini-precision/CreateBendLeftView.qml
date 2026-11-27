import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "../.."
import "../../core/BendCalculator.js" as BendCalculator

Item {
    id: root
    objectName: "create-bend-view bend-notes body button-append-new button-cancel button-compensation-direction button-create-new button-delete button-duplicate button-edit button-info button-open-vertical-diagram button-reset button-save combo-die combo-material combo-punch create-bend-press-toggle fields highlighted-text-field highlight-left-rounded icon-small item-selection label-overridden label-warning-orange label-warning-red measurement-text-field-override multi-icon panel-empty panel-warning-container pdm second-title small text-bend-notes text-bend-notes-bottom white-combo-box"
    property var appState: null

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
        ? appState.backGaugeCoordinateSystems
        : ["G54", "G55", "G56", "G57", "G58", "G59"]
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
        workingBends = cloneValue(appState ? appState.programBends || [] : [])
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
    function saveEditing() {
        if (!canSave) return
        var nextBends = cloneValue(workingBends)
        if (creatingNew) {
            nextBends.push(cloneValue(draftBend))
            selectedBendIndex = nextBends.length - 1
        } else {
            nextBends[selectedBendIndex] = cloneValue(draftBend)
        }
        workingBends = nextBends
        editing = false
        creatingNew = false
        editingName = false
        if (appState) appState.saveBends(workingBends)
        syncSelectedToolIndexes()
    }
    function resetEditing() {
        if (!editing) return
        draftBend = cloneValue(editSnapshot)
        syncSelectedToolIndexes()
    }
    function requestDelete() {
        if (creatingNew) { cancelEditing(); return }
        if (!hasBends || selectedBendIndex < 0) return
        var nextBends = cloneValue(workingBends)
        nextBends.splice(selectedBendIndex, 1)
        workingBends = nextBends
        selectedBendIndex = Math.max(0, Math.min(selectedBendIndex, workingBends.length - 1))
        editing = false
        creatingNew = false
        editingName = false
        if (appState) appState.saveBends(workingBends)
        syncSelectedToolIndexes()
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
        if (calculation.clearanceWarning) list.push({ level: "warning", text: qsTr("CLEARANCE WARNING: Punch-to-material clearance exceeds 0.300 in") })
        if (calculation.upperLimitExceededError) list.push({ level: "error", text: qsTr("TRAVEL LIMIT: Ram target exceeds upper physical travel") })
        if (calculation.lowerLimitExceededError) list.push({ level: "error", text: qsTr("TRAVEL LIMIT: Ram target exceeds lower bed limit") })
        return list
    }
    function showVerticalDiagram() {
        if (!appState) return
        appState.showImagePopup("VERTICAL POSITIONS DIAGRAM",
            "START SAFETY CLEARANCE  " + numberText(calculation.startSafetyClearance, 3, "—") + " in\n\n"
            + "BEND CLAMP POSITION  " + numberText(calculation.clampPosition, 3, "—") + " in\n\n"
            + "FINAL BEND POSITION  " + numberText(calculation.inUseFinalBendPosition, 3, "—") + " in\n\n"
            + "RETRACT AFTER BEND  " + numberText(calculation.retractAfterBend, 3, "—") + " in\n\n"
            + "TOTAL BEND STROKE  " + numberText(overrideEnabled ? calculation.overriddenTotalBendStroke : calculation.totalBendStroke, 3, "—") + " in",
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

    // Base industrial canvas
    Rectangle {
        anchors.fill: parent
        color: root.canvasBg
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // 1. TOP SEQUENCE & MOVE NAVIGATION HEADER (height: 48)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 7
            color: root.cardHeaderBg
            border.color: "#3F4246"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                // Move Step Pill & Arrows
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        width: 100
                        height: 32
                        radius: 5
                        color: "#383A3D"
                        border.color: "#475569"
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Text { text: "📐"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: qsTr("BEND %1/%2").arg(root.workingBends.length > 0 ? (root.selectedBendIndex + 1) : 0).arg(root.workingBends.length)
                                font.bold: true
                                font.pixelSize: 10
                                color: "#FFFFFF"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Prev Bend
                    Rectangle {
                        width: 34; height: 34; radius: 5
                        color: navPrevMouse.containsMouse ? "#4B5563" : "#383A3D"
                        border.color: "#475569"
                        opacity: root.selectedBendIndex > 0 ? 1.0 : 0.4
                        Text { anchors.centerIn: parent; text: "◀"; font.pixelSize: 11; font.bold: true; color: "#FFFFFF" }
                        MouseArea {
                            id: navPrevMouse
                            anchors.fill: parent
                            enabled: root.selectedBendIndex > 0 && !root.editing
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: { root.selectedBendIndex--; root.syncSelectedToolIndexes() }
                        }
                    }

                    // Next Bend
                    Rectangle {
                        width: 34; height: 34; radius: 5
                        color: navNextMouse.containsMouse ? "#4B5563" : "#383A3D"
                        border.color: "#475569"
                        opacity: root.selectedBendIndex < (root.workingBends.length - 1) ? 1.0 : 0.4
                        Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 11; font.bold: true; color: "#FFFFFF" }
                        MouseArea {
                            id: navNextMouse
                            anchors.fill: parent
                            enabled: root.selectedBendIndex < (root.workingBends.length - 1) && !root.editing
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: { root.selectedBendIndex++; root.syncSelectedToolIndexes() }
                        }
                    }
                }

                // Sequence Dropdown / Name Input
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    Layout.alignment: Qt.AlignVCenter

                    // Dropdown (when not renaming)
                    Rectangle {
                        visible: !root.editingName
                        anchors.fill: parent
                        radius: 5
                        color: "#1E232A"
                        border.color: "#475569"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                text: root.currentBend.name || qsTr("Untitled Bend Move")
                                font.bold: true
                                font.pixelSize: 13
                                color: "#FFFFFF"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "▼"
                                font.pixelSize: 10
                                color: "#94A3B8"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bendSelectorMenu.open()
                        }

                        Menu {
                            id: bendSelectorMenu
                            Repeater {
                                model: root.names(root.workingBends)
                                MenuItem {
                                    text: modelData
                                    onTriggered: {
                                        root.selectedBendIndex = index
                                        root.syncSelectedToolIndexes()
                                    }
                                }
                            }
                        }
                    }

                    // Name Editor (when renaming)
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
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            Text {
                                text: root.currentBend.name || ""
                                font.bold: true
                                font.pixelSize: 13
                                color: root.textPrimary
                                Layout.fillWidth: true
                            }
                            Text {
                                text: qsTr("TAP TO EDIT")
                                font.pixelSize: 9
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

                // Edit Name Button / Delete Button
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        width: 34; height: 34; radius: 5
                        color: root.editingName ? root.slate : root.blue
                        border.color: root.editingName ? "#475569" : "#1E6E9E"
                        Text { anchors.centerIn: parent; text: root.editingName ? "✕" : "✎"; font.pixelSize: 14; font.bold: true; color: "#FFFFFF" }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.editingName) root.editingName = false
                                else root.beginEdit(true)
                            }
                        }
                    }

                    Rectangle {
                        width: 34; height: 34; radius: 5
                        color: root.red
                        border.color: "#8E1B0E"
                        visible: root.editingName
                        Text { anchors.centerIn: parent; text: "🗑"; font.pixelSize: 13; color: "#FFFFFF" }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestDelete()
                        }
                    }
                }
            }
        }

        // 2. MAIN 3-COLUMN INDUSTRIAL PRECISION GRID
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // =================================================================
            // COLUMN 1: TOOLING CHIPS & ANGLE HERO & CLEARANCES (Width ~280)
            // =================================================================
            Rectangle {
                Layout.preferredWidth: 284 * root.sx
                Layout.fillHeight: true
                radius: 7
                color: root.cardBg
                border.color: root.cardBorderColor
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    CardHeader { title: qsTr("TOOLING & BEND ANGLE"); accentColor: root.red }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 8
                        spacing: 8

                        // 1. Tooling Selection Stack (Full Width, Matching Dropdown)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            ToolSelectorBar {
                                category: "PUNCH"
                                toolName: root.currentPunch.name || "Default Punch"
                                subSpec: "H: " + (root.currentPunch.heightInch ? root.currentPunch.heightInch.toFixed(3) : "4.603") + "″ · " + (root.currentPunch.punchProfileType || "STANDARD")
                                rightBadge: (root.currentPunch.heightInch ? root.currentPunch.heightInch.toFixed(3) : "4.603") + "″"
                                accent: root.red
                                items: root.punchItems
                                currentIndex: root.selectedPunchIndex
                                onSelected: function(idx) { root.selectTool("Punch", idx) }
                            }

                            ToolSelectorBar {
                                category: "DIE"
                                toolName: root.currentDie.name || "Default Die"
                                subSpec: "V: " + (root.currentDie.vdieOpeningInch ? root.currentDie.vdieOpeningInch.toFixed(3) : "0.472") + "″ · H: " + (root.currentDie.heightInch ? root.currentDie.heightInch.toFixed(3) : "1.870") + "″"
                                rightBadge: "V=" + (root.currentDie.vdieOpeningInch ? root.currentDie.vdieOpeningInch.toFixed(3) : "0.472") + "″"
                                accent: root.blue
                                items: root.dieItems
                                currentIndex: root.selectedDieIndex
                                onSelected: function(idx) { root.selectTool("Die", idx) }
                            }

                            ToolSelectorBar {
                                category: "MATERIAL"
                                toolName: root.currentMaterial.name || "Default Material"
                                subSpec: "Tensile: " + (root.currentMaterial.materialTensileStrengthPsi ? Math.round(root.currentMaterial.materialTensileStrengthPsi / 1000) + "k PSI" : "60k PSI") + " · T: " + (root.currentBend.materialThickness ? root.currentBend.materialThickness.toFixed(3) : "0.060") + "″"
                                rightBadge: (root.currentBend.materialThickness ? root.currentBend.materialThickness.toFixed(3) : "0.060") + "″"
                                accent: root.green
                                items: root.materialItems
                                currentIndex: root.selectedMaterialIndex
                                onSelected: function(idx) { root.selectTool("Material", idx) }
                            }
                        }

                        // 2. HERO BEND ANGLE CARD
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 125 * root.sy
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1.5

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: qsTr("DESIRED BEND ANGLE")
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: root.textPrimary
                                        font.letterSpacing: 0.5
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        radius: 3
                                        color: "#EFF6FF"
                                        border.color: "#BFDBFE"
                                        Layout.preferredWidth: 50; Layout.preferredHeight: 16
                                        Text { anchors.centerIn: parent; text: "TARGET"; font.bold: true; font.pixelSize: 8; color: root.blue }
                                    }
                                }

                                // Large Digital Angle Readout
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 8

                                    // Decrement button
                                    Button {
                                        Layout.preferredWidth: 34; Layout.preferredHeight: 34
                                        padding: 0
                                        enabled: !root.overrideEnabled
                                        onClicked: root.setNumericValue("desiredBendAngle", Number(root.currentBend.desiredBendAngle || 90) - 0.5, 15, 170)
                                        background: Rectangle { radius: 4; color: "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Text { anchors.centerIn: parent; text: "-0.5°"; font.bold: true; font.pixelSize: 10; color: root.textSecondary }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        radius: 6
                                        color: "#1E232A"
                                        border.color: root.blue
                                        border.width: 1.5

                                        Text {
                                            anchors.centerIn: parent
                                            text: numberText(root.currentBend.desiredBendAngle, 1, "90.0") + "°"
                                            font.bold: true
                                            font.pixelSize: 26
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

                                    // Increment button
                                    Button {
                                        Layout.preferredWidth: 34; Layout.preferredHeight: 34
                                        padding: 0
                                        enabled: !root.overrideEnabled
                                        onClicked: root.setNumericValue("desiredBendAngle", Number(root.currentBend.desiredBendAngle || 90) + 0.5, 15, 170)
                                        background: Rectangle { radius: 4; color: "#F1F5F9"; border.color: "#CBD5E1" }
                                        contentItem: Item {
                                            anchors.fill: parent
                                            Text { anchors.centerIn: parent; text: "+0.5°"; font.bold: true; font.pixelSize: 10; color: root.textSecondary }
                                        }
                                    }
                                }

                                // Angle Compensation Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // Toggle Direction Pill
                                    Rectangle {
                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 26
                                        radius: 4
                                        color: root.currentBend.angleCompensationReversed ? root.blue : root.amber
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.currentBend.angleCompensationReversed ? "UNDER" : "OVER"
                                            font.bold: true
                                            font.pixelSize: 10
                                            color: "#FFFFFF"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !root.overrideEnabled
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setBendValue("angleCompensationReversed", !root.currentBend.angleCompensationReversed)
                                        }
                                    }

                                    // Compensation Degrees Input
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 26
                                        radius: 4
                                        color: "#F8FAFC"
                                        border.color: "#CBD5E1"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            Text { text: qsTr("COMP:"); font.bold: true; font.pixelSize: 9; color: root.textMuted }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: numberText(root.currentBend.angleCompensation, 1, "0.0") + "°"
                                                font.bold: true; font.pixelSize: 11; font.family: "Monospace"; color: root.textPrimary
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !root.overrideEnabled
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
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

                        // 3. Workpiece Dimensions & Ram Clearance Fields
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#FFFFFF"
                            border.color: "#CBD5E1"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                CompactParamRow {
                                    paramLabel: qsTr("Material Thickness")
                                    paramValue: numberText(root.currentBend.materialThickness, 3, "0.060")
                                    paramUnit: "in"
                                    editable: !root.overrideEnabled
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.materialThickness, 3, "0.060") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("MATERIAL THICKNESS (0.01 - 2.5 IN)"), function(v) {
                                            root.setNumericValue("materialThickness", v, 0.01, 2.5)
                                        })
                                    }
                                }

                                CompactParamRow {
                                    paramLabel: qsTr("Flange Bend Width")
                                    paramValue: numberText(root.currentBend.bendWidth, 1, "12.0")
                                    paramUnit: "in"
                                    editable: true
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.bendWidth, 1, "12.0") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("BEND WIDTH (0.1 - 33.3 IN)"), function(v) {
                                            root.setNumericValue("bendWidth", v, 0.1, 33.3)
                                        })
                                    }
                                }

                                CompactParamRow {
                                    paramLabel: qsTr("Punch-to-Material Gap")
                                    paramValue: numberText(root.currentBend.punchToMaterialClearance, 3, "0.050")
                                    paramUnit: "in"
                                    editable: true
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.punchToMaterialClearance, 3, "0.050") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("PUNCH TO MATERIAL CLEARANCE"), function(v) {
                                            root.setNumericValue("punchToMaterialClearance", v, 0.01, 5.0)
                                        })
                                    }
                                }

                                CompactParamRow {
                                    paramLabel: qsTr("Additional Retract")
                                    paramValue: numberText(root.currentBend.additionalRetractAfterBend, 3, "0.000")
                                    paramUnit: "in"
                                    editable: true
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.additionalRetractAfterBend, 3, "0.000") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("ADDITIONAL RETRACT (0 - 3.75 IN)"), function(v) {
                                            root.setNumericValue("additionalRetractAfterBend", v, 0, 3.75)
                                        })
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // COLUMN 2: AUTOMATION & BACK GAUGE (Width ~270)
            // =================================================================
            Rectangle {
                Layout.preferredWidth: 270 * root.sx
                Layout.fillHeight: true
                radius: 7
                color: root.cardBg
                border.color: root.cardBorderColor
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    CardHeader { title: qsTr("AUTOMATION & BACK GAUGE"); accentColor: root.green }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 8
                        spacing: 8

                        // 1. BACK GAUGE MOVE CARD
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 180 * root.sy
                            radius: 6
                            color: "#FFFFFF"
                            border.color: root.backGaugeEnabled ? root.green : "#CBD5E1"
                            border.width: 1.5

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                // Hero Toggle Switch
                                RowLayout {
                                    Layout.fillWidth: true
                                    Column {
                                        Text { text: qsTr("BACK GAUGE MOTION"); font.bold: true; font.pixelSize: 10; color: root.textPrimary }
                                        Text { text: root.backGaugeEnabled ? qsTr("Active stop positioning") : qsTr("Stationary / Disabled"); font.pixelSize: 9; color: root.textMuted }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 50; height: 24; radius: 12
                                        color: root.backGaugeEnabled ? root.green : "#94A3B8"
                                        Rectangle {
                                            width: 18; height: 18; radius: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: root.backGaugeEnabled ? (parent.width - 21) : 3
                                            color: "#FFFFFF"
                                            Behavior on x { NumberAnimation { duration: 150 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setBendValue("backGaugeRefEdgeStopEnabled", !root.backGaugeEnabled)
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#E2E8F0" }

                                // Coordinate Stop Dropdown
                                RowLayout {
                                    Layout.fillWidth: true
                                    enabled: root.backGaugeEnabled
                                    opacity: root.backGaugeEnabled ? 1.0 : 0.4
                                    Text { text: qsTr("STOP DATUM:"); font.bold: true; font.pixelSize: 9; color: root.textSecondary }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredWidth: 90; Layout.preferredHeight: 24; radius: 4
                                        color: "#F1F5F9"; border.color: "#CBD5E1"
                                        Text { anchors.centerIn: parent; text: root.currentBend.backGaugeRefEdgeStop || "G54"; font.bold: true; font.pixelSize: 10; color: root.textPrimary }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: gMenu.open()
                                        }
                                        Menu {
                                            id: gMenu
                                            Repeater {
                                                model: root.backGaugeReferenceStopIds
                                                MenuItem {
                                                    text: modelData
                                                    onTriggered: root.setBendValue("backGaugeRefEdgeStop", modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                // X Position
                                CompactParamRow {
                                    enabled: root.backGaugeEnabled
                                    opacity: root.backGaugeEnabled ? 1.0 : 0.4
                                    paramLabel: qsTr("X Axis Stop")
                                    paramValue: numberText(root.currentBend.backGaugeXPosition, 3, "0.000")
                                    paramUnit: "in"
                                    editable: root.backGaugeEnabled
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.backGaugeXPosition, 3, "0.000") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("BACK GAUGE X POSITION"), function(v) {
                                            root.setNumericValue("backGaugeXPosition", v)
                                        })
                                    }
                                }

                                // R Elevation Position
                                CompactParamRow {
                                    enabled: root.backGaugeEnabled
                                    opacity: root.backGaugeEnabled ? 1.0 : 0.4
                                    paramLabel: qsTr("R Axis Elevation")
                                    paramValue: numberText(root.currentBend.backGaugeRPosition, 3, "0.000")
                                    paramUnit: "in"
                                    editable: root.backGaugeEnabled
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.backGaugeRPosition, 3, "0.000") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("BACK GAUGE R ELEVATION"), function(v) {
                                            root.setNumericValue("backGaugeRPosition", v)
                                        })
                                    }
                                }

                                // Jog Speed
                                CompactParamRow {
                                    enabled: root.backGaugeEnabled
                                    opacity: root.backGaugeEnabled ? 1.0 : 0.4
                                    paramLabel: qsTr("Jog Speed")
                                    paramValue: numberText(root.currentBend.backGaugeJogSpeed, 0, "100")
                                    paramUnit: "IPM"
                                    editable: root.backGaugeEnabled
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.currentBend.backGaugeJogSpeed, 0, "100") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("BACK GAUGE JOG SPEED (1 - 500 IPM)"), function(v) {
                                            root.setNumericValue("backGaugeJogSpeed", v, 1, 500)
                                        })
                                    }
                                }
                            }
                        }

                        // 2. FINAL BEND OVERRIDE CARD
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110 * root.sy
                            radius: 6
                            color: "#FFFFFF"
                            border.color: root.overrideEnabled ? root.red : "#CBD5E1"
                            border.width: 1.5

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Column {
                                        Text { text: qsTr("MANUAL RAM OVERRIDE"); font.bold: true; font.pixelSize: 10; color: root.overrideEnabled ? root.red : root.textPrimary }
                                        Text { text: root.overrideEnabled ? qsTr("Formula bypassed") : qsTr("Automatic formula active"); font.pixelSize: 9; color: root.textMuted }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: 50; height: 24; radius: 12
                                        color: root.overrideEnabled ? root.red : "#94A3B8"
                                        Rectangle {
                                            width: 18; height: 18; radius: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: root.overrideEnabled ? (parent.width - 21) : 3
                                            color: "#FFFFFF"
                                            Behavior on x { NumberAnimation { duration: 150 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
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
                                }

                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#E2E8F0" }

                                CompactParamRow {
                                    enabled: root.overrideEnabled
                                    opacity: root.overrideEnabled ? 1.0 : 0.4
                                    paramLabel: qsTr("Forced Ram Position")
                                    paramValue: numberText(root.machineRamPosition(root.currentBend.overriddenFinalBendPosition), 3, "—")
                                    paramUnit: "in"
                                    editable: root.overrideEnabled
                                    onEditTriggered: {
                                        if (!root.appState) return
                                        var t = { text: numberText(root.machineRamPosition(root.currentBend.overriddenFinalBendPosition), 3, "0.000") }
                                        root.appState.openOnScreenKeyboard(t, true, qsTr("FORCED RAM POSITION"), function(v) {
                                            root.setNumericValue("overriddenFinalBendPosition", v)
                                        })
                                    }
                                }
                            }
                        }

                        // 3. SAFETY ENVELOPE STATUS BADGE
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: root.activeWarnings.length > 0 ? (root.calculation.tonnageError ? "#FEF2F2" : "#FFFBEB") : "#F0FDF4"
                            border.color: root.activeWarnings.length > 0 ? (root.calculation.tonnageError ? "#FECACA" : "#FDE68A") : "#BBF7D0"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: root.activeWarnings.length > 0 ? (root.calculation.tonnageError ? root.red : root.amber) : root.green
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.activeWarnings.length > 0 ? "!" : "✓"
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: "#FFFFFF"
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    Text {
                                        text: root.activeWarnings.length > 0 ? qsTr("SAFETY WARNING DETECTED") : qsTr("GEOMETRY & TONNAGE VERIFIED")
                                        font.bold: true; font.pixelSize: 10
                                        color: root.activeWarnings.length > 0 ? (root.calculation.tonnageError ? root.red : root.amber) : "#15803D"
                                    }
                                    Text {
                                        text: root.activeWarnings.length > 0 ? root.activeWarnings[0].text : qsTr("All bend strokes and tonnage remain within rated limits.")
                                        font.pixelSize: 8
                                        color: root.textMuted
                                        wrapMode: Text.WordWrap
                                        width: 180
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // COLUMN 3: CALCULATED PARAMETERS (DRO) & BEND NOTES (Width ~290)
            // =================================================================
            ColumnLayout {
                Layout.preferredWidth: 284 * root.sx
                Layout.fillHeight: true
                spacing: 8

                // CARD 1: CALCULATED ENGINEERING PARAMETERS (DRO)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 7
                    color: root.cardBg
                    border.color: root.cardBorderColor
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        CardHeader { title: qsTr("CALCULATED PARAMETERS & DRO") }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.margins: 8
                            spacing: 5

                            // Tonnage Bar Card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                radius: 5
                                color: "#F8FAFC"
                                border.color: "#CBD5E1"
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: qsTr("BEND TONNAGE:"); font.bold: true; font.pixelSize: 9; color: root.textSecondary }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: numberText(root.calculation.bendTonnage, 1, "0.0") + " T / 12.5 T"
                                            font.bold: true; font.pixelSize: 11; font.family: "Monospace"
                                            color: root.calculation.tonnageError ? root.red : (root.calculation.tonnageWarning ? root.amber : root.green)
                                        }
                                    }
                                    // Progress bar
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: "#E2E8F0"
                                        Rectangle {
                                            width: Math.min(parent.width, Math.max(4, parent.width * (Number(root.calculation.bendTonnage || 0) / 12.5)))
                                            height: parent.height; radius: 4
                                            color: root.calculation.tonnageError ? root.red : (root.calculation.tonnageWarning ? root.amber : root.green)
                                        }
                                    }
                                }
                            }

                            // Readout rows
                            CompactDroRow {
                                label: qsTr("Final Ram Position")
                                value: numberText(root.calculation.inUseFinalBendPosition, 3, "—") + " in"
                                highlighted: root.overrideEnabled
                            }
                            CompactDroRow {
                                label: qsTr("Clamp Position")
                                value: numberText(root.calculation.clampPosition, 3, "—") + " in"
                            }
                            CompactDroRow {
                                label: qsTr("Start Safety Clearance")
                                value: numberText(root.calculation.startSafetyClearance, 3, "—") + " in"
                            }
                            CompactDroRow {
                                label: qsTr("Retract After Bend")
                                value: numberText(root.calculation.retractAfterBend, 3, "—") + " in"
                            }
                            CompactDroRow {
                                label: qsTr("Total Bend Stroke")
                                value: numberText(root.overrideEnabled ? root.calculation.overriddenTotalBendStroke : root.calculation.totalBendStroke, 3, "—") + " in"
                            }
                            CompactDroRow {
                                label: qsTr("Inside Bend Radius")
                                value: numberText(root.calculation.predictedInsideBendRadius, 3, "—") + " in"
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // CARD 2: OPERATOR BEND NOTES & VERTICAL DIAGRAM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 195 * root.sy
                    radius: 7
                    color: root.cardBg
                    border.color: root.cardBorderColor
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        CardHeader { title: qsTr("BEND NOTES & DIAGRAM") }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.margins: 8
                            spacing: 6

                            // Action Button for Vertical Diagram
                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                padding: 0
                                onClicked: root.showVerticalDiagram()
                                background: Rectangle {
                                    radius: 4
                                    color: root.red
                                }
                                contentItem: Item {
                                    anchors.fill: parent
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "📐"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Text {
                                            text: qsTr("OPEN VERTICAL POSITION DIAGRAM")
                                            font.bold: true
                                            font.pixelSize: 9
                                            color: "#FFFFFF"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }

                            // General Notes Area
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: "#FFFFFF"
                                border.color: "#CBD5E1"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 2

                                    Text {
                                        text: qsTr("GENERAL BEND NOTES:")
                                        font.bold: true
                                        font.pixelSize: 9
                                        color: root.textMuted
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: (root.currentBend && root.currentBend.notes) ? root.currentBend.notes : qsTr("Tap to write notes for this bend move...")
                                        font.pixelSize: 10
                                        color: (root.currentBend && root.currentBend.notes) ? root.textPrimary : "#94A3B8"
                                        wrapMode: Text.WordWrap
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.appState) return
                                        var t = { text: (root.currentBend && root.currentBend.notes) ? root.currentBend.notes : "" }
                                        root.appState.openOnScreenKeyboard(t, false, qsTr("GENERAL BEND NOTES"), function(v) {
                                            root.setBendValue("notes", v)
                                        })
                                    }
                                }
                            }

                            // X-Axis and R-Axis Reference Notes
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 4
                                    color: "#FFFFFF"
                                    border.color: "#CBD5E1"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        Text { text: qsTr("X:"); font.bold: true; font.pixelSize: 9; color: root.textMuted }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (root.currentBend && root.currentBend.xAxisNotes) ? root.currentBend.xAxisNotes : qsTr("X stop note...")
                                            font.pixelSize: 9
                                            color: (root.currentBend && root.currentBend.xAxisNotes) ? root.textPrimary : "#94A3B8"
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.appState) return
                                            var t = { text: (root.currentBend && root.currentBend.xAxisNotes) ? root.currentBend.xAxisNotes : "" }
                                            root.appState.openOnScreenKeyboard(t, false, qsTr("X-AXIS NOTES"), function(v) {
                                                root.setBendValue("xAxisNotes", v)
                                            })
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 4
                                    color: "#FFFFFF"
                                    border.color: "#CBD5E1"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        Text { text: qsTr("R:"); font.bold: true; font.pixelSize: 9; color: root.textMuted }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (root.currentBend && root.currentBend.rAxisNotes) ? root.currentBend.rAxisNotes : qsTr("R elev note...")
                                            font.pixelSize: 9
                                            color: (root.currentBend && root.currentBend.rAxisNotes) ? root.textPrimary : "#94A3B8"
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.appState) return
                                            var t = { text: (root.currentBend && root.currentBend.rAxisNotes) ? root.currentBend.rAxisNotes : "" }
                                            root.appState.openOnScreenKeyboard(t, false, qsTr("R-AXIS NOTES"), function(v) {
                                                root.setBendValue("rAxisNotes", v)
                                            })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. FOOTER ACTION HUB (height: 48)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 7
            color: root.cardBg
            border.color: root.cardBorderColor
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                // New Bend Move / Cancel
                Button {
                    Layout.preferredWidth: 120 * root.sx
                    Layout.preferredHeight: 34
                    padding: 0
                    onClicked: root.editing ? root.cancelEditing() : root.createNew()
                    background: Rectangle {
                        radius: 5
                        color: root.editing ? root.red : root.blue
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Text {
                            anchors.centerIn: parent
                            text: root.editing ? qsTr("CANCEL") : qsTr("+ NEW BEND")
                            font.bold: true; font.pixelSize: 10; color: "#FFFFFF"
                        }
                    }
                }

                // Save Bend Move
                Button {
                    Layout.preferredWidth: 90 * root.sx
                    Layout.preferredHeight: 34
                    padding: 0
                    enabled: root.canSave
                    onClicked: root.saveEditing()
                    background: Rectangle {
                        radius: 5
                        color: root.canSave ? root.green : "#94A3B8"
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("SAVE")
                            font.bold: true; font.pixelSize: 10; color: "#FFFFFF"
                        }
                    }
                }

                // Duplicate Bend Move
                Button {
                    Layout.preferredWidth: 100 * root.sx
                    Layout.preferredHeight: 34
                    padding: 0
                    enabled: root.hasBends && !root.creatingNew
                    onClicked: root.duplicateCurrent()
                    background: Rectangle {
                        radius: 5
                        color: root.hasBends && !root.creatingNew ? root.orange : "#94A3B8"
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("DUPLICATE")
                            font.bold: true; font.pixelSize: 10; color: "#FFFFFF"
                        }
                    }
                }

                // Reset Changes
                Button {
                    Layout.preferredWidth: 80 * root.sx
                    Layout.preferredHeight: 34
                    padding: 0
                    enabled: root.editing && root.hasBends
                    onClicked: root.resetEditing()
                    background: Rectangle {
                        radius: 5
                        color: root.editing && root.hasBends ? root.slate : "#94A3B8"
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("RESET")
                            font.bold: true; font.pixelSize: 10; color: "#FFFFFF"
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Load Bend into Program
                Button {
                    Layout.preferredWidth: 220 * root.sx
                    Layout.preferredHeight: 34
                    padding: 0
                    enabled: root.hasBends && !root.editing
                    onClicked: {
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
                    background: Rectangle {
                        radius: 5
                        color: root.hasBends && !root.editing ? root.charcoal : "#94A3B8"
                        border.color: "#475569"
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: "📥"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: qsTr("LOAD BEND INTO PROGRAM")
                                font.bold: true; font.pixelSize: 10; color: "#FFFFFF"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // REUSABLE SUBCOMPONENTS
    // =========================================================================

    component CardHeader: Rectangle {
        property string title: ""
        property color accentColor: root.blue
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: 7
        color: root.cardHeaderBg

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius
            color: parent.color
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: title
                font.bold: true
                font.pixelSize: 10
                color: "#FFFFFF"
                font.letterSpacing: 0.5
            }
        }
    }

    component ToolSelectorBar: Rectangle {
        id: bar
        property string category: "PUNCH"
        property string toolName: ""
        property string subSpec: ""
        property string rightBadge: ""
        property color accent: root.red
        property var items: []
        property int currentIndex: 0
        signal selected(int index)

        Layout.fillWidth: true
        Layout.preferredHeight: 38
        radius: 6
        color: barMouse.containsMouse || toolPopup.opened ? "#F8FAFC" : "#FFFFFF"
        border.color: toolPopup.opened ? accent : (barMouse.containsMouse ? accent : "#CBD5E1")
        border.width: toolPopup.opened ? 2 : 1.5

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            // Left Pill: Category Tag
            Rectangle {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 22
                radius: 4
                color: Qt.alpha(bar.accent, 0.12)
                border.color: Qt.alpha(bar.accent, 0.45)
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        color: bar.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: bar.category
                        font.bold: true
                        font.pixelSize: 9
                        color: bar.accent
                        font.letterSpacing: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Center: Tool Name and Sub-Spec
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: bar.toolName.length > 0 ? bar.toolName : ("Select " + bar.category)
                    font.bold: true
                    font.pixelSize: 11
                    color: root.textPrimary
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: bar.subSpec
                    font.pixelSize: 9
                    color: root.textMuted
                    elide: Text.ElideRight
                }
            }

            // Right: Dimension Badge with Chevron
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: rightRow.implicitWidth + 12
                radius: 4
                color: "#F1F5F9"
                border.color: "#CBD5E1"

                Row {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: bar.rightBadge
                        font.pixelSize: 9
                        font.bold: true
                        font.family: "Monospace"
                        color: root.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: toolPopup.opened ? "▲" : "▼"
                        font.pixelSize: 8
                        color: bar.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
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

        // Popup matching the exact width of the selector bar!
        Popup {
            id: toolPopup
            y: bar.height + 2
            x: 0
            width: bar.width
            implicitHeight: Math.min(210, (toolList.contentHeight > 0 ? toolList.contentHeight : 160) + 8)
            padding: 3
            modal: false
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

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
                    width: 5
                    contentItem: Rectangle { radius: 2.5; color: "#94A3B8" }
                }

                delegate: Rectangle {
                    id: itemDelegate
                    width: ListView.view.width
                    height: 38
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
                        spacing: 6

                        Text {
                            text: index === bar.currentIndex ? "✓" : "•"
                            font.bold: true
                            font.pixelSize: index === bar.currentIndex ? 12 : 14
                            color: index === bar.currentIndex ? bar.accent : "#94A3B8"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || ("Tool " + (index + 1))
                                font.bold: index === bar.currentIndex
                                font.pixelSize: 10
                                color: index === bar.currentIndex ? bar.accent : root.textPrimary
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (bar.category === "PUNCH") {
                                        return "Height: " + Number(modelData.heightInch || 0).toFixed(3) + "″ · " + (modelData.punchAngleDegree ? modelData.punchAngleDegree + "°" : "") + " · " + (modelData.punchProfileType || "PUNCH")
                                    } else if (bar.category === "DIE") {
                                        return "V-Opening: " + Number(modelData.vdieOpeningInch || 0).toFixed(3) + "″ · Height: " + Number(modelData.heightInch || 0).toFixed(3) + "″"
                                    } else {
                                        return "Tensile: " + (modelData.materialTensileStrengthPsi ? Math.round(modelData.materialTensileStrengthPsi / 1000) + "k PSI" : "60k PSI") + " · Springback: " + (modelData.materialSpringback || 1.0) + "°"
                                    }
                                }
                                font.pixelSize: 9
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

    component CompactParamRow: RowLayout {
        property string paramLabel: ""
        property string paramValue: ""
        property string paramUnit: ""
        property bool editable: true
        signal editTriggered()

        Layout.fillWidth: true
        Layout.preferredHeight: 28
        spacing: 6

        Text {
            text: paramLabel
            font.bold: true; font.pixelSize: 10; color: root.textSecondary
            Layout.fillWidth: true
        }

        Rectangle {
            Layout.preferredWidth: 84; Layout.preferredHeight: 26
            radius: 4
            color: editable ? "#F8FAFC" : "#F1F5F9"
            border.color: "#CBD5E1"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6; anchors.rightMargin: 6
                Text {
                    text: paramValue
                    font.bold: true; font.pixelSize: 11; font.family: "Monospace"
                    color: root.textPrimary; Layout.fillWidth: true
                }
                Text {
                    text: paramUnit
                    font.pixelSize: 9; color: root.textMuted
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: editable
                cursorShape: editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: editTriggered()
            }
        }
    }

    component CompactDroRow: Rectangle {
        property string label: ""
        property string value: ""
        property bool highlighted: false

        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 4
        color: highlighted ? "#FEF2F2" : "#F8FAFC"
        border.color: highlighted ? root.red : "#E2E8F0"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8; anchors.rightMargin: 8
            Text { text: label; font.bold: true; font.pixelSize: 9; color: highlighted ? root.red : root.textSecondary }
            Item { Layout.fillWidth: true }
            Text { text: value; font.bold: true; font.pixelSize: 11; font.family: "Monospace"; color: highlighted ? root.red : root.textPrimary }
        }
    }
}
