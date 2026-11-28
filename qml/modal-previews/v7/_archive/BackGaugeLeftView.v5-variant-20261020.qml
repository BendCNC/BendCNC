pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes

// =============================================================================
// BENDCNC V5 PRECISION - BACK GAUGE LEFT PANEL (864 × 638)
//
// A high-precision, aerospace-grade industrial console that elevates the
// legacy Back Gauge menu into a complete 2-axis CNC gauge control center.
//
// Features:
// 1. Live 2D Physical Back Gauge & Tooling Visualizer Stage with animated
//    finger profile, bed reference line, contact steps, and travel envelopes.
// 2. High-Contrast Dual Precision DRO (X & R axes) with simultaneous WCS/MCS
//    displays, single-tap Zeroing/Presetting, and motion vector indicators.
// 3. Ergonomic Industrial Vector Jog Compass with tactile directional pads,
//    central status core, and micro-nudge feathering buttons (±0.001", ±0.010").
// 4. Consolidated Motion Control Deck for Step increments & Feedrate speeds.
// 5. Smart Absolute Positioning ("Move to Target") with fast presets.
// 6. Diagnostics, 4-axis Limit Matrix (X1, X2, R1, R2), and Safety Stop.
// =============================================================================

Item {
    id: root
    objectName: "backgauge-left-panel-v5"

    property var appState: null
    property bool designerInteractive: true

    focus: true

    // -------------------------------------------------------------------------
    // Offline Simulation & Interactive Preview State
    // -------------------------------------------------------------------------
    property real simX: appState && isFinite(Number(appState.backGaugeX)) ? Number(appState.backGaugeX) : 4.2500
    property real simR: appState && isFinite(Number(appState.backGaugeR)) ? Number(appState.backGaugeR) : 1.1250
    property real simMachineX: appState && isFinite(Number(appState.backGaugeMachineX)) ? Number(appState.backGaugeMachineX) : (simX + 1.7500)
    property real simMachineR: appState && isFinite(Number(appState.backGaugeMachineR)) ? Number(appState.backGaugeMachineR) : (simR + 0.8500)
    property bool showMachineCoords: false
    property string activeDirection: appState ? appState.backGaugeActiveDirection : ""
    property bool isHomed: appState ? appState.backGaugeHomed : true
    property bool isReady: appState ? appState.backGaugeReady : true
    property string selectedProfile: appState ? appState.backGaugeCoordinateSystem : "G54"
    property var profileNames: ({
        "G54": qsTr("FINGER TIP · G54"),
        "G55": qsTr("LOWER STEP · G55"),
        "G56": qsTr("UPPER STEP · G56"),
        "G57": qsTr("DIE FLUSH · G57"),
        "G58": qsTr("REAR STOP · G58"),
        "G59": qsTr("CUSTOM · G59")
    })

    // Motion parameters
    property real jogStepVal: appState && isFinite(Number(appState.jogStep)) ? Number(appState.jogStep) : 0.0100
    property bool jogContinuous: appState ? appState.backGaugeContinuousJog : false
    property real jogSpeedVal: appState && isFinite(Number(appState.jogSpeed)) ? Number(appState.jogSpeed) : 50.0
    property string unitStr: appState && appState.backGaugeUnit === "MILLIMETER" ? "mm" : "in"
    property string speedUnitStr: appState && appState.backGaugeUnit === "MILLIMETER" ? "MMM" : "IPM"

    // Target positions
    property real targetX: simX
    property real targetR: simR

    // Design Tokens (V5 Gemini Precision Palette)
    readonly property color bgDark: "#0B0F17"
    readonly property color cardBg: "#131A26"
    readonly property color cardBorder: "#222D3E"
    readonly property color cardBorderHighlight: "#334155"
    readonly property color textPrimary: "#F8FAFC"
    readonly property color textSecondary: "#94A3B8"
    readonly property color textMuted: "#64748B"
    readonly property color cyanAccent: "#38BDF8"
    readonly property color cyanGlow: "#0284C7"
    readonly property color purpleAccent: "#C084FC"
    readonly property color purpleGlow: "#9333EA"
    readonly property color emeraldAccent: "#10B981"
    readonly property color amberAccent: "#F59E0B"
    readonly property color redAccent: "#EF4444"
    readonly property color redDark: "#991B1B"
    readonly property color jogPadBg: "#1E293B"
    readonly property color jogPadHover: "#283548"
    readonly property color jogPadActive: "#0284C7"

    // -------------------------------------------------------------------------
    // Keyboard & Jog Handlers
    // -------------------------------------------------------------------------
    function triggerJog(axis, dir, pressed) {
        if (pressed) {
            root.activeDirection = axis + (dir > 0 ? "+" : "-")
            if (appState) {
                appState.beginBackGaugeJog(axis, dir)
            } else if (designerInteractive) {
                var step = jogContinuous ? 0.05 : jogStepVal
                if (axis === "X") simX = Math.max(0, Math.min(24.0, simX + dir * step))
                if (axis === "R") simR = Math.max(-0.5, Math.min(6.0, simR + dir * step))
            }
        } else {
            root.activeDirection = ""
            if (appState) {
                appState.releaseBackGaugeJog(axis, dir)
            }
        }
    }

    function nudgeAxis(axis, delta) {
        if (axis === "X") {
            simX = Math.max(0, Math.min(24.0, simX + delta))
            if (appState) appState.setBackGaugeWorkPosition("X", simX)
        } else if (axis === "R") {
            simR = Math.max(-0.5, Math.min(6.0, simR + delta))
            if (appState) appState.setBackGaugeWorkPosition("R", simR)
        }
    }

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat) return
        if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_H) {
            triggerHome()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Left) { triggerJog("X", -1, true); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { triggerJog("X", 1, true); event.accepted = true; return }
        if (event.key === Qt.Key_Up) { triggerJog("R", 1, true); event.accepted = true; return }
        if (event.key === Qt.Key_Down) { triggerJog("R", -1, true); event.accepted = true; return }
    }

    Keys.onReleased: function(event) {
        if (event.isAutoRepeat) return
        if (event.key === Qt.Key_Left) { triggerJog("X", -1, false); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { triggerJog("X", 1, false); event.accepted = true; return }
        if (event.key === Qt.Key_Up) { triggerJog("R", 1, false); event.accepted = true; return }
        if (event.key === Qt.Key_Down) { triggerJog("R", -1, false); event.accepted = true; return }
    }

    function triggerHome() {
        if (appState) {
            appState.requestBackGaugeHome()
        } else {
            simX = 0.0000
            simR = 0.0000
            isHomed = true
        }
    }

    function triggerStop() {
        activeDirection = ""
        if (appState) appState.backGaugeStop()
    }

    function triggerExecuteMove() {
        if (appState) {
            appState.backGaugeMoveTo(targetX.toFixed(4), targetR.toFixed(4))
        } else {
            simX = targetX
            simR = targetR
        }
    }

    // -------------------------------------------------------------------------
    // Main UI Layout: 864 × 638
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: root.bgDark
        radius: 8
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // =================================================================
            // 1. TOP HEADER COCKPIT BAR (Height: 46px)
            // =================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: 8
                color: root.cardBg
                border.color: root.cardBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    // Module Title Badge
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            width: 3
                            height: 16
                            radius: 1.5
                            color: root.cyanAccent
                        }
                        Text {
                            text: qsTr("BACK GAUGE")
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                        Rectangle {
                            height: 20
                            width: versionText.implicitWidth + 10
                            radius: 4
                            color: "#1E293B"
                            border.color: "#334155"
                            border.width: 1
                            Text {
                                id: versionText
                                anchors.centerIn: parent
                                text: qsTr("2-AXIS CNC · X/R")
                                color: root.cyanAccent
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Homing Status & Action Button
                    Rectangle {
                        id: homeBtn
                        height: 32
                        Layout.preferredWidth: homeRow.implicitWidth + 16
                        radius: 6
                        color: root.isHomed ? "#064E3B" : "#7F1D1D"
                        border.color: root.isHomed ? root.emeraldAccent : root.redAccent
                        border.width: 1.2

                        RowLayout {
                            id: homeRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 7
                                height: 7
                                radius: 3.5
                                color: root.isHomed ? "#34D399" : "#F87171"
                            }
                            Text {
                                text: root.isHomed ? qsTr("HOMED · MACHINE ZERO") : qsTr("NOT HOMED · ALT+H")
                                color: "white"
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.triggerHome()
                        }
                    }

                    // Profile / Coordinate System Selector Dropdown
                    Rectangle {
                        height: 32
                        Layout.preferredWidth: 175
                        radius: 6
                        color: "#18202F"
                        border.color: "#334155"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 6

                            Text {
                                text: root.profileNames[root.selectedProfile] || root.selectedProfile
                                color: root.textPrimary
                                font.pixelSize: 10
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            // Quick Rename Pencil
                            Rectangle {
                                width: 22
                                height: 22
                                radius: 4
                                color: "#283548"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✎"
                                    color: root.textSecondary
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.appState) {
                                            root.appState.openOnScreenKeyboard(null, false, qsTr("RENAME STOP PROFILE"),
                                                function(val) { root.appState.renameBackGaugeCoordinateSystem(val) }, null)
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                var profiles = ["G54", "G55", "G56", "G57", "G58", "G59"]
                                var idx = (profiles.indexOf(root.selectedProfile) + 1) % profiles.length
                                root.selectedProfile = profiles[idx]
                                if (root.appState) root.appState.selectBackGaugeCoordinateSystem(root.selectedProfile)
                            }
                        }
                    }

                    // Coordinate Mode Toggle (WORK vs MACHINE)
                    Rectangle {
                        height: 30
                        Layout.preferredWidth: 140
                        radius: 5
                        color: "#0F172A"
                        border.color: "#334155"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                color: !root.showMachineCoords ? root.cyanGlow : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("WORK (WCS)")
                                    color: !root.showMachineCoords ? "white" : root.textMuted
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.showMachineCoords = false
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                color: root.showMachineCoords ? "#6366F1" : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("MACHINE (MCS)")
                                    color: root.showMachineCoords ? "white" : root.textMuted
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.showMachineCoords = true
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 2. MAIN COCKPIT: TWO-COLUMN INTERACTIVE SPLIT (Height: 520px)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // -------------------------------------------------------------
                // LEFT COLUMN: 2D GAUGE POSITION STAGE + JOG COMPASS (Width: 418px)
                // -------------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 418
                    spacing: 8

                    // CARD A: Interactive 2D Physical Back Gauge Stage (Height: 200px)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        radius: 8
                        color: root.cardBg
                        border.color: root.cardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            // Card Subtitle
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { width: 3; height: 12; radius: 1.5; color: root.cyanAccent }
                                Text {
                                    text: qsTr("2D PROFILE & TRAVEL ENVELOPE")
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("DIE DATUM: X=0.0000 · R=0.0000")
                                    color: root.textMuted
                                    font.pixelSize: 9
                                    font.family: "Monospace"
                                }
                            }

                            // 2D Canvas Stage
                            Canvas {
                                id: stageCanvas
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                onPaint: {
                                    var ctx = getContext("2d")
                                    var w = width
                                    var h = height
                                    ctx.clearRect(0, 0, w, h)

                                    // Canvas Background
                                    ctx.fillStyle = "#090D14"
                                    ctx.fillRect(0, 0, w, h)

                                    // Precision grid
                                    ctx.strokeStyle = "#161F2E"
                                    ctx.lineWidth = 1
                                    for (var gx = 20; gx < w; gx += 25) {
                                        ctx.beginPath(); ctx.moveTo(gx, 0); ctx.lineTo(gx, h); ctx.stroke()
                                    }
                                    for (var gy = 15; gy < h; gy += 25) {
                                        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
                                    }

                                    // Bending Reference Datum Line (X = 0) at x=55
                                    var datumX = 55
                                    var datumY = h - 45

                                    // Draw Lower Die V-Block Silhouette (Left)
                                    ctx.fillStyle = "#1E293B"
                                    ctx.strokeStyle = "#475569"
                                    ctx.lineWidth = 1.5
                                    ctx.beginPath()
                                    ctx.moveTo(10, h)
                                    ctx.lineTo(10, datumY + 12)
                                    ctx.lineTo(datumX - 15, datumY + 12)
                                    ctx.lineTo(datumX, datumY - 10) // V-die groove
                                    ctx.lineTo(datumX + 15, datumY + 12)
                                    ctx.lineTo(datumX + 15, h)
                                    ctx.closePath()
                                    ctx.fill()
                                    ctx.stroke()

                                    // Die Centerline (Cyan dashed line)
                                    ctx.strokeStyle = "#0284C7"
                                    ctx.lineWidth = 1.2
                                    ctx.setLineDash([3, 3])
                                    ctx.beginPath()
                                    ctx.moveTo(datumX, 5)
                                    ctx.lineTo(datumX, h - 5)
                                    ctx.stroke()
                                    ctx.setLineDash([])

                                    ctx.fillStyle = "#38BDF8"
                                    ctx.font = "8px Monospace"
                                    ctx.fillText("BEND LINE", datumX - 22, 12)

                                    // Sheet Rest Reference Plane (Bed Line)
                                    ctx.strokeStyle = "#334155"
                                    ctx.lineWidth = 1.5
                                    ctx.beginPath()
                                    ctx.moveTo(datumX + 15, datumY)
                                    ctx.lineTo(w - 15, datumY)
                                    ctx.stroke()

                                    // Gauge Travel Stroke Safe Envelope (0 to 24 in)
                                    var minPx = datumX + 25
                                    var maxPx = w - 40
                                    var usableW = maxPx - minPx

                                    // Calculate animated finger position
                                    var normalizedX = Math.min(24.0, Math.max(0.0, root.simX)) / 24.0
                                    var fingerScreenX = minPx + normalizedX * usableW
                                    var normalizedR = Math.min(6.0, Math.max(-0.5, root.simR)) / 6.0
                                    var fingerScreenY = datumY - (normalizedR * 50)

                                    // Draw Sheet Metal (Workpiece) resting on die & touching finger
                                    ctx.fillStyle = "rgba(148, 163, 184, 0.45)"
                                    ctx.strokeStyle = "#94A3B8"
                                    ctx.lineWidth = 1.2
                                    ctx.beginPath()
                                    ctx.fillRect(datumX - 10, datumY - 4, fingerScreenX - (datumX - 10), 4)
                                    ctx.strokeRect(datumX - 10, datumY - 4, fingerScreenX - (datumX - 10), 4)

                                    // Draw Back Gauge Finger Body Silhouette
                                    ctx.fillStyle = "#0284C7"
                                    ctx.strokeStyle = "#38BDF8"
                                    ctx.lineWidth = 1.5

                                    ctx.beginPath()
                                    // Finger tip contact point
                                    ctx.moveTo(fingerScreenX, fingerScreenY)
                                    ctx.lineTo(fingerScreenX + 16, fingerScreenY - 12) // step 1
                                    ctx.lineTo(fingerScreenX + 32, fingerScreenY - 12)
                                    ctx.lineTo(fingerScreenX + 32, fingerScreenY - 26) // step 2
                                    ctx.lineTo(fingerScreenX + 50, fingerScreenY - 26)
                                    ctx.lineTo(fingerScreenX + 50, fingerScreenY + 28) // main body post
                                    ctx.lineTo(fingerScreenX + 25, fingerScreenY + 28)
                                    ctx.lineTo(fingerScreenX + 25, fingerScreenY + 8)
                                    ctx.lineTo(fingerScreenX, fingerScreenY)
                                    ctx.closePath()
                                    ctx.fill()
                                    ctx.stroke()

                                    // Contact Point Glowing Pulse
                                    ctx.fillStyle = "#38BDF8"
                                    ctx.beginPath()
                                    ctx.arc(fingerScreenX, fingerScreenY, 3.5, 0, 2 * Math.PI)
                                    ctx.fill()

                                    // Current Depth Dimension Label
                                    ctx.fillStyle = "#F8FAFC"
                                    ctx.font = "bold 9px Monospace"
                                    ctx.fillText("X: " + root.simX.toFixed(3) + " " + root.unitStr, fingerScreenX - 18, fingerScreenY + 42)
                                    ctx.fillStyle = "#C084FC"
                                    ctx.fillText("R: " + root.simR.toFixed(3) + " " + root.unitStr, fingerScreenX - 18, fingerScreenY + 53)
                                }
                            }

                            // Trigger repaint on coordinate changes
                            Connections {
                                target: root
                                function onSimXChanged() { stageCanvas.requestPaint() }
                                function onSimRChanged() { stageCanvas.requestPaint() }
                            }

                            // Bottom travel envelope status bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: qsTr("TRAVEL: X [0.00 – 24.00\"]")
                                    color: root.textMuted
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("R [-0.50 – 6.00\"] · CLEARANCE SAFE")
                                    color: root.emeraldAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // CARD B: Ergonomic Tactile Jog Cluster & Micro-Nudge (Height: 312px)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: root.cardBg
                        border.color: root.cardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { width: 3; height: 12; radius: 1.5; color: root.purpleAccent }
                                Text {
                                    text: qsTr("TACTILE MOTION CLUSTER & NUDGE")
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    height: 18
                                    width: jogModeLabel.implicitWidth + 10
                                    radius: 3
                                    color: root.jogContinuous ? "#312E81" : "#1E293B"
                                    border.color: root.jogContinuous ? "#6366F1" : "#475569"
                                    border.width: 1
                                    Text {
                                        id: jogModeLabel
                                        anchors.centerIn: parent
                                        text: root.jogContinuous ? qsTr("CONTINUOUS") : (qsTr("STEP ") + root.jogStepVal.toFixed(4) + " " + root.unitStr)
                                        color: root.jogContinuous ? "#A5B4FC" : root.cyanAccent
                                        font.pixelSize: 8
                                        font.bold: true
                                    }
                                }
                            }

                            // Center Jog Compass (Cross layout with central indicator)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Grid {
                                    anchors.centerIn: parent
                                    columns: 3
                                    rows: 3
                                    spacing: 8

                                    // Row 1: [ -0.001" R ] [ ▲ R+ (LIFT) ] [ +0.001" R ]
                                    NudgeButton { text: "-.001 R"; onClicked: root.nudgeAxis("R", -0.001) }
                                    JogButton {
                                        id: btnRPlus
                                        axis: "R"; dir: 1; label: "R+ LIFT"
                                        iconGlyph: "▲"; accent: root.purpleAccent
                                    }
                                    NudgeButton { text: "+.001 R"; onClicked: root.nudgeAxis("R", 0.001) }

                                    // Row 2: [ ◄ X- (ADVANCE) ] [ CORE / STOP ] [ X+ ► (RETRACT) ]
                                    JogButton {
                                        id: btnXMinus
                                        axis: "X"; dir: -1; label: "X- ADVANCE"
                                        iconGlyph: "◄"; accent: root.cyanAccent
                                    }
                                    Rectangle {
                                        width: 72
                                        height: 60
                                        radius: 6
                                        color: root.activeDirection.length > 0 ? root.cyanGlow : "#1E2837"
                                        border.color: root.activeDirection.length > 0 ? root.cyanAccent : "#334155"
                                        border.width: 1.5

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                text: root.activeDirection.length > 0 ? root.activeDirection : "AXIS"
                                                color: "white"
                                                font.pixelSize: 14
                                                font.bold: true
                                                font.family: "Monospace"
                                                Layout.alignment: Qt.AlignHCenter
                                            }
                                            Text {
                                                text: root.activeDirection.length > 0 ? qsTr("ACTIVE") : qsTr("READY")
                                                color: root.activeDirection.length > 0 ? "#67E8F9" : root.textMuted
                                                font.pixelSize: 8
                                                font.bold: true
                                                Layout.alignment: Qt.AlignHCenter
                                            }
                                        }
                                    }
                                    JogButton {
                                        id: btnXPlus
                                        axis: "X"; dir: 1; label: "X+ RETRACT"
                                        iconGlyph: "►"; accent: root.cyanAccent
                                    }

                                    // Row 3: [ -0.010" X ] [ ▼ R- (LOWER) ] [ +0.010" X ]
                                    NudgeButton { text: "-.010 X"; onClicked: root.nudgeAxis("X", -0.010) }
                                    JogButton {
                                        id: btnRMinus
                                        axis: "R"; dir: -1; label: "R- LOWER"
                                        iconGlyph: "▼"; accent: root.purpleAccent
                                    }
                                    NudgeButton { text: "+.010 X"; onClicked: root.nudgeAxis("X", 0.010) }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // RIGHT COLUMN: DUAL DRO + STEP/SPEED HUBS + TARGET RUN (Width: 418px)
                // -------------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 418
                    spacing: 8

                    // CARD 1: Precision Dual DRO Deck (Height: 172px)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 172
                        radius: 8
                        color: root.cardBg
                        border.color: root.cardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { width: 3; height: 12; radius: 1.5; color: root.cyanAccent }
                                Text {
                                    text: qsTr("HIGH-CONTRAST DIGITAL READOUT (DRO)")
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.showMachineCoords ? qsTr("VIEW: MACHINE ABSOLUTE") : qsTr("VIEW: WORK ORIGIN")
                                    color: root.showMachineCoords ? "#A5B4FC" : root.cyanAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            // X-AXIS READOUT POD
                            Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                radius: 6
                                color: "#0B0F17"
                                border.color: root.activeDirection.indexOf("X") === 0 ? root.cyanAccent : "#1E2838"
                                border.width: 1.5

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Axis Badge
                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 4
                                        color: "#0C4A6E"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "X"
                                            color: root.cyanAccent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 0
                                        Text {
                                            text: (root.showMachineCoords ? root.simMachineX : root.simX).toFixed(4)
                                            color: "white"
                                            font.pixelSize: 22
                                            font.bold: true
                                            font.family: "Monospace"
                                        }
                                        Text {
                                            text: root.showMachineCoords ? ("WCS: " + root.simX.toFixed(4) + " " + root.unitStr) : ("MCS: " + root.simMachineX.toFixed(4) + " " + root.unitStr)
                                            color: root.textMuted
                                            font.pixelSize: 9
                                            font.family: "Monospace"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Action: ZERO X
                                    Rectangle {
                                        width: 60
                                        height: 28
                                        radius: 4
                                        color: "#1E293B"
                                        border.color: "#334155"
                                        border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("ZERO X")
                                            color: "#E2E8F0"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.simX = 0.0000
                                                if (root.appState) root.appState.setBackGaugeWorkPosition("X", 0)
                                            }
                                        }
                                    }

                                    // Action: SET X
                                    Rectangle {
                                        width: 52
                                        height: 28
                                        radius: 4
                                        color: "#0369A1"
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("SET X")
                                            color: "white"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (root.appState) {
                                                    root.appState.openOnScreenKeyboard(null, true, qsTr("SET X WORK POSITION"),
                                                        function(v) { root.simX = Number(v); root.appState.setBackGaugeWorkPosition("X", v) }, null)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // R-AXIS READOUT POD
                            Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                radius: 6
                                color: "#0B0F17"
                                border.color: root.activeDirection.indexOf("R") === 0 ? root.purpleAccent : "#1E2838"
                                border.width: 1.5

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Axis Badge
                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 4
                                        color: "#4C1D95"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "R"
                                            color: root.purpleAccent
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 0
                                        Text {
                                            text: (root.showMachineCoords ? root.simMachineR : root.simR).toFixed(4)
                                            color: "white"
                                            font.pixelSize: 22
                                            font.bold: true
                                            font.family: "Monospace"
                                        }
                                        Text {
                                            text: root.showMachineCoords ? ("WCS: " + root.simR.toFixed(4) + " " + root.unitStr) : ("MCS: " + root.simMachineR.toFixed(4) + " " + root.unitStr)
                                            color: root.textMuted
                                            font.pixelSize: 9
                                            font.family: "Monospace"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Action: ZERO R
                                    Rectangle {
                                        width: 60
                                        height: 28
                                        radius: 4
                                        color: "#1E293B"
                                        border.color: "#334155"
                                        border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("ZERO R")
                                            color: "#E2E8F0"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.simR = 0.0000
                                                if (root.appState) root.appState.setBackGaugeWorkPosition("R", 0)
                                            }
                                        }
                                    }

                                    // Action: SET R
                                    Rectangle {
                                        width: 52
                                        height: 28
                                        radius: 4
                                        color: "#7C3AED"
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("SET R")
                                            color: "white"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (root.appState) {
                                                    root.appState.openOnScreenKeyboard(null, true, qsTr("SET R WORK POSITION"),
                                                        function(v) { root.simR = Number(v); root.appState.setBackGaugeWorkPosition("R", v) }, null)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // CARD 2: Consolidated Step Increment & Speed Hub (Height: 180px)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        radius: 8
                        color: root.cardBg
                        border.color: root.cardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            // SECTION 2A: JOG STEP INCREMENT
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: qsTr("JOG STEP INCREMENT")
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.jogContinuous ? qsTr("CONTINUOUS ACTIVE") : (root.jogStepVal.toFixed(4) + " " + root.unitStr)
                                    color: root.cyanAccent
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "Monospace"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: [
                                        { val: 0.0005, label: "0.0005\"" },
                                        { val: 0.0010, label: "0.001\"" },
                                        { val: 0.0100, label: "0.010\"" },
                                        { val: 0.1000, label: "0.100\"" },
                                        { val: -1.0, label: "CONT." }
                                    ]
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 30
                                        radius: 4
                                        readonly property bool isSelected: modelData.val < 0 ? root.jogContinuous : (!root.jogContinuous && Math.abs(root.jogStepVal - modelData.val) < 0.0001)
                                        color: isSelected ? (modelData.val < 0 ? "#4338CA" : root.cyanGlow) : "#18202F"
                                        border.color: isSelected ? (modelData.val < 0 ? "#818CF8" : root.cyanAccent) : "#283548"
                                        border.width: isSelected ? 1.5 : 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: parent.isSelected ? "white" : root.textSecondary
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (modelData.val < 0) {
                                                    root.jogContinuous = true
                                                    if (root.appState) root.appState.setBackGaugeJogStep(root.jogStepVal, true)
                                                } else {
                                                    root.jogContinuous = false
                                                    root.jogStepVal = modelData.val
                                                    if (root.appState) root.appState.setBackGaugeJogStep(modelData.val, false)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // SECTION 2B: JOG VELOCITY & FEEDRATE
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Layout.topMargin: 4
                                Text {
                                    text: qsTr("JOG VELOCITY & FEEDRATE")
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.jogSpeedVal.toFixed(0) + " " + root.speedUnitStr
                                    color: root.purpleAccent
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "Monospace"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: [
                                        { val: 10, label: "10%" },
                                        { val: 25, label: "25%" },
                                        { val: 50, label: "50%" },
                                        { val: 75, label: "75%" },
                                        { val: 100, label: "RAPID" }
                                    ]
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 30
                                        radius: 4
                                        readonly property bool isSelected: Math.abs(root.jogSpeedVal - modelData.val) < 1.0
                                        color: isSelected ? (modelData.val === 100 ? "#B91C1C" : "#7C3AED") : "#18202F"
                                        border.color: isSelected ? (modelData.val === 100 ? "#F87171" : root.purpleAccent) : "#283548"
                                        border.width: isSelected ? 1.5 : 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: parent.isSelected ? "white" : root.textSecondary
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.jogSpeedVal = modelData.val
                                                if (root.appState) root.appState.setBackGaugeJogSpeed(modelData.val)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // CARD 3: Direct Target Position & Move Run Deck (Height: 140px)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: root.cardBg
                        border.color: root.cardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { width: 3; height: 12; radius: 1.5; color: root.amberAccent }
                                Text {
                                    text: qsTr("ABSOLUTE MOVE COMMAND")
                                    color: root.textSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("PRESETS: ")
                                    color: root.textMuted
                                    font.pixelSize: 9
                                }
                                Text {
                                    text: qsTr("FLUSH · RETRACT · PARK")
                                    color: root.amberAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            // Coordinate Inputs & Action Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Target X Input Pod
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 40
                                    radius: 5
                                    color: "#0F172A"
                                    border.color: "#334155"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { text: "TARGET X:"; color: root.cyanAccent; font.pixelSize: 10; font.bold: true }
                                        Text {
                                            text: root.targetX.toFixed(4)
                                            color: "white"
                                            font.pixelSize: 14
                                            font.bold: true
                                            font.family: "Monospace"
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text { text: root.unitStr; color: root.textMuted; font.pixelSize: 9 }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.appState) {
                                                root.appState.openOnScreenKeyboard(null, true, qsTr("ENTER TARGET X"),
                                                    function(v) { root.targetX = Number(v) }, null)
                                            } else {
                                                root.targetX = root.targetX === 4.25 ? 8.50 : 4.25
                                            }
                                        }
                                    }
                                }

                                // Target R Input Pod
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 40
                                    radius: 5
                                    color: "#0F172A"
                                    border.color: "#334155"
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { text: "TARGET R:"; color: root.purpleAccent; font.pixelSize: 10; font.bold: true }
                                        Text {
                                            text: root.targetR.toFixed(4)
                                            color: "white"
                                            font.pixelSize: 14
                                            font.bold: true
                                            font.family: "Monospace"
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text { text: root.unitStr; color: root.textMuted; font.pixelSize: 9 }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.appState) {
                                                root.appState.openOnScreenKeyboard(null, true, qsTr("ENTER TARGET R"),
                                                    function(v) { root.targetR = Number(v) }, null)
                                            } else {
                                                root.targetR = root.targetR === 1.125 ? 2.500 : 1.125
                                            }
                                        }
                                    }
                                }

                                // Prominent RUN / EXECUTE Button
                                Rectangle {
                                    width: 110
                                    height: 40
                                    radius: 5
                                    color: root.amberAccent
                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("RUN MOVE ▶")
                                        color: "#0F172A"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.triggerExecuteMove()
                                    }
                                }
                            }

                            // Quick Presets Pill Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                PresetPill { text: qsTr("0.000 FLUSH"); onClicked: { root.targetX = 0.0; root.targetR = 0.0 } }
                                PresetPill { text: qsTr("2.000 RETRACT"); onClicked: { root.targetX = 2.0; root.targetR = 0.5 } }
                                PresetPill { text: qsTr("6.000 MEDIUM"); onClicked: { root.targetX = 6.0; root.targetR = 1.0 } }
                                PresetPill { text: qsTr("12.000 PARK"); onClicked: { root.targetX = 12.0; root.targetR = 2.0 } }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 3. BOTTOM SAFETY & LIMITS MATRIX STRIP (Height: 44px)
            // =================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 8
                color: root.cardBg
                border.color: root.cardBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    // Limit Switch Indicators Matrix
                    RowLayout {
                        spacing: 6
                        Text {
                            text: qsTr("LIMIT MATRIX:")
                            color: root.textMuted
                            font.pixelSize: 9
                            font.bold: true
                        }
                        LimitPill {
                            label: "X1 MIN"
                            active: root.appState ? root.appState.backGaugeLimitX1 : (root.simX <= 0.001)
                        }
                        LimitPill {
                            label: "X2 MAX"
                            active: root.appState ? root.appState.backGaugeLimitX2 : (root.simX >= 23.99)
                        }
                        LimitPill {
                            label: "R1 MIN"
                            active: root.appState ? root.appState.backGaugeLimitR1 : (root.simR <= -0.49)
                        }
                        LimitPill {
                            label: "R2 MAX"
                            active: root.appState ? root.appState.backGaugeLimitR2 : (root.simR >= 5.99)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Motion Status
                    RowLayout {
                        spacing: 6
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: root.isReady ? root.emeraldAccent : root.redAccent
                        }
                        Text {
                            text: root.appState ? root.appState.backGaugeStatus : (root.activeDirection.length > 0 ? qsTr("MOTION ACTIVE · ") + root.activeDirection : qsTr("READY · CLOSED LOOP SERVO"))
                            color: root.textPrimary
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // Industrial Emergency STOP Button
                    Rectangle {
                        width: 175
                        height: 32
                        radius: 5
                        color: root.redAccent
                        border.color: root.redDark
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "⚠"
                                color: "white"
                                font.pixelSize: 13
                            }
                            Text {
                                text: qsTr("STOP BACK GAUGE")
                                color: "white"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.5
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.triggerStop()
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Reusable Sub-components
    // -------------------------------------------------------------------------
    component JogButton: Rectangle {
        id: jogComp
        property string axis: "X"
        property int dir: 1
        property string label: ""
        property string iconGlyph: ""
        property color accent: root.cyanAccent

        readonly property bool isPressed: root.activeDirection === (axis + (dir > 0 ? "+" : "-"))

        width: 105
        height: 60
        radius: 6
        color: isPressed ? Qt.darker(accent, 1.4) : (mouseArea.containsMouse ? root.jogPadHover : root.jogPadBg)
        border.color: isPressed ? accent : (mouseArea.containsMouse ? root.cardBorderHighlight : root.cardBorder)
        border.width: isPressed ? 2 : 1

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Text {
                text: jogComp.iconGlyph
                color: jogComp.isPressed ? "white" : jogComp.accent
                font.pixelSize: 16
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: jogComp.label
                color: jogComp.isPressed ? "white" : root.textPrimary
                font.pixelSize: 9
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: root.triggerJog(jogComp.axis, jogComp.dir, true)
            onReleased: root.triggerJog(jogComp.axis, jogComp.dir, false)
            onCanceled: root.triggerJog(jogComp.axis, jogComp.dir, false)
        }
    }

    component NudgeButton: Rectangle {
        property string text: ""
        signal clicked()

        width: 72
        height: 60
        radius: 6
        color: nudgeArea.pressed ? "#1E293B" : (nudgeArea.containsMouse ? "#182333" : "#121A26")
        border.color: nudgeArea.containsMouse ? root.cyanAccent : "#243144"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: parent.text
            color: root.textSecondary
            font.pixelSize: 9
            font.bold: true
            font.family: "Monospace"
        }

        MouseArea {
            id: nudgeArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }

    component PresetPill: Rectangle {
        property string text: ""
        signal clicked()

        Layout.fillWidth: true
        height: 24
        radius: 4
        color: "#18202F"
        border.color: "#334155"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: parent.text
            color: root.textSecondary
            font.pixelSize: 8
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: parent.clicked()
        }
    }

    component LimitPill: Rectangle {
        property string label: ""
        property bool active: false

        height: 22
        width: 52
        radius: 4
        color: active ? root.redDark : "#18202F"
        border.color: active ? root.redAccent : "#334155"
        border.width: active ? 1.5 : 1

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.active ? "white" : root.textMuted
            font.pixelSize: 8
            font.bold: true
        }
    }
}
