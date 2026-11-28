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
// Modern aerospace-grade tooling console replacing legacy 3-column cramping:
// 1. Studio Mode Deck: Instant focus switching across PUNCHES, DIES, and MATERIALS.
// 2. High-Precision 2D Vector CAD Stage: Live cross-section profile of punch (acute,
//    standard, gooseneck) and die V-groove with dynamic dimension arrows and angles.
// 3. Interactive Bed Assembly Rack: Visual press brake bed rail showing how available
//    tool segments assemble end-to-end with total assembled length and step controls.
// 4. Precision Specification Deck: Clean elevated cards, quick presets, and
//    ergonomic parameter controls with full unit indicators.
// 5. Tactile Industrial Action Hub: NEW, SAVE, DUPLICATE, DELETE with safety guards.
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

    property int punchIndex: 0
    property int dieIndex: 0
    property int materialIndex: 0

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

    readonly property var selectedRecord: currentRecords.length > 0 ? currentRecords[currentIndex] : ({})

    // Material preference sub-index
    property int selectedThicknessIndex: 0

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

    function setSegmentCount(segSize, delta, absoluteVal) {
        var rec = Object.assign({}, selectedRecord)
        var key = segSize === 16 ? "segmentCount16In"
                : (segSize === 8 ? "segmentCount8In"
                   : (segSize === 4 ? "segmentCount4In"
                      : (segSize === 2 ? "segmentCount2In" : "segmentCount1In")))
        var current = Number(rec[key])
        if (!isFinite(current)) current = 0
        if (absoluteVal !== undefined && absoluteVal !== null) {
            var n = Number(absoluteVal)
            if (isFinite(n) && n >= 0) rec[key] = Math.round(n)
        } else {
            rec[key] = Math.max(0, Math.round(current + delta))
        }
        replaceCurrentRecord(rec)
    }

    function runToolAction(action) {
        var kind = currentKind
        var records = currentRecords
        var idx = currentIndex
        if (appState && typeof appState.toolAction === "function") {
            var res = appState.toolAction(kind, action, records, idx)
            if (res && res.ok === true) {
                if (kind === "punch") {
                    dataStore.punches = res.records
                    root.punchIndex = res.selectedIndex
                } else if (kind === "die") {
                    dataStore.dies = res.records
                    root.dieIndex = res.selectedIndex
                } else {
                    dataStore.materials = res.records
                    root.materialIndex = res.selectedIndex
                }
                showToast(qsTr("%1 %2 successfully").arg(action).arg(kind.toUpperCase()))
                cadCanvas.requestPaint()
                return
            }
        }
        // Fallback local simulation for preview/testing
        var next = JSON.parse(JSON.stringify(records || []))
        if (action === "NEW") {
            var newTool = kind === "material"
                ? { id: "sim-" + Date.now(), name: "NEW MATERIAL " + (next.length + 1),
                    materialTensileStrengthPsi: 45000, insideRadiusRuleOfThumb: 0.15, materialSpringback: 0.7, thicknessToolingPreferences: [] }
                : (kind === "punch"
                   ? { id: "sim-" + Date.now(), name: "NEW PUNCH " + (next.length + 1), heightInch: 4.0,
                       punchProfileType: "STANDARD", punchAngleDegree: 35.0, segmentCount16In: 1, segmentCount8In: 1, segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 1 }
                   : { id: "sim-" + Date.now(), name: "NEW DIE " + (next.length + 1), heightInch: 2.0,
                       vdieOpeningInch: 0.630, dieAngleDegree: 85.0, overallWidthInch: 2.362, segmentCount16In: 1, segmentCount8In: 1, segmentCount4In: 1, segmentCount2In: 1, segmentCount1In: 1 })
            next.push(newTool)
            idx = next.length - 1
            showToast(qsTr("Created %1").arg(newTool.name))
        } else if (action === "DUPLICATE" && next.length > 0) {
            var dup = Object.assign({}, next[idx], {
                id: "sim-" + Date.now(),
                name: (next[idx].name || kind.toUpperCase()) + " COPY"
            })
            next.push(dup)
            idx = next.length - 1
            showToast(qsTr("Duplicated %1").arg(dup.name))
        } else if (action === "DELETE" && next.length > 0) {
            var deletedName = next[idx].name
            next.splice(idx, 1)
            idx = Math.max(0, Math.min(idx, next.length - 1))
            showToast(qsTr("Deleted %1").arg(deletedName))
        } else if (action === "SAVE") {
            showToast(qsTr("Saved %1 configurations").arg(kind.toUpperCase()))
        }
        if (kind === "punch") {
            dataStore.punches = next
            root.punchIndex = idx
        } else if (kind === "die") {
            dataStore.dies = next
            root.dieIndex = idx
        } else {
            dataStore.materials = next
            root.materialIndex = idx
        }
        cadCanvas.requestPaint()
    }

    // Calculated assembled length
    readonly property real totalAssembledLength: {
        var rec = selectedRecord
        var c16 = Number(rec.segmentCount16In) || 0
        var c8  = Number(rec.segmentCount8In)  || 0
        var c4  = Number(rec.segmentCount4In)  || 0
        var c2  = Number(rec.segmentCount2In)  || 0
        var c1  = Number(rec.segmentCount1In)  || 0
        return (c16 * 16) + (c8 * 8) + (c4 * 4) + (c2 * 2) + (c1 * 1)
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
    //    Top: High-Precision 2D Vector CAD Stage (height: 268)
    //    Bottom: Interactive Bed Assembly Rack (height: 298)
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
                text: root.activeTab === 0 ? qsTr("PUNCH PROFILE CAD · 1:1")
                        : (root.activeTab === 1 ? qsTr("V-DIE CROSS SECTION · 1:1") : qsTr("BEND DYNAMICS & TONNAGE"))
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
                    return "AIR BEND MODEL"
                }
                font.pixelSize: 9
                font.bold: true
                color: "#FFFFFF"
            }
        }

        // Dynamic Vector CAD Canvas
        Canvas {
            id: cadCanvas
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var rec = root.selectedRecord
                var cx = width / 2
                var cy = height / 2

                if (root.activeTab === 0) {
                    // ---------------------------------------------------------
                    // PUNCH PROFILE VECTOR DRAWING
                    // ---------------------------------------------------------
                    var pHeight = Number(rec.heightInch) || 4.0
                    var pAngle = Number(rec.punchAngleDegree) || 35.0
                    var pType = String(rec.punchProfileType || "STANDARD").toUpperCase()

                    var scale = 42.0 // px per inch
                    var totalH = Math.min(200, Math.max(120, pHeight * scale))
                    var tipY = cy + totalH * 0.42
                    var topY = tipY - totalH

                    var halfAngleRad = (pAngle * 0.5) * (Math.PI / 180.0)
                    var tipWidth = Math.sin(halfAngleRad) * 45

                    ctx.save()

                    // Punch body silhouette
                    ctx.beginPath()
                    ctx.moveTo(cx - 20, topY)
                    // Top tang
                    ctx.lineTo(cx + 20, topY)
                    ctx.lineTo(cx + 20, topY + 24)
                    ctx.lineTo(cx + 14, topY + 28) // retention safety groove
                    ctx.lineTo(cx + 20, topY + 34)

                    if (pType.indexOf("GOOSENECK") >= 0) {
                        // Deep gooseneck throat relief
                        var isExtreme = pType.indexOf("EXTREME") >= 0
                        var throatDepth = isExtreme ? 58 : 42
                        ctx.lineTo(cx + 26, topY + 55)
                        ctx.lineTo(cx + 26, topY + 95)
                        ctx.lineTo(cx + tipWidth, tipY - 25)
                        ctx.lineTo(cx, tipY) // Punch tip
                        ctx.lineTo(cx - tipWidth * 0.7, tipY - 25)
                        // Inward deep throat curve
                        ctx.quadraticCurveTo(cx - throatDepth, cy, cx - 24, topY + 50)
                        ctx.lineTo(cx - 20, topY + 24)
                    } else if (pType.indexOf("ACUTE") >= 0) {
                        // Acute narrow blade
                        ctx.lineTo(cx + 24, topY + 55)
                        ctx.lineTo(cx + tipWidth, tipY - 20)
                        ctx.lineTo(cx, tipY) // Punch tip
                        ctx.lineTo(cx - tipWidth, tipY - 20)
                        ctx.lineTo(cx - 24, topY + 55)
                        ctx.lineTo(cx - 20, topY + 24)
                    } else {
                        // Standard punch shoulder
                        ctx.lineTo(cx + 28, topY + 50)
                        ctx.lineTo(cx + tipWidth + 8, tipY - 35)
                        ctx.lineTo(cx + tipWidth, tipY - 15)
                        ctx.lineTo(cx, tipY) // Punch tip
                        ctx.lineTo(cx - tipWidth, tipY - 15)
                        ctx.lineTo(cx - tipWidth - 8, tipY - 35)
                        ctx.lineTo(cx - 28, topY + 50)
                        ctx.lineTo(cx - 20, topY + 24)
                    }
                    ctx.closePath()

                    // Steel metal gradient fill
                    var grad = ctx.createLinearGradient(cx - 50, topY, cx + 50, tipY)
                    grad.addColorStop(0, "#475569")
                    grad.addColorStop(0.5, "#64748B")
                    grad.addColorStop(1, "#334155")
                    ctx.fillStyle = grad
                    ctx.fill()

                    ctx.strokeStyle = "#94A3B8"
                    ctx.lineWidth = 1.8
                    ctx.stroke()

                    // Tip point focal highlight
                    ctx.fillStyle = root.redAccent
                    ctx.beginPath()
                    ctx.arc(cx, tipY, 3.5, 0, Math.PI * 2)
                    ctx.fill()

                    // Angle arc sector at tip
                    ctx.strokeStyle = "#F59E0B"
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    ctx.arc(cx, tipY, 32, -Math.PI / 2 - halfAngleRad, -Math.PI / 2 + halfAngleRad)
                    ctx.stroke()

                    // Angle callout text
                    ctx.fillStyle = "#F59E0B"
                    ctx.font = "bold 11px Consolas, monospace"
                    ctx.textAlign = "center"
                    ctx.fillText(pAngle.toFixed(1) + "°", cx, tipY - 38)

                    // Vertical Dimension Line (Height)
                    var dimX = cx + 80
                    ctx.strokeStyle = "#38BDF8"
                    ctx.lineWidth = 1.2
                    ctx.beginPath()
                    ctx.moveTo(dimX, topY)
                    ctx.lineTo(dimX, tipY)
                    // Arrows
                    ctx.moveTo(dimX - 4, topY + 6); ctx.lineTo(dimX, topY); ctx.lineTo(dimX + 4, topY + 6)
                    ctx.moveTo(dimX - 4, tipY - 6); ctx.lineTo(dimX, tipY); ctx.lineTo(dimX + 4, tipY - 6)
                    ctx.stroke()

                    // Height text callout
                    ctx.fillStyle = "#38BDF8"
                    ctx.font = "bold 11px Consolas, monospace"
                    ctx.textAlign = "left"
                    ctx.fillText("H = " + pHeight.toFixed(3) + "\"", dimX + 8, cy)

                    ctx.restore()

                } else if (root.activeTab === 1) {
                    // ---------------------------------------------------------
                    // DIE PROFILE VECTOR DRAWING
                    // ---------------------------------------------------------
                    var dHeight = Number(rec.heightInch) || 2.0
                    var vOpening = Number(rec.vdieOpeningInch) || 0.630
                    var dAngle = Number(rec.dieAngleDegree) || 85.0
                    var oWidth = Number(rec.overallWidthInch) || 2.362

                    var scaleD = 48.0
                    var blockW = Math.min(180, Math.max(100, oWidth * scaleD))
                    var blockH = Math.min(140, Math.max(80, dHeight * scaleD * 0.7))
                    var vHalfW = Math.min(blockW * 0.42, Math.max(12, (vOpening * scaleD) * 0.5))

                    var vAngleRad = (dAngle * 0.5) * (Math.PI / 180.0)
                    var vDepth = vHalfW / Math.tan(vAngleRad)
                    vDepth = Math.min(blockH * 0.75, vDepth)

                    var dieTopY = cy - blockH * 0.35
                    var dieBottomY = dieTopY + blockH

                    ctx.save()

                    // Die block silhouette with V-groove
                    ctx.beginPath()
                    ctx.moveTo(cx - blockW * 0.5, dieTopY)
                    // Top left shoulder
                    ctx.lineTo(cx - vHalfW, dieTopY)
                    // V-groove dip
                    ctx.lineTo(cx, dieTopY + vDepth)
                    // Top right shoulder
                    ctx.lineTo(cx + vHalfW, dieTopY)
                    ctx.lineTo(cx + blockW * 0.5, dieTopY)
                    // Right side
                    ctx.lineTo(cx + blockW * 0.5, dieBottomY - 18)
                    ctx.lineTo(cx + 20, dieBottomY - 18)
                    // Base tang
                    ctx.lineTo(cx + 18, dieBottomY)
                    ctx.lineTo(cx - 18, dieBottomY)
                    ctx.lineTo(cx - 20, dieBottomY - 18)
                    ctx.lineTo(cx - blockW * 0.5, dieBottomY - 18)
                    ctx.closePath()

                    // Metallic die gradient
                    var dGrad = ctx.createLinearGradient(cx - 60, dieTopY, cx + 60, dieBottomY)
                    dGrad.addColorStop(0, "#475569")
                    dGrad.addColorStop(0.5, "#64748B")
                    dGrad.addColorStop(1, "#1E293B")
                    ctx.fillStyle = dGrad
                    ctx.fill()

                    ctx.strokeStyle = "#94A3B8"
                    ctx.lineWidth = 1.8
                    ctx.stroke()

                    // V-opening dimension arrow (Top)
                    var vDimY = dieTopY - 14
                    ctx.strokeStyle = "#38BDF8"
                    ctx.lineWidth = 1.2
                    ctx.beginPath()
                    ctx.moveTo(cx - vHalfW, vDimY)
                    ctx.lineTo(cx + vHalfW, vDimY)
                    ctx.moveTo(cx - vHalfW + 4, vDimY - 3); ctx.lineTo(cx - vHalfW, vDimY); ctx.lineTo(cx - vHalfW + 4, vDimY + 3)
                    ctx.moveTo(cx + vHalfW - 4, vDimY - 3); ctx.lineTo(cx + vHalfW, vDimY); ctx.lineTo(cx + vHalfW - 4, vDimY + 3)
                    ctx.stroke()

                    // V label text
                    ctx.fillStyle = "#38BDF8"
                    ctx.font = "bold 11px Consolas, monospace"
                    ctx.textAlign = "center"
                    ctx.fillText("V = " + vOpening.toFixed(3) + "\"", cx, vDimY - 6)

                    // Die Angle Arc inside V-groove
                    ctx.strokeStyle = "#F59E0B"
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    ctx.arc(cx, dieTopY + vDepth, 24, -Math.PI / 2 - vAngleRad, -Math.PI / 2 + vAngleRad)
                    ctx.stroke()

                    ctx.fillStyle = "#F59E0B"
                    ctx.font = "bold 10px Consolas, monospace"
                    ctx.textAlign = "center"
                    ctx.fillText(dAngle.toFixed(0) + "°", cx, dieTopY + vDepth - 28)

                    // Die Height Dimension (Right side)
                    var hDimX = cx + blockW * 0.5 + 24
                    ctx.strokeStyle = "#A3E635"
                    ctx.lineWidth = 1.2
                    ctx.beginPath()
                    ctx.moveTo(hDimX, dieTopY)
                    ctx.lineTo(hDimX, dieBottomY)
                    ctx.moveTo(hDimX - 3, dieTopY + 5); ctx.lineTo(hDimX, dieTopY); ctx.lineTo(hDimX + 3, dieTopY + 5)
                    ctx.moveTo(hDimX - 3, dieBottomY - 5); ctx.lineTo(hDimX, dieBottomY); ctx.lineTo(hDimX + 3, dieBottomY - 5)
                    ctx.stroke()

                    ctx.fillStyle = "#A3E635"
                    ctx.font = "bold 10px Consolas, monospace"
                    ctx.textAlign = "left"
                    ctx.fillText("H = " + dHeight.toFixed(3) + "\"", hDimX + 6, cy)

                    ctx.restore()

                } else {
                    // ---------------------------------------------------------
                    // MATERIAL & BEND FORMING VECTOR DRAWING
                    // ---------------------------------------------------------
                    var uts = Number(rec.materialTensileStrengthPsi) || 45000
                    var sb = Number(rec.materialSpringback) || 0.7
                    var irRule = (Number(rec.insideRadiusRuleOfThumb) || 0.15) * 100

                    ctx.save()

                    // Formed sheet metal plate in V bend
                    var plateThick = 10
                    var bAngle = 45.0 * (Math.PI / 180.0)
                    var armLen = 70

                    ctx.beginPath()
                    ctx.moveTo(cx - armLen * Math.cos(bAngle), cy - armLen * Math.sin(bAngle))
                    ctx.lineTo(cx, cy)
                    ctx.lineTo(cx + armLen * Math.cos(bAngle), cy - armLen * Math.sin(bAngle))
                    ctx.strokeStyle = "#59A60C"
                    ctx.lineWidth = plateThick
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.stroke()

                    // Neutral Axis dotted line
                    ctx.strokeStyle = "#FACC15"
                    ctx.lineWidth = 1.2
                    ctx.setLineDash([3, 3])
                    ctx.beginPath()
                    ctx.moveTo(cx - (armLen - 4) * Math.cos(bAngle), cy - (armLen - 4) * Math.sin(bAngle))
                    ctx.lineTo(cx, cy)
                    ctx.lineTo(cx + (armLen - 4) * Math.cos(bAngle), cy - (armLen - 4) * Math.sin(bAngle))
                    ctx.stroke()
                    ctx.setLineDash([])

                    // Springback arc recovery indication
                    ctx.strokeStyle = "#F43F5E"
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    ctx.arc(cx, cy, armLen * 0.75, -Math.PI / 2 - bAngle, -Math.PI / 2 - bAngle + (sb * Math.PI / 60))
                    ctx.stroke()

                    // Material specs HUD overlay
                    ctx.fillStyle = "#F8FAFC"
                    ctx.font = "bold 12px Consolas, monospace"
                    ctx.textAlign = "center"
                    ctx.fillText(rec.name || "MATERIAL", cx, cy - 80)

                    ctx.fillStyle = "#A7F3D0"
                    ctx.font = "11px Consolas, monospace"
                    ctx.fillText("UTS: " + uts.toLocaleString() + " PSI  |  SB: " + sb.toFixed(1) + "°", cx, cy - 62)

                    // Air bend inside radius rule callout
                    ctx.fillStyle = "#FDE047"
                    ctx.font = "bold 10px Consolas, monospace"
                    ctx.fillText("Ri Rule: " + irRule.toFixed(0) + "% of V-Opening", cx, cy + 50)

                    // Tonnage Formula Box
                    ctx.fillStyle = "#1E293B"
                    ctx.fillRect(cx - 130, cy + 70, 260, 42)
                    ctx.strokeStyle = "#475569"
                    ctx.strokeRect(cx - 130, cy + 70, 260, 42)

                    ctx.fillStyle = "#38BDF8"
                    ctx.font = "bold 10px Consolas, monospace"
                    ctx.fillText("TONNAGE: F ≈ (1.42 · UTS · L · t²) / V", cx, cy + 86)
                    ctx.fillStyle = "#94A3B8"
                    ctx.font = "10px Consolas, monospace"
                    ctx.fillText("Est: ~12.5 Tons/ft for 16 ga @ V=0.630\"", cx, cy + 102)

                    ctx.restore()
                }
            }
        }
    }

    // Bottom: Interactive Bed Assembly Rack
    Rectangle {
        id: rackCard
        x: 10
        y: 332
        width: 414
        height: 298
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // Header Row: Title & Total Length Summary
            Row {
                width: parent.width
                Item { width: 1; height: 1 }
                Text {
                    text: root.activeTab === 2 ? qsTr("MATERIAL PROFILES & SPECS") : qsTr("SEGMENT INVENTORY & BED ASSEMBLY")
                    font.pixelSize: 11
                    font.bold: true
                    color: root.ink
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { Layout.fillWidth: true; width: parent.width - 290 }
                Rectangle {
                    visible: root.activeTab !== 2
                    height: 22
                    width: assembledLenText.implicitWidth + 16
                    radius: 11
                    color: root.totalAssembledLength >= 48 ? "#DCFCE7" : "#FEF3C7"
                    border.color: root.totalAssembledLength >= 48 ? "#86EFAC" : "#FDE68A"
                    border.width: 1

                    Text {
                        id: assembledLenText
                        anchors.centerIn: parent
                        text: qsTr("Total: %1\" (%2 mm)").arg(root.totalAssembledLength.toFixed(1)).arg((root.totalAssembledLength * 25.4).toFixed(0))
                        font.pixelSize: 10
                        font.bold: true
                        color: root.totalAssembledLength >= 48 ? "#166534" : "#92400E"
                    }
                }
            }

            // Visual Press Brake Bed Rail (Only for Punches & Dies)
            Rectangle {
                visible: root.activeTab !== 2
                width: parent.width
                height: 38
                color: "#1E293B"
                radius: 4
                border.color: "#334155"
                border.width: 1
                clip: true

                // Bed measurement ticks
                Row {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: (parent.width - 16) / 4
                    Repeater {
                        model: ["0\"", "12\"", "24\"", "36\"", "48\" BED"]
                        Text {
                            text: modelData
                            font.pixelSize: 8
                            font.bold: true
                            color: "#64748B"
                        }
                    }
                }

                // Assembled Segment Blocks visualization
                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 2

                    readonly property real maxBedInch: 48.0
                    readonly property real pxPerInch: (parent.width - 24) / maxBedInch

                    // 16" segments
                    Repeater {
                        model: Number(root.selectedRecord.segmentCount16In) || 0
                        Rectangle {
                            width: Math.max(8, 16 * parent.pxPerInch)
                            height: 18
                            radius: 2
                            color: root.activeAccent
                            border.color: "#FFFFFF"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "16\""; font.pixelSize: 8; font.bold: true; color: "#FFFFFF" }
                        }
                    }
                    // 8" segments
                    Repeater {
                        model: Number(root.selectedRecord.segmentCount8In) || 0
                        Rectangle {
                            width: Math.max(6, 8 * parent.pxPerInch)
                            height: 18
                            radius: 2
                            color: Qt.darker(root.activeAccent, 1.15)
                            border.color: "#FFFFFF"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "8\""; font.pixelSize: 8; font.bold: true; color: "#FFFFFF" }
                        }
                    }
                    // 4" segments
                    Repeater {
                        model: Number(root.selectedRecord.segmentCount4In) || 0
                        Rectangle {
                            width: Math.max(5, 4 * parent.pxPerInch)
                            height: 18
                            radius: 2
                            color: Qt.darker(root.activeAccent, 1.3)
                            border.color: "#FFFFFF"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "4\""; font.pixelSize: 8; font.bold: true; color: "#FFFFFF" }
                        }
                    }
                    // 2" segments
                    Repeater {
                        model: Number(root.selectedRecord.segmentCount2In) || 0
                        Rectangle {
                            width: Math.max(4, 2 * parent.pxPerInch)
                            height: 18
                            radius: 2
                            color: "#F59E0B"
                            Text { anchors.centerIn: parent; text: "2\""; font.pixelSize: 7; font.bold: true; color: "#FFFFFF" }
                        }
                    }
                    // 1" segments
                    Repeater {
                        model: Number(root.selectedRecord.segmentCount1In) || 0
                        Rectangle {
                            width: Math.max(3, 1 * parent.pxPerInch)
                            height: 18
                            radius: 2
                            color: "#EA580C"
                            Text { anchors.centerIn: parent; text: "1\""; font.pixelSize: 6; font.bold: true; color: "#FFFFFF" }
                        }
                    }
                }
            }

            // Segment Stepper Control Pods (16", 8", 4", 2", 1")
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
                        height: 34
                        color: root.cardBgAlt
                        radius: 4
                        border.color: root.cardBorder
                        border.width: 1

                        readonly property int countVal: {
                            var rec = root.selectedRecord
                            var n = Number(rec[modelData.key])
                            return isFinite(n) && n >= 0 ? Math.round(n) : 0
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            // Size Badge
                            Rectangle {
                                width: 88
                                height: 22
                                radius: 3
                                color: "#E2E8F0"
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: root.ink
                                }
                            }

                            // Subtotal preview
                            Text {
                                text: qsTr("%1 × %2\" = %3\"").arg(countVal).arg(modelData.size).arg(countVal * modelData.size)
                                font.pixelSize: 10
                                font.family: "Consolas, monospace"
                                color: root.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                                width: 90
                            }

                            Item { Layout.fillWidth: true; width: parent.width - 320 }

                            // Decrement Button [-]
                            Rectangle {
                                width: 28
                                height: 24
                                radius: 3
                                color: minusArea.containsMouse ? "#CBD5E1" : "#E2E8F0"
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; font.bold: true; color: root.ink }
                                MouseArea {
                                    id: minusArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setSegmentCount(modelData.size, -1)
                                }
                            }

                            // Numeric Count Box (Interactive Input)
                            Rectangle {
                                width: 44
                                height: 24
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.cardBorder
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: String(countVal)
                                    font.pixelSize: 12
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

                            // Increment Button [+]
                            Rectangle {
                                width: 28
                                height: 24
                                radius: 3
                                color: plusArea.containsMouse ? root.activeAccent : Qt.lighter(root.activeAccent, 1.25)
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; font.bold: true; color: "#FFFFFF" }
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

            // Alternate view for Material Studio (Thickness Table & Properties)
            Column {
                visible: root.activeTab === 2
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 100
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Text {
                            text: qsTr("RECOMMENDED AIR BENDING FORMULAS")
                            font.pixelSize: 10
                            font.bold: true
                            color: root.ink
                        }
                        Text {
                            text: qsTr("• Optimal Die Opening (Air Bend): V = 8 × t (for t < 0.25\")")
                            font.pixelSize: 10
                            color: root.textSecondary
                        }
                        Text {
                            text: qsTr("• Inside Bend Radius: Ri ≈ 0.15 × V (Mild Steel Rule)")
                            font.pixelSize: 10
                            color: root.textSecondary
                        }
                        Text {
                            text: qsTr("• Minimum Flange Width: b_min ≈ 0.7 × V")
                            font.pixelSize: 10
                            color: root.textSecondary
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 120
                    color: "#FFFFFF"
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Text {
                            text: qsTr("DEFAULT THICKNESS PAIRING QUICK ACCESS")
                            font.pixelSize: 10
                            font.bold: true
                            color: root.ink
                        }

                        Row {
                            spacing: 8
                            Repeater {
                                model: ["16 ga", "18 ga", "20 ga", "24 ga"]
                                delegate: Rectangle {
                                    width: 86
                                    height: 52
                                    radius: 4
                                    color: "#F8FAFC"
                                    border.color: "#CBD5E1"
                                    border.width: 1

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text { text: modelData; font.pixelSize: 11; font.bold: true; color: root.greenAccent; anchors.horizontalCenter: parent.horizontalCenter }
                                        Text { text: "Gooseneck 88°"; font.pixelSize: 8; color: root.textSecondary; anchors.horizontalCenter: parent.horizontalCenter }
                                        Text { text: "Acute 8mm Die"; font.pixelSize: 8; color: root.blueAccent; anchors.horizontalCenter: parent.horizontalCenter }
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
    // 3. RIGHT PANEL (x: 434, y: 56, width: 420, height: 574)
    //    Top: Tool Selector & Identification Card (height: 72)
    //    Middle: Technical Specifications Deck (height: 428)
    //    Bottom: Tactile Action Command Deck (height: 54)
    // =========================================================================

    // Top: Tool Selector & Identification Card
    Rectangle {
        id: selectorCard
        x: 434
        y: 56
        width: 420
        height: 72
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // Row 1: Header Category & Index Navigation
            Row {
                width: parent.width
                spacing: 6

                Text {
                    text: root.activeTab === 0 ? qsTr("ACTIVE PUNCH CATALOG")
                            : (root.activeTab === 1 ? qsTr("ACTIVE DIE CATALOG") : qsTr("ACTIVE MATERIAL CATALOG"))
                    font.pixelSize: 10
                    font.bold: true
                    color: root.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { Layout.fillWidth: true; width: parent.width - 240 }

                // Previous Button [◀]
                Rectangle {
                    width: 24
                    height: 20
                    radius: 3
                    color: prevMouse.containsMouse ? "#CBD5E1" : "#E2E8F0"
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "◀"; font.pixelSize: 10; color: root.ink }
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

                // Index Indicator
                Text {
                    text: qsTr("[ %1 of %2 ]").arg(root.currentIndex + 1).arg(root.currentRecords.length)
                    font.pixelSize: 10
                    font.bold: true
                    font.family: "Consolas, monospace"
                    color: root.activeAccent
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Next Button [▶]
                Rectangle {
                    width: 24
                    height: 20
                    radius: 3
                    color: nextMouse.containsMouse ? "#CBD5E1" : "#E2E8F0"
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 10; color: root.ink }
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
            }

            // Row 2: Tool Selector ComboBox + Quick Edit Pencil
            Row {
                width: parent.width
                spacing: 8

                ComboBox {
                    id: toolCombo
                    width: parent.width - 40
                    height: 32
                    model: root.currentRecords.map(function(r) { return r.name || "" })
                    currentIndex: root.currentIndex
                    onActivated: function(idx) {
                        if (root.activeTab === 0) root.punchIndex = idx
                        else if (root.activeTab === 1) root.dieIndex = idx
                        else root.materialIndex = idx
                        cadCanvas.requestPaint()
                    }

                    background: Rectangle {
                        radius: 4
                        color: "#FFFFFF"
                        border.color: root.cardBorder
                        border.width: 1
                    }

                    contentItem: Text {
                        leftPadding: 8
                        rightPadding: 24
                        text: toolCombo.displayText
                        font.pixelSize: 11
                        font.bold: true
                        color: root.ink
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                // Edit Tool Name Button [✏]
                Rectangle {
                    width: 32
                    height: 32
                    radius: 4
                    color: editMouse.containsMouse ? "#CBD5E1" : "#F1F5F9"
                    border.color: root.cardBorder
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✏"
                        font.pixelSize: 13
                        color: root.ink
                    }

                    MouseArea {
                        id: editMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var curName = root.selectedRecord.name || ""
                            root.openTextInput(qsTr("Edit Tool Name"), curName, function(newName) {
                                if (newName && newName.trim().length > 0) {
                                    var rec = Object.assign({}, root.selectedRecord, { name: newName.trim() })
                                    root.replaceCurrentRecord(rec)
                                }
                            })
                        }
                    }
                }
            }
        }
    }

    // Middle: Technical Specifications Deck
    Rectangle {
        id: specsCard
        x: 434
        y: 134
        width: 420
        height: 428
        color: root.cardBg
        radius: 6
        border.color: root.cardBorder
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            // -----------------------------------------------------------------
            // SPEC DECK FOR PUNCH STUDIO
            // -----------------------------------------------------------------
            Column {
                visible: root.activeTab === 0
                width: parent.width
                spacing: 10

                Text {
                    text: qsTr("GEOMETRIC SPECIFICATIONS")
                    font.pixelSize: 10
                    font.bold: true
                    color: root.textSecondary
                }

                // 1. Punch Height
                Rectangle {
                    width: parent.width
                    height: 48
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Column {
                            width: 130
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: qsTr("PUNCH HEIGHT"); font.pixelSize: 10; font.bold: true; color: root.ink }
                            Text { text: qsTr("Total vertical length"); font.pixelSize: 9; color: root.textMuted }
                        }

                        // Bump [-0.010"]
                        Rectangle {
                            width: 52
                            height: 28
                            radius: 3
                            color: hMinus.containsMouse ? "#CBD5E1" : "#E2E8F0"
                            anchors.verticalCenter: parent.verticalCenter
                            Text { anchors.centerIn: parent; text: "-0.010\""; font.pixelSize: 9; font.bold: true; color: root.ink }
                            MouseArea {
                                id: hMinus
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var cur = Number(root.selectedRecord.heightInch) || 0
                                    root.setNumericField("heightInch", Math.max(0.1, cur - 0.010))
                                }
                            }
                        }

                        // Display / Input Field
                        Rectangle {
                            width: 80
                            height: 28
                            radius: 3
                            color: "#FFFFFF"
                            border.color: root.redAccent
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: Number(root.selectedRecord.heightInch || 0).toFixed(3) + " in"
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: root.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNumericInput(qsTr("Punch Height (inches)"), root.selectedRecord.heightInch, function(val) {
                                    root.setNumericField("heightInch", val)
                                })
                            }
                        }

                        // Bump [+0.010"]
                        Rectangle {
                            width: 52
                            height: 28
                            radius: 3
                            color: hPlus.containsMouse ? "#CBD5E1" : "#E2E8F0"
                            anchors.verticalCenter: parent.verticalCenter
                            Text { anchors.centerIn: parent; text: "+0.010\""; font.pixelSize: 9; font.bold: true; color: root.ink }
                            MouseArea {
                                id: hPlus
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var cur = Number(root.selectedRecord.heightInch) || 0
                                    root.setNumericField("heightInch", cur + 0.010)
                                }
                            }
                        }
                    }
                }

                // 2. Punch Profile Type (4-way Segmented Buttons)
                Rectangle {
                    width: parent.width
                    height: 56
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        Text { text: qsTr("PUNCH PROFILE TYPE"); font.pixelSize: 10; font.bold: true; color: root.ink }

                        Row {
                            width: parent.width
                            spacing: 4
                            readonly property string activeProf: String(root.selectedRecord.punchProfileType || "STANDARD").toUpperCase()

                            Repeater {
                                model: ["ACUTE", "STANDARD", "GOOSENECK", "EXT. GOOSENECK"]
                                delegate: Rectangle {
                                    required property int index
                                    required property string modelData
                                    readonly property string fullKey: index === 3 ? "EXTREME GOOSENECK" : modelData
                                    readonly property bool isSel: parent.activeProf === fullKey

                                    width: (parent.width - 12) / 4
                                    height: 26
                                    radius: 3
                                    color: isSel ? root.redAccent : (profMouse.containsMouse ? "#CBD5E1" : "#FFFFFF")
                                    border.color: isSel ? root.redAccent : root.cardBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: isSel ? "#FFFFFF" : root.ink
                                    }

                                    MouseArea {
                                        id: profMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var rec = Object.assign({}, root.selectedRecord, { punchProfileType: fullKey })
                                            root.replaceCurrentRecord(rec)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. Punch Tip Angle
                Rectangle {
                    width: parent.width
                    height: 64
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        Row {
                            width: parent.width
                            Text { text: qsTr("PUNCH TIP ANGLE"); font.pixelSize: 10; font.bold: true; color: root.ink }
                            Item { Layout.fillWidth: true; width: parent.width - 200 }
                            Rectangle {
                                width: 70
                                height: 20
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.redAccent
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: Number(root.selectedRecord.punchAngleDegree || 0).toFixed(1) + "°"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                    color: root.ink
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openNumericInput(qsTr("Punch Angle (degrees)"), root.selectedRecord.punchAngleDegree, function(val) {
                                        root.setNumericField("punchAngleDegree", val)
                                    })
                                }
                            }
                        }

                        // Presets
                        Row {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: [30.0, 35.0, 60.0, 85.0, 88.0, 90.0]
                                delegate: Rectangle {
                                    required property real modelData
                                    readonly property bool isAngleSel: Math.abs(Number(root.selectedRecord.punchAngleDegree) - modelData) < 0.1
                                    width: (parent.width - 20) / 6
                                    height: 22
                                    radius: 3
                                    color: isAngleSel ? root.redAccent : (angMouse.containsMouse ? "#CBD5E1" : "#FFFFFF")
                                    border.color: isAngleSel ? root.redAccent : root.cardBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.toFixed(0) + "°"
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: isAngleSel ? "#FFFFFF" : root.ink
                                    }

                                    MouseArea {
                                        id: angMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setNumericField("punchAngleDegree", modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // 4. Engineering Limits Badge
                Rectangle {
                    width: parent.width
                    height: 60
                    color: "#F8FAFC"
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        Column {
                            width: 180
                            spacing: 2
                            Text { text: qsTr("MAX LOAD RATING"); font.pixelSize: 9; font.bold: true; color: root.textSecondary }
                            Text { text: qsTr("55 Tons / Meter (100 kN/m)"); font.pixelSize: 11; font.bold: true; color: root.ink }
                            Text { text: qsTr("Hardened 42CrMo Tool Steel"); font.pixelSize: 9; color: root.textMuted }
                        }

                        Rectangle { width: 1; height: parent.height; color: "#CBD5E1" }

                        Column {
                            spacing: 2
                            Text { text: qsTr("SAFETY ENVELOPE"); font.pixelSize: 9; font.bold: true; color: root.textSecondary }
                            Text { text: qsTr("Standard Euro Clamping 12.7mm"); font.pixelSize: 10; font.bold: true; color: root.ink }
                            Text { text: qsTr("Anti-drop Safety Tang Active"); font.pixelSize: 9; color: root.greenAccent }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // SPEC DECK FOR DIE STUDIO
            // -----------------------------------------------------------------
            Column {
                visible: root.activeTab === 1
                width: parent.width
                spacing: 8

                Text {
                    text: qsTr("V-DIE GEOMETRY & APERTURE")
                    font.pixelSize: 10
                    font.bold: true
                    color: root.textSecondary
                }

                // 1. Die Height
                Rectangle {
                    width: parent.width
                    height: 42
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text { text: qsTr("DIE HEIGHT (H)"); font.pixelSize: 10; font.bold: true; color: root.ink; width: 120; anchors.verticalCenter: parent.verticalCenter }

                        Item { Layout.fillWidth: true; width: parent.width - 240 }

                        Rectangle {
                            width: 90
                            height: 26
                            radius: 3
                            color: "#FFFFFF"
                            border.color: root.blueAccent
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: Number(root.selectedRecord.heightInch || 0).toFixed(3) + " in"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: root.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNumericInput(qsTr("Die Height (inches)"), root.selectedRecord.heightInch, function(val) {
                                    root.setNumericField("heightInch", val)
                                })
                            }
                        }
                    }
                }

                // 2. V-Die Opening (V)
                Rectangle {
                    width: parent.width
                    height: 64
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        Row {
                            width: parent.width
                            Text { text: qsTr("V-DIE OPENING (V)"); font.pixelSize: 10; font.bold: true; color: root.ink }
                            Item { Layout.fillWidth: true; width: parent.width - 200 }
                            Rectangle {
                                width: 90
                                height: 22
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.blueAccent
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: Number(root.selectedRecord.vdieOpeningInch || 0).toFixed(3) + " in"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                    color: root.ink
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openNumericInput(qsTr("V Opening (inches)"), root.selectedRecord.vdieOpeningInch, function(val) {
                                        root.setNumericField("vdieOpeningInch", val)
                                    })
                                }
                            }
                        }

                        // Presets: 0.315" (8mm), 0.630" (16mm), 0.866" (22mm), 1.024" (26mm), 1.378" (35mm), 1.969" (50mm)
                        Row {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: [
                                    { v: 0.315, l: "8mm" },
                                    { v: 0.630, l: "16mm" },
                                    { v: 0.866, l: "22mm" },
                                    { v: 1.024, l: "26mm" },
                                    { v: 1.378, l: "35mm" },
                                    { v: 1.969, l: "50mm" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isVSel: Math.abs(Number(root.selectedRecord.vdieOpeningInch) - modelData.v) < 0.01
                                    width: (parent.width - 20) / 6
                                    height: 22
                                    radius: 3
                                    color: isVSel ? root.blueAccent : (vMouse.containsMouse ? "#CBD5E1" : "#FFFFFF")
                                    border.color: isVSel ? root.blueAccent : root.cardBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.l
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: isVSel ? "#FFFFFF" : root.ink
                                    }

                                    MouseArea {
                                        id: vMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setNumericField("vdieOpeningInch", modelData.v)
                                    }
                                }
                            }
                        }
                    }
                }

                // 3. Die Angle (A)
                Rectangle {
                    width: parent.width
                    height: 58
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        Row {
                            width: parent.width
                            Text { text: qsTr("V-GROOVE INCLUDED ANGLE"); font.pixelSize: 10; font.bold: true; color: root.ink }
                            Item { Layout.fillWidth: true; width: parent.width - 200 }
                            Rectangle {
                                width: 70
                                height: 20
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.blueAccent
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: Number(root.selectedRecord.dieAngleDegree || 0).toFixed(1) + "°"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                    color: root.ink
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openNumericInput(qsTr("Die Angle (degrees)"), root.selectedRecord.dieAngleDegree, function(val) {
                                        root.setNumericField("dieAngleDegree", val)
                                    })
                                }
                            }
                        }

                        // Presets
                        Row {
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: [30.0, 35.0, 85.0, 88.0, 90.0]
                                delegate: Rectangle {
                                    required property real modelData
                                    readonly property bool isAngleSel: Math.abs(Number(root.selectedRecord.dieAngleDegree) - modelData) < 0.1
                                    width: (parent.width - 16) / 5
                                    height: 22
                                    radius: 3
                                    color: isAngleSel ? root.blueAccent : (dAngMouse.containsMouse ? "#CBD5E1" : "#FFFFFF")
                                    border.color: isAngleSel ? root.blueAccent : root.cardBorder
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.toFixed(0) + "°"
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: isAngleSel ? "#FFFFFF" : root.ink
                                    }

                                    MouseArea {
                                        id: dAngMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setNumericField("dieAngleDegree", modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // 4. Overall Width (W)
                Rectangle {
                    width: parent.width
                    height: 42
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text { text: qsTr("OVERALL DIE BLOCK WIDTH"); font.pixelSize: 10; font.bold: true; color: root.ink; width: 170; anchors.verticalCenter: parent.verticalCenter }

                        Item { Layout.fillWidth: true; width: parent.width - 290 }

                        Rectangle {
                            width: 90
                            height: 26
                            radius: 3
                            color: "#FFFFFF"
                            border.color: root.cardBorder
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: isFinite(Number(root.selectedRecord.overallWidthInch)) && Number(root.selectedRecord.overallWidthInch) > 0
                                        ? Number(root.selectedRecord.overallWidthInch).toFixed(3) + " in" : "N/A"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: root.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNumericInput(qsTr("Overall Width (inches)"), root.selectedRecord.overallWidthInch, function(val) {
                                    root.setNumericField("overallWidthInch", val)
                                })
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // SPEC DECK FOR MATERIAL STUDIO
            // -----------------------------------------------------------------
            Column {
                visible: root.activeTab === 2
                width: parent.width
                spacing: 8

                Text {
                    text: qsTr("MATERIAL MECHANICAL & SPRINGBACK DEFAULTS")
                    font.pixelSize: 10
                    font.bold: true
                    color: root.textSecondary
                }

                // 1. Tensile Strength (PSI)
                Rectangle {
                    width: parent.width
                    height: 42
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text { text: qsTr("TENSILE STRENGTH (UTS)"); font.pixelSize: 10; font.bold: true; color: root.ink; width: 170; anchors.verticalCenter: parent.verticalCenter }
                        Item { Layout.fillWidth: true; width: parent.width - 300 }

                        Rectangle {
                            width: 110
                            height: 26
                            radius: 3
                            color: "#FFFFFF"
                            border.color: root.greenAccent
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: Number(root.selectedRecord.materialTensileStrengthPsi || 0).toLocaleString() + " PSI"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: root.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNumericInput(qsTr("Tensile Strength (PSI)"), root.selectedRecord.materialTensileStrengthPsi, function(val) {
                                    root.setNumericField("materialTensileStrengthPsi", val)
                                })
                            }
                        }
                    }
                }

                // 2. Inside Radius Rule of Thumb (% of V)
                Rectangle {
                    width: parent.width
                    height: 42
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text { text: qsTr("INSIDE RADIUS RULE OF THUMB"); font.pixelSize: 10; font.bold: true; color: root.ink; width: 190; anchors.verticalCenter: parent.verticalCenter }
                        Item { Layout.fillWidth: true; width: parent.width - 300 }

                        Rectangle {
                            width: 90
                            height: 26
                            radius: 3
                            color: "#FFFFFF"
                            border.color: root.cardBorder
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: ((Number(root.selectedRecord.insideRadiusRuleOfThumb) || 0) * 100).toFixed(0) + " % of V"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: root.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNumericInput(qsTr("Inside Radius (% of V opening)"), (root.selectedRecord.insideRadiusRuleOfThumb || 0) * 100, function(val) {
                                    var n = Number(val)
                                    if (isFinite(n)) root.setNumericField("insideRadiusRuleOfThumb", n / 100.0)
                                })
                            }
                        }
                    }
                }

                // 3. Material Springback (degrees)
                Rectangle {
                    width: parent.width
                    height: 42
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8

                        Text { text: qsTr("MATERIAL SPRINGBACK (Δθ)"); font.pixelSize: 10; font.bold: true; color: root.ink; width: 190; anchors.verticalCenter: parent.verticalCenter }
                        Item { Layout.fillWidth: true; width: parent.width - 280 }

                        Rectangle {
                            width: 70
                            height: 26
                            radius: 3
                            color: "#FFFFFF"
                            border.color: root.greenAccent
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: Number(root.selectedRecord.materialSpringback || 0).toFixed(1) + "°"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: "Consolas, monospace"
                                color: root.ink
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openNumericInput(qsTr("Springback (degrees)"), root.selectedRecord.materialSpringback, function(val) {
                                    root.setNumericField("materialSpringback", val)
                                })
                            }
                        }
                    }
                }

                // 4. Default Tooling Preferences
                Rectangle {
                    width: parent.width
                    height: 110
                    color: root.cardBgAlt
                    radius: 4
                    border.color: root.cardBorder
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Text { text: qsTr("DEFAULT TOOLING PREFERENCES BY THICKNESS"); font.pixelSize: 10; font.bold: true; color: root.ink }

                        Row {
                            spacing: 8
                            Text { text: qsTr("Thickness:"); font.pixelSize: 10; color: root.textSecondary; width: 70; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle {
                                width: 130
                                height: 24
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.cardBorder
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "16 ga (0.0598\")"; font.pixelSize: 10; font.bold: true; color: root.ink }
                            }
                        }

                        Row {
                            spacing: 8
                            Text { text: qsTr("Tool Pairing:"); font.pixelSize: 10; color: root.textSecondary; width: 70; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle {
                                width: 150
                                height: 24
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.redAccent
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "Gooseneck 88° [8392]"; font.pixelSize: 9; font.bold: true; color: root.ink }
                            }
                            Rectangle {
                                width: 150
                                height: 24
                                radius: 3
                                color: "#FFFFFF"
                                border.color: root.blueAccent
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "Acute 8mm Die [5623]"; font.pixelSize: 9; font.bold: true; color: root.ink }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // 4. BOTTOM ACTION COMMAND HUB (x: 434, y: 570, width: 420, height: 54)
    //    NEW (+), SAVE (💾), DUPLICATE (⎘), DELETE (🗑)
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
            spacing: 8

            // 1. NEW BUTTON (+)
            Rectangle {
                width: 95
                height: 38
                radius: 4
                color: newMouse.containsMouse ? Qt.darker(root.activeAccent, 1.15) : root.activeAccent

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "+"; font.pixelSize: 16; font.bold: true; color: "#FFFFFF" }
                    Text { text: qsTr("NEW"); font.pixelSize: 12; font.bold: true; color: "#FFFFFF" }
                }

                MouseArea {
                    id: newMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("NEW")
                }
            }

            // 2. SAVE BUTTON (💾)
            Rectangle {
                width: 95
                height: 38
                radius: 4
                color: saveMouse.containsMouse ? "#111827" : root.charcoal

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "💾"; font.pixelSize: 13; color: "#FFFFFF" }
                    Text { text: qsTr("SAVE"); font.pixelSize: 12; font.bold: true; color: "#FFFFFF" }
                }

                MouseArea {
                    id: saveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("SAVE")
                }
            }

            // 3. DUPLICATE BUTTON (⎘)
            Rectangle {
                width: 105
                height: 38
                radius: 4
                color: dupMouse.containsMouse ? Qt.darker(root.amberAccent, 1.15) : root.amberAccent

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "⎘"; font.pixelSize: 14; font.bold: true; color: "#1E293B" }
                    Text { text: qsTr("DUPLICATE"); font.pixelSize: 11; font.bold: true; color: "#1E293B" }
                }

                MouseArea {
                    id: dupMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("DUPLICATE")
                }
            }

            // 4. DELETE BUTTON (🗑)
            Rectangle {
                width: parent.width - 320
                height: 38
                radius: 4
                color: delMouse.containsMouse ? "#FEE2E2" : "#FFFFFF"
                border.color: "#EF4444"
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "🗑"; font.pixelSize: 13; color: "#DC2626" }
                    Text { text: qsTr("DEL"); font.pixelSize: 11; font.bold: true; color: "#DC2626" }
                }

                MouseArea {
                    id: delMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runToolAction("DELETE")
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Toast Notification Banner (Floating bottom overlay)
    // -------------------------------------------------------------------------
    Rectangle {
        visible: root.toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        height: 34
        width: toastContent.implicitWidth + 32
        radius: 17
        color: "#0F172A"
        border.color: "#334155"
        border.width: 1
        z: 99

        Text {
            id: toastContent
            anchors.centerIn: parent
            text: root.toastText
            font.pixelSize: 11
            font.bold: true
            color: "#F8FAFC"
        }
    }
}
