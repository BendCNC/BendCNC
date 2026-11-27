import QtQuick
import "../.." as Production

Item {
    id: root
    objectName: "ram-dro-view header body panel-load main-axis panel-home-position axis-y-1 axis-y-2 axis-y-diff panel-total-load panel-live-ram-velocity value-box value-row"

    // Operational channels are independent controller telemetry
    property var appState: null
    readonly property bool metric: appState ? appState.metricUnits === true : false
    function axisText(v) { return metric ? (Number(v) * 25.4).toFixed(2) : Number(v).toFixed(4) }
    property bool productionMode: false
    readonly property bool telemetryAvailable: appState
        ? (appState.offlineSimulationEnabled || appState.independentRamTelemetryAvailable) : false
    readonly property real ramCurrent: appState
        ? (appState.independentRamTelemetryAvailable
            ? (appState.ramPositionY1 + appState.ramPositionY2) / 2.0
            : appState.ramPosition) : -0.05
    readonly property bool measuredVelocityAvailable: appState
        ? appState.measuredRamVelocityAvailable : false
    readonly property bool motorRpmAvailable: appState
        ? (appState.offlineSimulationEnabled || appState.motorRpmAvailable) : false
    readonly property real ramVelocity: measuredVelocityAvailable
        ? appState.measuredRamVelocity : 0
    readonly property real ramTotalLoad: appState ? appState.liveTonnage : 0
    property real displayedRamCurrent: ramCurrent
    // Quantized to display resolution: sub-resolution telemetry noise must not
    // restart the SmoothedAnimations below (each restart forces full-window
    // scene-graph frames on the press while idle).
    property real displayedRamVelocity: Math.round(ramVelocity * 10) / 10
    property real displayedRamTotalLoad: Math.round(ramTotalLoad * 20) / 20
    property real axisLoadCapacity: 12.5
    property bool animationsEnabled: true

    Behavior on displayedRamVelocity {
        enabled: root.animationsEnabled && root.visible
        SmoothedAnimation { duration: 220; velocity: -1; maximumEasingTime: 90 }
    }
    Behavior on displayedRamTotalLoad {
        enabled: root.animationsEnabled && root.visible
        SmoothedAnimation { duration: 260; velocity: -1; maximumEasingTime: 110 }
    }

    Production.LayoutMetrics { id: metrics }

    // Initial Original Color Palette Restored
    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color purple: "#800080"
    readonly property color teal: "#009E9E"
    readonly property color orange: "#FFA500"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color ink: "#232323"
    readonly property color muted: "#60646C"

    readonly property int gap: metrics.ramDroBodyGap
    readonly property int inset: metrics.standardMargin
    readonly property int sideWidth: metrics.ramDroLoadPanelWidth
    readonly property int bodyTop: metrics.ramDroHeaderHeight
    readonly property int bodyHeight: height - metrics.ramDroHeaderHeight
    readonly property int centerX: inset + sideWidth + gap
    readonly property int centerWidth: root.width - (inset * 2) - (sideWidth * 2) - (gap * 2)
    readonly property int rowY: bodyTop + inset
    readonly property int mainHeight: metrics.ramDroMainAxisHeight
    readonly property int secondaryHeight: metrics.ramDroSecondaryAxisHeight
    readonly property int smallHeight: metrics.ramDroSmallPanelHeight
    readonly property int contentHeight: mainHeight + secondaryHeight + smallHeight + gap * 2

    // Simulated / live positions
    readonly property real y1Position: appState && !appState.offlineSimulationEnabled
        ? appState.ramPositionY1 : (root.productionMode
            ? root.displayedRamCurrent : root.displayedRamCurrent + 0.0004)
    readonly property real y2Position: appState && !appState.offlineSimulationEnabled
        ? appState.ramPositionY2 : (root.productionMode
            ? root.displayedRamCurrent : root.displayedRamCurrent - 0.0004)
    readonly property real deltaPosition: Math.abs(y1Position - y2Position)

    // Commanded Position & Distance To Go
    readonly property real commandedPosition: appState && appState.commandedJogPosition !== undefined
        ? Number(appState.commandedJogPosition)
        : -0.0500
    readonly property real distanceToGo: appState && appState.distanceToGo !== undefined
        ? Number(appState.distanceToGo)
        : 0.0000

    readonly property real y1Load: appState && !appState.offlineSimulationEnabled
        ? appState.ramLoadY1 : (root.productionMode
            ? root.displayedRamTotalLoad / 2
            : Math.max(0.52, root.displayedRamTotalLoad * 0.52))
    readonly property real y2Load: appState && !appState.offlineSimulationEnabled
        ? appState.ramLoadY2 : (root.productionMode
            ? root.displayedRamTotalLoad / 2
            : Math.max(0.48, root.displayedRamTotalLoad * 0.48))

    // RPM Telemetry: supports up to 4 digits (+: ascending green, -: descending red)
    readonly property real liveRpmY1: appState && appState.motorRpmAvailable
        ? Number(appState.motorRpmY1)
        : (!root.productionMode && appState && appState.offlineSimulationEnabled
            ? (Math.abs(root.displayedRamVelocity) > 0.05
                ? root.displayedRamVelocity * 600.0
                : 1200.0) // 4-digit demo ascending (+1200) in preview
            : 0)

    readonly property real liveRpmY2: appState && appState.motorRpmAvailable
        ? Number(appState.motorRpmY2)
        : (!root.productionMode && appState && appState.offlineSimulationEnabled
            ? (Math.abs(root.displayedRamVelocity) > 0.05
                ? root.displayedRamVelocity * 600.0
                : -1200.0) // 4-digit demo descending (-1200) in preview
            : 0)

    // =========================================================================
    // HEADER BANNER (Original Red)
    // =========================================================================
    Rectangle {
        objectName: "header"
        x: 0
        y: 0
        width: parent.width
        height: metrics.ramDroHeaderHeight
        color: root.red
        radius: metrics.panelRadius
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: metrics.panelRadius; color: root.red }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: inset + 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text { text: "RAM"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont }
            Text { text: "POSITION"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont; font.bold: true }
            Text { text: "&"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont }
            Text { text: "LOAD"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont; font.bold: true }
        }

        // Quiet telemetry status indicator
        Row {
            anchors.right: parent.right
            anchors.rightMargin: inset + 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: root.telemetryAvailable ? "#4ADE80" : "#F87171"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.telemetryAvailable ? "LIVE" : "OFFLINE"
                color: "white"
                font.bold: true
                font.pixelSize: 11
                opacity: 0.95
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // =========================================================================
    // BODY CONTAINER BACKDROP (Original Light Grey)
    // =========================================================================
    Rectangle {
        objectName: "body"
        x: 0
        y: bodyTop
        width: parent.width
        height: bodyHeight
        color: root.lightGrey
        radius: metrics.panelRadius
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: metrics.panelRadius; color: root.lightGrey }
    }

    // =========================================================================
    // LEFT & RIGHT LOAD TOWERS (No Y1 / Y2 label, 4-digit RPM at bottom)
    // =========================================================================
    LoadTower {
        objectName: "panel-load y1-load"
        x: inset
        y: rowY
        width: sideWidth
        height: contentHeight
        loadValue: root.y1Load
        rpmValue: root.liveRpmY1
    }

    LoadTower {
        objectName: "panel-load y2-load"
        x: root.width - inset - sideWidth
        y: rowY
        width: sideWidth
        height: contentHeight
        loadValue: root.y2Load
        rpmValue: root.liveRpmY2
    }

    // =========================================================================
    // MAIN AXIS DIGITAL READOUT (Original Green)
    // =========================================================================
    Rectangle {
        objectName: "main-axis"
        x: centerX
        y: rowY
        width: centerWidth
        height: mainHeight
        color: root.green
        radius: metrics.smallRadius

        Column {
            anchors.fill: parent
            anchors.margins: inset
            spacing: 2

            // Header line: Title on left, Home indicator on right
            Item {
                width: parent.width
                height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CURRENT"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 15
                }

                Row {
                    id: homeRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "HOME POSITION"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 13
                        opacity: 0.95
                    }

                    HomeIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 15
                        color: "white"
                    }
                }
            }

            // Main readout body: Hero CURRENT on left, COMMANDED & DIST TO GO on right
            Item {
                width: parent.width
                height: parent.height - 24

                // Primary Hero DRO
                Row {
                    id: currentValue
                    objectName: "current-value"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - auxiliaryReadouts.width - 8)
                    spacing: 6

                    Text {
                        objectName: "current-value-number"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - currentUnit.width - parent.spacing)
                        height: 43
                        verticalAlignment: Text.AlignVCenter
                        text: root.telemetryAvailable ? root.axisText(root.displayedRamCurrent) : "----"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 35
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 23
                    }

                    Text {
                        id: currentUnit
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 5
                        text: root.metric ? "mm" : "in"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 15
                        opacity: 0.9
                    }
                }

                // Precision Aux Readouts (Commanded & Distance To Go)
                Rectangle {
                    id: auxiliaryReadouts
                    objectName: "precision-aux-readouts"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 144
                    height: 44
                    radius: metrics.smallRadius
                    color: Qt.rgba(0, 0, 0, 0.16)

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        spacing: 0

                        // Commanded Position
                        Item {
                            width: parent.width
                            height: 18

                            Text {
                                objectName: "commanded-label"
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - commandedValue.width - 3)
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: "COMMANDED"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 9
                                fontSizeMode: Text.Fit
                                minimumPixelSize: 7
                                opacity: 0.85
                            }

                            Row {
                                id: commandedValue
                                objectName: "commanded-value"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    text: root.telemetryAvailable ? root.axisText(root.commandedPosition) : "----"
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: root.metric ? "mm" : "in"
                                    color: "white"
                                    font.pixelSize: 10
                                    opacity: 0.85
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Subtle flat separator
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: "white"
                            opacity: 0.12
                        }

                        // Distance To Go
                        Item {
                            width: parent.width
                            height: 18

                            Text {
                                objectName: "distance-to-go-label"
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - distanceToGoValue.width - 3)
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: "DIST TO GO"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 9
                                fontSizeMode: Text.Fit
                                minimumPixelSize: 7
                                opacity: 0.85
                            }

                            Row {
                                id: distanceToGoValue
                                objectName: "distance-to-go-value"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    text: root.telemetryAvailable ? root.axisText(root.distanceToGo) : "----"
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: root.metric ? "mm" : "in"
                                    color: "white"
                                    font.pixelSize: 10
                                    opacity: 0.85
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SECONDARY AXES (Razor-Sharp Vector Curves: Y1 Round Left, Delta Round Right)
    // =========================================================================
    Row {
        objectName: "secondary-axes"
        x: centerX
        y: rowY + mainHeight + gap
        width: centerWidth
        height: secondaryHeight
        spacing: 0
        clip: true

        // Y1 (Purple #800080) - Native vector round left corners, clipped straight right
        Item {
            objectName: "axis-y-1"
            width: Math.floor(parent.width / 3)
            height: parent.height
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width + metrics.smallRadius
                color: root.purple
                radius: metrics.smallRadius
            }

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Y1"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Text {
                        text: root.telemetryAvailable ? root.axisText(root.y1Position) : "----"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.metric ? "mm" : "in"
                        color: "white"
                        font.pixelSize: 10
                        opacity: 0.9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // Y2 (Blue #2D83B2) - Flat middle
        Item {
            objectName: "axis-y-2"
            width: Math.floor(parent.width / 3)
            height: parent.height
            clip: true

            Rectangle {
                anchors.fill: parent
                color: root.blue
            }

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Y2"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Text {
                        text: root.telemetryAvailable ? root.axisText(root.y2Position) : "----"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.metric ? "mm" : "in"
                        color: "white"
                        font.pixelSize: 10
                        opacity: 0.9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // Y1 / Y2 Delta (Teal #009E9E) - Native vector round right corners, clipped straight left
        Item {
            objectName: "axis-y-diff"
            width: parent.width - Math.floor(parent.width / 3) * 2
            height: parent.height
            clip: true

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width + metrics.smallRadius
                color: root.teal
                radius: metrics.smallRadius
            }

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Y1/Y2 Delta"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Text {
                        text: root.telemetryAvailable ? root.axisText(root.deltaPosition) : "----"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.metric ? "mm" : "in"
                        color: "white"
                        font.pixelSize: 10
                        opacity: 0.9
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // =========================================================================
    // BOTTOM PANELS (TOTAL LOAD: Orange, LIVE VELOCITY: Red)
    // =========================================================================
    Row {
        x: centerX
        y: rowY + mainHeight + gap + secondaryHeight + gap
        width: centerWidth
        height: smallHeight
        spacing: gap

        // Total Applied Load Panel (Original Orange)
        Rectangle {
            objectName: "panel-total-load"
            width: (parent.width - gap) / 2
            height: parent.height
            color: root.orange
            radius: metrics.smallRadius

            Column {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 3

                // Header Row
                Item {
                    width: parent.width
                    height: 14

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "TOTAL LOAD"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 10
                        opacity: 0.95
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "MAX " + (root.axisLoadCapacity * 2).toFixed(0) + "T"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 9
                        opacity: 0.75
                    }
                }

                // Value Row
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.telemetryAvailable ? root.displayedRamTotalLoad.toFixed(1) : "----"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 21
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 3
                            text: "T"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 12
                            opacity: 0.9
                        }
                    }

                    // Percentage of capacity
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round((root.displayedRamTotalLoad / Math.max(0.1, root.axisLoadCapacity * 2)) * 100) + "%"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 11
                        opacity: 0.8
                    }
                }

                // Load Intensity Track
                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 1.5
                    color: Qt.rgba(0, 0, 0, 0.22)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, Math.min(parent.width, parent.width * (root.displayedRamTotalLoad / Math.max(0.1, root.axisLoadCapacity * 2))))
                        radius: 1.5
                        color: "white"

                        Behavior on width {
                            enabled: root.animationsEnabled
                            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }

        // Live Velocity Panel (Original Red)
        Rectangle {
            objectName: "panel-live-ram-velocity"
            width: (parent.width - gap) / 2
            height: parent.height
            color: root.red
            radius: metrics.smallRadius

            Column {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 3

                // Header Row
                Item {
                    width: parent.width
                    height: 14

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RAM VELOCITY"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 10
                        opacity: 0.95
                    }

                    // Motion / Direction Badge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 14
                        width: dirText.implicitWidth + 8
                        radius: 3
                        color: Qt.rgba(0, 0, 0, 0.25)

                        Text {
                            id: dirText
                            anchors.centerIn: parent
                            text: root.displayedRamVelocity > 0.05
                                ? "▲ UP"
                                : (root.displayedRamVelocity < -0.05 ? "▼ DOWN" : "IDLE")
                            color: "white"
                            font.bold: true
                            font.pixelSize: 9
                            opacity: 0.95
                        }
                    }
                }

                // Value Row
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.telemetryAvailable && root.measuredVelocityAvailable
                                ? (root.metric ? (Math.abs(root.displayedRamVelocity) * 25.4 / 60).toFixed(2) : Math.abs(root.displayedRamVelocity).toFixed(1)) : "0.0"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 21
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 3
                            text: root.metric ? "mm/s" : "IPM"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 11
                            opacity: 0.9
                        }
                    }
                }

                // Velocity Intensity Track
                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 1.5
                    color: Qt.rgba(0, 0, 0, 0.22)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, Math.min(parent.width, parent.width * (Math.abs(root.displayedRamVelocity) / 15.0)))
                        radius: 1.5
                        color: "white"

                        Behavior on width {
                            enabled: root.animationsEnabled
                            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // LOAD TOWER COMPONENT (Pressure Gauge without lines, 4-digit RPM support)
    // =========================================================================
    component LoadTower: Rectangle {
        id: tower
        property real loadValue: 0
        property real rpmValue: 0

        readonly property real normalizedIntensity: Math.round(200 * Math.max(0, Math.min(1, Math.abs(loadValue) / Math.max(0.001, root.axisLoadCapacity)))) / 200

        readonly property color targetColor: normalizedIntensity < 0.5
            ? Qt.rgba(0.35 + normalizedIntensity * 1.25, 0.65, 0.05, 1)
            : Qt.rgba(0.975, 0.63 - (normalizedIntensity - 0.5) * 0.95, 0.02, 1)

        property real animatedIntensity: normalizedIntensity
        property color animatedColor: targetColor

        Behavior on animatedIntensity {
            enabled: root.animationsEnabled && tower.visible
            SmoothedAnimation { duration: 280; velocity: -1; maximumEasingTime: 120 }
        }
        Behavior on animatedColor {
            enabled: root.animationsEnabled && tower.visible
            ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        // RPM direction and styling (supports up to 4 digits: e.g. +2400 / -3000)
        readonly property bool isAscending: rpmValue > 0.05
        readonly property bool isDescending: rpmValue < -0.05
        readonly property string rpmNumberText: isAscending ? ("+" + Math.abs(rpmValue).toFixed(0))
            : (isDescending ? ("-" + Math.abs(rpmValue).toFixed(0))
            : "0")
        readonly property color rpmColor: isAscending ? root.green
            : (isDescending ? root.red : root.muted)

        color: "white"
        radius: metrics.smallRadius

        Column {
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 5

            // Top: Load Value with 'T' directly beside it (NO Y1 / Y2 label)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                Text {
                    id: tonnageVal
                    text: root.telemetryAvailable ? tower.loadValue.toFixed(1) : "----"
                    color: root.ink
                    font.bold: true
                    font.pixelSize: 15
                }

                Text {
                    anchors.baseline: tonnageVal.baseline
                    text: "T"
                    color: root.muted
                    font.bold: true
                    font.pixelSize: 11
                }
            }

            // Middle: Vertical Pressure Gauge Track - NO HORIZONTAL LINES
            Item {
                width: parent.width - 4
                height: 118
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    objectName: "load-intensity-track"
                    anchors.fill: parent
                    radius: metrics.smallRadius
                    color: "#D7D7D7"
                    clip: true

                    // Dynamic Fill Bar (smooth continuous gradient, no horizontal ticks)
                    Rectangle {
                        objectName: "load-intensity-fill"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * tower.animatedIntensity
                        radius: metrics.smallRadius
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0; color: Qt.lighter(tower.animatedColor, 1.18) }
                            GradientStop { position: 0.48; color: tower.animatedColor }
                            GradientStop { position: 1; color: Qt.darker(tower.animatedColor, 1.12) }
                        }
                    }
                }
            }

            // Bottom: Signed RPM Display (Number on top, RPM unit below for 4-digit support)
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tower.rpmNumberText
                    color: tower.rpmColor
                    font.bold: true
                    font.pixelSize: 13
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "RPM"
                    color: tower.rpmColor
                    font.bold: true
                    font.pixelSize: 9
                    opacity: 0.85
                }
            }
        }
    }

    // =========================================================================
    // HOME ICON
    // =========================================================================
    component HomeIcon: Item {
        id: iconItem
        property int size: 16
        property color color: "white"
        width: size
        height: size

        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = iconItem.color
                ctx.beginPath()
                ctx.moveTo(width * 0.08, height * 0.48)
                ctx.lineTo(width * 0.5, height * 0.12)
                ctx.lineTo(width * 0.92, height * 0.48)
                ctx.lineTo(width * 0.82, height * 0.48)
                ctx.lineTo(width * 0.82, height * 0.9)
                ctx.lineTo(width * 0.22, height * 0.9)
                ctx.lineTo(width * 0.22, height * 0.48)
                ctx.closePath()
                ctx.fill()
            }
        }
    }
}
