import QtQuick
import QtQuick.Layouts

Rectangle {
    id: actionBar
    objectName: "action-bar ActionBarView RestartSystemView SystemInfoView ApplicationUpdateView ModuleFirmwareUpdateView MachineFirmwareUpdateView BleedHydraulicsView BackupView WifiConnectionView label-version label-title button bleed-hydarulics-view wifi-connection-button"

    color: "#FFFFFF"
    implicitHeight: 40

    readonly property color orange: "#FFA500"
    readonly property color charcoal: "#2B2C2B"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color red: "#A82011"
    readonly property color green: "#167A00"
    readonly property color grey: "#A8A8A8"
    property var appState: null

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 7
        anchors.rightMargin: 7
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        spacing: 4

        // Software power-off toggle: first tap arms (5 s), second tap confirms.
        Rectangle {
            id: powerToggle
            objectName: "power-off-toggle"
            property bool armed: false
            readonly property bool blocked: !!actionBar.appState && !!actionBar.appState.runActive
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: armed ? 128 : 92
            Layout.preferredHeight: 30
            radius: 15
            color: armed ? "#B91C1C" : "#3F3F46"
            opacity: blocked ? 0.45 : 1.0
            Rectangle {
                width: 24; height: 24; radius: 12
                anchors.verticalCenter: parent.verticalCenter
                x: powerToggle.armed ? parent.width - width - 3 : 3
                color: "white"
                Behavior on x { NumberAnimation { duration: 120 } }
                // Drawn power symbol: the U+23FB glyph sits off-centre in the font box.
                Canvas {
                    id: powerIcon
                    anchors.centerIn: parent
                    width: 14; height: 14
                    readonly property color ink: powerToggle.armed ? "#B91C1C" : "#3F3F46"
                    onInkChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = ink
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.arc(7, 7.5, 5.2, -Math.PI / 2 + 0.75, 3 * Math.PI / 2 - 0.75)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(7, 1.2); ctx.lineTo(7, 7)
                        ctx.stroke()
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: powerToggle.armed ? 10 : 32
                text: powerToggle.armed ? "CONFIRM OFF" : "TURN OFF"
                color: "white"
                font.bold: true
                font.pixelSize: 11
            }
            Timer { id: powerArmTimer; interval: 5000; onTriggered: powerToggle.armed = false }
            MouseArea {
                anchors.fill: parent
                enabled: !powerToggle.blocked
                onClicked: {
                    if (!powerToggle.armed) {
                        powerToggle.armed = true
                        powerArmTimer.restart()
                        return
                    }
                    powerArmTimer.stop()
                    powerToggle.armed = false
                    if (actionBar.appState)
                        actionBar.appState.toolbarAction("power-off")
                }
            }
        }

        // Restart toggle, same style as TURN OFF: first tap arms (5 s), second confirms.
        Rectangle {
            id: restartToggle
            objectName: "button restart-system-view RestartSystemView.fxml restart-toggle"
            property bool armed: false
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: armed ? 128 : 92
            Layout.preferredHeight: 30
            radius: 15
            color: armed ? "#D97706" : "#3F3F46"
            Rectangle {
                width: 24; height: 24; radius: 12
                anchors.verticalCenter: parent.verticalCenter
                x: restartToggle.armed ? parent.width - width - 3 : 3
                color: "white"
                Behavior on x { NumberAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: "\u21BB"; font.pixelSize: 14; font.bold: true; color: restartToggle.armed ? "#D97706" : "#3F3F46" }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: restartToggle.armed ? 10 : 32
                text: restartToggle.armed ? "CONFIRM" : "RESTART"
                color: "white"
                font.bold: true
                font.pixelSize: 11
            }
            Timer { id: restartArmTimer; interval: 5000; onTriggered: restartToggle.armed = false }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (!restartToggle.armed) {
                        restartToggle.armed = true
                        restartArmTimer.restart()
                        return
                    }
                    restartArmTimer.stop()
                    restartToggle.armed = false
                    if (actionBar.appState)
                        actionBar.appState.toolbarAction("restart")
                }
            }
        }

        RowLayout {
            objectName: "sys-info-view SystemInfoView.fxml sys-info-pair sys-info-separator label-sys-info low medium high"
            spacing: 8
            Layout.alignment: Qt.AlignVCenter
            SysPair {
                valueObjectName: "cpu-load-value"
                label: "CPU"
                value: actionBar.appState ? actionBar.appState.cpuLoadText : "--"
                level: actionBar.appState ? actionBar.appState.cpuLoadLevel : "unknown"
            }
            SysPair {
                valueObjectName: "cpu-temperature-value"
                label: "TEMP"
                value: actionBar.appState ? actionBar.appState.cpuTemperatureText : "--"
                level: actionBar.appState ? actionBar.appState.cpuTemperatureLevel : "unknown"
            }
            SysPair {
                valueObjectName: "memory-used-value"
                label: "RAM"
                value: actionBar.appState ? actionBar.appState.memoryText : "--"
                level: actionBar.appState ? actionBar.appState.memoryLevel : "unknown"
            }
        }

        Item { Layout.fillWidth: true }

        ActionButton { visible: actionBar.appState && actionBar.appState.applicationUpdateAvailable; objectName: "button application-update-view ApplicationUpdateView.fxml button-orange bold icon-18"; icon: "↟"; text: "UPDATE APP"; widthHint: 116; colorHint: orange; onClicked: if (actionBar.appState) actionBar.appState.toolbarAction("update-app") }
        ActionButton { visible: actionBar.appState && actionBar.appState.moduleUpdateAvailable; objectName: "button module-firmware-update-view ModuleFirmwareUpdateView.fxml button-orange bold icon-18"; icon: "↟"; text: "UPDATE MODULE"; widthHint: 140; colorHint: orange; onClicked: if (actionBar.appState) actionBar.appState.toolbarAction("update-module") }
        ActionButton { visible: actionBar.appState && actionBar.appState.machineUpdateAvailable; objectName: "button machine-firmware-update-view MachineFirmwareUpdateView.fxml button-orange bold icon-18"; icon: "↟"; text: "UPDATE MACHINE"; widthHint: 140; colorHint: orange; onClicked: if (actionBar.appState) actionBar.appState.toolbarAction("update-machine") }
        // Display units: tap to toggle inches/IPM <-> mm/cm and mm/s.
        Rectangle {
            objectName: "button units-toggle"
            Layout.preferredWidth: 58
            Layout.fillHeight: true
            radius: 4
            color: "#1E293B"
            border.width: 1
            border.color: "#475569"
            readonly property bool metric: actionBar.appState ? actionBar.appState.metricUnits : false
            Row {
                anchors.centerIn: parent
                spacing: 0
                Repeater {
                    model: [{ t: "mm", m: true }, { t: "in", m: false }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 26
                        height: 22
                        radius: 3
                        color: modelData.m === parent.parent.metric ? "#FFA500" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.t
                            font.bold: true
                            font.pixelSize: 12
                            color: modelData.m === parent.parent.parent.metric ? "#111827" : "#CBD5E1"
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: if (actionBar.appState) actionBar.appState.setMetricUnits(!actionBar.appState.metricUnits)
            }
        }
        IconButton {
            objectName: "button machine-log-view fas-file-alt"
            accessibleName: qsTr("Machine logs")
            iconSource: "icons/fa-file-white.svg"
            colorHint: orange
            onClicked: if (actionBar.appState) actionBar.appState.toolbarAction("log")
        }
        IconButton {
            objectName: "button backup-view BackupView.fxml fas-history"
            accessibleName: qsTr("Backup")
            iconSource: "icons/fa-undo.svg"
            colorHint: orange
            onClicked: if (actionBar.appState) actionBar.appState.toolbarAction("backup")
        }
        IconButton {
            objectName: "button wifi-connection-button WifiConnectionView.fxml wifi-connection-view"
            accessibleName: actionBar.appState && actionBar.appState.wifiConnected
                ? qsTr("Wi-Fi connected") : qsTr("Wi-Fi disconnected")
            iconSource: "icons/fa-wifi.svg"
            iconSize: 26
            colorHint: actionBar.appState && actionBar.appState.wifiConnected ? "#59A60C" : red
            glyphColor: "white"
            borderColor: actionBar.appState && actionBar.appState.wifiConnected ? "#3F7A08" : "#7F180D"
            borderWidth: 2
            radiusHint: 7
            onClicked: if (actionBar.appState) actionBar.appState.toolbarAction("wifi")
        }
    }

    component ActionButton: Rectangle {
        id: actionButton
        property string icon: ""
        property string text: ""
        property string labelObjectName: "action-button-label"
        property int widthHint: 100
        property int labelSize: 11
        property color colorHint: "#FFA500"
        signal clicked()
        Layout.preferredWidth: widthHint
        Layout.fillHeight: true
        radius: 4
        color: colorHint
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 6
            Text { text: icon; visible: icon.length > 0; color: "white"; font.bold: true; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
            Text {
                objectName: actionButton.labelObjectName
                text: actionButton.text
                color: "white"
                font.bold: true
                font.pixelSize: actionButton.labelSize
                fontSizeMode: Text.Fit
                minimumPixelSize: 8
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
                Layout.preferredHeight: actionButton.height - 8
                Layout.alignment: Qt.AlignVCenter
            }
        }
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component IconButton: Rectangle {
        id: iconButton
        property string glyph: ""
        property url iconSource: ""
        property int iconSize: 23
        property string accessibleName: ""
        property color colorHint: "#FFA500"
        property color glyphColor: "white"
        property color borderColor: "transparent"
        property int borderWidth: 0
        property int radiusHint: 4
        signal clicked()
        Layout.preferredWidth: 36
        Layout.fillHeight: true
        radius: radiusHint
        color: colorHint
        border.color: borderColor
        border.width: borderWidth
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Image {
            objectName: "icon-image"
            anchors.centerIn: parent
            width: iconButton.iconSize
            height: iconButton.iconSize
            source: iconButton.iconSource
            sourceSize.width: iconButton.iconSize
            sourceSize.height: iconButton.iconSize
            fillMode: Image.PreserveAspectFit
            visible: iconButton.iconSource.toString().length > 0
            Accessible.ignored: true
        }
        Text {
            anchors.centerIn: parent
            text: glyph
            color: glyphColor
            font.bold: true
            font.pixelSize: 18
            visible: iconButton.iconSource.toString().length === 0
            Accessible.ignored: true
        }
        Keys.onSpacePressed: clicked()
        Keys.onReturnPressed: clicked()
        MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
    }

    component SysPair: RowLayout {
        property string label: ""
        property string value: ""
        property string valueObjectName: "label-sys-info"
        property string level: "low"
        readonly property color valueColor: level === "high" ? actionBar.red
            : (level === "medium" ? actionBar.orange
               : (level === "low" ? "#59A60C" : actionBar.grey))
        spacing: 4
        Text { text: label; color: "grey"; font.pixelSize: 13 }
        Text {
            objectName: parent.valueObjectName + " label-sys-info " + parent.level
            text: parent.value
            color: parent.valueColor
            font.pixelSize: 13
        }
    }

    component MotorRpmPair: RowLayout {
        property string label: ""
        property string valueObjectName: "motor-rpm-value"
        property bool available: false
        property real rpm: 0
        readonly property bool descending: rpm < -0.05
        readonly property bool ascending: rpm > 0.05
        readonly property string rpmText: !available ? "-- RPM"
            : (ascending ? "+" : (descending ? "−" : ""))
              + Math.abs(rpm).toFixed(0) + " RPM"
        spacing: 4
        Text { text: parent.label; color: "grey"; font.pixelSize: 13 }
        Text {
            objectName: parent.valueObjectName + " label-sys-info motor-rpm"
            text: parent.rpmText
            color: !parent.available ? actionBar.grey
                : (parent.descending ? actionBar.red
                   : (parent.ascending ? actionBar.green : actionBar.grey))
            font.pixelSize: 13
            font.bold: parent.available && (parent.descending || parent.ascending)
        }
    }

    component SeparatorLine: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 20
        color: "#BCBCBC"
    }
}
