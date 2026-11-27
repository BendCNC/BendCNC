import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import "core/Units.js" as Units

Rectangle {
    id: root
    objectName: "manual-mode-view cad-import-view"
    property var appState: null
    property int draggedBendIndex: -1
    property int draggedBendTargetIndex: -1
    property int selectedBendIndex: -1
    onSelectedBendIndexChanged: if (appState) appState.cadSelectedBendIndex = selectedBendIndex
    LayoutMetrics { id: metrics }

    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color teal: "#1B7A5A"
    readonly property color charcoal: "#2B2C2B"
    readonly property color grey: "#A8A8A8"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color ink: "#232323"
    readonly property color white: "#FFFFFF"
    readonly property color orange: "orange"
    readonly property color cadWarning: "#F5A623"
    readonly property color darkTable: "#1F1F1F"
    readonly property color tableHeaderTop: "#F8FAFC"
    readonly property color tableHeaderBottom: "#E2E8F0"
    readonly property color tableGrid: "#CBD5E1"
    readonly property color tableCell: "#FFFFFF"
    readonly property color tableAlt: "#F1F5F9"
    readonly property var columns: metrics.cadTableColumns
    readonly property real columnWeightTotal: {
        var total = 0
        for (var i = 0; i < columns.length; i++) total += columns[i][1]
        return total
    }
    property real tableWidth: 0
    property real dragGhostY: 0
    // Header and rows share these widths so columns always line up; the last
    // column absorbs rounding so the row exactly fills the table.
    function colW(i) {
        if (tableWidth <= 0 || columnWeightTotal <= 0) return columns[i][1]
        if (i === columns.length - 1) {
            var used = 0
            for (var k = 0; k < i; k++) used += Math.floor(tableWidth * columns[k][1] / columnWeightTotal)
            return tableWidth - used
        }
        return Math.floor(tableWidth * columns[i][1] / columnWeightTotal)
    }
    function draggedBend() {
        if (!appState || !appState.cadBends || draggedBendIndex < 0 || draggedBendIndex >= appState.cadBends.length)
            return null
        return appState.cadBends[draggedBendIndex]
    }
    color: grey

    DataStore { id: dataStore }

    onAppStateChanged: {
        if (appState && appState.cadBends && appState.cadBends.length > 0 && selectedBendIndex < 0)
            selectedBendIndex = 0
    }

    Connections {
        target: root.appState
        function onCadBendsChanged() {
            if (!root.appState || !root.appState.cadBends || root.appState.cadBends.length === 0)
                root.selectedBendIndex = -1
            else
                root.selectedBendIndex = Math.max(0, Math.min(root.selectedBendIndex,
                                                               root.appState.cadBends.length - 1))
        }
    }

    function punchStackLabel(bend) {
        var widths = bend && bend.punchSegmentWidths ? bend.punchSegmentWidths : []
        if (widths.length === 0)
            return "-"
        var parts = []
        for (var i = 0; i < widths.length; i++)
            parts.push(String(Math.round(Number(widths[i]) * 100) / 100))
        var phase = Math.max(0, Math.round(Number(bend.toolingPhaseIndex) || 0))
        return "S" + (phase + 1) + ": " + parts.join("+")
    }

    function selectedBend() {
        if (!appState || !appState.cadBends || selectedBendIndex < 0 || selectedBendIndex >= appState.cadBends.length)
            return null
        return appState.cadBends[selectedBendIndex]
    }

    function moveSelected(offset) {
        if (!appState || !appState.cadBends || selectedBendIndex < 0)
            return
        var destination = selectedBendIndex + offset
        if (destination < 0 || destination >= appState.cadBends.length)
            return
        var from = selectedBendIndex
        selectedBendIndex = destination
        if (!appState.moveCadBend(from, destination))
            selectedBendIndex = from
    }

    property string importCurrentDirectory: ""
    property var importEntries: []

    function refreshImportEntries(path) {
        if (typeof fileIo === "undefined" || !fileIo)
            return
        var target = String(path || "")
        if (target.length === 0)
            target = fileIo.importDirectory()
        importCurrentDirectory = target
        importEntries = fileIo.directoryEntries(importCurrentDirectory)
        var root0 = fileIo.importDirectory()
        importRootFolders = (fileIo.directoryEntries(root0) || []).filter(function(e) { return e.directory })
            .sort(function(a, b) { return String(a.name).localeCompare(String(b.name), undefined, { numeric: true, sensitivity: "base" }) })
        importMessage = ""
    }

    property var importRootFolders: []
    property string importFilter: ""
    // Sort column (name/date/size/type) + direction; folders always first.
    property string importSortKey: "date"
    property bool importSortDesc: true
    function setImportSort(key) {
        if (importSortKey === key)
            importSortDesc = !importSortDesc
        else {
            importSortKey = key
            importSortDesc = key === "date" || key === "size"
        }
    }
    function importSortArrow(key) {
        return importSortKey === key ? (importSortDesc ? " ▼" : " ▲") : ""
    }
    function importExt(entry) {
        return entry.directory ? "" : String(entry.name).split(".").pop().toUpperCase()
    }
    function importRelativeDate(ms) {
        if (!ms)
            return ""
        var d = new Date(ms), now = new Date()
        var day0 = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        if (ms >= day0)
            return qsTr("Today ") + Qt.formatDateTime(d, "hh:mm")
        if (ms >= day0 - 86400000)
            return qsTr("Yesterday ") + Qt.formatDateTime(d, "hh:mm")
        return Qt.formatDateTime(d, "yyyy-MM-dd hh:mm")
    }
    function importSizeText(size) {
        size = size || 0
        return size >= 1048576 ? (size / 1048576).toFixed(1) + " MB" : (size / 1024).toFixed(1) + " KB"
    }
    property string importMessage: ""
    property bool importMessageError: false
    readonly property bool importCanOrganize: importCurrentDirectory.length > 0
        && importCurrentDirectory !== "assets/bcbends"
        && importCurrentDirectory.indexOf("assets/") !== 0
    readonly property var importVisibleEntries: {
        var query = importFilter.trim().toLowerCase()
        var list = (importEntries || []).filter(function(e) {
            return query.length === 0 || String(e.name).toLowerCase().indexOf(query) >= 0
        })
        var key = importSortKey, dir = importSortDesc ? -1 : 1
        var byName = function(a, b) {
            return String(a.name).localeCompare(String(b.name), undefined, { numeric: true, sensitivity: "base" })
        }
        list.sort(function(a, b) {
            if (a.directory !== b.directory)
                return a.directory ? -1 : 1
            var c = 0
            if (key === "date")
                c = (a.modified || 0) - (b.modified || 0)
            else if (key === "size")
                c = a.directory ? (a.count || 0) - (b.count || 0) : (a.size || 0) - (b.size || 0)
            else if (key === "type")
                c = importExt(a).localeCompare(importExt(b))
            if (c === 0)
                c = byName(a, b)
            return c * dir
        })
        return list
    }

    function importBreadcrumbs() {
        var path = String(importCurrentDirectory || "").replace(/\\/g, "/")
        var parts = path.split("/")
        var crumbs = []
        var acc = ""
        for (var i = 0; i < parts.length; i++) {
            if (parts[i].length === 0 && i > 0)
                continue
            acc = i === 0 ? (parts[0].length === 0 ? "/" : parts[0]) : (acc.endsWith("/") ? acc + parts[i] : acc + "/" + parts[i])
            crumbs.push({ name: parts[i].length === 0 ? "/" : parts[i], path: acc })
        }
        return crumbs
    }

    function importEntryDetail(entry) {
        if (entry.directory)
            return (entry.count || 0) + qsTr(" CAD files")
        var size = entry.size || 0
        var sizeText = size >= 1048576 ? (size / 1048576).toFixed(1) + " MB" : (size / 1024).toFixed(1) + " KB"
        var date = entry.modified ? Qt.formatDateTime(new Date(entry.modified), "yyyy-MM-dd hh:mm") : ""
        var ext = String(entry.name).split(".").pop().toUpperCase()
        return ext + "  ·  " + sizeText + (date.length ? "  ·  " + date : "")
    }

    function setImportMessage(text, error) {
        importMessage = text
        importMessageError = !!error
    }

    function openImportNameDialog(mode, entry) {
        importNameDialog.mode = mode
        importNameDialog.entry = entry
        importNameField.text = mode === "rename" && entry ? entry.name : ""
        importNameDialog.open()
    }

    function commitImportNameDialog() {
        var name = importNameField.text.trim()
        var ok = false
        if (importNameDialog.mode === "mkdir")
            ok = fileIo.makeDirectory(importCurrentDirectory, name)
        else if (importNameDialog.entry)
            ok = fileIo.renameEntry(importNameDialog.entry.path, name)
        if (!ok) {
            setImportMessage(qsTr("Invalid or existing name: ") + name, true)
            return
        }
        setImportMessage((importNameDialog.mode === "mkdir" ? qsTr("Folder created: ") : qsTr("Renamed to: ")) + name, false)
        importNameDialog.close()
        refreshImportEntries(importCurrentDirectory)
    }

    function openImportDeleteDialog(entry) {
        importDeleteDialog.entry = entry
        importDeleteDialog.open()
    }

    function commitImportDelete() {
        var entry = importDeleteDialog.entry
        importDeleteDialog.close()
        if (!entry)
            return
        if (fileIo.deleteEntry(entry.path))
            setImportMessage(qsTr("Deleted ") + entry.name, false)
        else
            setImportMessage(qsTr("Cannot delete ") + entry.name
                             + (entry.directory ? qsTr(" (folder not empty?)") : ""), true)
        refreshImportEntries(importCurrentDirectory)
    }

    function openImportMoveDialog(entry) {
        var targets = []
        var parentDir = fileIo.parentDirectory(importCurrentDirectory)
        if (parentDir && parentDir !== importCurrentDirectory)
            targets.push({ label: qsTr("▲ Parent folder"), path: parentDir })
        for (var i = 0; i < importEntries.length; i++) {
            var e = importEntries[i]
            if (e.directory && e.path !== entry.path)
                targets.push({ label: "📁 " + e.name, path: e.path })
        }
        importMoveDialog.entry = entry
        importMoveDialog.targets = targets
        importMoveDialog.open()
    }

    function commitImportMove(targetPath) {
        var entry = importMoveDialog.entry
        importMoveDialog.close()
        if (!entry)
            return
        if (fileIo.moveEntry(entry.path, targetPath))
            setImportMessage(qsTr("Moved ") + entry.name, false)
        else
            setImportMessage(qsTr("Cannot move ") + entry.name + qsTr(" (name exists?)"), true)
        refreshImportEntries(importCurrentDirectory)
    }

    component PickerButton: Rectangle {
        id: pickerButton
        property string label: ""
        property bool checked: false
        property color base: "#334155"
        property color hot: "#0284C7"
        signal clicked()
        Layout.preferredWidth: 90
        Layout.preferredHeight: 34
        radius: 4
        color: checked ? hot : (pickerMouse.containsMouse ? Qt.lighter(base, 1.3) : base)
        Text {
            anchors.centerIn: parent
            text: pickerButton.label
            color: "#FFFFFF"
            font.pixelSize: 12
            font.bold: true
        }
        MouseArea {
            id: pickerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pickerButton.clicked()
        }
    }

    function openImportPicker() {
        if (typeof fileIo !== "undefined" && fileIo && typeof fileIo.directoryEntries === "function") {
            if (importCurrentDirectory.length === 0) {
                if (fileIo.exists("assets/bcbends"))
                    importCurrentDirectory = "assets/bcbends"
                else
                    importCurrentDirectory = fileIo.importDirectory()
            }
            refreshImportEntries(importCurrentDirectory)
            cadImportPicker.open()
        } else {
            cadFileDialog.open()
        }
    }

    FileDialog {
        id: cadFileDialog
        title: "Select Fusion 360 bend file"
        nameFilters: ["BendCNC CAD files (*.bend *.bcbend)", "JSON files (*.json)", "All files (*)"]
        onAccepted: if (root.appState) root.appState.cadLoadFile(selectedFile, dataStore.punches, dataStore.dies, dataStore.materials, dataStore.userSettings)
    }

    // Planner tooling alternatives ranked by how closely they reproduce the CAD
    // sheet-metal rule radius; selecting one re-applies its collision-checked plan
    // (table + LIVE 3D preview) and stores it in the .bend.
    CadGeometryModal {
        id: cadGeometryModal
        cadJson: root.appState ? root.appState.cadLoadedJson : null
    }

    Popup {
        id: toolingOptionsPopup
        objectName: "cad-tooling-options-popup"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(980, root.width - 40)
        height: Math.min(470, root.height - 40)
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        readonly property var selection: root.appState && root.appState.cadUnfoldPlan
                                         ? root.appState.cadUnfoldPlan.toolingSelection : null
        background: Rectangle { color: "#1E293B"; radius: 8; border.color: "#475569"; border.width: 1 }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "TOOLING OPTIONS"
                    color: white; font.pixelSize: 15; font.bold: true
                }
                Text {
                    readonly property var s: toolingOptionsPopup.selection
                    text: s ? ("Design R " + Number(s.designInsideRadiusMm).toFixed(2) + " mm (±"
                               + Number(s.radiusToleranceMm).toFixed(2) + ")  t " + Number(s.thicknessMm).toFixed(2)
                               + " mm  min angle " + Number(s.includedAngleDegrees).toFixed(0) + "°  "
                               + s.viableCandidateCount + "/" + s.candidateCount + " pairs match design") : ""
                    color: "#CBD5E1"; font.pixelSize: 11
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                SequenceButton { label: "CLOSE"; onClicked: toolingOptionsPopup.close() }
            }
            Text {
                visible: !!(toolingOptionsPopup.selection && toolingOptionsPopup.selection.preferred
                            && !toolingOptionsPopup.selection.preferred.matchesDesign)
                text: visible ? "Material preference does not match the design: "
                                + toolingOptionsPopup.selection.preferred.reasons.join(", ") : ""
                color: cadWarning; font.pixelSize: 11
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                model: root.appState ? root.appState.cadToolingOptions : []
                delegate: Rectangle {
                    id: optionCard
                    required property var modelData
                    readonly property var meta: modelData.meta
                    readonly property var selection: toolingOptionsPopup.selection
                    width: 300
                    height: ListView.view.height
                    radius: 6
                    color: modelData.active ? "#0F3B2E" : "#273449"
                    border.color: modelData.active ? green : "#475569"
                    border.width: modelData.active ? 2 : 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        RowLayout {
                            spacing: 4
                            Repeater {
                                model: {
                                    var tags = []
                                    if (optionCard.modelData.active) tags.push(["ACTIVE", green])
                                    if (optionCard.meta.preferred) tags.push(["PREFERRED", "#0284C7"])
                                    var options = root.appState ? root.appState.cadToolingOptions : []
                                    var closest = true
                                    for (var i = 0; i < options.length; i++)
                                        if (Math.abs(options[i].meta.radiusErrorMm) < Math.abs(optionCard.meta.radiusErrorMm))
                                            closest = false
                                    if (closest) tags.push(["CLOSEST R", teal])
                                    if (!optionCard.meta.clear) tags.push(["NOT VIABLE", red])
                                    return tags
                                }
                                delegate: Rectangle {
                                    required property var modelData
                                    width: tagText.implicitWidth + 10; height: 16; radius: 3; color: modelData[1]
                                    Text { id: tagText; anchors.centerIn: parent; text: parent.modelData[0]
                                           color: white; font.pixelSize: 11; font.bold: true }
                                }
                            }
                        }
                        Text { text: optionCard.meta.dieName; color: white; font.pixelSize: 12; font.bold: true
                               Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: optionCard.meta.punchName; color: "#CBD5E1"; font.pixelSize: 11
                               Layout.fillWidth: true; elide: Text.ElideRight }
                        Canvas {
                            id: sectionCanvas
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.fillStyle = "#111827"; ctx.fillRect(0, 0, width, height)
                                var v = Number(optionCard.meta.openingMm), r = Number(optionCard.meta.predictedInsideRadiusMm)
                                var t = Number(optionCard.selection ? optionCard.selection.thicknessMm : 1)
                                var design = Number(optionCard.selection ? optionCard.selection.designInsideRadiusMm : r)
                                if (!(v > 0)) return
                                var s = width / (v * 2.2), cx = width / 2, top = height * 0.55
                                var dieHalf = Math.tan(Math.max(15, Number(optionCard.meta.dieAngleDegrees || 30)) * Math.PI / 360)
                                var depth = (v / 2) / Math.max(0.2, dieHalf)
                                // Die V and shoulders
                                ctx.fillStyle = "#64748B"; ctx.beginPath()
                                ctx.moveTo(cx - v * 1.05 * s, top); ctx.lineTo(cx - v / 2 * s, top)
                                ctx.lineTo(cx, top + Math.min(depth * s, height - top - 4))
                                ctx.lineTo(cx + v / 2 * s, top); ctx.lineTo(cx + v * 1.05 * s, top)
                                ctx.lineTo(cx + v * 1.05 * s, height); ctx.lineTo(cx - v * 1.05 * s, height)
                                ctx.closePath(); ctx.fill()
                                // Sheet in air bend with predicted inside radius
                                var sag = Math.min((r + t) * s * 1.2, height * 0.25)
                                ctx.strokeStyle = "#F59E0B"; ctx.lineWidth = Math.max(2, t * s)
                                ctx.beginPath(); ctx.moveTo(cx - v * 1.0 * s, top - t * s / 2 - sag * 0.15)
                                ctx.quadraticCurveTo(cx, top + sag, cx + v * 1.0 * s, top - t * s / 2 - sag * 0.15); ctx.stroke()
                                // Punch tip
                                ctx.fillStyle = "#94A3B8"; ctx.beginPath()
                                var tipY = top + sag - t * s * 1.1
                                ctx.moveTo(cx - v * 0.35 * s, 0); ctx.lineTo(cx, tipY); ctx.lineTo(cx + v * 0.35 * s, 0)
                                ctx.closePath(); ctx.fill()
                                ctx.fillStyle = white; ctx.font = "11px sans-serif"
                                ctx.fillText("V " + v.toFixed(1) + " mm", 4, height - 6)
                                ctx.fillText("Ri " + r.toFixed(2) + " / design " + design.toFixed(2), 4, 12)
                            }
                            Component.onCompleted: requestPaint()
                            onWidthChanged: requestPaint()
                        }
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Repeater {
                                model: [
                                    ["Predicted Ri", Number(optionCard.meta.predictedInsideRadiusMm).toFixed(2) + " mm ("
                                     + (optionCard.meta.radiusErrorMm >= 0 ? "+" : "") + Number(optionCard.meta.radiusErrorMm).toFixed(2) + ")"],
                                    ["Outside R", (Number(optionCard.meta.predictedInsideRadiusMm)
                                                   + Number(optionCard.selection ? optionCard.selection.thicknessMm : 0)).toFixed(2) + " mm"],
                                    ["Tonnage", optionCard.meta.tonnagePerMeterKn !== null && optionCard.meta.tonnagePerMeterKn !== undefined
                                                ? Number(optionCard.meta.tonnagePerMeterKn).toFixed(0) + " kN/m" : "-"],
                                    ["Min flange", Number(optionCard.meta.minFlangeMm).toFixed(1) + " mm"],
                                    ["Strokes / setups", optionCard.meta.stageCount + " / " + optionCard.meta.setupCount],
                                    ["Route", optionCard.meta.clear ? "collision-free" : String(optionCard.meta.status)]
                                ]
                                delegate: Text {
                                    required property var modelData
                                    text: modelData[0] + ":  " + modelData[1]
                                    color: "#E2E8F0"; font.pixelSize: 11
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                        SequenceButton {
                            objectName: "cad-tooling-option-use"
                            label: optionCard.modelData.active ? "IN USE" : "USE + PREVIEW"
                            enabledValue: !optionCard.modelData.active && optionCard.modelData.available
                            base: teal
                            Layout.fillWidth: true
                            onClicked: if (root.appState) root.appState.selectCadToolingAlternative(optionCard.modelData.index)
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: cadImportPicker
        objectName: "cad-import-picker"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(1000, root.width - 40)
        height: Math.min(640, root.height - 40)
        modal: true
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            color: "#1E293B"
            radius: 8
            border.color: "#475569"
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: qsTr("IMPORT FUSION 360 / CAD FILE")
                    color: white
                    font.pixelSize: 17
                    font.bold: true
                }
                Text {
                    text: root.importVisibleEntries.length + qsTr(" items")
                    color: "#64748B"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                PickerButton {
                    label: "✕"
                    base: "#334155"
                    hot: "#EF4444"
                    Layout.preferredWidth: 36
                    onClicked: cadImportPicker.close()
                }
            }

            // Locations + folder actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                PickerButton {
                    label: qsTr("IMPORTS")
                    checked: root.importCurrentDirectory === fileIo.importDirectory()
                    onClicked: root.refreshImportEntries(fileIo.importDirectory())
                }
                PickerButton {
                    label: qsTr("SAMPLES")
                    visible: typeof fileIo !== "undefined" && fileIo && fileIo.exists("assets/bcbends")
                    onClicked: root.refreshImportEntries("assets/bcbends")
                }
                PickerButton {
                    label: qsTr("USB")
                    onClicked: {
                        var usbCandidates = ["/media", "/mnt", "D:/", "E:/", "F:/"]
                        for (var i = 0; i < usbCandidates.length; i++) {
                            if (fileIo.exists(usbCandidates[i])) {
                                root.refreshImportEntries(usbCandidates[i])
                                return
                            }
                        }
                        root.refreshImportEntries("/media")
                    }
                }
                Item { Layout.fillWidth: true }
                PickerButton {
                    objectName: "cad-import-new-folder"
                    label: qsTr("+ NEW FOLDER")
                    base: "#0F766E"
                    hot: "#14B8A6"
                    Layout.preferredWidth: 120
                    onClicked: root.openImportNameDialog("mkdir", null)
                }
                PickerButton {
                    label: qsTr("BROWSE (PC)...")
                    Layout.preferredWidth: 120
                    onClicked: {
                        cadImportPicker.close()
                        cadFileDialog.open()
                    }
                }
            }

            // Breadcrumb + search + sort
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                PickerButton {
                    objectName: "cad-import-up"
                    label: qsTr("▲ UP")
                    Layout.preferredWidth: 64
                    onClicked: root.refreshImportEntries(fileIo.parentDirectory(root.importCurrentDirectory))
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: 4
                    color: "#0F172A"
                    border.color: "#334155"
                    Flickable {
                        id: crumbFlick
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        contentWidth: crumbRow.width
                        clip: true
                        onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
                        Row {
                            id: crumbRow
                            height: parent.height
                            spacing: 2
                            Repeater {
                                model: root.importBreadcrumbs()
                                delegate: Row {
                                    required property var modelData
                                    required property int index
                                    height: crumbRow.height
                                    Text {
                                        visible: index > 0
                                        text: " › "
                                        color: "#475569"
                                        font.pixelSize: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: modelData.name
                                        color: crumbMouse.containsMouse ? "#7DD3FC" : "#CBD5E1"
                                        font.pixelSize: 13
                                        font.bold: index === root.importBreadcrumbs().length - 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            id: crumbMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshImportEntries(modelData.path)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                TextField {
                    id: importSearch
                    objectName: "cad-import-search"
                    Layout.preferredWidth: 170
                    Layout.preferredHeight: 34
                    placeholderText: qsTr("Search...")
                    color: white
                    placeholderTextColor: "#64748B"
                    font.pixelSize: 13
                    background: Rectangle { radius: 4; color: "#0F172A"; border.color: importSearch.activeFocus ? "#38BDF8" : "#334155" }
                    onTextChanged: root.importFilter = text
                }
                Repeater {
                    model: [{ k: "name", t: qsTr("NAME") }, { k: "date", t: qsTr("DATE") },
                            { k: "size", t: qsTr("SIZE") }, { k: "type", t: qsTr("TYPE") }]
                    delegate: PickerButton {
                        required property var modelData
                        objectName: "cad-import-sort-" + modelData.k
                        label: modelData.t + root.importSortArrow(modelData.k)
                        checked: root.importSortKey === modelData.k
                        Layout.preferredWidth: 72
                        onClicked: root.setImportSort(modelData.k)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

            // Folder sidebar: one tap to any folder of the imports library.
            Rectangle {
                Layout.preferredWidth: 190
                Layout.fillHeight: true
                color: "#0F172A"
                radius: 6
                border.color: "#334155"
                clip: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    Text {
                        text: qsTr("FOLDERS")
                        color: "#64748B"
                        font.pixelSize: 11
                        font.bold: true
                        Layout.leftMargin: 4
                    }
                    ListView {
                        id: folderSidebar
                        objectName: "cad-import-folder-sidebar"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: [{ name: qsTr("All imports"), path: fileIo.importDirectory(), root: true }].concat(root.importRootFolders)
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            id: folderItem
                            required property var modelData
                            readonly property bool current: String(root.importCurrentDirectory).replace(/\\/g, "/") === String(modelData.path).replace(/\\/g, "/")
                            width: folderSidebar.width
                            height: 34
                            radius: 4
                            color: current ? "#0369A1" : (folderMouse.containsMouse ? "#1E3A5F" : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text { text: folderItem.modelData.root ? "🏠" : "📁"; font.pixelSize: 13 }
                                Text {
                                    text: folderItem.modelData.name
                                    color: folderItem.current ? "white" : "#CBD5E1"
                                    font.pixelSize: 13
                                    font.bold: folderItem.current
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: !folderItem.modelData.root
                                    text: String(folderItem.modelData.count || 0)
                                    color: "#64748B"
                                    font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                id: folderMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.refreshImportEntries(folderItem.modelData.path)
                            }
                        }
                    }
                }
            }

            // File list
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0F172A"
                radius: 6
                border.color: "#334155"
                border.width: 1
                clip: true

                ListView {
                    id: importFileList
                    objectName: "cad-import-file-list"
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    spacing: 2
                    model: root.importVisibleEntries
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: fileItem
                        required property var modelData
                        width: importFileList.width
                        height: 44
                        radius: 4
                        color: fileItemMouse.containsMouse ? (modelData.directory ? "#334155" : "#1E3A5F") : "#111C33"

                        MouseArea {
                            id: fileItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (fileItem.modelData.directory) {
                                    root.refreshImportEntries(fileItem.modelData.path)
                                    return
                                }
                                cadImportPicker.close()
                                if (root.appState) {
                                    var targetUrl = fileIo.localFileUrl(fileItem.modelData.path)
                                    root.appState.cadLoadFile(targetUrl, dataStore.punches, dataStore.dies, dataStore.materials, dataStore.userSettings)
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: 6
                                color: fileItem.modelData.directory ? "#0C4A6E" : "#422006"
                                Text {
                                    anchors.centerIn: parent
                                    text: fileItem.modelData.directory ? "📁" : "📄"
                                    font.pixelSize: 16
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 120
                                spacing: 1
                                Text {
                                    text: fileItem.modelData.name
                                    color: fileItem.modelData.directory ? "#7DD3FC" : white
                                    font.pixelSize: 14
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: (fileItem.modelData.directory ? (fileItem.modelData.count || 0) + qsTr(" files") : root.importSizeText(fileItem.modelData.size))
                                          + "   ·   " + root.importRelativeDate(fileItem.modelData.modified)
                                    color: "#94A3B8"
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }

                            PickerButton {
                                label: "✎"
                                visible: root.importCanOrganize
                                Layout.preferredWidth: 34
                                onClicked: root.openImportNameDialog("rename", fileItem.modelData)
                            }
                            PickerButton {
                                label: "⇄"
                                visible: root.importCanOrganize
                                Layout.preferredWidth: 34
                                onClicked: root.openImportMoveDialog(fileItem.modelData)
                            }
                            PickerButton {
                                objectName: "cad-import-delete-button"
                                label: "✕"
                                visible: root.importCanOrganize
                                base: "#7F1D1D"
                                hot: "#DC2626"
                                Layout.preferredWidth: 34
                                onClicked: root.openImportDeleteDialog(fileItem.modelData)
                            }
                            Text {
                                text: fileItem.modelData.directory ? "›" : "OPEN"
                                color: fileItem.modelData.directory ? "#7DD3FC" : "#F59E0B"
                                font.pixelSize: fileItem.modelData.directory ? 22 : 11
                                font.bold: true
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: importFileList.count === 0
                        text: root.importFilter.length > 0
                              ? qsTr("No files match \"") + root.importFilter + "\""
                              : qsTr("No .bend, .bcbend or .json files found in this folder")
                        color: "#64748B"
                        font.pixelSize: 14
                    }
                }
            }
            }

            Text {
                Layout.fillWidth: true
                text: root.importMessage
                visible: text.length > 0
                color: root.importMessageError ? "#F87171" : "#4ADE80"
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        // New folder / rename
        Popup {
            id: importNameDialog
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 420
            height: 170
            modal: true
            closePolicy: Popup.CloseOnEscape
            property string mode: "mkdir"
            property var entry: null
            onOpened: { importNameField.forceActiveFocus(); importNameField.selectAll() }
            background: Rectangle { color: "#1E293B"; radius: 8; border.color: "#38BDF8" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Text {
                    text: importNameDialog.mode === "mkdir" ? qsTr("NEW FOLDER") : qsTr("RENAME")
                    color: white
                    font.pixelSize: 15
                    font.bold: true
                }
                TextField {
                    id: importNameField
                    objectName: "cad-import-name-field"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: white
                    font.pixelSize: 14
                    background: Rectangle { radius: 4; color: "#0F172A"; border.color: "#38BDF8" }
                    onAccepted: root.commitImportNameDialog()
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PickerButton { label: qsTr("CANCEL"); Layout.preferredWidth: 90; onClicked: importNameDialog.close() }
                    PickerButton {
                        label: qsTr("OK")
                        base: "#0F766E"
                        hot: "#14B8A6"
                        Layout.preferredWidth: 90
                        onClicked: root.commitImportNameDialog()
                    }
                }
            }
        }

        // Delete confirmation
        Popup {
            id: importDeleteDialog
            objectName: "cad-import-delete-dialog"
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 440
            height: 190
            modal: true
            closePolicy: Popup.CloseOnEscape
            property var entry: null
            background: Rectangle { color: "#1E293B"; radius: 8; border.color: "#DC2626" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Text {
                    text: importDeleteDialog.entry && importDeleteDialog.entry.directory
                          ? qsTr("DELETE FOLDER?") : qsTr("DELETE FILE?")
                    color: white
                    font.pixelSize: 15
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: importDeleteDialog.entry ? importDeleteDialog.entry.name : ""
                    color: "#FCA5A5"
                    font.pixelSize: 14
                    elide: Text.ElideMiddle
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("This cannot be undone.")
                    color: "#94A3B8"
                    font.pixelSize: 12
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PickerButton { label: qsTr("CANCEL"); Layout.preferredWidth: 90; onClicked: importDeleteDialog.close() }
                    PickerButton {
                        objectName: "cad-import-delete-confirm"
                        label: qsTr("DELETE")
                        base: "#7F1D1D"
                        hot: "#DC2626"
                        Layout.preferredWidth: 90
                        onClicked: root.commitImportDelete()
                    }
                }
            }
        }

        // Move into a sub-folder or the parent folder
        Popup {
            id: importMoveDialog
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: 440
            height: 380
            modal: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            property var entry: null
            property var targets: []
            background: Rectangle { color: "#1E293B"; radius: 8; border.color: "#38BDF8" }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8
                Text {
                    text: qsTr("MOVE ") + (importMoveDialog.entry ? importMoveDialog.entry.name : "") + qsTr(" TO")
                    color: white
                    font.pixelSize: 15
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    model: importMoveDialog.targets
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 40
                        radius: 4
                        color: moveMouse.containsMouse ? "#1E3A5F" : "#0F172A"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            text: modelData.label
                            color: "#7DD3FC"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            id: moveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.commitImportMove(modelData.path)
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        text: qsTr("No folders here - create one with + NEW FOLDER")
                        color: "#64748B"
                        font.pixelSize: 13
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PickerButton { label: qsTr("CANCEL"); Layout.preferredWidth: 90; onClicked: importMoveDialog.close() }
                }
            }
        }
    }

    Item { objectName: "manual-mode-view, cad-import-view button-run-manual-stroke, cad-import-button button-tonnage-hold, cad-generate-button"; visible: false }

    // CAD file processing progress; blocks input until the staged load ends.
    Rectangle {
        objectName: "cad-import-progress"
        anchors.fill: parent
        z: 100
        visible: root.appState ? root.appState.cadLoadBusy : false
        color: "#B0000000"
        MouseArea { anchors.fill: parent; hoverEnabled: true; preventStealing: true }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(520, parent.width - 40)
            height: 150
            radius: 8
            color: "#1E293B"
            border.color: "#38BDF8"
            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                Text {
                    text: "Processing CAD file..."
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: root.appState ? root.appState.cadLoadStage : ""
                    color: "#CBD5E1"
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: parent.width
                    height: 14
                    radius: 7
                    clip: true
                    color: "#334155"
                    Rectangle {
                        width: parent.width * (root.appState ? root.appState.cadLoadProgress : 0)
                        height: parent.height
                        radius: 7
                        color: "#38BDF8"
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                    // Moving sheen: shows the worker is alive between stages.
                    Rectangle {
                        width: 40
                        height: parent.height
                        radius: 7
                        color: "#80FFFFFF"
                        SequentialAnimation on x {
                            running: root.appState ? root.appState.cadLoadBusy : false
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 480; duration: 1200 }
                        }
                    }
                }
                Text {
                    text: Math.round((root.appState ? root.appState.cadLoadProgress : 0) * 100) + " %"
                    color: "#94A3B8"
                    font.pixelSize: 12
                }
            }
        }
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: metrics.standardMargin
        columns: 1
        rowSpacing: metrics.cadPanelGap
        columnSpacing: 0

        // CAD import + part info merged into one compact panel so the bend
        // sequence table gets the remaining height.
        PartInfoPanel {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            Layout.minimumHeight: 150
            Layout.maximumHeight: 150
        }
        BendSequencePanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: metrics.cadPanelHeights[2]
        }
        GeneratePanel {
            Layout.fillWidth: true
            Layout.preferredHeight: metrics.cadPanelHeights[3]
            Layout.minimumHeight: metrics.cadPanelHeights[3]
            Layout.maximumHeight: metrics.cadPanelHeights[3]
        }
    }

    // -------------------------------------------------------------------------
    // Shared Structural Components
    // -------------------------------------------------------------------------
    component ManualHeader: Rectangle {
        property string title: ""
        property string subtitle: ""
        property color base: "#2D83B2"
        property int titleSize: 15
        objectName: "header label-title label-subtitle"
        Layout.fillWidth: true
        Layout.preferredHeight: 33
        Layout.minimumHeight: 33
        Layout.maximumHeight: 33
        radius: metrics.panelRadius
        color: base

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: metrics.panelRadius
            color: parent.base
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            Text { text: title; color: white; font.pixelSize: titleSize; font.bold: true }
            Text { text: subtitle; color: "#E2E8F0"; font.pixelSize: 13; font.bold: true; visible: subtitle.length > 0 }
        }
    }

    component ManualBody: Rectangle {
        default property alias content: inner.data
        property int inset: 7
        objectName: "body"
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: lightGrey
        radius: metrics.panelRadius

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: metrics.panelRadius
            color: lightGrey
        }

        Item { id: inner; anchors.fill: parent; anchors.margins: inset }
    }

    // -------------------------------------------------------------------------
    // 1. CAD IMPORT PANEL
    // -------------------------------------------------------------------------
    component CadImportPanel: ColumnLayout {
        objectName: "panel-set-temp-tonnage-limit"
        spacing: 0
        ManualHeader { title: "CAD IMPORT" }
        ManualBody {
            inset: 6
            RowLayout {
                anchors.fill: parent
                spacing: 12

                ActionButton {
                    objectName: "button-run-manual-stroke cad-import-button buttonLoadFile"
                    label: "IMPORT FUSION 360"
                    iconSource: "icons/fa-file-white.svg"
                    colorValue: teal
                    Layout.preferredWidth: metrics.cadImportButtonWidth
                    Layout.minimumWidth: metrics.cadImportButtonWidth
                    Layout.maximumWidth: metrics.cadImportButtonWidth
                    Layout.fillHeight: true
                    onClicked: root.openImportPicker()
                }

                Text {
                    objectName: "label-line2 labelFileName"
                    text: root.appState && root.appState.cadFileName ? root.appState.cadFileName : "No file imported"
                    color: root.appState && root.appState.cadFileName ? ink : "#64748B"
                    font.pixelSize: 13
                    font.bold: true
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // 2. PART INFO PANEL
    // -------------------------------------------------------------------------
    component PartInfoPanel: ColumnLayout {
        objectName: "panel-manual-stroke-operation"
        spacing: 0
        ManualHeader { title: "PART INFO"; base: red; titleSize: 15 }
        ManualBody {
            inset: 7
            GridLayout {
                anchors.fill: parent
                columns: 4
                columnSpacing: 10
                rowSpacing: 4

                ActionButton {
                    objectName: "button-run-manual-stroke cad-import-button buttonLoadFile"
                    label: "IMPORT FUSION 360"
                    iconSource: "icons/fa-file-white.svg"
                    colorValue: teal
                    Layout.row: 0; Layout.column: 0; Layout.columnSpan: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    onClicked: root.openImportPicker()
                }
                Text {
                    objectName: "label-line2 labelFileName"
                    text: root.appState && root.appState.cadFileName ? root.appState.cadFileName : "No file imported"
                    color: root.appState && root.appState.cadFileName ? ink : "#64748B"
                    font.pixelSize: 13
                    font.bold: true
                    Layout.row: 0; Layout.column: 2; Layout.columnSpan: 2
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }

                InfoLabel { label: "Part:"; Layout.row: 1; Layout.column: 0 }
                ValueLabel {
                    objectName: "labelPartName label-line2"
                    value: root.appState && root.appState.cadPartName ? root.appState.cadPartName : "-"
                    dimmed: !(root.appState && root.appState.cadPartName)
                    Layout.row: 1
                    Layout.column: 1
                    Layout.fillWidth: true
                }

                InfoLabel { label: "Program:"; Layout.row: 1; Layout.column: 2 }
                TextFieldBox {
                    objectName: "cad-program-name-field textProgramName"
                    value: root.appState ? root.appState.cadProgramName : "Program name"
                    Layout.row: 1
                    Layout.column: 3
                    Layout.fillWidth: true
                    onValueEdited: function(newValue) {
                        if (root.appState)
                            root.appState.cadProgramName = newValue
                    }
                }

                InfoLabel { label: "Material:"; Layout.row: 2; Layout.column: 0 }
                ValueLabel {
                    objectName: "labelMaterial label-line2"
                    value: root.appState && root.appState.cadMaterial ? root.appState.cadMaterial : "-"
                    dimmed: !(root.appState && root.appState.cadMaterial)
                    Layout.row: 2
                    Layout.column: 1
                }

                InfoLabel { label: "Thickness:"; Layout.row: 2; Layout.column: 2 }
                ValueLabel {
                    objectName: "labelThickness label-line2"
                    value: root.appState && root.appState.cadThickness ? root.appState.cadThickness : "-"
                    dimmed: !(root.appState && root.appState.cadThickness)
                    Layout.row: 2
                    Layout.column: 3
                }

                InfoLabel { label: "Flat Pattern:"; Layout.row: 3; Layout.column: 0 }
                ValueLabel {
                    objectName: "labelFlatPattern label-line2"
                    value: root.appState && root.appState.cadFlatPattern ? root.appState.cadFlatPattern : "-"
                    dimmed: !(root.appState && root.appState.cadFlatPattern)
                    Layout.row: 3
                    Layout.column: 1
                }

                InfoLabel { label: "Status:"; Layout.row: 3; Layout.column: 2 }
                ValueLabel {
                    objectName: "labelStatus label-line2"
                    value: root.appState && root.appState.cadStatusMessage ? root.appState.cadStatusMessage : "No file loaded"
                    warning: root.appState ? root.appState.cadHasErrors : false
                    dimmed: !(root.appState && root.appState.cadImported)
                    Layout.row: 3
                    Layout.column: 3
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // 3. BEND SEQUENCE PANEL (Tactile Drag & Arrange Table)
    // -------------------------------------------------------------------------
    component BendSequencePanel: ColumnLayout {
        objectName: "panel-set-temp-tonnage-limit"
        spacing: 0
        ManualHeader {
            title: "BEND SEQUENCE"
            subtitle: "(" + (root.appState && root.appState.cadBendCount ? root.appState.cadBendCount : 0) + " bends)"

            SequenceButton {
                objectName: "cad-geometry-view-button"
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                width: 120
                label: "VIEW FLAT / 3D"
                enabledValue: !!(root.appState && root.appState.cadLoadedJson
                                 && (root.appState.cadLoadedJson.flatPattern
                                     || root.appState.cadLoadedJson.sheetMetalGraph))
                base: "#0D9488"
                onClicked: cadGeometryModal.open()
            }
        }
        ManualBody {
            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                // Top sequence control bar
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    spacing: 6

                    SequenceButton {
                        label: "▲ UP"
                        enabledValue: root.selectedBendIndex > 0
                        onClicked: root.moveSelected(-1)
                    }
                    SequenceButton {
                        label: "▼ DOWN"
                        enabledValue: root.appState && root.appState.cadBends && root.selectedBendIndex >= 0
                                      && root.selectedBendIndex < root.appState.cadBends.length - 1
                        onClicked: root.moveSelected(1)
                    }
                    SequenceButton {
                        label: root.selectedBend() && root.selectedBend().locked ? "🔓 UNLOCK / AUTO" : "🔒 LOCK STEP"
                        enabledValue: root.selectedBendIndex >= 0
                        Layout.preferredWidth: 125
                        onClicked: if (root.appState) root.appState.toggleCadBendLock(root.selectedBendIndex)
                    }
                    SequenceButton {
                        label: "RESTORE SUGGESTED"
                        enabledValue: root.appState && root.appState.cadManualSequenceOverride
                        Layout.preferredWidth: 145
                        base: teal
                        onClicked: {
                            if (root.appState && root.appState.restoreCadSuggestedOrder())
                                root.selectedBendIndex = (root.appState.cadBends && root.appState.cadBends.length > 0) ? 0 : -1
                        }
                    }

                    SequenceButton {
                        objectName: "cad-tooling-options-button"
                        readonly property int optionCount: root.appState && root.appState.cadToolingOptions
                                                           ? root.appState.cadToolingOptions.length : 0
                        label: "TOOLING OPTIONS (" + optionCount + ")"
                        enabledValue: optionCount > 0
                        Layout.preferredWidth: 135
                        base: "#0284C7"
                        onClicked: toolingOptionsPopup.open()
                    }

                    SequenceButton {
                        objectName: "cad-rerun-planner-button"
                        readonly property bool planning: root.appState && root.appState.cadUnfoldState === "planning"
                        label: planning ? "PLANNING..." : "RE-RUN PLANNER"
                        enabledValue: !!(root.appState && root.appState.cadUnfoldPlannerAvailable
                                         && root.appState.cadUnfoldFileUrl.length > 0 && !planning)
                        Layout.preferredWidth: 135
                        base: "#7C3AED"
                        onClicked: root.appState.rerunCadUnfoldPlan()
                    }


                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.draggedBendIndex >= 0 && root.draggedBend()
                              ? ("MOVING BEND " + String(root.draggedBend().id) + " → STEP " + String(root.draggedBendTargetIndex + 1))
                              : root.selectedBendIndex >= 0 ? ("STEP " + String(root.selectedBendIndex + 1) + " SELECTED") : "SELECT A STEP"
                        color: root.draggedBendIndex >= 0 ? "#0284C7" : (root.selectedBendIndex >= 0 ? teal : "#64748B")
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                // Table Container
                Rectangle {
                    objectName: "cad-bend-table tableBends"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#F8FAFC"
                    border.color: tableGrid
                    border.width: 1
                    radius: 3
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Table Column Headers
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 25
                            spacing: 0
                            Repeater {
                                model: columns
                                TableHeader {
                                    label: modelData[0]
                                    Layout.preferredWidth: root.colW(index)
                                }
                            }
                        }

                        // Scrollable Rows Body
                        Rectangle {
                            id: tableBodyRect
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#FFFFFF"
                            clip: true
                            onWidthChanged: root.tableWidth = width
                            Component.onCompleted: root.tableWidth = width

                            Flickable {
                                id: tableFlickable
                                anchors.fill: parent
                                contentWidth: width
                                contentHeight: bendsColumn.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: root.draggedBendIndex < 0

                                // Floating ghost of the dragged bend that follows the finger/cursor.
                                Rectangle {
                                    visible: root.draggedBendIndex >= 0 && root.draggedBendTargetIndex !== root.draggedBendIndex
                                    z: 50
                                    x: 2
                                    width: bendsColumn.width - 4
                                    height: 31
                                    y: Math.max(0, Math.min(bendsColumn.height - height, root.dragGhostY - height / 2))
                                    radius: 3
                                    color: "#E0F2FE"
                                    opacity: 0.95
                                    border.color: "#0284C7"
                                    border.width: 2
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.draggedBend()
                                              ? ("≡  BEND " + String(root.draggedBend().id) + "  ·  " + (root.draggedBend().angle || "-") + "°  ·  "
                                                 + (root.draggedBend().width || "-") + "\"   →   STEP " + String(root.draggedBendTargetIndex + 1))
                                              : ""
                                        color: "#075985"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                Column {
                                    id: bendsColumn
                                    width: parent.width
                                    spacing: 0

                                    Repeater {
                                        model: root.appState ? root.appState.cadBends : []

                                        Item {
                                            id: bendRow
                                            objectName: "cad-bend-row-" + String(index)
                                            width: bendsColumn.width
                                            height: 31 + bendRow.toolChangeHeight
                                            required property int index
                                            required property var modelData
                                            readonly property var bend: modelData
                                            // Visual TOOL CHANGE step before this bend; does not alter sequence numbers.
                                            readonly property var toolChange: root.appState ? root.appState.toolChangeBeforeBend(root.appState.cadBends, bendRow.index) : null
                                            readonly property real toolChangeHeight: toolChange ? 26 : 0

                                            Rectangle {
                                                objectName: "cad-tool-change-row-" + String(bendRow.index)
                                                visible: !!bendRow.toolChange
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                height: bendRow.toolChangeHeight
                                                color: "#FFFBEB"
                                                // Dashed-look separators above/below
                                                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: "#FCD34D" }
                                                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: "#FCD34D" }
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    height: 1
                                                    color: "#F59E0B"
                                                    opacity: 0.45
                                                }
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: Math.min(parent.width - 24, tcRowContent.implicitWidth + 24)
                                                    height: parent.height - 6
                                                    radius: height / 2
                                                    color: "#F59E0B"
                                                    Row {
                                                        id: tcRowContent
                                                        anchors.centerIn: parent
                                                        spacing: 8
                                                        Text {
                                                            text: "\u21C4  " + (bendRow.toolChange && bendRow.toolChange.title ? bendRow.toolChange.title : "TOOL CHANGE")
                                                            color: "#1C1917"
                                                            font.pixelSize: 11
                                                            font.bold: true
                                                            font.letterSpacing: 0.6
                                                        }
                                                        Rectangle { width: 1; height: 12; anchors.verticalCenter: parent.verticalCenter; color: "#92400E" }
                                                        Text {
                                                            color: "#1C1917"
                                                            font.pixelSize: 11
                                                            text: !bendRow.toolChange ? "" : bendRow.toolChange.summary
                                                        }
                                                    }
                                                }
                                            }
                                            readonly property bool selected: root.selectedBendIndex === bendRow.index
                                            readonly property bool isDragSource: root.draggedBendIndex === bendRow.index
                                            readonly property bool isDragTarget: root.draggedBendTargetIndex === bendRow.index && root.draggedBendIndex >= 0 && root.draggedBendIndex !== bendRow.index
                                            readonly property color rowColor: selected ? "#D8EBF5" : (bendRow.index % 2 === 0 ? tableCell : tableAlt)
                                            z: isDragSource ? 30 : (isDragTarget ? 20 : 1)

                                            // Drop Target Insertion Indicator Bar
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: root.draggedBendIndex > bendRow.index ? parent.top : undefined
                                                anchors.bottom: root.draggedBendIndex < bendRow.index ? parent.bottom : undefined
                                                height: 3
                                                color: "#0284C7"
                                                visible: bendRow.isDragTarget
                                                z: 40
                                            }

                                            // Row Selection Click
                                            MouseArea {
                                                anchors.fill: parent
                                                z: -1
                                                onClicked: root.selectedBendIndex = bendRow.index
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.topMargin: bendRow.toolChangeHeight
                                                spacing: 0
                                                opacity: bendRow.isDragSource && root.draggedBendTargetIndex !== bendRow.index ? 0.35 : 1.0

                                                DragCell {
                                                    // Stable bend id: keeps its number when reordered.
                                                    value: "≡ " + String(bendRow.bend.id !== undefined ? bendRow.bend.id : bendRow.bend.seq)
                                                    Layout.preferredWidth: root.colW(0)
                                                    baseColor: bendRow.isDragSource ? "#BAE6FD" : bendRow.rowColor
                                                    dragTarget: bendRow
                                                    onDragStarted: {
                                                        root.selectedBendIndex = bendRow.index
                                                        root.draggedBendIndex = bendRow.index
                                                        root.draggedBendTargetIndex = bendRow.index
                                                    }
                                                    onDragMoved: function(globalY) {
                                                        if (!root.appState || !root.appState.cadBends || root.appState.cadBends.length === 0) return
                                                        var posInTable = tableFlickable.contentItem.mapFromGlobal(0, globalY)
                                                        var rowH = 31
                                                        root.dragGhostY = posInTable.y
                                                        var targetIdx = Math.max(0, Math.min(root.appState.cadBends.length - 1, Math.floor(posInTable.y / rowH)))
                                                        // Rows can be taller when a TOOL CHANGE strip precedes them.
                                                        var colPos = bendsColumn.mapFromGlobal(0, globalY)
                                                        var hit = bendsColumn.childAt(1, colPos.y)
                                                        if (hit && hit.index !== undefined)
                                                            targetIdx = hit.index
                                                        else if (colPos.y < 0)
                                                            targetIdx = 0
                                                        else if (colPos.y >= bendsColumn.height)
                                                            targetIdx = root.appState.cadBends.length - 1
                                                        root.draggedBendTargetIndex = targetIdx
                                                    }
                                                    onDragEnded: {
                                                        bendRow.finishDragReorder()
                                                    }
                                                    onPressed: {
                                                        root.selectedBendIndex = bendRow.index
                                                        root.draggedBendIndex = bendRow.index
                                                        root.draggedBendTargetIndex = bendRow.index
                                                    }
                                                    onReleased: {
                                                        bendRow.finishDragReorder()
                                                    }
                                                }

                                                TableCell {
                                                    value: bendRow.bend.fix || (bendRow.bend.locked ? "LOCK" : "AUTO")
                                                    Layout.preferredWidth: root.colW(1)
                                                    baseColor: bendRow.rowColor
                                                    interactive: true
                                                    onClicked: {
                                                        root.selectedBendIndex = bendRow.index
                                                        if (root.appState)
                                                            root.appState.toggleCadBendLock(bendRow.index)
                                                    }
                                                }
                                                TableCell { value: bendRow.bend.angle || "-"; Layout.preferredWidth: root.colW(2); baseColor: bendRow.rowColor }
                                                TableCell { value: bendRow.bend.width || "-"; Layout.preferredWidth: root.colW(3); baseColor: bendRow.rowColor }
                                                TableCell {
                                                    value: bendRow.bend.tonnage || "-"
                                                    Layout.preferredWidth: root.colW(4)
                                                    baseColor: bendRow.rowColor
                                                    warning: Number(bendRow.bend.tonnageValue || 0) > 12.5
                                                }
                                                TableCell { value: bendRow.bend.vdie || "-"; Layout.preferredWidth: root.colW(5); baseColor: bendRow.rowColor }
                                                TableCell { value: bendRow.bend.dir || "-"; Layout.preferredWidth: root.colW(6); baseColor: bendRow.rowColor }
                                                TableCell { value: bendRow.bend.ref || "-"; Layout.preferredWidth: root.colW(7); baseColor: bendRow.rowColor }
                                                TableCell { value: bendRow.bend.setupLabel || bendRow.bend.setup || "-"; Layout.preferredWidth: root.colW(8); baseColor: bendRow.rowColor }
                                                TableCell { value: bendRow.bend.punch || "-"; Layout.preferredWidth: root.colW(9); baseColor: bendRow.rowColor }
                                                TableCell {
                                                    value: bendRow.bend.chg || "-"
                                                    Layout.preferredWidth: root.colW(10)
                                                    baseColor: bendRow.rowColor
                                                    warning: bendRow.bend.chg !== "SAME" && bendRow.bend.chg !== "START"
                                                }
                                                TableCell { value: bendRow.bend.bg || "-"; Layout.preferredWidth: root.colW(11); baseColor: bendRow.rowColor }
                                                TableCell { value: bendRow.bend.bgr || "-"; Layout.preferredWidth: root.colW(12); baseColor: bendRow.rowColor }
                                                TableCell {
                                                    value: bendRow.bend.status || "OK"
                                                    Layout.preferredWidth: root.colW(13)
                                                    baseColor: bendRow.rowColor
                                                    warning: bendRow.bend.status !== "OK"
                                                    error: bendRow.bend.status === "ERROR"
                                                }
                                            }

                                            // Reorder logic preserves existing automated test contract
                                            function finishDragReorder() {
                                                var view = root
                                                var state = view.appState
                                                var from = view.draggedBendIndex
                                                var to = view.draggedBendTargetIndex
                                                view.draggedBendIndex = -1
                                                view.draggedBendTargetIndex = -1
                                                if (state && from >= 0 && to >= 0 && from !== to) {
                                                    view.selectedBendIndex = to
                                                    state.moveCadBend(from, to)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Visual punch stack for the selected bend: proportional
                // segment blocks with widths, overlaid by the required bend
                // length so coverage and tool reuse are visible at a glance.
                Rectangle {
                    id: punchStackPanel
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    color: "#F8FAFC"
                    border.color: tableGrid
                    radius: metrics.smallRadius
                    readonly property var bend: root.selectedBend()
                    readonly property var widths: bend && bend.punchSegmentWidths ? bend.punchSegmentWidths : []
                    readonly property real total: {
                        var t = 0
                        for (var i = 0; i < widths.length; i++) t += Number(widths[i]) || 0
                        return t
                    }
                    readonly property real required: bend ? (Number(bend.width) || 0) : 0
                    readonly property real stationOffset: bend ? (Number(bend.toolingStationOffsetIn) || 0) : 0
    // Material centre on the bed (planner coverage); see ToolBarView.
    readonly property real bendCenter: bend && bend.toolingBendCenterIn !== null && bend.toolingBendCenterIn !== undefined
        && isFinite(Number(bend.toolingBendCenterIn)) ? Number(bend.toolingBendCenterIn) : -stationOffset
                    // Every installed punch (active stack + side-by-side stations),
                    // table-absolute and mirrored to the operator view like the
                    // RUN STACK strip / LIVE 3D. Sorted left->right.
                    readonly property var pieces: {
                        var out = []
                        if (!bend) return out
                        var start = Number(bend.punchSegmentStartIn)
                        var x = (isFinite(start) ? start : -total / 2) + stationOffset
                        for (var i = 0; i < widths.length; i++) {
                            var w = Number(widths[i]) || 0
                            out.push({ x: -(x + w), w: w, active: true }); x += w
                        }
                        var co = bend.toolingCoStations || []
                        for (var c = 0; c < co.length; c++) {
                            var cw = co[c].punchWidths || []
                            var cx = Number(co[c].punchStartIn) + stationOffset
                            for (var k = 0; isFinite(cx) && k < cw.length; k++) {
                                var wk = Number(cw[k]) || 0
                                out.push({ x: -(cx + wk), w: wk, active: false }); cx += wk
                            }
                        }
                        out.sort(function(a, b) { return a.x - b.x })
                        return out
                    }
                    readonly property var gaps: {
                        var g = []
                        for (var i = 1; i < pieces.length; i++) {
                            var end = pieces[i - 1].x + pieces[i - 1].w
                            var d = pieces[i].x - end
                            if (d > 0.01)
                                g.push({ x: end, w: d })
                        }
                        return g
                    }
                    readonly property real lo: {
                        var v = bendCenter - required / 2
                        for (var i = 0; i < pieces.length; i++) v = Math.min(v, pieces[i].x)
                        return v
                    }
                    readonly property real hi: {
                        var v = bendCenter + required / 2
                        for (var i = 0; i < pieces.length; i++) v = Math.max(v, pieces[i].x + pieces[i].w)
                        return v
                    }
                    readonly property real span: Math.max(hi - lo, 1e-6)
                    readonly property int pieceCount: pieces.length
                    readonly property int sharedCount: {
                        if (!bend || !root.appState || !root.appState.cadBends) return 0
                        var n = 0, list = root.appState.cadBends
                        for (var i = 0; i < list.length; i++)
                            if (Number(list[i].toolingPhaseIndex || 0) === Number(bend.toolingPhaseIndex || 0)) n++
                        return n
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 10

                        Column {
                            Layout.preferredWidth: 120
                            spacing: 2
                            Text {
                                text: punchStackPanel.bend ? ("PUNCH STACK S" + (Math.round(Number(punchStackPanel.bend.toolingPhaseIndex) || 0) + 1)) : "PUNCH STACK"
                                color: ink; font.pixelSize: 11; font.bold: true
                            }
                            Text {
                                text: punchStackPanel.widths.length
                                      ? punchStackPanel.total.toFixed(2) + " in · " + punchStackPanel.pieceCount + " pcs"
                                        + (punchStackPanel.gaps.length ? " · " + punchStackPanel.gaps.length + " gap" + (punchStackPanel.gaps.length > 1 ? "s" : "") : "")
                                      : "No stack assigned"
                                color: "#475569"; font.pixelSize: 11
                            }
                            Text {
                                text: punchStackPanel.bend && punchStackPanel.bend.punchInventoryShortage
                                      ? "INVENTORY SHORT"
                                      : (punchStackPanel.sharedCount > 0 ? "Shared by " + punchStackPanel.sharedCount + " bends" : "")
                                color: punchStackPanel.bend && punchStackPanel.bend.punchInventoryShortage ? red : teal
                                font.pixelSize: 11; font.bold: true
                            }
                        }

                        Item {
                            id: stackTrack
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            readonly property real pxPerIn: width / punchStackPanel.span

                            // Required bend length (amber outline) centered on the stack.
                            Rectangle {
                                visible: punchStackPanel.required > 0
                                width: punchStackPanel.required * stackTrack.pxPerIn
                                x: (punchStackPanel.bendCenter - punchStackPanel.required / 2 - punchStackPanel.lo) * stackTrack.pxPerIn
                                y: 2; height: 30
                                color: "transparent"
                                border.color: "#F59E0B"; border.width: 2; radius: 4
                                z: 2
                            }
                            // Gaps between installed punches: hatched slot + distance.
                            Repeater {
                                model: punchStackPanel.gaps
                                Item {
                                    required property var modelData
                                    x: (modelData.x - punchStackPanel.lo) * stackTrack.pxPerIn
                                    y: 5
                                    width: modelData.w * stackTrack.pxPerIn
                                    height: 24
                                    z: 3
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 1
                                        color: "#DC2626"
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        height: 16; radius: 3
                                        width: gapLabel.implicitWidth + 8
                                        color: "#FEF2F2"; border.color: "#DC2626"; border.width: 1
                                        Text {
                                            id: gapLabel
                                            anchors.centerIn: parent
                                            text: "GAP " + Units.len(Math.round(modelData.w * 1000) / 1000, root.appState ? root.appState.metricUnits === true : false, 3)
                                            color: "#B91C1C"; font.pixelSize: 11; font.bold: true
                                        }
                                    }
                                }
                            }
                            Repeater {
                                    model: punchStackPanel.pieces
                                    Rectangle {
                                        required property var modelData
                                        x: (modelData.x - punchStackPanel.lo) * stackTrack.pxPerIn
                                        y: 5
                                        opacity: modelData.active ? 1 : 0.6
                                        width: Math.max(2, Number(modelData.w) * stackTrack.pxPerIn)
                                        height: 24
                                        radius: 2
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: "#475569" }
                                            GradientStop { position: 1; color: "#1E293B" }
                                        }
                                        border.color: "#F8FAFC"; border.width: 1
                                        Rectangle {
                                            anchors.centerIn: parent
                                            height: 16; radius: 8
                                            width: Math.max(16, widthLabel.implicitWidth + 8)
                                            z: 3
                                            color: "white"; border.color: "#0F172A"; border.width: 1
                                            Text {
                                                id: widthLabel
                                                anchors.centerIn: parent
                                                text: String(Math.round(Number(modelData.w) * 100) / 100)
                                                color: "#0F172A"; font.pixelSize: 11; font.bold: true
                                            }
                                        }
                                    }
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: punchStackPanel.required > 0
                                text: "Bend " + Units.len(punchStackPanel.required, root.appState ? root.appState.metricUnits === true : false, 3)
                                      + (punchStackPanel.total + 1e-3 < punchStackPanel.required ? "  ·  NOT COVERED" : "")
                                color: punchStackPanel.total + 1e-3 < punchStackPanel.required ? red : "#B45309"
                                font.pixelSize: 11; font.bold: true
                            }
                        }
                    }
                }

                // Bottom Inspector & Backgauge R adjustment
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: "#ECECEC"
                    border.color: tableGrid
                    radius: metrics.smallRadius

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 8

                        Text {
                            text: {
                                var bend = root.selectedBend()
                                if (!bend)
                                    return "Select a bend to inspect setup, tooling, warnings, and backgauge values."
                                var messages = (bend.errors || []).concat(bend.warnings || [])
                                return "STEP " + bend.seq + " · " + (bend.setup || "STD") + " · " + (bend.punchName || bend.punch || "Punch")
                                    + " / " + (bend.dieName || bend.vdie || "Die") + (messages.length ? " · " + messages.join(" · ") : " · Ready")
                            }
                            color: root.selectedBend() && root.selectedBend().errors && root.selectedBend().errors.length > 0 ? red : ink
                            font.pixelSize: 11
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            text: "BG R"
                            color: ink
                            font.pixelSize: 11
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            Layout.preferredWidth: 78
                            Layout.preferredHeight: 26
                            color: root.selectedBendIndex >= 0 ? white : "#E2E8F0"
                            border.color: bgrInput.activeFocus ? teal : tableGrid
                            radius: metrics.smallRadius

                            TextInput {
                                id: bgrInput
                                objectName: "cad-bgr-input"
                                anchors.fill: parent
                                anchors.margins: 3
                                verticalAlignment: TextInput.AlignVCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                text: root.selectedBend() && root.selectedBend().bgr !== undefined ? root.selectedBend().bgr : ""
                                enabled: root.selectedBendIndex >= 0
                                validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
                                selectByMouse: true
                                font.pixelSize: 12
                                font.bold: true
                                color: enabled ? ink : "#94A3B8"
                                onEditingFinished: if (root.appState) root.appState.updateCadBendR(root.selectedBendIndex, text)
                                TapHandler {
                                    onTapped: if (root.appState && bgrInput.enabled) root.appState.openOnScreenKeyboard(
                                        bgrInput, true, qsTr("BACK GAUGE R"),
                                        function(value) { root.appState.updateCadBendR(root.selectedBendIndex, value) })
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // 4. GENERATE PANEL
    // -------------------------------------------------------------------------
    component GeneratePanel: ColumnLayout {
        spacing: 0
        ActionButton {
            objectName: "button-tonnage-hold cad-generate-button buttonGenerate"
            label: root.appState && root.appState.cadUnfoldState === "planning"
                   ? "PLANNING 3D SEQUENCE..." : "GENERATE BEND PROGRAM"
            iconSource: "icons/fa-save.svg"
            colorValue: cadWarning
            textColor: "#1F1F1F"
            disabled: !(root.appState && root.appState.cadImported && root.appState.cadBends && root.appState.cadBends.length > 0 && !root.appState.cadHasErrors
                        && root.appState.cadUnfoldState !== "planning")
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            onClicked: if (root.appState) root.appState.cadAction("generate")
        }
    }

    // -------------------------------------------------------------------------
    // Reusable UI Primitives
    // -------------------------------------------------------------------------
    component ActionButton: Rectangle {
        id: actBtn
        signal clicked()
        property string label: ""
        property string iconSource: ""
        property color colorValue: green
        property color textColor: white
        property bool disabled: false
        Layout.preferredHeight: metrics.compactControlHeight
        radius: metrics.panelRadius
        color: actMouse.containsMouse && !disabled ? Qt.darker(colorValue, 1.12) : colorValue
        opacity: disabled ? 0.55 : 1

        RowLayout {
            anchors.centerIn: parent
            spacing: 8

            Image {
                visible: actBtn.iconSource.length > 0
                source: actBtn.iconSource
                sourceSize.width: 14
                sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: actBtn.label
                color: actBtn.textColor
                font.pixelSize: 13
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            id: actMouse
            anchors.fill: parent
            enabled: !parent.disabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }
    }

    component InfoLabel: Text {
        property string label: ""
        text: label
        color: ink
        font.pixelSize: 13
        font.bold: true
        Layout.preferredWidth: metrics.cadPartLabelWidth
        verticalAlignment: Text.AlignVCenter
    }

    component ValueLabel: Text {
        property string value: ""
        property bool warning: false
        property bool dimmed: false
        text: value
        color: warning ? red : (dimmed ? "#64748B" : ink)
        font.pixelSize: 13
        font.bold: true
        Layout.preferredWidth: metrics.cadPartValueWidth
        Layout.fillWidth: true
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    component TextFieldBox: Rectangle {
        property string value: ""
        signal valueEdited(string newValue)
        Layout.preferredWidth: metrics.cadPartValueWidth
        Layout.fillWidth: true
        Layout.preferredHeight: metrics.cadProgramFieldHeight
        radius: metrics.smallRadius
        color: white
        border.color: programNameInput.activeFocus ? teal : tableGrid
        border.width: programNameInput.activeFocus ? 2 : 1

        TextInput {
            id: programNameInput
            objectName: "cad-program-name-input"
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            text: parent.value
            color: ink
            font.pixelSize: 13
            font.bold: true
            selectByMouse: true
            clip: true
            onTextEdited: parent.valueEdited(text)
            TapHandler {
                onTapped: if (root.appState) root.appState.openOnScreenKeyboard(
                    programNameInput, false, qsTr("PROGRAM NAME"),
                    function(value) { programNameInput.parent.valueEdited(value) })
            }
        }
    }

    component TableHeader: Rectangle {
        property string label: ""
        Layout.preferredHeight: 25
        gradient: Gradient {
            GradientStop { position: 0; color: tableHeaderTop }
            GradientStop { position: 1; color: tableHeaderBottom }
        }
        border.color: tableGrid
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: label
            color: darkTable
            font.pixelSize: 11
            font.bold: true
        }
    }

    component TableCell: Rectangle {
        signal clicked()
        property string value: ""
        property bool warning: false
        property bool error: false
        property bool interactive: false
        property color baseColor: tableCell
        Layout.fillHeight: true
        color: error ? "#FCA5A5" : (warning ? "#FED7AA" : baseColor)
        border.color: tableGrid
        border.width: 1

        Text {
            anchors.centerIn: parent
            width: parent.width - 4
            text: parent.value
            color: darkTable
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.interactive
            hoverEnabled: parent.interactive
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }
    }

    component DragCell: Rectangle {
        id: dCell
        signal pressed()
        signal released()
        signal dragStarted()
        signal dragMoved(real globalY)
        signal dragEnded()
        property string value: ""
        property color baseColor: tableCell
        property var dragTarget: null
        Layout.fillHeight: true
        color: dragMouse.containsMouse || root.draggedBendIndex >= 0 ? Qt.darker(baseColor, 1.05) : baseColor
        border.color: tableGrid
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 3
            Text {
                text: "≡"
                color: teal
                font.pixelSize: 13
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: dCell.value.replace("≡", "").trim()
                color: ink
                font.pixelSize: 11
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: dragMouse
            anchors.fill: parent
            cursorShape: Qt.SizeVerCursor
            hoverEnabled: true
            preventStealing: true

            onPressed: function(mouse) {
                dCell.pressed()
                dCell.dragStarted()
            }
            onPositionChanged: function(mouse) {
                if (dragMouse.pressed) {
                    var globalPt = dragMouse.mapToGlobal(mouse.x, mouse.y)
                    dCell.dragMoved(globalPt.y)
                }
            }
            onReleased: {
                dCell.released()
                dCell.dragEnded()
            }
        }
    }

    component SequenceButton: Rectangle {
        signal clicked()
        property string label: ""
        property bool enabledValue: true
        property color base: charcoal
        Layout.preferredWidth: 78
        Layout.preferredHeight: 28
        radius: metrics.smallRadius
        color: seqMouse.containsMouse && enabledValue ? Qt.darker(base, 1.15) : base
        opacity: enabledValue ? 1 : 0.45

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: white
            font.pixelSize: 11
            font.bold: true
        }

        MouseArea {
            id: seqMouse
            anchors.fill: parent
            enabled: parent.enabledValue
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }
    }
}
