pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes

// =============================================================================
// BENDCNC V5 PRECISION - BACK GAUGE LEFT PANEL (864 × 638)
// VIVID INDUSTRIAL PALETTE (Matches BendCNC Production Identity)
//
// Implementa exactamente los refinamientos solicitados sobre el diseño V5:
// 1. JOG VELOCITY: El valor (100.000 IPM) es un campo de entrada editable con
//    fondo blanco interactivo para cambiar la velocidad mediante teclado numérico.
// 2. LIMIT SWITCHES: Muestra estrictamente X1, X2, R1, R2 para cada lado.
// 3. MOTION CLUSTER ORGANIZADO:
//    - Cruceta de jog direccional simétrica y limpia (R+ LIFT, X- ADVANCE, X+ RETRACT, R- LOWER).
//    - Barra inferior de micro-nudge perfectamente alineada y separada (±0.001" R | ±0.010" X).
// =============================================================================

Item {
    id: root
    objectName: "backgauge-left-panel-v5"

    property var appState: null
    property bool designerInteractive: true

    width: 864
    height: 638
    focus: true

    // -------------------------------------------------------------------------
    // Offline Simulation & Interactive Preview State
    // -------------------------------------------------------------------------
    property real simX: appState && isFinite(Number(appState.backGaugeX)) && Number(appState.backGaugeX) > 0 ? Number(appState.backGaugeX) : 4.2500
    property real simR: appState && isFinite(Number(appState.backGaugeR)) && Number(appState.backGaugeR) > 0 ? Number(appState.backGaugeR) : 1.1250
    property real simMachineX: appState && isFinite(Number(appState.backGaugeMachineX)) && Number(appState.backGaugeMachineX) > 0 ? Number(appState.backGaugeMachineX) : (simX + 1.7500)
    property real simMachineR: appState && isFinite(Number(appState.backGaugeMachineR)) && Number(appState.backGaugeMachineR) > 0 ? Number(appState.backGaugeMachineR) : (simR + 0.8500)
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
    property real jogSpeedVal: appState && isFinite(Number(appState.jogSpeed)) ? Number(appState.jogSpeed) : 100.0
    property string unitStr: appState && appState.backGaugeUnit === "MILLIMETER" ? "mm" : "in"
    property string speedUnitStr: appState && appState.backGaugeUnit === "MILLIMETER" ? "MMM" : "IPM"

    // Target positions
    property real targetX: simX
    property real targetR: simR

    // -------------------------------------------------------------------------
    // Design Tokens (BendCNC Vivid Production Palette)
    // -------------------------------------------------------------------------
    readonly property color bgCanvas: "#E5E7EB"         // Industrial base grey
    readonly property color cardBg: "#FFFFFF"           // Elevated crisp white cards
    readonly property color cardBgAlt: "#F8FAFC"        // Subtle technical card tint
    readonly property color cardBorder: "#CBD5E1"       // Clean card outline
    readonly property color topBarBg: "#23272D"         // Solid charcoal cockpit bar
    readonly property color ink: "#1E232A"              // High-contrast primary text
    readonly property color textSecondary: "#475569"    // Slate secondary labels
    readonly property color textMuted: "#64748B"        // Muted captions

    // Vivid Accent Colors (Authentic to BendCNC)
    readonly property color blueAccent: "#2D83B2"       // Vivid steel blue (primary action / jog active)
    readonly property color blueHover: "#1E75A6"        // Deep vivid blue
    readonly property color greenAccent: "#59A60C"      // Vivid emerald green (homed, ready, idle)
    readonly property color redAccent: "#A82011"        // Vivid rich red (stop, continuous, limits)
    readonly property color orangeAccent: "#FFA500"     // Vivid safety orange (run button)
    readonly property color orangeDark: "#EA580C"       // Vivid deep amber
    readonly property color purpleAccent: "#7C3AED"     // Vivid purple (R axis identity)
    readonly property color charcoal: "#2B2C2B"         // Authentic BendCNC jog button charcoal

    // -------------------------------------------------------------------------
    // Keyboard & Jog Handlers
    // -------------------------------------------------------------------------
    // Hidden text target required by AppState.openOnScreenKeyboard().
    TextInput { id: keyboardProxy; visible: false; width: 0; height: 0 }

    function openKeyboard(numeric, title, initial, commit) {
        if (!appState)
            return false
        keyboardProxy.text = initial === undefined || initial === null ? "" : String(initial)
        return appState.openOnScreenKeyboard(keyboardProxy, numeric, title, commit, null, true)
    }

    function profileLabel(system) {
        if (appState && appState.backGaugeCoordinateDisplayName)
            return appState.backGaugeCoordinateDisplayName(system)
        return profileNames[system] || system
    }

    function triggerJog(axis, dir, pressed) {
        if (pressed) {
            if (!appState) root.activeDirection = axis + (dir > 0 ? "+" : "-")
            if (appState) {
                appState.beginBackGaugeJog(axis, dir)
            } else if (designerInteractive) {
                var step = jogContinuous ? 0.05 : jogStepVal
                if (axis === "X") simX = Math.max(0, Math.min(24.0, simX + dir * step))
                if (axis === "R") simR = Math.max(-0.5, Math.min(6.0, simR + dir * step))
            }
        } else {
            if (!appState) root.activeDirection = ""
            if (appState) {
                appState.releaseBackGaugeJog(axis, dir)
            }
        }
    }

    function nudgeAxis(axis, delta) {
        if (appState) {
            appState.setBackGaugeWorkPosition(axis, (axis === "X" ? simX : simR) + delta)
            return
        }
        if (axis === "X")
            simX = Math.max(0, Math.min(24.0, simX + delta))
        else if (axis === "R")
            simR = Math.max(-0.5, Math.min(6.0, simR + delta))
    }

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat) return
        if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_H) {
            triggerHome(); event.accepted = true; return
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
        if (appState) appState.backGaugeStop()
        else activeDirection = ""
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
        color: root.bgCanvas
        radius: 0
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 8

            // =================================================================
            // 1. TOP HEADER COCKPIT BAR (Height: 46px)
            // =================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: 7
                color: root.topBarBg
                border.color: "#374151"
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
                            width: 3.5
                            height: 18
                            radius: 1.75
                            color: root.blueAccent
                        }
                        Text {
                            text: qsTr("BACK GAUGE")
                            color: "white"
                            font.pixelSize: 13
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                        Rectangle {
                            height: 22
                            width: versionText.implicitWidth + 12
                            radius: 4
                            color: root.blueAccent
                            Text {
                                id: versionText
                                anchors.centerIn: parent
                                text: qsTr("2-AXIS CNC · X/R")
                                color: "white"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Homing Status & Action Button (Vivid Green when homed)
                    Rectangle {
                        id: homeBtn
                        height: 32
                        Layout.preferredWidth: homeRow.implicitWidth + 18
                        radius: 5
                        color: root.isHomed ? root.greenAccent : root.redAccent
                        border.color: root.isHomed ? "#74C01D" : "#EF4444"
                        border.width: 1

                        RowLayout {
                            id: homeRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "white"
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

                    // Profile / Coordinate System Selector Dropdown (Crisp White Pill)
                    Rectangle {
                        height: 32
                        Layout.preferredWidth: 180
                        radius: 5
                        color: "#FFFFFF"
                        border.color: "#CBD5E1"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: root.profileLabel(root.selectedProfile)
                                color: root.ink
                                font.pixelSize: 10
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            // Quick Rename Pencil in Red
                            Rectangle {
                                width: 22
                                height: 22
                                radius: 4
                                color: "#FEE2E2"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✎"
                                    color: root.redAccent
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.openKeyboard(false, qsTr("RENAME STOP PROFILE"), root.profileLabel(root.selectedProfile),
                                            function(val) { root.appState.renameBackGaugeCoordinateSystem(val) })
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                var profiles = root.appState ? root.appState.backGaugeCoordinateSystems : ["G54", "G55", "G56", "G57", "G58", "G59"]
                                var next = profiles[(profiles.indexOf(root.selectedProfile) + 1) % profiles.length]
                                if (root.appState) root.appState.selectBackGaugeCoordinateSystem(next)
                                else root.selectedProfile = next
                            }
                        }
                    }

                    // Coordinate Mode Toggle (WORK vs MACHINE)
                    Rectangle {
                        height: 32
                        Layout.preferredWidth: 155
                        radius: 5
                        color: "#1E2328"
                        border.color: "#4B5563"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 2
                            anchors.margins: 2

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 4
                                color: !root.showMachineCoords ? root.blueAccent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("WORK (WCS)")
                                    color: "white"
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
                                color: root.showMachineCoords ? root.blueAccent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: qsTr("MACHINE (MCS)")
                                    color: "white"
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
                        radius: 7
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
                                Rectangle { width: 3.5; height: 13; radius: 1.75; color: root.blueAccent }
                                Text {
                                    text: qsTr("2D PROFILE & TRAVEL ENVELOPE")
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("DIE DATUM: X=0.0000 · R=0.0000")
                                    color: root.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.family: "Monospace"
                                }
                            }

                            // 2D Canvas Stage (Clean Technical Blueprint Style)
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
                                    ctx.fillStyle = "#F1F5F9"
                                    ctx.fillRect(0, 0, w, h)

                                    // Subtle drafting grid
                                    ctx.strokeStyle = "#E2E8F0"
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

                                    // Draw Lower Die V-Block Silhouette (Machined Gunmetal Steel)
                                    ctx.fillStyle = "#475569"
                                    ctx.strokeStyle = "#334155"
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

                                    // Die Centerline (Vivid Crimson Dashed Line)
                                    ctx.strokeStyle = root.redAccent
                                    ctx.lineWidth = 1.5
                                    ctx.setLineDash([4, 3])
                                    ctx.beginPath()
                                    ctx.moveTo(datumX, 5)
                                    ctx.lineTo(datumX, h - 5)
                                    ctx.stroke()
                                    ctx.setLineDash([])

                                    ctx.fillStyle = root.redAccent
                                    ctx.font = "bold 8px sans-serif"
                                    ctx.fillText("BEND LINE", datumX - 22, 12)

                                    // Sheet Rest Reference Plane (Bed Line)
                                    ctx.strokeStyle = "#94A3B8"
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
                                    ctx.fillStyle = "#94A3B8"
                                    ctx.strokeStyle = "#475569"
                                    ctx.lineWidth = 1.2
                                    ctx.beginPath()
                                    ctx.fillRect(datumX - 10, datumY - 4, fingerScreenX - (datumX - 10), 4)
                                    ctx.strokeRect(datumX - 10, datumY - 4, fingerScreenX - (datumX - 10), 4)

                                    // Draw Back Gauge Finger Body Silhouette
                                    ctx.fillStyle = root.blueAccent
                                    ctx.strokeStyle = "#1E75A6"
                                    ctx.lineWidth = 1.5

                                    ctx.beginPath()
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

                                    // Contact Point Highlight
                                    ctx.fillStyle = root.orangeAccent
                                    ctx.beginPath()
                                    ctx.arc(fingerScreenX, fingerScreenY, 4, 0, 2 * Math.PI)
                                    ctx.fill()

                                    // Coordinate tags
                                    ctx.fillStyle = root.ink
                                    ctx.font = "bold 9px Monospace"
                                    ctx.fillText("X: " + root.simX.toFixed(3) + " " + root.unitStr, fingerScreenX - 18, fingerScreenY + 42)
                                    ctx.fillStyle = root.purpleAccent
                                    ctx.fillText("R: " + root.simR.toFixed(3) + " " + root.unitStr, fingerScreenX - 18, fingerScreenY + 53)
                                }
                            }

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
                                    text: qsTr("TRAVEL ENVELOPE: X [0.00 – 24.00\"]")
                                    color: root.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("R [-0.50 – 6.00\"] · CLEARANCE SAFE")
                                    color: root.greenAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // CARD B: Ergonomic Tactile Jog Cluster & Micro-Nudge (Height: 312px)
                    // ORGANIZED MOTION CLUSTER: Symmetrical Cruciform D-Pad + Dedicated Micro-Trim Dock
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 7
                        color: root.cardBg
                        border.color: root.cardBorder
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { width: 3.5; height: 13; radius: 1.75; color: root.blueAccent }
                                Text {
                                    text: qsTr("TACTILE MOTION CLUSTER")
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    height: 20
                                    width: jogModeLabel.implicitWidth + 12
                                    radius: 4
                                    color: root.jogContinuous ? "#FEE2E2" : "#E0F2FE"
                                    border.color: root.jogContinuous ? root.redAccent : root.blueAccent
                                    border.width: 1
                                    Text {
                                        id: jogModeLabel
                                        anchors.centerIn: parent
                                        text: root.jogContinuous ? qsTr("CONTINUOUS") : (qsTr("STEP ") + root.jogStepVal.toFixed(4) + " " + root.unitStr)
                                        color: root.jogContinuous ? root.redAccent : root.blueAccent
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                            }

                            // 1. Cruceta de Jogging Limpia y Simétrica (D-Pad Centrado)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Item {
                                    anchors.centerIn: parent
                                    width: 300
                                    height: 180

                                    // Botón R+ (LIFT - Arriba)
                                    JogButton {
                                        id: btnRPlus
                                        x: 100; y: 2
                                        width: 100; height: 54
                                        axis: "R"; dir: 1; label: "R+ LIFT"
                                        iconGlyph: "▲"
                                    }

                                    // Botón X- (ADVANCE - Izquierda)
                                    JogButton {
                                        id: btnXMinus
                                        x: 2; y: 62
                                        width: 100; height: 54
                                        axis: "X"; dir: -1; label: "X- ADVANCE"
                                        iconGlyph: "◀"
                                    }

                                    // Núcleo Central de Ejes
                                    Rectangle {
                                        x: 112; y: 62
                                        width: 76; height: 54
                                        radius: 6
                                        color: root.activeDirection.length > 0 ? root.blueAccent : "#F1F5F9"
                                        border.color: root.activeDirection.length > 0 ? root.blueHover : root.cardBorder
                                        border.width: 1.5

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            Text {
                                                text: root.activeDirection.length > 0 ? root.activeDirection : "AXIS"
                                                color: root.activeDirection.length > 0 ? "white" : root.ink
                                                font.pixelSize: 13
                                                font.bold: true
                                                font.family: "Monospace"
                                                Layout.alignment: Qt.AlignHCenter
                                            }
                                            Text {
                                                text: root.activeDirection.length > 0 ? qsTr("ACTIVE") : qsTr("READY")
                                                color: root.activeDirection.length > 0 ? "#E0F2FE" : root.greenAccent
                                                font.pixelSize: 8
                                                font.bold: true
                                                Layout.alignment: Qt.AlignHCenter
                                            }
                                        }
                                    }

                                    // Botón X+ (RETRACT - Derecha)
                                    JogButton {
                                        id: btnXPlus
                                        x: 198; y: 62
                                        width: 100; height: 54
                                        axis: "X"; dir: 1; label: "X+ RETRACT"
                                        iconGlyph: "▶"
                                    }

                                    // Botón R- (LOWER - Abajo)
                                    JogButton {
                                        id: btnRMinus
                                        x: 100; y: 122
                                        width: 100; height: 54
                                        axis: "R"; dir: -1; label: "R- LOWER"
                                        iconGlyph: "▼"
                                    }
                                }
                            }

                            // 2. Barra Organizada de Micro-Ajuste Fino (Separada y Simétrica)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 6
                                color: "#F8FAFC"
                                border.color: "#E2E8F0"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 6

                                    Text {
                                        text: qsTr("MICRO-NUDGE:")
                                        color: root.textSecondary
                                        font.pixelSize: 9
                                        font.bold: true
                                        Layout.leftMargin: 4
                                    }

                                    NudgeButton { text: "-.001\" R"; onClicked: root.nudgeAxis("R", -0.001) }
                                    NudgeButton { text: "+.001\" R"; onClicked: root.nudgeAxis("R", 0.001) }

                                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: "#CBD5E1" }

                                    NudgeButton { text: "-.010\" X"; onClicked: root.nudgeAxis("X", -0.010) }
                                    NudgeButton { text: "+.010\" X"; onClicked: root.nudgeAxis("X", 0.010) }
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
                        radius: 7
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
                                Rectangle { width: 3.5; height: 13; radius: 1.75; color: root.blueAccent }
                                Text {
                                    text: qsTr("HIGH-CONTRAST DIGITAL READOUT (DRO)")
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.showMachineCoords ? qsTr("VIEW: MACHINE ABSOLUTE") : qsTr("VIEW: WORK ORIGIN")
                                    color: root.blueAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            // X-AXIS READOUT POD
                            Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                radius: 6
                                color: root.activeDirection.indexOf("X") === 0 ? "#F0F9FF" : "#F8FAFC"
                                border.color: root.activeDirection.indexOf("X") === 0 ? root.blueAccent : root.cardBorder
                                border.width: 1.5

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Axis Badge (Vivid Steel Blue)
                                    Rectangle {
                                        width: 26
                                        height: 26
                                        radius: 4
                                        color: root.blueAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: "X"
                                            color: "white"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 0
                                        Text {
                                            text: (root.showMachineCoords ? root.simMachineX : root.simX).toFixed(4)
                                            color: root.ink
                                            font.pixelSize: 22
                                            font.bold: true
                                            font.family: "Monospace"
                                        }
                                        Text {
                                            text: root.showMachineCoords ? ("WCS: " + root.simX.toFixed(4) + " " + root.unitStr) : ("MCS: " + root.simMachineX.toFixed(4) + " " + root.unitStr)
                                            color: root.textSecondary
                                            font.pixelSize: 9
                                            font.bold: true
                                            font.family: "Monospace"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Action: ZERO X
                                    Rectangle {
                                        width: 62
                                        height: 30
                                        radius: 4
                                        color: root.redAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("ZERO X")
                                            color: "white"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (root.appState) root.appState.setBackGaugeWorkPosition("X", 0)
                                                else root.simX = 0.0000
                                            }
                                        }
                                    }

                                    // Action: SET X
                                    Rectangle {
                                        width: 56
                                        height: 30
                                        radius: 4
                                        color: root.blueAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("SET X")
                                            color: "white"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.openKeyboard(true, qsTr("SET X WORK POSITION"), root.simX.toFixed(4),
                                                    function(v) { root.appState.setBackGaugeWorkPosition("X", v) })
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
                                color: root.activeDirection.indexOf("R") === 0 ? "#FAF5FF" : "#F8FAFC"
                                border.color: root.activeDirection.indexOf("R") === 0 ? root.purpleAccent : root.cardBorder
                                border.width: 1.5

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // Axis Badge (Vivid Purple)
                                    Rectangle {
                                        width: 26
                                        height: 26
                                        radius: 4
                                        color: root.purpleAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: "R"
                                            color: "white"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 0
                                        Text {
                                            text: (root.showMachineCoords ? root.simMachineR : root.simR).toFixed(4)
                                            color: root.ink
                                            font.pixelSize: 22
                                            font.bold: true
                                            font.family: "Monospace"
                                        }
                                        Text {
                                            text: root.showMachineCoords ? ("WCS: " + root.simR.toFixed(4) + " " + root.unitStr) : ("MCS: " + root.simMachineR.toFixed(4) + " " + root.unitStr)
                                            color: root.textSecondary
                                            font.pixelSize: 9
                                            font.bold: true
                                            font.family: "Monospace"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Action: ZERO R
                                    Rectangle {
                                        width: 62
                                        height: 30
                                        radius: 4
                                        color: root.redAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("ZERO R")
                                            color: "white"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (root.appState) root.appState.setBackGaugeWorkPosition("R", 0)
                                                else root.simR = 0.0000
                                            }
                                        }
                                    }

                                    // Action: SET R
                                    Rectangle {
                                        width: 56
                                        height: 30
                                        radius: 4
                                        color: root.purpleAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("SET R")
                                            color: "white"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.openKeyboard(true, qsTr("SET R WORK POSITION"), root.simR.toFixed(4),
                                                    function(v) { root.appState.setBackGaugeWorkPosition("R", v) })
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
                        radius: 7
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
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.jogContinuous ? qsTr("CONTINUOUS ACTIVE") : (root.jogStepVal.toFixed(4) + " " + root.unitStr)
                                    color: root.jogContinuous ? root.redAccent : root.blueAccent
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
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        height: 30
                                        radius: 4
                                        readonly property bool isSelected: modelData.val < 0 ? root.jogContinuous : (!root.jogContinuous && Math.abs(root.jogStepVal - modelData.val) < 0.0001)
                                        color: isSelected ? (modelData.val < 0 ? root.redAccent : root.blueAccent) : root.charcoal

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: "white"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (root.appState) {
                                                    root.appState.setBackGaugeJogStep(modelData.val < 0 ? root.jogStepVal : modelData.val, modelData.val < 0)
                                                } else if (modelData.val < 0) {
                                                    root.jogContinuous = true
                                                } else {
                                                    root.jogContinuous = false
                                                    root.jogStepVal = modelData.val
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // SECTION 2B: JOG VELOCITY & FEEDRATE (CON CAMPO EDITABLE)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Layout.topMargin: 4
                                Text {
                                    text: qsTr("JOG VELOCITY & FEEDRATE")
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }

                                // Campo editable de velocidad (100.000 IPM)
                                Rectangle {
                                    Layout.preferredWidth: 120
                                    Layout.preferredHeight: 24
                                    radius: 4
                                    color: "#FFFFFF"
                                    border.color: speedMouse.containsMouse ? root.blueAccent : root.cardBorder
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        Text {
                                            text: root.jogSpeedVal.toFixed(1)
                                            color: root.ink
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: "Monospace"
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            text: root.speedUnitStr
                                            color: root.blueAccent
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: speedMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (root.appState) {
                                                root.openKeyboard(true, qsTr("JOG VELOCITY"), root.jogSpeedVal.toFixed(3),
                                                    function(v) { root.appState.setBackGaugeJogSpeed(Number(v)) })
                                            } else {
                                                root.jogSpeedVal = root.jogSpeedVal === 100.0 ? 75.0 : 100.0
                                            }
                                        }
                                    }
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
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        height: 30
                                        radius: 4
                                        readonly property bool isSelected: Math.abs(root.jogSpeedVal - modelData.val) < 1.0
                                        color: isSelected ? (modelData.val === 100 ? root.redAccent : root.blueAccent) : root.charcoal

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: "white"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (root.appState) root.appState.setBackGaugeJogSpeed(modelData.val)
                                                else root.jogSpeedVal = modelData.val
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
                        radius: 7
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
                                Rectangle { width: 3.5; height: 13; radius: 1.75; color: root.orangeAccent }
                                Text {
                                    text: qsTr("ABSOLUTE MOVE COMMAND")
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("PRESETS: ")
                                    color: root.textSecondary
                                    font.pixelSize: 9
                                }
                                Text {
                                    text: qsTr("FLUSH · RETRACT · PARK")
                                    color: root.orangeDark
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
                                    color: "#F8FAFC"
                                    border.color: root.cardBorder
                                    border.width: 1.2

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { text: "TARGET X:"; color: root.blueAccent; font.pixelSize: 10; font.bold: true }
                                        Text {
                                            text: root.targetX.toFixed(4)
                                            color: root.ink
                                            font.pixelSize: 14
                                            font.bold: true
                                            font.family: "Monospace"
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text { text: root.unitStr; color: root.textSecondary; font.pixelSize: 9; font.bold: true }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.appState) {
                                                root.openKeyboard(true, qsTr("ENTER TARGET X"), root.targetX.toFixed(4),
                                                    function(v) { root.targetX = Number(v) })
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
                                    color: "#F8FAFC"
                                    border.color: root.cardBorder
                                    border.width: 1.2

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { text: "TARGET R:"; color: root.purpleAccent; font.pixelSize: 10; font.bold: true }
                                        Text {
                                            text: root.targetR.toFixed(4)
                                            color: root.ink
                                            font.pixelSize: 14
                                            font.bold: true
                                            font.family: "Monospace"
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text { text: root.unitStr; color: root.textSecondary; font.pixelSize: 9; font.bold: true }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.appState) {
                                                root.openKeyboard(true, qsTr("ENTER TARGET R"), root.targetR.toFixed(4),
                                                    function(v) { root.targetR = Number(v) })
                                            } else {
                                                root.targetR = root.targetR === 1.125 ? 2.500 : 1.125
                                            }
                                        }
                                    }
                                }

                                // Prominent RUN / EXECUTE Button (Vivid Safety Orange #FFA500)
                                Rectangle {
                                    width: 115
                                    height: 40
                                    radius: 5
                                    color: root.orangeAccent
                                    border.color: root.orangeDark
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("RUN MOVE ▶")
                                        color: root.ink
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
            // LIMIT SWITCHES EXCLUSIVAMENTE: X1, X2, R1, R2
            // =================================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 7
                color: root.cardBg
                border.color: root.cardBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    // Limit Switch Indicators Matrix: ÚNICAMENTE X1, X2, R1, R2
                    RowLayout {
                        spacing: 6
                        Text {
                            text: qsTr("LIMIT MATRIX:")
                            color: root.ink
                            font.pixelSize: 9
                            font.bold: true
                        }
                        LimitPill {
                            label: "X1"
                            active: root.appState ? root.appState.backGaugeLimitX1 : (root.simX <= 0.001)
                        }
                        LimitPill {
                            label: "X2"
                            active: root.appState ? root.appState.backGaugeLimitX2 : (root.simX >= 23.99)
                        }
                        LimitPill {
                            label: "R1"
                            active: root.appState ? root.appState.backGaugeLimitR1 : (root.simR <= -0.49)
                        }
                        LimitPill {
                            label: "R2"
                            active: root.appState ? root.appState.backGaugeLimitR2 : (root.simR >= 5.99)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Motion Status
                    RowLayout {
                        spacing: 6
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: root.isReady ? root.greenAccent : root.redAccent
                        }
                        Text {
                            text: root.appState ? root.appState.backGaugeStatus : (root.activeDirection.length > 0 ? qsTr("MOTION ACTIVE · ") + root.activeDirection : qsTr("READY · CLOSED LOOP SERVO"))
                            color: root.ink
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // Industrial Emergency STOP Button
                    Rectangle {
                        width: 180
                        height: 32
                        radius: 5
                        color: root.redAccent
                        border.color: Qt.darker(root.redAccent, 1.2)
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

        readonly property bool isPressed: root.activeDirection === (axis + (dir > 0 ? "+" : "-"))

        radius: 6
        color: isPressed ? root.blueAccent : (mouseArea.containsMouse ? "#3A3B3A" : root.charcoal)
        border.color: isPressed ? root.blueHover : "#475569"
        border.width: isPressed ? 2 : 1

        RowLayout {
            anchors.centerIn: parent
            spacing: 5
            Text {
                text: jogComp.iconGlyph
                color: "white"
                font.pixelSize: 14
            }
            Text {
                text: jogComp.label
                color: "white"
                font.pixelSize: 11
                font.bold: true
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.appState || root.appState.backGaugeCanOperate
            onPressed: { root.forceActiveFocus(); root.triggerJog(jogComp.axis, jogComp.dir, true) }
            onReleased: root.triggerJog(jogComp.axis, jogComp.dir, false)
            onCanceled: root.triggerJog(jogComp.axis, jogComp.dir, false)
        }
    }

    component NudgeButton: Rectangle {
        property string text: ""
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 4
        color: nudgeArea.pressed ? "#CBD5E1" : (nudgeArea.containsMouse ? "#F1F5F9" : "white")
        border.color: nudgeArea.containsMouse ? root.blueAccent : root.cardBorder
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: parent.text
            color: root.ink
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
        color: pillArea.containsMouse ? "#F1F5F9" : "#FFFFFF"
        border.color: pillArea.containsMouse ? root.blueAccent : root.cardBorder
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: parent.text
            color: root.ink
            font.pixelSize: 8
            font.bold: true
        }

        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }

    component LimitPill: Rectangle {
        property string label: ""
        property bool active: false

        height: 24
        width: 44
        radius: 5
        color: active ? root.redAccent : "#E2E8F0"
        border.color: active ? Qt.darker(root.redAccent, 1.2) : root.cardBorder
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.active ? "white" : root.textSecondary
            font.pixelSize: 11
            font.bold: true
        }
    }
}
