import QtQuick
import QtQuick.Layouts

Rectangle {
    id: toolBar
    objectName: "toolbar ToolBar LogoView ModuleConnectionView MachineConnectionView logo logo-placeholder logo-image box title-bold title-lighter by title-image element element-name device-connection-view panel-connected label-no-connection"

    color: "#E8E8E8"
    implicitWidth: 1366
    implicitHeight: 50

    readonly property color green: "#59A60C"
    readonly property color grey: "#A8A8A8"
    readonly property color orange: "#D97706"
    readonly property color red: "#A82011"
    readonly property color ink: "#232323"
    property var appState: null

    // Match the right-hand content column, including its 10 px inset.
    LayoutMetrics { id: metrics }
    readonly property int connectionGroupWidth: metrics.columnRightWidth
    readonly property int connectionGap: 8
    readonly property int connectionWidth: Math.floor((connectionGroupWidth - connectionGap) / 2)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 5
        anchors.bottomMargin: 5
        spacing: 7

        // Punch and die stack of the active setup phase (selected CAD bend,
        // else the selected program bend, else the first CAD bend).
        Item {
            id: stackView
            objectName: "logo LogoView.fxml logo-placeholder toolbar-tool-stack"
            Layout.preferredWidth: metrics.columnLeftWidth
            Layout.minimumWidth: metrics.columnLeftWidth
            Layout.maximumWidth: metrics.columnLeftWidth
            Layout.preferredHeight: 38
            readonly property var bend: {
                var s = toolBar.appState
                if (!s) return null
                // Active program: follows the selected/executing RUN bend.
                var prog = s.programBends || []
                var i = Number(s.selectedRunBend)
                if (i >= 0 && i < prog.length)
                    return prog[i]
                if (s.selectedBend && s.selectedBend.punchSegmentWidths)
                    return s.selectedBend
                return prog.length > 0 ? prog[0] : null
            }
            readonly property var punchWidths: bend && bend.punchSegmentWidths ? bend.punchSegmentWidths : []
            readonly property var dieWidths: bend && bend.dieSegmentWidths ? bend.dieSegmentWidths : []
            function sum(a) { var t = 0; for (var i = 0; i < a.length; i++) t += Number(a[i]) || 0; return t }
            readonly property real punchTotal: sum(punchWidths)
            readonly property real dieTotal: sum(dieWidths)
            readonly property real required: bend
                ? (Number(bend.width) || Number(bend.widthValue) || Number(bend.lengthIn) || 0) : 0
            readonly property real supportWidth: 33.0
            readonly property real span: Math.max(punchTotal, dieTotal, required, supportWidth)
            readonly property real stationOffset: bend ? (Number(bend.toolingStationOffsetIn) || 0) : 0
    // Material centre on the bed: planner coverage when known (stationYmm is a
    // band-frame shift and misplaces notch-split/wider bands).
    readonly property real bendCenter: bend && bend.toolingBendCenterIn !== null && bend.toolingBendCenterIn !== undefined
        && isFinite(Number(bend.toolingBendCenterIn)) ? Number(bend.toolingBendCenterIn) : -stationOffset
            // Absolute table positions (0 = table centre) of the active stack
            // plus every side-by-side station already installed.
            function placed(kind) {
                var out = []
                if (!bend) return out
                var widths = kind === "die" ? dieWidths : punchWidths
                var total = sum(widths)
                var start = Number(kind === "die" ? bend.dieSegmentStartIn : bend.punchSegmentStartIn)
                var x = (isFinite(start) ? start : -total / 2) + stationOffset
                for (var i = 0; i < widths.length; i++) {
                    out.push({ x: x, w: Number(widths[i]) || 0, active: true }); x += Number(widths[i]) || 0
                }
                var co = bend.toolingCoStations || []
                for (var c = 0; c < co.length; c++) {
                    var cw = (kind === "die" ? co[c].dieWidths : co[c].punchWidths) || []
                    var cx = Number(kind === "die" ? co[c].dieStartIn : co[c].punchStartIn) + stationOffset
                    for (var k = 0; k < cw.length; k++) {
                        out.push({ x: cx, w: Number(cw[k]) || 0, active: false }); cx += Number(cw[k]) || 0
                    }
                }
                return out
            }
            readonly property var punchPlaced: placed("punch")
            readonly property var diePlaced: placed("die")
            opacity: punchWidths.length > 0 || dieWidths.length > 0 ? 1 : 0

            Rectangle {
                anchors.fill: parent
                color: "#D6D9DD"
                radius: 7
                border.color: "#B8BDC4"
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.fillHeight: true
                    radius: 4
                    color: toolBar.ink
                    Column {
                        anchors.centerIn: parent
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "STACK"; color: "#CBD5E1"; font.pixelSize: 11; font.bold: true }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: stackView.bend ? "S" + (Math.round(Number(stackView.bend.toolingPhaseIndex) || 0) + 1) : "--"
                            color: "white"; font.pixelSize: 14; font.bold: true
                        }
                    }
                }

                Column {
                    id: stackRows
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2

                    Repeater {
                        model: [
                            { label: "PUNCH", widths: stackView.punchWidths, placed: stackView.punchPlaced, total: stackView.punchTotal,
                              shortage: !!(stackView.bend && (stackView.bend.punchInventoryShortage || stackView.bend.punchUnsupported)), fill: "#334155" },
                            { label: "DIE", widths: stackView.dieWidths, placed: stackView.diePlaced, total: stackView.dieTotal,
                              shortage: !!(stackView.bend && (stackView.bend.dieInventoryShortage || stackView.bend.dieUnsupported)), fill: "#64748B" }
                        ]
                        delegate: Row {
                            id: stackRow
                            required property var modelData
                            width: stackRows.width
                            height: (stackRows.height - stackRows.spacing) / 2
                            spacing: 6
                            Text {
                                width: 36; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: stackRow.modelData.label; font.pixelSize: 11; font.bold: true; color: toolBar.ink
                            }
                            Item {
                                id: track
                                width: stackRow.width - 36 - 64 - 2 * stackRow.spacing
                                height: stackRow.height
                                readonly property real pxPerIn: width / stackView.span
                                Repeater {
                                    model: stackRow.modelData.placed
                                    delegate: Rectangle {
                                        id: segment
                                        required property var modelData
                                        // Mirrored about the table centre: operator view (matches LIVE 3D).
                                        x: track.width / 2 - (segment.modelData.x + segment.modelData.w) * track.pxPerIn
                                        width: Math.max(2, segment.modelData.w * track.pxPerIn - 1)
                                        height: track.height
                                        radius: 2
                                        color: stackRow.modelData.fill
                                        opacity: segment.modelData.active ? 1 : 0.55
                                        Text {
                                            anchors.centerIn: parent
                                            visible: segment.width > 14
                                            text: (toolBar.appState && toolBar.appState.metricUnits) ? String(Math.round(Number(segment.modelData.w) * 25.4)) : String(Number(segment.modelData.w))
                                            color: "white"; font.pixelSize: 11; font.bold: true
                                        }
                                    }
                                }
                                // Bend contact area, drawn over the segments so it stays
                                // visible when it is shorter than the stack.
                                Rectangle {
                                    visible: stackView.required > 0
                                    width: stackView.required * track.pxPerIn
                                    height: parent.height + 2
                                    y: -1
                                    x: track.width / 2 + stackView.bendCenter * track.pxPerIn - width / 2
                                    color: "#33F59E0B"; border.color: "#F59E0B"; border.width: 2; radius: 3
                                }
                                // 33 in holder limits: pieces outside overhang the machine.
                                Repeater {
                                    model: [-1, 1]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 2; height: track.height + 2; y: -1
                                        color: "#DC2626"
                                        x: track.width / 2 + modelData * stackView.supportWidth / 2 * track.pxPerIn - 1
                                    }
                                }
                            }
                            Text {
                                width: 64; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: stackRow.modelData.widths.length ? ((toolBar.appState && toolBar.appState.metricUnits) ? (stackRow.modelData.total * 25.4).toFixed(1) + " mm" : stackRow.modelData.total.toFixed(2) + " in") : "--"
                                font.pixelSize: 11; font.bold: true
                                color: stackRow.modelData.shortage ? toolBar.red : toolBar.ink
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        ConnectionElement {
            objectName: "device-connection-view module-connection-view"
            prefix: "BG"
            title: "BG"
            status: toolBar.appState ? toolBar.appState.moduleToolbarState : "DISCONNECTED"
            controllerState: toolBar.appState ? toolBar.appState.backGaugeStatus : "UNKNOWN"
            readyName: toolBar.appState ? toolBar.appState.moduleName : qsTr("BACK GAUGE")
            homed: toolBar.appState ? toolBar.appState.backGaugeHomed : false
            disconnectEnabled: toolBar.appState ? toolBar.appState.moduleConnected : false
            onConnectRequested: if (toolBar.appState) toolBar.appState.setConnection("module", true)
            onDisconnectRequested: if (toolBar.appState) toolBar.appState.setConnection("module", false)
            Layout.preferredWidth: toolBar.connectionWidth
            Layout.minimumWidth: toolBar.connectionWidth
            Layout.maximumWidth: toolBar.connectionWidth
            Layout.preferredHeight: 38
            Layout.minimumHeight: 38
            Layout.maximumHeight: 38
        }

        ConnectionElement {
            objectName: "device-connection-view machine-connection-view"
            prefix: "BEND"
            title: "BEND"
            status: toolBar.appState ? toolBar.appState.machineToolbarState : "DISCONNECTED"
            controllerState: toolBar.appState ? toolBar.appState.machineStatus : "UNKNOWN"
            readyName: toolBar.appState ? toolBar.appState.machineName : qsTr("LS-BEND")
            homed: toolBar.appState ? (toolBar.appState.offlineSimulationEnabled
                || (toolBar.appState.machineControl && toolBar.appState.machineControl.pressHomed)) : false
            disconnectEnabled: toolBar.appState ? toolBar.appState.machineConnected : false
            onConnectRequested: if (toolBar.appState) toolBar.appState.setConnection("machine", true)
            onDisconnectRequested: if (toolBar.appState) toolBar.appState.setConnection("machine", false)
            Layout.preferredWidth: toolBar.connectionWidth
            Layout.minimumWidth: toolBar.connectionWidth
            Layout.maximumWidth: toolBar.connectionWidth
            Layout.preferredHeight: 38
            Layout.minimumHeight: 38
            Layout.maximumHeight: 38
        }
    }

    component ConnectionElement: Item {
        id: connectionElement
        implicitWidth: toolBar.connectionWidth
        implicitHeight: 38
        property string prefix: "BG"
        property string title: ""
        property string status: "DISCONNECTED"
        property string controllerState: "UNKNOWN"
        property string readyName: ""
        property bool homed: false
        property bool disconnectEnabled: false
        readonly property bool connectEnabled: status === "DISCONNECTED" || status === "FAULTED"
        readonly property bool controllerAlarm: status === "READY_WITH_ALARM"

        readonly property string labelText: {
            if (status === "READY" || controllerAlarm)
                return readyName
            if (status === "DISCONNECTED")
                return qsTr("CONNECT")
            return status.replace(/_/g, " ")
        }

        readonly property string value: prefix + " · " + labelText

        readonly property color baseColor: {
            if (status === "FAULTED" || controllerAlarm || (status === "READY" && !homed))
                return "#A82011"
            if (status === "READY")
                return "#167A00"
            if (status === "CONNECTING" || status === "INITIALIZING"
                    || status === "RESETTING" || status === "DISCONNECTING")
                return "#D97706"
            return "#525866"
        }

        readonly property color borderColor: {
            if (status === "FAULTED" || controllerAlarm || (status === "READY" && !homed))
                return "#DC2626"
            if (status === "READY")
                return "#38A116"
            if (status === "CONNECTING" || status === "INITIALIZING"
                    || status === "RESETTING" || status === "DISCONNECTING")
                return "#F59E0B"
            return "#6B7280"
        }

        signal connectRequested()
        signal disconnectRequested()

        // Keep invisible element-name for objectName query compatibility
        Item { objectName: "element-name"; visible: false }

        Rectangle {
            id: pillContainer
            objectName: "panel-connected"
            anchors.fill: parent
            radius: 8
            color: primaryMouse.containsMouse && connectionElement.connectEnabled
                ? Qt.lighter(connectionElement.baseColor, 1.15)
                : connectionElement.baseColor
            border.color: connectionElement.borderColor
            border.width: 1

            MouseArea {
                id: primaryMouse
                objectName: "connection-primary-action"
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: connectionElement.connectEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: connectionElement.connectEnabled
                onClicked: connectionElement.connectRequested()
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 8

                // Recessed Dark Prefix Badge [BG] / [BEND]
                Rectangle {
                    Layout.preferredWidth: connectionElement.prefix === "BG" ? 38 : 54
                    Layout.fillHeight: true
                    radius: 5
                    color: "#181A1E"

                    Text {
                        anchors.centerIn: parent
                        text: connectionElement.prefix
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 12
                    }
                }

                // Center Status Label
                Text {
                    text: connectionElement.labelText
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                }

                // Disconnect / Alarm Action Button
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter
                    radius: 13
                    color: disconnectMouse.pressed ? "#66000000"
                        : (disconnectMouse.containsMouse ? "#4D000000" : "#26000000")
                    border.color: "#40FFFFFF"
                    border.width: 1
                    opacity: connectionElement.disconnectEnabled ? 1.0 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: connectionElement.controllerAlarm ? "!" : "✕"
                        color: "#FFFFFF"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: disconnectMouse
                        objectName: "connection-disconnect-action"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: connectionElement.disconnectEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: connectionElement.disconnectEnabled
                        onClicked: connectionElement.disconnectRequested()
                    }
                }
            }
        }
    }
}
