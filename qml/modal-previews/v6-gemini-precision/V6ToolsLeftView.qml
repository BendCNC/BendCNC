pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "../.." as Production

// =============================================================================
// BENDCNC V5 PRECISION - TOOLS STUDIO LEFT PANEL (864 × 638)
// VIVID INDUSTRIAL CNC CONSOLE (Matches BendCNC Production Identity)
//
// 1. Studio Mode Deck: Instant focus switching across PUNCHES, DIES, and MATERIALS.
// 2. High-Precision 2D DXF & Vector CAD Stage: Real DXF CAD tool profiles loaded
//    from assets/ (punches and dies) with steel fill, crisp contour and dimensions.
// 3. Ergonomic Segment Inventory: Clean, well-spaced segment cards (16", 8", 4", 2", 1")
//    with steppers flush to the right margin, eliminating dead space.
// 4. Fully Functional Material Studio: Interactive thickness profile selection
//    (1/2 in, 16 ga, 18 ga, 20 ga, 24 ga), Preferred Punch, Preferred Die, Clearance %.
// 5. Pixel-Aligned Industrial Action Hub: NEW, SAVE, DUPLICATE, DELETE with clean SVG icons.
// 6. Straight top canvas edge (radius: 0) directly flush with top navigation bar.
// =============================================================================

Item {
    id: root
    objectName: "tools-left-panel-v5"

    property var appState: null
    property bool designerInteractive: true

    width: 864
    height: 638
    focus: true

    Production.DataStore { id: dataStore }

    // -------------------------------------------------------------------------
    // Studio Navigation State
    // -------------------------------------------------------------------------
    // 0: PUNCHES, 1: DIES, 2: MATERIALS
    property int activeTab: 0
    onActiveTabChanged: cadCanvas.requestPaint()

    property int punchIndex: 0
    property int dieIndex: 0
    property int materialIndex: 0

    onPunchIndexChanged: cadCanvas.requestPaint()
    onDieIndexChanged: cadCanvas.requestPaint()
    onMaterialIndexChanged: { selectedThicknessIndex = 0; cadCanvas.requestPaint() }

    readonly property string currentKind: activeTab === 0 ? "punch" : (activeTab === 1 ? "die" : "material")

    readonly property var currentRecords: {
        if (activeTab === 0) return dataStore.punches || []
        if (activeTab === 1) return dataStore.dies || []
        return dataStore.materials || []
    }

    readonly property int currentIndex: {
        if (activeTab === 0) return Math.max(0, Math.min(punchIndex, Math.max(0, (dataStore.punches || []).length - 1)))
        if (activeTab === 1) return Math.max(0, Math.min(dieIndex, Math.max(0, (dataStore.dies || []).length - 1)))
        return Math.max(0, Math.min(materialIndex, Math.max(0, (dataStore.materials || []).length - 1)))
    }
    onCurrentIndexChanged: cadCanvas.requestPaint()

    readonly property var selectedRecord: currentRecords.length > 0 ? currentRecords[currentIndex] : ({})

    // Material preference sub-index
    property int selectedThicknessIndex: 0
    onSelectedThicknessIndexChanged: cadCanvas.requestPaint()

    readonly property var activeThicknessPreferences: {
        var rec = selectedRecord
        return (rec && rec.thicknessToolingPreferences && rec.thicknessToolingPreferences.length > 0)
                ? rec.thicknessToolingPreferences : []
    }

    readonly property var currentThicknessPref: {
        var prefs = activeThicknessPreferences
        if (prefs.length === 0) return null
        var idx = Math.max(0, Math.min(selectedThicknessIndex, prefs.length - 1))
        return prefs[idx]
    }

    // -------------------------------------------------------------------------
    // Design Tokens (BendCNC Vivid Production Palette)
    // -------------------------------------------------------------------------
    readonly property color bgCanvas: "#E5E7EB"         // Industrial base grey
    readonly property color cardBg: "#FFFFFF"           // Elevated crisp white cards
    readonly property color cardBgAlt: "#F8FAFC"        // Subtle technical card tint
    readonly property color cardBorder: "#CBD5E1"       // Clean card outline
    readonly property color ink: "#1E232A"              // High-contrast primary text
    readonly property color textSecondary: "#475569"    // Slate secondary labels
    readonly property color textMuted: "#64748B"        // Muted captions

    // Vivid Accent Colors (Authentic to BendCNC)
    readonly property color redAccent: "#A82011"        // Punch studio primary
    readonly property color blueAccent: "#2D83B2"       // Die studio primary
    readonly property color greenAccent: "#59A60C"      // Material studio primary
    readonly property color amberAccent: "#F59E0B"      // Duplicate / safety warning
    readonly property color charcoal: "#2B2C2B"         // Cockpit button charcoal
    readonly property color blueprintBg: "#161E28"      // Precision CAD dark background
    readonly property color blueprintGrid: "#223143"    // Subtle CAD grid lines

    readonly property color activeAccent: activeTab === 0 ? redAccent : (activeTab === 1 ? blueAccent : greenAccent)

    // -------------------------------------------------------------------------
    // Toast Feedback
    // -------------------------------------------------------------------------
    property string toastText: ""
    Timer {
        id: toastTimer
        interval: 2200
        repeat: false
        onTriggered: root.toastText = ""
    }
    function showToast(msg: string) {
        root.toastText = msg
        toastTimer.restart()
    }

    // -------------------------------------------------------------------------
    // Keyboard Target Helper
    // -------------------------------------------------------------------------
    TextInput { id: keyboardProxy; visible: false; width: 0; height: 0 }

    function openNumericInput(title, initial, commit) {
        if (appState && typeof appState.openOnScreenKeyboard === "function") {
            keyboardProxy.text = initial === undefined || initial === null ? "" : String(initial)
            return appState.openOnScreenKeyboard(keyboardProxy, true, title, commit, null, true)
        }
        var next = prompt(title, initial)
        if (next !== null && next !== undefined)
            commit(next)
        return true
    }

    function openTextInput(title, initial, commit) {
        if (appState && typeof appState.openOnScreenKeyboard === "function") {
            keyboardProxy.text = initial === undefined || initial === null ? "" : String(initial)
            return appState.openOnScreenKeyboard(keyboardProxy, false, title, commit, null, true)
        }
        var next = prompt(title, initial)
        if (next !== null && next !== undefined)
            commit(next)
        return true
    }

    // -------------------------------------------------------------------------
    // Reactive Storage Helpers
    // -------------------------------------------------------------------------
    function replaceCurrentRecord(record) {
        if (currentRecords.length === 0) return
        var next = currentRecords.slice(0)
        next[currentIndex] = record
        if (activeTab === 0) {
            dataStore.punches = next
        } else if (activeTab === 1) {
            dataStore.dies = next
        } else {
            dataStore.materials = next
        }
        cadCanvas.requestPaint()
    }

    function setNumericField(field, value) {
        var num = Number(value)
        if (!isFinite(num)) return
        var rec = Object.assign({}, selectedRecord)
        rec[field] = num
        replaceCurrentRecord(rec)
    }

    function setStringField(field, value) {
        var rec = Object.assign({}, selectedRecord)
        rec[field] = String(value)
        replaceCurrentRecord(rec)
    }

    function setSegmentCount(size, delta, absolute) {
        var rec = Object.assign({}, selectedRecord)
        var key = "segmentCount" + size + "In"
        var current = Number(rec[key])
        if (!isFinite(current) || current < 0) current = 0
        var next = absolute !== undefined ? Number(absolute) : current + delta
        if (!isFinite(next) || next < 0) next = 0
        rec[key] = next
        replaceCurrentRecord(rec)
    }

    function setThicknessPreferenceField(field, value) {
        if (activeTab !== 2 || !selectedRecord) return
        var rec = Object.assign({}, selectedRecord)
        var prefs = (rec.thicknessToolingPreferences || []).slice(0)
        var idx = Math.max(0, Math.min(selectedThicknessIndex, prefs.length - 1))
        if (idx < prefs.length) {
            var item = Object.assign({}, prefs[idx])
            item[field] = value
            prefs[idx] = item
            rec.thicknessToolingPreferences = prefs
            replaceCurrentRecord(rec)
            showToast(qsTr("Updated %1 preference").arg(item.thicknessLabel || "profile"))
        }
    }

    function addNewThicknessPreference(label) {
        if (activeTab !== 2 || !selectedRecord) return
        var rec = Object.assign({}, selectedRecord)
        var prefs = (rec.thicknessToolingPreferences || []).slice(0)
        var defaultPunchId = dataStore.punches && dataStore.punches.length > 0 ? dataStore.punches[0].id : null
        var defaultDieId = dataStore.dies && dataStore.dies.length > 0 ? dataStore.dies[0].id : null
        var newPref = {
            thicknessLabel: label || "14 ga",
            preferredPunchId: defaultPunchId,
            preferredDieId: defaultDieId,
            punchToMaterialClearanceInch: null,
            punchToMaterialClearancePercent: 85.0
        }
        prefs.push(newPref)
        rec.thicknessToolingPreferences = prefs
        replaceCurrentRecord(rec)
        selectedThicknessIndex = prefs.length - 1
        showToast(qsTr("Added %1 thickness profile").arg(newPref.thicknessLabel))
    }

    // -------------------------------------------------------------------------
    // Tool Actions: NEW, SAVE, DUPLICATE, DELETE
    // -------------------------------------------------------------------------
    function runToolAction(action) {
        var next = currentRecords.slice(0)
        if (action === "NEW") {
            var newId = "tool-" + Date.now().toString(16)
            var created = null
            if (activeTab === 0) {
                created = { id: newId, name: qsTr("Custom Punch %1").arg(next.length + 1), stock: false, heightInch: 4.0, punchAngleDegree: 35.0, punchProfileType: "STANDARD",
                    segmentCount16In: 1, segmentCount8In: 1, segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 1 }
                next.push(created)
                dataStore.punches = next
                punchIndex = next.length - 1
            } else if (activeTab === 1) {
                created = { id: newId, name: qsTr("Custom Die %1").arg(next.length + 1), stock: false, heightInch: 2.0, vdieOpeningInch: 0.630, dieAngleDegree: 85.0, overallWidthInch: 2.362,
                    segmentCount16In: 1, segmentCount8In: 1, segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 1 }
                next.push(created)
                dataStore.dies = next
                dieIndex = next.length - 1
            } else {
                created = { id: newId, name: qsTr("Custom Material %1").arg(next.length + 1), stock: false,
                    materialTensileStrengthPsi: 45000, insideRadiusRuleOfThumb: 0.15, materialSpringback: 0.7, thicknessToolingPreferences: [] }
                next.push(created)
                dataStore.materials = next
                materialIndex = next.length - 1
            }
            showToast(qsTr("Created %1").arg(created.name))
        } else if (action === "SAVE") {
            showToast(qsTr("Saved %1").arg(selectedRecord.name || "Tool"))
        } else if (action === "DUPLICATE" && next.length > 0) {
            var src = selectedRecord
            var dup = Object.assign({}, src)
            dup.id = "tool-" + Date.now().toString(16)
            dup.name = String(src.name || "Tool") + " (COPY)"
            dup.stock = false
            next.push(dup)
            if (activeTab === 0) { dataStore.punches = next; punchIndex = next.length - 1 }
            else if (activeTab === 1) { dataStore.dies = next; dieIndex = next.length - 1 }
            else { dataStore.materials = next; materialIndex = next.length - 1 }
            showToast(qsTr("Duplicated %1").arg(dup.name))
        } else if (action === "DELETE" && next.length > 1) {
            var delName = selectedRecord.name || "Tool"
            next.splice(currentIndex, 1)
            if (activeTab === 0) { dataStore.punches = next; punchIndex = Math.max(0, currentIndex - 1) }
            else if (activeTab === 1) { dataStore.dies = next; dieIndex = Math.max(0, currentIndex - 1) }
            else { dataStore.materials = next; materialIndex = Math.max(0, currentIndex - 1) }
            showToast(qsTr("Deleted %1").arg(delName))
        } else if (action === "DELETE") {
            showToast(qsTr("Cannot delete last record"))
        }
        cadCanvas.requestPaint()
    }

    // -------------------------------------------------------------------------
    // DXF Asset Resolution & Parser Engine (Matches RunExecutionCanvas pattern)
    // -------------------------------------------------------------------------
    property var dxfCache: ({})

    function resolveAssetPath(path) {
        var raw = String(path || "")
        if (raw.length === 0 || raw.indexOf("://") >= 0 || raw.indexOf("/") === 0 || (raw.length > 1 && raw.charAt(1) === ":"))
            return raw
        try {
            if (typeof fileIo !== "undefined" && fileIo !== null && typeof fileIo.appDir === "function") {
                var base = fileIo.appDir()
                if (base && base.length > 0) {
                    var marker = raw.indexOf("assets/")
                    var packaged = marker >= 0 ? base + "/" + raw.substring(marker) : base + "/" + raw
                    if (typeof fileIo.exists !== "function" || fileIo.exists(packaged))
                        return packaged
                    return base + "/" + raw
                }
            }
        } catch (e) {}
        return raw
    }

    function loadText(path) {
        var resolved = resolveAssetPath(path)
        try {
            if (typeof fileIo !== "undefined" && fileIo !== null) {
                var fileText = fileIo.read(resolved)
                if (fileText && fileText.length > 0)
                    return fileText
            }
        } catch (err) {}
        try {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", path, false)
            xhr.send()
            if ((xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300))
                    && xhr.responseText !== undefined && xhr.responseText !== null && xhr.responseText.length > 0)
                return xhr.responseText
        } catch (e) {}
        return ""
    }

    function extractBracketedToolId(name) {
        var matches = String(name || "").match(/\[([^\]]+)\]/g)
        if (!matches || matches.length === 0) return ""
        var last = matches[matches.length - 1]
        return last.substring(1, last.length - 1)
    }

    function dxfAssetPath(kind, name) {
        var raw = String(name || "").toLowerCase()
        var bracketed = extractBracketedToolId(raw)
        var token = bracketed.length > 0 ? bracketed : raw
        token = token.replace(/^bc-/, "").trim()

        if (kind === "punch") {
            if (token.indexOf("8392") >= 0 || raw.indexOf("8392") >= 0 || raw.indexOf("goodeneck") >= 0 || raw.indexOf("gooseneck 88") >= 0)
                return "../../assets/Punches/Goodeneck 88° Punch [8392].dxf"
            if (token.indexOf("3924") >= 0 || raw.indexOf("3924") >= 0 || raw.indexOf("extreme") >= 0)
                return "../../assets/Punches/Extreme Gooseneck 85° Punch [3924].dxf"
            if (token.indexOf("3169") >= 0 || raw.indexOf("3169") >= 0)
                return "../../assets/Punches/Acute 30° Punch [3169].dxf"
            if (token.indexOf("9302") >= 0 || raw.indexOf("9302") >= 0 || raw.indexOf("standart 30") >= 0)
                return "../../assets/Punches/Standart 30° Punch [9302].dxf"
            if (token.indexOf("2287") >= 0 || raw.indexOf("2287") >= 0 || raw.indexOf("heavy duty") >= 0)
                return "../../assets/Punches/Heavy Duty 35° Punch [2287].dxf"
        } else if (kind === "die") {
            if (token.indexOf("4387") >= 0 || raw.indexOf("4387") >= 0 || raw.indexOf("4 way") >= 0 || raw.indexOf("4-way") >= 0)
                return "../../assets/Dies/Standart 4-Way Die [4387].dxf"
            if (token.indexOf("9355") >= 0 || raw.indexOf("9355") >= 0 || raw.indexOf("26mm 30") >= 0)
                return "../../assets/Dies/Acute 26mm 30° Die [9355].dxf"
            if (token.indexOf("9858") >= 0 || raw.indexOf("9858") >= 0 || raw.indexOf("16.5mm") >= 0)
                return "../../assets/Dies/Acute 16.5mm 30° Die [9858].dxf"
            if (token.indexOf("5623") >= 0 || raw.indexOf("5623") >= 0 || raw.indexOf("8mm") >= 0)
                return "../../assets/Dies/Acute 8mm 30° Die [5623].dxf"
            if (token.indexOf("2285") >= 0 || token.indexOf("2288") >= 0 || raw.indexOf("2285") >= 0 || raw.indexOf("26mm 35") >= 0 || raw.indexOf("2in 35") >= 0)
                return "../../assets/Dies/Acute 26mm 35° Die [2285].dxf"
        }
        return ""
    }

    function dxfBulgePolylinePoints(points, bulges, closed) {
        var expanded = []
        if (!points || points.length < 2) return points ? points.slice(0) : expanded
        var segmentCount = closed ? points.length : points.length - 1
        var maxStep = Math.PI / 18
        function appendPoint(point) {
            if (expanded.length === 0 || Math.hypot(expanded[expanded.length - 1].x - point.x, expanded[expanded.length - 1].y - point.y) > 1.0e-9)
                expanded.push({ x: point.x, y: point.y })
        }
        for (var segmentIndex = 0; segmentIndex < segmentCount; segmentIndex++) {
            var start = points[segmentIndex]
            var end = points[(segmentIndex + 1) % points.length]
            var bulge = bulges && isFinite(Number(bulges[segmentIndex])) ? Number(bulges[segmentIndex]) : 0
            appendPoint(start)
            if (Math.abs(bulge) <= 1.0e-12) continue
            var dx = end.x - start.x
            var dy = end.y - start.y
            var chord = Math.hypot(dx, dy)
            if (chord <= 1.0e-12) continue
            var sweep = 4 * Math.atan(bulge)
            var radius = chord * (1 + bulge * bulge) / (4 * Math.abs(bulge))
            var centerOffset = chord * (1 - bulge * bulge) / (4 * bulge)
            var center = {
                x: (start.x + end.x) * 0.5 - dy / chord * centerOffset,
                y: (start.y + end.y) * 0.5 + dx / chord * centerOffset
            }
            var startAngle = Math.atan2(start.y - center.y, start.x - center.x)
            var steps = Math.max(1, Math.ceil(Math.abs(sweep) / maxStep))
            for (var step = 1; step < steps; step++) {
                var angle = startAngle + sweep * step / steps
                appendPoint({
                    x: center.x + radius * Math.cos(angle),
                    y: center.y + radius * Math.sin(angle)
                })
            }
        }
        if (closed) appendPoint(points[0])
        else appendPoint(points[points.length - 1])
        return expanded
    }

    function loadDxfModel(path) {
        if (!path || path.length === 0) return null
        if (dxfCache[path] !== undefined) return dxfCache[path]
        var text = loadText(path)
        if (!text || text.length === 0) {
            dxfCache[path] = null
            return null
        }
        var tokens = text.split(/\r?\n/)
        var lines = []
        var polylines = []
        var bounds = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
        function includePoint(x, y) {
            bounds.minX = Math.min(bounds.minX, x)
            bounds.maxX = Math.max(bounds.maxX, x)
            bounds.minY = Math.min(bounds.minY, y)
            bounds.maxY = Math.max(bounds.maxY, y)
        }
        function collectBlock(start) {
            var values = ({})
            var next = start
            for (; next < tokens.length - 1; next += 2) {
                var c = String(tokens[next]).trim()
                var v = String(tokens[next + 1]).trim()
                if (c === "0") break
                if (!values[c]) values[c] = []
                values[c].push(v)
            }
            return { values: values, nextIndex: next }
        }
        function firstNumber(values, key, fallback) {
            if (!values[key] || values[key].length === 0) return fallback
            var value = Number(values[key][0])
            return isFinite(value) ? value : fallback
        }
        for (var i = 0; i < tokens.length - 1; i += 2) {
            var code = String(tokens[i]).trim()
            var type = String(tokens[i + 1]).trim()
            if (code !== "0") continue
            if (type === "LINE") {
                var lineBlock = collectBlock(i + 2)
                i = lineBlock.nextIndex - 2
                var x1 = firstNumber(lineBlock.values, "10", NaN)
                var y1 = firstNumber(lineBlock.values, "20", NaN)
                var x2 = firstNumber(lineBlock.values, "11", NaN)
                var y2 = firstNumber(lineBlock.values, "21", NaN)
                if (isFinite(x1) && isFinite(y1) && isFinite(x2) && isFinite(y2)) {
                    lines.push({ x1: x1, y1: y1, x2: x2, y2: y2 })
                    includePoint(x1, y1); includePoint(x2, y2)
                }
            } else if (type === "LWPOLYLINE") {
                var polyEntityStart = i + 2
                var polyBlock = collectBlock(polyEntityStart)
                i = polyBlock.nextIndex - 2
                var points = []
                var bulges = []
                var pendingVertex = null
                for (var polyToken = polyEntityStart; polyToken < polyBlock.nextIndex; polyToken += 2) {
                    var polyCode = String(tokens[polyToken]).trim()
                    var polyValue = Number(tokens[polyToken + 1])
                    if (polyCode === "10") {
                        if (pendingVertex && isFinite(pendingVertex.x) && isFinite(pendingVertex.y)) {
                            points.push({ x: pendingVertex.x, y: pendingVertex.y })
                            bulges.push(pendingVertex.bulge)
                        }
                        pendingVertex = { x: polyValue, y: NaN, bulge: 0 }
                    } else if (polyCode === "20" && pendingVertex) {
                        pendingVertex.y = polyValue
                    } else if (polyCode === "42" && pendingVertex) {
                        pendingVertex.bulge = isFinite(polyValue) ? polyValue : 0
                    }
                }
                if (pendingVertex && isFinite(pendingVertex.x) && isFinite(pendingVertex.y)) {
                    points.push({ x: pendingVertex.x, y: pendingVertex.y })
                    bulges.push(pendingVertex.bulge)
                }
                var closed = (Math.floor(firstNumber(polyBlock.values, "70", 0)) & 1) === 1
                if (points.length > 1) {
                    var expandedPoints = dxfBulgePolylinePoints(points, bulges, closed)
                    for (var expandedIndex = 0; expandedIndex < expandedPoints.length; expandedIndex++)
                        includePoint(expandedPoints[expandedIndex].x, expandedPoints[expandedIndex].y)
                    polylines.push({ points: expandedPoints, closed: closed })
                }
            }
        }
        if (!isFinite(bounds.minX)) {
            dxfCache[path] = null
            return null
        }
        var model = { lines: lines, polylines: polylines, bounds: bounds }
        dxfCache[path] = model
        return model
    }

    // -------------------------------------------------------------------------
    // Canvas Base Background (radius: 0 meeting top menu straight!)
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: root.bgCanvas
        radius: 0
    }

    // =========================================================================
    // 1. TOP STUDIO MODE DECK (x: 10, y: 8, width: 844, height: 42)
    // =========================================================================
    Rectangle {
        id: studioDeck
        x: 10
        y: 8
        width: 844
        height: 42
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Tab 0: PUNCH STUDIO
            Rectangle {
                width: 175
                height: 32
                radius: 5
                color: root.activeTab === 0 ? root.redAccent : (pMouse.containsMouse ? "#F1F5F9" : "transparent")
                border.color: root.activeTab === 0 ? root.redAccent : "#CBD5E1"
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "▼"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.activeTab === 0 ? "#FFFFFF" : root.redAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: qsTr("PUNCH STUDIO")
                        font.pixelSize: 12
                        font.bold: true
                        color: root.activeTab === 0 ? "#FFFFFF" : root.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 22
                        height: 18
                        radius: 9
                        color: root.activeTab === 0 ? "#82160A" : "#E2E8F0"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: String((dataStore.punches || []).length)
                            font.pixelSize: 10
                            font.bold: true
                            color: root.activeTab === 0 ? "#FFFFFF" : root.textSecondary
                        }
                    }
                }

                MouseArea {
                    id: pMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.activeTab = 0; cadCanvas.requestPaint() }
                }
            }

            // Tab 1: DIE STUDIO
            Rectangle {
                width: 175
                height: 32
                radius: 5
                color: root.activeTab === 1 ? root.blueAccent : (dMouse.containsMouse ? "#F1F5F9" : "transparent")
                border.color: root.activeTab === 1 ? root.blueAccent : "#CBD5E1"
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "▲"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.activeTab === 1 ? "#FFFFFF" : root.blueAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: qsTr("DIE STUDIO")
                        font.pixelSize: 12
                        font.bold: true
                        color: root.activeTab === 1 ? "#FFFFFF" : root.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 22
                        height: 18
                        radius: 9
                        color: root.activeTab === 1 ? "#1E5E82" : "#E2E8F0"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: String((dataStore.dies || []).length)
                            font.pixelSize: 10
                            font.bold: true
                            color: root.activeTab === 1 ? "#FFFFFF" : root.textSecondary
                        }
                    }
                }

                MouseArea {
                    id: dMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.activeTab = 1; cadCanvas.requestPaint() }
                }
            }

            // Tab 2: MATERIAL STUDIO
            Rectangle {
                width: 185
                height: 32
                radius: 5
                color: root.activeTab === 2 ? root.greenAccent : (mMouse.containsMouse ? "#F1F5F9" : "transparent")
                border.color: root.activeTab === 2 ? root.greenAccent : "#CBD5E1"
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "■"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.activeTab === 2 ? "#FFFFFF" : root.greenAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: qsTr("MATERIAL STUDIO")
                        font.pixelSize: 12
                        font.bold: true
                        color: root.activeTab === 2 ? "#FFFFFF" : root.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 22
                        height: 18
                        radius: 9
                        color: root.activeTab === 2 ? "#3E7507" : "#E2E8F0"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: String((dataStore.materials || []).length)
                            font.pixelSize: 10
                            font.bold: true
                            color: root.activeTab === 2 ? "#FFFFFF" : root.textSecondary
                        }
                    }
                }

                MouseArea {
                    id: mMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.activeTab = 2; cadCanvas.requestPaint() }
                }
            }
        }

        // Quick Spec Chip (Top Right)
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 28
            width: specText.implicitWidth + 24
            radius: 14
            color: "#F1F5F9"
            border.color: "#CBD5E1"
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.activeAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    id: specText
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "Consolas, monospace"
                    color: root.textSecondary
                    text: {
                        var r = root.selectedRecord
                        if (root.activeTab === 0) {
                            return (r.heightInch ? Number(r.heightInch).toFixed(3) + "\" H" : "0.000\" H")
                                    + " · " + (r.punchAngleDegree ? Number(r.punchAngleDegree).toFixed(1) + "°" : "0.0°")
                                    + " · " + (r.punchProfileType || "STANDARD")
                        } else if (root.activeTab === 1) {
                            return "V=" + (r.vdieOpeningInch ? Number(r.vdieOpeningInch).toFixed(3) + "\"" : "0.000\"")
                                    + " · " + (r.dieAngleDegree ? Number(r.dieAngleDegree).toFixed(1) + "°" : "0.0°")
                                    + " · " + (r.heightInch ? Number(r.heightInch).toFixed(3) + "\" H" : "0.000\" H")
                        } else {
                            return (r.materialTensileStrengthPsi ? Number(r.materialTensileStrengthPsi).toLocaleString() + " PSI" : "0 PSI")
                                    + " · " + (r.materialSpringback ? Number(r.materialSpringback).toFixed(1) + "° SB" : "0.0°")
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 2. LEFT PANEL (x: 10, y: 56, width: 414, height: 574)
    //    Top: High-Precision 2D DXF Vector CAD Stage (height: 268)
    //    Bottom: Segment Inventory (height: 298)
    // =========================================================================

    // Top: 2D CAD Stage
    Rectangle {
        id: cadCard
        x: 10
        y: 56
        width: 414
        height: 268
        color: root.blueprintBg
        radius: 6
        border.color: root.blueprintGrid
        border.width: 1
        clip: true

        // Grid Lines Background
        Canvas {
            id: gridCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#1E2A38"
                ctx.lineWidth = 1
                for (var x = 20; x < width; x += 20) {
                    ctx.beginPath()
                    ctx.moveTo(x, 0)
                    ctx.lineTo(x, height)
                    ctx.stroke()
                }
                for (var y = 20; y < height; y += 20) {
                    ctx.beginPath()
                    ctx.moveTo(0, y)
                    ctx.lineTo(width, y)
                    ctx.stroke()
                }
                // Center vertical reference datum line
                ctx.strokeStyle = "#334559"
                ctx.lineWidth = 1.5
                ctx.setLineDash([4, 4])
                ctx.beginPath()
                ctx.moveTo(width / 2, 0)
                ctx.lineTo(width / 2, height)
                ctx.stroke()
                ctx.setLineDash([])
            }
        }

        // CAD Overlay Badge (Top Left)
        Rectangle {
            x: 10
            y: 10
            height: 20
            width: cadTitle.implicitWidth + 16
            radius: 4
            color: "#0F172A"
            border.color: "#334155"
            border.width: 1

            Text {
                id: cadTitle
                anchors.centerIn: parent
                text: root.activeTab === 0 ? qsTr("PUNCH PROFILE DXF · 1:1 CAD")
                        : (root.activeTab === 1 ? qsTr("V-DIE PROFILE DXF · 1:1 CAD") : qsTr("BEND DYNAMICS & MATERIAL MODEL"))
                font.pixelSize: 9
                font.bold: true
                color: "#94A3B8"
            }
        }

        // Active Profile Type Badge (Top Right)
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.top: parent.top
            anchors.topMargin: 10
            height: 20
            width: typeLabel.implicitWidth + 16
            radius: 4
            color: root.activeAccent

            Text {
                id: typeLabel
                anchors.centerIn: parent
                text: {
                    var r = root.selectedRecord
                    if (root.activeTab === 0) return String(r.punchProfileType || "STANDARD")
                    if (root.activeTab === 1) return (r.dieAngleDegree ? Number(r.dieAngleDegree).toFixed(0) + "° V-DIE" : "V-DIE")
                    var p = root.currentThicknessPref
                    return (p ? p.thicknessLabel + " · " : "") + "AIR BEND"
                }
                font.pixelSize: 9
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // Dynamic 2D DXF CAD Canvas
        Canvas {
            id: cadCanvas
            anchors.fill: parent
            antialiasing: true

            function getPunchTangCenterX(dxfModel) {
                if (!dxfModel || !dxfModel.bounds || !dxfModel.polylines) return 0.0
                var b = dxfModel.bounds
                var topY = b.maxY
                var tangMinX = Infinity
                var tangMaxX = -Infinity
                for (var i = 0; i < dxfModel.polylines.length; i++) {
                    var poly = dxfModel.polylines[i]
                    if (!poly.points) continue
                    for (var j = 0; j < poly.points.length; j++) {
                        var pt = poly.points[j]
                        if (pt.y >= topY - 0.12) {
                            tangMinX = Math.min(tangMinX, pt.x)
                            tangMaxX = Math.max(tangMaxX, pt.x)
                        }
                    }
                }
                if (isFinite(tangMinX) && isFinite(tangMaxX)) {
                    return (tangMinX + tangMaxX) * 0.5
                }
                return (b.minX + b.maxX) * 0.5
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var rec = root.selectedRecord
                var cx = width / 2
                var cy = height / 2

                // =============================================================
                // TAB 0: PUNCH STUDIO CAD STAGE
                // =============================================================
                if (root.activeTab === 0) {
                    var dxfPathP = root.dxfAssetPath("punch", rec.name || rec.id)
                    var dxfModelP = root.loadDxfModel(dxfPathP)

                    var pAngle = Number(rec.punchAngleDegree) || 30.0
                    var halfRadP = (pAngle * 0.5) * (Math.PI / 180.0)

                    if (dxfModelP && dxfModelP.bounds && isFinite(dxfModelP.bounds.minX)
                            && dxfModelP.polylines && dxfModelP.polylines.length > 0) {
                        var bP = dxfModelP.bounds
                        var mWP = Math.max(0.1, bP.maxX - bP.minX)
                        var mHP = Math.max(0.1, bP.maxY - bP.minY)
                        var padP = 42

                        // Center punch based on top tang mounting centerline!
                        var tangXP = cadCanvas.getPunchTangCenterX(dxfModelP)
                        var maxHalfWP = Math.max(Math.abs(tangXP - bP.minX), Math.abs(bP.maxX - tangXP))
                        var scaleP = Math.min((width * 0.5 - padP) / Math.max(0.1, maxHalfWP), (height - padP * 2) / mHP)
                        var midYP = (bP.minY + bP.maxY) * 0.5

                        var toXP = function(x) { return cx + (x - tangXP) * scaleP }
                        var toYP = function(y) { return cy - (y - midYP) * scaleP }

                        ctx.save()

                        for (var pi = 0; pi < dxfModelP.polylines.length; pi++) {
                            var polyP = dxfModelP.polylines[pi]
                            if (!polyP.points || polyP.points.length < 2) continue
                            ctx.beginPath()
                            ctx.moveTo(toXP(polyP.points[0].x), toYP(polyP.points[0].y))
                            for (var ppt = 1; ppt < polyP.points.length; ppt++) {
                                ctx.lineTo(toXP(polyP.points[ppt].x), toYP(polyP.points[ppt].y))
                            }
                            if (polyP.closed) {
                                ctx.closePath()
                                var gradP = ctx.createLinearGradient(cx - 50, cy - 80, cx + 50, cy + 80)
                                gradP.addColorStop(0, "#475569")
                                gradP.addColorStop(0.5, "#64748B")
                                gradP.addColorStop(1, "#334155")
                                ctx.fillStyle = gradP
                                ctx.fill()
                            }
                            ctx.strokeStyle = "#F87171"
                            ctx.lineWidth = 1.8
                            ctx.stroke()
                        }

                        var topScreenYP = toYP(bP.maxY)
                        var bottomScreenYP = toYP(bP.minY)
                        var leftScreenXP = toXP(bP.minX)
                        var rightScreenXP = toXP(bP.maxX)

                        // Height Dimension Line (Right side)
                        var dimXP = Math.min(width - 15, rightScreenXP + 22)
                        ctx.strokeStyle = "#38BDF8"
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(dimXP, topScreenYP); ctx.lineTo(dimXP, bottomScreenYP)
                        ctx.moveTo(dimXP - 4, topScreenYP + 6); ctx.lineTo(dimXP, topScreenYP); ctx.lineTo(dimXP + 4, topScreenYP + 6)
                        ctx.moveTo(dimXP - 4, bottomScreenYP - 6); ctx.lineTo(dimXP, bottomScreenYP); ctx.lineTo(dimXP + 4, bottomScreenYP - 6)
                        ctx.stroke()

                        ctx.fillStyle = "#38BDF8"
                        ctx.font = "bold 10px Consolas, monospace"
                        ctx.textAlign = "left"
                        var hValP = Number(rec.heightInch) || mHP
                        ctx.fillText(hValP.toFixed(3) + "\"", dimXP + 6, cy)

                        // Width Dimension Line (Bottom)
                        var dimYP = Math.min(height - 10, bottomScreenYP + 18)
                        ctx.strokeStyle = "#F59E0B"
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(leftScreenXP, dimYP); ctx.lineTo(rightScreenXP, dimYP)
                        ctx.moveTo(leftScreenXP + 6, dimYP - 4); ctx.lineTo(leftScreenXP, dimYP); ctx.lineTo(leftScreenXP + 6, dimYP + 4)
                        ctx.moveTo(rightScreenXP - 6, dimYP - 4); ctx.lineTo(rightScreenXP, dimYP); ctx.lineTo(rightScreenXP - 6, dimYP + 4)
                        ctx.stroke()

                        ctx.fillStyle = "#F59E0B"
                        ctx.textAlign = "center"
                        ctx.fillText("W=" + mWP.toFixed(3) + "\"", cx, dimYP + 12)

                        // Tip Degrees Dimension Callout (Arc at tip vertex + Leader Line to the LEFT)
                        var arcRP = 28
                        ctx.strokeStyle = "#FACC15"
                        ctx.lineWidth = 1.6
                        ctx.beginPath()
                        ctx.arc(cx, bottomScreenYP, arcRP, -Math.PI * 0.5 - halfRadP, -Math.PI * 0.5 + halfRadP)
                        ctx.stroke()

                        var rayLenP = arcRP + 6
                        ctx.strokeStyle = "rgba(250, 204, 21, 0.45)"
                        ctx.lineWidth = 1.0
                        ctx.beginPath()
                        ctx.moveTo(cx, bottomScreenYP); ctx.lineTo(cx - Math.sin(halfRadP) * rayLenP, bottomScreenYP - Math.cos(halfRadP) * rayLenP)
                        ctx.moveTo(cx, bottomScreenYP); ctx.lineTo(cx + Math.sin(halfRadP) * rayLenP, bottomScreenYP - Math.cos(halfRadP) * rayLenP)
                        ctx.stroke()

                        // Leader line pointing to the left side so badge NEVER covers the tip
                        var arcPtX = cx - Math.sin(halfRadP * 0.7) * arcRP
                        var arcPtY = bottomScreenYP - Math.cos(halfRadP * 0.7) * arcRP
                        var elbowX = cx - Math.max(38, Math.sin(halfRadP) * arcRP + 18)
                        var elbowY = bottomScreenYP - 18
                        var shelfX = elbowX - 16

                        ctx.strokeStyle = "#FACC15"
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(arcPtX, arcPtY)
                        ctx.lineTo(elbowX, elbowY)
                        ctx.lineTo(shelfX, elbowY)
                        ctx.stroke()

                        ctx.fillStyle = "#FACC15"
                        ctx.beginPath(); ctx.arc(arcPtX, arcPtY, 2.5, 0, Math.PI * 2); ctx.fill()

                        var degTextP = (pAngle % 1 === 0 ? pAngle.toFixed(0) : pAngle.toFixed(1)) + "°"
                        ctx.font = "bold 11px Consolas, monospace"
                        var twP = ctx.measureText(degTextP).width
                        var badgeX = shelfX - twP - 10
                        var badgeY = elbowY - 8
                        ctx.fillStyle = "rgba(15, 23, 42, 0.92)"
                        ctx.fillRect(badgeX, badgeY, twP + 8, 16)
                        ctx.strokeStyle = "#EAB308"
                        ctx.lineWidth = 1.0
                        ctx.strokeRect(badgeX, badgeY, twP + 8, 16)
                        ctx.fillStyle = "#FEF08A"
                        ctx.textAlign = "center"
                        ctx.fillText(degTextP, badgeX + (twP + 8) * 0.5, elbowY + 4)

                        ctx.restore()
                        return
                    }

                    // Fallback to Parametric Punch Profile
                    var pHeight = Number(rec.heightInch) || 4.0
                    var scaleP2 = 42.0
                    var totalH = Math.min(200, Math.max(120, pHeight * scaleP2))
                    var tipY = cy + totalH * 0.42
                    var topY = tipY - totalH
                    var tipWidth = Math.sin(halfRadP) * 45

                    ctx.save()
                    ctx.beginPath()
                    ctx.moveTo(cx - 20, topY)
                    ctx.lineTo(cx + 20, topY)
                    ctx.lineTo(cx + 20, topY + 24)
                    ctx.lineTo(cx + 14, topY + 28)
                    ctx.lineTo(cx + 20, topY + 34)
                    ctx.lineTo(cx + 28, topY + 50)
                    ctx.lineTo(cx + tipWidth, tipY - 15)
                    ctx.lineTo(cx, tipY)
                    ctx.lineTo(cx - tipWidth, tipY - 15)
                    ctx.lineTo(cx - 28, topY + 50)
                    ctx.lineTo(cx - 20, topY + 24)
                    ctx.closePath()
                    var gradP2 = ctx.createLinearGradient(cx - 50, topY, cx + 50, tipY)
                    gradP2.addColorStop(0, "#475569"); gradP2.addColorStop(1, "#334155")
                    ctx.fillStyle = gradP2; ctx.fill()
                    ctx.strokeStyle = "#F87171"; ctx.lineWidth = 1.8; ctx.stroke()

                    // Tip angle on fallback with leader to left
                    ctx.strokeStyle = "#FACC15"; ctx.lineWidth = 1.6
                    ctx.beginPath()
                    ctx.arc(cx, tipY, 26, -Math.PI * 0.5 - halfRadP, -Math.PI * 0.5 + halfRadP)
                    ctx.stroke()

                    var arcPtX2 = cx - Math.sin(halfRadP * 0.7) * 26
                    var arcPtY2 = tipY - Math.cos(halfRadP * 0.7) * 26
                    var elbowX2 = cx - Math.max(38, Math.sin(halfRadP) * 26 + 18)
                    var elbowY2 = tipY - 18
                    var shelfX2 = elbowX2 - 16

                    ctx.strokeStyle = "#FACC15"; ctx.lineWidth = 1.2
                    ctx.beginPath()
                    ctx.moveTo(arcPtX2, arcPtY2); ctx.lineTo(elbowX2, elbowY2); ctx.lineTo(shelfX2, elbowY2)
                    ctx.stroke()

                    ctx.fillStyle = "#FACC15"
                    ctx.beginPath(); ctx.arc(arcPtX2, arcPtY2, 2.5, 0, Math.PI * 2); ctx.fill()

                    var degTextP2 = (pAngle % 1 === 0 ? pAngle.toFixed(0) : pAngle.toFixed(1)) + "°"
                    ctx.font = "bold 11px Consolas, monospace"
                    var twP2 = ctx.measureText(degTextP2).width
                    var badgeX2 = shelfX2 - twP2 - 10
                    var badgeY2 = elbowY2 - 8
                    ctx.fillStyle = "rgba(15, 23, 42, 0.92)"
                    ctx.fillRect(badgeX2, badgeY2, twP2 + 8, 16)
                    ctx.strokeStyle = "#EAB308"; ctx.lineWidth = 1.0
                    ctx.strokeRect(badgeX2, badgeY2, twP2 + 8, 16)
                    ctx.fillStyle = "#FEF08A"; ctx.textAlign = "center"
                    ctx.fillText(degTextP2, badgeX2 + (twP2 + 8) * 0.5, elbowY2 + 4)

                    ctx.restore()
                    return
                }

                // =============================================================
                // TAB 1: DIE STUDIO CAD STAGE
                // =============================================================
                if (root.activeTab === 1) {
                    var is4Way = String(rec.name || "").toLowerCase().indexOf("4 way") >= 0
                            || String(rec.name || "").toLowerCase().indexOf("4-way") >= 0
                            || String(rec.name || "").indexOf("4387") >= 0
                    var rotDeg = 0
                    var vVal = Number(rec.vdieOpeningInch) || 0.630

                    if (is4Way) {
                        // User specification: Top is smallest (0.630in), then bottom (0.866in), then right (1.378in), left (1.969in)
                        if (Math.abs(vVal - 0.630) < 0.05) {
                            rotDeg = 0       // Top face (smallest)
                        } else if (Math.abs(vVal - 0.866) < 0.05) {
                            rotDeg = 180     // Bottom face -> rotate 180 to top
                        } else if (Math.abs(vVal - 1.378) < 0.05) {
                            rotDeg = 90      // Right face -> rotate 90 CCW to top
                        } else if (Math.abs(vVal - 1.969) < 0.05) {
                            rotDeg = 270     // Left face -> rotate 270 to top
                        }
                    }
                    var rotRad = (rotDeg * Math.PI) / 180.0
                    var cosR = Math.cos(rotRad)
                    var sinR = Math.sin(rotRad)

                    var dxfPathD = root.dxfAssetPath("die", rec.name || rec.id)
                    var dxfModelD = root.loadDxfModel(dxfPathD)

                    if (dxfModelD && dxfModelD.bounds && isFinite(dxfModelD.bounds.minX)
                            && dxfModelD.polylines && dxfModelD.polylines.length > 0) {

                        var bD = dxfModelD.bounds
                        var midXD = (bD.minX + bD.maxX) * 0.5
                        var midYD = (bD.minY + bD.maxY) * 0.5

                        // Calculate rotated coordinates & bounds
                        var rotB = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
                        var rotatedPolylines = []

                        for (var di = 0; di < dxfModelD.polylines.length; di++) {
                            var polyD = dxfModelD.polylines[di]
                            if (!polyD.points || polyD.points.length < 2) continue
                            var rPts = []
                            for (var dpt = 0; dpt < polyD.points.length; dpt++) {
                                var ox = polyD.points[dpt].x - midXD
                                var oy = polyD.points[dpt].y - midYD
                                var rx = ox * cosR - oy * sinR
                                var ry = ox * sinR + oy * cosR
                                rotB.minX = Math.min(rotB.minX, rx)
                                rotB.maxX = Math.max(rotB.maxX, rx)
                                rotB.minY = Math.min(rotB.minY, ry)
                                rotB.maxY = Math.max(rotB.maxY, ry)
                                rPts.push({ x: rx, y: ry })
                            }
                            rotatedPolylines.push({ points: rPts, closed: polyD.closed })
                        }

                        var mWD = Math.max(0.1, rotB.maxX - rotB.minX)
                        var mHD = Math.max(0.1, rotB.maxY - rotB.minY)
                        var padD = 44
                        var scaleD = Math.min((width - padD * 2) / mWD, (height - padD * 2) / mHD)

                        var toXD = function(x) { return cx + x * scaleD }
                        var toYD = function(y) { return cy - y * scaleD }

                        ctx.save()

                        for (var rpi = 0; rpi < rotatedPolylines.length; rpi++) {
                            var rPoly = rotatedPolylines[rpi]
                            ctx.beginPath()
                            ctx.moveTo(toXD(rPoly.points[0].x), toYD(rPoly.points[0].y))
                            for (var rpt = 1; rpt < rPoly.points.length; rpt++) {
                                ctx.lineTo(toXD(rPoly.points[rpt].x), toYD(rPoly.points[rpt].y))
                            }
                            if (rPoly.closed) {
                                ctx.closePath()
                                var gradD = ctx.createLinearGradient(cx - 50, cy - 80, cx + 50, cy + 80)
                                gradD.addColorStop(0, "#475569")
                                gradD.addColorStop(0.5, "#64748B")
                                gradD.addColorStop(1, "#334155")
                                ctx.fillStyle = gradD
                                ctx.fill()
                            }
                            ctx.strokeStyle = "#60A5FA"
                            ctx.lineWidth = 1.8
                            ctx.stroke()
                        }

                        var topScreenYD = toYD(rotB.maxY)
                        var bottomScreenYD = toYD(rotB.minY)
                        var leftScreenXD = toXD(rotB.minX)
                        var rightScreenXD = toXD(rotB.maxX)

                        // Height Dimension Line (Right side)
                        var dimXD = Math.min(width - 15, rightScreenXD + 22)
                        ctx.strokeStyle = "#38BDF8"
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(dimXD, topScreenYD); ctx.lineTo(dimXD, bottomScreenYD)
                        ctx.moveTo(dimXD - 4, topScreenYD + 6); ctx.lineTo(dimXD, topScreenYD); ctx.lineTo(dimXD + 4, topScreenYD + 6)
                        ctx.moveTo(dimXD - 4, bottomScreenYD - 6); ctx.lineTo(dimXD, bottomScreenYD); ctx.lineTo(dimXD + 4, bottomScreenYD - 6)
                        ctx.stroke()

                        ctx.fillStyle = "#38BDF8"
                        ctx.font = "bold 10px Consolas, monospace"
                        ctx.textAlign = "left"
                        var hValD = Number(rec.heightInch) || mHD
                        ctx.fillText(hValD.toFixed(3) + "\"", dimXD + 6, cy)

                        // Base Width Dimension Line (Bottom) -> Specifically "Base W = ..."
                        var dimYD = Math.min(height - 10, bottomScreenYD + 18)
                        ctx.strokeStyle = "#F59E0B"
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(leftScreenXD, dimYD); ctx.lineTo(rightScreenXD, dimYD)
                        ctx.moveTo(leftScreenXD + 6, dimYD - 4); ctx.lineTo(leftScreenXD, dimYD); ctx.lineTo(leftScreenXD + 6, dimYD + 4)
                        ctx.moveTo(rightScreenXD - 6, dimYD - 4); ctx.lineTo(rightScreenXD, dimYD); ctx.lineTo(rightScreenXD - 6, dimYD + 4)
                        ctx.stroke()

                        ctx.fillStyle = "#F59E0B"
                        ctx.font = "bold 10px Consolas, monospace"
                        ctx.textAlign = "center"
                        var baseWVal = Number(rec.overallWidthInch) || mWD
                        ctx.fillText("Base W=" + baseWVal.toFixed(3) + "\"", cx, dimYD + 12)

                        // V-Die Opening Dimension Line (Top active V-groove) -> Specifically "V = ..."
                        var vPx = Math.max(16, Math.min(mWD * scaleD * 0.95, vVal * scaleD))
                        var vx1 = cx - vPx * 0.5
                        var vx2 = cx + vPx * 0.5
                        var dimVY = Math.max(26, topScreenYD - 14)

                        ctx.strokeStyle = "#38BDF8"
                        ctx.lineWidth = 1.2
                        ctx.beginPath()
                        ctx.moveTo(vx1, dimVY); ctx.lineTo(vx2, dimVY)
                        ctx.moveTo(vx1, dimVY - 4); ctx.lineTo(vx1, topScreenYD + 2)
                        ctx.moveTo(vx2, dimVY - 4); ctx.lineTo(vx2, topScreenYD + 2)
                        ctx.moveTo(vx1 + 5, dimVY - 3); ctx.lineTo(vx1, dimVY); ctx.lineTo(vx1 + 5, dimVY + 3)
                        ctx.moveTo(vx2 - 5, dimVY - 3); ctx.lineTo(vx2, dimVY); ctx.lineTo(vx2 - 5, dimVY + 3)
                        ctx.stroke()

                        var vText = "V=" + vVal.toFixed(3) + "\""
                        ctx.font = "bold 10px Consolas, monospace"
                        var vtw = ctx.measureText(vText).width
                        ctx.fillStyle = "rgba(15, 23, 42, 0.92)"
                        ctx.fillRect(cx - vtw * 0.5 - 4, dimVY - 14, vtw + 8, 14)
                        ctx.strokeStyle = "#0284C7"; ctx.lineWidth = 0.8
                        ctx.strokeRect(cx - vtw * 0.5 - 4, dimVY - 14, vtw + 8, 14)
                        ctx.fillStyle = "#38BDF8"; ctx.textAlign = "center"
                        ctx.fillText(vText, cx, dimVY - 3)

                        // V Notch angle label
                        var dAngle = Number(rec.dieAngleDegree) || 85.0
                        var dAngText = (dAngle % 1 === 0 ? dAngle.toFixed(0) : dAngle.toFixed(1)) + "°"
                        ctx.fillStyle = "rgba(148, 163, 184, 0.9)"
                        ctx.font = "bold 9px Consolas, monospace"
                        ctx.fillText(dAngText, cx, topScreenYD + 16)

                        ctx.restore()
                        return
                    }

                    // Fallback to Parametric Die Block
                    var blockW = 160, blockH = 110
                    var dieTopY = cy - blockH * 0.35, dieBottomY = dieTopY + blockH
                    var vHalfW = Math.min(blockW * 0.42, Math.max(15, vVal * 48 * 0.5))
                    var dAngleF = Number(rec.dieAngleDegree) || 85.0
                    var vDepthF = vHalfW / Math.tan((dAngleF * 0.5) * (Math.PI / 180.0))

                    ctx.save()
                    ctx.beginPath()
                    ctx.moveTo(cx - blockW * 0.5, dieTopY)
                    ctx.lineTo(cx - vHalfW, dieTopY)
                    ctx.lineTo(cx, dieTopY + vDepthF)
                    ctx.lineTo(cx + vHalfW, dieTopY)
                    ctx.lineTo(cx + blockW * 0.5, dieTopY)
                    ctx.lineTo(cx + blockW * 0.5, dieBottomY)
                    ctx.lineTo(cx - blockW * 0.5, dieBottomY)
                    ctx.closePath()
                    var gradDF = ctx.createLinearGradient(cx - 60, dieTopY, cx + 60, dieBottomY)
                    gradDF.addColorStop(0, "#475569"); gradDF.addColorStop(1, "#334155")
                    ctx.fillStyle = gradDF; ctx.fill()
                    ctx.strokeStyle = "#60A5FA"; ctx.lineWidth = 1.8; ctx.stroke()

                    // Base W callout
                    ctx.fillStyle = "#F59E0B"; ctx.font = "bold 10px Consolas, monospace"; ctx.textAlign = "center"
                    ctx.fillText("Base W=" + (Number(rec.overallWidthInch) || 2.362).toFixed(3) + "\"", cx, dieBottomY + 16)
                    // V callout
                    ctx.fillStyle = "#38BDF8"
                    ctx.fillText("V=" + vVal.toFixed(3) + "\"", cx, dieTopY - 8)

                    ctx.restore()
                    return
                }

                // =============================================================
                // TAB 2: MATERIAL STUDIO CAD STAGE (REALISTIC TOOLING & WORKPIECE)
                // =============================================================
                var matRec = rec
                var matName = String(matRec.name || "").toLowerCase()
                var tensile = Number(matRec.materialTensileStrengthPsi) || 45000
                var springback = Number(matRec.materialSpringback) || 0.7
                var irFactor = Number(matRec.insideRadiusRuleOfThumb) || 0.15

                var pref = root.currentThicknessPref
                if (!pref && matRec.thicknessToolingPreferences && matRec.thicknessToolingPreferences.length > 0)
                    pref = matRec.thicknessToolingPreferences[0]

                var tLabel = pref ? String(pref.thicknessLabel || "16 ga") : "16 ga"

                function parseThicknessVal(lbl) {
                    var s = String(lbl || "").toLowerCase().trim()
                    if (s.indexOf("1/2") >= 0) return 0.500
                    if (s.indexOf("3/8") >= 0) return 0.375
                    if (s.indexOf("1/4") >= 0) return 0.250
                    if (s.indexOf("3/16") >= 0) return 0.1875
                    if (s.indexOf("1/8") >= 0) return 0.125
                    if (s.indexOf("10 ga") >= 0) return 0.1345
                    if (s.indexOf("11 ga") >= 0) return 0.1196
                    if (s.indexOf("12 ga") >= 0) return 0.1046
                    if (s.indexOf("14 ga") >= 0) return 0.0747
                    if (s.indexOf("16 ga") >= 0) return 0.0598
                    if (s.indexOf("18 ga") >= 0) return 0.0478
                    if (s.indexOf("20 ga") >= 0) return 0.0359
                    if (s.indexOf("22 ga") >= 0) return 0.0299
                    if (s.indexOf("24 ga") >= 0) return 0.0239
                    var num = parseFloat(s)
                    return isFinite(num) && num > 0 ? num : 0.0598
                }
                var tInch = parseThicknessVal(tLabel)
                // Scale thickness noticeably: 1/2 in -> 16px, 16 ga -> 5px, 24 ga -> 3.5px
                var sheetThickPx = Math.max(3.5, Math.min(18.0, 3.5 + tInch * 25.0))

                // Realistic Material Shaders
                var matTheme = {
                    title: "COLD ROLLED STEEL",
                    colorLabel: "#94A3B8",
                    fillStart: "#475569", fillMid: "#64748B", fillEnd: "#334155",
                    stroke: "#94A3B8",
                    specular: "rgba(255, 255, 255, 0.40)"
                }
                if (matName.indexOf("stainless") >= 0 || matName.indexOf("304") >= 0 || matName.indexOf("316") >= 0) {
                    matTheme = {
                        title: "STAINLESS STEEL 304",
                        colorLabel: "#E2E8F0",
                        fillStart: "#CBD5E1", fillMid: "#FFFFFF", fillEnd: "#94A3B8",
                        stroke: "#FFFFFF",
                        specular: "rgba(255, 255, 255, 0.85)"
                    }
                } else if (matName.indexOf("aluminum") >= 0 || matName.indexOf("3003") >= 0 || matName.indexOf("6061") >= 0 || matName.indexOf("5052") >= 0) {
                    matTheme = {
                        title: "SOFT ALUMINUM 3003",
                        colorLabel: "#A7F3D0",
                        fillStart: "#E2E8F0", fillMid: "#F8FAFC", fillEnd: "#CBD5E1",
                        stroke: "#F1F5F9",
                        specular: "rgba(255, 255, 255, 0.70)"
                    }
                } else if (matName.indexOf("hot rolled") >= 0 || matName.indexOf("a36") >= 0) {
                    matTheme = {
                        title: "HOT ROLLED STEEL A36",
                        colorLabel: "#A1A1AA",
                        fillStart: "#1E293B", fillMid: "#374151", fillEnd: "#111827",
                        stroke: "#64748B",
                        specular: "rgba(255, 255, 255, 0.20)"
                    }
                } else if (matName.indexOf("copper") >= 0 || matName.indexOf("brass") >= 0) {
                    matTheme = {
                        title: "COPPER / BRASS",
                        colorLabel: "#FCD34D",
                        fillStart: "#B45309", fillMid: "#F59E0B", fillEnd: "#78350F",
                        stroke: "#FDE68A",
                        specular: "rgba(255, 255, 255, 0.60)"
                    }
                }

                // Look up preferred punch and preferred die
                var punchRecM = null
                if (pref && pref.preferredPunchId && dataStore.punches) {
                    for (var mpi = 0; mpi < dataStore.punches.length; mpi++) {
                        if (dataStore.punches[mpi].id === pref.preferredPunchId) {
                            punchRecM = dataStore.punches[mpi]
                            break
                        }
                    }
                }
                if (!punchRecM && dataStore.punches && dataStore.punches.length > 0)
                    punchRecM = dataStore.punches[0]

                var dieRecM = null
                if (pref && pref.preferredDieId && dataStore.dies) {
                    for (var mdi = 0; mdi < dataStore.dies.length; mdi++) {
                        if (dataStore.dies[mdi].id === pref.preferredDieId) {
                            dieRecM = dataStore.dies[mdi]
                            break
                        }
                    }
                }
                if (!dieRecM && dataStore.dies && dataStore.dies.length > 0)
                    dieRecM = dataStore.dies[0]

                ctx.save()

                // Standard 90-degree air bend representation for universal clarity
                var halfBendRad = 45.0 * (Math.PI / 180.0) // 0.785398 rad
                var sinA = 0.70710678
                var cosA = 0.70710678

                // Vertically centered at 128px for balanced proportions
                var bendApexY = 128

                // -------------------------------------------------------------
                // 1. Render Die at bottom (balanced scale so it is never tiny)
                // -------------------------------------------------------------
                var dieDxfPathM = dieRecM ? root.dxfAssetPath("die", dieRecM.name || dieRecM.id) : ""
                var dieDxfModelM = dieDxfPathM ? root.loadDxfModel(dieDxfPathM) : null

                var is4WayM = dieRecM && (String(dieRecM.name || "").toLowerCase().indexOf("4 way") >= 0
                        || String(dieRecM.name || "").toLowerCase().indexOf("4-way") >= 0
                        || String(dieRecM.name || "").indexOf("4387") >= 0)
                var rotDegM = 0
                var vValM = Number(dieRecM ? dieRecM.vdieOpeningInch : 0.866) || 0.866
                if (is4WayM) {
                    if (Math.abs(vValM - 0.630) < 0.05) rotDegM = 0
                    else if (Math.abs(vValM - 0.866) < 0.05) rotDegM = 180
                    else if (Math.abs(vValM - 1.378) < 0.05) rotDegM = 90
                    else if (Math.abs(vValM - 1.969) < 0.05) rotDegM = 270
                }
                var cosRM = Math.cos((rotDegM * Math.PI) / 180.0)
                var sinRM = Math.sin((rotDegM * Math.PI) / 180.0)

                var dieTopYM = bendApexY + sheetThickPx + 3

                if (dieDxfModelM && dieDxfModelM.bounds && isFinite(dieDxfModelM.bounds.minX)
                        && dieDxfModelM.polylines && dieDxfModelM.polylines.length > 0) {
                    var bDM = dieDxfModelM.bounds
                    var midXDM = (bDM.minX + bDM.maxX) * 0.5
                    var midYDM = (bDM.minY + bDM.maxY) * 0.5
                    var rotBM = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity }
                    var rPolysM = []

                    for (var dm1 = 0; dm1 < dieDxfModelM.polylines.length; dm1++) {
                        var pDM = dieDxfModelM.polylines[dm1]
                        if (!pDM.points || pDM.points.length < 2) continue
                        var ptsM = []
                        for (var dm2 = 0; dm2 < pDM.points.length; dm2++) {
                            var oxM = pDM.points[dm2].x - midXDM
                            var oyM = pDM.points[dm2].y - midYDM
                            var rxM = oxM * cosRM - oyM * sinRM
                            var ryM = oxM * sinRM + oyM * cosRM
                            rotBM.minX = Math.min(rotBM.minX, rxM); rotBM.maxX = Math.max(rotBM.maxX, rxM)
                            rotBM.minY = Math.min(rotBM.minY, ryM); rotBM.maxY = Math.max(rotBM.maxY, ryM)
                            ptsM.push({ x: rxM, y: ryM })
                        }
                        rPolysM.push({ points: ptsM, closed: pDM.closed })
                    }

                    // Generous die scale so all dies are clearly visible (never tiny)
                    var dieNatH = Math.max(0.1, rotBM.maxY - rotBM.minY)
                    var scaleDM = Math.min(36.0, 78.0 / dieNatH)
                    var toXDM = function(x) { return cx + x * scaleDM }
                    var toYDM = function(y) { return dieTopYM - (y - rotBM.maxY) * scaleDM }

                    for (var rmi = 0; rmi < rPolysM.length; rmi++) {
                        var rp = rPolysM[rmi]
                        ctx.beginPath()
                        ctx.moveTo(toXDM(rp.points[0].x), toYDM(rp.points[0].y))
                        for (var rpi2 = 1; rpi2 < rp.points.length; rpi2++) {
                            ctx.lineTo(toXDM(rp.points[rpi2].x), toYDM(rp.points[rpi2].y))
                        }
                        if (rp.closed) {
                            ctx.closePath()
                            var gradDieM = ctx.createLinearGradient(cx - 50, dieTopYM, cx + 50, dieTopYM + 80)
                            gradDieM.addColorStop(0, "#1E293B"); gradDieM.addColorStop(1, "#334155")
                            ctx.fillStyle = gradDieM; ctx.fill()
                        }
                        ctx.strokeStyle = "#60A5FA"; ctx.lineWidth = 1.4; ctx.stroke()
                    }
                } else {
                    // Parametric die block
                    var blockWM = 160, blockHM = 78
                    var vOpenPxM = Math.max(32, Math.min(85, vValM * 36))
                    var vDepM = (vOpenPxM * 0.5) / Math.tan(halfBendRad)
                    ctx.beginPath()
                    ctx.moveTo(cx - blockWM * 0.5, dieTopYM)
                    ctx.lineTo(cx - vOpenPxM * 0.5, dieTopYM)
                    ctx.lineTo(cx, dieTopYM + vDepM)
                    ctx.lineTo(cx + vOpenPxM * 0.5, dieTopYM)
                    ctx.lineTo(cx + blockWM * 0.5, dieTopYM)
                    ctx.lineTo(cx + blockWM * 0.5, dieTopYM + blockHM)
                    ctx.lineTo(cx - blockWM * 0.5, dieTopYM + blockHM)
                    ctx.closePath()
                    var gradDieFall = ctx.createLinearGradient(cx - 50, dieTopYM, cx + 50, dieTopYM + blockHM)
                    gradDieFall.addColorStop(0, "#1E293B"); gradDieFall.addColorStop(1, "#334155")
                    ctx.fillStyle = gradDieFall; ctx.fill()
                    ctx.strokeStyle = "#60A5FA"; ctx.lineWidth = 1.4; ctx.stroke()
                }

                // -------------------------------------------------------------
                // 2. Render Bent Sheet Metal Workpiece (90-Degree Standard Bend)
                // -------------------------------------------------------------
                var armLen = 64

                // Inner contour at 45° from vertical
                var inLx = cx - armLen * sinA
                var inLy = bendApexY - armLen * cosA
                var inRx = cx + armLen * sinA
                var inRy = bendApexY - armLen * cosA

                // Outer contour offset by sheetThickPx along normal
                var outNormX = cosA * sheetThickPx
                var outNormY = sinA * sheetThickPx
                var outRx = inRx + outNormX
                var outRy = inRy + outNormY
                var outApexY = bendApexY + sheetThickPx * 1.4142
                var outLx = inLx - outNormX
                var outLy = inLy + outNormY

                ctx.beginPath()
                ctx.moveTo(inLx, inLy)
                ctx.lineTo(cx, bendApexY)
                ctx.lineTo(inRx, inRy)
                ctx.lineTo(outRx, outRy)
                ctx.lineTo(cx, outApexY)
                ctx.lineTo(outLx, outLy)
                ctx.closePath()

                var sheetGrad = ctx.createLinearGradient(inLx, inLy, inRx, inRy)
                sheetGrad.addColorStop(0, matTheme.fillStart)
                sheetGrad.addColorStop(0.35, matTheme.fillMid)
                sheetGrad.addColorStop(0.5, matTheme.fillStart)
                sheetGrad.addColorStop(0.7, matTheme.fillMid)
                sheetGrad.addColorStop(1, matTheme.fillEnd)
                ctx.fillStyle = sheetGrad
                ctx.fill()

                ctx.strokeStyle = matTheme.stroke
                ctx.lineWidth = 1.6
                ctx.stroke()

                // Specular highlight line along inner bend fold
                ctx.strokeStyle = matTheme.specular
                ctx.lineWidth = 1.2
                ctx.beginPath()
                ctx.moveTo(inLx, inLy)
                ctx.lineTo(cx, bendApexY)
                ctx.lineTo(inRx, inRy)
                ctx.stroke()

                // -------------------------------------------------------------
                // 3. Render Punch descending from top (Tang Centered on Centerline)
                // -------------------------------------------------------------
                var punchDxfPathM = punchRecM ? root.dxfAssetPath("punch", punchRecM.name || punchRecM.id) : ""
                var punchDxfModelM = punchDxfPathM ? root.loadDxfModel(punchDxfPathM) : null

                if (punchDxfModelM && punchDxfModelM.bounds && isFinite(punchDxfModelM.bounds.minX)
                        && punchDxfModelM.polylines && punchDxfModelM.polylines.length > 0) {
                    var bPM = punchDxfModelM.bounds
                    var tangXPM = cadCanvas.getPunchTangCenterX(punchDxfModelM)
                    var punchNatH = Math.max(0.1, bPM.maxY - bPM.minY)
                    var scalePM = Math.min(26.0, 78.0 / punchNatH)

                    var toXPM = function(x) { return cx + (x - tangXPM) * scalePM }
                    var toYPM = function(y) { return bendApexY - (y - bPM.minY) * scalePM }

                    for (var pm1 = 0; pm1 < punchDxfModelM.polylines.length; pm1++) {
                        var pPolyM = punchDxfModelM.polylines[pm1]
                        if (!pPolyM.points || pPolyM.points.length < 2) continue
                        ctx.beginPath()
                        ctx.moveTo(toXPM(pPolyM.points[0].x), toYPM(pPolyM.points[0].y))
                        for (var pm2 = 1; pm2 < pPolyM.points.length; pm2++) {
                            ctx.lineTo(toXPM(pPolyM.points[pm2].x), toYPM(pPolyM.points[pm2].y))
                        }
                        if (pPolyM.closed) {
                            ctx.closePath()
                            var gradPunchM = ctx.createLinearGradient(cx - 40, bendApexY - 78, cx + 40, bendApexY)
                            gradPunchM.addColorStop(0, "#334155"); gradPunchM.addColorStop(1, "#475569")
                            ctx.fillStyle = gradPunchM; ctx.fill()
                        }
                        ctx.strokeStyle = "#F87171"; ctx.lineWidth = 1.4; ctx.stroke()
                    }
                } else {
                    // Parametric punch tip descending
                    var pAngleM = Number(punchRecM ? punchRecM.punchAngleDegree : 30.0) || 30.0
                    var halfAngPM = (pAngleM * 0.5) * (Math.PI / 180.0)
                    var tipWM = Math.sin(halfAngPM) * 40
                    ctx.beginPath()
                    ctx.moveTo(cx - 18, bendApexY - 76)
                    ctx.lineTo(cx + 18, bendApexY - 76)
                    ctx.lineTo(cx + tipWM, bendApexY - 14)
                    ctx.lineTo(cx, bendApexY)
                    ctx.lineTo(cx - tipWM, bendApexY - 14)
                    ctx.closePath()
                    var gradPFall = ctx.createLinearGradient(cx - 30, bendApexY - 76, cx + 30, bendApexY)
                    gradPFall.addColorStop(0, "#334155"); gradPFall.addColorStop(1, "#475569")
                    ctx.fillStyle = gradPFall; ctx.fill()
                    ctx.strokeStyle = "#F87171"; ctx.lineWidth = 1.4; ctx.stroke()
                }

                // -------------------------------------------------------------
                // 4. Engineering Callouts & Tooling Labels
                // -------------------------------------------------------------
                // Thickness Leader Line: placed in open area on the right, clear of top badges!
                var flMidX = (cx + outRx) * 0.5
                var flMidY = (outApexY + outRy) * 0.5
                var leaderStartX = flMidX
                var leaderStartY = flMidY
                var leaderMidX = leaderStartX + 22
                var leaderEndX = leaderMidX + 24

                ctx.strokeStyle = "#FACC15"; ctx.lineWidth = 1.2
                ctx.beginPath()
                ctx.moveTo(leaderStartX, leaderStartY)
                ctx.lineTo(leaderMidX, leaderStartY)
                ctx.lineTo(leaderEndX, leaderStartY)
                ctx.stroke()
                ctx.fillStyle = "#FACC15"
                ctx.beginPath(); ctx.arc(leaderStartX, leaderStartY, 2.5, 0, Math.PI * 2); ctx.fill()

                var thText = "t=" + tLabel + " (" + tInch.toFixed(3) + "\")"
                ctx.font = "bold 10px Consolas, monospace"
                var thw = ctx.measureText(thText).width
                ctx.fillStyle = "rgba(15, 23, 42, 0.92)"
                ctx.fillRect(leaderEndX + 3, leaderStartY - 8, thw + 8, 16)
                ctx.strokeStyle = "#EAB308"; ctx.lineWidth = 0.8
                ctx.strokeRect(leaderEndX + 3, leaderStartY - 8, thw + 8, 16)
                ctx.fillStyle = "#FEF08A"; ctx.textAlign = "left"
                ctx.fillText(thText, leaderEndX + 7, leaderStartY + 4)

                // Punch & Die labels
                ctx.font = "bold 9px Consolas, monospace"
                ctx.fillStyle = "#F87171"; ctx.textAlign = "left"
                var pLabelName = "Punch: " + (punchRecM ? (punchRecM.name || "Punch") : "Punch")
                if (pLabelName.length > 28) pLabelName = pLabelName.substring(0, 26) + "..."
                ctx.fillText(pLabelName, 12, 38)

                ctx.fillStyle = "#60A5FA"
                var dLabelName = "Die: " + (dieRecM ? (dieRecM.name || "Die") : "Die")
                if (dLabelName.length > 28) dLabelName = dLabelName.substring(0, 26) + "..."
                ctx.fillText(dLabelName, 12, height - 26)

                // Bottom Physics Summary Pill
                var summaryText = matTheme.title + " · 90° BEND · Δθ = " + springback.toFixed(1) + "° · " + (tensile / 1000).toFixed(0) + " ksi"
                ctx.font = "bold 10px Consolas, monospace"
                var smw = ctx.measureText(summaryText).width
                ctx.fillStyle = "rgba(15, 23, 42, 0.92)"
                ctx.fillRect(cx - smw * 0.5 - 6, height - 20, smw + 12, 16)
                ctx.strokeStyle = "#334155"; ctx.lineWidth = 0.8
                ctx.strokeRect(cx - smw * 0.5 - 6, height - 20, smw + 12, 16)
                ctx.fillStyle = matTheme.colorLabel; ctx.textAlign = "center"
                ctx.fillText(summaryText, cx, height - 8)

                ctx.restore()
            }
        }
    }

    // Bottom Left Card: Segment Inventory (or Material Thickness Deck)
    Rectangle {
        id: bottomCard
        x: 10
        y: 332
        width: 414
        height: 298
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // Header Row (without confusing total bar / bed assembly)
            Row {
                width: parent.width
                height: 24

                Text {
                    text: root.activeTab === 2 ? qsTr("MATERIAL THICKNESS PROFILES") : qsTr("SEGMENT INVENTORY")
                    font.pixelSize: 12
                    font.bold: true
                    color: root.ink
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Segment Inventory Cards (for Punches & Dies)
            // Reorganized to completely eliminate dead space after the [+] button!
            Column {
                visible: root.activeTab !== 2
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { size: 16, label: "16\" SEGMENT", key: "segmentCount16In" },
                        { size: 8,  label: "8\" SEGMENT",  key: "segmentCount8In" },
                        { size: 4,  label: "4\" SEGMENT",  key: "segmentCount4In" },
                        { size: 2,  label: "2\" SEGMENT",  key: "segmentCount2In" },
                        { size: 1,  label: "1\" SEGMENT",  key: "segmentCount1In" }
                    ]

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: parent.width
                        height: 44
                        color: root.cardBgAlt
                        radius: 5
                        border.color: root.cardBorder
                        border.width: 1

                        readonly property int countVal: {
                            var rec = root.selectedRecord
                            var n = Number(rec[modelData.key])
                            return isFinite(n) && n >= 0 ? Math.round(n) : 0
                        }

                        // Left Side: Badge and Subtotal
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Rectangle {
                                width: 95
                                height: 26
                                radius: 4
                                color: "#E2E8F0"
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: root.ink
                                }
                            }

                            Text {
                                text: qsTr("%1 × %2\" = %3\"").arg(countVal).arg(modelData.size).arg(countVal * modelData.size)
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: countVal > 0 ? root.textSecondary : root.textMuted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Right Side: Steppers Flush to Right Edge (Zero dead space!)
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            // Decrement [-]
                            Rectangle {
                                width: 34
                                height: 30
                                radius: 4
                                color: minusArea.containsMouse ? "#CBD5E1" : "#E2E8F0"
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 16; font.bold: true; color: root.ink }
                                MouseArea {
                                    id: minusArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSegmentCount(modelData.size, -1)
                                }
                            }

                            // Numeric Input Box
                            Rectangle {
                                width: 50
                                height: 30
                                radius: 4
                                color: "#FFFFFF"
                                border.color: countVal > 0 ? root.activeAccent : root.cardBorder
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: String(countVal)
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: countVal > 0 ? root.activeAccent : root.textMuted
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openNumericInput(modelData.label + " Count", countVal, function(val) {
                                        root.setSegmentCount(modelData.size, 0, val)
                                    })
                                }
                            }

                            // Increment [+]
                            Rectangle {
                                width: 34
                                height: 30
                                radius: 4
                                color: plusArea.containsMouse ? Qt.darker(root.activeAccent, 1.15) : root.activeAccent
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 16; font.bold: true; color: "#FFFFFF" }
                                MouseArea {
                                    id: plusArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSegmentCount(modelData.size, 1)
                                }
                            }
                        }
                    }
                }
            }

            // Material Studio: Interactive Thickness Profiles List
            Column {
                visible: root.activeTab === 2
                width: parent.width
                spacing: 8

                Text {
                    text: qsTr("Select thickness to view or configure preferred tooling:")
                    font.pixelSize: 11
                    color: root.textSecondary
                }

                // Grid of Thickness Chips
                Flow {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.activeThicknessPreferences
                        delegate: Rectangle {
                            required property int index
                            required property var modelData

                            readonly property bool isSelected: root.selectedThicknessIndex === index
                            width: 90
                            height: 38
                            radius: 5
                            color: isSelected ? root.greenAccent : (thChipMouse.containsMouse ? "#E2E8F0" : root.cardBgAlt)
                            border.color: isSelected ? root.greenAccent : root.cardBorder
                            border.width: 1

                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    text: modelData.thicknessLabel || "N/A"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: isSelected ? "#FFFFFF" : root.ink
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: modelData.preferredDieId ? qsTr("Configured") : qsTr("Default")
                                    font.pixelSize: 9
                                    color: isSelected ? "#DCFCE7" : root.textMuted
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                id: thChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedThicknessIndex = index
                            }
                        }
                    }

                    // Add Custom Thickness Button
                    Rectangle {
                        width: 90
                        height: 38
                        radius: 5
                        color: "#F8FAFC"
                        border.color: "#94A3B8"
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text { text: "+"; font.pixelSize: 14; font.bold: true; color: root.greenAccent }
                            Text { text: qsTr("ADD"); font.pixelSize: 10; font.bold: true; color: root.greenAccent }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.openTextInput(qsTr("Enter Thickness Label (e.g. 14 ga, 1/4 in)"), "14 ga", function(val) {
                                    if (val && String(val).trim().length > 0)
                                        root.addNewThicknessPreference(String(val).trim())
                                })
                            }
                        }
                    }
                }

                // Air Bending Rule Summary Card
                Rectangle {
                    width: parent.width
                    height: 95
                    color: root.cardBgAlt
                    radius: 5
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text { text: qsTr("RECOMMENDED AIR BENDING DESIGN RULES"); font.pixelSize: 10; font.bold: true; color: root.ink }
                        Text { text: qsTr("• Optimal Die Opening: V = 8 × t (for sheet t < 0.25\")"); font.pixelSize: 9; color: root.textSecondary }
                        Text { text: qsTr("• Inside Bend Radius: Ri ≈ 0.15 × V opening"); font.pixelSize: 9; color: root.textSecondary }
                        Text { text: qsTr("• Minimum Flange Width: b_min ≈ 0.7 × V opening"); font.pixelSize: 9; color: root.textSecondary }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 3. RIGHT PANEL: RECORD SELECTOR & SPECIFICATION DECK (x: 434, y: 56, width: 420, height: 506)
    // =========================================================================
    Rectangle {
        id: rightDeck
        x: 434
        y: 56
        width: 420
        height: 506
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // 1. Record Header & Selector Pod
            Rectangle {
                width: parent.width
                height: 58
                color: root.cardBgAlt
                radius: 5
                border.color: root.cardBorder
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Prev Button
                    Rectangle {
                        width: 32
                        height: 40
                        radius: 4
                        color: prevMouse.containsMouse ? "#CBD5E1" : "#E2E8F0"
                        anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: "◀"; font.pixelSize: 12; color: root.ink }
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.activeTab === 0) root.punchIndex = Math.max(0, root.punchIndex - 1)
                                else if (root.activeTab === 1) root.dieIndex = Math.max(0, root.dieIndex - 1)
                                else root.materialIndex = Math.max(0, root.materialIndex - 1)
                                cadCanvas.requestPaint()
                            }
                        }
                    }

                    // Active Record Title & ID
                    Column {
                        width: parent.width - 128
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: root.selectedRecord.name || "Default Tool"
                            font.pixelSize: 13
                            font.bold: true
                            color: root.ink
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: qsTr("INDEX %1 OF %2 · %3").arg(root.currentIndex + 1).arg(root.currentRecords.length).arg(root.selectedRecord.stock ? "FACTORY STOCK" : "CUSTOM USER TOOL")
                            font.pixelSize: 9
                            font.bold: true
                            color: root.selectedRecord.stock ? root.blueAccent : root.amberAccent
                        }
                    }

                    // Next Button
                    Rectangle {
                        width: 32
                        height: 40
                        radius: 4
                        color: nextMouse.containsMouse ? "#CBD5E1" : "#E2E8F0"
                        anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 12; color: root.ink }
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.activeTab === 0) root.punchIndex = Math.min((dataStore.punches || []).length - 1, root.punchIndex + 1)
                                else if (root.activeTab === 1) root.dieIndex = Math.min((dataStore.dies || []).length - 1, root.dieIndex + 1)
                                else root.materialIndex = Math.min((dataStore.materials || []).length - 1, root.materialIndex + 1)
                                cadCanvas.requestPaint()
                            }
                        }
                    }

                    // Rename / Edit Pen Button
                    Rectangle {
                        width: 32
                        height: 40
                        radius: 4
                        color: penMouse.containsMouse ? root.activeAccent : "#F1F5F9"
                        border.color: root.cardBorder
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            source: penMouse.containsMouse ? "../../icons/fa-pen-white.svg" : "../../icons/fa-pen.svg"
                            fillMode: Image.PreserveAspectFit
                        }

                        MouseArea {
                            id: penMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openTextInput(qsTr("Rename Tool Name"), root.selectedRecord.name, function(val) {
                                if (val && String(val).trim().length > 0)
                                    root.setStringField("name", String(val).trim())
                            })
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // SPECIFICATION CARDS ACCORDING TO ACTIVE STUDIO
            // -----------------------------------------------------------------

            // PUNCH STUDIO SPEC DECK
            Column {
                visible: root.activeTab === 0
                width: parent.width
                spacing: 8

                // Height Inch
                Rectangle {
                    width: parent.width; height: 42; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("PUNCH HEIGHT (INCH)"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 90; height: 28; radius: 4; color: "#FFFFFF"; border.color: root.redAccent; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.heightInch || 0).toFixed(3) + "\""; font.pixelSize: 12; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Punch Height (Inch)"), root.selectedRecord.heightInch, function(v) { root.setNumericField("heightInch", v) }) }
                        }
                    }
                }

                // Punch Angle Degree
                Rectangle {
                    width: parent.width; height: 42; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("TIP ANGLE (DEGREES)"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 90; height: 28; radius: 4; color: "#FFFFFF"; border.color: root.redAccent; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.punchAngleDegree || 0).toFixed(1) + "°"; font.pixelSize: 12; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Tip Angle (Degrees)"), root.selectedRecord.punchAngleDegree, function(v) { root.setNumericField("punchAngleDegree", v) }) }
                        }
                    }
                }

                // Punch Profile Type Selector
                Rectangle {
                    width: parent.width; height: 70; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Column {
                        anchors.fill: parent; anchors.margins: 8; spacing: 6
                        Text { text: qsTr("PUNCH PROFILE FAMILY"); font.pixelSize: 11; font.bold: true; color: root.ink }
                        Row {
                            spacing: 6
                            Repeater {
                                model: ["ACUTE", "STANDARD", "GOOSENECK", "EXTREME_GOOSENECK"]
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool isCur: String(root.selectedRecord.punchProfileType || "STANDARD").toUpperCase() === modelData
                                    width: 90; height: 26; radius: 3
                                    color: isCur ? root.redAccent : "#FFFFFF"; border.color: isCur ? root.redAccent : root.cardBorder; border.width: 1
                                    Text { anchors.centerIn: parent; text: modelData.replace("_", " "); font.pixelSize: 8; font.bold: true; color: isCur ? "#FFFFFF" : root.ink }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setStringField("punchProfileType", modelData) }
                                }
                            }
                        }
                    }
                }
            }

            // DIE STUDIO SPEC DECK
            Column {
                visible: root.activeTab === 1
                width: parent.width
                spacing: 8

                // V-Die Opening Inch
                Rectangle {
                    width: parent.width; height: 42; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("V-DIE OPENING (INCH)"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 90; height: 28; radius: 4; color: "#FFFFFF"; border.color: root.blueAccent; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.vdieOpeningInch || 0).toFixed(3) + "\""; font.pixelSize: 12; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("V-Die Opening (Inch)"), root.selectedRecord.vdieOpeningInch, function(v) { root.setNumericField("vdieOpeningInch", v) }) }
                        }
                    }
                }

                // Die Angle Degree
                Rectangle {
                    width: parent.width; height: 42; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("DIE V-GROOVE ANGLE"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 90; height: 28; radius: 4; color: "#FFFFFF"; border.color: root.blueAccent; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.dieAngleDegree || 0).toFixed(1) + "°"; font.pixelSize: 12; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Die V Angle"), root.selectedRecord.dieAngleDegree, function(v) { root.setNumericField("dieAngleDegree", v) }) }
                        }
                    }
                }

                // Die Height Inch
                Rectangle {
                    width: parent.width; height: 42; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("DIE BLOCK HEIGHT"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 90; height: 28; radius: 4; color: "#FFFFFF"; border.color: root.cardBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.heightInch || 0).toFixed(3) + "\""; font.pixelSize: 12; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Die Height (Inch)"), root.selectedRecord.heightInch, function(v) { root.setNumericField("heightInch", v) }) }
                        }
                    }
                }

                // Overall Width Inch
                Rectangle {
                    width: parent.width; height: 42; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("OVERALL BASE WIDTH"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 90; height: 28; radius: 4; color: "#FFFFFF"; border.color: root.cardBorder; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.overallWidthInch || 0).toFixed(3) + "\""; font.pixelSize: 12; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Overall Width (Inch)"), root.selectedRecord.overallWidthInch, function(v) { root.setNumericField("overallWidthInch", v) }) }
                        }
                    }
                }
            }

            // MATERIAL STUDIO SPEC DECK (FULLY FUNCTIONAL!)
            Column {
                visible: root.activeTab === 2
                width: parent.width
                spacing: 8

                // 1. Tensile Strength
                Rectangle {
                    width: parent.width; height: 40; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("TENSILE STRENGTH (PSI)"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 110; height: 26; radius: 3; color: "#FFFFFF"; border.color: root.greenAccent; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.materialTensileStrengthPsi || 0).toLocaleString() + " PSI"; font.pixelSize: 11; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Tensile Strength (PSI)"), root.selectedRecord.materialTensileStrengthPsi, function(val) { root.setNumericField("materialTensileStrengthPsi", val) }) }
                        }
                    }
                }

                // 2. Springback Angle
                Rectangle {
                    width: parent.width; height: 40; color: root.cardBgAlt; radius: 4; border.color: root.cardBorder; border.width: 1
                    Item {
                        anchors.fill: parent; anchors.margins: 8
                        Text { text: qsTr("MATERIAL SPRINGBACK (Δθ)"); font.pixelSize: 11; font.bold: true; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 80; height: 26; radius: 3; color: "#FFFFFF"; border.color: root.greenAccent; border.width: 1
                            Text { anchors.centerIn: parent; text: Number(root.selectedRecord.materialSpringback || 0).toFixed(1) + "°"; font.pixelSize: 11; font.bold: true; font.family: "Consolas, monospace"; color: root.ink }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openNumericInput(qsTr("Springback (Degrees)"), root.selectedRecord.materialSpringback, function(val) { root.setNumericField("materialSpringback", val) }) }
                        }
                    }
                }

                // 3. Active Thickness Tooling Preferences Editor Card
                Rectangle {
                    width: parent.width
                    height: 180
                    color: root.cardBgAlt
                    radius: 5
                    border.color: root.greenAccent
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        // Header with selected thickness label
                        Row {
                            width: parent.width
                            height: 22
                            spacing: 6
                            Rectangle { width: 4; height: 16; radius: 2; color: root.greenAccent; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: qsTr("TOOLING PREFERENCE: %1").arg(root.currentThicknessPref ? root.currentThicknessPref.thicknessLabel : qsTr("NONE"))
                                font.pixelSize: 11
                                font.bold: true
                                color: root.ink
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Preferred Punch Selector
                        Row {
                            width: parent.width
                            height: 32
                            spacing: 8

                            Text { text: qsTr("Preferred Punch:"); font.pixelSize: 10; font.bold: true; color: root.textSecondary; width: 110; anchors.verticalCenter: parent.verticalCenter }

                            Rectangle {
                                width: parent.width - 120
                                height: 28
                                radius: 4
                                color: "#FFFFFF"
                                border.color: root.redAccent
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.ink
                                    text: {
                                        var pref = root.currentThicknessPref
                                        if (!pref || !pref.preferredPunchId) return qsTr("Select Punch...")
                                        var punches = dataStore.punches || []
                                        for (var i = 0; i < punches.length; i++) {
                                            if (punches[i].id === pref.preferredPunchId) return punches[i].name
                                        }
                                        return pref.preferredPunchId
                                    }
                                }

                                Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "▼"; font.pixelSize: 9; color: root.textMuted }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var punches = dataStore.punches || []
                                        if (punches.length === 0) return
                                        var pref = root.currentThicknessPref
                                        var curIdx = 0
                                        for (var i = 0; i < punches.length; i++) {
                                            if (pref && punches[i].id === pref.preferredPunchId) { curIdx = i; break }
                                        }
                                        var nextIdx = (curIdx + 1) % punches.length
                                        root.setThicknessPreferenceField("preferredPunchId", punches[nextIdx].id)
                                    }
                                }
                            }
                        }

                        // Preferred Die Selector
                        Row {
                            width: parent.width
                            height: 32
                            spacing: 8

                            Text { text: qsTr("Preferred Die:"); font.pixelSize: 10; font.bold: true; color: root.textSecondary; width: 110; anchors.verticalCenter: parent.verticalCenter }

                            Rectangle {
                                width: parent.width - 120
                                height: 28
                                radius: 4
                                color: "#FFFFFF"
                                border.color: root.blueAccent
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.ink
                                    text: {
                                        var pref = root.currentThicknessPref
                                        if (!pref || !pref.preferredDieId) return qsTr("Select Die...")
                                        var dies = dataStore.dies || []
                                        for (var i = 0; i < dies.length; i++) {
                                            if (dies[i].id === pref.preferredDieId) return dies[i].name
                                        }
                                        return pref.preferredDieId
                                    }
                                }

                                Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "▼"; font.pixelSize: 9; color: root.textMuted }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var dies = dataStore.dies || []
                                        if (dies.length === 0) return
                                        var pref = root.currentThicknessPref
                                        var curIdx = 0
                                        for (var i = 0; i < dies.length; i++) {
                                            if (pref && dies[i].id === pref.preferredDieId) { curIdx = i; break }
                                        }
                                        var nextIdx = (curIdx + 1) % dies.length
                                        root.setThicknessPreferenceField("preferredDieId", dies[nextIdx].id)
                                    }
                                }
                            }
                        }

                        // Punch Clearance %
                        Row {
                            width: parent.width
                            height: 32
                            spacing: 8

                            Text { text: qsTr("Punch Clearance %:"); font.pixelSize: 10; font.bold: true; color: root.textSecondary; width: 110; anchors.verticalCenter: parent.verticalCenter }

                            Rectangle {
                                width: 90
                                height: 28
                                radius: 4
                                color: "#FFFFFF"
                                border.color: root.cardBorder
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                    color: root.ink
                                    text: {
                                        var pref = root.currentThicknessPref
                                        var val = pref ? Number(pref.punchToMaterialClearancePercent) : NaN
                                        return isFinite(val) ? val.toFixed(1) + " %" : qsTr("AUTO")
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var pref = root.currentThicknessPref
                                        var curVal = pref && isFinite(Number(pref.punchToMaterialClearancePercent)) ? Number(pref.punchToMaterialClearancePercent) : 85.0
                                        root.openNumericInput(qsTr("Punch Clearance (%)"), curVal, function(val) {
                                            var n = Number(val)
                                            if (isFinite(n)) root.setThicknessPreferenceField("punchToMaterialClearancePercent", n)
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

    // =========================================================================
    // 4. BOTTOM ACTION COMMAND HUB (x: 434, y: 570, width: 420, height: 54)
    //    NEW (+), SAVE (fa-save), DUPLICATE (fa-file), DELETE (fa-trash)
    //    Pixel-perfect vertical & horizontal alignment with crisp SVG icons.
    // =========================================================================
    Rectangle {
        id: actionHub
        x: 434
        y: 570
        width: 420
        height: 54
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // 1. NEW BUTTON
            Rectangle {
                width: 92
                height: 38
                radius: 4
                color: newMouse.containsMouse ? Qt.darker(root.activeAccent, 1.15) : root.activeAccent

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                        width: 13
                        height: 13
                        source: "../../icons/fa-plus.svg"
                        sourceSize.width: 13
                        sourceSize.height: 13
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: qsTr("NEW")
                        font.pixelSize: 11
                        font.bold: true
                        color: "#FFFFFF"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: newMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("NEW")
                }
            }

            // 2. SAVE BUTTON
            Rectangle {
                width: 92
                height: 38
                radius: 4
                color: saveMouse.containsMouse ? "#111827" : root.charcoal

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                        width: 13
                        height: 13
                        source: "../../icons/fa-save.svg"
                        sourceSize.width: 13
                        sourceSize.height: 13
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: qsTr("SAVE")
                        font.pixelSize: 11
                        font.bold: true
                        color: "#FFFFFF"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: saveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("SAVE")
                }
            }

            // 3. DUPLICATE BUTTON
            Rectangle {
                width: 104
                height: 38
                radius: 4
                color: dupMouse.containsMouse ? Qt.darker(root.amberAccent, 1.15) : root.amberAccent

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                        width: 13
                        height: 13
                        source: "../../icons/fa-file-black.svg"
                        sourceSize.width: 13
                        sourceSize.height: 13
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: qsTr("DUPLICATE")
                        font.pixelSize: 11
                        font.bold: true
                        color: "#1E293B"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: dupMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("DUPLICATE")
                }
            }

            // 4. DELETE BUTTON
            Rectangle {
                width: 98
                height: 38
                radius: 4
                color: delMouse.containsMouse ? Qt.darker(root.redAccent, 1.2) : root.redAccent
                opacity: root.currentRecords.length > 1 ? 1.0 : 0.45

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                        width: 13
                        height: 13
                        source: "../../icons/fa-trash.svg"
                        sourceSize.width: 13
                        sourceSize.height: 13
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: qsTr("DELETE")
                        font.pixelSize: 11
                        font.bold: true
                        color: "#FFFFFF"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: delMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.currentRecords.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.runToolAction("DELETE")
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Toast Notification Banner (Auto-dismissing)
    // -------------------------------------------------------------------------
    Rectangle {
        id: toastBanner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        height: 32
        width: toastLabel.implicitWidth + 28
        radius: 16
        color: "#0F172A"
        opacity: root.toastText.length > 0 ? 0.95 : 0.0
        visible: opacity > 0
        z: 999

        Behavior on opacity { NumberAnimation { duration: 180 } }

        Row {
            anchors.centerIn: parent
            spacing: 8
            Rectangle { width: 6; height: 6; radius: 3; color: root.activeAccent; anchors.verticalCenter: parent.verticalCenter }
            Text {
                id: toastLabel
                text: root.toastText
                font.pixelSize: 11
                font.bold: true
                color: "#FFFFFF"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}


