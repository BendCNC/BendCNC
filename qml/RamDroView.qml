import QtQuick
import "core/Units.js" as Units

Item {
    id: root
    objectName: "ram-dro-view header body panel-load main-axis panel-home-position axis-y-1 axis-y-2 axis-y-diff panel-total-load panel-live-ram-velocity value-box value-row"

    // Operational channels are independent controller telemetry. Snapshot/test
    // simulation remains explicit; production never synthesizes matching Y1/Y2.
    property var appState: null
    readonly property bool metric: appState ? appState.metricUnits === true : false
    function axisText(v) { return metric ? (Number(v) * 25.4).toFixed(2) : Number(v).toFixed(4) }
    readonly property bool telemetryAvailable: appState
        ? (appState.offlineSimulationEnabled || appState.independentRamTelemetryAvailable) : false
    readonly property real ramCurrent: appState
        ? (appState.independentRamTelemetryAvailable
            ? (appState.ramPositionY1 + appState.ramPositionY2) / 2.0
            : appState.ramPosition) : -0.05
    readonly property bool measuredVelocityAvailable: appState
        ? appState.measuredRamVelocityAvailable : false
    readonly property real ramVelocity: measuredVelocityAvailable
        ? appState.measuredRamVelocity : 0
    readonly property real ramTotalLoad: appState ? appState.liveTonnage : 0
    property real displayedRamCurrent: ramCurrent
    property real displayedRamVelocity: ramVelocity
    property real displayedRamTotalLoad: ramTotalLoad
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

    LayoutMetrics { id: metrics }

    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color purple: "#800080"
    readonly property color teal: "#009E9E"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color ink: "#232323"
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
    readonly property real y1Position: appState && !appState.offlineSimulationEnabled
        ? appState.ramPositionY1 : root.displayedRamCurrent
    readonly property real y2Position: appState && !appState.offlineSimulationEnabled
        ? appState.ramPositionY2 : root.displayedRamCurrent
    readonly property real y1Load: appState && !appState.offlineSimulationEnabled
        ? appState.ramLoadY1 : root.displayedRamTotalLoad / 2
    readonly property real y2Load: appState && !appState.offlineSimulationEnabled
        ? appState.ramLoadY2 : root.displayedRamTotalLoad / 2

    Rectangle {
        objectName: "header"
        x: 0
        y: 0
        width: parent.width
        height: metrics.ramDroHeaderHeight
        color: red
        radius: metrics.panelRadius
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: metrics.panelRadius; color: red }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: inset
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text { text: "RAM"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont }
            Text { text: "POSITION"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont; font.bold: true }
            Text { text: "&"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont }
            Text { text: "LOAD"; color: "white"; font.pixelSize: metrics.ramDroHeaderFont; font.bold: true }
        }
    }

    Rectangle {
        objectName: "body"
        x: 0
        y: bodyTop
        width: parent.width
        height: bodyHeight
        color: lightGrey
        radius: metrics.panelRadius
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: metrics.panelRadius; color: lightGrey }
    }

    LoadPanel { objectName: "panel-load y1-load"; x: inset; y: rowY; width: sideWidth; height: contentHeight; title: "Y1 RAM\nLOAD"; load: root.y1Load }
    LoadPanel { objectName: "panel-load y2-load"; x: root.width - inset - sideWidth; y: rowY; width: sideWidth; height: contentHeight; title: "Y2 RAM\nLOAD"; load: root.y2Load }

    Rectangle {
        objectName: "main-axis"
        x: centerX
        y: rowY
        width: centerWidth
        height: mainHeight
        color: green
        radius: metrics.smallRadius

        Column {
            anchors.fill: parent
            anchors.margins: inset
            spacing: 0
            Row {
                width: parent.width
                height: 21
                Text { id: currentTitle; anchors.verticalCenter: parent.verticalCenter; text: "CURRENT"; color: "white"; font.bold: true; font.pixelSize: 16 }
                Item { width: Math.max(0, parent.width - currentTitle.width - homePosition.width); height: 1 }
                Row {
                    id: homePosition
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: gap
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "HOME POSITION"; color: "white"; font.bold: true; font.pixelSize: 16 }
                    HomeIcon { anchors.verticalCenter: parent.verticalCenter; size: 18; color: "white" }
                }
            }
            Row {
                width: parent.width
                height: parent.height - 21
                Text { anchors.verticalCenter: parent.verticalCenter; width: metrics.ramDroMainValueWidth; text: root.telemetryAvailable ? root.axisText(root.displayedRamCurrent) : "----"; color: "white"; font.bold: true; font.pixelSize: metrics.ramDroMainValueFont }
                Item { width: Math.max(0, parent.width - metrics.ramDroMainValueWidth - unitLabel.width); height: 1 }
                Text { id: unitLabel; anchors.verticalCenter: parent.verticalCenter; text: root.metric ? "mm" : "in"; color: "white"; font.bold: true; font.pixelSize: 16 }
            }
        }
    }

    Row {
        objectName: "secondary-axes"
        x: centerX
        y: rowY + mainHeight + gap
        width: centerWidth
        height: secondaryHeight
        spacing: 0
        AxisPanel { objectName: "axis-y-1"; width: parent.width / 3; height: parent.height; title: "Y1"; value: root.telemetryAvailable ? root.axisText(root.y1Position) : "----"; base: purple; roundLeft: true }
        AxisPanel { objectName: "axis-y-2"; width: parent.width / 3; height: parent.height; title: "Y2"; value: root.telemetryAvailable ? root.axisText(root.y2Position) : "----"; base: blue }
        AxisPanel { objectName: "axis-y-diff"; width: parent.width / 3; height: parent.height; title: "Y1/Y2 Delta"; value: root.telemetryAvailable ? root.axisText(Math.abs(root.y1Position - root.y2Position)) : "----"; base: teal; roundRight: true }
    }

    SmallPanel {
        objectName: "panel-total-load"
        x: centerX
        y: rowY + mainHeight + gap + secondaryHeight + gap
        width: (centerWidth - gap) / 2
        height: smallHeight
        title: "TOTAL LOAD"
        value: root.telemetryAvailable ? root.displayedRamTotalLoad.toFixed(1) : "----"
        unit: "TONS"
        base: "orange"
    }

    SmallPanel {
        objectName: "panel-live-ram-velocity"
        x: centerX + (centerWidth + gap) / 2
        y: rowY + mainHeight + gap + secondaryHeight + gap
        width: (centerWidth - gap) / 2
        height: smallHeight
        title: "LIVE RAM VELOCITY"
        value: root.telemetryAvailable && root.measuredVelocityAvailable
            ? (root.metric ? (root.displayedRamVelocity * 25.4 / 60).toFixed(2) : root.displayedRamVelocity.toFixed(1)) : "----"
        unit: root.metric ? "mm/s" : "IPM"
        base: red
    }

    component LoadPanel: Rectangle {
        id: loadPanel
        property string title: ""
        property real load: 0
        readonly property real normalizedIntensity: Math.max(0, Math.min(1, Math.abs(load) / Math.max(0.001, root.axisLoadCapacity)))
        property real animatedIntensity: normalizedIntensity
        // Color follows the animated fill height, so it cannot run out of step
        // with it. The previous separate ColorAnimation restarted on every
        // telemetry frame and flickered with noisy per-side load. Continuous
        // green -> yellow -> red ramp (no step at 50%).
        readonly property real colorIntensity: Math.max(0, Math.min(1, animatedIntensity))
        readonly property color animatedColor: colorIntensity < 0.5
            ? Qt.rgba(0.35 + colorIntensity * 1.25, 0.65, 0.05, 1)
            : Qt.rgba(0.975, 0.65 - (colorIntensity - 0.5) * 0.99, 0.05 - (colorIntensity - 0.5) * 0.06, 1)

        Behavior on animatedIntensity {
            enabled: root.animationsEnabled && loadPanel.visible
            SmoothedAnimation { duration: 280; velocity: -1; maximumEasingTime: 120 }
        }

        color: "white"
        radius: metrics.smallRadius
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 7; text: root.telemetryAvailable ? loadPanel.load.toFixed(1) : "----"; color: ink; font.bold: true; font.pixelSize: 14 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 25; text: "TONS"; color: ink; font.bold: true; font.pixelSize: 11 }
        Rectangle {
            id: loadTrack
            objectName: "load-intensity-track"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 43
            width: parent.width - 14
            height: metrics.ramDroLoadBarHeight
            radius: metrics.smallRadius
            color: "#D7D7D7"
            clip: true

            Rectangle {
                id: loadFill
                objectName: "load-intensity-fill"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * loadPanel.animatedIntensity
                radius: Math.min(metrics.smallRadius, height / 2)
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.lighter(loadPanel.animatedColor, 1.18) }
                    GradientStop { position: 0.48; color: loadPanel.animatedColor }
                    GradientStop { position: 1; color: Qt.darker(loadPanel.animatedColor, 1.12) }
                }
            }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 7; width: parent.width - 14; text: loadPanel.title; color: ink; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; lineHeight: 0.9; wrapMode: Text.WordWrap }
    }

    component AxisPanel: Item {
        property string title: ""
        property string value: ""
        property color base: purple
        property bool roundLeft: false
        property bool roundRight: false

        Rectangle {
            anchors.fill: parent
            color: base
            radius: (roundLeft || roundRight) ? metrics.smallRadius : 0
        }

        Rectangle { visible: !roundLeft; x: 0; y: 0; width: metrics.smallRadius; height: metrics.smallRadius; color: base }
        Rectangle { visible: !roundLeft; x: 0; y: parent.height - metrics.smallRadius; width: metrics.smallRadius; height: metrics.smallRadius; color: base }
        Rectangle { visible: !roundRight; x: parent.width - metrics.smallRadius; y: 0; width: metrics.smallRadius; height: metrics.smallRadius; color: base }
        Rectangle { visible: !roundRight; x: parent.width - metrics.smallRadius; y: parent.height - metrics.smallRadius; width: metrics.smallRadius; height: metrics.smallRadius; color: base }

        Column {
            anchors.fill: parent
            anchors.leftMargin: inset
            anchors.rightMargin: inset
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 4
            Text { width: parent.width; text: title; color: "white"; font.bold: true; font.pixelSize: metrics.ramDroAxisTitleFont; horizontalAlignment: Text.AlignHCenter }
            Row {
                width: parent.width
                height: 18
                Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 22; text: value; color: "white"; font.bold: true; font.pixelSize: metrics.ramDroAxisValueFont }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 22; text: root.metric ? "mm" : "in"; color: "white"; font.bold: true; font.pixelSize: metrics.ramDroAxisUnitFont; horizontalAlignment: Text.AlignRight }
            }
        }
    }

    component SmallPanel: Rectangle {
        property string title: ""
        property string value: ""
        property string unit: ""
        property color base: red
        color: base
        radius: metrics.smallRadius
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: inset
            anchors.rightMargin: inset
            height: 40
            spacing: 2
            Text { width: parent.width; text: title; color: "white"; font.bold: true; font.pixelSize: 11; fontSizeMode: Text.Fit; minimumPixelSize: 9; horizontalAlignment: Text.AlignLeft }
            Row {
                width: parent.width
                height: 20
                spacing: 4
                Rectangle {
                    width: parent.width - 38
                    height: parent.height
                    color: "#C7C7C7"
                    radius: metrics.smallRadius
                    Text { anchors.right: parent.right; anchors.rightMargin: inset; anchors.verticalCenter: parent.verticalCenter; text: value; color: ink; font.bold: true; font.pixelSize: 12 }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 34; text: unit; color: "white"; font.bold: true; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
            }
        }
    }

    component HomeIcon: Item {
        property int size: 18
        property color color: "white"
        width: size
        height: size
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = color
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
