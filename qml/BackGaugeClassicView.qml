import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Shapes

Item {
    id: root
    objectName: "backgauge-classic-view"
    property var appState: null
    property bool openProfilePopupOnCompleted: false
    property var coordinateSelector: null
    focus: true

    onActiveFocusChanged: {
        if (!activeFocus && appState && appState.backGaugeActiveDirection.length === 2) {
            const direction = appState.backGaugeActiveDirection
            appState.releaseBackGaugeJog(direction.charAt(0), direction.charAt(1) === "+" ? 1 : -1)
        }
    }
    Component.onDestruction: {
        if (appState && appState.backGaugeActiveDirection.length === 2) {
            const direction = appState.backGaugeActiveDirection
            appState.releaseBackGaugeJog(direction.charAt(0), direction.charAt(1) === "+" ? 1 : -1)
        }
    }

    readonly property real sx: width / 864
    readonly property real sy: height / 638.4
    readonly property real outerH: 593.6 * sy
    readonly property real pad: 7.2 * sx
    readonly property real leftPaneX: 7.2 * sx
    readonly property real leftPaneW: 348 * sx
    readonly property real rightX: 362.4 * sx
    readonly property real rightW: Math.min(493.6 * sx, width - rightX)
    readonly property real rightInnerW: Math.max(0, rightW - 14.4 * sx)
    readonly property real fieldH: 27.2 * sy

    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color charcoal: "#2B2C2B"
    readonly property color grey: "#A8A8A8"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color paper: "#F5F5F5"
    readonly property color ink: "#232323"
    readonly property color white: "#FFFFFF"
    readonly property color cyan: "#00FFFF"
    readonly property color orange: "orange"
    readonly property color transparentColor: "transparent"

    Timer {
        interval: 250
        running: root.openProfilePopupOnCompleted
        repeat: false
        onTriggered: {
            if (root.coordinateSelector)
                root.coordinateSelector.popup.open()
        }
    }

    function openNumericKeyboard(field, title, commitHandler) {
        if (appState)
            appState.openOnScreenKeyboard(field, true, title, commitHandler)
    }

    function openTextKeyboard(field, title, commitHandler, cancelHandler) {
        if (appState)
            appState.openOnScreenKeyboard(field, false, title, commitHandler, cancelHandler)
    }

    function jogFromKey(key, pressed) {
        var axis = ""
        var direction = 0
        if (key === Qt.Key_Left) { axis = "X"; direction = -1 }
        else if (key === Qt.Key_Right) { axis = "X"; direction = 1 }
        else if (key === Qt.Key_Up) { axis = "R"; direction = 1 }
        else if (key === Qt.Key_Down) { axis = "R"; direction = -1 }
        else return false
        if (!appState) return false
        if (pressed) appState.beginBackGaugeJog(axis, direction)
        else appState.releaseBackGaugeJog(axis, direction)
        return true
    }

    Keys.onPressed: function(event) {
        if (event.isAutoRepeat) return
        if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_H) {
            if (appState) appState.requestBackGaugeHome()
            event.accepted = true
            return
        }
        event.accepted = jogFromKey(event.key, true)
    }
    Keys.onReleased: function(event) {
        if (event.isAutoRepeat) return
        event.accepted = jogFromKey(event.key, false)
    }

    Timer {
        interval: 120
        repeat: true
        running: root.appState && root.appState.offlineSimulationEnabled
                 && root.appState.backGaugeContinuousJog
                 && root.appState.backGaugeActiveDirection.length > 0
        onTriggered: root.appState.continueBackGaugeJog()
    }

    Rectangle {
        anchors.fill: parent
        color: grey
    }

    Item {
        objectName: "column-left"
        x: 0
        y: 0
        width: root.rightX
        height: root.outerH

        Item {
            objectName: "backgauge-jog-pad-view BackGaugeJogPadView"
            x: 44.8 * root.sx
            y: 191.2 * root.sy
            width: 272.8 * root.sx
            height: 174.4 * root.sy

            JogPadButton { objectName: "buttonNegativeX"; x: 4 * root.sx; y: 46.4 * root.sy; label: qsTr("X-"); iconName: "arrow-left"; axis: "X"; direction: -1 }
            JogPadButton { objectName: "buttonPositiveR"; x: 93.6 * root.sx; y: 4 * root.sy; label: qsTr("R+"); iconName: "arrow-up"; axis: "R"; direction: 1 }
            JogPadButton { objectName: "buttonNegativeR"; x: 93.6 * root.sx; y: 88.8 * root.sy; label: qsTr("R-"); iconName: "arrow-down"; axis: "R"; direction: -1 }
            JogPadButton { objectName: "buttonPositiveX"; x: 183.2 * root.sx; y: 46.4 * root.sy; label: qsTr("X+"); iconName: "arrow-right"; axis: "X"; direction: 1 }
        }

        Rectangle {
            objectName: "stop-button BackGaugeStopView"
            x: 14.4 * root.sx
            y: 548.8 * root.sy
            width: 333.6 * root.sx
            height: 29.6 * root.sy
            radius: 7
            color: red
            Text { anchors.centerIn: parent; text: qsTr("STOP BACK GAUGE"); color: white; font.pixelSize: 12; font.bold: true }
            MouseArea { anchors.fill: parent; onClicked: if (root.appState) root.appState.backGaugeStop() }
        }
    }

    Item {
        objectName: "column-right panelControlPreventedOverlay blur-popup"
        x: root.rightX
        y: 7.2 * root.sy
        width: root.rightW
        height: 579.2 * root.sy

        BackGaugeDroPanel { x: root.pad; y: root.pad; width: root.rightInnerW; height: 133.6 * root.sy }
        BackGaugeModePanel { objectName: "backgauge-mode-view BackGaugeJogStepView"; x: root.pad; y: 148 * root.sy; width: root.rightInnerW; height: 71.2 * root.sy; mode: "step"; titleA: qsTr("JOG"); titleB: qsTr("STEP"); value: root.appState ? (root.appState.backGaugeContinuousJog ? "CONT." : root.appState.jogStep.toFixed(4)) : "0.1000"; unit: root.appState && root.appState.backGaugeUnit === "MILLIMETER" ? "mm" : "in"; presets: root.appState ? root.appState.backGaugeStepPresets : [0.0005, 0.001, 0.01, 0.1] }
        BackGaugeModePanel { objectName: "backgauge-mode-view BackGaugeJogSpeedView"; x: root.pad; y: 226.4 * root.sy; width: root.rightInnerW; height: 71.2 * root.sy; mode: "speed"; titleA: qsTr("JOG"); titleB: qsTr("SPEED"); value: root.appState ? root.appState.jogSpeed.toFixed(3) : "100.000"; unit: root.appState && root.appState.backGaugeUnit === "MILLIMETER" ? "MMM" : "IPM"; presets: root.appState ? root.appState.backGaugeSpeedPresets : [1, 10, 25, 50, 75, 100] }
        BackGaugeMoveToPanel { x: root.pad; y: 304.8 * root.sy; width: root.rightInnerW; height: 73.6 * root.sy }

    }

    BackGaugeStatusBar { x: 0; y: 593.6 * root.sy; width: parent.width; height: 44 * root.sy }

    component JogPadButton: Rectangle {
        property string label: ""
        property string iconName: ""
        property string axis: "X"
        property int direction: 1
        readonly property string directionKey: axis + (direction > 0 ? "+" : "-")
        readonly property bool selected: root.appState
            && root.appState.backGaugeActiveDirection === directionKey
        readonly property bool enabled: root.appState && root.appState.backGaugeCanOperate
        width: 85.6 * root.sx
        height: 81.6 * root.sy
        radius: 7
        color: selected ? blue : charcoal
        opacity: enabled ? 1 : 0.45
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5.4 * root.sy
            IconGlyph { glyph: iconName; iconColor: white; size: 17 * Math.min(root.sx, root.sy); Layout.preferredWidth: 17 * root.sx; Layout.preferredHeight: 17 * root.sy; Layout.alignment: Qt.AlignHCenter }
            Text { text: label; color: white; font.pixelSize: 17; font.bold: true; Layout.alignment: Qt.AlignHCenter }
        }
        Accessible.role: Accessible.Button
        Accessible.name: label
        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            onPressed: { root.forceActiveFocus(); root.appState.beginBackGaugeJog(parent.axis, parent.direction) }
            onReleased: root.appState.releaseBackGaugeJog(parent.axis, parent.direction)
            onCanceled: root.appState.releaseBackGaugeJog(parent.axis, parent.direction)
        }
    }

    component BackGaugeDroPanel: Rectangle {
        id: droPanel
        objectName: "backgauge-dro-view BackGaugeDroView BackGaugeHomingView"
        property bool showMachine: false
        radius: 7
        color: lightGrey

        Item {
            anchors.fill: parent
            anchors.margins: 7.2

            RoundedCorners { x: 0; y: 30.4 * root.sy; width: parent.width; height: 88.8 * root.sy; radiusSize: 7; color: Qt.darker(lightGrey, 1.10); topLeft: true; topRight: true; bottomLeft: true; bottomRight: true }
            RoundedCorners { x: 88 * root.sx; y: 0; width: 247.2 * root.sx; height: 30.4 * root.sy; radiusSize: 7; color: Qt.darker(lightGrey, 1.10); topLeft: true; topRight: true }
            RoundedCorners { x: 335.2 * root.sx; y: 0; width: 60 * root.sx; height: 30.4 * root.sy; radiusSize: 7; color: droPanel.showMachine ? Qt.darker(lightGrey, 1.10) : Qt.darker(grey, 1.10); topLeft: true; topRight: true }
            Text { x: 342.4 * root.sx; y: 8 * root.sy; text: qsTr("MACHINE"); color: ink; font.pixelSize: 11; font.bold: true }
            MouseArea { objectName: "machine-coordinate-tab"; x: 335.2 * root.sx; y: 0; width: 60 * root.sx; height: 30.4 * root.sy; onClicked: droPanel.showMachine = true }

            RowLayout {
                objectName: "hbox-controls tab-overlay"
                x: 0
                y: 0
                width: parent.width
                height: 30.4 * root.sy
                spacing: 4
                RoundedCorners {
                    objectName: "button-home"
                    Layout.preferredWidth: 80 * root.sx
                    Layout.fillHeight: true
                    radiusSize: 7
                    color: root.appState && root.appState.backGaugeHomed ? green : red
                    opacity: root.appState && root.appState.backGaugeReady ? 1 : 0.45
                    topLeft: true
                    topRight: true
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5 * root.sx
                        IconGlyph { glyph: "home"; iconColor: white; size: 16 * Math.min(root.sx, root.sy); Layout.preferredWidth: 16 * root.sx; Layout.preferredHeight: 16 * root.sy }
                        Text { text: root.appState && root.appState.backGaugeHomed ? qsTr("HOMED") : qsTr("HOME"); color: white; font.pixelSize: 12; font.bold: true }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.appState && root.appState.backGaugeReady; onClicked: if (root.appState) root.appState.requestBackGaugeHome() }
                }
                Item { Layout.preferredWidth: 4 }
                CoordinateSystemCombo { objectName: "coordinate-systems-box"; Layout.preferredWidth: 200 * root.sx; Layout.preferredHeight: 23.4 * root.sy; Layout.alignment: Qt.AlignVCenter }
                Rectangle { Layout.preferredWidth: 2 * root.sx; Layout.fillHeight: true; color: Qt.darker(lightGrey, 1.25) }
                Rectangle {
                    objectName: "coordinate-name-edit-button"
                    Layout.preferredWidth: 19.2 * root.sx
                    Layout.fillHeight: true
                    color: transparentColor
                    IconGlyph { anchors.centerIn: parent; glyph: "pen"; iconColor: red; size: 11 * Math.min(root.sx, root.sy); width: 11 * root.sx; height: 11 * root.sy }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.appState && root.appState.backGaugeCanOperate
                        onClicked: {
                            coordinateNameEditor.visible = true
                            coordinateNameEditor.forceActiveFocus()
                            root.openTextKeyboard(
                                coordinateNameEditor, qsTr("REFERENCE STOP PROFILE"),
                                function(value) {
                                    if (root.appState)
                                        root.appState.renameBackGaugeCoordinateSystem(value)
                                    coordinateNameEditor.visible = false
                                },
                                function() { coordinateNameEditor.visible = false })
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            MouseArea {
                objectName: "work-coordinate-tab"
                x: 88 * root.sx
                y: 0
                width: 247.2 * root.sx
                height: 30.4 * root.sy
                enabled: droPanel.showMachine
                onClicked: droPanel.showMachine = false
            }

            ColumnLayout {
                objectName: "axes-container"
                x: 7.2 * root.sx
                y: 37.6 * root.sy
                width: parent.width - 14.4 * root.sx
                height: 74.4 * root.sy
                spacing: 1
                AxisRow { objectName: "hbox-axis, corners-top"; axis: "X"; value: root.appState && root.appState.backGaugePositionAvailable ? (droPanel.showMachine ? root.appState.backGaugeMachineX : root.appState.backGaugeX).toFixed(4) : "—"; topRow: true; machineMode: droPanel.showMachine }
                AxisRow { objectName: "hbox-axis,corners-bottom"; axis: "R"; value: root.appState && root.appState.backGaugePositionAvailable ? (droPanel.showMachine ? root.appState.backGaugeMachineR : root.appState.backGaugeR).toFixed(4) : "—"; bottomRow: true; machineMode: droPanel.showMachine }
            }
            TextField {
                id: coordinateNameEditor
                objectName: "coordinate-name-editor"
                visible: false
                x: 88 * root.sx; y: 0; width: 247.2 * root.sx; height: 30.4 * root.sy
                text: root.appState ? root.appState.backGaugeCoordinateDisplayName(root.appState.backGaugeCoordinateSystem) : ""
                selectByMouse: true
                onAccepted: {
                    if (root.appState) {
                        root.appState.renameBackGaugeCoordinateSystem(text)
                        if (root.appState.onScreenKeyboardTarget === coordinateNameEditor)
                            root.appState.closeOnScreenKeyboardState()
                    }
                    visible = false
                }
                background: Rectangle { color: white; border.color: red; border.width: 1 }
            }
        }
    }

    component AxisRow: Rectangle {
        property string axis: ""
        property string value: ""
        property bool topRow: false
        property bool bottomRow: false
        property bool machineMode: false
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: transparentColor
        RoundedCorners { anchors.fill: parent; radiusSize: 7; color: white; topLeft: topRow; topRight: topRow; bottomLeft: bottomRow; bottomRight: bottomRow }
        RowLayout {
            anchors.fill: parent
            spacing: 1
            Text { objectName: "label-axis"; text: axis; Layout.preferredWidth: 31.2 * root.sx; color: ink; font.pixelSize: 17; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            TextField {
                id: axisEditor
                objectName: "work-" + axis.toLowerCase() + "-field"
                text: value
                readOnly: machineMode
                Layout.fillWidth: true
                color: ink
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: TextInput.AlignLeft
                leftPadding: 1
                validator: DoubleValidator { notation: DoubleValidator.StandardNotation; decimals: 4 }
                background: null
                MouseArea {
                    anchors.fill: parent
                    enabled: !machineMode && root.appState && root.appState.backGaugeCanOperate
                    onClicked: {
                        axisEditor.forceActiveFocus()
                        root.openNumericKeyboard(axisEditor, qsTr("SET %1 WORK POSITION").arg(axis),
                            function(value) {
                                if (root.appState)
                                    root.appState.setBackGaugeWorkPosition(axis, value)
                            })
                    }
                }
            }
            RoundedCorners { visible: !machineMode; objectName: topRow ? "button-set, corner-top-right" : "button-set, corner-bottom-right"; Layout.preferredWidth: 44 * root.sx; Layout.fillHeight: true; radiusSize: 7; color: red; topRight: topRow; bottomRight: bottomRow; Text { anchors.centerIn: parent; text: axisEditor.activeFocus ? qsTr("SET") : qsTr("ZERO"); color: white; font.pixelSize: 11; font.bold: true; rotation: -90 } MouseArea { anchors.fill: parent; onClicked: if (root.appState) root.appState.setBackGaugeWorkPosition(axis, axisEditor.activeFocus ? axisEditor.text : 0) } }
        }
    }

    component BackGaugeModePanel: Rectangle {
        property string titleA: ""
        property string titleB: ""
        property string value: ""
        property string unit: ""
        property var presets: []
        property string mode: "step"
        Layout.fillWidth: true
        Layout.preferredHeight: 71
        Layout.minimumHeight: 71
        Layout.maximumHeight: 71
        radius: 7
        color: lightGrey

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 7
            RowLayout {
                objectName: "grid text-box"
                Layout.fillWidth: true
                spacing: 4
                Text { text: titleA; color: ink; font.pixelSize: 15; font.bold: true }
                Text { text: titleB; color: ink; font.pixelSize: 15 }
                Item { Layout.fillWidth: true }
                TextField {
                    id: modeEditor
                    objectName: "jog-" + mode + "-field"
                    Layout.preferredWidth: 161 * root.sx
                    Layout.preferredHeight: root.fieldH
                    text: value
                    readOnly: mode === "step" && root.appState && root.appState.backGaugeContinuousJog
                    selectByMouse: true
                    horizontalAlignment: TextInput.AlignRight
                    color: ink
                    font.pixelSize: 15
                    font.bold: true
                    validator: DoubleValidator { bottom: 0; decimals: mode === "step" ? 4 : 3 }
                    onAccepted: if (root.appState) { if (mode === "step") root.appState.setBackGaugeJogStep(text, false); else root.appState.setBackGaugeJogSpeed(text) }
                    background: Rectangle { color: white; radius: 3 }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !modeEditor.readOnly && root.appState && root.appState.backGaugeCanOperate
                        onClicked: root.openNumericKeyboard(
                            modeEditor, mode === "step" ? qsTr("JOG STEP") : qsTr("JOG SPEED"),
                            function(value) {
                                if (!root.appState)
                                    return
                                if (mode === "step")
                                    root.appState.setBackGaugeJogStep(value, false)
                                else
                                    root.appState.setBackGaugeJogSpeed(value)
                            })
                    }
                }
                Text { objectName: "label-unit"; text: unit; color: ink; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 32 * root.sx; elide: Text.ElideRight }
            }
            RowLayout {
                objectName: "presets"
                Layout.fillWidth: true
                spacing: 4
                    Repeater { model: mode === "step" ? presets.concat(["CONTINUOUS"]) : presets; Rectangle { readonly property bool special: mode === "step" ? index === presets.length : index === presets.length - 1; readonly property bool selected: root.appState && (mode === "step" ? (special ? root.appState.backGaugeContinuousJog : (!root.appState.backGaugeContinuousJog && Math.abs(root.appState.jogStep - Number(modelData)) < 0.00001)) : Math.abs(root.appState.jogSpeed - Number(modelData)) < 0.00001); objectName: special ? "special" : "button-preset"; Layout.fillWidth: true; Layout.preferredHeight: 22.4 * root.sy; radius: 7; color: selected ? (special ? (mode === "step" ? red : blue) : blue) : charcoal; Text { anchors.centerIn: parent; text: parent.special ? (mode === "step" ? qsTr("CONTINUOUS") : qsTr("RAPID")) : Number(modelData).toLocaleString(Qt.locale(), "f", mode === "step" ? (Number(modelData) < 0.01 ? 3 : Number(modelData) < 0.1 ? 2 : Number(modelData) < 1 ? 1 : 0) : 0); color: white; font.pixelSize: 11; font.bold: true } MouseArea { anchors.fill: parent; onClicked: if (root.appState) { if (mode === "step") root.appState.setBackGaugeJogStep(parent.special ? root.appState.jogStep : Number(modelData), parent.special); else root.appState.setBackGaugeJogSpeed(Number(modelData)) } } } }
            }
        }
    }

    component BackGaugeMoveToPanel: Rectangle {
        objectName: "backgauge-move-to-view BackGaugeMoveToView"
        radius: 7
        color: lightGrey
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 7
            RowLayout { objectName: "title"; spacing: 4; Text { text: qsTr("MOVE"); color: ink; font.pixelSize: 15; font.bold: true } Text { text: qsTr("TO"); color: ink; font.pixelSize: 15 } }
            RowLayout {
                objectName: "body"
                Layout.fillWidth: true
                spacing: 7
                    SmallField { id: moveX; objectName: "move-x-field"; value: root.appState ? root.appState.backGaugeX.toFixed(4) : "0.0000"; keyboardTitle: qsTr("MOVE TO X"); Layout.fillWidth: true }
                Text { text: "X"; color: ink; font.pixelSize: 15; font.bold: true }
                SmallField { id: moveR; objectName: "move-r-field"; value: root.appState ? root.appState.backGaugeR.toFixed(4) : "0.0000"; keyboardTitle: qsTr("MOVE TO R"); Layout.fillWidth: true }
                Text { text: "R"; color: ink; font.pixelSize: 15; font.bold: true }
                Rectangle { objectName: "move-run-button"; Layout.preferredWidth: 48 * root.sx; Layout.preferredHeight: 32.8 * root.sy; radius: 5; color: orange; opacity: root.appState && root.appState.backGaugeCanOperate ? 1 : 0.45; Text { anchors.centerIn: parent; text: qsTr("RUN"); color: ink; font.pixelSize: 14; font.bold: true } MouseArea { anchors.fill: parent; enabled: root.appState && root.appState.backGaugeCanOperate; onClicked: if (root.appState) root.appState.backGaugeMoveTo(moveX.text, moveR.text) } }
            }
        }
    }

    component SmallField: TextField {
        property string value: ""
        property string keyboardTitle: qsTr("ENTER VALUE")
        text: value
        Layout.minimumWidth: 120 * root.sx
        Layout.preferredWidth: 184.8 * root.sx
        Layout.preferredHeight: root.fieldH
        selectByMouse: true
        horizontalAlignment: TextInput.AlignRight
        color: ink
        font.pixelSize: 15
        font.bold: true
        validator: DoubleValidator { notation: DoubleValidator.StandardNotation; decimals: 4 }
        background: Rectangle { radius: 3; color: white }
        MouseArea {
            anchors.fill: parent
            enabled: root.appState && root.appState.backGaugeCanOperate
            onClicked: root.openNumericKeyboard(parent, parent.keyboardTitle, null)
        }
    }

    component CoordinateSystemCombo: ComboBox {
        id: coordinateCombo
        model: root.appState ? root.appState.backGaugeCoordinateSystems : []
        delegate: Component {
            ItemDelegate {
                required property string modelData
                width: coordinateCombo.width
                height: 22.4 * root.sy
                text: root.appState ? root.appState.backGaugeCoordinateDisplayName(modelData) : ""
            }
        }
        currentIndex: root.appState
            ? Math.max(0, root.appState.backGaugeCoordinateSystems.indexOf(root.appState.backGaugeCoordinateSystem))
            : 0
        enabled: root.appState && root.appState.backGaugeCanOperate
        Component.onCompleted: root.coordinateSelector = coordinateCombo
        implicitHeight: 23.4 * root.sy
        font.pixelSize: 11
        font.bold: true
        leftPadding: 7 * root.sx
        rightPadding: 20 * root.sx
        indicator: CaretGlyph { x: coordinateCombo.width - 15.2 * root.sx; y: (coordinateCombo.height - 7.4 * root.sy) / 2; width: 10.4 * root.sx; height: 7.4 * root.sy; iconColor: red }
        displayText: root.appState
            ? root.appState.backGaugeCoordinateDisplayName(root.appState.backGaugeCoordinateSystem)
            : ""
        onActivated: function(index) {
            if (root.appState && index >= 0 && index < root.appState.backGaugeCoordinateSystems.length)
                root.appState.selectBackGaugeCoordinateSystem(root.appState.backGaugeCoordinateSystems[index])
        }
        contentItem: Text { text: coordinateCombo.displayText; color: ink; font: coordinateCombo.font; verticalAlignment: Text.AlignVCenter; leftPadding: coordinateCombo.leftPadding; rightPadding: coordinateCombo.rightPadding; elide: Text.ElideRight }
        background: Rectangle { color: transparentColor; border.color: transparentColor; border.width: 0; radius: 0 }
        popup: Popup {
            y: coordinateCombo.height
            width: coordinateCombo.width
            implicitHeight: root.appState
                ? root.appState.backGaugeCoordinateSystems.length * 22.4 * root.sy
                : 0
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            contentItem: ListView {
                id: comboList
                clip: true
                model: coordinateCombo.popup.visible && root.appState
                    ? root.appState.backGaugeCoordinateSystems
                    : []
                currentIndex: coordinateCombo.highlightedIndex >= 0 ? coordinateCombo.highlightedIndex : coordinateCombo.currentIndex
                delegate: Component {
                    Rectangle {
                        required property string modelData
                        required property int index
                        width: comboList.width
                        height: 22.4 * root.sy
                        color: comboList.currentIndex === index ? red : "transparent"
                        Text {
                            anchors.fill: parent
                            text: root.appState
                                ? root.appState.backGaugeCoordinateDisplayName(modelData)
                                : ""
                            color: parent.color === root.red ? white : red
                            font.pixelSize: 11
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 7 * root.sx
                            rightPadding: 7 * root.sx
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                coordinateCombo.currentIndex = index
                                coordinateCombo.activated(index)
                                coordinateCombo.popup.close()
                            }
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    x: comboList.width - width
                    width: 20.8 * root.sx
                    contentItem: Rectangle { color: Qt.lighter(grey, 1.15); radius: 0 }
                    background: Rectangle { color: transparentColor }
                }
            }
            background: Rectangle { color: Qt.darker(grey, 1.10); border.color: transparentColor; border.width: 0; radius: 0 }
        }
    }

    component BackGaugeStatusBar: Rectangle {
        objectName: "backgauge-status-bar-view BackGaugeStatusBarView"
        color: transparentColor
        RoundedCorners { anchors.fill: parent; radiusSize: 7; color: lightGrey; bottomLeft: true; bottomRight: true }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 7; color: lightGrey }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 7
            Repeater { model: [{ label: "X1", active: root.appState && root.appState.backGaugeLimitX1 }, { label: "X2", active: root.appState && root.appState.backGaugeLimitX2 }, { label: "R1", active: root.appState && root.appState.backGaugeLimitR1 }, { label: "R2", active: root.appState && root.appState.backGaugeLimitR2 }]; Rectangle { objectName: "limit-indicator-" + modelData.label; Layout.preferredWidth: 28; Layout.fillHeight: true; radius: 7; color: modelData.active ? red : grey; Text { anchors.centerIn: parent; text: modelData.label; color: white; font.pixelSize: 12; font.bold: true } } }
            Item { Layout.fillWidth: true }
            Text { text: root.appState ? root.appState.backGaugeStatus : "Status"; color: ink; font.pixelSize: 12; font.bold: true }
            Rectangle { objectName: "status-label"; Layout.preferredWidth: 21; Layout.fillHeight: true; radius: 7; color: !root.appState || !root.appState.moduleConnected ? grey : (root.appState.backGaugeReady ? green : red); Text { anchors.centerIn: parent; text: ""; color: white; font.pixelSize: 12; font.bold: true } }
        }
    }

    component RoundedCorners: Rectangle {
        property real radiusSize: 7
        property bool topLeft: false
        property bool topRight: false
        property bool bottomLeft: false
        property bool bottomRight: false
        radius: radiusSize

        Rectangle { visible: !topLeft; x: 0; y: 0; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
        Rectangle { visible: !topRight; x: parent.width - parent.radiusSize; y: 0; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
        Rectangle { visible: !bottomLeft; x: 0; y: parent.height - parent.radiusSize; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
        Rectangle { visible: !bottomRight; x: parent.width - parent.radiusSize; y: parent.height - parent.radiusSize; width: parent.radiusSize; height: parent.radiusSize; color: parent.color }
    }

    component CaretGlyph: Shape {
        id: caretShape
        property color iconColor: ink
        ShapePath {
            fillColor: caretShape.iconColor
            strokeWidth: 0
            startX: 0
            startY: 0
            PathLine { x: caretShape.width; y: 0 }
            PathLine { x: caretShape.width / 2; y: caretShape.height }
            PathLine { x: 0; y: 0 }
        }
    }

    component IconGlyph: Shape {
        property string glyph: ""
        property color iconColor: white
        property real size: 16
        readonly property bool arrowGlyph: glyph === "arrow-left" || glyph === "arrow-right" || glyph === "arrow-up" || glyph === "arrow-down"
        width: size
        height: size

        ShapePath {
            strokeColor: parent.arrowGlyph ? parent.iconColor : "transparent"
            strokeWidth: parent.arrowGlyph ? Math.max(2, parent.size * 0.14) : 0
            fillColor: "transparent"
            startX: glyph === "arrow-left" ? size * 0.70 : glyph === "arrow-right" ? size * 0.30 : size * 0.50
            startY: glyph === "arrow-up" ? size * 0.70 : glyph === "arrow-down" ? size * 0.30 : size * 0.50
            PathLine { x: glyph === "arrow-left" ? size * 0.25 : glyph === "arrow-right" ? size * 0.75 : size * 0.50; y: glyph === "arrow-up" ? size * 0.25 : glyph === "arrow-down" ? size * 0.75 : size * 0.50 }
            PathMove { x: glyph === "arrow-left" ? size * 0.25 : glyph === "arrow-right" ? size * 0.75 : glyph === "arrow-up" ? size * 0.50 : size * 0.50; y: glyph === "arrow-up" ? size * 0.25 : glyph === "arrow-down" ? size * 0.75 : size * 0.50 }
            PathLine { x: glyph === "arrow-left" ? size * 0.45 : glyph === "arrow-right" ? size * 0.55 : glyph === "arrow-up" ? size * 0.32 : size * 0.32; y: glyph === "arrow-left" ? size * 0.30 : glyph === "arrow-right" ? size * 0.30 : glyph === "arrow-up" ? size * 0.45 : size * 0.55 }
            PathMove { x: glyph === "arrow-left" ? size * 0.25 : glyph === "arrow-right" ? size * 0.75 : glyph === "arrow-up" ? size * 0.50 : size * 0.50; y: glyph === "arrow-up" ? size * 0.25 : glyph === "arrow-down" ? size * 0.75 : size * 0.50 }
            PathLine { x: glyph === "arrow-left" ? size * 0.45 : glyph === "arrow-right" ? size * 0.55 : glyph === "arrow-up" ? size * 0.68 : size * 0.68; y: glyph === "arrow-left" ? size * 0.70 : glyph === "arrow-right" ? size * 0.70 : glyph === "arrow-up" ? size * 0.45 : size * 0.55 }
        }

        ShapePath {
            fillColor: glyph === "home" ? iconColor : "transparent"
            strokeWidth: 0
            startX: size * 0.10
            startY: size * 0.48
            PathLine { x: size * 0.50; y: size * 0.12 }
            PathLine { x: size * 0.90; y: size * 0.48 }
            PathLine { x: size * 0.78; y: size * 0.48 }
            PathLine { x: size * 0.78; y: size * 0.88 }
            PathLine { x: size * 0.58; y: size * 0.88 }
            PathLine { x: size * 0.58; y: size * 0.62 }
            PathLine { x: size * 0.42; y: size * 0.62 }
            PathLine { x: size * 0.42; y: size * 0.88 }
            PathLine { x: size * 0.22; y: size * 0.88 }
            PathLine { x: size * 0.22; y: size * 0.48 }
            PathLine { x: size * 0.10; y: size * 0.48 }
        }

        ShapePath {
            fillColor: glyph === "pen" ? iconColor : "transparent"
            strokeWidth: 0
            startX: size * 0.18
            startY: size * 0.72
            PathLine { x: size * 0.25; y: size * 0.88 }
            PathLine { x: size * 0.42; y: size * 0.82 }
            PathLine { x: size * 0.84; y: size * 0.40 }
            PathLine { x: size * 0.70; y: size * 0.26 }
            PathLine { x: size * 0.28; y: size * 0.68 }
            PathLine { x: size * 0.18; y: size * 0.72 }
        }
    }
}
