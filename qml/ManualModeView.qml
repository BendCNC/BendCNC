import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "core/Units.js" as Units

Item {
    id: root
    objectName: "manual-mode-view"
    property var appState: null
    readonly property bool metric: appState ? appState.metricUnits === true : false
    function lenFmt(inches) { return metric ? (Number(inches) * 25.4).toFixed(2) : Number(inches).toFixed(4) }
    function isLengthSetting(key) {
        return key === "manualModeSafetyPlaneClearance" || key === "manualModeStartRamPosition"
            || key === "manualModeEndRamPosition" || key === "manualModeMoveToPosition" || key === "jogStep"
    }
    function settingInput(key, value) {
        if (metric && isLengthSetting(key)) {
            var n = Number(value)
            return isFinite(n) ? String(n / 25.4) : value
        }
        return value
    }
    property bool liveTuningOpen: false
    readonly property var liveTuningCaptureItem: liveTuningLoader.status === Loader.Ready
        && liveTuningLoader.item ? liveTuningLoader.item.contentItem : null

    onVisibleChanged: if (!visible) liveTuningOpen = false

    Loader {
        id: liveTuningLoader
        objectName: "manual-thc-live-loader"
        active: root.liveTuningOpen && root.visible
        sourceComponent: Component {
            ThcLiveTuningPanel {
                backend: root.appState ? root.appState.machineControl : null
                offline: !root.appState || root.appState.offlineSimulationEnabled
                approachSpeed: root.appState ? root.appState.bendRamSpeed : 0
                intendedVisible: root.visible && root.liveTuningOpen
                onClosed: root.liveTuningOpen = false
                Component.onCompleted: open()
            }
        }
    }

    readonly property bool controlsEnabled: appState ? appState.pressCanOperate : false
    readonly property bool settingsEnabled: appState && !appState.manualActivationPending
        && !appState.manualLeavePending && !appState.tonnageHoldActive
        && appState.manualModeState !== "DISABLE REQUIRED"
    readonly property color red: "#A82011"
    readonly property color green: "#59A60C"
    readonly property color blue: "#2D83B2"
    readonly property color teal: "#1B7A5A"
    readonly property color charcoal: "#2B2C2B"
    readonly property color grey: "#A8A8A8"
    readonly property color lightGrey: "#E0E0E0"
    readonly property color paper: "#F5F5F5"
    readonly property color ink: "#232323"
    readonly property color muted: "#666666"
    readonly property color white: "#FFFFFF"
    readonly property color orange: "#FFA500"
    readonly property int panelGap: 8
    readonly property int headerHeight: 30
    readonly property int fieldHeight: 40
    readonly property int actionHeight: 48

    function openNumeric(field, title, settingKey) {
        if (!appState)
            return
        appState.openOnScreenKeyboard(field, true, title, function(value) {
            if (!appState.setManualSetting(settingKey, root.settingInput(settingKey, value)))
                field.text = root.settingText(settingKey)
        }, function() { field.text = root.settingText(settingKey) })
    }

    function settingText(key) {
        if (!appState)
            return "0.0000"
        if (key === "manualModeSafetyPlaneClearance")
            return root.lenFmt(appState.manualSafetyPlaneClearance)
        if (key === "manualModeStartRamPosition")
            return root.lenFmt(appState.manualStartRamPosition)
        if (key === "manualModeEndRamPosition")
            return root.lenFmt(appState.manualEndRamPosition)
        if (key === "manualModeMaxTonnagePerRam")
            return appState.manualModeMaxTonnagePerRam.toFixed(1)
        if (key === "manualModeMoveToPosition")
            return root.lenFmt(appState.manualMoveToPosition)
        if (key === "jogStep")
            return root.lenFmt(appState.manualJogStep)
        return "0.0000"
    }

    function toggleNativeManualMode() {
        if (!appState)
            return
        if (appState.manualModeEnabled || appState.manualActivationPending) {
            appState.deactivateManualMode()
            return
        }
        if (appState.safetyPopupsEnabled) {
            appState.showConfirmation(
                qsTr("WARNING: MANUAL MODE ACTIVATION"),
                qsTr("Manual mode permits direct ram movement. Verify the temporary tonnage limit, safety clearance, tooling, workpiece, and machine area. Only trained operators may proceed."),
                function() { appState.activateManualMode() },
                function() {})
            appState.popupButtonText = qsTr("I UNDERSTAND & AGREE")
            return
        }
        appState.activateManualMode()
    }

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: grey

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.panelGap
            spacing: root.panelGap

            ManualModeStatePanel {
                Layout.fillWidth: true
                Layout.minimumHeight: 64
                Layout.preferredHeight: 64
                Layout.maximumHeight: 64
            }

            // Designer v9 rows: left 88 + 296 + 144, right 88 + 218 + 98 + 52 + 56 (+ gaps) = 544.
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 544
                Layout.preferredHeight: 544
                Layout.maximumHeight: 544
                spacing: root.panelGap

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: root.panelGap

                    CompactFieldPanel {
                        objectName: "panel-set-temp-tonnage-limit"
                        Layout.preferredHeight: 88
                        title: qsTr("TEMPORARY TONNAGE LIMIT")
                        label: qsTr("Max tonnage / ram")
                        settingKey: "manualModeMaxTonnagePerRam"
                        valueText: root.appState ? root.appState.manualModeMaxTonnagePerRam.toFixed(1) : "12.5"
                        unit: qsTr("T")
                    }
                    StrokeOperationPanel {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 296
                    }
                    ServiceMenuRow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 144
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: root.panelGap

                    // Same 88 px height as TEMPORARY TONNAGE LIMIT (Designer v9).
                    // Right column: 88 + 218 + 98 + 52 + 56 + 4 * 8 = 544.
                    TonnageHoldPanel { Layout.fillWidth: true; Layout.preferredHeight: 88; Layout.minimumHeight: 88; Layout.maximumHeight: 88 }
                    ManualJogStepPanel { Layout.fillWidth: true; Layout.preferredHeight: 218; Layout.minimumHeight: 218; Layout.maximumHeight: 218 }
                    ManualMoveToPanel { Layout.fillWidth: true; Layout.preferredHeight: 98; Layout.minimumHeight: 98; Layout.maximumHeight: 98 }
                    ActionButton {
                        objectName: "button-thc-live-fine-tune"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        Layout.minimumHeight: 52
                        Layout.maximumHeight: 52
                        label: qsTr("PID CALIBRATION")
                        detail: qsTr("Dynamic Dual-Ram and Tonnage Balance")
                        baseColor: teal
                        onClicked: root.liveTuningOpen = true
                    }
                    ActionButton {
                        objectName: "button-manual-continuous-jog"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        Layout.minimumHeight: 56
                        Layout.maximumHeight: 56
                        label: qsTr("MANUAL CONTINUOUS JOG")
                        detail: qsTr("-Y · Safety button operated")
                        baseColor: red
                        controlEnabled: root.controlsEnabled
                        onClicked: if (root.appState) root.appState.manualAction("continuous-down")
                    }
                }
            }
            Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
        }
    }

    component Header: Rectangle {
        property string title: ""
        property color headerColor: blue
        objectName: "header label-title"
        Layout.fillWidth: true
        Layout.minimumHeight: root.headerHeight
        Layout.preferredHeight: root.headerHeight
        Layout.maximumHeight: root.headerHeight
        radius: 7
        color: headerColor
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.radius
            color: parent.color
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            text: parent.title
            color: white
            font.pixelSize: 14
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    component PanelBody: Rectangle {
        objectName: "manual-subcard-body"
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 7
        color: lightGrey
        // Square the shared edge with Header; only the outer bottom corners
        // stay rounded. This also works on the press's older Qt runtime.
        Rectangle {
            objectName: "manual-subcard-body-top"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.radius
            color: parent.color
        }
    }

    component NumericField: TextField {
        id: field
        property string unit: ""
        property string settingKey: ""
        // Not "displayText": that would shadow TextInput.displayText.
        property string formattedValue: ""
        objectName: "measurement-text-field text-box label-unit"
        Layout.fillWidth: true
        Layout.minimumWidth: 110
        Layout.preferredHeight: root.fieldHeight
        Layout.minimumHeight: root.fieldHeight
        readOnly: !root.settingsEnabled
        selectByMouse: true
        horizontalAlignment: TextInput.AlignRight
        verticalAlignment: TextInput.AlignVCenter
        font.pixelSize: 15
        font.bold: true
        color: ink
        Binding {
            target: field
            property: "text"
            value: field.formattedValue
            when: !field.activeFocus
            restoreMode: Binding.RestoreBindingOrValue
        }
        rightPadding: unit.length > 0 ? 38 : 8
        background: Rectangle {
            radius: 4
            color: field.readOnly ? "#ECECEC" : white
            border.color: field.activeFocus ? blue : "#B7B7B7"
            border.width: field.activeFocus ? 2 : 1
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: field.unit
                color: ink
                font.pixelSize: 14
                font.bold: true
            }
        }
        onEditingFinished: {
            if (!readOnly && activeFocus && root.appState
                    && !root.appState.setManualSetting(settingKey, root.settingInput(settingKey, text)))
                text = root.settingText(settingKey)
        }
        Accessible.name: settingKey
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: if (!field.readOnly)
                root.openNumeric(field,
                    qsTr("ENTER %1").arg(field.settingKey.replace(/([A-Z])/g, " $1").toUpperCase()),
                    field.settingKey)
        }
    }

    component CompactFieldPanel: ColumnLayout {
        property string title: ""
        property string label: ""
        property string valueText: ""
        property string settingKey: ""
        property string unit: ""
        spacing: 0
        Layout.fillWidth: true
        Header { title: parent.title; headerColor: blue }
        PanelBody {
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Text { text: parent.parent.parent.label; Layout.fillWidth: true; color: ink; font.pixelSize: 14; font.bold: true }
                NumericField {
                    objectName: "manual-setting-" + parent.parent.parent.settingKey
                    formattedValue: parent.parent.parent.valueText
                    settingKey: parent.parent.parent.settingKey
                    unit: parent.parent.parent.unit
                    Layout.preferredWidth: 132
                    Layout.maximumWidth: 152
                }
            }
        }
    }

    component StrokeOperationPanel: ColumnLayout {
        objectName: "panel-manual-stroke-operation"
        spacing: 0
        Header { title: qsTr("PEDAL STROKE OPERATION"); headerColor: red }
        PanelBody {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 6
                    columnSpacing: 10
                    FieldLabel { title: qsTr("Safety clearance"); detail: qsTr("Above start position") }
                    NumericField { objectName: "manual-setting-safety-clearance"; formattedValue: root.settingText("manualModeSafetyPlaneClearance"); settingKey: "manualModeSafetyPlaneClearance"; unit: root.metric ? "mm" : qsTr("in") }
                    FieldLabel { title: qsTr("Start ram position"); detail: qsTr("Machine coordinate") }
                    NumericField { objectName: "manual-setting-start-position"; formattedValue: root.settingText("manualModeStartRamPosition"); settingKey: "manualModeStartRamPosition"; unit: root.metric ? "mm" : qsTr("in") }
                    FieldLabel { title: qsTr("End ram position"); detail: qsTr("Machine coordinate") }
                    NumericField { objectName: "manual-setting-end-position"; formattedValue: root.settingText("manualModeEndRamPosition"); settingKey: "manualModeEndRamPosition"; unit: root.metric ? "mm" : qsTr("in") }
                    FieldLabel { title: qsTr("Stroke distance"); detail: qsTr("Start to end") }
                    ReadOnlyField { valueText: root.appState ? root.lenFmt(root.appState.manualStrokeDistance) : "0.0001"; unit: root.metric ? "mm" : qsTr("in") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    TogglePanel {
                        objectName: "manual-repeat-stroke"
                        Layout.preferredWidth: 140
                        Layout.maximumWidth: 140
                        title: qsTr("Repeat")
                        active: root.appState ? root.appState.manualRepeatStroke : false
                        onClicked: if (root.appState) root.appState.manualAction("toggle-repeat-stroke")
                    }
                    ActionButton {
                        objectName: "button-run-manual-stroke"
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.actionHeight
                        label: qsTr("RUN PEDAL STROKE")
                        baseColor: green
                        controlEnabled: root.controlsEnabled
                        onClicked: if (root.appState) root.appState.manualAction("stroke")
                    }
                }
            }
        }
    }

    component FieldLabel: ColumnLayout {
        id: fieldLabel
        property string title: ""
        property string detail: ""
        Layout.fillWidth: true
        spacing: 1
        Text { text: fieldLabel.title; color: ink; font.pixelSize: 14; font.bold: true }
        Text { text: fieldLabel.detail; color: muted; font.pixelSize: 12; visible: text.length > 0 }
    }

    component ReadOnlyField: Rectangle {
        property string valueText: ""
        property string unit: ""
        objectName: "measurement-text-field disabled"
        Layout.fillWidth: true
        Layout.preferredHeight: root.fieldHeight
        Layout.minimumHeight: root.fieldHeight
        radius: 4
        color: "#ECECEC"
        border.color: "#B7B7B7"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            Text { text: parent.parent.valueText; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; color: ink; font.pixelSize: 15; font.bold: true }
            Text { text: parent.parent.unit; color: ink; font.pixelSize: 14; font.bold: true }
        }
    }

    component TogglePanel: Rectangle {
        id: togglePanel
        signal clicked()
        property string title: ""
        property bool active: false
        Layout.fillWidth: true
        Layout.preferredHeight: root.actionHeight
        Layout.minimumHeight: root.actionHeight
        radius: 7
        color: "#C7C7C7"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            Text { text: togglePanel.title; Layout.fillWidth: true; color: ink; font.pixelSize: 14; font.bold: true; wrapMode: Text.WordWrap }
            Switch {
                Layout.fillHeight: true
                Layout.minimumWidth: 64
                Layout.preferredWidth: 64
                Layout.maximumWidth: 64
                checked: togglePanel.active
                onClicked: togglePanel.clicked()
            }
        }
    }

    component ActionButton: Button {
        id: actionButton
        property string label: ""
        property string detail: ""
        property color baseColor: charcoal
        property bool controlEnabled: true
        enabled: controlEnabled
        padding: 6
        background: Rectangle {
            radius: 6
            color: !actionButton.enabled ? "#CACACA"
                : actionButton.down ? Qt.darker(actionButton.baseColor, 1.12)
                : actionButton.baseColor
            border.width: actionButton.activeFocus ? 2 : 0
            border.color: ink
        }
        contentItem: ColumnLayout {
            spacing: 1
            Text {
                text: actionButton.label
                color: !actionButton.enabled ? root.ink
                    : (actionButton.baseColor === root.orange ? "#1E1E1E" : root.white)
                font.pixelSize: 14
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: actionButton.detail.length > 0
                text: actionButton.detail
                color: !actionButton.enabled ? root.muted
                    : (actionButton.baseColor === root.orange ? "#2D2D2D" : "#E2E8F0")
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: label
    }

    component ManualModeStatePanel: Rectangle {
        objectName: "manual-mode-state-view ManualModeStateView"
        radius: 7
        color: charcoal
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: qsTr("MANUAL CONTROL"); color: white; font.pixelSize: 15; font.bold: true }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Browse freely · Enable Manual for machine control")
                    color: "#D5D5D5"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                radius: 5
                color: "#414241"
                Text {
                    objectName: "manual-mode-state"
                    anchors.fill: parent
                    anchors.margins: 5
                    text: root.appState ? root.appState.manualModeState : qsTr("DISABLED")
                    color: {
                        if (!root.appState || root.appState.manualModeState === "DISABLED") return "#FFFFFF"
                        if (root.appState.manualModeState === "ENABLED") return "#AEDE80"
                        return "#FFD17A"
                    }
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
            }
            ActionButton {
                objectName: "button-enable-manual-machine"
                Layout.preferredWidth: 164
                Layout.fillHeight: true
                label: root.appState && (root.appState.manualModeEnabled
                    || root.appState.manualActivationPending)
                    ? qsTr("DISABLE MANUAL") : qsTr("ENABLE MANUAL")
                baseColor: root.appState && root.appState.manualModeEnabled ? red : green
                controlEnabled: root.appState && !root.appState.manualLeavePending
                    && !root.appState.tonnageHoldActive
                    && !root.appState.contactProfileActive
                onClicked: root.toggleNativeManualMode()
            }
        }
    }

    component ServiceMenuRow: RowLayout {
        objectName: "manual-measurement-menu manual-service-menu"
        spacing: root.panelGap
        ColumnLayout {
            objectName: "manual-calibration-card"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: 0
            Header { title: qsTr("CALIBRATION & MEASURE"); headerColor: blue }
            PanelBody {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    // The header already names the card; give its line to the
                    // measurement detail when one is present so the 38 px
                    // Designer v9 buttons still fit the 144 px service row.
                    Text { visible: !calibrationDetail.visible; text: qsTr("Die top datum & piece thickness"); color: ink; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    StatusPill {
                        readonly property bool calibrated: root.appState && root.appState.manualDieTopCalibrationValid
                        text: calibrated
                            ? qsTr("Die top: %1 · Calibrated").arg(Units.len(root.appState.manualDieTopCalibration, root.metric, 4))
                            : qsTr("Datum: Not set · Calibration ready")
                        fillColor: calibrated ? "#ECFDF5" : "#F3F4F6"
                        borderColor: calibrated ? "#A7F3D0" : "#D1D5DB"
                        textColor: calibrated ? "#065F46" : "#4B5563"
                    }
                    Text {
                        id: calibrationDetail
                        objectName: "manual-calibration-card-detail"
                        visible: text.length > 0
                        text: {
                            if (!root.appState)
                                return ""
                            var parts = []
                            if (root.appState.manualDieTopCalibrationValid
                                    && root.appState.manualCalibrationReferenceThickness > 0)
                                parts.push(qsTr("Ref %1").arg(Units.len(root.appState.manualCalibrationReferenceThickness, root.metric, 4)))
                            if (root.appState.measuredMaterialThicknessValid)
                                parts.push(qsTr("Program t %1").arg(Units.len(root.appState.measuredMaterialThickness, root.metric, 4)))
                            if (root.appState.measuredThicknessOverrideActive)
                                parts.push(qsTr("RUN OVERRIDE ON"))
                            return parts.join(" · ")
                        }
                        color: muted; font.pixelSize: 11; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton { objectName: "button-die-top-calibration"; Layout.fillWidth: true; Layout.preferredHeight: 38; label: qsTr("CALIBRATE"); baseColor: blue; onClicked: if (root.appState) root.appState.openManualMeasurement("CALIBRATION") }
                        ActionButton { objectName: "button-piece-measurement"; Layout.fillWidth: true; Layout.preferredHeight: 38; label: qsTr("MEASURE"); baseColor: teal; onClicked: if (root.appState) root.appState.openManualMeasurement("MEASUREMENT") }
                    }
                }
            }
        }
        ColumnLayout {
            objectName: "manual-bleed-card"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: 0
            Header { title: qsTr("BLEED HYDRAULICS"); headerColor: "#C25E00" }
            PanelBody {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    Text { text: qsTr("Cylinder air purge protocol"); color: ink; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    StatusPill {
                        text: qsTr("Dual cylinder service wizard")
                        fillColor: "#FFFBEB"
                        borderColor: "#FDE68A"
                        textColor: "#92400E"
                    }
                    ActionButton { objectName: "button-open-bleed-hydraulics"; Layout.fillWidth: true; Layout.preferredHeight: 38; label: qsTr("OPEN"); baseColor: "#C25E00"; onClicked: if (root.appState) root.appState.toolbarAction("bleed") }
                }
            }
        }
    }

    component StatusPill: Rectangle {
        id: statusPill
        property string text: ""
        property color fillColor: "#F3F4F6"
        property color borderColor: "#D1D5DB"
        property color textColor: "#4B5563"
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        Layout.minimumHeight: 24
        radius: 3
        color: fillColor
        border.color: borderColor
        Text {
            anchors.centerIn: parent
            width: parent.width - 8
            text: statusPill.text
            color: statusPill.textColor
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    component TonnageHoldPanel: ColumnLayout {
        objectName: "panel-tonnage-hold panel-tonnage-hold-compact"
        spacing: 0
        Rectangle {
            objectName: "header label-title"
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            Layout.minimumHeight: root.headerHeight
            Layout.maximumHeight: root.headerHeight
            radius: 7
            color: teal
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.radius; color: parent.color }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 5
                Text { text: qsTr("CONSTANT TONNAGE HOLD"); color: white; font.pixelSize: 14; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                Text { text: qsTr("LIVE"); color: "#B2DFDB"; font.pixelSize: 11; font.bold: true }
                Rectangle {
                    objectName: "tonnage-hold-live-pill"
                    Layout.preferredHeight: 20
                    Layout.preferredWidth: liveTonnageText.implicitWidth + 12
                    radius: 3
                    color: "#184E3F"
                    border.color: "#26A69A"
                    Text {
                        id: liveTonnageText
                        anchors.centerIn: parent
                        text: root.appState && root.appState.independentRamTelemetryAvailable ? root.appState.liveTonnage.toFixed(2) + " T" : "— T"
                        color: "#A7F3D0"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }
        PanelBody {
            // Designer v9: Target, PEDAL and AUTO share one 40 px row.
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                RowLayout {
                    Layout.preferredWidth: 120
                    spacing: 6
                    Text { text: qsTr("Target"); color: ink; font.pixelSize: 13; font.bold: true }
                    TextField {
                        id: holdTarget
                        objectName: "tonnage-hold-target"
                        Layout.preferredWidth: 68
                        Layout.preferredHeight: root.fieldHeight
                        font.pixelSize: 15
                        font.bold: true
                        property string formattedValue: root.appState ? root.appState.tonnageHoldTarget.toFixed(1) : "1.0"
                        Binding {
                            target: holdTarget
                            property: "text"
                            value: holdTarget.formattedValue
                            when: !holdTarget.activeFocus
                            restoreMode: Binding.RestoreBindingOrValue
                        }
                        readOnly: !root.settingsEnabled
                        horizontalAlignment: TextInput.AlignRight
                        rightPadding: 22
                        background: Rectangle {
                            radius: 4
                            color: holdTarget.readOnly ? "#ECECEC" : white
                            border.color: holdTarget.activeFocus ? blue : "#B7B7B7"
                            border.width: holdTarget.activeFocus ? 2 : 1
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("T")
                                color: ink
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: if (!holdTarget.readOnly && root.appState) {
                                holdTarget.focus = true
                                root.appState.openOnScreenKeyboard(holdTarget, true,
                                    qsTr("ENTER TARGET TONNAGE"), function(value) {
                                        var target = Number(value)
                                        if (isFinite(target))
                                            root.appState.tonnageHoldTarget = Math.max(0.5, Math.min(24.0, target))
                                        holdTarget.focus = false
                                    }, function() {
                                        holdTarget.focus = false
                                        holdTarget.text = holdTarget.formattedValue
                                    })
                            }
                        }
                    }
                }
                    ActionButton {
                        objectName: "button-tonnage-hold button-tonnage-hold-active"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.fieldHeight
                        label: root.appState && root.appState.tonnageHoldActive ? qsTr("STOP") : qsTr("PEDAL")
                        baseColor: root.appState && root.appState.tonnageHoldActive ? red : teal
                        controlEnabled: root.appState && (root.controlsEnabled || root.appState.tonnageHoldActive)
                        onClicked: if (root.appState) root.appState.manualAction("tonnage-hold")
                    }
                    ActionButton {
                        objectName: "button-automatic-tonnage-hold"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.fieldHeight
                        label: root.appState && root.appState.contactProfileActive
                            ? qsTr("CANCEL") : qsTr("AUTO")
                        baseColor: root.appState && root.appState.contactProfileActive ? red : green
                        controlEnabled: root.appState
                            && (root.appState.contactProfileCanOperate
                                || root.appState.contactProfileActive)
                        onClicked: if (root.appState)
                            root.appState.manualAction("automatic-tonnage-hold")
                    }
                    // Standalone punch SEAT (tool change outside RUN)
                    ActionButton {
                        objectName: "button-standalone-seat"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.fieldHeight
                        readonly property bool seatActive: root.appState ? root.appState.standaloneSeatActive : false
                        label: seatActive ? qsTr("STOP")
                            : (root.appState && root.appState.toolChangeEqualForceSeat ? qsTr("SEAT EQ") : qsTr("SEAT"))
                        baseColor: seatActive ? red : orange
                        controlEnabled: root.appState
                            && (seatActive || root.appState.standaloneSeatAvailable)
                        onClicked: if (root.appState) {
                            if (seatActive) root.appState.stopStandaloneSeat()
                            else root.appState.startStandaloneSeat()
                        }
                    }
                    // Ram leveling: saves the Y1-Y2 skew measured during the seat hold.
                    ActionButton {
                        objectName: "button-ram-level"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: root.fieldHeight
                        label: qsTr("LEVEL")
                        baseColor: orange
                        controlEnabled: root.appState && root.appState.ramLevelAvailable
                        onClicked: if (root.appState) root.appState.applyRamLevel()
                    }
            }
        }
    }

    component ManualJogStepPanel: ColumnLayout {
        objectName: "manual-jog-step-view ManualModeJogStepView"
        spacing: 0
        Header { title: qsTr("MANUAL JOG STEP"); headerColor: charcoal }
        PanelBody {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                // Row 1: step size, compact Repeat pod and field share 38 px.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: qsTr("Step size"); Layout.fillWidth: true; color: ink; font.pixelSize: 13; font.bold: true }
                    Rectangle {
                        objectName: "manual-repeat-jog"
                        Layout.preferredWidth: 116 + Math.max(0, repeatSwitch.implicitWidth - 42)
                        Layout.preferredHeight: 38
                        radius: 4
                        color: "#D6D9DC"
                        border.color: "#B4B8BC"
                        clip: true
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 4
                            Text { text: qsTr("Repeat"); color: ink; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true }
                            Switch {
                                id: repeatSwitch
                                padding: 0
                                Layout.preferredWidth: implicitWidth
                                Layout.alignment: Qt.AlignVCenter
                                checked: root.appState ? root.appState.manualRepeatJog : false
                                onClicked: if (root.appState) root.appState.manualAction("toggle-repeat-jog")
                            }
                        }
                    }
                    NumericField {
                        objectName: "manual-setting-jog-step"
                        formattedValue: root.settingText("jogStep")
                        settingKey: "jogStep"
                        unit: root.metric ? "mm" : qsTr("in")
                        Layout.preferredWidth: 124
                        Layout.maximumWidth: 134
                        Layout.preferredHeight: 38
                        Layout.minimumHeight: 38
                    }
                }
                // Row 2: presets, monospace with a blue highlight on the active step.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    spacing: 6
                    Repeater {
                        model: [0.0005, 0.001, 0.01, 0.1]
                        Rectangle {
                            id: jogPreset
                            required property real modelData
                            readonly property bool selected: root.appState
                                && Math.abs(modelData - root.appState.manualJogStep) < 0.0000001
                            objectName: "manual-jog-preset-" + modelData.toFixed(4)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            radius: 4
                            color: presetArea.pressed ? Qt.darker(selected ? blue : "#374151", 1.12)
                                : selected ? blue : "#374151"
                            border.color: selected ? "#38BDF8" : "#1F2937"
                            border.width: selected ? 1.5 : 1
                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.toFixed(4)
                            Text {
                                anchors.centerIn: parent
                                text: root.lenFmt(jogPreset.modelData)
                                color: white
                                font.pixelSize: 13
                                font.bold: true
                                font.family: "monospace"
                            }
                            MouseArea {
                                id: presetArea
                                anchors.fill: parent
                                onClicked: if (root.appState) root.appState.manualAction("jog-step", jogPreset.modelData)
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ActionButton {
                        objectName: "manual-jog-up"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 44
                        label: qsTr("↑ +Y · RAM UP")
                        detail: qsTr("Retract")
                        baseColor: orange
                        controlEnabled: root.controlsEnabled
                        onClicked: if (root.appState) root.appState.manualAction("jog-up")
                    }
                    ActionButton {
                        objectName: "manual-jog-down"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 44
                        label: qsTr("↓ -Y · RAM DOWN")
                        detail: qsTr("Safety button operated")
                        baseColor: orange
                        controlEnabled: root.controlsEnabled
                        onClicked: if (root.appState) root.appState.manualAction("jog-down")
                    }
                }
            }
        }
    }

    component ManualMoveToPanel: ColumnLayout {
        objectName: "manual-mode-move-to-view ManualModeMoveToView"
        spacing: 0
        Header { title: qsTr("MOVE TO · SAFETY BUTTON OPERATED"); headerColor: charcoal }
        PanelBody {
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                FieldLabel { title: qsTr("Y position"); detail: qsTr("Machine coordinate") }
                NumericField {
                    objectName: "manual-setting-move-to-position"
                    formattedValue: root.settingText("manualModeMoveToPosition")
                    settingKey: "manualModeMoveToPosition"
                    unit: root.metric ? "mm" : qsTr("in")
                    Layout.preferredWidth: 124
                    Layout.maximumWidth: 134
                    Layout.preferredHeight: 38
                    Layout.minimumHeight: 38
                }
                ActionButton {
                    objectName: "button-run"
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 38
                    label: qsTr("RUN")
                    baseColor: orange
                    controlEnabled: root.controlsEnabled
                    onClicked: if (root.appState) root.appState.manualAction("move-to", root.appState.manualMoveToPosition)
                }
            }
        }
    }
}
