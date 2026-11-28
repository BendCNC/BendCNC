import QtQuick
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

    // BendCNC Vivid Industrial Palette (matching Manual, Run, and Tools)
    readonly property color canvasBg: "#BFC2C5"         // Authentic industrial grey base
    readonly property color cardBg: "#E0E0E0"           // Chapa metálica grey panels (eliminates sterile white)
    readonly property color cardHeaderBg: "#2B2C2B"     // Charcoal cockpit header
    readonly property color cardBorderColor: "#8B95A1"  // Technical card outline
    readonly property color cardDividerColor: "#CBD5E1" // Clean divider
    readonly property color inputBg: "#FFFFFF"          // Pure white reserved ONLY for interactive input fields
    readonly property color inputBorderColor: "#64748B" // Crisp defined border for inputs
    readonly property color textPrimary: "#0F172A"      // Primary ink
    readonly property color textSecondary: "#334155"    // Secondary text
    readonly property color textMuted: "#475569"        // Caption / label text

    readonly property color red: "#A82011"              // Vivid punch red
    readonly property color green: "#59A60C"            // Vivid material / save green
    readonly property color blue: "#2D83B2"             // Vivid die / angle blue
    readonly property color charcoal: "#1E232A"         // Deep charcoal for DRO boxes
    readonly property color grey: "#94A3B8"
    readonly property color lightGrey: "#E2E8F0"
    readonly property color paper: "#F1F5F9"
    readonly property color ink: "#0F172A"
    readonly property color white: "#FFFFFF"
    readonly property color purple: "#6366F1"
    readonly property color orange: "#EA580C"           // Safety orange for Duplicate
    readonly property color amber: "#D97706"            // Amber for Overbent
    readonly property color cardSurface: "#E0E0E0"
    readonly property color cardBorder: "#8B95A1"

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
    readonly property var nameEditor: bendNameEditor
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
    readonly property var editableMeasurementFields: [
        desiredAngleEditor, angleCompensationEditor, clearanceEditor,
        additionalRetractEditor, materialThicknessEditor, bendWidthEditor,
        backGaugeXEditor, backGaugeREditor, backGaugeSpeedEditor
    ]
    readonly property var punchItems: dataStore.punches
    readonly property var dieItems: dataStore.dies
    readonly property var materialItems: dataStore.materials
    readonly property var calculation: calculateBend()
    readonly property var activeWarnings: warningItems()
    readonly property bool hasBends: workingBends.length > 0 || creatingNew
    readonly property bool canSave: editing && hasUnsavedChanges
        && bendIsValid(currentBend) && isNameUnique(currentBend.name)

    DataStore {
        id: dataStore
    }

    Connections {
        target: root.appState
        ignoreUnknownSignals: true
        function onProgramBendsChanged() {
            if (!root.editing)
                root.syncWorkingBends()
        }
        function onActiveProgramChanged() {
            if (!root.editing)
                root.syncWorkingBends()
        }
    }

    Component.onCompleted: syncWorkingBends()
    onAppStateChanged: if (!editing) syncWorkingBends()

    function cloneValue(value) {
        if (value === undefined || value === null)
            return ({})
        return JSON.parse(JSON.stringify(value))
    }
    function syncWorkingBends() {
        workingBends = cloneValue(appState ? appState.programBends || [] : [])
        selectedBendIndex = workingBends.length > 0
            ? Math.max(0, Math.min(selectedBendIndex, workingBends.length - 1)) : -1
        syncSelectedToolIndexes()
    }
    function ensureEditing() {
        if (editing)
            return
        if (!hasBends)
            return
        editSnapshot = cloneValue(currentBend)
        draftBend = cloneValue(currentBend)
        editing = true
        creatingNew = false
    }
    function beginEdit(openNameKeyboard) {
        ensureEditing()
        if (!editing)
            return
        if (openNameKeyboard)
            beginNameEdit(bendNameEditor)
    }
    function defaultBend() {
        return {
            id: "bend-" + String(Date.now()), name: nextUnusedName("UNTITLED BEND"), stock: false,
            materialThickness: NaN, desiredBendAngle: NaN, angleCompensation: 0,
            angleCompensationReversed: false, punchToMaterialClearance: 0.05,
            additionalRetractAfterBend: 0, bendWidth: 0.1,
            backGaugeRefEdgeStop: "G54", backGaugeRefEdgeStopEnabled: false,
            backGaugeXPosition: 0, backGaugeRPosition: appState ? Number(appState.defaultBackGaugeRPositionInch || 0) : 0,
            backGaugeJogSpeed: 100, overrideFinalBendPositionEnabled: false,
            overriddenFinalBendPosition: 0, notes: "", xAxisNotes: "", rAxisNotes: "",
            punchId: "", dieId: "", materialId: "",
            dateCreated: new Date().toISOString()
        }
    }
    function nextUnusedName(base) {
        var taken = ({})
        for (var index = 0; index < workingBends.length; index++)
            taken[String(workingBends[index].name || "")] = true
        if (!taken[base]) return base
        for (var suffix = 1; suffix < 1000; suffix++) {
            var candidate = base + " " + suffix
            if (!taken[candidate]) return candidate
        }
        return base + " " + Date.now()
    }
    function createNew() {
        editSnapshot = ({})
        draftBend = defaultBend()
        creatingNew = true
        editing = true
        editingName = true
    }
    function duplicateCurrent() {
        if (!hasBends || creatingNew)
            return
        editSnapshot = cloneValue(currentBend)
        draftBend = cloneValue(currentBend)
        draftBend.id = "bend-" + String(Date.now())
        draftBend.name = nextUnusedName(String(currentBend.name || "UNTITLED BEND") + " COPY")
        draftBend.stock = false
        draftBend.dateCreated = new Date().toISOString()
        creatingNew = true
        editing = true
        editingName = true
    }
    function cancelEditing() {
        draftBend = cloneValue(editSnapshot)
        editing = false
        creatingNew = false
        editingName = false
        syncSelectedToolIndexes()
        if (appState)
            appState.log("CREATE BEND", "Edit cancelled; original values restored")
    }
    function resetEditing() {
        if (!editing)
            return
        var preservedName = currentBend.name
        var defaults = defaultBend()
        defaults.id = currentBend.id || defaults.id
        defaults.name = preservedName
        defaults.dateCreated = currentBend.dateCreated || defaults.dateCreated
        draftBend = defaults
        syncSelectedToolIndexes()
        if (appState)
            appState.log("CREATE BEND", "Values reset to defaults")
    }
    function saveEditing() {
        if (!canSave) {
            if (appState)
                appState.showAlarm("SAVE BEND", !isNameUnique(currentBend.name)
                    ? "A bend move with this name already exists. Enter a unique name."
                    : "Complete all required tooling and numeric fields before saving.")
            return false
        }
        if (!appState)
            return false
        var savedBend = appState.bendFromCreateDraft(
            bendTitle(), currentBend, currentPunch, currentDie, currentMaterial,
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
        for (var index = 0; index < workingBends.length; index++) {
            if (String(workingBends[index].id || "") === savedId) {
                selectedBendIndex = index
                break
            }
        }
        return true
    }
    function requestDelete() {
        if (!hasBends || creatingNew || !appState)
            return
        var name = bendTitle()
        appState.showConfirmation("DELETE BEND MOVE",
            "Delete “" + name + "” from " + appState.activeProgram + "?",
            function() {
                if (!appState.removeProgramBend(selectedBendIndex)) {
                    appState.showAlarm("DELETE BEND MOVE",
                        "Could not write programs.json safely. The selected program was not confirmed as saved.")
                    return
                }
                editing = false
                editingName = false
                root.syncWorkingBends()
            }, null)
    }
    function setBendValue(key, value) {
        ensureEditing()
        if (!editing)
            return
        draftBend[key] = value
        draftBend = Object.assign({}, draftBend)
    }
    function setNumericValue(key, value, minimum, maximum) {
        var numeric = Number(value)
        if (!isFinite(numeric))
            return
        if (minimum !== undefined) numeric = Math.max(minimum, numeric)
        if (maximum !== undefined) numeric = Math.min(maximum, numeric)
        setBendValue(key, numeric)
        if (creatingNew && key === "materialThickness")
            setBendValue("punchToMaterialClearance", resolvePunchClearance(currentMaterial, numeric))
    }
    function syncSelectedToolIndexes() {
        selectedPunchIndex = indexById(dataStore.punches, currentBend.punchId)
        selectedDieIndex = indexById(dataStore.dies, currentBend.dieId)
        selectedMaterialIndex = indexById(dataStore.materials, currentBend.materialId)
    }
    function selectTool(kind, index) {
        ensureEditing()
        if (!editing || overrideEnabled)
            return
        if (kind === "Punch") {
            selectedPunchIndex = index
            setBendValue("punchId", currentPunch.id || "")
        } else if (kind === "Die") {
            selectedDieIndex = index
            setBendValue("dieId", currentDie.id || "")
        } else {
            selectedMaterialIndex = index
            setBendValue("materialId", currentMaterial.id || "")
            if (creatingNew)
                setBendValue("punchToMaterialClearance", resolvePunchClearance(currentMaterial, Number(currentBend.materialThickness)))
        }
        logSelection(kind, kind === "Punch" ? currentPunch : (kind === "Die" ? currentDie : currentMaterial))
    }
    function bendIsValid(bend) {
        var required = [bend.materialThickness, bend.desiredBendAngle, bend.angleCompensation,
            bend.punchToMaterialClearance, bend.additionalRetractAfterBend, bend.bendWidth,
            bend.overriddenFinalBendPosition]
        for (var index = 0; index < required.length; index++)
            if (!isFinite(Number(required[index]))) return false
        return String(bend.name || "").trim().length > 0
            && String(bend.punchId || "").length > 0
            && String(bend.dieId || "").length > 0
            && String(bend.materialId || "").length > 0
    }
    function canonicalThicknessProfiles() {
        return [
            { label: "1/2 in", inch: 0.5 }, { label: "3/8 in", inch: 0.375 },
            { label: "5/16 in", inch: 0.3125 }, { label: "1/4 in", inch: 0.25 },
            { label: "3/16 in", inch: 0.1875 }, { label: "5/32 in", inch: 0.1563 },
            { label: "1/8 in", inch: 0.125 }, { label: "3/32 in", inch: 0.0938 },
            { label: "1/16 in", inch: 0.0625 }, { label: "7 ga", inch: 0.1793 },
            { label: "8 ga", inch: 0.1644 }, { label: "10 ga", inch: 0.1345 },
            { label: "11 ga", inch: 0.1196 }, { label: "12 ga", inch: 0.1046 },
            { label: "13 ga", inch: 0.0897 }, { label: "14 ga", inch: 0.0747 },
            { label: "16 ga", inch: 0.0598 }, { label: "18 ga", inch: 0.0478 },
            { label: "20 ga", inch: 0.0359 }, { label: "22 ga", inch: 0.0299 },
            { label: "24 ga", inch: 0.0239 }
        ]
    }
    function resolvePunchClearance(material, thickness) {
        var numericThickness = Number(thickness)
        if (!isFinite(numericThickness) || numericThickness <= 0)
            return 0.05
        var profiles = canonicalThicknessProfiles()
        var nearest = profiles[0]
        for (var profileIndex = 1; profileIndex < profiles.length; profileIndex++)
            if (Math.abs(profiles[profileIndex].inch - numericThickness) < Math.abs(nearest.inch - numericThickness))
                nearest = profiles[profileIndex]
        var preferences = material && material.thicknessToolingPreferences ? material.thicknessToolingPreferences : []
        for (var preferenceIndex = 0; preferenceIndex < preferences.length; preferenceIndex++) {
            var preference = preferences[preferenceIndex] || {}
            if (String(preference.thicknessLabel || "").trim().toLowerCase() !== nearest.label.toLowerCase())
                continue
            var percent = Number(preference.punchToMaterialClearancePercent)
            if (preference.punchToMaterialClearancePercent !== null && isFinite(percent))
                return numericThickness * percent / 100
            var inches = Number(preference.punchToMaterialClearanceInch)
            if (preference.punchToMaterialClearanceInch !== null && isFinite(inches))
                return inches
        }
        return numericThickness * 0.85
    }
    function isNameUnique(name) {
        var clean = String(name || "").trim()
        for (var index = 0; index < workingBends.length; index++) {
            var candidate = workingBends[index]
            if (String(candidate.id || "") !== String(currentBend.id || "")
                    && String(candidate.name || "") === clean)
                return false
        }
        return clean.length > 0
    }
    function calculateBend() {
        if (!currentBend || !currentPunch || !currentDie || !currentMaterial)
            return ({})
        return BendCalculator.computeBend({
            bend: currentBend, punch: currentPunch, die: currentDie, material: currentMaterial,
            settings: { materialClampRatePercentage: appState ? appState.materialClampRatePercentage : 5 },
            machine: {
                ramToTableOpening: appState ? appState.authoritativeRamToTableOpening() : NaN,
                validRangeInchMin: -4, validRangeInchMax: -0.05, jogStepPaddingInch: 0.01
            },
            limits: { tonnageWarningThreshold: 12.5, tonnageErrorThreshold: 25,
                punchToMaterialClearanceWarningThreshold: 0.3 }
        })
    }
    function warningItems() {
        var result = []
        if (calculation.punchToMaterialClearanceWarning)
            result.push({ text: "UNSAFE CLEARANCE PLANE", base: amber })
        if (overrideEnabled)
            result.push({ text: "OVERRIDDEN BEND DEPTH", base: amber })
        if (calculation.tonnageError)
            result.push({ text: "TONNAGE RATING EXCEEDED", base: red })
        else if (calculation.tonnageWarning)
            result.push({ text: "CENTER WORK PIECE", base: amber })
        if (calculation.finalBendPositionOutLimit)
            result.push({ text: "BEND DEPTH NOT IN RANGE", base: red })
        if (calculation.upperLimitExceededError && calculation.lowerLimitExceededError)
            result.push({ text: "UPPER AND LOWER TRAVEL LIMIT EXCEEDED", base: red })
        else if (calculation.upperLimitExceededError)
            result.push({ text: "UPPER TRAVEL LIMIT EXCEEDED", base: red })
        else if (calculation.lowerLimitExceededError)
            result.push({ text: "LOWER TRAVEL LIMIT EXCEEDED", base: red })
        return result
    }
    function showInfo(title, body) {
        if (appState)
            appState.showPopup(title, body, 1, "info", "CLOSE")
    }
    function showVerticalDiagram() {
        if (!appState)
            return
        appState.showImagePopup("VERTICAL POSITIONS DIAGRAM",
            "START SAFETY CLEARANCE  " + numberText(calculation.startSafetyClearance, 3, "—") + " in\n\n"
            + "BEND CLAMP POSITION  " + numberText(calculation.clampPosition, 3, "—") + " in\n\n"
            + "FINAL BEND POSITION  " + numberText(calculation.inUseFinalBendPosition, 3, "—") + " in\n\n"
            + "RETRACT AFTER BEND  " + numberText(calculation.retractAfterBend, 3, "—") + " in\n\n"
            + "TOTAL BEND STROKE  " + numberText(overrideEnabled ? calculation.overriddenTotalBendStroke : calculation.totalBendStroke, 3, "—") + " in",
            "images/info/create_bend/vertical_diagram.png")
    }

    function names(items) { var result = []; for (var i = 0; i < items.length; i++) result.push(items[i].name || ""); return result }
    function pdmNames(items, comboClass) { var result = []; for (var i = 0; i < items.length; i++) result.push(formatPdmName(items[i] ? items[i].name : "", comboClass)); return result }
    function formatPdmName(name, comboClass) {
        var value = name || ""
        var bracketStart = value.indexOf("[")
        var bracket = bracketStart >= 0 ? value.substring(bracketStart).trim() : ""
        var title = bracketStart >= 0 ? value.substring(0, bracketStart).trim() : value.trim()
        if (comboClass === "combo-punch")
            title = title.replace(/\s+Punch\b/gi, "").trim()
        else if (comboClass === "combo-die")
            title = title.replace(/\s+Die\b/gi, "").trim()
        if (bracket.length === 0) {
            var parenStart = title.indexOf("(")
            if (parenStart > 0) {
                bracket = title.substring(parenStart).trim()
                title = title.substring(0, parenStart).trim()
            }
        }
        return bracket.length > 0 ? title + "\n" + bracket : title
    }
    function indexById(items, id) { if (!id) return -1; for (var i = 0; i < items.length; i++) if (items[i].id === id) return i; return -1 }
    function backGaugeReferenceStopNames() {
        var result = []
        for (var i = 0; i < backGaugeReferenceStopIds.length; i++) {
            var id = backGaugeReferenceStopIds[i]
            result.push(appState ? appState.backGaugeCoordinateDisplayName(id) : id)
        }
        return result
    }
    function numberText(value, digits, fallback) { if (value === undefined || value === null || isNaN(Number(value))) return fallback || "0"; return Number(value).toFixed(digits) }
    function derivedClearance() { return currentBend.punchToMaterialClearance }
    function calcFinalBendPosition() { return Number(calculation.inUseFinalBendPosition) }
    function calcTonnage() { return Number(calculation.bendTonnage) }
    function pdmPopupMaxHeight(combo) { return Math.max(120 * sy, (585.6 - 7.2 - (49.6 + 22.4 + combo.height / sy)) * sy) }
    readonly property string iconRoot: Qt.resolvedUrl("../../icons/")
    function iconPath(name) {
        if (name === "pen-white") return iconRoot + "fa-pen-white.svg"
        if (name === "pen") return iconRoot + "fa-pen.svg"
        if (name === "trash-white") return iconRoot + "fa-trash.svg"
        if (name === "trash") return iconRoot + "fa-trash-black.svg"
        if (name === "info-circle-white") return iconRoot + "fa-info-circle-white.svg"
        if (name === "info-circle") return iconRoot + "fa-info-circle.svg"
        if (name === "caret-down-white") return iconRoot + "fa-caret-down-white.svg"
        if (name === "caret-down") return iconRoot + "fa-caret-down.svg"
        if (name === "plus-white") return iconRoot + "fa-plus.svg"
        if (name === "plus") return iconRoot + "fa-plus.svg"
        if (name === "times-white") return iconRoot + "fa-times.svg"
        if (name === "times") return iconRoot + "fa-times.svg"
        if (name === "save-white") return iconRoot + "fa-save.svg"
        if (name === "save") return iconRoot + "fa-save.svg"
        if (name === "undo-white") return iconRoot + "fa-undo.svg"
        if (name === "undo") return iconRoot + "fa-undo.svg"
        if (name === "duplicate") return iconRoot + "fa-file-black.svg"
        if (name === "duplicate-white") return iconRoot + "fa-file-white.svg"
        if (name === "list-plus-white") return iconRoot + "fa-list-ol.svg"
        if (name === "list-plus") return iconRoot + "fa-list-ol.svg"
        if (name === "exclamation-triangle") return iconRoot + "fa-exclamation-triangle.svg"
        return iconRoot + "fa-" + name + ".svg"
    }
    function bendTitle() { return currentBend.name || "Bend" }
    function logSelection(kind, item) { if (appState) appState.log("CREATE BEND", kind + " selected: " + ((item && item.name) ? item.name : "Unknown")) }
    function openTextKeyboard(field, title, commitHandler) {
        if (appState)
            appState.openOnScreenKeyboard(field, false, title, commitHandler)
    }
    function openNumericKeyboard(field, title, commitHandler) {
        if (appState)
            appState.openOnScreenKeyboard(field, true, title, commitHandler)
    }
    function beginNameEdit(field) {
        ensureEditing()
        if (!editing)
            return
        editingName = true
        if (appState)
            appState.log("CREATE BEND", "Edit name " + bendTitle())
        var editor = field || bendNameEditor
        Qt.callLater(function() { editor.openKeyboard() })
    }

    // BendCNC light background canvas
    Rectangle {
        anchors.fill: parent
        color: root.canvasBg
    }

    // ==========================================
    // LEFT PANEL: Parameter Editor & Sequence Hub
    // ==========================================
    Item {
        objectName: "left body"
        x: 0
        y: 0
        width: 610 * root.sx
        height: parent.height

        Item {
            objectName: "bendEditor body"
            x: 0
            y: 0
            width: parent.width
            height: 585.6 * root.sy

            // 1. SEQUENCE HEADER CARD
            Rectangle {
                objectName: "item-selection"
                x: 6 * root.sx
                y: 6 * root.sy
                width: parent.width - 12 * root.sx
                height: 42 * root.sy
                radius: 7
                color: root.cardBg
                border.color: root.cardBorderColor
                border.width: 1

                // Section Title (Clean label with vertical separator)
                Item {
                    id: bendMoveHeaderTitle
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.sx
                    anchors.verticalCenter: parent.verticalCenter
                    width: 90 * root.sx
                    height: parent.height

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("BEND MOVE")
                        color: root.textPrimary
                        font.bold: true
                        font.pixelSize: 11
                        font.letterSpacing: 0.5
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1.5 * root.sx
                        height: 18 * root.sy
                        color: "#94A3B8"
                    }
                }

                // Edit Pen Button (Cobalt Blue with White Icon & Generous Margin)
                IconButton {
                    id: topActionBtn
                    visible: !editingName
                    enabled: hasBends
                    anchors.right: parent.right
                    anchors.rightMargin: 16 * root.sx
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36 * root.sx
                    height: 32 * root.sy
                    glyph: "pen"
                    base: root.blue
                    iconColor: "white"
                    borderColor: "#1E6E9E"
                    onClicked: root.beginEdit(true)
                }

                // Delete Trash Button (Shown during Name Edit)
                IconButton {
                    id: topDeleteBtn
                    visible: editingName
                    enabled: !creatingNew
                    anchors.right: parent.right
                    anchors.rightMargin: 16 * root.sx
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36 * root.sx
                    height: 32 * root.sy
                    glyph: "trash"
                    base: root.red
                    iconColor: "white"
                    borderColor: "#8E1B0E"
                    onClicked: root.requestDelete()
                }

                // Sequence Dropdown (Centered between title and edit button)
                EntityCombo {
                    id: bendCombo
                    visible: !editingName
                    enabled: !editing
                    anchors.left: bendMoveHeaderTitle.right
                    anchors.leftMargin: 12 * root.sx
                    anchors.right: topActionBtn.left
                    anchors.rightMargin: 12 * root.sx
                    anchors.verticalCenter: parent.verticalCenter
                    height: 32 * root.sy
                    objectName: "combo-box-base combo-box white-combo-box"
                    model: root.names(workingBends)
                    currentIndex: root.selectedBendIndex
                    dark: false
                    onActivated: function(index) {
                        root.selectedBendIndex = index
                        root.syncSelectedToolIndexes()
                        root.logSelection("Bend", currentBend)
                    }
                }

                // Inline Name Editor
                AppTextField {
                    id: bendNameEditor
                    objectName: "create-bend-name-field"
                    visible: editingName
                    anchors.left: bendMoveHeaderTitle.right
                    anchors.leftMargin: 12 * root.sx
                    anchors.right: topDeleteBtn.left
                    anchors.rightMargin: 12 * root.sx
                    anchors.verticalCenter: parent.verticalCenter
                    height: 32 * root.sy
                    text: currentBend.name || ""
                    alignLeft: true
                    keyboardTitle: qsTr("BEND NAME")
                    onKeyboardCommitted: function(value) { root.setBendValue("name", String(value).trim()) }
                }
            }

            // 2. TOOLING SELECTION STRIP (Punch, Die, Material)
            Item {
                objectName: "pdm"
                visible: hasBends
                x: 6 * root.sx
                y: 54 * root.sy
                width: parent.width - 12 * root.sx
                height: 64 * root.sy

                Row {
                    anchors.fill: parent
                    spacing: 6 * root.sx

                    PdmBlock {
                        enabled: !overrideEnabled
                        width: (parent.width - 12 * root.sx) / 3
                        height: parent.height
                        label: "PUNCH"
                        comboClass: "combo-punch"
                        accent: root.red
                        items: dataStore.punches
                        model: root.pdmNames(dataStore.punches, "combo-punch")
                        currentIndex: root.selectedPunchIndex
                        onActivated: function(index) { root.selectTool("Punch", index) }
                    }
                    PdmBlock {
                        enabled: !overrideEnabled
                        width: (parent.width - 12 * root.sx) / 3
                        height: parent.height
                        label: "DIE"
                        comboClass: "combo-die"
                        accent: root.blue
                        items: dataStore.dies
                        model: root.pdmNames(dataStore.dies, "combo-die")
                        currentIndex: root.selectedDieIndex
                        onActivated: function(index) { root.selectTool("Die", index) }
                    }
                    PdmBlock {
                        enabled: !overrideEnabled
                        width: (parent.width - 12 * root.sx) / 3
                        height: parent.height
                        label: "MATERIAL TYPE"
                        comboClass: "combo-material"
                        accent: root.green
                        items: dataStore.materials
                        model: root.pdmNames(dataStore.materials, "combo-material")
                        currentIndex: root.selectedMaterialIndex
                        onActivated: function(index) { root.selectTool("Material", index) }
                    }
                }
            }

            // 3. PARAMETERS CARD (Angles, Clearances, Material, Controls)
            Rectangle {
                objectName: "fields"
                visible: hasBends
                x: 6 * root.sx
                y: 124 * root.sy
                width: parent.width - 12 * root.sx
                height: backGaugeEnabled ? 284 * root.sy : 452 * root.sy
                radius: 7
                color: root.cardBg
                border.color: root.cardBorderColor
                border.width: 1

                // Card Section Header
                CardHeader {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    title: "BEND GEOMETRY & MATERIAL SPECIFICATIONS"
                    accentColor: root.blue
                }

                // --- LEFT COLUMN: Angles & Ram Clearance ---
                Rectangle {
                    x: 12 * root.sx
                    y: 32 * root.sy
                    width: 278 * root.sx
                    height: 18 * root.sy
                    color: "#D1D5DB"
                    radius: 3
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("ANGLE & RAM CLEARANCE")
                        font.bold: true
                        font.pixelSize: 9
                        color: "#334155"
                        font.letterSpacing: 0.5
                    }
                }

                // Row 1: Desired Bend Angle (Featured Card)
                HighlightAngleLabel {
                    x: 12 * root.sx
                    y: 56 * root.sy
                    width: 138 * root.sx
                    height: 36 * root.sy
                }
                InfoButton {
                    x: 152 * root.sx
                    y: 56 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("DESIRED BEND ANGLE", "The included angle requested after springback and angle compensation are applied.")
                }
                MeasureField {
                    id: desiredAngleEditor
                    objectName: "create-bend-angle-field highlighted-text-field"
                    x: 174 * root.sx
                    y: 56 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    value: numberText(currentBend.desiredBendAngle, 1, "—")
                    unit: "deg"
                    highlighted: true
                    editable: !overrideEnabled && hasBends
                    keyboardTitle: qsTr("DESIRED BEND ANGLE")
                    onKeyboardCommitted: function(value) { root.setNumericValue("desiredBendAngle", value, 15, 170) }
                }

                // Row 2: Angle Compensation
                FieldLabel {
                    x: 12 * root.sx
                    y: 98 * root.sy
                    width: 138 * root.sx
                    height: 36 * root.sy
                    text: "ANGLE COMPENSATION"
                }
                InfoButton {
                    x: 152 * root.sx
                    y: 98 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("ANGLE COMPENSATION", "OVERBENT adds compensation to bend farther. UNDERBENT subtracts compensation to bend less.")
                }
                ToggleButtonLike {
                    objectName: "create-bend-compensation-direction"
                    enabled: !overrideEnabled && hasBends
                    x: 174 * root.sx
                    y: 98 * root.sy
                    width: 52 * root.sx
                    height: 36 * root.sy
                    text: currentBend.angleCompensationReversed ? "UNDER" : "OVER"
                    base: currentBend.angleCompensationReversed ? root.blue : root.amber
                    onClicked: {
                        root.setBendValue("angleCompensationReversed", !currentBend.angleCompensationReversed)
                        if (appState) appState.log("CREATE BEND", "Angle compensation direction " + (currentBend.angleCompensationReversed ? "UNDERBENT" : "OVERBENT"))
                    }
                }
                MeasureField {
                    id: angleCompensationEditor
                    objectName: "create-bend-compensation-field"
                    x: 228 * root.sx
                    y: 98 * root.sy
                    width: 60 * root.sx
                    height: 36 * root.sy
                    value: numberText(currentBend.angleCompensation, 1, "0.0")
                    unit: "deg"
                    editable: !overrideEnabled && hasBends
                    keyboardTitle: qsTr("ANGLE COMPENSATION")
                    onKeyboardCommitted: function(value) { root.setNumericValue("angleCompensation", value, 0, 90) }
                }

                // Row 3: Punch to Material Clearance
                FieldLabel {
                    x: 12 * root.sx
                    y: 140 * root.sy
                    width: 138 * root.sx
                    height: 36 * root.sy
                    text: "PUNCH TO MATERIAL\nCLEARANCE"
                }
                InfoButton {
                    x: 152 * root.sx
                    y: 140 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("PUNCH-TO-MATERIAL CLEARANCE", "Clearance between the punch and material at the start safety position. Values over 0.300 in trigger a safety warning.")
                }
                MeasureField {
                    id: clearanceEditor
                    objectName: "create-bend-clearance-field"
                    x: 174 * root.sx
                    y: 140 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    value: numberText(derivedClearance(), 3, "0.050")
                    unit: "in"
                    editable: hasBends
                    keyboardTitle: qsTr("PUNCH TO MATERIAL CLEARANCE")
                    onKeyboardCommitted: function(value) { root.setNumericValue("punchToMaterialClearance", value, 0.01, 5) }
                }

                // Row 4: Additional Retract After Bend
                FieldLabel {
                    x: 12 * root.sx
                    y: 182 * root.sy
                    width: 138 * root.sx
                    height: 36 * root.sy
                    text: "ADDITIONAL RETRACT\nAFTER BEND"
                }
                InfoButton {
                    x: 152 * root.sx
                    y: 182 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("ADDITIONAL RETRACT AFTER BEND", "Extra upward ram travel after completing the bend, limited by machine travel.")
                }
                MeasureField {
                    id: additionalRetractEditor
                    objectName: "create-bend-retract-field"
                    x: 174 * root.sx
                    y: 182 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    value: numberText(currentBend.additionalRetractAfterBend, 3, "0.000")
                    unit: "in"
                    editable: hasBends
                    keyboardTitle: qsTr("ADDITIONAL RETRACT")
                    onKeyboardCommitted: function(value) { root.setNumericValue("additionalRetractAfterBend", value, 0, 3.75) }
                }

                // Vertical Divider
                Rectangle {
                    x: 298 * root.sx
                    y: 34 * root.sy
                    width: 1 * root.sx
                    height: 186 * root.sy
                    color: root.cardDividerColor
                }

                // --- RIGHT COLUMN: Material Dimensions & Automation ---
                Rectangle {
                    x: 304 * root.sx
                    y: 32 * root.sy
                    width: 280 * root.sx
                    height: 18 * root.sy
                    color: "#D1D5DB"
                    radius: 3
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("MATERIAL DIMENSIONS & AUTOMATION")
                        font.bold: true
                        font.pixelSize: 9
                        color: "#334155"
                        font.letterSpacing: 0.5
                    }
                }

                // Row 1: Material Thickness
                FieldLabel {
                    x: 304 * root.sx
                    y: 56 * root.sy
                    width: 140 * root.sx
                    height: 36 * root.sy
                    text: "MATERIAL THICKNESS"
                    singleLine: true
                }
                InfoButton {
                    x: 446 * root.sx
                    y: 56 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("MATERIAL THICKNESS", "Workpiece gauge thickness.")
                }
                MeasureField {
                    id: materialThicknessEditor
                    objectName: "create-bend-thickness-field"
                    x: 468 * root.sx
                    y: 56 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    value: numberText(currentBend.materialThickness, 3, "—")
                    unit: "in"
                    editable: !overrideEnabled && hasBends
                    keyboardTitle: qsTr("MATERIAL THICKNESS")
                    onKeyboardCommitted: function(value) { root.setNumericValue("materialThickness", value, 0.01, 2.5) }
                }

                // Row 2: Bend Width
                FieldLabel {
                    x: 304 * root.sx
                    y: 98 * root.sy
                    width: 140 * root.sx
                    height: 36 * root.sy
                    text: "BEND WIDTH"
                    singleLine: true
                }
                InfoButton {
                    x: 446 * root.sx
                    y: 98 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("BEND WIDTH", "Length of material being bent. It is used to calculate required tonnage.")
                }
                MeasureField {
                    id: bendWidthEditor
                    objectName: "create-bend-width-field"
                    x: 468 * root.sx
                    y: 98 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    value: numberText(currentBend.bendWidth, 1, "0.1")
                    unit: "in"
                    editable: hasBends
                    keyboardTitle: qsTr("BEND WIDTH")
                    onKeyboardCommitted: function(value) { root.setNumericValue("bendWidth", value, 0.1, 33.3) }
                }

                // Row 3: Add Back Gauge Move Toggle
                FieldLabel {
                    x: 304 * root.sx
                    y: 140 * root.sy
                    width: 140 * root.sx
                    height: 36 * root.sy
                    text: "ADD BACK GAUGE\nMOVE"
                }
                InfoButton {
                    x: 446 * root.sx
                    y: 140 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("ADD BACK GAUGE MOVE", "Enables programmable X and R back gauge stop positioning for this bend.")
                }
                ToggleButtonLike {
                    objectName: "create-bend-backgauge-toggle"
                    enabled: hasBends
                    x: 468 * root.sx
                    y: 140 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    text: backGaugeEnabled ? "ENABLED" : "DISABLED"
                    base: backGaugeEnabled ? root.green : "#64748B"
                    accentPill: true
                    onClicked: {
                        root.setBendValue("backGaugeRefEdgeStopEnabled", !backGaugeEnabled)
                        if (appState) appState.log("CREATE BEND", "Back gauge move " + (currentBend.backGaugeRefEdgeStopEnabled ? "enabled" : "disabled"))
                    }
                }

                // Row 4: Override Final Bend Pos Toggle
                FieldLabel {
                    x: 304 * root.sx
                    y: 182 * root.sy
                    width: 140 * root.sx
                    height: 36 * root.sy
                    text: "OVERRIDE FINAL BEND\nPOSITION"
                }
                InfoButton {
                    x: 446 * root.sx
                    y: 182 * root.sy
                    width: 20 * root.sx
                    height: 36 * root.sy
                    onClicked: root.showInfo("OVERRIDE FINAL BEND POSITION", "Replaces the calculated final ram position with an operator-entered value. Tooling, angle, and thickness remain locked while enabled.")
                }
                ToggleButtonLike {
                    objectName: "create-bend-override-toggle"
                    enabled: hasBends
                    x: 468 * root.sx
                    y: 182 * root.sy
                    width: 114 * root.sx
                    height: 36 * root.sy
                    text: overrideEnabled ? "OVERRIDE" : "DISABLED"
                    base: overrideEnabled ? root.red : "#64748B"
                    accentPill: true
                    onClicked: {
                        var next = !overrideEnabled
                        if (next) {
                            var calculated = Number(calculation.calculatedFinalBendPosition)
                            if (!isFinite(calculated)) calculated = Number(currentBend.finalPosition)
                            if (!isFinite(calculated)) {
                                if (appState) appState.showAlarm("FINAL BEND OVERRIDE", "A calculated or stored final bend position is required before enabling the override.")
                                return
                            }
                            root.setBendValue("overriddenFinalBendPosition", calculated)
                        }
                        root.setBendValue("overrideFinalBendPositionEnabled", next)
                        if (appState) appState.log("CREATE BEND", "Final bend override " + (next ? "enabled" : "disabled"))
                    }
                }

                // Row 5: Active Warnings or Nominal Status Container
                WarningPanel {
                    visible: root.activeWarnings.length > 0
                    x: 304 * root.sx
                    y: 222 * root.sy
                    width: 278 * root.sx
                    height: parent.height - 228 * root.sy
                }

                Rectangle {
                    visible: root.activeWarnings.length === 0 && hasBends
                    x: 12 * root.sx
                    y: 228 * root.sy
                    width: parent.width - 24 * root.sx
                    height: 44 * root.sy
                    radius: 6
                    color: "#F8FAFC"
                    border.color: "#CBD5E1"
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8 * root.sx
                        spacing: 10 * root.sx

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24 * root.sx
                            height: 24 * root.sy
                            radius: 12
                            color: "#DCFCE7"
                            border.color: "#86EFAC"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "#15803D"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: qsTr("GEOMETRY & TOOLING PARAMETERS VERIFIED")
                                color: "#166534"
                                font.bold: true
                                font.pixelSize: 10
                                font.letterSpacing: 0.5
                            }
                            Text {
                                text: qsTr("Calculated bend tonnage and ram positions are within safe travel limits.")
                                color: "#475569"
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }

            // 4. BACK GAUGE POSITIONING CARD (visible when back gauge is enabled)
            Rectangle {
                objectName: "back-gauge"
                visible: hasBends && backGaugeEnabled
                x: 6 * root.sx
                y: 414 * root.sy
                width: parent.width - 12 * root.sx
                height: 162 * root.sy
                radius: 7
                color: root.cardBg
                border.color: "#86EFAC"
                border.width: 1

                CardHeader {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    title: "BACK GAUGE POSITIONING (X & R AXIS)"
                    accentColor: root.green
                }

                FieldLabel {
                    x: 14 * root.sx
                    y: 36 * root.sy
                    width: 260 * root.sx
                    height: 16 * root.sy
                    text: "REFERENCE EDGE STOP COORDINATE SYSTEM"
                    singleLine: true
                }
                EntityCombo {
                    objectName: "reference-edge-stop-combo"
                    x: 14 * root.sx
                    y: 56 * root.sy
                    width: parent.width - 28 * root.sx
                    height: 32 * root.sy
                    model: root.backGaugeReferenceStopNames()
                    currentIndex: Math.max(0, root.backGaugeReferenceStopIds.indexOf(currentBend.backGaugeRefEdgeStop || "G54"))
                    dark: false
                    onActivated: function(index) {
                        if (index < 0 || index >= root.backGaugeReferenceStopIds.length)
                            return
                        root.setBendValue("backGaugeRefEdgeStop", root.backGaugeReferenceStopIds[index])
                        root.logSelection("Reference edge stop", {
                            name: root.backGaugeReferenceStopNames()[index]
                        })
                    }
                }

                Row {
                    x: 14 * root.sx
                    y: 96 * root.sy
                    width: parent.width - 28 * root.sx
                    height: 56 * root.sy
                    spacing: 12 * root.sx

                    Column {
                        width: (parent.width - 24 * root.sx) / 3
                        height: parent.height
                        spacing: 4 * root.sy
                        FieldLabel { width: parent.width; height: 16 * root.sy; text: "X POSITION"; singleLine: true }
                        MeasureField {
                            id: backGaugeXEditor
                            objectName: "create-bend-backgauge-x-field"
                            width: parent.width
                            height: 32 * root.sy
                            value: numberText(currentBend.backGaugeXPosition, 3, "0.000")
                            unit: "in"
                            editable: backGaugeEnabled
                            keyboardTitle: qsTr("BACK GAUGE X")
                            onKeyboardCommitted: function(value) { root.setNumericValue("backGaugeXPosition", value) }
                        }
                    }

                    Column {
                        width: (parent.width - 24 * root.sx) / 3
                        height: parent.height
                        spacing: 4 * root.sy
                        FieldLabel { width: parent.width; height: 16 * root.sy; text: "R POSITION"; singleLine: true }
                        MeasureField {
                            id: backGaugeREditor
                            objectName: "create-bend-backgauge-r-field"
                            width: parent.width
                            height: 32 * root.sy
                            value: numberText(currentBend.backGaugeRPosition, 3, "0.000")
                            unit: "in"
                            editable: backGaugeEnabled
                            keyboardTitle: qsTr("BACK GAUGE R")
                            onKeyboardCommitted: function(value) { root.setNumericValue("backGaugeRPosition", value) }
                        }
                    }

                    Column {
                        width: (parent.width - 24 * root.sx) / 3
                        height: parent.height
                        spacing: 4 * root.sy
                        FieldLabel { width: parent.width; height: 16 * root.sy; text: "JOG SPEED"; singleLine: true }
                        MeasureField {
                            id: backGaugeSpeedEditor
                            objectName: "create-bend-backgauge-speed-field"
                            width: parent.width
                            height: 32 * root.sy
                            value: numberText(currentBend.backGaugeJogSpeed, 0, "100")
                            unit: "IPM"
                            editable: backGaugeEnabled
                            keyboardTitle: qsTr("BACK GAUGE JOG SPEED")
                            onKeyboardCommitted: function(value) { root.setNumericValue("backGaugeJogSpeed", value, 1, 500) }
                        }
                    }
                }
            }

            // Empty state placeholder
            Rectangle {
                objectName: "create-bend-empty-panel"
                visible: !hasBends
                x: 6 * root.sx
                y: 54 * root.sy
                width: parent.width - 12 * root.sx
                height: 520 * root.sy
                radius: 7
                color: root.cardBg
                border.color: root.cardBorderColor
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: qsTr("NO BENDS AVAILABLE")
                    color: root.textMuted
                    font.bold: true
                    font.pixelSize: 18
                }
            }
        }

        // 5. FOOTER ACTION HUB
        Item {
            objectName: "footer"
            x: 0
            y: 585.6 * root.sy
            width: parent.width
            height: 52.8 * root.sy

            Row {
                x: 6 * root.sx
                y: 6 * root.sy
                width: parent.width - 12 * root.sx
                height: 40 * root.sy
                spacing: 6 * root.sx

                FooterButton {
                    objectName: "create-bend-new-cancel-button"
                    width: 114 * root.sx
                    height: parent.height
                    label: editing ? "CANCEL" : "NEW BEND\nMOVE"
                    footerGlyph: editing ? "times" : "plus"
                    base: editing ? root.red : root.blue
                    allRounded: true
                    onClicked: editing ? root.cancelEditing() : root.createNew()
                }
                FooterButton {
                    objectName: "create-bend-save-button"
                    enabled: canSave
                    width: 86 * root.sx
                    height: parent.height
                    label: "SAVE"
                    footerGlyph: "save"
                    base: root.green
                    allRounded: true
                    onClicked: root.saveEditing()
                }
                FooterButton {
                    objectName: "create-bend-duplicate-button"
                    enabled: hasBends && !creatingNew
                    width: 104 * root.sx
                    height: parent.height
                    label: "DUPLICATE"
                    footerGlyph: "duplicate"
                    base: root.orange
                    textColor: "white"
                    allRounded: true
                    onClicked: root.duplicateCurrent()
                }
                FooterButton {
                    objectName: "create-bend-reset-button"
                    enabled: editing && hasBends
                    width: 92 * root.sx
                    height: parent.height
                    label: "RESET"
                    footerGlyph: "undo"
                    base: "#64748B"
                    allRounded: true
                    onClicked: root.resetEditing()
                }
                FooterButton {
                    objectName: "create-bend-load-button"
                    enabled: hasBends && !editing
                    width: parent.width - 420 * root.sx
                    height: parent.height
                    label: "LOAD BEND\nINTO PROGRAM"
                    footerGlyph: "list-plus"
                    base: root.charcoal
                    allRounded: true
                    onClicked: if (appState) appState.createBendAction("load", root.bendTitle(), root.currentBend, root.currentPunch, root.currentDie, root.currentMaterial, root.calcFinalBendPosition(), root.calcTonnage())
                }
            }
        }
    }

    // ==========================================
    // RIGHT PANEL: Live Calculations & Bend Notes
    // ==========================================
    Item {
        objectName: "right"
        x: 612 * root.sx
        y: 0
        width: 246 * root.sx
        height: parent.height

        // 1. CALCULATED POSITIONS & STROKE CARD
        Rectangle {
            objectName: "fields"
            visible: hasBends
            x: 2 * root.sx
            y: 6 * root.sy
            width: parent.width - 4 * root.sx
            height: 304 * root.sy
            radius: 7
            color: root.cardBg
            border.color: root.cardBorderColor
            border.width: 1

            CardHeader {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                title: "CALCULATED POSITIONS & STROKE"
                accentColor: root.red
            }

            // Calculation Rows
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 32 * root.sy
                spacing: 2 * root.sy

                CalcRow {
                    label: "START SAFETY\nCLEARANCE POSITION"
                    value: numberText(calculation.startSafetyClearance, 3, "—")
                    unit: "in"
                    severity: calculation.upperLimitExceededError || calculation.lowerLimitExceededError ? "high" : "normal"
                }
                CalcRow {
                    label: "BEND CLAMP POSITION"
                    value: numberText(calculation.clampPosition, 3, "—")
                    unit: "in"
                    severity: calculation.upperLimitExceededError || calculation.lowerLimitExceededError ? "high" : "normal"
                }
                CalcRow {
                    label: overrideEnabled ? "FINAL BEND POSITION\nOVERRIDDEN" : "FINAL BEND POSITION"
                    value: numberText(calculation.inUseFinalBendPosition, 3, "—")
                    unit: "in"
                    redLabel: overrideEnabled
                    editableValue: overrideEnabled
                    severity: calculation.finalBendPositionOutLimit ? "high" : "normal"
                    onValueCommitted: function(value) { root.setNumericValue("overriddenFinalBendPosition", value) }
                }
                CalcRow {
                    label: "RETRACT AFTER BEND\nPOSITION"
                    value: numberText(calculation.retractAfterBend, 3, "—")
                    unit: "in"
                }
                CalcRow {
                    label: "TOTAL BEND STROKE"
                    value: numberText(overrideEnabled ? calculation.overriddenTotalBendStroke : calculation.totalBendStroke, 3, "—")
                    unit: "in"
                }
                CalcRow {
                    label: "CALCULATED BEND\nTONNAGE"
                    value: numberText(calculation.bendTonnage, 3, "—")
                    unit: "tons"
                    info: true
                    severity: calculation.tonnageError ? "high" : (calculation.tonnageWarning ? "medium" : "low")
                    onInfoClicked: root.showInfo("CALCULATED BEND TONNAGE", "Estimated force uses material thickness, tensile strength, bend width, and die V-opening. Green is normal, orange requires centering the work piece, and red exceeds the rating.")
                }
                CalcRow {
                    label: "PREDICTED INSIDE\nBEND RADIUS"
                    value: numberText(calculation.predictedInsideBendRadius, 3, "—")
                    unit: "in"
                    info: true
                    severity: "low"
                    onInfoClicked: root.showInfo("PREDICTED INSIDE BEND RADIUS", "Estimated inside radius based on die opening, material tensile strength, and the material radius rule of thumb.")
                }
            }

            // Bottom action: Open Diagram
            ActionButton {
                objectName: "create-bend-vertical-diagram-button"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6 * root.sx
                height: 28 * root.sy
                text: "OPEN VERTICAL POSITION DIAGRAM"
                base: root.red
                onClicked: root.showVerticalDiagram()
            }
        }

        // 2. BEND SPECIFIC NOTES CARD
        Rectangle {
            objectName: "bend-notes"
            visible: hasBends
            x: 2 * root.sx
            y: 316 * root.sy
            width: parent.width - 4 * root.sx
            height: 316 * root.sy
            radius: 7
            color: root.cardBg
            border.color: root.cardBorderColor
            border.width: 1

            CardHeader {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                title: "BEND REFERENCE NOTES"
                accentColor: root.orange
            }

            // Header 1: Back Gauge Origin Notes
            NotesTitle {
                x: 6 * root.sx
                y: 32 * root.sy
                width: parent.width - 12 * root.sx
                height: 20 * root.sy
                text: "BACK GAUGE ZERO ORIGIN"
                base: "#F1F5F9"
                textColor: root.textPrimary
            }

            // X-Axis Note
            NotesSubTitle {
                x: 6 * root.sx
                y: 56 * root.sy
                width: 48 * root.sx
                height: 56 * root.sy
                text: "X-AXIS"
            }
            NotesArea {
                objectName: "create-bend-x-axis-notes"
                x: 58 * root.sx
                y: 56 * root.sy
                width: parent.width - 64 * root.sx
                height: 56 * root.sy
                text: currentBend.xAxisNotes || ""
                placeholderText: "Example: Zeroed at center of table"
                keyboardTitle: qsTr("X-AXIS NOTES")
                onKeyboardCommitted: function(value) { root.setBendValue("xAxisNotes", value) }
            }

            // R-Axis Note
            NotesSubTitle {
                x: 6 * root.sx
                y: 118 * root.sy
                width: 48 * root.sx
                height: 56 * root.sy
                text: "R-AXIS"
            }
            NotesArea {
                objectName: "create-bend-r-axis-notes"
                x: 58 * root.sx
                y: 118 * root.sy
                width: parent.width - 64 * root.sx
                height: 56 * root.sy
                text: currentBend.rAxisNotes || ""
                placeholderText: "Example: Finger zeroed on top of table"
                keyboardTitle: qsTr("R-AXIS NOTES")
                onKeyboardCommitted: function(value) { root.setBendValue("rAxisNotes", value) }
            }

            // Header 2: General Bend Notes
            NotesTitle {
                x: 6 * root.sx
                y: 180 * root.sy
                width: parent.width - 12 * root.sx
                height: 20 * root.sy
                text: "GENERAL BEND NOTES"
                base: "#F1F5F9"
                textColor: root.textPrimary
            }

            // General Bend Note
            NotesArea {
                objectName: "create-bend-general-notes"
                x: 6 * root.sx
                y: 204 * root.sy
                width: parent.width - 12 * root.sx
                height: parent.height - 212 * root.sy
                text: currentBend.notes || ""
                placeholderText: "Here you can write notes about this specific bend move"
                bottomRounded: true
                keyboardTitle: qsTr("GENERAL BEND NOTES")
                onKeyboardCommitted: function(value) { root.setBendValue("notes", value) }
            }
        }
    }

    // ==========================================
    // REUSABLE COMPONENTS
    // ==========================================

    component CardHeader: Rectangle {
        property string title: ""
        property color accentColor: root.blue
        height: 28 * root.sy
        color: root.cardHeaderBg
        radius: 7

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius
            color: parent.color
        }

        Text {
            x: 12 * root.sx
            anchors.verticalCenter: parent.verticalCenter
            text: parent.title
            color: "white"
            font.bold: true
            font.pixelSize: 11
            font.letterSpacing: 0.5
            elide: Text.ElideRight
        }
    }

    component PdmBlock: Rectangle {
        id: pdmRoot
        property string label: ""
        property string comboClass: ""
        property color accent: root.red
        property var model: []
        property var items: []
        property int currentIndex: 0
        signal activated(int index)

        radius: 8 * root.sx
        color: "white"
        border.color: pdmRoot.accent
        border.width: 1.5
        clip: true
        opacity: enabled ? 1 : 0.45

        // Integrated Solid Color Header Band with rounded top corners
        Rectangle {
            id: pdmHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.topMargin: 1
            height: 18 * root.sy
            color: pdmRoot.accent
            radius: 7 * root.sx

            // Square off bottom corners so dividing line against combo is flat
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.radius
                color: parent.color
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8 * root.sx
                anchors.verticalCenter: parent.verticalCenter
                text: pdmRoot.label
                color: "white"
                font.bold: true
                font.pixelSize: 10
                font.letterSpacing: 0.5
            }
        }

        // Seamless Tool Selector Area with rounded bottom corners
        EntityCombo {
            enabled: pdmRoot.enabled
            objectName: "combo-box-base combo-box " + pdmRoot.comboClass
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: pdmHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            model: pdmRoot.model
            rawItems: pdmRoot.items
            comboClass: pdmRoot.comboClass
            currentIndex: pdmRoot.currentIndex
            accent: pdmRoot.accent
            dark: false
            twoLineItems: true
            seamless: true
            onActivated: function(index) { pdmRoot.activated(index) }
        }
    }

    component EntityCombo: ComboBox {
        id: combo
        property bool colored: false
        property bool dark: false
        property bool twoLineItems: false
        property bool seamless: false
        property string comboClass: ""
        property var rawItems: []
        property color accent: root.red
        property int hoverIndex: -1
        font.pixelSize: 11
        font.bold: true
        leftPadding: 0
        rightPadding: 0
        indicator: VectorIcon {
            x: combo.width - 18 * root.sx
            y: (combo.height - 10 * root.sy) / 2
            width: 10 * root.sx
            height: 10 * root.sy
            iconName: "caret-down"
            rotation: combo.popup.visible ? 180 : 0
        }
        contentItem: Item {
            Text {
                x: 8 * root.sx
                y: 0
                width: parent.width - x - 22 * root.sx
                height: parent.height
                text: combo.displayText
                color: root.textPrimary
                font: combo.font
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.NoWrap
                maximumLineCount: combo.twoLineItems ? 2 : 1
                elide: Text.ElideRight
                lineHeight: 0.95
            }
        }
        background: Rectangle {
            radius: combo.seamless ? 7 * root.sx : 5
            color: combo.down ? "#F1F5F9" : (combo.hovered ? "#F8FAFC" : "white")
            border.color: combo.seamless ? "transparent" : (combo.popup.visible ? root.blue : root.inputBorderColor)
            border.width: combo.seamless ? 0 : 1

            // Square off top corners when seamless so it meets the header squarely
            Rectangle {
                visible: combo.seamless
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.radius
                color: parent.color
            }
        }
        popup: Popup {
            y: combo.height + 2 * root.sy
            width: combo.width
            implicitHeight: Math.min(comboList.contentHeight + 6 * root.sy, combo.twoLineItems ? root.pdmPopupMaxHeight(combo) : 200 * root.sy)
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            padding: 3
            contentItem: ListView {
                id: comboList
                property var comboOwner: combo
                clip: true
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.hoverIndex >= 0 ? combo.hoverIndex : combo.currentIndex
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 6 * root.sx
                    contentItem: Rectangle { radius: width / 2; color: "#94A3B8" }
                }
            }
            background: Rectangle {
                color: "white"
                border.color: root.cardBorderColor
                border.width: 1
                radius: 5
            }
        }
        delegate: Component {
            Item {
                readonly property var owner: ListView.view ? ListView.view.comboOwner : null
                width: owner ? owner.width : 240 * root.sx
                height: (owner && owner.twoLineItems ? 40 : 28) * root.sy
                readonly property bool highlighted: owner ? owner.hoverIndex === index : false
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: parent.highlighted ? "#EFF6FF" : "transparent"
                }
                Text {
                    x: 8 * root.sx
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 16 * root.sx
                    text: modelData
                    color: parent.highlighted ? root.blue : root.textPrimary
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                    maximumLineCount: owner && owner.twoLineItems ? 2 : 1
                    elide: Text.ElideRight
                    lineHeight: 0.94
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: if (parent.owner) parent.owner.hoverIndex = index
                    onExited: if (parent.owner && parent.owner.hoverIndex === index) parent.owner.hoverIndex = -1
                    onClicked: {
                        if (parent.owner) {
                            parent.owner.currentIndex = index
                            parent.owner.activated(index)
                            parent.owner.popup.close()
                            parent.owner.hoverIndex = -1
                        }
                    }
                }
            }
        }
    }

    component AppTextField: TextField {
        property bool alignLeft: false
        property string keyboardTitle: qsTr("ENTER TEXT")
        signal keyboardCommitted(string value)
        function openKeyboard() {
            root.openTextKeyboard(this, keyboardTitle,
                                  function(value) { keyboardCommitted(value) })
        }
        selectByMouse: true
        color: root.textPrimary
        font.pixelSize: 12
        font.bold: true
        horizontalAlignment: alignLeft ? TextInput.AlignLeft : TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        leftPadding: 8 * root.sx
        rightPadding: 8 * root.sx
        background: Rectangle {
            radius: 5
            color: "white"
            border.color: parent.activeFocus ? root.blue : root.inputBorderColor
            border.width: 1
        }
        TapHandler { onTapped: parent.openKeyboard() }
    }

    component MeasureField: TextField {
        property string value: ""
        property string unit: ""
        property bool highlighted: false
        property bool editable: false
        property color fieldColor: "white"
        property color foregroundColor: root.textPrimary
        property bool outlined: false
        property string keyboardTitle: qsTr("ENTER VALUE")
        signal keyboardCommitted(string value)
        function openKeyboard() {
            if (editable)
                root.openNumericKeyboard(this, keyboardTitle,
                                         function(value) { keyboardCommitted(value) })
        }
        text: value
        readOnly: !editable
        selectByMouse: true
        color: foregroundColor
        font.pixelSize: 12
        font.bold: true
        horizontalAlignment: TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        leftPadding: 4 * root.sx
        rightPadding: Math.max(16 * root.sx, unitText.width + 6 * root.sx)
        background: Rectangle {
            radius: 5
            color: parent.fieldColor
            border.color: parent.highlighted ? root.purple : (parent.outlined ? root.red : (parent.editable ? root.inputBorderColor : "#E2E8F0"))
            border.width: parent.highlighted ? 2 : (parent.outlined ? 2 : 1)
        }
        Text {
            id: unitText
            anchors.right: parent.right
            anchors.rightMargin: 4 * root.sx
            anchors.verticalCenter: parent.verticalCenter
            text: parent.unit
            color: root.textMuted
            font.pixelSize: 10
            font.bold: true
        }
        TapHandler { enabled: parent.editable; onTapped: parent.openKeyboard() }
    }

    component FieldLabel: Text {
        property color textColor: root.textPrimary
        property bool singleLine: false
        color: textColor
        font.bold: true
        font.pixelSize: 11
        wrapMode: singleLine ? Text.NoWrap : Text.WordWrap
        verticalAlignment: Text.AlignVCenter
        elide: singleLine ? Text.ElideRight : Text.ElideNone
    }

    component InfoButton: Button {
        id: infoBtn
        Accessible.name: qsTr("Show information")
        hoverEnabled: true

        contentItem: Text {
            anchors.centerIn: parent
            text: "i"
            font.bold: true
            font.pixelSize: 11
            font.family: "Georgia, 'Times New Roman', serif"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: infoBtn.down ? "#0F172A" : (infoBtn.hovered ? root.blue : "#334155")
        }
        background: Rectangle {
            anchors.centerIn: parent
            width: 18 * root.sx
            height: 18 * root.sx
            radius: width / 2
            color: infoBtn.down ? "#CBD5E1" : (infoBtn.hovered ? "#DBEAFE" : "#E2E8F0")
            border.color: infoBtn.hovered ? root.blue : "#94A3B8"
            border.width: 1.5
        }
    }

    component IconButton: Button {
        id: iconBtn
        property string glyph: ""
        property color base: "#F1F5F9"
        property color iconColor: "black"
        property color borderColor: root.cardBorderColor
        hoverEnabled: true
        contentItem: VectorIcon {
            anchors.centerIn: parent
            width: 15 * root.sx
            height: 15 * root.sy
            iconName: iconBtn.glyph + (iconBtn.iconColor === root.white || iconBtn.iconColor === "white" || iconBtn.iconColor === "#ffffff" ? "-white" : "")
        }
        background: Rectangle {
            radius: 5
            color: iconBtn.down ? Qt.darker(iconBtn.base, 1.1) : (iconBtn.hovered ? Qt.lighter(iconBtn.base, 1.05) : iconBtn.base)
            border.color: iconBtn.hovered ? root.blue : iconBtn.borderColor
            border.width: iconBtn.borderColor === "transparent" ? 0 : 1
        }
    }

    component ToggleButtonLike: Button {
        property color base: root.red
        property bool accentPill: false
        opacity: enabled ? 1 : 0.45
        contentItem: Text {
            text: parent.text
            color: "white"
            font.bold: true
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideNone
        }
        background: Rectangle {
            radius: 4
            color: parent.down ? Qt.darker(parent.base, 1.1) : (parent.hovered ? Qt.lighter(parent.base, 1.05) : parent.base)
        }
    }

    component ActionButton: Button {
        property color base: root.red
        contentItem: Text {
            text: parent.text
            color: "white"
            font.bold: true
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
        background: Rectangle {
            radius: 4
            color: parent.down ? Qt.darker(parent.base, 1.1) : (parent.hovered ? Qt.lighter(parent.base, 1.05) : parent.base)
        }
    }

    component FooterButton: ActionButton {
        property string label: ""
        property string footerGlyph: ""
        property color textColor: "white"
        property bool leftRounded: false
        property bool rightRounded: false
        property bool allRounded: true
        opacity: enabled ? 1 : 0.40
        text: label
        background: Rectangle {
            color: parent.down ? Qt.darker(parent.base, 1.1) : (parent.hovered ? Qt.lighter(parent.base, 1.05) : parent.base)
            radius: 5
        }
        contentItem: Item {
            VectorIcon {
                id: footerIcon
                visible: parent.parent.footerGlyph !== ""
                x: 8 * root.sx
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.sx
                height: 14 * root.sy
                iconName: parent.parent.footerGlyph + (parent.parent.textColor === root.white || parent.parent.textColor === "white" ? "-white" : "")
            }
            Text {
                x: footerIcon.visible ? 26 * root.sx : 6 * root.sx
                y: 0
                width: parent.width - x - 6 * root.sx
                height: parent.height
                text: parent.parent.label
                color: parent.parent.textColor
                font.bold: true
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                maximumLineCount: 2
                lineHeight: 0.95
            }
        }
    }

    component HighlightAngleLabel: Rectangle {
        radius: 5
        color: "#E0F2FE"
        border.color: root.blue
        border.width: 1.5
        Rectangle {
            x: 6 * root.sx
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.sx
            height: 20 * root.sy
            radius: 10
            color: root.blue
            Text {
                anchors.centerIn: parent
                text: "∠"
                color: "white"
                font.bold: true
                font.pixelSize: 12
            }
        }
        Column {
            x: 30 * root.sx
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 34 * root.sx
            spacing: 1
            Text {
                width: parent.width
                text: "DESIRED BEND ANGLE"
                color: "#0369A1"
                font.bold: true
                font.pixelSize: 9
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: "INCLUDED"
                color: "#0284C7"
                font.bold: true
                font.pixelSize: 8
                font.letterSpacing: 0.5
                elide: Text.ElideRight
            }
        }
    }

    component WarningPanel: Item {
        Column {
            anchors.fill: parent
            spacing: 6 * root.sy
            Repeater {
                model: root.activeWarnings
                WarningLabel {
                    required property var modelData
                    width: parent.width
                    text: modelData.text
                    base: modelData.base
                }
            }
        }
    }

    component WarningLabel: Rectangle {
        property string text: ""
        property color base: root.red
        width: parent.width
        height: 24 * root.sy
        color: base
        radius: 4
        VectorIcon {
            x: 8 * root.sx
            anchors.verticalCenter: parent.verticalCenter
            width: 12 * root.sx
            height: 12 * root.sy
            iconName: "exclamation-triangle"
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 26 * root.sx
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 30 * root.sx
            text: parent.text
            color: "white"
            font.bold: true
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    component CalcRow: Item {
        id: calcRow
        property string label: ""
        property string value: ""
        property string unit: ""
        property bool redLabel: false
        property bool info: false
        property bool editableValue: false
        property string severity: "normal"
        signal valueCommitted(string value)
        signal infoClicked()

        x: 6 * root.sx
        width: parent.width - 12 * root.sx
        height: 32 * root.sy

        FieldLabel {
            x: 2 * root.sx
            y: 0
            width: calcRow.info ? 130 * root.sx : 150 * root.sx
            height: parent.height
            text: calcRow.label
            textColor: calcRow.redLabel ? root.red : root.textPrimary
            font.pixelSize: 10
        }
        InfoButton {
            visible: calcRow.info
            x: 130 * root.sx
            y: 0
            width: 22 * root.sx
            height: parent.height
            onClicked: calcRow.infoClicked()
        }
        MeasureField {
            id: overriddenFinalPositionEditor
            objectName: calcRow.editableValue ? "create-bend-overridden-final-position-field" : ""
            x: parent.width - 76 * root.sx
            y: 2 * root.sy
            width: 76 * root.sx
            height: 28 * root.sy
            value: calcRow.value
            unit: calcRow.unit
            editable: calcRow.editableValue
            keyboardTitle: qsTr("FINAL BEND POSITION")
            fieldColor: calcRow.editableValue ? "white" : (calcRow.severity === "high" ? root.red : (calcRow.severity === "medium" ? root.amber : (calcRow.severity === "low" ? root.green : root.charcoal)))
            foregroundColor: calcRow.editableValue ? root.ink : "white"
            outlined: calcRow.editableValue
            onKeyboardCommitted: function(value) { calcRow.valueCommitted(value) }
        }
    }

    component NotesTitle: Rectangle {
        property string text: ""
        property color base: "#CBD5E1"
        property color textColor: root.textPrimary
        property bool topRounded: false
        color: base
        radius: 4
        border.color: root.cardBorderColor
        border.width: 1
        Text {
            anchors.centerIn: parent
            width: parent.width - 8 * root.sx
            text: parent.text
            color: parent.textColor
            font.bold: true
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideNone
            wrapMode: Text.WordWrap
        }
    }

    component NotesSubTitle: Rectangle {
        property string text: ""
        color: "#D8DCE1"
        radius: 3
        border.color: root.cardBorderColor
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: root.textSecondary
            font.bold: true
            font.pixelSize: 10
        }
    }

    component NotesArea: ScrollView {
        id: notesScroll
        property alias text: notesText.text
        property alias textInput: notesText
        property string keyboardTitle: qsTr("ENTER TEXT")
        property string placeholderText: ""
        property bool bottomRounded: false
        signal keyboardCommitted(string value)
        function openKeyboard() {
            root.openTextKeyboard(
                notesText, keyboardTitle,
                function(value) { keyboardCommitted(value) })
        }
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.vertical.width: 6 * root.sx
        ScrollBar.vertical.contentItem: Rectangle { radius: width / 2; color: "#CBD5E1" }
        background: Rectangle {
            color: "white"
            border.color: root.inputBorderColor
            border.width: 1
            radius: notesScroll.bottomRounded ? 5 : 3
        }
        TextArea {
            id: notesText
            objectName: notesScroll.objectName + "-input"
            width: notesScroll.availableWidth
            selectByMouse: true
            wrapMode: TextEdit.WordWrap
            placeholderText: notesScroll.placeholderText
            placeholderTextColor: root.textMuted
            color: root.textPrimary
            font.pixelSize: 11
            padding: 5 * root.sx
            background: null
            TapHandler {
                onTapped: notesScroll.openKeyboard()
            }
        }
    }

    component VectorIcon: Image {
        property string iconName: "caret-down"
        source: root.iconPath(iconName)
        sourceSize.width: Math.max(1, width)
        sourceSize.height: Math.max(1, height)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
