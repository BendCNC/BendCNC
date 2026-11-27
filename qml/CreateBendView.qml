import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "core/BendCalculator.js" as BendCalculator

Item {
    id: root
    objectName: "create-bend-view bend-notes body button-append-new button-cancel button-compensation-direction button-create-new button-delete button-duplicate button-edit button-info button-open-vertical-diagram button-reset button-save combo-die combo-material combo-punch create-bend-press-toggle fields highlighted-text-field highlight-left-rounded icon-small item-selection label-overridden label-warning-orange label-warning-red measurement-text-field-override multi-icon panel-empty panel-warning-container pdm second-title small text-bend-notes text-bend-notes-bottom white-combo-box"
    property var appState: null

    readonly property real sx: width / 864
    readonly property real sy: height / 638.4
    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color charcoal: "#2B2C2B"
    readonly property color grey: "#A8A8A8"
    readonly property color paper: "#F5F5F5"
    readonly property color ink: "#232323"
    readonly property color white: "#FFFFFF"
    readonly property color purple: "#694D90"
    readonly property color orange: "orange"
    readonly property color cardSurface: "#B7B7B7"
    readonly property color cardBorder: "#8F8F8F"
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
        function onStoredProgramBendsChanged() {
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
        // Create Bend edits the selected program sequence. Production N1
        // programs keep their bends inline in programs.json while the global
        // bends.json library can legitimately be empty.
        // storedProgramBends excludes the session-only measured thickness
        // override, so saving here never persists the override values.
        workingBends = cloneValue(appState ? (appState.storedProgramBends !== undefined
            ? appState.storedProgramBends : appState.programBends) || [] : [])
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
            result.push({ text: "UNSAFE CLEARANCE PLANE", base: orange })
        if (overrideEnabled)
            result.push({ text: "OVERRIDDEN BEND DEPTH", base: orange })
        if (calculation.tonnageError)
            result.push({ text: "TONNAGE RATING EXCEEDED", base: red })
        else if (calculation.tonnageWarning)
            result.push({ text: "CENTER WORK PIECE", base: orange })
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
    function iconPath(name) {
        if (name === "pen-white") return "icons/fa-pen-white.svg"
        if (name === "trash-white") return "icons/fa-trash.svg"
        if (name === "trash") return "icons/fa-trash-black.svg"
        if (name === "info-circle-white") return "icons/fa-info-circle-white.svg"
        if (name === "caret-down-white") return "icons/fa-caret-down-white.svg"
        if (name === "plus-white") return "icons/fa-plus.svg"
        if (name === "times-white") return "icons/fa-times.svg"
        if (name === "save-white") return "icons/fa-save.svg"
        if (name === "undo-white") return "icons/fa-undo.svg"
        if (name === "duplicate") return "icons/fa-file-black.svg"
        if (name === "duplicate-white") return "icons/fa-file-white.svg"
        if (name === "list-plus-white") return "icons/fa-list-ol.svg"
        return "icons/fa-" + name + ".svg"
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

    Rectangle { anchors.fill: parent; color: grey }

    Item {
        objectName: "left body"
        x: 0; y: 0; width: 613.6 * root.sx; height: parent.height
        Item {
            objectName: "bendEditor body"
            x: 0; y: 0; width: parent.width; height: 585.6 * root.sy
            Item {
                objectName: "item-selection"
                x: 7.2 * root.sx; y: 7.2 * root.sy; width: 599.2 * root.sx; height: 35.2 * root.sy
                EntityCombo { visible: !editingName; enabled: !editing; x: 0; y: 0; width: 561.6 * root.sx; height: parent.height; objectName: "combo-box-base combo-box white-combo-box"; model: root.names(workingBends); currentIndex: root.selectedBendIndex; onActivated: function(index) { root.selectedBendIndex = index; root.syncSelectedToolIndexes(); root.logSelection("Bend", currentBend) } }
                AppTextField {
                    id: bendNameEditor
                    objectName: "create-bend-name-field"
                    visible: editingName
                    x: 0; y: 0; width: 561.6 * root.sx; height: parent.height
                    text: currentBend.name || ""
                    alignLeft: true
                    keyboardTitle: qsTr("BEND NAME")
                    onKeyboardCommitted: function(value) { root.setBendValue("name", String(value).trim()) }
                }
                IconButton { visible: !editingName; enabled: hasBends; x: 568.8 * root.sx; y: 0; width: 30.4 * root.sx; height: parent.height; glyph: "pen"; base: "white"; iconColor: ink; borderColor: ink; onClicked: root.beginEdit(true) }
                IconButton { visible: editingName; enabled: !creatingNew; x: 568.8 * root.sx; y: 0; width: 30.4 * root.sx; height: parent.height; glyph: "trash"; base: red; iconColor: "white"; onClicked: root.requestDelete() }
            }
            Item {
                objectName: "pdm"
                visible: hasBends
                x: 7.2 * root.sx; y: 49.6 * root.sy; width: 600 * root.sx; height: 57.8 * root.sy
                PdmBlock { enabled: !overrideEnabled; x: 0; y: 0; width: 197.6 * root.sx; label: "PUNCH"; comboClass: "combo-punch"; accent: red; items: dataStore.punches; model: root.pdmNames(dataStore.punches, "combo-punch"); currentIndex: root.selectedPunchIndex; onActivated: function(index) { root.selectTool("Punch", index) } }
                PdmBlock { enabled: !overrideEnabled; x: 201.6 * root.sx; y: 0; width: 196 * root.sx; label: "DIE"; comboClass: "combo-die"; accent: blue; items: dataStore.dies; model: root.pdmNames(dataStore.dies, "combo-die"); currentIndex: root.selectedDieIndex; onActivated: function(index) { root.selectTool("Die", index) } }
                PdmBlock { enabled: !overrideEnabled; x: 402.4 * root.sx; y: 0; width: 197.6 * root.sx; label: "MATERIAL TYPE"; comboClass: "combo-material"; accent: green; items: dataStore.materials; model: root.pdmNames(dataStore.materials, "combo-material"); currentIndex: root.selectedMaterialIndex; onActivated: function(index) { root.selectTool("Material", index) } }
            }
            Item {
                objectName: "fields"
                visible: hasBends
                x: 7.2 * root.sx; y: 113.6 * root.sy; width: 599.2 * root.sx; height: 308.8 * root.sy
                HighlightAngleLabel { x: 0; y: 0; width: 137.6 * root.sx; height: 36.8 * root.sy }
                InfoButton { x: 144 * root.sx; y: 0; width: 30.4 * root.sx; height: 36.8 * root.sy; onClicked: root.showInfo("DESIRED BEND ANGLE", "The included angle requested after springback and angle compensation are applied.") }
                MeasureField { id: desiredAngleEditor; objectName: "create-bend-angle-field highlighted-text-field"; x: 179.2 * root.sx; y: 0; width: 133.6 * root.sx; height: 36.8 * root.sy; value: numberText(currentBend.desiredBendAngle, 1, "—"); unit: "deg"; highlighted: true; editable: !overrideEnabled && hasBends; keyboardTitle: qsTr("DESIRED BEND ANGLE"); onKeyboardCommitted: function(value) { root.setNumericValue("desiredBendAngle", value, 15, 170) } }
                FieldLabel { x: 0; y: 44 * root.sy; width: 137.6 * root.sx; height: 30.4 * root.sy; text: "ANGLE COMPENSATION" }
                InfoButton { x: 144 * root.sx; y: 44 * root.sy; width: 30.4 * root.sx; height: 30.4 * root.sy; onClicked: root.showInfo("ANGLE COMPENSATION", "OVERBENT adds compensation to bend farther. UNDERBENT subtracts compensation to bend less.") }
                ToggleButtonLike { objectName: "create-bend-compensation-direction"; enabled: !overrideEnabled && hasBends; x: 179.2 * root.sx; y: 44 * root.sy; width: 86 * root.sx; height: 30.4 * root.sy; text: currentBend.angleCompensationReversed ? "UNDERBENT" : "OVERBENT"; base: currentBend.angleCompensationReversed ? blue : red; onClicked: { root.setBendValue("angleCompensationReversed", !currentBend.angleCompensationReversed); if (appState) appState.log("CREATE BEND", "Angle compensation direction " + (currentBend.angleCompensationReversed ? "UNDERBENT" : "OVERBENT")) } }
                MeasureField { id: angleCompensationEditor; objectName: "create-bend-compensation-field"; x: 272.4 * root.sx; y: 44 * root.sy; width: 40.4 * root.sx; height: 30.4 * root.sy; value: numberText(currentBend.angleCompensation, 1, "0.0"); unit: "deg"; editable: !overrideEnabled && hasBends; keyboardTitle: qsTr("ANGLE COMPENSATION"); onKeyboardCommitted: function(value) { root.setNumericValue("angleCompensation", value, 0, 90) } }
                FieldLabel { x: 0; y: 81.6 * root.sy; width: 137.6 * root.sx; height: 30.4 * root.sy; text: "PUNCH TO MATERIAL CLEARANCE" }
                InfoButton { x: 144 * root.sx; y: 81.6 * root.sy; width: 30.4 * root.sx; height: 30.4 * root.sy; onClicked: root.showInfo("PUNCH-TO-MATERIAL CLEARANCE", "Clearance between the punch and material at the start safety position. Values over 0.300 in trigger a safety warning.") }
                MeasureField { id: clearanceEditor; objectName: "create-bend-clearance-field"; x: 179.2 * root.sx; y: 81.6 * root.sy; width: 133.6 * root.sx; height: 30.4 * root.sy; value: numberText(derivedClearance(), 3, "0.050"); unit: "in"; editable: hasBends; keyboardTitle: qsTr("PUNCH TO MATERIAL CLEARANCE"); onKeyboardCommitted: function(value) { root.setNumericValue("punchToMaterialClearance", value, 0.01, 5) } }
                FieldLabel { x: 0; y: 119.2 * root.sy; width: 137.6 * root.sx; height: 30.4 * root.sy; text: "ADDITIONAL RETRACT AFTER BEND" }
                InfoButton { x: 144 * root.sx; y: 119.2 * root.sy; width: 30.4 * root.sx; height: 30.4 * root.sy; onClicked: root.showInfo("ADDITIONAL RETRACT AFTER BEND", "Extra upward ram travel after completing the bend, limited by machine travel.") }
                MeasureField { id: additionalRetractEditor; objectName: "create-bend-retract-field"; x: 179.2 * root.sx; y: 119.2 * root.sy; width: 133.6 * root.sx; height: 30.4 * root.sy; value: numberText(currentBend.additionalRetractAfterBend, 3, "0.000"); unit: "in"; editable: hasBends; keyboardTitle: qsTr("ADDITIONAL RETRACT"); onKeyboardCommitted: function(value) { root.setNumericValue("additionalRetractAfterBend", value, 0, 3.75) } }
                FieldLabel { x: 359.2 * root.sx; y: 10.4 * root.sy; width: 136 * root.sx; height: 15.2 * root.sy; text: "MATERIAL THICKNESS"; font.pixelSize: 11; singleLine: true }
                MeasureField { id: materialThicknessEditor; objectName: "create-bend-thickness-field"; x: 499.2 * root.sx; y: 0; width: 99.2 * root.sx; height: 36.8 * root.sy; value: numberText(currentBend.materialThickness, 3, "—"); unit: "in"; editable: !overrideEnabled && hasBends; keyboardTitle: qsTr("MATERIAL THICKNESS"); onKeyboardCommitted: function(value) { root.setNumericValue("materialThickness", value, 0.01, 2.5) } }
                // Thickness released from Manual > Measure (USE IN PROGRAM).
                ToggleButtonLike { objectName: "create-bend-use-measured-thickness"; visible: appState && appState.measuredMaterialThicknessValid; enabled: !overrideEnabled && hasBends; x: 359.2 * root.sx; y: 27.2 * root.sy; width: 136 * root.sx; height: 15.2 * root.sy; text: appState && appState.measuredMaterialThicknessValid ? qsTr("USE MEASURED %1 in").arg(appState.measuredMaterialThickness.toFixed(4)) : ""; base: blue; onClicked: { if (!appState || !appState.measuredMaterialThicknessValid) return; root.setNumericValue("materialThickness", appState.measuredMaterialThickness, 0.01, 2.5); appState.log("CREATE BEND", "Material thickness set from measurement " + appState.measuredMaterialThickness.toFixed(4) + " in") } }
                FieldLabel { x: 359.2 * root.sx; y: 52 * root.sy; width: 101.6 * root.sx; height: 15.2 * root.sy; text: "BEND WIDTH"; font.pixelSize: 11; singleLine: true }
                InfoButton { x: 464.8 * root.sx; y: 44 * root.sy; width: 30.4 * root.sx; height: 30.4 * root.sy; onClicked: root.showInfo("BEND WIDTH", "Length of material being bent. It is used to calculate required tonnage.") }
                MeasureField { id: bendWidthEditor; objectName: "create-bend-width-field"; x: 499.2 * root.sx; y: 44 * root.sy; width: 99.2 * root.sx; height: 30.4 * root.sy; value: numberText(currentBend.bendWidth, 1, "0.1"); unit: "in"; editable: hasBends; keyboardTitle: qsTr("BEND WIDTH"); onKeyboardCommitted: function(value) { root.setNumericValue("bendWidth", value, 0.1, 33.3) } }
                FieldLabel { x: 359.2 * root.sx; y: 88.8 * root.sy; width: 136 * root.sx; height: 15.2 * root.sy; text: "ADD BACK GAUGE MOVE"; font.pixelSize: 11; singleLine: true }
                ToggleButtonLike { objectName: "create-bend-backgauge-toggle"; enabled: hasBends; x: 499.2 * root.sx; y: 81.6 * root.sy; width: 99.2 * root.sx; height: 30.4 * root.sy; text: backGaugeEnabled ? "ENABLED" : "DISABLED"; base: backGaugeEnabled ? green : red; onClicked: { root.setBendValue("backGaugeRefEdgeStopEnabled", !backGaugeEnabled); if (appState) appState.log("CREATE BEND", "Back gauge move " + (currentBend.backGaugeRefEdgeStopEnabled ? "enabled" : "disabled")) } }
                FieldLabel { x: 359.2 * root.sx; y: 119.2 * root.sy; width: 99.2 * root.sx; height: 30.4 * root.sy; text: "OVERRIDE FINAL BEND POS" }
                InfoButton { x: 464.8 * root.sx; y: 119.2 * root.sy; width: 30.4 * root.sx; height: 30.4 * root.sy; onClicked: root.showInfo("OVERRIDE FINAL BEND POSITION", "Replaces the calculated final ram position with an operator-entered value. Tooling, angle, and thickness remain locked while enabled.") }
                ToggleButtonLike { objectName: "create-bend-override-toggle"; enabled: hasBends; x: 499.2 * root.sx; y: 119.2 * root.sy; width: 99.2 * root.sx; height: 30.4 * root.sy; text: overrideEnabled ? "ENABLED" : "DISABLED"; base: overrideEnabled ? green : red; onClicked: { var next = !overrideEnabled; if (next) { var calculated = Number(calculation.calculatedFinalBendPosition); if (!isFinite(calculated)) calculated = Number(currentBend.finalPosition); if (!isFinite(calculated)) { if (appState) appState.showAlarm("FINAL BEND OVERRIDE", "A calculated or stored final bend position is required before enabling the override."); return } root.setBendValue("overriddenFinalBendPosition", calculated) } root.setBendValue("overrideFinalBendPositionEnabled", next); if (appState) appState.log("CREATE BEND", "Final bend override " + (next ? "enabled" : "disabled")) } }
                WarningPanel { x: 359.2 * root.sx; y: 156.8 * root.sy; width: 240 * root.sx; height: 152 * root.sy }
            }
            Rectangle {
                objectName: "back-gauge"
                visible: hasBends && backGaugeEnabled
                x: 7.2 * root.sx; y: 429.6 * root.sy; width: 599.2 * root.sx; height: 116 * root.sy; radius: 7; color: green
                FieldLabel { x: 7.2 * root.sx; y: 7.2 * root.sy; width: 180 * root.sx; height: 15.2 * root.sy; text: "REFERENCE EDGE STOP"; textColor: "white"; singleLine: true }
                EntityCombo {
                    objectName: "reference-edge-stop-combo"
                    x: 7.2 * root.sx; y: 29.6 * root.sy
                    width: 585.6 * root.sx; height: 27.4 * root.sy
                    model: root.backGaugeReferenceStopNames()
                    currentIndex: Math.max(0, root.backGaugeReferenceStopIds.indexOf(currentBend.backGaugeRefEdgeStop || "G54"))
                    dark: true
                    onActivated: function(index) {
                        if (index < 0 || index >= root.backGaugeReferenceStopIds.length)
                            return
                        root.setBendValue("backGaugeRefEdgeStop", root.backGaugeReferenceStopIds[index])
                        root.logSelection("Reference edge stop", {
                            name: root.backGaugeReferenceStopNames()[index]
                        })
                    }
                }
                FieldLabel { x: 7.2 * root.sx; y: 63.2 * root.sy; width: 80 * root.sx; height: 15.2 * root.sy; text: "X POSITION"; textColor: "white"; singleLine: true }
                FieldLabel { x: 204.8 * root.sx; y: 63.2 * root.sy; width: 80 * root.sx; height: 15.2 * root.sy; text: "R POSITION"; textColor: "white"; singleLine: true }
                FieldLabel { x: 401.6 * root.sx; y: 63.2 * root.sy; width: 80 * root.sx; height: 15.2 * root.sy; text: "JOG SPEED"; textColor: "white"; singleLine: true }
                MeasureField { id: backGaugeXEditor; objectName: "create-bend-backgauge-x-field"; x: 7.2 * root.sx; y: 85.6 * root.sy; width: 190.4 * root.sx; height: 23.2 * root.sy; value: numberText(currentBend.backGaugeXPosition, 3, "0.000"); unit: "in"; editable: backGaugeEnabled; keyboardTitle: qsTr("BACK GAUGE X"); onKeyboardCommitted: function(value) { root.setNumericValue("backGaugeXPosition", value) } }
                MeasureField { id: backGaugeREditor; objectName: "create-bend-backgauge-r-field"; x: 204.8 * root.sx; y: 85.6 * root.sy; width: 190.4 * root.sx; height: 23.2 * root.sy; value: numberText(currentBend.backGaugeRPosition, 3, "0.000"); unit: "in"; editable: backGaugeEnabled; keyboardTitle: qsTr("BACK GAUGE R"); onKeyboardCommitted: function(value) { root.setNumericValue("backGaugeRPosition", value) } }
                MeasureField { id: backGaugeSpeedEditor; objectName: "create-bend-backgauge-speed-field"; x: 401.6 * root.sx; y: 85.6 * root.sy; width: 190.4 * root.sx; height: 23.2 * root.sy; value: numberText(currentBend.backGaugeJogSpeed, 0, "100"); unit: "IPM"; editable: backGaugeEnabled; keyboardTitle: qsTr("BACK GAUGE JOG SPEED"); onKeyboardCommitted: function(value) { root.setNumericValue("backGaugeJogSpeed", value, 1, 500) } }
            }
            Rectangle {
                objectName: "create-bend-empty-panel"
                visible: !hasBends
                x: 7.2 * root.sx; y: 49.6 * root.sy; width: 599.2 * root.sx; height: 496 * root.sy
                radius: 7; color: paper; border.color: cardBorder; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: qsTr("NO BENDS AVAILABLE")
                    color: ink
                    font.bold: true
                    font.pixelSize: 18
                }
            }
        }
        Item {
            objectName: "footer"
            x: 0; y: 585.6 * root.sy; width: parent.width; height: 52.8 * root.sy
            FooterButton { objectName: "create-bend-new-cancel-button"; x: 7.2 * root.sx; y: 7.2 * root.sy; width: 120 * root.sx; height: 38.4 * root.sy; label: editing ? "CANCEL" : "NEW BEND\nMOVE"; footerGlyph: editing ? "times" : "plus"; base: editing ? red : blue; leftRounded: true; onClicked: editing ? root.cancelEditing() : root.createNew() }
            FooterButton { objectName: "create-bend-save-button"; enabled: canSave; x: 127.2 * root.sx; y: 7.2 * root.sy; width: 90.4 * root.sx; height: 38.4 * root.sy; label: "SAVE"; footerGlyph: "save"; base: green; onClicked: root.saveEditing() }
            FooterButton { objectName: "create-bend-duplicate-button"; enabled: hasBends && !creatingNew; x: 217.6 * root.sx; y: 7.2 * root.sy; width: 102.4 * root.sx; height: 38.4 * root.sy; label: "DUPLICATE"; footerGlyph: "duplicate"; base: orange; textColor: ink; onClicked: root.duplicateCurrent() }
            FooterButton { objectName: "create-bend-reset-button"; enabled: editing && hasBends; x: 319.2 * root.sx; y: 7.2 * root.sy; width: 101.6 * root.sx; height: 38.4 * root.sy; label: "RESET"; footerGlyph: "undo"; base: charcoal; rightRounded: true; onClicked: root.resetEditing() }
            FooterButton { objectName: "create-bend-load-button"; enabled: hasBends && !editing; x: 432 * root.sx; y: 7.2 * root.sy; width: 174.4 * root.sx; height: 38.4 * root.sy; label: "LOAD BEND\nINTO PROGRAM"; footerGlyph: "list-plus"; base: charcoal; allRounded: true; onClicked: if (appState) appState.createBendAction("load", root.bendTitle(), root.currentBend, root.currentPunch, root.currentDie, root.currentMaterial, root.calcFinalBendPosition(), root.calcTonnage()) }
        }
    }

    Item {
        objectName: "right"
        x: 613.6 * root.sx; y: 0; width: 251.2 * root.sx; height: parent.height
        Rectangle { anchors.fill: parent; color: grey }
        Rectangle {
            objectName: "fields"
            visible: hasBends
            x: 4 * root.sx; y: 4 * root.sy; width: 243.2 * root.sx; height: 300.8 * root.sy
            radius: 7; color: cardSurface; border.color: cardBorder; border.width: 1
            ActionButton { objectName: "create-bend-vertical-diagram-button"; x: 4 * root.sx; y: 4 * root.sy; width: 235.2 * root.sx; height: 26.4 * root.sy; text: "OPEN VERTICAL POSITION DIAGRAM"; base: red; onClicked: root.showVerticalDiagram() }
            CalcRow { y: 37.6 * root.sy; label: "START SAFETY\nCLEARANCE POSITION"; value: numberText(calculation.startSafetyClearance, 3, "—"); unit: "in"; severity: calculation.upperLimitExceededError || calculation.lowerLimitExceededError ? "high" : "normal" }
            CalcRow { y: 75.2 * root.sy; label: "BEND CLAMP POSITION"; value: numberText(calculation.clampPosition, 3, "—"); unit: "in"; severity: calculation.upperLimitExceededError || calculation.lowerLimitExceededError ? "high" : "normal" }
            CalcRow { y: 112.8 * root.sy; label: overrideEnabled ? "FINAL BEND POSITION\nOVERRIDDEN" : "FINAL BEND POSITION"; value: numberText(calculation.inUseFinalBendPosition, 3, "—"); unit: "in"; redLabel: overrideEnabled; editableValue: overrideEnabled; severity: calculation.finalBendPositionOutLimit ? "high" : "normal"; onValueCommitted: function(value) { root.setNumericValue("overriddenFinalBendPosition", value) } }
            CalcRow { y: 150.4 * root.sy; label: "RETRACT AFTER BEND\nPOSITION"; value: numberText(calculation.retractAfterBend, 3, "—"); unit: "in" }
            CalcRow { y: 188 * root.sy; label: "TOTAL BEND STROKE"; value: numberText(overrideEnabled ? calculation.overriddenTotalBendStroke : calculation.totalBendStroke, 3, "—"); unit: "in" }
            CalcRow { y: 225.6 * root.sy; label: "CALCULATED BEND\nTONNAGE"; value: numberText(calculation.bendTonnage, 3, "—"); unit: "tons"; info: true; severity: calculation.tonnageError ? "high" : (calculation.tonnageWarning ? "medium" : "low"); onInfoClicked: root.showInfo("CALCULATED BEND TONNAGE", "Estimated force uses material thickness, tensile strength, bend width, and die V-opening. Green is normal, orange requires centering the work piece, and red exceeds the rating.") }
            CalcRow { y: 263.2 * root.sy; label: "PREDICTED INSIDE\nBEND RADIUS"; value: numberText(calculation.predictedInsideBendRadius, 3, "—"); unit: "in"; info: true; severity: "low"; onInfoClicked: root.showInfo("PREDICTED INSIDE BEND RADIUS", "Estimated inside radius based on die opening, material tensile strength, and the material radius rule of thumb.") }
        }
        Rectangle {
            objectName: "bend-notes"
            visible: hasBends
            x: 4 * root.sx; y: 311.2 * root.sy; width: 243.2 * root.sx; height: 323.2 * root.sy
            radius: 7; color: cardSurface; border.color: cardBorder; border.width: 1
            NotesTitle { x: 1 * root.sx; y: 1 * root.sy; width: 241.2 * root.sx; height: 32.8 * root.sy; text: "BACK GAUGE ZERO ORIGIN NOTES"; base: red; topRounded: true }
            NotesSubTitle { x: 1 * root.sx; y: 34.4 * root.sy; width: 61.4 * root.sx; height: 72 * root.sy; text: "X-AXIS" }
            NotesArea { objectName: "create-bend-x-axis-notes"; x: 63.2 * root.sx; y: 34.4 * root.sy; width: 179 * root.sx; height: 72 * root.sy; text: currentBend.xAxisNotes || ""; placeholderText: "Example: Back Gauge Reference Edge was zeroed at center of the table"; keyboardTitle: qsTr("X-AXIS NOTES"); onKeyboardCommitted: function(value) { root.setBendValue("xAxisNotes", value) } }
            NotesSubTitle { x: 1 * root.sx; y: 107.2 * root.sy; width: 61.4 * root.sx; height: 71.2 * root.sy; text: "R-AXIS" }
            NotesArea { objectName: "create-bend-r-axis-notes"; x: 63.2 * root.sx; y: 107.2 * root.sy; width: 179 * root.sx; height: 71.2 * root.sy; text: currentBend.rAxisNotes || ""; placeholderText: "Example: Finger zeroed on top of table"; keyboardTitle: qsTr("R-AXIS NOTES"); onKeyboardCommitted: function(value) { root.setBendValue("rAxisNotes", value) } }
            NotesTitle { x: 1 * root.sx; y: 179.2 * root.sy; width: 241.2 * root.sx; height: 32.8 * root.sy; text: "GENERAL BEND NOTES"; base: orange; textColor: ink }
            NotesArea { objectName: "create-bend-general-notes"; x: 1 * root.sx; y: 212.8 * root.sy; width: 241.2 * root.sx; height: 109.4 * root.sy; text: currentBend.notes || ""; placeholderText: "Here you can write notes about this specific bend move"; bottomRounded: true; keyboardTitle: qsTr("GENERAL BEND NOTES"); onKeyboardCommitted: function(value) { root.setBendValue("notes", value) } }
        }
    }

    component PdmBlock: Item {
        property string label: ""
        property string comboClass: ""
        property color accent: red
        property var model: []
        property var items: []
        property int currentIndex: 0
        signal activated(int index)
        opacity: enabled ? 1 : 0.45
        Text { x: 0; y: 0; width: parent.width; height: 15.2 * root.sy; text: parent.label; color: ink; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight }
        EntityCombo { enabled: parent.enabled; objectName: "combo-box-base combo-box " + parent.comboClass; x: 0; y: 22.4 * root.sy; width: parent.width; height: 35.4 * root.sy; model: parent.model; rawItems: parent.items; comboClass: parent.comboClass; currentIndex: parent.currentIndex; accent: parent.accent; colored: true; twoLineItems: true; onActivated: function(index) { parent.activated(index) } }
    }

    component EntityCombo: ComboBox {
        id: combo
        property bool colored: false
        property bool dark: false
        property bool twoLineItems: false
        property string comboClass: ""
        property var rawItems: []
        property color accent: red
        property int hoverIndex: -1
        font.pixelSize: twoLineItems ? 12 : 12
        font.bold: true
        leftPadding: 0
        rightPadding: 0
        indicator: VectorIcon { x: combo.width - 17.4 * root.sx; y: (combo.height - 10 * root.sy) / 2; width: 10.4 * root.sx; height: 10 * root.sy; iconName: combo.colored || combo.dark ? "caret-down-white" : "caret-down"; rotation: combo.popup.visible ? 180 : 0 }
        contentItem: Item {
            Text { x: combo.twoLineItems ? 7 * root.sx : 7 * root.sx; y: 0; width: parent.width - x - (combo.twoLineItems ? 19 * root.sx : 26 * root.sx); height: parent.height; text: combo.displayText; color: combo.colored || combo.dark ? "white" : ink; font: combo.font; verticalAlignment: Text.AlignVCenter; wrapMode: Text.NoWrap; maximumLineCount: combo.twoLineItems ? 2 : 1; elide: Text.ElideRight; lineHeight: 0.96 }
        }
        background: Rectangle { radius: 4; color: combo.colored ? combo.accent : (combo.dark ? grey : "white"); border.color: combo.colored ? combo.accent : ink; border.width: 1 }
        popup: Popup {
            y: combo.height
            width: combo.width
            implicitHeight: Math.min(comboList.contentHeight, combo.twoLineItems ? root.pdmPopupMaxHeight(combo) : 180 * root.sy)
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            contentItem: ListView {
                id: comboList
                property var comboOwner: combo
                clip: true
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.hoverIndex >= 0 ? combo.hoverIndex : combo.currentIndex
                ScrollBar.vertical: ScrollBar {
                    policy: combo.twoLineItems ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
                    width: combo.twoLineItems ? 0 : 12 * root.sx
                    contentItem: Rectangle { color: combo.twoLineItems ? "transparent" : "#B0000000" }
                    background: Rectangle { color: combo.twoLineItems ? "transparent" : "#16000000" }
                }
            }
            background: Rectangle { color: combo.colored || combo.dark ? combo.accent : "white"; border.color: combo.colored || combo.dark ? combo.accent : ink; border.width: combo.colored || combo.dark ? 0 : 1; radius: 4; Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 4 * root.sy; color: parent.color } }
        }
        delegate: Component {
            Item {
                readonly property var owner: ListView.view ? ListView.view.comboOwner : null
                width: owner ? owner.width : 240 * root.sx
                height: (owner && owner.twoLineItems ? 42 : 28) * root.sy
                readonly property bool highlighted: owner ? owner.hoverIndex === index : false
                Rectangle { anchors.fill: parent; color: parent.highlighted ? "#26FFFFFF" : (owner && (owner.colored || owner.dark) ? "transparent" : white) }
                Text { x: 7 * root.sx; y: 3 * root.sy; width: parent.width - x - 7 * root.sx; height: parent.height - 6 * root.sy; text: modelData; color: parent.highlighted ? white : (owner && (owner.colored || owner.dark) ? white : ink); font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignLeft; verticalAlignment: Text.AlignVCenter; wrapMode: Text.NoWrap; maximumLineCount: owner && owner.twoLineItems ? 2 : 1; elide: Text.ElideRight; lineHeight: 0.94 }
                MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: if (parent.owner) parent.owner.hoverIndex = index; onExited: if (parent.owner && parent.owner.hoverIndex === index) parent.owner.hoverIndex = -1; onClicked: { if (parent.owner) { parent.owner.currentIndex = index; parent.owner.activated(index); parent.owner.popup.close(); parent.owner.hoverIndex = -1 } } }
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
        color: ink
        font.pixelSize: 12
        font.bold: true
        horizontalAlignment: alignLeft ? TextInput.AlignLeft : TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        leftPadding: 7 * root.sx
        rightPadding: 7 * root.sx
        background: Rectangle { radius: 4; color: "white"; border.color: "#C9C9C9"; border.width: 1 }
        TapHandler { onTapped: parent.openKeyboard() }
    }

    component MeasureField: TextField {
        property string value: ""
        property string unit: ""
        property bool highlighted: false
        property bool editable: false
        property color fieldColor: "white"
        property color foregroundColor: ink
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
        rightPadding: Math.max(18 * root.sx, unitText.width + 8 * root.sx)
        background: Rectangle { radius: 4; color: parent.fieldColor; border.color: parent.highlighted ? purple : (parent.outlined ? red : "transparent"); border.width: parent.highlighted ? 3 : (parent.outlined ? 2 : 0) }
        Text { id: unitText; anchors.right: parent.right; anchors.rightMargin: 4 * root.sx; anchors.verticalCenter: parent.verticalCenter; text: parent.unit; color: parent.foregroundColor; font.pixelSize: 11; font.bold: true }
        TapHandler { enabled: parent.editable; onTapped: parent.openKeyboard() }
    }

    component FieldLabel: Text { property color textColor: ink; property bool singleLine: false; color: textColor; font.bold: true; font.pixelSize: 12; wrapMode: singleLine ? Text.NoWrap : Text.WordWrap; verticalAlignment: Text.AlignVCenter; elide: singleLine ? Text.ElideRight : Text.ElideNone }
    component InfoButton: Button { Accessible.name: qsTr("Show information"); contentItem: VectorIcon { anchors.centerIn: parent; width: 16 * root.sx; height: 16 * root.sy; iconName: "info-circle" } background: Rectangle { color: parent.down ? "#16000000" : "transparent"; radius: 4 } }
    component IconButton: Button { property string glyph: ""; property color base: charcoal; property color iconColor: "white"; property color borderColor: "transparent"; contentItem: VectorIcon { anchors.centerIn: parent; width: 14 * root.sx; height: 14 * root.sy; iconName: parent.glyph + (parent.iconColor === white || parent.iconColor === "white" ? "-white" : "") } background: Rectangle { radius: 4; color: parent.down ? Qt.darker(parent.base, 1.08) : parent.base; border.color: parent.borderColor; border.width: parent.borderColor === "transparent" ? 0 : 1 } }
    component ToggleButtonLike: Button { property color base: red; opacity: enabled ? 1 : 0.45; contentItem: Text { text: parent.text; color: "white"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideNone } background: Rectangle { radius: 4; color: parent.down ? Qt.darker(parent.base, 1.08) : parent.base; border.color: parent.base === green ? "#4A8B0A" : (parent.base === blue ? "#246C93" : "#8E1B0E"); border.width: 1 } }
    component ActionButton: Button { property color base: red; contentItem: Text { text: parent.text; color: "white"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap } background: Rectangle { radius: 4; color: parent.down ? Qt.darker(parent.base, 1.08) : parent.base } }
    component FooterButton: ActionButton {
        property string label: ""
        property string footerGlyph: ""
        property color textColor: "white"
        property bool leftRounded: false
        property bool rightRounded: false
        property bool allRounded: false
        opacity: enabled ? 1 : 0.42
        text: label
        background: Rectangle {
            color: parent.down ? Qt.darker(parent.base, 1.08) : parent.base
            radius: parent.allRounded || parent.leftRounded || parent.rightRounded ? 4 : 0
        }
        contentItem: Item {
            VectorIcon { id: footerIcon; visible: parent.parent.footerGlyph !== ""; x: 8 * root.sx; anchors.verticalCenter: parent.verticalCenter; width: 15 * root.sx; height: 15 * root.sy; iconName: parent.parent.footerGlyph + (parent.parent.textColor === white || parent.parent.textColor === "white" ? "-white" : "") }
            Text { x: footerIcon.visible ? 27 * root.sx : 7 * root.sx; y: 0; width: parent.width - x - 7 * root.sx; height: parent.height; text: parent.parent.label; color: parent.parent.textColor; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap; elide: Text.ElideNone; maximumLineCount: 2; lineHeight: 0.95 }
        }
    }
    component HighlightAngleLabel: Rectangle { radius: 4; color: purple; Rectangle { x: 5 * root.sx; anchors.verticalCenter: parent.verticalCenter; width: 24 * root.sx; height: 25.6 * root.sy; radius: 12; color: ink; Text { anchors.centerIn: parent; text: "deg"; color: "white"; font.bold: true; font.pixelSize: 11 } } Text { x: 32 * root.sx; y: 4 * root.sy; width: parent.width - 36 * root.sx; text: "DESIRED BEND ANGLE\nINCLUDED"; color: "white"; font.bold: true; font.pixelSize: 11; lineHeight: 0.9; elide: Text.ElideRight } }
    component WarningPanel: Item {
        Column {
            anchors.fill: parent
            spacing: 7 * root.sy
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
    component WarningLabel: Rectangle { property string text: ""; property color base: red; width: parent.width; height: 23.2 * root.sy; color: base; radius: 3; VectorIcon { x: 6 * root.sx; anchors.verticalCenter: parent.verticalCenter; width: 11 * root.sx; height: 11 * root.sy; iconName: "exclamation-triangle" } Text { anchors.left: parent.left; anchors.leftMargin: 23 * root.sx; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 29 * root.sx; text: parent.text; color: "white"; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight } }
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
        x: 7.2 * root.sx; width: 229 * root.sx; height: 30.4 * root.sy
        FieldLabel { x: 0; y: 0; width: calcRow.info ? 109 * root.sx : 139 * root.sx; height: parent.height; text: calcRow.label; textColor: calcRow.redLabel ? red : ink; font.pixelSize: 11 }
        InfoButton { visible: calcRow.info; x: 109 * root.sx; y: 0; width: 30 * root.sx; height: parent.height; onClicked: calcRow.infoClicked() }
        MeasureField {
            id: overriddenFinalPositionEditor
            objectName: calcRow.editableValue ? "create-bend-overridden-final-position-field" : ""
            x: 143.4 * root.sx; y: 0; width: 85.6 * root.sx; height: parent.height
            value: calcRow.value; unit: calcRow.unit; editable: calcRow.editableValue
            keyboardTitle: qsTr("FINAL BEND POSITION")
            fieldColor: calcRow.editableValue ? white : (calcRow.severity === "high" ? red : (calcRow.severity === "medium" ? orange : (calcRow.severity === "low" ? green : charcoal)))
            foregroundColor: calcRow.editableValue ? ink : white
            outlined: calcRow.editableValue
            onKeyboardCommitted: function(value) { calcRow.valueCommitted(value) }
        }
    }
    component NotesTitle: Rectangle { property string text: ""; property color base: red; property color textColor: "white"; property bool topRounded: false; color: base; radius: topRounded ? 6 : 0; Rectangle { visible: parent.topRounded; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: parent.radius; color: parent.color } Text { anchors.centerIn: parent; width: parent.width - 8 * root.sx; text: parent.text; color: parent.textColor; font.bold: true; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideNone; wrapMode: Text.WordWrap } }
    component NotesSubTitle: Rectangle { property string text: ""; color: paper; Text { anchors.centerIn: parent; text: parent.text; color: ink; font.bold: true; font.pixelSize: 12 } }
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
        ScrollBar.vertical.width: 8 * root.sx
        ScrollBar.vertical.contentItem: Rectangle { radius: width / 2; color: "#66000000" }
        ScrollBar.vertical.background: Rectangle { radius: width / 2; color: "#10000000" }
        background: Rectangle { color: "white"; border.color: "#D0D0D0"; border.width: 1; radius: notesScroll.bottomRounded ? 6 : 0; Rectangle { visible: notesScroll.bottomRounded; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: parent.radius; color: parent.color } }
        TextArea {
            id: notesText
            objectName: notesScroll.objectName + "-input"
            width: notesScroll.availableWidth
            selectByMouse: true
            wrapMode: TextEdit.WordWrap
            placeholderText: notesScroll.placeholderText
            placeholderTextColor: "#A8A8A8"
            color: ink
            font.pixelSize: 11
            padding: 4 * root.sx
            background: null
            TapHandler {
                onTapped: notesScroll.openKeyboard()
            }
        }
    }

    component SoftScrollBar: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: 8 * root.sx
            contentItem: Rectangle { radius: width / 2; color: "#66000000" }
            background: Rectangle { radius: width / 2; color: "#10000000" }
    }

    component StockIcon: Image {
        source: "../../../src/main/resources/images/icon-small.png"
        sourceSize.width: Math.max(1, width)
        sourceSize.height: Math.max(1, height)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
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

    component CaretGlyph: Shape {
        id: caretShape
        property color iconColor: ink
        ShapePath { fillColor: caretShape.iconColor; strokeWidth: 0; startX: 0; startY: 0; PathLine { x: caretShape.width; y: 0 } PathLine { x: caretShape.width / 2; y: caretShape.height } PathLine { x: 0; y: 0 } }
    }

    component IconGlyph: Shape {
        id: iconShape
        property string glyph: ""
        property color iconColor: white
        property real size: 12
        readonly property bool plusLike: glyph === "plus" || glyph === "list-plus"
        readonly property bool timesLike: glyph === "times"
        readonly property bool undoLike: glyph === "undo"
        width: size
        height: size

        ShapePath { fillColor: glyph === "pen" ? iconColor : "transparent"; strokeWidth: 0; startX: size * 0.18; startY: size * 0.72; PathLine { x: size * 0.25; y: size * 0.88 } PathLine { x: size * 0.42; y: size * 0.82 } PathLine { x: size * 0.84; y: size * 0.40 } PathLine { x: size * 0.70; y: size * 0.26 } PathLine { x: size * 0.28; y: size * 0.68 } PathLine { x: size * 0.18; y: size * 0.72 } }
        ShapePath { fillColor: glyph === "trash" ? iconColor : "transparent"; strokeWidth: 0; startX: size * 0.28; startY: size * 0.34; PathLine { x: size * 0.72; y: size * 0.34 } PathLine { x: size * 0.66; y: size * 0.88 } PathLine { x: size * 0.34; y: size * 0.88 } PathLine { x: size * 0.28; y: size * 0.34 } PathMove { x: size * 0.24; y: size * 0.25 } PathLine { x: size * 0.76; y: size * 0.25 } PathLine { x: size * 0.76; y: size * 0.32 } PathLine { x: size * 0.24; y: size * 0.32 } PathLine { x: size * 0.24; y: size * 0.25 } }
        ShapePath { fillColor: glyph === "save" ? iconColor : "transparent"; strokeWidth: 0; startX: size * 0.16; startY: size * 0.14; PathLine { x: size * 0.78; y: size * 0.14 } PathLine { x: size * 0.86; y: size * 0.24 } PathLine { x: size * 0.86; y: size * 0.86 } PathLine { x: size * 0.16; y: size * 0.86 } PathLine { x: size * 0.16; y: size * 0.14 } PathMove { x: size * 0.30; y: size * 0.58 } PathLine { x: size * 0.72; y: size * 0.58 } PathLine { x: size * 0.72; y: size * 0.86 } PathLine { x: size * 0.30; y: size * 0.86 } PathLine { x: size * 0.30; y: size * 0.58 } }
        ShapePath { fillColor: glyph === "duplicate" ? iconColor : "transparent"; strokeWidth: 0; startX: size * 0.18; startY: size * 0.22; PathLine { x: size * 0.56; y: size * 0.22 } PathLine { x: size * 0.56; y: size * 0.68 } PathLine { x: size * 0.18; y: size * 0.68 } PathLine { x: size * 0.18; y: size * 0.22 } PathMove { x: size * 0.38; y: size * 0.34 } PathLine { x: size * 0.78; y: size * 0.34 } PathLine { x: size * 0.78; y: size * 0.82 } PathLine { x: size * 0.38; y: size * 0.82 } PathLine { x: size * 0.38; y: size * 0.34 } }
        ShapePath { strokeColor: plusLike || timesLike ? iconColor : "transparent"; strokeWidth: plusLike || timesLike ? Math.max(2, size * 0.16) : 0; fillColor: "transparent"; startX: timesLike ? size * 0.25 : size * 0.50; startY: timesLike ? size * 0.25 : size * 0.20; PathLine { x: timesLike ? size * 0.75 : size * 0.50; y: timesLike ? size * 0.75 : size * 0.80 } PathMove { x: timesLike ? size * 0.75 : size * 0.20; y: timesLike ? size * 0.25 : size * 0.50 } PathLine { x: timesLike ? size * 0.25 : size * 0.80; y: timesLike ? size * 0.75 : size * 0.50 } }
        ShapePath { strokeColor: undoLike ? iconColor : "transparent"; strokeWidth: undoLike ? Math.max(2, size * 0.14) : 0; fillColor: "transparent"; startX: size * 0.78; startY: size * 0.72; PathLine { x: size * 0.54; y: size * 0.86 } PathLine { x: size * 0.28; y: size * 0.74 } PathLine { x: size * 0.20; y: size * 0.46 } PathLine { x: size * 0.38; y: size * 0.24 } PathLine { x: size * 0.66; y: size * 0.24 } PathMove { x: size * 0.36; y: size * 0.12 } PathLine { x: size * 0.18; y: size * 0.44 } PathLine { x: size * 0.50; y: size * 0.44 } }
        ShapePath { fillColor: glyph === "info" ? iconColor : "transparent"; strokeWidth: 0; startX: size * 0.50; startY: size * 0.08; PathArc { x: size * 0.50; y: size * 0.92; radiusX: size * 0.42; radiusY: size * 0.42; useLargeArc: true } PathArc { x: size * 0.50; y: size * 0.08; radiusX: size * 0.42; radiusY: size * 0.42; useLargeArc: true } PathMove { x: size * 0.46; y: size * 0.42 } PathLine { x: size * 0.56; y: size * 0.42 } PathLine { x: size * 0.56; y: size * 0.76 } PathLine { x: size * 0.46; y: size * 0.76 } PathLine { x: size * 0.46; y: size * 0.42 } }
        ShapePath { fillColor: glyph === "warning" ? iconColor : "transparent"; strokeWidth: 0; startX: size * 0.50; startY: size * 0.10; PathLine { x: size * 0.92; y: size * 0.86 } PathLine { x: size * 0.08; y: size * 0.86 } PathLine { x: size * 0.50; y: size * 0.10 } }
        ShapePath { strokeColor: glyph === "list-plus" ? iconColor : "transparent"; strokeWidth: glyph === "list-plus" ? Math.max(1, size * 0.10) : 0; fillColor: "transparent"; startX: size * 0.12; startY: size * 0.26; PathLine { x: size * 0.62; y: size * 0.26 } PathMove { x: size * 0.12; y: size * 0.46 } PathLine { x: size * 0.62; y: size * 0.46 } PathMove { x: size * 0.12; y: size * 0.66 } PathLine { x: size * 0.54; y: size * 0.66 } }
    }
}
