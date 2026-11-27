pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// Presentation only. All command admission and ownership stay in the Popup.
// Designer v9 layout: header with state chip · telemetry column (tonnage
// chart + motor RPM) · LOOP PARAMETERS card with fixed lifecycle actions ·
// amber safety footer with CLOSE. Narrow layouts move the telemetry column
// into the parameter scroll so every value and action remains reachable.
Rectangle {
    id: root
    required property var controller
    required property var history
    readonly property bool wide: width >= 720
    // Notes (ranges, defaults, revisions) are on demand so the parameter
    // card fits without scrolling.
    property bool infoOpen: false
    readonly property int touchHeight: 38
    readonly property color teal: "#10B981"
    readonly property color red: "#EF4444"
    readonly property color blue: "#0284C7"
    readonly property color amber: "#F59E0B"
    readonly property color purple: "#8B5CF6"
    readonly property bool faultState: controller.stopUnconfirmed || controller.tuningError !== ""
    readonly property string stateLabel: controller.stopUnconfirmed ? qsTr("STOP UNCONFIRMED")
        : !controller.transportReady ? qsTr("OFFLINE")
        : controller.tuningError !== "" ? qsTr("TUNING ERROR")
        : controller.pending ? qsTr("PENDING")
        : controller.holding ? qsTr("HOLDING")
        : controller.ownsOperation ? (controller.commissioningState || qsTr("OWNED"))
        : controller.idle ? qsTr("IDLE")
        : (controller.commissioningState || qsTr("NOT READY"))
    readonly property color stateColor: faultState ? red
        : !controller.transportReady ? "#94A3B8"
        : controller.pending ? amber
        : controller.holding ? teal
        : controller.ownsOperation ? "#38BDF8"
        : "#94A3B8"
    readonly property color stateFill: faultState ? "#38181A"
        : controller.holding ? "#1A3828" : "#1E293B"
    color: "#0F141C"
    radius: 12

    component PanelButton: Button {
        id: button
        property color actionColor: "#1E293B"
        property color borderColor: "#334155"
        Layout.minimumHeight: root.touchHeight
        Layout.preferredHeight: root.touchHeight
        Layout.minimumWidth: root.touchHeight
        padding: 4
        font.pixelSize: 11
        font.bold: true
        background: Rectangle {
            radius: 6
            color: !button.enabled ? "#1A202C"
                : button.down ? Qt.darker(button.actionColor, 1.2) : button.actionColor
            border.width: button.activeFocus ? 2 : 1
            border.color: button.activeFocus ? "#38BDF8" : button.borderColor
        }
        contentItem: Text {
            text: button.text
            color: button.enabled ? "#FFFFFF" : "#64748B"
            font: button.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Accessible.name: text
    }

    component Chip: Rectangle {
        id: chip
        property alias text: chipText.text
        property color accent: "#334155"
        property color textColor: "#94A3B8"
        property bool dot: false
        implicitHeight: 20
        implicitWidth: chipRow.implicitWidth + 12
        radius: 4
        color: "#18202F"
        border.color: accent
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Rectangle { visible: chip.dot; Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: chip.accent }
            Text { id: chipText; color: chip.textColor; font.bold: true; font.pixelSize: 11 }
        }
    }

    component CardTitle: RowLayout {
        id: cardTitle
        property string text
        property color accent: "#38BDF8"
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: cardTitle.text
            color: "#E2E8F0"
            font.bold: true
            font.pixelSize: 11
            font.letterSpacing: 0.5
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        anchors.fill: parent
        enabled: !root.controller.confirmationVisible
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 8
                color: "#182333"
                border.color: "#0284C7"
                border.width: 1.5
                Text { anchors.centerIn: parent; text: qsTr("PID"); color: "#38BDF8"; font.bold: true; font.pixelSize: 13 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.maximumWidth: implicitWidth
                        Layout.fillWidth: true
                        text: qsTr("PID CALIBRATION")
                        color: "#FFFFFF"
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 0.5
                        elide: Text.ElideRight
                    }
                    Chip {
                        objectName: "thc-live-state-chip"
                        dot: true
                        text: root.stateLabel
                        accent: root.stateColor
                        color: root.stateFill
                        textColor: "#FFFFFF"
                    }
                    Chip { text: qsTr("AUTO · 1 T") }
                    Chip { text: qsTr("RAM VOLATILE"); accent: "#78350F"; textColor: "#FCD34D" }
                    Item { Layout.fillWidth: true }
                }
                Text {
                    objectName: "thc-live-status"
                    Layout.fillWidth: true
                    color: root.controller.stopUnconfirmed ? "#F87171" : "#94A3B8"
                    font.pixelSize: 11
                    font.bold: root.controller.stopUnconfirmed
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.controller.stopUnconfirmed
                        ? qsTr("STOP UNCONFIRMED — keep the machine stopped; inspect recovery. No automatic Home or restart.")
                        : !root.controller.transportReady ? qsTr("OFFLINE / NO CONTROLLER TRANSPORT — controls disabled.")
                        : root.controller.pending ? qsTr("Request pending — wait for the exact firmware acknowledgement.")
                        : root.controller.tuningError !== "" ? qsTr("Tuning error: %1 · Inspect recovery; no automatic retry.").arg(root.controller.tuningError)
                        : root.controller.ownsOperation ? qsTr("Owner %1 · %2 · Operator lease: 2 s").arg(root.controller.ownerId).arg(root.controller.commissioningState)
                        : root.controller.supported ? qsTr("Capability queried · Safely homed idle or owned HOLD only.")
                        : qsTr("Capability not confirmed — query the controller first. Version 1.3 is not proof.")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            ColumnLayout {
                id: wideTelemetryHost
                objectName: "thc-live-telemetry-wide-host"
                visible: root.wide
                Layout.fillWidth: true
                Layout.preferredWidth: 530
                Layout.fillHeight: true
                spacing: 0
            }

            Rectangle {
                objectName: "thc-live-loop-card"
                Layout.fillWidth: !root.wide
                Layout.preferredWidth: root.wide ? (root.width >= 900 ? 540 : 470) : -1
                Layout.fillHeight: true
                radius: 9
                color: "#141A24"
                border.color: "#273244"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    CardTitle {
                        text: qsTr("PID PARAMETERS")
                        accent: root.purple
                        Chip {
                            objectName: "thc-live-draft-chip"
                            visible: root.controller.draftDirty
                            text: qsTr("UNSAVED DRAFT")
                            color: "#7C2D12"
                            accent: "#EA580C"
                            textColor: "#FED7AA"
                        }
                    }
                    ScrollView {
                        id: bodyScroll
                        objectName: "thc-live-body-scroll"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: bodyScroll.availableWidth
                            spacing: 8

                            ColumnLayout {
                                id: compactTelemetryHost
                                objectName: "thc-live-telemetry-compact-host"
                                visible: !root.wide
                                Layout.fillWidth: true
                                spacing: 0
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width >= 430 ? 2 : 1
                                columnSpacing: 8
                                rowSpacing: 5
                                Repeater {
                                    model: root.controller.fields
                                    Rectangle {
                                        id: fieldCard
                                        required property var modelData
                                        readonly property bool extended: root.controller.extendedRanges
                                        readonly property bool outside: root.controller.outsideOriginalRange(modelData)
                                        readonly property bool changed: root.controller.draftDirty
                                            && root.controller.draft[modelData.key] !== root.controller.requested[modelData.key]
                                        property bool keypadOpen: false
                                        property bool replaceTouchText: true
                                        function touchKey(key) {
                                            let value = replaceTouchText ? "" : extendedInput.text
                                            if (key === "C") value = ""
                                            else if (key === "⌫") value = value.slice(0, -1)
                                            else value += key
                                            replaceTouchText = false
                                            extendedInput.forceActiveFocus()
                                            extendedInput.text = value
                                            root.controller.setDraftText(modelData.key, value)
                                        }
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.minimumWidth: 150
                                        Layout.preferredHeight: fieldColumn.implicitHeight + 8
                                        color: "#0B0F17"
                                        border.color: outside ? root.red : changed ? root.amber : "#1E2838"
                                        radius: 6

                                        ColumnLayout {
                                            id: fieldColumn
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Text { text: fieldCard.modelData.title; color: "#FFFFFF"; font.pixelSize: 11; font.bold: true }
                                                Text {
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignRight
                                                    elide: Text.ElideRight
                                                    readonly property string minimumText: (fieldCard.modelData.minimum / 10000).toFixed(fieldCard.modelData.digits)
                                                    readonly property string maximumText: (fieldCard.modelData.maximum / 10000).toFixed(fieldCard.modelData.digits)
                                                    text: fieldCard.extended
                                                        ? qsTr("Original %1–%2").arg(minimumText).arg(maximumText)
                                                        : qsTr("%1–%2 · step %3").arg(minimumText).arg(maximumText)
                                                            .arg((fieldCard.modelData.step / 10000).toFixed(fieldCard.modelData.digits))
                                                    color: "#64748B"
                                                    font.pixelSize: 11
                                                }
                                            }
                                            // v1: [SpinBox ×4][DEF]; v2: [−][value][+][123][DEF] on one row.
                                            GridLayout {
                                                Layout.fillWidth: true
                                                columns: 5
                                                columnSpacing: 3
                                                rowSpacing: 3
                                                SpinBox {
                                                    id: spin
                                                    visible: !fieldCard.extended
                                                    objectName: "thc-live-" + fieldCard.modelData.key
                                                    Layout.row: 0
                                                    Layout.column: 0
                                                    Layout.columnSpan: 4
                                                    Layout.fillWidth: true
                                                    Layout.minimumHeight: root.touchHeight
                                                    Layout.preferredHeight: root.touchHeight
                                                    enabled: root.controller.canTune && typeof root.controller.draft[fieldCard.modelData.key] === "number"
                                                        && !root.controller.confirmationVisible
                                                    from: fieldCard.modelData.minimum
                                                    to: fieldCard.modelData.maximum
                                                    stepSize: fieldCard.modelData.step
                                                    value: typeof root.controller.draft[fieldCard.modelData.key] === "number"
                                                        ? Math.round(root.controller.draft[fieldCard.modelData.key] * 10000) : from
                                                    editable: false
                                                    textFromValue: function(value, locale) { return (value / 10000).toFixed(fieldCard.modelData.digits) }
                                                    onValueModified: root.controller.setDraftValue(fieldCard.modelData.key, value / 10000)
                                                    leftPadding: root.touchHeight
                                                    rightPadding: root.touchHeight
                                                    contentItem: Text {
                                                        text: typeof root.controller.draft[fieldCard.modelData.key] === "number" ? spin.displayText : qsTr("—")
                                                        color: spin.enabled ? "#FFFFFF" : "#64748B"
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                        font.family: "Monospace"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    background: Rectangle {
                                                        color: "#141A24"
                                                        radius: 4
                                                        border.color: spin.activeFocus ? root.blue : "#2B374A"
                                                    }
                                                    up.indicator: Rectangle {
                                                        x: spin.width - width
                                                        width: root.touchHeight
                                                        height: spin.height
                                                        radius: 4
                                                        color: !spin.enabled ? "#1E293B" : spin.up.pressed ? "#CBD5E1" : "#E2E8F0"
                                                        Text { anchors.centerIn: parent; text: qsTr("+"); color: spin.enabled ? "#0F141C" : "#64748B"; font.pixelSize: 20; font.bold: true }
                                                    }
                                                    down.indicator: Rectangle {
                                                        width: root.touchHeight
                                                        height: spin.height
                                                        radius: 4
                                                        color: !spin.enabled ? "#1E293B" : spin.down.pressed ? "#CBD5E1" : "#E2E8F0"
                                                        Text { anchors.centerIn: parent; text: qsTr("−"); color: spin.enabled ? "#0F141C" : "#64748B"; font.pixelSize: 20; font.bold: true }
                                                    }
                                                    Accessible.name: fieldCard.modelData.title
                                                }
                                                PanelButton {
                                                    visible: fieldCard.extended
                                                    objectName: "thc-live-minus-" + fieldCard.modelData.key
                                                    Layout.row: 0
                                                    Layout.column: 0
                                                    Layout.preferredWidth: root.touchHeight
                                                    text: qsTr("−")
                                                    font.pixelSize: 18
                                                    enabled: root.controller.canTune && !root.controller.confirmationVisible
                                                    actionColor: fieldCard.outside ? "#991B1B" : "#334155"
                                                    Accessible.name: qsTr("Decrease %1").arg(fieldCard.modelData.title)
                                                    onClicked: root.controller.stepDraft(fieldCard.modelData, -1)
                                                }
                                                TextField {
                                                    id: extendedInput
                                                    visible: fieldCard.extended
                                                    objectName: "thc-live-extended-" + fieldCard.modelData.key
                                                    Layout.row: 0
                                                    Layout.column: 1
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 50
                                                    Layout.preferredHeight: root.touchHeight
                                                    enabled: root.controller.canTune && !root.controller.confirmationVisible
                                                    color: "#FFFFFF"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    font.family: "Monospace"
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    selectByMouse: true
                                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                                    Accessible.name: fieldCard.modelData.title
                                                    onTextEdited: root.controller.setDraftText(fieldCard.modelData.key, text)
                                                    background: Rectangle {
                                                        color: "#141A24"
                                                        radius: 4
                                                        border.width: extendedInput.activeFocus ? 2 : 1
                                                        border.color: fieldCard.outside ? root.red : extendedInput.activeFocus ? "#38BDF8" : "#2B374A"
                                                    }
                                                    Binding {
                                                        target: extendedInput
                                                        property: "text"
                                                        when: !extendedInput.activeFocus
                                                        restoreMode: Binding.RestoreNone
                                                        value: root.controller.numericText(root.controller.draft, fieldCard.modelData.key, 6)
                                                    }
                                                }
                                                PanelButton {
                                                    visible: fieldCard.extended
                                                    objectName: "thc-live-plus-" + fieldCard.modelData.key
                                                    Layout.row: 0
                                                    Layout.column: 2
                                                    Layout.preferredWidth: root.touchHeight
                                                    text: qsTr("+")
                                                    font.pixelSize: 18
                                                    enabled: root.controller.canTune && !root.controller.confirmationVisible
                                                    actionColor: fieldCard.outside ? "#991B1B" : "#334155"
                                                    Accessible.name: qsTr("Increase %1").arg(fieldCard.modelData.title)
                                                    onClicked: root.controller.stepDraft(fieldCard.modelData, 1)
                                                }
                                                PanelButton {
                                                    visible: fieldCard.extended
                                                    objectName: "thc-live-keypad-" + fieldCard.modelData.key
                                                    Layout.row: 0
                                                    Layout.column: 3
                                                    Layout.preferredWidth: root.touchHeight
                                                    text: fieldCard.keypadOpen ? qsTr("OK") : qsTr("123")
                                                    Accessible.name: qsTr("Keypad %1 · draft only").arg(fieldCard.modelData.title)
                                                    enabled: root.controller.canTune && !root.controller.confirmationVisible
                                                    onClicked: {
                                                        fieldCard.keypadOpen = !fieldCard.keypadOpen
                                                        fieldCard.replaceTouchText = true
                                                        if (fieldCard.keypadOpen) extendedInput.forceActiveFocus()
                                                    }
                                                }
                                                PanelButton {
                                                    objectName: "thc-live-default-" + fieldCard.modelData.key
                                                    Layout.row: 0
                                                    Layout.column: 4
                                                    Layout.preferredWidth: root.touchHeight
                                                    text: qsTr("DEF")
                                                    font.pixelSize: 11
                                                    enabled: root.controller.canResetDraft
                                                    Accessible.name: qsTr("%1 factory default %2 · draft only")
                                                        .arg(fieldCard.modelData.title)
                                                        .arg(root.controller.numericText(root.controller.factoryDefaults, fieldCard.modelData.key, fieldCard.modelData.digits))
                                                    onClicked: root.controller.resetDraftField(fieldCard.modelData.key)
                                                }
                                            }
                                            GridLayout {
                                                visible: fieldCard.keypadOpen && fieldCard.extended
                                                enabled: root.controller.canTune && !root.controller.confirmationVisible
                                                Layout.fillWidth: true
                                                columns: 3
                                                columnSpacing: 2
                                                rowSpacing: 2
                                                Repeater {
                                                    model: ["7", "8", "9", "4", "5", "6", "1", "2", "3", ".", "0", "⌫", "C"]
                                                    PanelButton {
                                                        required property string modelData
                                                        objectName: "thc-live-key-" + fieldCard.modelData.key + "-" + modelData
                                                        Layout.fillWidth: true
                                                        focusPolicy: Qt.NoFocus
                                                        text: modelData
                                                        onClicked: fieldCard.touchKey(modelData)
                                                    }
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: qsTr("ACK %1 · EFF %2")
                                                    .arg(root.controller.numericText(root.controller.requested, fieldCard.modelData.key, fieldCard.extended ? 6 : fieldCard.modelData.digits))
                                                    .arg(root.controller.numericText(root.controller.effective, fieldCard.modelData.key, fieldCard.extended ? 6 : fieldCard.modelData.digits))
                                                color: "#94A3B8"
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                PanelButton {
                                    objectName: "thc-live-default-all"
                                    Layout.fillWidth: true
                                    text: qsTr("DEFAULT ALL SIX · DRAFT ONLY")
                                    enabled: root.controller.canResetDraft
                                    onClicked: root.controller.resetDraftDefaults()
                                }
                                PanelButton {
                                    objectName: "thc-live-info-toggle"
                                    Layout.preferredWidth: 96
                                    text: root.infoOpen ? qsTr("HIDE INFO") : qsTr("INFO")
                                    onClicked: root.infoOpen = !root.infoOpen
                                }
                            }
                            Text {
                                objectName: "thc-live-default-note"
                                visible: root.infoOpen
                                Layout.fillWidth: true
                                text: root.controller.extendedRanges
                                    ? qsTr("V2 default: 2026-10-31 HOLD sweep set B. Defaults edit only this draft, not firmware. Review, then APPLY SIX.")
                                    : qsTr("Shipped factory snapshot. Defaults edit only this draft, not firmware. Review, then APPLY SIX.")
                                color: "#94A3B8"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                objectName: "thc-live-range-warning"
                                visible: root.infoOpen
                                Layout.fillWidth: true
                                text: root.controller.extendedRanges
                                    ? qsTr("Extended tuning · v2. Nonnegative values, FS > CQ. Six decimals; technical wire ceiling 999999999.999999. Red marks values outside the original ranges; output safety caps remain active.")
                                    : qsTr("Firmware v1 / unconfirmed: original ranges retained. Extended tuning requires firmware v2 and a successful QUERY.")
                                color: "#F87171"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                objectName: "thc-live-revisions"
                                visible: root.infoOpen
                                Layout.fillWidth: true
                                text: qsTr("Requested (ACK-confirmed): revision %1\nEffective telemetry: target revision %2 · effective revision %3 · ramp %4 ms · hold %5")
                                    .arg(root.controller.numericText(root.controller.requested, "revision", 0))
                                    .arg(root.controller.numericText(root.controller.effective, "revision", 0))
                                    .arg(root.controller.numericText(root.controller.effective, "effectiveRevision", 0))
                                    .arg(root.controller.numericText(root.controller.effective, "rampMs", 0))
                                    .arg(root.controller.numericText(root.controller.effective, "hold", 0))
                                color: "#94A3B8"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                objectName: "thc-live-apply-note"
                                visible: root.infoOpen || (!root.controller.draftValid && root.controller.supported)
                                Layout.fillWidth: true
                                text: !root.controller.draftValid && root.controller.supported
                                    ? qsTr("Invalid draft: six finite values within the negotiated firmware/decimal limits required; FS must be strictly greater than CQ.")
                                    : qsTr("Apply sends all six values atomically without resetting demand, I or history. Accepted changes ramp for at least 500 ms in fresh HOLD. ACK is not effective-gain or physical bumpless proof. Rate uses firmware units, not kHz.")
                                color: !root.controller.draftValid && root.controller.supported ? "#F87171" : "#94A3B8"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Text {
                        objectName: "thc-live-action-error"
                        Layout.fillWidth: true
                        visible: root.controller.actionError !== "" || (root.controller.ownerMatches && root.controller.backend.operationError !== "")
                        text: root.controller.actionError || (root.controller.ownerMatches ? String(root.controller.backend.operationError || "") : "")
                        color: "#F87171"
                        font.pixelSize: 11
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }

                    // Two rows: setup (query, apply, start) then release / stop.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 6
                        rowSpacing: 6
                        PanelButton { objectName: "thc-live-query"; Layout.fillWidth: true; Layout.preferredWidth: 1; text: qsTr("QUERY"); enabled: root.controller.canQuery; actionColor: "#334155"; onClicked: root.controller.queryCapability() }
                        PanelButton { objectName: "thc-live-apply"; Layout.fillWidth: true; Layout.preferredWidth: 1; text: qsTr("APPLY SIX"); enabled: root.controller.canApply; actionColor: "#059669"; onClicked: root.controller.applyDraft() }
                        PanelButton { objectName: "thc-live-start"; Layout.fillWidth: true; Layout.preferredWidth: 2; Layout.columnSpan: 2; text: qsTr("CONTINUOUS AUTO 1 T"); enabled: root.controller.canStart; actionColor: root.blue; onClicked: root.controller.requestStart() }
                        PanelButton { objectName: "thc-live-release"; Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.columnSpan: 2; text: qsTr("RELEASE"); enabled: root.controller.ownsOperation && root.controller.surfaceActive; actionColor: "#475569"; onClicked: root.controller.releaseOwned() }
                        PanelButton { objectName: "thc-live-stop"; Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.columnSpan: 2; text: qsTr("STOP / CANCEL"); enabled: root.controller.ownsOperation; actionColor: "#DC2626"; onClicked: root.controller.cancelOwned() }
                    }
                }
            }
        }

        Rectangle {
            objectName: "thc-live-safety-footer"
            Layout.fillWidth: true
            Layout.preferredHeight: footerRow.implicitHeight + 6
            radius: 7
            color: "#181410"
            border.color: "#78350F"
            RowLayout {
                id: footerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 3
                spacing: 8
                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 9
                    color: root.amber
                    Text { anchors.centerIn: parent; text: "!"; color: "#181410"; font.bold: true; font.pixelSize: 12 }
                }
                Text {
                    objectName: "thc-live-safety-warning"
                    Layout.fillWidth: true
                    text: qsTr("RAM-only: reboot resets tuning. Continuous removes only the normal HOLD observation timeout. Approach 45 s, acquisition 60 s, release 40 s and safety/watchdogs remain. Sampled 5 T is NOT a guaranteed ceiling.")
                    color: "#FDE68A"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                PanelButton {
                    objectName: "thc-live-close"
                    Layout.preferredWidth: 100
                    text: qsTr("CLOSE · Esc")
                    actionColor: "#334155"
                    onClicked: root.controller.close()
                }
            }
        }
    }

    // One telemetry column: beside the parameters when wide, inside the
    // parameter scroll when narrow (never duplicated objectNames).
    ColumnLayout {
        id: telemetryColumn
        objectName: "thc-live-telemetry-column"
        parent: root.wide ? wideTelemetryHost : compactTelemetryHost
        Layout.fillWidth: true
        Layout.fillHeight: root.wide
        spacing: 10
        ThcTonnageChart {
            Layout.fillWidth: true
            Layout.fillHeight: root.wide
            Layout.minimumHeight: 180
            Layout.preferredHeight: 232
            history: root.history
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            Layout.minimumHeight: 150
            color: "#141A24"
            border.color: "#273244"
            radius: 9
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                CardTitle {
                    text: qsTr("MOTOR RPM TELEMETRY · MEASURED")
                    accent: root.teal
                    Chip {
                        objectName: "thc-live-rpm-sync"
                        readonly property bool known: typeof root.history.rpmDelta === "number" && isFinite(root.history.rpmDelta)
                        text: qsTr("SYNC Δ %1 RPM").arg(root.controller.numericText({ value: root.history.rpmDelta }, "value", 0))
                        color: !known ? "#18202F" : root.history.rpmDelta <= 15 ? "#064E3B" : "#78350F"
                        accent: !known ? "#334155" : root.history.rpmDelta <= 15 ? root.teal : root.amber
                        textColor: !known ? "#94A3B8" : root.history.rpmDelta <= 15 ? "#6EE7B7" : "#FCD34D"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    Repeater {
                        model: ["Y1", "Y2"]
                        Rectangle {
                            id: motorCard
                            required property string modelData
                            readonly property bool leftCylinder: modelData === "Y1"
                            readonly property var rpm: leftCylinder ? root.history.rpmY1 : root.history.rpmY2
                            readonly property color accent: leftCylinder ? root.teal : root.blue
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: "#0B0F17"
                            border.color: "#1E2838"
                            radius: 7
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: motorCard.leftCylinder ? qsTr("MOTOR Y1 · LEFT CYLINDER") : qsTr("MOTOR Y2 · RIGHT CYLINDER")
                                    color: motorCard.accent
                                    font.bold: true
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    objectName: "thc-live-rpm-" + motorCard.modelData.toLowerCase()
                                    Layout.fillWidth: true
                                    text: qsTr("%1 RPM").arg(root.controller.numericText({ value: motorCard.rpm }, "value", 0))
                                    color: "#FFFFFF"
                                    font.pixelSize: 22
                                    font.bold: true
                                    font.family: "Monospace"
                                }
                                // Visual 0–3000 RPM scale only; not a controller limit.
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: "#1E293B"
                                    Rectangle {
                                        width: typeof motorCard.rpm === "number" && isFinite(motorCard.rpm)
                                            ? Math.min(parent.width, Math.max(0, parent.width * Math.abs(motorCard.rpm) / 3000)) : 0
                                        height: parent.height
                                        radius: 3
                                        color: motorCard.accent
                                    }
                                }
                                Text {
                                    objectName: "thc-live-motor-unavailable-" + motorCard.modelData.toLowerCase()
                                    Layout.fillWidth: true
                                    text: qsTr("Target — · Temp — · Torque —\nNot available from controller")
                                    color: "#94A3B8"
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }
        }
        Text {
            objectName: "thc-live-diagnostics"
            Layout.fillWidth: true
            text: qsTr("TH_CTRL (informative): force %1 T · request %2 IPM · commanded velocity %3 IPM\nP %4 · I %5 · D %6 · ha %7 = learned HOLD authority (NOT bootstrap). Velocity is NOT measured speed. No physical band success is asserted.")
                .arg(root.controller.numericText(root.controller.diagnostics, "force", 3))
                .arg(root.controller.numericText(root.controller.diagnostics, "request", 4))
                .arg(root.controller.numericText(root.controller.diagnostics, "velocity", 4))
                .arg(root.controller.numericText(root.controller.diagnostics, "p", 4))
                .arg(root.controller.numericText(root.controller.diagnostics, "i", 4))
                .arg(root.controller.numericText(root.controller.diagnostics, "d", 4))
                .arg(root.controller.numericText(root.controller.diagnostics, "ha", 4))
            color: "#94A3B8"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    // Local confirmation cannot be suppressed by global popup preferences.
    Rectangle {
        anchors.fill: parent
        visible: root.controller.confirmationVisible
        color: "#0F141C"
        border.color: "#EF4444"
        border.width: 3
        radius: 9
        MouseArea { anchors.fill: parent; onClicked: {} }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            Text { Layout.fillWidth: true; text: qsTr("CONFIRM CONTINUOUS AUTO 1 T"); color: "#F87171"; font.pixelSize: 20; font.bold: true; wrapMode: Text.WordWrap }
            ScrollView {
                id: confirmationScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Text {
                    width: confirmationScroll.availableWidth
                    text: qsTr("This starts real ram movement using isolated recovery. Verify tooling, workpiece, machine area and supervision. HOLD continues only after controller qualification. Keep this panel visible and foreground: closing, navigation or losing foreground stops lease renewal and cancels ONLY this V53 owner. A sampled 5 T threshold is not a guaranteed force ceiling. Backend safety admission remains authoritative.")
                    color: "#E2E8F0"
                    font.pixelSize: 18
                    wrapMode: Text.WordWrap
                }
            }
            RowLayout {
                Layout.fillWidth: true
                PanelButton { objectName: "thc-live-confirm-back"; Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: 48; text: qsTr("BACK — DO NOT START"); onClicked: root.controller.confirmationVisible = false }
                PanelButton { objectName: "thc-live-confirm-start"; Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: 48; text: qsTr("I CONFIRM — START 1 T"); enabled: root.controller.confirmationVisible && root.controller.canStart; actionColor: "#DC2626"; onClicked: root.controller.confirmStart() }
            }
        }
    }
}
