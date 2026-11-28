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
    property var dataStore: null
    property bool designerInteractive: true

    width: 864
    height: 638
    focus: true

    // -------------------------------------------------------------------------
    // Offline Simulation & Interactive Preview State
    // -------------------------------------------------------------------------
    property real simX: appState && appState.backGaugeX !== undefined && isFinite(Number(appState.backGaugeX)) ? Number(appState.backGaugeX) : 4.2500
    property real simR: appState && appState.backGaugeR !== undefined && isFinite(Number(appState.backGaugeR)) ? Number(appState.backGaugeR) : 1.1250
    readonly property real unitScale: unitStr === "mm" ? 25.4 : 1.0
    readonly property real stageXMax: 17.0 * unitScale
    readonly property real stageRMin: -2.75 * unitScale
    readonly property real stageRMax: 6.0 * unitScale
    readonly property int stageDecimals: unitStr === "mm" ? 2 : 3
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
    // Active Die Resolution & Keyboard Handlers
    // -------------------------------------------------------------------------
    function activeDieInfo() {
        var dieName = ""
        var dieId = ""
        if (root.appState && root.appState.selectedBend) {
            dieName = root.appState.selectedBend.die || root.appState.selectedBend.dieName || ""
            dieId = root.appState.selectedBend.dieId || root.appState.selectedBend.die_id || ""
        }
        if (!dieName && root.appState && root.appState.programBends && root.appState.programBends.length > 0) {
            var b0 = root.appState.programBends[0]
            dieName = b0.die || b0.dieName || ""
            dieId = b0.dieId || b0.die_id || ""
        }

        var result = {
            name: dieName || "Acute 8mm 30° Die",
            vOpening: 0.315,
            angleDeg: 30.0,
            heightInch: 1.862,
            widthInch: 0.783,
            tangWidthInch: 0.500,
            tangHeightInch: 0.508
        }

        var diesList = (root.dataStore && root.dataStore.dies) ? root.dataStore.dies
            : (root.appState && root.appState.dataStore && root.appState.dataStore.dies)
            ? root.appState.dataStore.dies
            : []
        for (var i = 0; i < diesList.length; i++) {
            var d = diesList[i]
            if ((dieId && d.id === dieId) || (dieName && (d.name === dieName || d.name.indexOf(dieName) !== -1 || dieName.indexOf(d.name) !== -1))) {
                result.name = d.name
                result.vOpening = Number(d.vdieOpeningInch || 0.315)
                result.angleDeg = Number(d.dieAngleDegree || 30.0)
                result.heightInch = Number(d.heightInch || 1.862)
                var rawW = Number(d.overallWidthInch || d.overallBaseWidthInch || 0)
                result.widthInch = rawW > 0.4 ? rawW : 0.783
                result.tangWidthInch = 0.500
                result.tangHeightInch = 0.508
                break
            }
        }

        var n = result.name.toLowerCase()
        if (n.indexOf("8mm") !== -1 || n.indexOf("5623") !== -1) {
            result.vOpening = 0.315; result.angleDeg = 30.0; result.heightInch = 1.862; result.widthInch = 0.783
        } else if (n.indexOf("16.5") !== -1 || n.indexOf("9858") !== -1) {
            result.vOpening = 0.650; result.angleDeg = 30.0; result.heightInch = 1.862; result.widthInch = 1.183
        } else if ((n.indexOf("26mm") !== -1 && n.indexOf("35") !== -1) || n.indexOf("2285") !== -1) {
            result.vOpening = 1.024; result.angleDeg = 35.0; result.heightInch = 3.498; result.widthInch = 2.905
        } else if (n.indexOf("26mm") !== -1 || n.indexOf("9355") !== -1) {
            result.vOpening = 1.024; result.angleDeg = 30.0; result.heightInch = 1.865; result.widthInch = 1.767
        } else if (n.indexOf("4 way") !== -1 || n.indexOf("4-way") !== -1 || n.indexOf("4387") !== -1) {
            result.vOpening = 0.866; result.angleDeg = 85.0; result.heightInch = 2.362; result.widthInch = 2.362
        }
        return result
    }

    // Hidden text target required by AppState.openOnScreenKeyboard().
    TextInput { id: keyboardProxy; visible: false; width: 0; height: 0 }

    function openKeyboard(numeric, title, initial, commit) {
        if (!appState || typeof appState.openOnScreenKeyboard !== "function")
            return false
        keyboardProxy.text = initial === undefined || initial === null ? "" : String(initial)
        return appState.openOnScreenKeyboard(keyboardProxy, numeric, title, commit, null, true)
    }

    function cleanDieTitle(raw) {
        if (!raw) return "Acute 26mm 30° Die"
        return String(raw).replace(/\s*\[.*?\]\s*/g, "").replace(/\bDie\s+30°\s+Die\b/g, "30° Die").trim()
    }

    function activePartLengthIn() {
        if (root.appState && root.appState.selectedBend) {
            var bend = root.appState.selectedBend
            var rawLen = bend.length || bend.partLength || bend.flangeLength || bend.width || bend.sheetLength
            if (rawLen && isFinite(Number(rawLen)) && Number(rawLen) > 0)
                return Number(rawLen)
            var bx = Math.abs(Number(bend.x || 0))
            if (bx > 0.1) return Math.max(5.5, bx + 3.5)
        }
        return 6.0
    }

    function activeFlangeLengthIn() {
        if (root.appState && root.appState.selectedBend) {
            var bx = Math.abs(Number(root.appState.selectedBend.x || 0))
            if (bx > 0.05 && bx < 16.5) return bx
        }
        return Math.min(2.0, root.activePartLengthIn() / 2)
    }

    function activeSheetThicknessIn() {
        if (root.appState && root.appState.selectedBend) {
            var t = Number(root.appState.selectedBend.thickness || 0)
            if (t > 0.01 && t < 0.5) return t
        }
        return 0.060
    }

    function profileLabel(system) {
        if (appState && appState.backGaugeCoordinateDisplayName) {
            var name = appState.backGaugeCoordinateDisplayName(system)
            if (name && name !== system)
                return name
        }
        return profileNames[system] || system
    }

    function triggerJog(axis, dir, pressed) {
        if (pressed) {
            if (!appState) root.activeDirection = axis + (dir > 0 ? "+" : "-")
            if (appState) {
                appState.beginBackGaugeJog(axis, dir)
            } else if (designerInteractive) {
                var step = jogContinuous ? 0.05 : jogStepVal
                if (axis === "X") simX = Math.max(0, Math.min(17.0, simX + dir * step))
                if (axis === "R") simR = Math.max(-2.75, Math.min(6.0, simR + dir * step))
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

                    // Profile / Coordinate System Selector Dropdown + Rename Action
                    RowLayout {
                        spacing: 4
                        Layout.preferredWidth: 205
                        height: 32

                        ComboBox {
                            id: profileCombo
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            model: root.appState ? root.appState.backGaugeCoordinateSystems : ["G54", "G55", "G56", "G57", "G58", "G59"]
                            currentIndex: model ? model.indexOf(root.selectedProfile) : 0

                            onActivated: function(index) {
                                var selected = model[index]
                                if (root.appState && root.appState.selectBackGaugeCoordinateSystem) {
                                    root.appState.selectBackGaugeCoordinateSystem(selected)
                                } else {
                                    root.selectedProfile = selected
                                }
                            }

                            displayText: root.profileLabel(root.selectedProfile)

                            background: Rectangle {
                                implicitWidth: 165
                                implicitHeight: 32
                                radius: 5
                                color: "#FFFFFF"
                                border.color: profileCombo.popup.visible ? root.blueAccent : "#CBD5E1"
                                border.width: profileCombo.popup.visible ? 2 : 1
                            }

                            contentItem: Text {
                                leftPadding: 8
                                rightPadding: 16
                                text: profileCombo.displayText
                                font.pixelSize: 10
                                font.bold: true
                                color: root.ink
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                            indicator: Canvas {
                                id: comboIndicator
                                x: profileCombo.width - width - 8
                                y: (profileCombo.height - height) / 2
                                width: 8
                                height: 5
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.fillStyle = root.textSecondary
                                    ctx.beginPath()
                                    ctx.moveTo(0, 0)
                                    ctx.lineTo(width, 0)
                                    ctx.lineTo(width / 2, height)
                                    ctx.closePath()
                                    ctx.fill()
                                }
                            }

                            popup: Popup {
                                y: profileCombo.height + 2
                                width: profileCombo.width
                                implicitHeight: contentItem.implicitHeight + 4
                                padding: 2
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: Math.min(220, contentHeight)
                                    model: profileCombo.popup.visible ? profileCombo.delegateModel : null
                                    currentIndex: profileCombo.highlightedIndex
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                background: Rectangle {
                                    radius: 6
                                    color: "#FFFFFF"
                                    border.color: "#94A3B8"
                                    border.width: 1
                                }
                            }

                            delegate: ItemDelegate {
                                id: itemDel
                                required property var modelData
                                required property int index
                                width: profileCombo.width - 4
                                height: 30
                                highlighted: profileCombo.highlightedIndex === index
                                contentItem: Text {
                                    text: root.profileLabel(modelData)
                                    color: (root.selectedProfile === modelData) ? root.blueAccent : root.ink
                                    font.pixelSize: 10
                                    font.bold: root.selectedProfile === modelData
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle {
                                    color: itemDel.highlighted ? "#F1F5F9" : "transparent"
                                    radius: 4
                                }
                            }
                        }

                        // Quick Rename Button
                        Rectangle {
                            id: renameBtn
                            width: 32
                            height: 32
                            radius: 5
                            color: renameMa.containsPress ? "#E2E8F0" : (renameMa.containsMouse ? "#F1F5F9" : "#FFFFFF")
                            border.color: renameMa.containsMouse ? root.blueAccent : "#CBD5E1"
                            border.width: 1

                            Canvas {
                                id: pencilIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                antialiasing: true
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    var strokeCol = renameMa.containsMouse ? root.blueAccent : "#475569"
                                    ctx.strokeStyle = strokeCol
                                    ctx.fillStyle = strokeCol
                                    ctx.lineWidth = 1.3
                                    ctx.lineJoin = "round"
                                    ctx.lineCap = "round"

                                    // Main pencil shaft angled at 45 deg
                                    ctx.beginPath()
                                    ctx.moveTo(3.5, 12.5)
                                    ctx.lineTo(10.5, 5.5)
                                    ctx.lineTo(12.5, 7.5)
                                    ctx.lineTo(5.5, 14.5)
                                    ctx.closePath()
                                    ctx.stroke()

                                    // Pencil sharp tip
                                    ctx.beginPath()
                                    ctx.moveTo(3.5, 12.5)
                                    ctx.lineTo(1.5, 14.5)
                                    ctx.lineTo(5.5, 14.5)
                                    ctx.closePath()
                                    ctx.fill()

                                    // Top eraser / cap
                                    ctx.beginPath()
                                    ctx.moveTo(10.5, 5.5)
                                    ctx.lineTo(12.5, 3.5)
                                    ctx.lineTo(14.5, 5.5)
                                    ctx.lineTo(12.5, 7.5)
                                    ctx.closePath()
                                    ctx.stroke()
                                }
                            }

                            MouseArea {
                                id: renameMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: pencilIcon.requestPaint()
                                onExited: pencilIcon.requestPaint()
                                onPressed: pencilIcon.requestPaint()
                                onReleased: pencilIcon.requestPaint()
                                onClicked: {
                                    var currentName = root.profileLabel(root.selectedProfile)
                                    root.openKeyboard(false, qsTr("RENAME STOP PROFILE"), currentName, function(val) {
                                        if (val && val.trim().length > 0) {
                                            var trimmed = val.trim()
                                            var updated = Object.assign({}, root.profileNames)
                                            updated[root.selectedProfile] = trimmed
                                            root.profileNames = updated
                                            if (root.appState && root.appState.renameBackGaugeCoordinateSystem) {
                                                root.appState.renameBackGaugeCoordinateSystem(trimmed)
                                            }
                                        }
                                    })
                                }
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
                                Text {
                                    text: qsTr("2D PROFILE · MACHINE VIEW (RIGHT)")
                                    color: root.ink
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    readonly property var activeDie: root.activeDieInfo()
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    text: qsTr("ACTIVE DIE: %1 · V=%2\"").arg(root.cleanDieTitle(activeDie.name)).arg(activeDie.vOpening.toFixed(3))
                                    color: root.blueAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.family: "Courier New"
                                }
                            }

                            // 2D Canvas Stage (Clean Technical Blueprint Style)
                            // Viewed from the RIGHT side of the press brake:
                            // Active lower die on the LEFT (Bend Line / datum at center of die).
                            // Backgauge finger on the RIGHT (approaches the die from the back, moving left).
                            // Workpiece rests on the die top bed, gauging against the finger stop face.
                            Canvas {
                                id: stageCanvas
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

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

                                    // Unified Physical Scale (exact 1:1 proportion between Finger, Die, and Workpiece)
                                    var die = root.activeDieInfo()
                                    var scalePx = 20.0

                                    // Bending Reference Datum Line (X = 0, center of die)
                                    // In RIGHT VIEW: Die / Bend Line is on the LEFT side of the machine.
                                    var datumX = Math.round(w * 0.22)
                                    var datumY = Math.round(h * 0.63)

                                    // Real Die Dimensions (canonical DXF: width=0.783", height=1.862" working height excluding tang, V=0.315", angle=30°)
                                    var dieW = (die.widthInch || 0.783) * scalePx
                                    var dieHalfW = dieW / 2
                                    var dieH = (die.heightInch || 1.862) * scalePx
                                    var halfV = ((die.vOpening || 0.315) * scalePx) / 2
                                    var vAngleRad = (((die.angleDeg || 30.0) / 2) * Math.PI) / 180
                                    var vDepthPx = Math.max(6, Math.min(dieH * 0.45, halfV / Math.tan(vAngleRad)))
                                    var dieLeft = datumX - dieHalfW
                                    var dieRight = datumX + dieHalfW
                                    var tableY = datumY + dieH
                                    var tangW = (die.tangWidthInch || 0.500) * scalePx
                                    var tangHalfW = tangW / 2
                                    var tangH = Math.min(12, (die.tangHeightInch || 0.508) * scalePx)

                                    // Machine Table / Bed (supports the die block from front bed to die holder)
                                    ctx.fillStyle = "#E2E8F0"
                                    ctx.fillRect(8, tableY, (dieRight - 8) + 16, h - tableY)
                                    ctx.strokeStyle = "#94A3B8"
                                    ctx.lineWidth = 1.2
                                    ctx.beginPath()
                                    ctx.moveTo(8, tableY)
                                    ctx.lineTo(dieRight + 18, tableY)
                                    ctx.stroke()

                                    // Draw Active Lower Die Silhouette (Exact DXF geometry with shoulder chamfers, V-groove & tang)
                                    ctx.fillStyle = "#3E4C5E"
                                    ctx.strokeStyle = "#1E293B"
                                    ctx.lineWidth = 1.5
                                    ctx.beginPath()
                                    // Top left corner
                                    ctx.moveTo(dieLeft, datumY + 2)
                                    ctx.lineTo(dieLeft + 2, datumY)
                                    // V-groove rim left
                                    ctx.lineTo(datumX - halfV, datumY)
                                    // V-groove bottom vertex
                                    ctx.lineTo(datumX, datumY + vDepthPx)
                                    // V-groove rim right
                                    ctx.lineTo(datumX + halfV, datumY)
                                    // Top right shoulder
                                    ctx.lineTo(dieRight - 2, datumY)
                                    ctx.lineTo(dieRight, datumY + 2)
                                    // Right body side down to table
                                    ctx.lineTo(dieRight, tableY)
                                    // Tang right step-in
                                    ctx.lineTo(datumX + tangHalfW, tableY)
                                    ctx.lineTo(datumX + tangHalfW, tableY + tangH)
                                    // Tang bottom
                                    ctx.lineTo(datumX - tangHalfW, tableY + tangH)
                                    // Tang left step-out
                                    ctx.lineTo(datumX - tangHalfW, tableY)
                                    ctx.lineTo(dieLeft, tableY)
                                    ctx.closePath()
                                    ctx.fill()
                                    ctx.stroke()

                                    // Subtle V-groove pocket shadow
                                    ctx.fillStyle = "#1E293B"
                                    ctx.beginPath()
                                    ctx.moveTo(datumX - halfV, datumY)
                                    ctx.lineTo(datumX, datumY + vDepthPx)
                                    ctx.lineTo(datumX + halfV, datumY)
                                    ctx.closePath()
                                    ctx.fill()

                                    // Die Centerline (Vivid Crimson Dashed Line = BEND LINE)
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
                                    ctx.textAlign = "center"
                                    ctx.fillText("BEND LINE", datumX, 12)
                                    ctx.textAlign = "left"

                                    // Sheet Rest Reference Plane (Front operator bed support)
                                    ctx.strokeStyle = "#94A3B8"
                                    ctx.lineWidth = 1.2
                                    ctx.beginPath()
                                    ctx.moveTo(8, datumY)
                                    ctx.lineTo(dieLeft, datumY)
                                    ctx.stroke()

                                    // Fixed Workpiece (Sheet Metal with physical proportions, non-stretching)
                                    var partLenIn = root.activePartLengthIn()
                                    var flangeIn = root.activeFlangeLengthIn()
                                    var sheetThickIn = root.activeSheetThicknessIn()

                                    var programmedFlangePx = Math.max(16, Math.round(flangeIn * scalePx))
                                    var partLenPx = Math.max(programmedFlangePx + 24, Math.round(partLenIn * scalePx))
                                    var sheetTPx = Math.max(3, Math.min(6, Math.round(sheetThickIn * scalePx * 2.2)))

                                    // Sheet rests on the die at datumY.
                                    // Bend line is at datumX.
                                    // Rear flange extends to the RIGHT towards the backgauge:
                                    var sheetRight = datumX + programmedFlangePx
                                    var sheetLeft = Math.max(8, sheetRight - partLenPx)

                                    ctx.fillStyle = "#CBD5E1"
                                    ctx.strokeStyle = "#475569"
                                    ctx.lineWidth = 1.2
                                    ctx.fillRect(sheetLeft, datumY - sheetTPx, sheetRight - sheetLeft, sheetTPx)
                                    ctx.strokeRect(sheetLeft, datumY - sheetTPx, sheetRight - sheetLeft, sheetTPx)

                                    // Finger DXF Canonical Dimensions (Finger Side.dxf: 4.00" length, 0.75" body height, 0.375" nose shelf)
                                    var fLen = 4.00 * scalePx
                                    var minStopX = dieRight + 4
                                    var maxStopX = w - fLen - 12
                                    var usableW = Math.max(20, maxStopX - minStopX)

                                    var xClamped = Math.min(root.stageXMax, Math.max(0.0, root.simX))
                                    var rClamped = Math.min(root.stageRMax, Math.max(root.stageRMin, root.simR))

                                    // In RIGHT VIEW:
                                    // Travel mapping: at simX = 0, finger stop face is at minStopX (closest to die on left).
                                    // Retracting (X+ RETRACT) moves finger to the RIGHT away from die.
                                    // Advancing (X- ADVANCE) moves finger to the LEFT towards die.
                                    var stopX = minStopX + (xClamped / root.stageXMax) * usableW

                                    // Physical 1:1 R elevation travel:
                                    // 1.0 inch of R movement = scalePx pixels in exact 1:1 proportion with die and finger.
                                    // R = 0 aligns finger contact shelf with die top surface (datumY).
                                    // R = -die.heightInch (-1.862 in) lowers finger shelf EXACTLY to table surface (datumY + dieH).
                                    var rPx = (rClamped <= 0)
                                        ? (rClamped * scalePx)
                                        : Math.min(datumY - 16, rClamped * scalePx)
                                    var baseY = datumY - rPx

                                    // Finger DXF Side Profile Silhouette (Pointing LEFT towards the die):
                                    // dx = 0 is at stopX (pointing left); dx increases to the right towards the back.
                                    function fpx(dx) { return stopX + dx * scalePx }
                                    function fpy(dy) { return baseY - dy * scalePx }

                                    ctx.fillStyle = root.blueAccent
                                    ctx.strokeStyle = "#1E75A6"
                                    ctx.lineWidth = 1.5
                                    ctx.beginPath()
                                    // Start at front stop face bottom corner
                                    ctx.moveTo(fpx(0.00), fpy(0.00))
                                    // Up front stop face
                                    ctx.lineTo(fpx(0.00), fpy(0.375))
                                    // Along nose shelf to the right
                                    ctx.lineTo(fpx(1.00), fpy(0.375))
                                    // Step up to main body
                                    ctx.lineTo(fpx(1.00), fpy(0.750))
                                    // Along top edge to the right
                                    ctx.lineTo(fpx(3.625), fpy(0.750))
                                    // Rear circular cap (center (fpx(3.625), fpy(0.375)), radius 0.375")
                                    ctx.arc(fpx(3.625), fpy(0.375), 0.375 * scalePx, 1.5 * Math.PI, 0.5 * Math.PI, false)
                                    // Flat bottom back to the front stop face
                                    ctx.lineTo(fpx(0.00), fpy(0.00))
                                    ctx.closePath()
                                    ctx.fill()
                                    ctx.stroke()

                                    // Mounting Hole: center (fpx(3.625), fpy(0.375)), radius = 0.15625" (5/16" dia)
                                    ctx.fillStyle = "#F1F5F9"
                                    ctx.strokeStyle = "#1E75A6"
                                    ctx.lineWidth = 1.2
                                    ctx.beginPath()
                                    ctx.arc(fpx(3.625), fpy(0.375), 0.15625 * scalePx, 0, 2 * Math.PI)
                                    ctx.fill()
                                    ctx.stroke()

                                    // Active Contact Point Highlight (Orange Bead in contact, subtle locator when clear)
                                    var inContact = Math.abs(stopX - sheetRight) < 3.5
                                    ctx.fillStyle = inContact ? root.orangeAccent : "#94A3B8"
                                    ctx.beginPath()
                                    if (root.selectedProfile === "G55" || root.selectedProfile === "G56") {
                                        ctx.arc(fpx(1.00), fpy(0.375), 3.5, 0, 2 * Math.PI)
                                    } else {
                                        ctx.arc(fpx(0.00), fpy(0.00), 3.5, 0, 2 * Math.PI)
                                    }
                                    ctx.fill()

                                    // X Dimension Line from Die Datum (Bend Line) to Finger Stop Face
                                    var dimY = datumY - sheetTPx - 16
                                    ctx.strokeStyle = root.ink
                                    ctx.lineWidth = 1
                                    ctx.beginPath()
                                    ctx.moveTo(datumX, dimY)
                                    ctx.lineTo(stopX, dimY)
                                    ctx.moveTo(datumX, dimY - 4); ctx.lineTo(datumX, dimY + 4)
                                    ctx.moveTo(stopX, dimY - 4); ctx.lineTo(stopX, dimY + 4)
                                    ctx.stroke()

                                    // Coordinate Tags
                                    ctx.font = "bold 9px sans-serif"
                                    var xText = "X: " + root.simX.toFixed(root.stageDecimals) + " " + root.unitStr
                                    var rText = "R: " + root.simR.toFixed(root.stageDecimals) + " " + root.unitStr
                                    var midX = (datumX + stopX) / 2
                                    var textX = (stopX - datumX < 50) ? (stopX + 35) : midX
                                    ctx.fillStyle = root.ink
                                    ctx.textAlign = "center"
                                    ctx.fillText(xText, textX, dimY - 3)

                                    // R elevation label pinned in upper-left corner of blueprint
                                    ctx.fillStyle = root.purpleAccent
                                    ctx.textAlign = "left"
                                    ctx.fillText(rText, 14, 20)
                                }
                            }

                            Connections {
                                target: root
                                function onSimXChanged() { stageCanvas.requestPaint() }
                                function onSimRChanged() { stageCanvas.requestPaint() }
                                function onUnitStrChanged() { stageCanvas.requestPaint() }
                                function onSelectedProfileChanged() { stageCanvas.requestPaint() }
                            }

                            Connections {
                                target: root.appState ? root.appState : null
                                function onSelectedBendChanged() { stageCanvas.requestPaint() }
                                function onSelectedRunBendChanged() { stageCanvas.requestPaint() }
                            }

                            // Bottom travel envelope status bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: qsTr("TRAVEL ENVELOPE: X [0 – %1 %2]").arg(root.stageXMax.toFixed(root.unitStr === "mm" ? 0 : 2)).arg(root.unitStr)
                                    color: root.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                Item { Layout.preferredWidth: 4 }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    readonly property bool inEnvelope: root.simX >= 0 && root.simX <= root.stageXMax && root.simR >= root.stageRMin && root.simR <= root.stageRMax
                                    text: qsTr("R [%1 – %2 %3] · %4").arg(root.stageRMin.toFixed(root.unitStr === "mm" ? 1 : 2)).arg(root.stageRMax.toFixed(root.unitStr === "mm" ? 1 : 2)).arg(root.unitStr).arg(inEnvelope ? qsTr("CLEARANCE SAFE") : qsTr("OUT OF ENVELOPE"))
                                    color: inEnvelope ? root.greenAccent : root.redAccent
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
                                Text {
                                    text: qsTr("POSITION SETUP")
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
                            text: qsTr("Limits:")
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
