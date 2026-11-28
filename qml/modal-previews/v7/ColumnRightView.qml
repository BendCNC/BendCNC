import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import "../.." as Production

Item {
    id: columnRight
    objectName: "column-right ColumnRight LiveReportView SwitchControlHintView MachineStateView RamDroView LedIndicatorsView CommandedJogView DistanceToGoView UserControlView JogSpeedSettingsView RetractJogView MachineHomingView MachineAbortView KillHydraulicPowerView"
    property var appState: null
    property bool productionMode: false
    readonly property bool physicalInputsRequired: appState
        && !appState.offlineSimulationEnabled
        && appState.machineControl
        && appState.machineControl.panelJogRequiresPhysicalInputs
    signal openMeasurementRequested()

    Production.LayoutMetrics { id: metrics }

    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color charcoal: "#2B2C2B"
    readonly property color headerGrey: "#676867"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color bodyGrey: "#BFBFBF"
    readonly property color paper: "#F5F5F5"
    readonly property color ink: "#232323"
    readonly property color orange: "#FFA500"
    readonly property int gap: metrics.columnRightGap
    readonly property int pad: metrics.standardMargin
    readonly property int ramDroY: pad + metrics.columnRightPanelTopHeight + gap
    readonly property int ledY: ramDroY + metrics.columnRightRamDroHeight + gap
    readonly property int jogY: ledY + metrics.columnRightLedHeight + gap
    readonly property int topGroupHeight: jogY + metrics.columnRightJogHeight + pad
    readonly property int bottomGroupY: topGroupHeight + gap
    readonly property int bottomGroupHeight: Math.max(0, height - bottomGroupY)
    readonly property int innerWidth: width - pad * 2
    readonly property real rightGridColumnWidth: (innerWidth - gap) / 2
    readonly property real userControlColumnWidth: (innerWidth - gap * 2) / 3
    readonly property real backGaugeWidth: Math.round((innerWidth - gap) * 0.62)
    readonly property real measurementButtonWidth: innerWidth - backGaugeWidth - gap
    readonly property real ledWideWidth: (innerWidth - gap * 2) * 0.40
    readonly property real ledNarrowWidth: innerWidth - ledWideWidth * 2 - gap * 2
    readonly property real userControlButtonHeight: Math.max(0, (bottomGroupHeight - pad * 2 - metrics.columnRightUserHeaderHeight - gap * 2) / 2)

    Rectangle {
        objectName: "group group-top"
        x: 0
        y: 0
        width: parent.width
        height: topGroupHeight
        color: charcoal
        radius: metrics.panelRadius
    }

    Item {
        objectName: "panel-top"
        x: pad
        y: pad
        width: innerWidth
        height: metrics.columnRightPanelTopHeight

        Row {
            objectName: "column-right-group-header live-report-view"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text { anchors.verticalCenter: parent.verticalCenter; text: "STATUS"; color: "white"; font.bold: true; font.pixelSize: 16 }
        }

        MachineStatePanel {
            id: machineStatePanel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            maximumWidth: columnRight.physicalInputsRequired
                ? Math.max(120, (parent.width - 110) / 2 - 4)
                : parent.width
            status: appState ? appState.machineStatus : "IDLE"
        }

        SwitchControlHint {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            visible: columnRight.physicalInputsRequired
            width: visible ? 110 : 0
            height: parent.height
        }
    }

    // Refined v5 RamDroView instance
    RamDroView {
        id: ramDro
        appState: columnRight.appState
        productionMode: columnRight.productionMode
        x: pad
        y: ramDroY
        width: innerWidth
        height: metrics.columnRightRamDroHeight
    }

    LedIndicators {
        x: pad
        y: ledY
        width: innerWidth
        height: metrics.columnRightLedHeight
    }

    Row {
        id: jogRow
        objectName: "grid backgauge-and-measurements"
        x: pad
        y: jogY
        width: innerWidth
        height: metrics.columnRightJogHeight
        spacing: gap
        BackGaugePositionsPanel {
            width: backGaugeWidth
            height: parent.height
            positionAvailable: appState ? appState.backGaugePositionAvailable : false
            posX: appState ? appState.backGaugeX : 0.0000
            posR: appState ? appState.backGaugeR : 0.0000
            bgUnit: appState ? (appState.backGaugeUnit === "MILLIMETER"
                || appState.backGaugeUnit === "MM" || appState.unit === "mm" ? "mm" : "in") : "in"
            metric: appState ? appState.metricUnits === true : false
        }
        OpenMeasurementButton {
            width: measurementButtonWidth
            height: parent.height
            onClicked: {
                if (columnRight.appState) {
                    columnRight.appState.openManualMeasurement("MEASUREMENT")
                }
                columnRight.openMeasurementRequested()
            }
        }
    }

    Rectangle {
        objectName: "group group-bottom"
        x: 0
        y: bottomGroupY
        width: parent.width
        height: bottomGroupHeight
        color: charcoal
        radius: metrics.panelRadius
    }

    Production.UserControlView {
        x: pad
        y: bottomGroupY + pad
        width: innerWidth
        height: metrics.columnRightUserHeaderHeight
    }

    Row {
        objectName: "grid user-control-grid row-top"
        x: pad
        y: bottomGroupY + pad + metrics.columnRightUserHeaderHeight + gap
        width: innerWidth
        height: userControlButtonHeight
        spacing: gap
        JogSpeedPanel {
            width: userControlColumnWidth * 2 + gap
            height: parent.height
            appState: columnRight.appState
            bendSpeed: appState ? appState.bendRamSpeed : 5
            jogSpeed: appState ? appState.jogRamSpeed : 5
        }
        Column {
            width: userControlColumnWidth
            height: parent.height
            spacing: 3
            ControlButton {
                objectName: "button continuous-retract-jog"
                width: parent.width
                height: (parent.height - parent.spacing) / 2
                controlEnabled: appState ? appState.pressCanPanelJog : false
                title: "RETRACT"
                buttonColor: orange
                iconType: "arrow-up"
                iconSize: 16
                titleSize: 11
                onControlPressed: if (appState) appState.machineAction("retract-jog")
                onControlReleased: if (appState) appState.machineAction("retract-jog-release")
            }
            ControlButton {
                objectName: "button continuous-advance-jog"
                width: parent.width
                height: (parent.height - parent.spacing) / 2
                controlEnabled: appState ? appState.pressCanPanelJog : false
                title: "ADVANCE"
                buttonColor: red
                iconType: "arrow-down"
                iconSize: 16
                titleSize: 11
                onControlPressed: if (appState) appState.machineAction("advance-jog")
                onControlReleased: if (appState) appState.machineAction("advance-jog-release")
            }
        }
    }

    Row {
        objectName: "grid user-control-grid row-bottom"
        x: pad
        y: bottomGroupY + pad + metrics.columnRightUserHeaderHeight + gap + userControlButtonHeight + gap
        width: innerWidth
        height: userControlButtonHeight
        spacing: gap
        HomeControlButton {
            width: userControlColumnWidth
            height: parent.height
            appState: columnRight.appState
        }
        AbortControlButton {
            width: userControlColumnWidth
            height: parent.height
            appState: columnRight.appState
        }
        KillHydraulicsButton {
            width: userControlColumnWidth
            height: parent.height
            appState: columnRight.appState
        }
    }

    component SwitchControlHint: Item {
        id: switchHint
        objectName: "switch-control-hint-view"
        Rectangle {
            objectName: "foot-pedal-control"
            anchors.centerIn: parent
            width: 110
            height: parent.height
            radius: metrics.smallRadius
            color: "transparent"
            visible: !columnRight.physicalInputsRequired
            border.color: "#16F529"
            border.width: 2
            Row {
                anchors.centerIn: parent
                spacing: 1
                Text { objectName: "panel-input-requirement"; anchors.verticalCenter: parent.verticalCenter; width: columnRight.physicalInputsRequired ? 100 : 40; text: columnRight.physicalInputsRequired ? qsTr("PHYSICAL\nTWO-HAND\nREQUIRED") : qsTr("FOOT\nPEDAL\nCONTROL"); color: "white"; font.bold: true; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter; lineHeight: 0.82 }
                VectorIcon { visible: !columnRight.physicalInputsRequired; anchors.verticalCenter: parent.verticalCenter; type: "arrow-down"; size: 22; color: red }
                VectorIcon { visible: !columnRight.physicalInputsRequired; anchors.verticalCenter: parent.verticalCenter; type: "arrow-up"; size: 22; color: "white" }
                VectorIcon { visible: !columnRight.physicalInputsRequired; anchors.verticalCenter: parent.verticalCenter; type: "arrow-down"; size: 22; color: red }
            }
        }
    }

    component MachineStatePanel: Rectangle {
        id: statePanelRoot
        property string status: "IDLE"
        readonly property string displayStatus: status.trim().replace(/[-_\s]+/g, " ").toUpperCase()
        property real maximumWidth: Number.POSITIVE_INFINITY
        readonly property color statusColor: displayStatus === "IDLE" ? green : (displayStatus === "RUNNING" || displayStatus === "HOMING" || displayStatus === "RETRACT JOG" ? orange : red)
        objectName: "machine-state-view"
        radius: metrics.smallRadius
        color: paper

        width: Math.min(maximumWidth, statusLabel.implicitWidth + statusBadge.desiredWidth + 18)
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        Text {
            id: statusLabel
            objectName: "machine-status-label"
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Machine Status:"
            color: ink
            font.bold: true
            font.pixelSize: 12
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            width: Math.max(42, statusBadge.x - anchors.leftMargin - 4)
        }

        Rectangle {
            id: statusBadge
            objectName: "machine-state idle"
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 4
            readonly property real desiredWidth: Math.max(50, statusValueText.implicitWidth + 16)
            width: Math.min(desiredWidth, Math.max(50, parent.width - 78))
            radius: metrics.smallRadius
            color: statePanelRoot.statusColor

            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: statusValueText
                objectName: "machine-status-value"
                anchors.centerIn: parent
                text: statePanelRoot.displayStatus
                color: "white"
                font.bold: true
                font.pixelSize: 11
                fontSizeMode: Text.Fit
                minimumPixelSize: 7
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    component LedIndicators: Row {
        objectName: "led-indicators-view"
        spacing: gap

        // JOG BUTTONS PANEL
        Rectangle {
            objectName: "led-panel-jog"
            width: ledWideWidth
            height: parent.height
            color: headerGrey
            radius: metrics.panelRadius

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 5

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "JOG BUTTONS"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                    opacity: 0.95
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    width: parent.width
                    height: 48

                    JogButtonIndicator {
                        objectName: "jog-indicator-left"
                        width: (parent.width - 6) / 2
                        height: parent.height
                        label: "LEFT"
                        ledName: "left"
                        active: appState ? appState.leftSafetyJog : false
                    }

                    JogButtonIndicator {
                        objectName: "jog-indicator-right"
                        width: (parent.width - 6) / 2
                        height: parent.height
                        label: "RIGHT"
                        ledName: "right"
                        active: appState ? appState.rightSafetyJog : false
                    }
                }
            }
        }

        // FOOT PEDAL PANEL
        Rectangle {
            objectName: "led-panel-pedal"
            width: ledWideWidth
            height: parent.height
            color: headerGrey
            radius: metrics.panelRadius

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 5

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "PEDAL"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                    opacity: 0.95
                }

                PedalIndicator {
                    objectName: "pedal-indicator"
                    width: parent.width
                    height: 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: appState ? appState.physicalPedalActive : false
                }
            }
        }

        // ANTI-BIND PANEL
        Rectangle {
            objectName: "led-panel-anti-bind"
            width: ledNarrowWidth
            height: parent.height
            color: headerGrey
            radius: metrics.panelRadius

            Column {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 5

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "ANTI-BIND"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                    opacity: 0.95
                }

                AntiBindIndicator {
                    objectName: "anti-bind-indicator"
                    width: parent.width
                    height: 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: appState ? appState.antiBindSwitch : false
                }
            }
        }
    }

    component BackGaugePositionsPanel: Item {
        id: bgPositionsPanel
        objectName: "backgauge-positions-view"
        property bool positionAvailable: false
        property real posX: 0.0000
        property real posR: 0.0000
        property string bgUnit: "in"
        property bool metric: false
        function dispPos(v) {
            var n = Number(v)
            var inches = bgUnit === "mm" ? n / 25.4 : n
            return metric ? (inches * 25.4).toFixed(2) : inches.toFixed(4)
        }

        Rectangle {
            objectName: "header"
            x: 0
            y: 0
            width: 76
            height: parent.height
            color: blue
            radius: metrics.panelRadius
            Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right; width: metrics.panelRadius; color: blue }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: pad
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text { text: "BACK"; color: "white"; font.pixelSize: 13 }
                Text { text: "GAUGE"; color: "white"; font.bold: true; font.pixelSize: 13 }
            }
        }

        Rectangle {
            objectName: "body"
            x: 76
            y: 0
            width: parent.width - x
            height: parent.height
            color: bodyGrey
            radius: metrics.panelRadius
            Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left; width: metrics.panelRadius; color: bodyGrey }

            Column {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 4

                // X Axis row
                Row {
                    width: parent.width
                    height: 21
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 19
                        radius: 3
                        color: "#2D83B2"
                        Text {
                            anchors.centerIn: parent
                            text: "X"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        objectName: "backgauge-x-value"
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20 - 30 - parent.spacing * 2
                        text: bgPositionsPanel.positionAvailable
                            ? bgPositionsPanel.dispPos(bgPositionsPanel.posX) : "----"
                        color: ink
                        font.bold: true
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignRight
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        text: bgPositionsPanel.metric ? "mm" : "in"
                        color: ink
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // R Axis row
                Row {
                    width: parent.width
                    height: 21
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 19
                        radius: 3
                        color: "#475569"
                        Text {
                            anchors.centerIn: parent
                            text: "R"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        objectName: "backgauge-r-value"
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20 - 30 - parent.spacing * 2
                        text: bgPositionsPanel.positionAvailable
                            ? bgPositionsPanel.dispPos(bgPositionsPanel.posR) : "----"
                        color: ink
                        font.bold: true
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignRight
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        text: bgPositionsPanel.metric ? "mm" : "in"
                        color: ink
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }

    component OpenMeasurementButton: Rectangle {
        id: openMeasRoot
        objectName: "open-measurement-button"
        signal clicked()
        radius: metrics.panelRadius
        color: measMouse.pressed ? Qt.darker(blue, 1.18) : (measMouse.containsMouse ? Qt.lighter(blue, 1.10) : blue)
        border.color: Qt.lighter(blue, 1.20)
        border.width: 1
        scale: measMouse.pressed ? 0.97 : 1.0

        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on scale { NumberAnimation { duration: 80 } }

        Row {
            anchors.centerIn: parent
            spacing: 8

            // Caliper / Precision Gauge Vector Icon
            Canvas {
                id: caliperCanvas
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 24
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "white"
                    ctx.fillStyle = "white"
                    ctx.lineWidth = 1.8
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"

                    // Caliper main beam
                    ctx.beginPath()
                    ctx.moveTo(4, 2)
                    ctx.lineTo(4, 22)
                    ctx.stroke()

                    // Main fixed upper jaw
                    ctx.beginPath()
                    ctx.moveTo(4, 3)
                    ctx.lineTo(19, 3)
                    ctx.lineTo(19, 7)
                    ctx.lineTo(7, 7)
                    ctx.stroke()

                    // Sliding lower jaw
                    ctx.beginPath()
                    ctx.moveTo(4, 12)
                    ctx.lineTo(17, 12)
                    ctx.lineTo(17, 15)
                    ctx.lineTo(7, 15)
                    ctx.stroke()

                    // Measurement graduation ticks
                    ctx.lineWidth = 1.2
                    for (var y = 8; y <= 20; y += 3) {
                        ctx.beginPath()
                        ctx.moveTo(4, y)
                        ctx.lineTo(7, y)
                        ctx.stroke()
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "MEASURE"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                }

                Text {
                    text: "PART / CALIB"
                    color: "#D1E7F5"
                    font.bold: true
                    font.pixelSize: 9
                }
            }
        }

        MouseArea {
            id: measMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: openMeasRoot.clicked()
        }
    }

    component JogSpeedPanel: Item {
        id: speedPanel
        readonly property bool metric: appState ? appState.metricUnits === true : false
        function dispSpeed(v) { return metric ? (Number(v) * 25.4 / 60).toFixed(1) : Number(v).toFixed(1) }
        function fromSpeed(v) { return metric ? Number(v) * 60 / 25.4 : Number(v) }
        property var appState: null
        property real bendSpeed: 5
        property real jogSpeed: 5
        objectName: "jog-speed-settings-view"

        Row {
            anchors.fill: parent
            spacing: columnRight.gap

            // 1. BEND SPEED CARD (Aligned above HOME button)
            Rectangle {
                id: bendCard
                width: columnRight.userControlColumnWidth
                height: parent.height
                radius: metrics.panelRadius
                color: "#2C7FB8"
                border.color: bendMouse.containsMouse ? "white" : "transparent"
                border.width: 1
                scale: bendMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 3

                    Item {
                        width: parent.width
                        height: 14
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("BEND SPEED")
                            color: "white"
                            font.bold: true
                            font.pixelSize: 10
                            opacity: 0.95
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: speedPanel.appState && speedPanel.appState.ramSpeedCanEdit
                            height: 14
                            width: bendEditText.implicitWidth + 8
                            radius: 3
                            color: Qt.rgba(0, 0, 0, 0.25)
                            Text {
                                id: bendEditText
                                anchors.centerIn: parent
                                text: qsTr("EDIT")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 9
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: parent.height - 14 - 3 - 2 * parent.spacing
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: speedPanel.dispSpeed(speedPanel.bendSpeed)
                                color: "white"
                                font.bold: true
                                font.pixelSize: 21
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 3
                                text: speedPanel.metric ? qsTr("mm/s") : qsTr("IPM")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                                opacity: 0.9
                            }
                        }
                        TextField {
                            id: bendField
                            objectName: "bend-speed-field"
                            visible: false
                            text: speedPanel.dispSpeed(speedPanel.bendSpeed)
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.rgba(0, 0, 0, 0.22)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(0, Math.min(parent.width, parent.width * Number(speedPanel.bendSpeed) / 15.0))
                            radius: 1.5
                            color: "white"
                        }
                    }
                }

                MouseArea {
                    id: bendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: speedPanel.appState && speedPanel.appState.ramSpeedCanEdit
                    onClicked: {
                        if (speedPanel.appState) {
                            speedPanel.appState.openOnScreenKeyboard(
                                bendField, true, qsTr("BEND SPEED"),
                                function(value) {
                                    const saved = speedPanel.appState.setRamSpeed("bend", speedPanel.fromSpeed(value))
                                    bendField.text = Qt.binding(function() {
                                        return speedPanel.dispSpeed(speedPanel.bendSpeed)
                                    })
                                    if (!saved && speedPanel.appState.storageBackendReady) {
                                        speedPanel.appState.showAlarm(
                                            qsTr("SPEED SETTING FAILED"),
                                            qsTr("The previous speed was restored because the setting could not be saved."))
                                    }
                                })
                        }
                    }
                }
            }

            // 2. JOG SPEED CARD (Aligned above STOP button)
            Rectangle {
                id: jogCard
                width: columnRight.userControlColumnWidth
                height: parent.height
                radius: metrics.panelRadius
                color: "#0E9F9A"
                border.color: jogMouse.containsMouse ? "white" : "transparent"
                border.width: 1
                scale: jogMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 3

                    Item {
                        width: parent.width
                        height: 14
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("JOG SPEED")
                            color: "white"
                            font.bold: true
                            font.pixelSize: 10
                            opacity: 0.95
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: speedPanel.appState && speedPanel.appState.ramSpeedCanEdit
                            height: 14
                            width: jogEditText.implicitWidth + 8
                            radius: 3
                            color: Qt.rgba(0, 0, 0, 0.25)
                            Text {
                                id: jogEditText
                                anchors.centerIn: parent
                                text: qsTr("EDIT")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 9
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: parent.height - 14 - 3 - 2 * parent.spacing
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: speedPanel.dispSpeed(speedPanel.jogSpeed)
                                color: "white"
                                font.bold: true
                                font.pixelSize: 21
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 3
                                text: speedPanel.metric ? qsTr("mm/s") : qsTr("IPM")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                                opacity: 0.9
                            }
                        }
                        TextField {
                            id: jogField
                            objectName: "jog-speed-field"
                            visible: false
                            text: speedPanel.dispSpeed(speedPanel.jogSpeed)
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Qt.rgba(0, 0, 0, 0.22)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(0, Math.min(parent.width, parent.width * Number(speedPanel.jogSpeed) / 15.0))
                            radius: 1.5
                            color: "white"
                        }
                    }
                }

                MouseArea {
                    id: jogMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: speedPanel.appState && speedPanel.appState.ramSpeedCanEdit
                    onClicked: {
                        if (speedPanel.appState) {
                            speedPanel.appState.openOnScreenKeyboard(
                                jogField, true, qsTr("JOG SPEED"),
                                function(value) {
                                    const saved = speedPanel.appState.setRamSpeed("jog", speedPanel.fromSpeed(value))
                                    jogField.text = Qt.binding(function() {
                                        return speedPanel.dispSpeed(speedPanel.jogSpeed)
                                    })
                                    if (!saved && speedPanel.appState.storageBackendReady) {
                                        speedPanel.appState.showAlarm(
                                            qsTr("SPEED SETTING FAILED"),
                                            qsTr("The previous speed was restored because the setting could not be saved."))
                                    }
                                })
                        }
                    }
                }
            }
        }
    }

    component MeasurementBox: Rectangle {
        property string value: ""
        property string unit: ""
        radius: metrics.smallRadius
        color: "white"
        Text { anchors.right: unitLabel.left; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: value; color: ink; font.bold: true; font.pixelSize: 12 }
        Text { id: unitLabel; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: unit; color: ink; font.pixelSize: 12 }
    }

    component ControlButton: Rectangle {
        id: controlButtonRoot
        signal clicked()
        signal controlPressed()
        signal controlReleased()
        signal controlLongPressed()
        property string title: ""
        property string iconType: ""
        property color buttonColor: blue
        property int iconSize: 16
        property int titleSize: 12
        property bool controlEnabled: true
        objectName: "button"
        radius: metrics.panelRadius
        scale: buttonMouse.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }

        color: !controlEnabled ? "#52525B"
             : (buttonMouse.pressed ? Qt.darker(buttonColor, 1.20)
             : (buttonMouse.containsMouse ? Qt.lighter(buttonColor, 1.10) : buttonColor))
        border.color: controlEnabled ? Qt.lighter(buttonColor, 1.15) : "#71717A"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: title.length > 0 ? 6 : 0
            VectorIcon { anchors.verticalCenter: parent.verticalCenter; type: iconType; size: iconSize; color: "white" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: title
                color: "white"
                font.pixelSize: titleSize
                font.bold: true
                visible: title.length > 0
            }
        }

        MouseArea {
            id: buttonMouse
            objectName: "control-input"
            property bool longPressHandled: false
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: parent.controlEnabled || pressed
            pressAndHoldInterval: 850
            onPressed: {
                longPressHandled = false
                parent.controlPressed()
            }
            onReleased: parent.controlReleased()
            onCanceled: parent.controlReleased()
            onClicked: {
                if (!longPressHandled)
                    parent.clicked()
            }
            onPressAndHold: {
                longPressHandled = true
                parent.controlLongPressed()
            }
        }
    }

    component HomeControlButton: Item {
        id: homeBtn
        objectName: "button home-machine"
        property var appState: null
        readonly property bool controlEnabled: appState ? appState.pressCanHome : false
        readonly property bool isHomed: appState && appState.backGaugeHomed && (appState.offlineSimulationEnabled || (appState.machineControl && appState.machineControl.pressHomed))
        readonly property bool isHoming: appState && (appState.machineStatus === "HOMING" || appState.backGaugeStatus === "HOMING")
        readonly property bool controllerRequiresHoming: appState
            && appState.machineStatus === "STARTUP_HOMING_REQUIRED"
        readonly property bool needsHoming: controlEnabled && !isHoming
            && (controllerRequiresHoming || !isHomed)

        property real glowPulse: 0.0

        // Stepped blink instead of a 60 fps infinite animation: the press can idle
        // in STARTUP_HOMING_REQUIRED for hours and a continuous animation kept
        // the render thread at ~60% CPU (Orange Pi ~70 C).
        Timer {
            interval: 750
            repeat: true
            running: homeBtn.needsHoming
            onTriggered: homeBtn.glowPulse = homeBtn.glowPulse > 0.5 ? 0.0 : 1.0
            onRunningChanged: if (!running) homeBtn.glowPulse = 0.0
        }

        // Main button body - perfectly contained within grid cell, no external edge lines
        Rectangle {
            id: buttonBody
            anchors.fill: parent
            radius: metrics.panelRadius
            scale: homeMouse.pressed ? 0.96 : 1.0
            Behavior on scale { NumberAnimation { duration: 80 } }

            color: !homeBtn.controlEnabled ? "#52525B"
                 : homeBtn.isHoming ? orange
                 : homeBtn.isHomed ? (homeMouse.pressed ? Qt.darker(green, 1.20) : (homeMouse.containsMouse ? Qt.lighter(green, 1.10) : green))
                 : (homeMouse.pressed ? Qt.darker(blue, 1.20) : (homeMouse.containsMouse ? Qt.lighter(blue, 1.10) : blue))

            border.color: !homeBtn.controlEnabled ? "#71717A"
                        : homeBtn.isHoming ? Qt.lighter(orange, 1.20)
                        : homeBtn.isHomed ? Qt.lighter(green, 1.25)
                        : homeBtn.needsHoming ? Qt.rgba(0.25, 0.85, 1.0, 0.40 + 0.60 * homeBtn.glowPulse)
                        : Qt.lighter(blue, 1.15)
            border.width: homeBtn.needsHoming ? 2 : 1

            // Vibrant inner illumination pulse when action is required
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: homeBtn.needsHoming
                color: "#38BDF8"
                opacity: 0.10 + 0.42 * homeBtn.glowPulse
            }

            Column {
                anchors.centerIn: parent
                spacing: 5

                VectorIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    type: "home"
                    size: 26
                    color: "white"
                    // Stepped (no Behavior): an 80 ms animation per 750 ms blink
                    // step kept the press rendering ~7 fps while idle.
                    scale: homeBtn.needsHoming ? (1.0 + 0.14 * homeBtn.glowPulse) : 1.0
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: homeBtn.isHoming ? qsTr("HOMING...") : (homeBtn.isHomed ? qsTr("HOMED") : qsTr("HOME"))
                    color: "white"
                    font.bold: true
                    font.pixelSize: 14
                }
            }

            MouseArea {
                id: homeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: homeBtn.controlEnabled
                pressAndHoldInterval: 850
                property bool longPressHandled: false

                onPressed: {
                    longPressHandled = false
                }
                onClicked: {
                    if (!longPressHandled && homeBtn.appState) {
                        homeBtn.appState.machineAction("home")
                    }
                }
                onPressAndHold: {
                    longPressHandled = true
                    if (homeBtn.appState) {
                        homeBtn.appState.startCombinedHome()
                    }
                }
            }
        }
    }

    component AbortControlButton: Rectangle {
        id: abortBtn
        objectName: "button machine-abort"
        property var appState: null
        readonly property bool controlEnabled: appState ? appState.pressCanAbort : false
        radius: metrics.panelRadius
        scale: abortMouse.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }

        color: !controlEnabled ? "#52525B"
             : (abortMouse.pressed ? Qt.darker(red, 1.20) : (abortMouse.containsMouse ? Qt.lighter(red, 1.10) : red))
        border.color: controlEnabled ? Qt.lighter(red, 1.15) : "#71717A"
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 5

            VectorIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                type: "stop"
                size: 22
                color: "white"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("STOP")
                color: "white"
                font.bold: true
                font.pixelSize: 15
            }
        }

        MouseArea {
            id: abortMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: abortBtn.controlEnabled
            onClicked: {
                if (abortBtn.appState)
                    abortBtn.appState.machineAction("abort")
            }
        }
    }

    component KillHydraulicsButton: Rectangle {
        id: killBtn
        objectName: "button kill-hydraulics"
        property var appState: null
        readonly property bool controlEnabled: appState ? appState.machineConnected : false
        radius: metrics.panelRadius
        scale: killMouse.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }

        color: !controlEnabled ? "#3F3F46"
             : (killMouse.pressed ? "#0C0D10" : (killMouse.containsMouse ? "#25272D" : "#1A1B20"))
        border.color: killMouse.containsMouse ? "#EF4444" : "#383B43"
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 5

            VectorIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                type: "power"
                size: 24
                color: killBtn.controlEnabled ? "#EF4444" : "#71717A"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.parent.width - 10
                text: qsTr("KILL HYDRAULICS")
                color: "white"
                font.bold: true
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.Fit
                minimumPixelSize: 9
            }
        }

        MouseArea {
            id: killMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: killBtn.controlEnabled
            onClicked: {
                if (killBtn.appState)
                    killBtn.appState.machineAction("kill-hydraulics")
            }
        }
    }

    component JogButtonIndicator: Rectangle {
        id: jogIndRoot
        property string label: ""
        property string ledName: ""
        property bool active: false

        radius: 6
        color: active ? "#165E34" : "#2B2D31"
        border.color: active ? "#22C55E" : "#40434A"
        border.width: active ? 2 : 1
        scale: jogMouse.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 80 } }

        Text {
            anchors.centerIn: parent
            text: jogIndRoot.label
            color: jogIndRoot.active ? "#FFFFFF" : "#9CA3AF"
            font.bold: true
            font.pixelSize: 13

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            id: jogMouse
            anchors.fill: parent
            enabled: !columnRight.productionMode
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (columnRight.appState)
                    columnRight.appState.toggleLed(jogIndRoot.ledName)
            }
        }
    }

    component PedalIndicator: Rectangle {
        id: pedalIndRoot
        property bool active: false

        readonly property string pedalPath: "M 17 83 L 15 84 L 13 85 L 12 86 L 11 88 L 11 93 L 15 97 L 18 99 L 24 102 L 26 104 L 25 106 L 23 109 L 17 117 L 16 120 L 4 137 L 3 139 L 4 143 L 22 143 L 24 141 L 26 138 L 30 132 L 31 129 L 39 117 L 43 114 L 45 115 L 52 120 L 58 124 L 63 127 L 68 127 L 70 126 L 72 124 L 73 122 L 73 118 L 72 116 L 70 114 L 67 112 L 64 111 L 56 105 L 35 92 L 22 84 L 19 83 Z M 30 106 L 32 107 L 34 109 L 38 111 L 37 113 L 33 118 L 32 121 L 22 136 L 19 139 L 9 138 L 10 136 L 12 134 L 13 131 L 28 108 Z M 18 87 L 20 88 L 22 89 L 28 93 L 35 98 L 56 111 L 64 115 L 67 117 L 69 119 L 69 121 L 67 123 L 65 123 L 63 122 L 50 114 L 29 101 L 21 96 L 18 94 L 15 90 Z"

        readonly property string footPath: "M 136 8 L 134 11 L 129 19 L 119 35 L 116 40 L 116 42 L 116 45 L 116 47 L 119 51 L 117 54 L 113 58 L 109 58 L 101 61 L 97 62 L 92 63 L 83 64 L 71 64 L 61 63 L 55 62 L 49 61 L 32 56 L 27 56 L 23 57 L 21 58 L 18 60 L 15 63 L 13 66 L 13 72 L 13 74 L 14 76 L 15 77 L 16 77 L 21 81 L 35 90 L 46 97 L 62 107 L 64 108 L 66 109 L 69 110 L 72 111 L 75 111 L 84 114 L 86 115 L 89 118 L 89 121 L 90 124 L 92 126 L 95 127 L 100 131 L 113 139 L 115 140 L 118 141 L 122 141 L 124 140 L 126 139 L 136 129 L 138 126 L 140 123 L 143 118 L 146 112 L 148 107 L 148 104 L 149 101 L 157 86 L 156 84 L 154 83 L 155 81 L 158 78 L 158 77 L 161 75 L 164 77 L 168 77 L 170 76 L 172 74 L 174 71 L 176 68 L 182 57 L 190 46 L 191 44 L 191 42 L 188 39 L 182 35 L 169 26 L 147 11 L 141 7 L 139 6 Z M 71 68 L 74 69 L 74 76 L 70 77 Z M 89 67 L 93 68 L 93 72 L 92 74 L 90 75 L 88 73 Z M 52 66 L 56 67 L 55 77 L 51 76 Z M 28 61 L 29 60 L 31 60 L 32 61 L 43 63 L 47 65 L 47 77 L 48 79 L 50 81 L 52 81 L 55 81 L 57 81 L 59 79 L 60 77 L 61 67 L 65 68 L 65 76 L 66 79 L 68 81 L 70 82 L 74 82 L 78 78 L 79 68 L 84 69 L 84 75 L 86 78 L 88 79 L 93 79 L 96 76 L 97 74 L 98 66 L 100 65 L 110 62 L 113 62 L 115 63 L 121 67 L 150 85 L 151 88 L 147 95 L 145 100 L 144 106 L 142 110 L 138 118 L 135 123 L 132 127 L 123 136 L 121 136 L 119 137 L 113 134 L 100 126 L 97 124 L 94 121 L 93 119 L 93 117 L 92 115 L 88 111 L 85 110 L 79 108 L 70 106 L 62 102 L 54 97 L 21 76 L 17 72 L 17 68 L 18 66 L 21 63 L 23 62 L 25 61 Z M 124 52 L 129 55 L 147 66 L 155 71 L 156 73 L 152 78 L 152 79 L 149 80 L 147 79 L 141 75 L 139 74 L 131 69 L 123 63 L 120 62 L 118 59 L 120 56 Z M 138 13 L 140 12 L 142 13 L 147 17 L 157 23 L 179 38 L 183 41 L 186 44 L 183 49 L 177 57 L 170 68 L 169 71 L 166 73 L 162 71 L 147 62 L 129 51 L 121 46 L 120 42 L 121 40 L 124 35 L 129 27 L 134 19 L 138 14 Z"

        radius: 6
        color: active ? "#165E34" : "#2B2D31"
        border.color: active ? "#22C55E" : "#40434A"
        border.width: active ? 2 : 1
        scale: pedalMouse.pressed ? 0.97 : 1.0

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 80 } }

        Item {
            id: pedalContainer
            anchors.centerIn: parent
            width: 44
            height: 30

            // Mechanical Pedal Switch (tilts down when stepped on)
            Item {
                id: pedalPlate
                anchors.fill: parent
                rotation: pedalIndRoot.active ? -5 : 0
                transformOrigin: Item.BottomLeft
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: pedalIndRoot.active ? "#86EFAC" : "#94A3B8"
                        fillRule: ShapePath.EvenOddFill
                        Behavior on fillColor { ColorAnimation { duration: 140 } }
                        PathSvg { path: pedalIndRoot.pedalPath }
                        scale: Qt.size(0.20, 0.20)
                    }
                }
            }

            // Animated Foot (Steps down with physical spring action)
            Item {
                id: foot
                anchors.fill: parent
                y: pedalIndRoot.active ? 2.8 : 0
                x: pedalIndRoot.active ? -1.5 : 0
                rotation: pedalIndRoot.active ? -4 : 0
                transformOrigin: Item.BottomLeft

                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: pedalIndRoot.active ? "#4ADE80" : "#E2E8F0"
                        fillRule: ShapePath.EvenOddFill
                        Behavior on fillColor { ColorAnimation { duration: 140 } }
                        PathSvg { path: pedalIndRoot.footPath }
                        scale: Qt.size(0.20, 0.20)
                    }
                }
            }
        }

        MouseArea {
            id: pedalMouse
            anchors.fill: parent
            enabled: !columnRight.productionMode
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (columnRight.appState)
                    columnRight.appState.toggleLed("pedal")
            }
        }
    }

    component AntiBindIndicator: Rectangle {
        id: antiBindIndRoot
        property bool active: false

        radius: 6
        color: active ? "#4A1515" : "#2B2D31"
        border.color: active ? "#EF4444" : "#40434A"
        border.width: active ? 2 : 1
        scale: antiBindMouse.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 80 } }

        Item {
            anchors.centerIn: parent
            width: 36
            height: 32

            // Normal State: Industrial Safety Shield with Checkmark (Interlock Active & Healthy)
            Canvas {
                id: shieldCanvas
                anchors.fill: parent
                visible: !antiBindIndRoot.active
                opacity: antiBindIndRoot.active ? 0.0 : 1.0
                scale: antiBindIndRoot.active ? 0.8 : 1.0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 140 } }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.save();
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    var cx = width / 2;
                    var cy = height / 2;
                    var sw = 10;
                    var sy = cy - 2;

                    // Safety Shield Outline
                    ctx.strokeStyle = "#64748B";
                    ctx.lineWidth = 2.0;
                    ctx.beginPath();
                    ctx.moveTo(cx - sw, sy - 9);
                    ctx.lineTo(cx + sw, sy - 9);
                    ctx.lineTo(cx + sw, sy + 1);
                    ctx.quadraticCurveTo(cx + sw, sy + 10, cx, sy + 13);
                    ctx.quadraticCurveTo(cx - sw, sy + 10, cx - sw, sy + 1);
                    ctx.closePath();
                    ctx.stroke();

                    // Green Checkmark inside Shield
                    ctx.strokeStyle = "#22C55E";
                    ctx.lineWidth = 2.2;
                    ctx.beginPath();
                    ctx.moveTo(cx - 4.5, sy + 1);
                    ctx.lineTo(cx - 1, sy + 4.5);
                    ctx.lineTo(cx + 5, sy - 2);
                    ctx.stroke();

                    ctx.restore();
                }
            }

            // Fault / Trip State: Bold Red Hazard Triangle with exclamation mark
            Canvas {
                id: tripCanvas
                anchors.fill: parent
                visible: antiBindIndRoot.active
                opacity: antiBindIndRoot.active ? 1.0 : 0.0
                scale: antiBindIndRoot.active ? 1.0 : 0.8
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.save();
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    var cx = width / 2;
                    var cy = height / 2;
                    var triH = 24;
                    var triW = 28;
                    var topY = cy - triH / 2;
                    var botY = cy + triH / 2;

                    ctx.strokeStyle = "#EF4444";
                    ctx.fillStyle = "#EF4444";
                    ctx.lineWidth = 2.4;

                    // Triangle
                    ctx.beginPath();
                    ctx.moveTo(cx, topY);
                    ctx.lineTo(cx + triW / 2, botY);
                    ctx.lineTo(cx - triW / 2, botY);
                    ctx.closePath();
                    ctx.stroke();

                    // Exclamation mark
                    ctx.lineWidth = 2.4;
                    ctx.beginPath();
                    ctx.moveTo(cx, topY + 6.5);
                    ctx.lineTo(cx, cy + 3);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.arc(cx, botY - 4, 1.4, 0, Math.PI * 2);
                    ctx.fill();

                    ctx.restore();
                }
            }
        }

        MouseArea {
            id: antiBindMouse
            anchors.fill: parent
            enabled: !columnRight.productionMode
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (columnRight.appState)
                    columnRight.appState.toggleLed("anti-bind")
            }
        }
    }

    component VectorIcon: Item {
        property string type: ""
        property color color: "white"
        property int size: 16
        width: size
        height: size

        Rectangle { visible: type === "stop"; anchors.fill: parent; radius: 2; color: parent.color }
        Rectangle { visible: type === "arrow-up"; x: size * 0.42; y: size * 0.32; width: size * 0.16; height: size * 0.58; color: parent.color }
        Rectangle { visible: type === "arrow-down"; x: size * 0.42; y: size * 0.10; width: size * 0.16; height: size * 0.58; color: parent.color }
        Canvas {
            anchors.fill: parent
            visible: type === "arrow-up" || type === "arrow-down" || type === "home" || type === "power" || type === "gear"
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = color
                ctx.strokeStyle = color
                ctx.lineWidth = Math.max(2, size * 0.12)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                if (type === "arrow-up") {
                    ctx.beginPath(); ctx.moveTo(size * 0.5, size * 0.08); ctx.lineTo(size * 0.16, size * 0.42); ctx.lineTo(size * 0.37, size * 0.42); ctx.lineTo(size * 0.37, size * 0.9); ctx.lineTo(size * 0.63, size * 0.9); ctx.lineTo(size * 0.63, size * 0.42); ctx.lineTo(size * 0.84, size * 0.42); ctx.closePath(); ctx.fill()
                } else if (type === "arrow-down") {
                    ctx.beginPath(); ctx.moveTo(size * 0.5, size * 0.92); ctx.lineTo(size * 0.16, size * 0.58); ctx.lineTo(size * 0.37, size * 0.58); ctx.lineTo(size * 0.37, size * 0.1); ctx.lineTo(size * 0.63, size * 0.1); ctx.lineTo(size * 0.63, size * 0.58); ctx.lineTo(size * 0.84, size * 0.58); ctx.closePath(); ctx.fill()
                } else if (type === "home") {
                    ctx.beginPath(); ctx.moveTo(size * 0.08, size * 0.48); ctx.lineTo(size * 0.5, size * 0.12); ctx.lineTo(size * 0.92, size * 0.48); ctx.lineTo(size * 0.82, size * 0.48); ctx.lineTo(size * 0.82, size * 0.9); ctx.lineTo(size * 0.22, size * 0.9); ctx.lineTo(size * 0.22, size * 0.48); ctx.closePath(); ctx.fill()
                } else if (type === "power") {
                    var cx = size * 0.5
                    var cy = size * 0.55
                    var r = size * 0.35
                    ctx.lineWidth = Math.max(2.4, size * 0.13)
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, -Math.PI * 0.28, -Math.PI * 0.72, false)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(cx, size * 0.10)
                    ctx.lineTo(cx, cy)
                    ctx.stroke()
                } else if (type === "gear") {
                    ctx.beginPath(); ctx.arc(size * 0.5, size * 0.5, size * 0.28, 0, Math.PI * 2); ctx.stroke(); ctx.beginPath(); ctx.arc(size * 0.5, size * 0.5, size * 0.08, 0, Math.PI * 2); ctx.stroke(); for (var i = 0; i < 8; i++) { var a = i * Math.PI / 4; ctx.beginPath(); ctx.moveTo(size * 0.5 + Math.cos(a) * size * 0.34, size * 0.5 + Math.sin(a) * size * 0.34); ctx.lineTo(size * 0.5 + Math.cos(a) * size * 0.46, size * 0.5 + Math.sin(a) * size * 0.46); ctx.stroke() }
                }
            }
        }
    }
}
