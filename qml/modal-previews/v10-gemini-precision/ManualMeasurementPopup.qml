import QtQuick

Item {
    id: root
    ModalMetrics { id: modalMetrics }
    objectName: "manual-measurement-popup"
    property var appState: null
    visible: appState ? appState.manualMeasurementVisible : false
    anchors.fill: parent
    focus: visible
    // Below MachinePopupLayer (9000) and MachineAlarmPopupLayer (9100): the
    // AUTO hold confirmation and any alarm raised while measuring must be
    // reachable without closing Calibrate / Measure.
    z: 8900
    property bool toolingPickerOpen: false

    // Tooling library used to resolve punch/die heights for the opening.
    DataStore { id: toolingStore }

    function refreshCalibrationTooling() {
        if (!appState)
            return
        toolingStore.punches = toolingStore.loadPersistentJson("punches.json", "data/current/punches.json", [])
        toolingStore.dies = toolingStore.loadPersistentJson("dies.json", "data/current/dies.json", [])
        appState.resolveManualCalibrationTooling(toolingStore.punches, toolingStore.dies)
    }

    onVisibleChanged: {
        toolingPickerOpen = false
        if (visible)
            refreshCalibrationTooling()
    }

    function toolingSummary() {
        if (!appState || !appState.manualCalibrationToolingValid)
            return ""
        return qsTr("P %1 · D %2 in")
            .arg(appState.manualCalibrationPunchHeight.toFixed(3))
            .arg(appState.manualCalibrationDieHeight.toFixed(3))
    }

    function openKnownThicknessKeyboard(field) {
        if (!appState)
            return
        var keyboardTarget = field && field.text !== undefined ? field : dialog
        appState.openOnScreenKeyboard(keyboardTarget, true, qsTr("ENTER KNOWN PIECE SIZE"),
            function(value) {
                if (!appState.setManualKnownPieceThickness(value,
                                                            appState.manualKnownPieceUnit))
                    keyboardTarget.text = root.knownPieceDisplayText()
            }, function() { keyboardTarget.text = root.knownPieceDisplayText() })
    }

    // Keyboard target for the measuring tonnage (the keyboard reads .text).
    QtObject {
        id: tonnageKeyboardTarget
        property string text: ""
    }

    function openMeasurementTonnageKeyboard() {
        if (!appState || (appState.manualMeasurementMode !== "MEASUREMENT"
                          && appState.manualMeasurementMode !== "CALIBRATION")
                || appState.manualMeasurementProcessActive)
            return false
        tonnageKeyboardTarget.text = appState.manualMeasurementTonnage.toFixed(2)
        return appState.openOnScreenKeyboard(tonnageKeyboardTarget, true,
            qsTr("MEASURING TONNAGE (0.5–1.0 T)"),
            function(value) { appState.setManualMeasurementTonnage(value) },
            function() {}, true)
    }

    function knownPieceDisplayText() {
        if (!appState)
            return "0.1250"
        return appState.manualKnownPieceDisplayValue.toFixed(
            appState.manualKnownPieceUnit === "MILLIMETER" ? 3 : 4)
    }

    Keys.onEscapePressed: function(event) {
        event.accepted = true
        if (appState)
            appState.closeManualMeasurement()
    }

    Rectangle { anchors.fill: parent; color: "#A6000000" }
    MouseArea { anchors.fill: parent }

    MeasurementModal {
        id: dialog
        objectName: "manual-measurement-dialog"
        width: modalMetrics.operationalWidth
        height: modalMetrics.operationalHeight
        anchors.centerIn: parent
        headerTheme: "BLUE"
        operationalMode: root.appState && root.appState.manualMeasurementMode === "CALIBRATION"
            ? "CALIBRATE" : "MEASURE"
        telemetryReady: root.appState && root.appState.manualMeasurementTelemetryReady
        ramPositionY1: root.appState ? root.appState.ramPositionY1 : 0
        ramPositionY2: root.appState ? root.appState.ramPositionY2 : 0
        ramPositionMean: root.appState ? root.appState.manualMeasurementRamMean : 0
        ramLoadY1: root.appState ? root.appState.ramLoadY1 : 0
        ramLoadY2: root.appState ? root.appState.ramLoadY2 : 0
        liveTonnage: root.appState ? root.appState.liveTonnage : 0
        tonnageHoldTarget: root.appState ? root.appState.manualMeasurementTargetTonnage : 0
        measurementTonnageEditable: root.appState !== null
            && (root.appState.manualMeasurementMode === "MEASUREMENT"
                || root.appState.manualMeasurementMode === "CALIBRATION")
            && !root.appState.manualMeasurementProcessActive
        dieTopCalibrationValid: root.appState && root.appState.manualDieTopCalibrationValid
        calibratedDieTop: root.appState ? root.appState.manualDieTopCalibration : 0
        shimUnit: root.appState ? root.appState.manualKnownPieceUnit : "INCH"
        shimThicknessInches: root.appState ? root.appState.manualKnownPieceThickness : 0
        shimThicknessMm: shimThicknessInches * 25.4
        property string text: root.knownPieceDisplayText()
        measurementUnit: root.appState ? root.appState.manualKnownPieceUnit : "INCH"
        measurementResult: root.appState ? root.appState.manualMeasurementResult : Number.NaN
        liveValue: root.appState ? root.appState.manualMeasurementRunningValue : Number.NaN
        measurementStatus: root.appState ? root.appState.manualMeasurementStatus : qsTr("READY")
        requiredSamples: root.appState ? root.appState.manualMeasurementRequiredSamples : 10
        qualifiedSamples: root.appState ? root.appState.manualMeasurementQualifiedSamples : 0
        processActive: root.appState && root.appState.manualMeasurementProcessActive
        appliedLoadMean: root.appState ? root.appState.manualMeasurementAcceptedLoadMean : Number.NaN
        appliedLoadPeak: root.appState ? root.appState.manualMeasurementAcceptedLoadPeak : Number.NaN
        acceptedSamples: root.appState ? root.appState.manualMeasurementAcceptedSamples : 0
        acceptedDurationMs: root.appState ? root.appState.manualMeasurementAcceptedDurationMs : 0
        convergenceEnabled: root.appState && root.appState.manualMeasurementConvergenceActive
        minimumSamples: root.appState ? root.appState.manualMeasurementMinimumSamples : 30
        convergenceTolerance: root.appState ? root.appState.manualMeasurementConvergenceTolerance : 0.0002
        convergenceSpread: root.appState ? root.appState.manualMeasurementConvergenceSpread : Number.NaN
        acceptedCriterion: root.appState ? root.appState.manualMeasurementAcceptedCriterion : ""
        liveOpeningCurrent: root.appState ? root.appState.manualCalibrationCurrentOpening : Number.NaN
        liveOpening: root.appState ? root.appState.manualCalibrationLiveOpening : Number.NaN
        tonnageHoldActive: root.appState && root.appState.tonnageHoldActive
        contactProfileActive: root.appState && root.appState.contactProfileActive
        closePending: root.appState && root.appState.manualMeasurementClosePending
        toolingText: root.toolingSummary()
        toolingValid: root.appState && root.appState.manualCalibrationToolingValid
        openingCurrent: root.appState ? root.appState.manualCalibrationOpeningPrevious : Number.NaN
        openingCandidate: root.appState ? root.appState.manualCalibrationOpeningCandidate : Number.NaN
        openingState: root.appState ? root.appState.manualCalibrationOpeningState : ""
        openingCanApply: root.appState && root.appState.manualCalibrationOpeningCanApply
        onReferencePiece: root.appState && root.appState.manualMeasurementOnReferencePiece
        referenceThickness: root.appState ? root.appState.manualCalibrationReferenceThickness : Number.NaN
        stackMeasurement: root.appState ? root.appState.manualMeasurementStackResult : Number.NaN
        programThicknessUsed: root.appState && root.appState.manualMeasurementUsedForProgram
        thicknessOverrideAvailable: !!root.appState && root.appState.measuredMaterialThicknessValid
            && !root.appState.runActive && !root.appState.runSimulatedRun
        thicknessOverrideActive: !!root.appState && root.appState.measuredThicknessOverrideActive

        Binding {
            target: dialog
            property: "operationalMode"
            value: root.appState && root.appState.manualMeasurementMode === "CALIBRATION"
                ? "CALIBRATE" : "MEASURE"
            when: root.appState !== null
            restoreMode: Binding.RestoreBindingOrValue
        }

        onOperationalModeChanged: {
            if (!root.appState)
                return
            const requested = dialog.operationalMode === "CALIBRATE"
                ? "CALIBRATION" : "MEASUREMENT"
            if (root.appState.manualMeasurementMode !== requested)
                root.appState.switchManualMeasurementMode(requested)
        }
        onEditShimRequested: root.openKnownThicknessKeyboard(dialog)
        onUnitChanged: function(unit) { if (root.appState) root.appState.setManualKnownPieceUnit(unit) }
        onPedalRequested: if (root.appState) {
            if (root.appState.tonnageHoldActive)
                root.appState.stopManualMeasurementProcess()
            else
                root.appState.startManualMeasurementProcess("PEDAL")
        }
        onAutoRequested: if (root.appState) {
            if (root.appState.contactProfileActive)
                root.appState.stopManualMeasurementProcess()
            else
                root.appState.startManualMeasurementProcess("AUTO")
        }
        onCloseRequested: if (root.appState) root.appState.closeManualMeasurement()
        onToolingRequested: root.toolingPickerOpen = true
        onReferencePieceToggled: if (root.appState)
            root.appState.setManualMeasurementOnReferencePiece(!root.appState.manualMeasurementOnReferencePiece)
        onApplyOpeningRequested: if (root.appState) root.appState.applyManualCalibrationOpening()
        onUseForProgramRequested: if (root.appState) root.appState.useManualMeasurementForProgram()
        onThicknessOverrideToggled: if (root.appState)
            root.appState.setMeasuredThicknessOverride(!root.appState.measuredThicknessOverrideEnabled)
        onMeasurementTonnageRequested: root.openMeasurementTonnageKeyboard()
    }

    // Punch / die selection for the calibration opening.
    Rectangle {
        objectName: "manual-calibration-tooling-picker"
        visible: root.toolingPickerOpen
        anchors.fill: dialog
        radius: dialog.radius
        color: "#E6000000"
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 80
            height: parent.height - 80
            radius: 10
            color: "#F5F5F5"
            border.color: "#B8B8B8"

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    width: parent.width
                    text: qsTr("CALIBRATION TOOLING · installed punch and die")
                    color: "#232323"
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: qsTr("Opening = punch height + die height − calibrated die top. A wrong selection gives a wrong opening.")
                    color: "#3F403F"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    height: parent.height - 140
                    spacing: 12

                    Repeater {
                        model: [
                            { kind: "PUNCH", title: qsTr("PUNCH"), items: toolingStore.punches,
                              selectedId: root.appState ? root.appState.manualCalibrationPunchId : "" },
                            { kind: "DIE", title: qsTr("DIE"), items: toolingStore.dies,
                              selectedId: root.appState ? root.appState.manualCalibrationDieId : "" }
                        ]
                        delegate: Column {
                            id: toolingColumn
                            required property var modelData
                            width: (parent.width - 12) / 2
                            height: parent.height
                            spacing: 6

                            Text {
                                text: toolingColumn.modelData.title
                                color: "#2D83B2"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            ListView {
                                objectName: "manual-calibration-tooling-" + toolingColumn.modelData.kind.toLowerCase() + "-list"
                                width: parent.width
                                height: parent.height - 26
                                clip: true
                                spacing: 4
                                model: toolingColumn.modelData.items || []
                                delegate: Rectangle {
                                    id: toolingRow
                                    required property var modelData
                                    readonly property bool selected: String(modelData.id) === String(toolingColumn.modelData.selectedId)
                                    width: ListView.view.width
                                    height: 40
                                    radius: 6
                                    color: selected ? "#EBF4F9" : "#FFFFFF"
                                    border.color: selected ? "#2D83B2" : "#D3D3D3"
                                    border.width: selected ? 2 : 1

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.right: heightText.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(toolingRow.modelData.name || toolingRow.modelData.id)
                                        color: "#232323"
                                        font.pixelSize: 12
                                        font.bold: toolingRow.selected
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: heightText
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Number(toolingRow.modelData.heightInch).toFixed(3) + " in"
                                        color: "#3F403F"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: if (root.appState)
                                            root.appState.setManualCalibrationTooling(toolingColumn.modelData.kind,
                                                                                      toolingRow.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    objectName: "manual-calibration-tooling-done"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 200
                    height: 46
                    radius: 6
                    color: "#2D83B2"
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("DONE")
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toolingPickerOpen = false
                    }
                }
            }
        }
    }
}