pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // Modal geometry: fixed 950 × 600 per BendCNC operational standard
    width: 950
    height: 600
    radius: 12
    clip: true
    color: colPaper
    border.color: colOutline
    border.width: 1

    // -------------------------------------------------------------------------
    // BendCNC Production Color Palette
    // -------------------------------------------------------------------------
    readonly property color colRed: "#A82011"
    readonly property color colGreen: "#59A60C"
    readonly property color colGreenBg: "#EBF7E5"
    readonly property color colBlue: "#2D83B2"
    readonly property color colBlueBg: "#EBF4F9"
    readonly property color colCharcoal: "#2B2C2B"
    readonly property color colCharcoalRaised: "#3F403F"
    readonly property color colPaper: "#F5F5F5"
    readonly property color colCardBg: "#FFFFFF"
    readonly property color colCardMuted: "#EAEAEA"
    readonly property color colInk: "#232323"
    readonly property color colGrey: "#A8A8A8"
    readonly property color colOutline: "#B8B8B8"
    readonly property color colDivider: "#D3D3D3"
    readonly property color colAmber: "#D97706"
    readonly property color colAmberBg: "#FEF3C7"

    // Header color variation: "BLUE" (operational default) or "RED" (production standard)
    property string headerTheme: "BLUE" // "BLUE" | "RED"
    readonly property color headerColor: headerTheme === "RED" ? colRed : colBlue

    // -------------------------------------------------------------------------
    // Operational Mode: Unified "MEASURE" (default) or "CALIBRATE" (tooling recalibration)
    // -------------------------------------------------------------------------
    property string operationalMode: "MEASURE" // "MEASURE" | "CALIBRATE"

    // Telemetry Properties
    property bool telemetryReady: true
    property real ramPositionY1: 1.3750
    property real ramPositionY2: 1.3750
    property real ramPositionMean: 1.3750
    property real ramPositionSkew: Math.abs(ramPositionY1 - ramPositionY2)

    property real ramLoadY1: 0.500
    property real ramLoadY2: 0.500
    property real liveTonnage: ramLoadY1 + ramLoadY2
    property real tonnageHoldTarget: 1.000
    // MEASURE: the TARGET card sets the measuring tonnage (0.5–1.0 T) while
    // idle. AUTO is a fixed 1.00 T profile, so it is unavailable below that.
    property bool measurementTonnageEditable: false
    property bool autoAvailable: true

    // Dual-Cylinder Balance Metrics (Position & Force)
    readonly property real posBalanceRatio: {
        if (!telemetryReady) return 0.5
        let diff = ramPositionY1 - ramPositionY2
        let ratio = 0.5 + (diff / 0.01) * 0.5
        return Math.max(0.05, Math.min(0.95, ratio))
    }
    readonly property int posBalanceY1Pct: Math.round(posBalanceRatio * 100)
    readonly property int posBalanceY2Pct: 100 - posBalanceY1Pct

    readonly property real forceBalanceRatio: {
        let totalForce = ramLoadY1 + ramLoadY2
        if (!telemetryReady || totalForce < 0.01) return 0.5
        let ratio = ramLoadY1 / totalForce
        return Math.max(0.05, Math.min(0.95, ratio))
    }
    readonly property int forceBalanceY1Pct: Math.round(forceBalanceRatio * 100)
    readonly property int forceBalanceY2Pct: 100 - forceBalanceY1Pct

    // Reference Datum
    property bool dieTopCalibrationValid: true
    property real calibratedDieTop: 1.2500

    // Recalibration Known Shim Size
    property string shimUnit: "INCH" // "INCH" | "MILLIMETER"
    property real shimThicknessInches: 0.1250
    property real shimThicknessMm: 3.1750
    readonly property string shimDisplayString: shimUnit === "MILLIMETER"
        ? shimThicknessMm.toFixed(3)
        : shimThicknessInches.toFixed(4)

    // Piece Measurement Result & Units
    property string measurementUnit: "INCH" // "INCH" | "MILLIMETER"
    readonly property bool metric: measurementUnit === "MILLIMETER"
    property real measurementResult: Number.NaN
    readonly property string measurementDisplayString: {
        if (!isFinite(measurementResult)) return "----"
        if (measurementUnit === "MILLIMETER") {
            return (measurementResult * 25.4).toFixed(3)
        }
        return measurementResult.toFixed(4)
    }
    // Provisional average while frames are accumulated (die top in CALIBRATE,
    // thickness in MEASURE). Shown in blue until the result is final.
    property real liveValue: Number.NaN
    readonly property bool liveValueShown: !isFinite(measurementResult) && isFinite(liveValue)
    readonly property string bigResultText: {
        if (operationalMode === "CALIBRATE") {
            if (liveValueShown) return lenFmtUnit(liveValue)
            return dieTopCalibrationValid ? lenFmtUnit(calibratedDieTop) : "----"
        }
        if (liveValueShown)
            return measurementUnit === "MILLIMETER" ? (liveValue * 25.4).toFixed(3) : liveValue.toFixed(4)
        return measurementDisplayString
    }

    // Process & Telemetry Stability
    property string measurementStatus: operationalMode === "CALIBRATE" ? "READY TO CALIBRATE" : "READY TO MEASURE"
    property int requiredSamples: 10
    property int qualifiedSamples: 0
    property bool processActive: false
    property real appliedLoadMean: Number.NaN
    property real appliedLoadPeak: Number.NaN
    property int acceptedSamples: 0
    property real acceptedDurationMs: 0
    // Optional convergence acceptance (Settings) and the rule that accepted
    // the last result: "" | CONVERGED | FIXED | TIME LIMIT.
    property bool convergenceEnabled: false
    property int minimumSamples: 30
    property real convergenceTolerance: 0.0002
    property real convergenceSpread: Number.NaN
    property string acceptedCriterion: ""
    readonly property string acceptedCriterionText: acceptedCriterion === "FIXED"
        ? qsTr("FIXED %1").arg(requiredSamples) : acceptedCriterion

    property bool tonnageHoldActive: false
    property bool contactProfileActive: false
    property bool closePending: false

    // Calibration tooling and the ram-to-table opening it derives
    property string toolingText: ""
    property bool toolingValid: false
    readonly property string punchSummaryText: {
        if (!toolingText) return "----"
        var m = toolingText.match(/P\s*([^·]+)/)
        return m ? m[1].trim() : toolingText
    }
    readonly property string dieSummaryText: {
        if (!toolingText) return "----"
        var m = toolingText.match(/D\s*(.+)/)
        return m ? m[1].trim() : ""
    }
    property real openingCurrent: Number.NaN
    property real openingCandidate: Number.NaN
    property string openingState: ""
    property bool openingCanApply: false
    // Opening the running die top would give, while still averaging.
    property real liveOpeningCurrent: Number.NaN
    property real liveOpening: Number.NaN
    readonly property bool liveOpeningShown: operationalMode === "CALIBRATE"
        && openingState === "" && liveValueShown && isFinite(liveOpening)

    // Thin material measured stacked on the calibration reference part
    property bool onReferencePiece: false
    property real referenceThickness: Number.NaN
    property real stackMeasurement: Number.NaN
    property bool programThicknessUsed: false
    // Session-only override of the program thickness by the released measurement.
    property bool thicknessOverrideAvailable: false
    property bool thicknessOverrideActive: false
    readonly property int actionButtonWidth: operationalMode === "MEASURE" ? 166 : 190

    function lenFmt(inches) {
        var n = Number(inches)
        if (!isFinite(n)) return "----"
        return metric ? (n * 25.4).toFixed(3) : n.toFixed(4)
    }
    function lenFmtUnit(inches) {
        return isFinite(Number(inches)) ? lenFmt(inches) + (metric ? " mm" : " in") : "----"
    }

    function lengthText(inches, digitsIn, digitsMm) {
        if (!isFinite(inches)) return "----"
        return measurementUnit === "MILLIMETER"
            ? (inches * 25.4).toFixed(digitsMm) + " mm"
            : inches.toFixed(digitsIn) + " in"
    }

    readonly property string infoLineText: {
        if (operationalMode === "CALIBRATE") {
            if (liveOpeningShown) {
                let liveDelta = isFinite(liveOpeningCurrent)
                    ? liveOpening - liveOpeningCurrent : Number.NaN
                return qsTr("OPENING %1 → %2%3 · LIVE")
                    .arg(lenFmt(liveOpeningCurrent))
                    .arg(lenFmtUnit(liveOpening))
                    .arg(isFinite(liveDelta)
                         ? qsTr(" (Δ %1%2)").arg(liveDelta >= 0 ? "+" : "").arg(lenFmt(liveDelta)) : "")
            }
            if (openingState === "" )
                return toolingValid
                    ? qsTr("Opening = punch + die − die top · saved after calibration")
                    : qsTr("Select punch / die to update the ram-to-table opening")
            if (openingState === "NO TOOLING")
                return qsTr("OPENING NOT UPDATED · no punch / die selected")
            let delta = isFinite(openingCurrent) && isFinite(openingCandidate)
                ? openingCandidate - openingCurrent : Number.NaN
            return qsTr("OPENING %1 → %2%3 · %4")
                .arg(lenFmt(openingCurrent))
                .arg(lenFmtUnit(openingCandidate))
                .arg(isFinite(delta) ? qsTr(" (Δ %1%2)").arg(delta >= 0 ? "+" : "").arg(lenFmt(delta)) : "")
                .arg(openingState)
        }
        if (programThicknessUsed)
            return qsTr("SAVED · bend programs can use %1").arg(lengthText(measurementResult, 4, 3))
        if (onReferencePiece && isFinite(stackMeasurement))
            return qsTr("STACK %1 − REFERENCE %2").arg(lengthText(stackMeasurement, 4, 3))
                .arg(lengthText(referenceThickness, 4, 3))
        if (onReferencePiece)
            return qsTr("Place thin part ON the %1 reference part").arg(lengthText(referenceThickness, 4, 3))
        if (convergenceEnabled)
            return qsTr("Accepts once stable: ≥ %1 frames, mean Δ ≤ %2 (max %3 / 30 s)")
                .arg(minimumSamples).arg(lenFmtUnit(convergenceTolerance)).arg(requiredSamples)
        return qsTr("Averages %1 frames; needs ≥ 30 within 30 s").arg(requiredSamples)
    }

    // Action signals
    signal pedalRequested()
    signal autoRequested()
    signal closeRequested()
    signal editShimRequested()
    signal unitChanged(string unit)
    signal toolingRequested()
    signal referencePieceToggled()
    signal applyOpeningRequested()
    signal useForProgramRequested()
    signal thicknessOverrideToggled()
    signal measurementTonnageRequested()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // =====================================================================
        // HEADER (Height: 80px, radius 12 with squared bottom corners)
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: root.operationalMode === "CALIBRATE" ? root.colCharcoal : root.headerColor
            radius: 12

            // Square bottom corners
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 12
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 16
                spacing: 16

                // Titles adapting to active mode
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        spacing: 8
                        Text {
                            text: root.operationalMode === "CALIBRATE"
                                ? qsTr("DIE TOP CALIBRATION (SETUP)")
                                : qsTr("PART THICKNESS MEASUREMENT")
                            color: "white"
                            font.pixelSize: 23
                            font.bold: true
                        }

                        // Mode tag
                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: modeTagText.implicitWidth + 12
                            radius: 4
                            color: root.operationalMode === "CALIBRATE" ? root.colAmber : "#26FFFFFF"

                            Text {
                                id: modeTagText
                                anchors.centerIn: parent
                                text: root.operationalMode === "CALIBRATE" ? qsTr("SETUP MODE") : qsTr("MEASURE MODE")
                                color: "white"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        text: root.operationalMode === "CALIBRATE"
                            ? qsTr("Dual-cylinder reference datum qualification using known thickness shim")
                            : qsTr("Realtime dual-cylinder contact acquisition & thickness calculation")
                        color: "white"
                        opacity: 0.92
                        font.pixelSize: 14
                    }
                }

                Item { Layout.fillWidth: true }

                // Status chip aligned flush with right cards below
                Rectangle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: 124
                    radius: 14
                    color: "#26FFFFFF"
                    border.color: "white"
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 3.5
                            color: root.telemetryReady ? "#86EFAC" : "#FCA5A5"
                        }
                        Text {
                            text: root.telemetryReady ? qsTr("SENSORS LIVE") : qsTr("OFFLINE")
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }
            }
        }

        // =====================================================================
        // CONTENT AREA (Height: 440px, Margins: 16px)
        // Two-column layout: Left (Telemetry Dynamics) + Right (Unified Workflow)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 12

            // -----------------------------------------------------------------
            // LEFT COLUMN (Width: 520px): RAM DYNAMICS & TONNAGE DISTRIBUTION
            // -----------------------------------------------------------------
            Rectangle {
                Layout.preferredWidth: 520
                Layout.fillHeight: true
                radius: 8
                color: root.colCardBg
                border.color: root.colOutline
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // ---- SECTION 1: RAM ENCODER POSITION ----
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: qsTr("RAM ENCODER POSITION")
                            color: root.colInk
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.5
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: qsTr("UNIT: INCHES [in]")
                            color: root.colGrey
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.4
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 6

                        TelemetryField {
                            tag: qsTr("Y1 AXIS (LEFT)")
                            valueText: root.telemetryReady ? root.lenFmt(root.ramPositionY1) : "----"
                            unitText: root.metric ? qsTr("mm") : qsTr("in")
                            accentColor: root.colBlue
                            badgeText: qsTr("LVDT 1")
                        }

                        TelemetryField {
                            tag: qsTr("Y2 AXIS (RIGHT)")
                            valueText: root.telemetryReady ? root.lenFmt(root.ramPositionY2) : "----"
                            unitText: root.metric ? qsTr("mm") : qsTr("in")
                            accentColor: root.colBlue
                            badgeText: qsTr("LVDT 2")
                        }

                        TelemetryField {
                            tag: qsTr("Y1 / Y2 MEAN")
                            valueText: root.telemetryReady ? root.lenFmt(root.ramPositionMean) : "----"
                            unitText: root.metric ? qsTr("mm") : qsTr("in")
                            accentColor: root.colBlue
                            badgeText: qsTr("AVERAGE")
                        }

                        TelemetryField {
                            tag: qsTr("SKEW |Y1 - Y2|")
                            valueText: root.telemetryReady ? root.lenFmt(root.ramPositionSkew) : "----"
                            unitText: root.metric ? qsTr("mm") : qsTr("in")
                            accentColor: root.ramPositionSkew <= 0.0010 ? root.colGreen : root.colRed
                            badgeText: root.ramPositionSkew <= 0.0010 ? qsTr("PARALLEL") : qsTr("TILT")
                            badgeBg: root.ramPositionSkew <= 0.0010 ? root.colGreenBg : "#FDE8E8"
                            badgeColor: root.ramPositionSkew <= 0.0010 ? root.colGreen : root.colRed
                        }
                    }

                    // ---- DUAL-CYLINDER POSITION BALANCE GAUGE ----
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 5
                        color: "#F8FAFC"
                        border.color: root.colDivider

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: qsTr("POSITION BALANCE")
                                color: root.colCharcoal
                                font.pixelSize: 11
                                font.bold: true
                            }

                            Item {
                                id: posTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: "#E2E8F0"
                                }

                                Rectangle {
                                    id: y1PosBar
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * root.posBalanceRatio
                                    radius: 4
                                    color: root.ramPositionSkew <= 0.0010 ? root.colBlue : root.colRed
                                }

                                Rectangle {
                                    id: y2PosBar
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * (1.0 - root.posBalanceRatio)
                                    radius: 4
                                    color: root.ramPositionSkew <= 0.0010 ? "#5BA2CC" : "#F87171"
                                }

                                Rectangle {
                                    x: Math.max(0, Math.min(parent.width - 2, parent.width * root.posBalanceRatio - 1))
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 2
                                    color: "white"
                                }
                            }

                            Text {
                                text: qsTr("%1% Y1 / %2% Y2").arg(root.posBalanceY1Pct).arg(root.posBalanceY2Pct)
                                color: root.ramPositionSkew <= 0.0010 ? root.colBlue : root.colRed
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: root.colDivider
                    }

                    // ---- SECTION 2: FORCE & TONNAGE DISTRIBUTION ----
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: qsTr("FORCE & TONNAGE DISTRIBUTION")
                            color: root.colInk
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.5
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: qsTr("UNIT: US TONS [T]")
                            color: root.colGrey
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.4
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 6

                        TelemetryField {
                            tag: qsTr("Y1 TONNAGE")
                            valueText: root.telemetryReady ? root.ramLoadY1.toFixed(3) : "----"
                            unitText: qsTr("T")
                            accentColor: root.colGreen
                            badgeText: qsTr("CYL 1")
                        }

                        TelemetryField {
                            tag: qsTr("Y2 TONNAGE")
                            valueText: root.telemetryReady ? root.ramLoadY2.toFixed(3) : "----"
                            unitText: qsTr("T")
                            accentColor: root.colGreen
                            badgeText: qsTr("CYL 2")
                        }

                        TelemetryField {
                            tag: qsTr("TOTAL APPLIED")
                            valueText: root.telemetryReady ? root.liveTonnage.toFixed(3) : "----"
                            unitText: qsTr("T")
                            accentColor: root.colGreen
                            badgeText: qsTr("TOTAL FORCE")
                        }

                        // Interactive Target Force Control (Clearly distinguished from passive sensor readings)
                        Rectangle {
                            id: targetForceCard
                            objectName: "manual-measurement-tonnage-target"
                            property bool tappable: root.measurementTonnageEditable
                            readonly property string valueText: root.tonnageHoldTarget.toFixed(3)
                            readonly property string tag: root.operationalMode === "MEASURE"
                                ? qsTr("MEASURE TARGET") : qsTr("CALIBRATE TARGET")
                            signal tapped()

                            Layout.fillWidth: true
                            Layout.preferredHeight: 58
                            radius: 6
                            color: targetForceMouse.pressed ? root.colBlueBg
                                : (targetForceMouse.containsMouse ? "#E0F2FE"
                                    : (root.measurementTonnageEditable ? "#F0F9FF" : root.colCardBg))
                            border.color: targetForceMouse.containsMouse ? "#0284C7"
                                : (root.measurementTonnageEditable ? "#38BDF8" : root.colDivider)
                            border.width: root.measurementTonnageEditable ? 2 : 1.5

                            MouseArea {
                                id: targetForceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.measurementTonnageEditable
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    targetForceCard.tapped()
                                    root.measurementTonnageRequested()
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: root.operationalMode === "MEASURE"
                                            ? qsTr("MEASURE TARGET")
                                            : qsTr("CALIBRATE TARGET")
                                        color: root.measurementTonnageEditable ? "#0369A1" : root.colInk
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Prominent EDIT affordance button
                                    Rectangle {
                                        Layout.preferredHeight: 16
                                        Layout.preferredWidth: editTargetPill.implicitWidth + 12
                                        radius: 8
                                        color: targetForceMouse.containsMouse ? "#0284C7"
                                            : (root.measurementTonnageEditable ? root.colBlue : root.colPaper)

                                        Text {
                                            id: editTargetPill
                                            anchors.centerIn: parent
                                            text: root.measurementTonnageEditable ? qsTr("EDIT (0.5–1.0 T)") : qsTr("SETPOINT")
                                            color: root.measurementTonnageEditable ? "white" : root.colGrey
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: root.tonnageHoldTarget.toFixed(3)
                                        color: root.measurementTonnageEditable ? "#0284C7" : root.colCharcoal
                                        font.pixelSize: 22
                                        font.bold: true
                                    }

                                    Text {
                                        text: qsTr("T")
                                        color: root.measurementTonnageEditable ? "#0284C7" : root.colGrey
                                        font.pixelSize: 12
                                        font.bold: true
                                        Layout.alignment: Qt.AlignBaseline
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        visible: root.measurementTonnageEditable
                                        text: qsTr("TAP TO SET")
                                        color: targetForceMouse.containsMouse ? "#0284C7" : "#0369A1"
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.3
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }
                        }
                    }

                    // ---- DUAL-CYLINDER FORCE BALANCE GAUGE ----
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 5
                        color: "#F8FAFC"
                        border.color: root.colDivider

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: qsTr("FORCE BALANCE")
                                color: root.colCharcoal
                                font.pixelSize: 11
                                font.bold: true
                            }

                            Item {
                                id: forceTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: "#E2E8F0"
                                }

                                Rectangle {
                                    id: y1ForceBar
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * root.forceBalanceRatio
                                    radius: 4
                                    color: root.colGreen
                                }

                                Rectangle {
                                    id: y2ForceBar
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * (1.0 - root.forceBalanceRatio)
                                    radius: 4
                                    color: "#6DBE20"
                                }

                                Rectangle {
                                    x: Math.max(0, Math.min(parent.width - 2, parent.width * root.forceBalanceRatio - 1))
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 2
                                    color: "white"
                                }
                            }

                            Text {
                                text: qsTr("%1% Y1 / %2% Y2").arg(root.forceBalanceY1Pct).arg(root.forceBalanceY2Pct)
                                color: Math.abs(root.forceBalanceY1Pct - 50) <= 5 ? root.colGreen : root.colRed
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN (Width: 386px): UNIFIED WORKFLOW & METRICS TERMINAL
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // CARD 1: REFERENCE DATUM & RECALIBRATE CONTROLS
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.operationalMode === "CALIBRATE" ? 142 : 116
                    radius: 8
                    color: root.colCardBg
                    border.color: root.operationalMode === "CALIBRATE" ? root.colAmber : root.colOutline
                    border.width: root.operationalMode === "CALIBRATE" ? 1.5 : 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Mode-dependent title row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.operationalMode === "CALIBRATE"
                                    ? qsTr("1. KNOWN SHIM THICKNESS")
                                    : qsTr("1. CALIBRATED DIE TOP REFERENCE")
                                color: root.colInk
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.4
                                elide: Text.ElideRight
                            }

                            // In Calibrate mode: Return to measure quick action
                            Rectangle {
                                visible: root.operationalMode === "CALIBRATE"
                                Layout.preferredHeight: 20
                                Layout.preferredWidth: returnMeasureLabel.implicitWidth + 14
                                radius: 10
                                color: returnMeasureMouse.containsMouse ? root.colGreenBg : "#F8FAFC"
                                border.color: returnMeasureMouse.containsMouse ? root.colGreen : root.colGrey
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "✓"
                                        color: root.colGreen
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        id: returnMeasureLabel
                                        text: qsTr("RETURN TO MEASURE")
                                        color: root.colCharcoal
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    id: returnMeasureMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.operationalMode = "MEASURE"
                                }
                            }

                            // Status badge
                            Rectangle {
                                Layout.minimumWidth: calibStatusText.implicitWidth + 12
                                Layout.preferredHeight: 20
                                Layout.preferredWidth: calibStatusText.implicitWidth + 12
                                radius: 10
                                color: root.operationalMode === "CALIBRATE"
                                    ? root.colAmberBg
                                    : (root.dieTopCalibrationValid ? root.colGreenBg : "#FDE8E8")
                                border.color: root.operationalMode === "CALIBRATE"
                                    ? root.colAmber
                                    : (root.dieTopCalibrationValid ? root.colGreen : root.colRed)
                                border.width: 1

                                Text {
                                    id: calibStatusText
                                    anchors.centerIn: parent
                                    text: root.operationalMode === "CALIBRATE"
                                        ? qsTr("RECALIBRATING")
                                        : (root.dieTopCalibrationValid ? qsTr("CALIBRATED") : qsTr("NOT CALIBRATED"))
                                    color: root.operationalMode === "CALIBRATE"
                                        ? root.colAmber
                                        : (root.dieTopCalibrationValid ? root.colGreen : root.colRed)
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }

                        // Middle Content (in Measure Mode): Shows Active Die Top
                        Rectangle {
                            visible: root.operationalMode === "MEASURE"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            radius: 5
                            color: "#F8FAFC"
                            border.color: root.colDivider
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                                }

                                Text {
                                    text: qsTr("ACTIVE DIE TOP:")
                                    color: root.colCharcoal
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.dieTopCalibrationValid
                                        ? root.lenFmtUnit(root.calibratedDieTop)
                                        : qsTr("NO DATUM")
                                    color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                            }
                        }

                        // Middle Content (in Calibrate Mode): Tactile Editable Shim Thickness Card
                        Rectangle {
                            visible: root.operationalMode === "CALIBRATE"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 6
                            color: shimInputMouse.containsMouse ? "#FEF3C7" : "#FFFFFF"
                            border.color: shimInputMouse.containsMouse ? root.colAmber : "#F59E0B"
                            border.width: 1.5

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Rectangle {
                                    Layout.preferredHeight: 22
                                    Layout.preferredWidth: 22
                                    radius: 4
                                    color: "#FEF3C7"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "#"
                                        color: root.colAmber
                                        font.pixelSize: 13
                                    }
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Text {
                                        text: qsTr("SHIM THICKNESS:")
                                        color: root.colCharcoal
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        text: qsTr("Touch to enter exact size")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    objectName: "manual-known-piece-thickness"
                                    text: root.shimDisplayString
                                    color: root.colInk
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Text {
                                    text: root.shimUnit === "MILLIMETER" ? qsTr("mm") : qsTr("in")
                                    color: root.colAmber
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Rectangle {
                                    Layout.preferredHeight: 22
                                    Layout.preferredWidth: editShimPillText.implicitWidth + 14
                                    radius: 11
                                    color: shimInputMouse.containsMouse ? "#B45309" : root.colAmber

                                    Text {
                                        id: editShimPillText
                                        anchors.centerIn: parent
                                        text: qsTr("EDIT")
                                        color: "white"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            MouseArea {
                                id: shimInputMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editShimRequested()
                            }
                        }

                        // Bottom row (in Measure Mode): thin-part control + recalibrate die top button
                        RowLayout {
                            visible: root.operationalMode === "MEASURE"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            spacing: 6

                            // Thin part control
                            Rectangle {
                                id: auxBtn
                                objectName: "manual-measurement-thin-toggle"
                                readonly property bool auxActive: root.onReferencePiece
                                readonly property bool auxAvailable: !root.processActive
                                    && isFinite(root.referenceThickness)
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                radius: 5
                                opacity: auxAvailable ? 1.0 : 0.55
                                color: auxActive ? root.colBlueBg : "#F8FAFC"
                                border.color: auxActive ? root.colBlue : root.colGrey
                                border.width: auxActive ? 1.5 : 1

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: isFinite(root.referenceThickness)
                                        ? (root.onReferencePiece ? qsTr("✓ THIN PART · ON REF %1") : qsTr("THIN PART · ON REF %1"))
                                            .arg(root.lengthText(root.referenceThickness, 4, 3))
                                        : qsTr("THIN PART: CALIBRATE FIRST")
                                    color: root.colCharcoal
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.3
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: auxBtn.auxAvailable
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.referencePieceToggled()
                                }
                            }

                            // Recalibrate button (switches to CALIBRATE mode)
                            Rectangle {
                                id: recalibBtn
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                radius: 5
                                color: recalibHover.containsMouse ? root.colBlueBg : "#F8FAFC"
                                border.color: recalibHover.containsMouse ? root.colBlue : root.colGrey
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Item { Layout.fillWidth: true }

                                    Item {
                                        Layout.preferredWidth: 12
                                        Layout.preferredHeight: 12

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: "transparent"
                                            border.color: root.colBlue
                                            border.width: 2
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 3
                                            height: 3
                                            radius: 1.5
                                            color: root.colBlue
                                        }
                                    }

                                    Text {
                                        Layout.maximumWidth: recalibBtn.width - 36
                                        text: qsTr("RECALIBRATE DIE TOP")
                                        color: root.colCharcoal
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.3
                                        elide: Text.ElideRight
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                MouseArea {
                                    id: recalibHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.operationalMode = "CALIBRATE"
                                }
                            }
                        }

                        // Bottom content (in Calibrate Mode): Active Installed Tooling Card
                        Rectangle {
                            id: toolingCard
                            visible: root.operationalMode === "CALIBRATE"
                            objectName: "manual-calibration-tooling"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 6
                            color: toolingCardMouse.containsMouse ? "#F1F5F9"
                                : (root.toolingValid ? "#F8FAFC" : root.colAmberBg)
                            border.color: toolingCardMouse.containsMouse ? root.colBlue
                                : (root.toolingValid ? root.colDivider : root.colAmber)
                            border.width: 1.5

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                // Tooling tag
                                Rectangle {
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: toolBadgeLabel.implicitWidth + 8
                                    radius: 4
                                    color: root.toolingValid ? "#E2E8F0" : root.colAmber
                                    Text {
                                        id: toolBadgeLabel
                                        anchors.centerIn: parent
                                        text: qsTr("TOOLING")
                                        color: root.toolingValid ? root.colCharcoal : "white"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                // Punch section
                                RowLayout {
                                    spacing: 3
                                    Text {
                                        text: qsTr("PUNCH:")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        text: root.toolingValid ? root.punchSummaryText : "----"
                                        color: root.colInk
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                Text {
                                    text: "·"
                                    color: root.colDivider
                                    font.bold: true
                                }

                                // Die section
                                RowLayout {
                                    spacing: 3
                                    Text {
                                        text: qsTr("DIE:")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        text: root.toolingValid ? root.dieSummaryText : "----"
                                        color: root.colInk
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Action button: CHANGE / SELECT
                                Rectangle {
                                    Layout.preferredHeight: 22
                                    Layout.preferredWidth: changeToolLabel.implicitWidth + 12
                                    radius: 4
                                    color: root.toolingValid
                                        ? (toolingCardMouse.containsMouse ? root.colBlue : root.colBlueBg)
                                        : root.colAmber
                                    border.color: root.toolingValid ? root.colBlue : root.colAmber
                                    border.width: 1

                                    Text {
                                        id: changeToolLabel
                                        anchors.centerIn: parent
                                        text: root.toolingValid ? qsTr("CHANGE") : qsTr("SELECT TOOLING")
                                        color: root.toolingValid
                                            ? (toolingCardMouse.containsMouse ? "white" : root.colBlue)
                                            : "white"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            MouseArea {
                                id: toolingCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toolingRequested()
                            }
                        }
                    }
                }

                // CARD 2: MEASUREMENT STAGE & TELEMETRY METRICS TERMINAL
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: root.colCardBg
                    border.color: root.colOutline
                    border.width: 1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Status line (Clean 2-element layout: title + status badge)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.operationalMode === "CALIBRATE"
                                    ? qsTr("2. DIE TOP CONTACT ACQUISITION")
                                    : qsTr("2. PART MEASUREMENT")
                                color: root.colInk
                                font.pixelSize: root.operationalMode === "CALIBRATE" ? 11 : 12
                                font.bold: true
                                font.letterSpacing: 0.5
                                elide: Text.ElideRight
                            }

                            // Status badge
                            Rectangle {
                                Layout.minimumWidth: statusText.implicitWidth + 16
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: statusText.implicitWidth + 16
                                radius: 12
                                color: root.processActive ? root.colGreenBg : root.colPaper
                                border.color: root.processActive ? root.colGreen : root.colOutline
                                border.width: 1

                                Text {
                                    id: statusText
                                    anchors.centerIn: parent
                                    text: root.measurementStatus
                                    color: root.processActive ? root.colGreen : root.colCharcoal
                                    font.pixelSize: root.operationalMode === "CALIBRATE" ? 11 : 11
                                    font.bold: true
                                }
                            }
                        }

                        // Prominent Measured Result Readout Box (Generous fixed height to ensure no text clipping)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 98
                            Layout.minimumHeight: 92
                            radius: 6
                            color: "#F8FAFC"
                            border.color: isFinite(root.measurementResult) ? root.colGreen : root.colDivider
                            border.width: isFinite(root.measurementResult) ? 1.5 : 1
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 2

                                // Readout header: Title on left, IN/MM switch on right
                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: root.operationalMode === "CALIBRATE"
                                            ? qsTr("CALCULATED DIE TOP REFERENCE")
                                            : qsTr("MEASURED PART THICKNESS")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        elide: Text.ElideRight
                                    }

                                    // IN / MM Segmented Pill Switch
                                    Rectangle {
                                        Layout.preferredWidth: 84
                                        Layout.preferredHeight: 22
                                        radius: 4
                                        color: root.colPaper
                                        border.color: root.colOutline

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 1

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: 3
                                                color: root.measurementUnit === "INCH" ? root.colBlue : "transparent"

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: qsTr("IN")
                                                    color: root.measurementUnit === "INCH" ? "white" : root.colCharcoal
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }

                                                MouseArea {
                                                    objectName: "manual-known-piece-unit-in"
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.measurementUnit = "INCH"
                                                        root.unitChanged("INCH")
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: 3
                                                color: root.measurementUnit === "MILLIMETER" ? root.colBlue : "transparent"

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: qsTr("MM")
                                                    color: root.measurementUnit === "MILLIMETER" ? "white" : root.colCharcoal
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }

                                                MouseArea {
                                                    objectName: "manual-known-piece-unit-mm"
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.measurementUnit = "MILLIMETER"
                                                        root.unitChanged("MILLIMETER")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Big digital result
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 6

                                    Text {
                                        objectName: "manual-measurement-big-result"
                                        text: root.bigResultText
                                        color: isFinite(root.measurementResult) ? root.colGreen
                                            : (root.liveValueShown ? root.colBlue : root.colCharcoal)
                                        font.pixelSize: 30
                                        font.bold: true
                                    }

                                    Text {
                                        visible: root.operationalMode !== "CALIBRATE"
                                            && (isFinite(root.measurementResult) || root.liveValueShown)
                                        text: root.measurementUnit === "MILLIMETER" ? qsTr("mm") : qsTr("in")
                                        color: root.colBlue
                                        font.pixelSize: 14
                                        font.bold: true
                                        Layout.alignment: Qt.AlignBaseline
                                    }
                                }

                                // Bottom Prompt
                                Text {
                                    objectName: "manual-measurement-result-prompt"
                                    text: root.liveValueShown
                                        ? (root.convergenceEnabled
                                            ? qsTr("CONVERGING %1 · Δ %2 / %3 · LIVE, NOT FINAL")
                                                .arg(root.qualifiedSamples)
                                                .arg(isFinite(root.convergenceSpread)
                                                     ? (root.metric ? (root.convergenceSpread * 25.4).toFixed(5) : root.convergenceSpread.toFixed(5)) : "----")
                                                .arg(root.lenFmtUnit(root.convergenceTolerance))
                                            : qsTr("AVERAGING %1 / %2 · LIVE, NOT FINAL")
                                                .arg(root.qualifiedSamples).arg(root.requiredSamples))
                                        : root.operationalMode === "CALIBRATE"
                                        ? (root.dieTopCalibrationValid
                                            ? qsTr("NEW DIE TOP CALIBRATED & LOCKED")
                                            : qsTr("PRESS PEDAL OR AUTO TO QUALIFY DIE TOP"))
                                        : (isFinite(root.measurementResult)
                                            ? qsTr("ACCURATE THICKNESS STORED")
                                            : (root.processActive
                                                ? qsTr("MEASURING CONTACT POSITION...")
                                                : qsTr("PRESS PEDAL OR AUTO TO MEASURE")))
                                    color: root.liveValueShown ? root.colBlue
                                        : (isFinite(root.measurementResult) || root.dieTopCalibrationValid
                                        ? root.colGreen
                                        : (root.processActive ? root.colBlue : root.colGrey))
                                    font.pixelSize: 11
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Segmented 10-Frame Progress Bar
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("TELEMETRY STABILITY PROGRESS")
                                    color: root.colCharcoal
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    objectName: "manual-measurement-sample-count"
                                    text: root.acceptedCriterion !== "" && root.acceptedSamples > 0
                                        ? qsTr("%1 SAMPLES · %2").arg(root.acceptedSamples)
                                            .arg(root.acceptedCriterionText)
                                        : qsTr("%1 / %2 SAMPLES")
                                            .arg(root.qualifiedSamples)
                                            .arg(root.requiredSamples)
                                    color: (root.acceptedCriterion !== "" && root.acceptedSamples > 0)
                                        || (root.qualifiedSamples === root.requiredSamples && root.requiredSamples > 0)
                                        ? root.colGreen : root.colBlue
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            // 10-segment track (Sleek 14px height)
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                Layout.maximumHeight: 14
                                spacing: 3

                                Repeater {
                                    model: root.requiredSamples > 0 ? Math.min(20, root.requiredSamples) : 10
                                    Rectangle {
                                        required property int index
                                        readonly property real doneSegs: root.requiredSamples > 0 ? root.qualifiedSamples * Math.min(20, root.requiredSamples) / root.requiredSamples : 0
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 14
                                        Layout.maximumHeight: 14
                                        radius: 2
                                        color: index + 1 <= doneSegs
                                            ? root.colGreen
                                            : (root.processActive && index === Math.floor(doneSegs)
                                                ? root.colBlue : "#E2E8F0")
                                        border.color: index + 1 <= doneSegs
                                            ? root.colGreen
                                            : (root.processActive && index === Math.floor(doneSegs)
                                                ? root.colBlue : "#CBD5E1")
                                        border.width: 1
                                    }
                                }
                            }
                        }

                        // Structured Telemetry Diagnostic Metrics Row (Replaces blank white void)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 42
                            Layout.minimumHeight: 38
                            Layout.maximumHeight: 42
                            spacing: 6

                            // Mean Force Metric
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: "#F8FAFC"
                                border.color: root.colDivider

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        text: qsTr("MEAN FORCE")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Text {
                                        text: isFinite(root.appliedLoadMean)
                                            ? root.appliedLoadMean.toFixed(3) + " T"
                                            : "----"
                                        color: root.colCharcoal
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            // Peak Force Metric
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: "#F8FAFC"
                                border.color: root.colDivider

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        text: qsTr("PEAK FORCE")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Text {
                                        text: isFinite(root.appliedLoadPeak)
                                            ? root.appliedLoadPeak.toFixed(3) + " T"
                                            : "----"
                                        color: root.colCharcoal
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            // Hold Time Metric
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: "#F8FAFC"
                                border.color: root.colDivider

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        text: qsTr("HOLD DURATION")
                                        color: root.colGrey
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Text {
                                        text: root.acceptedDurationMs > 0
                                            ? (root.acceptedDurationMs / 1000).toFixed(1) + " s"
                                            : "----"
                                        color: root.colCharcoal
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }
                        }

                        // Opening update (calibrate) / stack, program use or
                        // averaging rule (measure)
                        Text {
                            objectName: "manual-measurement-info-line"
                            Layout.fillWidth: true
                            text: root.infoLineText
                            color: root.liveOpeningShown ? root.colBlue
                                : root.operationalMode === "CALIBRATE"
                                && (root.openingState === "REVIEW" || root.openingState === "OUT OF RANGE"
                                    || root.openingState === "FAILED" || root.openingState === "BUSY")
                                ? root.colAmber
                                : (root.openingState === "APPLIED" && root.operationalMode === "CALIBRATE")
                                    || (root.programThicknessUsed && root.operationalMode !== "CALIBRATE")
                                    ? root.colGreen : root.colCharcoal
                            opacity: 0.9
                            font.pixelSize: 11
                            font.bold: root.operationalMode === "CALIBRATE"
                                ? (root.openingState !== "" || root.liveOpeningShown) : root.programThicknessUsed
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }

        // =====================================================================
        // FOOTER (Height: 80px, white background with rounded bottom corners)
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "white"
            radius: 12

            // Square top corners
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 12
                color: parent.color
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: root.colDivider
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: root.operationalMode === "MEASURE" ? 12 : 16

                // CLOSE
                HarmonizedButton {
                    Layout.preferredWidth: root.actionButtonWidth
                    text: root.closePending ? qsTr("STOPPING...") : qsTr("CLOSE")
                    baseColor: root.colCardMuted
                    textColor: root.colCharcoal
                    borderColor: root.colGrey
                    onClicked: root.closeRequested()
                }

                // PEDAL
                HarmonizedButton {
                    Layout.preferredWidth: root.actionButtonWidth
                    text: root.tonnageHoldActive ? qsTr("STOP PEDAL") : qsTr("PEDAL")
                    baseColor: root.tonnageHoldActive ? root.colRed : root.colCharcoal
                    textColor: "white"
                    onClicked: root.pedalRequested()
                }

                // AUTO ACTION (Adapts based on operational mode)
                HarmonizedButton {
                    objectName: "manual-measurement-auto"
                    Layout.preferredWidth: root.actionButtonWidth
                    controlEnabled: root.contactProfileActive || root.autoAvailable
                    text: root.contactProfileActive
                        ? qsTr("CANCEL AUTO")
                        : (root.operationalMode === "CALIBRATE" ? qsTr("AUTO CALIBRATE")
                            : qsTr("AUTO MEASURE"))
                    baseColor: root.contactProfileActive
                        ? root.colRed
                        : (root.operationalMode === "CALIBRATE" ? root.colGreen : root.colBlue)
                    textColor: "white"
                    onClicked: root.autoRequested()
                }

                // CALIBRATE: operator-confirmed opening write.
                // MEASURE: release the measured thickness to bend programs.
                HarmonizedButton {
                    objectName: root.operationalMode === "CALIBRATE"
                        ? "manual-calibration-apply-opening" : "manual-measurement-use-for-program"
                    Layout.preferredWidth: root.actionButtonWidth
                    text: root.operationalMode === "CALIBRATE"
                        ? (root.openingState === "SENT" || root.openingState === "WAITING"
                            ? qsTr("SAVING...") : qsTr("APPLY OPENING"))
                        : (root.programThicknessUsed ? qsTr("IN PROGRAM") : qsTr("USE IN PROGRAM"))
                    controlEnabled: root.operationalMode === "CALIBRATE"
                        ? root.openingCanApply && !root.processActive
                        : isFinite(root.measurementResult) && root.measurementResult > 0
                            && !root.programThicknessUsed && !root.processActive
                    baseColor: root.operationalMode === "CALIBRATE" ? root.colAmber : root.colGreen
                    textColor: "white"
                    onClicked: {
                        if (root.operationalMode === "CALIBRATE")
                            root.applyOpeningRequested()
                        else
                            root.useForProgramRequested()
                    }
                }

                // MEASURE: run programs with the released thickness without
                // editing them (session only).
                HarmonizedButton {
                    objectName: "manual-measurement-override-toggle"
                    visible: root.operationalMode === "MEASURE"
                    Layout.preferredWidth: root.actionButtonWidth
                    text: root.thicknessOverrideActive ? qsTr("t OVERRIDE ON") : qsTr("t OVERRIDE OFF")
                    controlEnabled: (root.thicknessOverrideAvailable || root.thicknessOverrideActive)
                        && !root.processActive
                    baseColor: root.thicknessOverrideActive ? "#C25E00" : root.colCharcoal
                    textColor: "white"
                    onClicked: root.thicknessOverrideToggled()
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: TelemetryField
    // =========================================================================
    component TelemetryField: Rectangle {
        id: fieldCard
        property string tag: ""
        property string valueText: ""
        property string unitText: ""
        property color accentColor: root.colBlue
        property string badgeText: ""
        property color badgeBg: root.colPaper
        property color badgeColor: root.colGrey
        property bool tappable: false
        signal tapped()

        Layout.fillWidth: true
        Layout.preferredHeight: 58
        radius: 6
        color: fieldMouse.pressed ? root.colBlueBg : root.colCardBg
        border.color: accentColor
        border.width: tappable ? 2.5 : 1.5

        MouseArea {
            id: fieldMouse
            anchors.fill: parent
            enabled: fieldCard.tappable
            cursorShape: Qt.PointingHandCursor
            onClicked: fieldCard.tapped()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: fieldCard.tag
                    color: root.colInk
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: fieldCard.badgeText.length > 0
                    Layout.preferredHeight: 14
                    Layout.preferredWidth: badgeLabel.implicitWidth + 8
                    radius: 3
                    color: fieldCard.badgeBg

                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: fieldCard.badgeText
                        color: fieldCard.badgeColor
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: fieldCard.valueText
                    color: fieldCard.accentColor
                    font.pixelSize: 22
                    font.bold: true
                }

                Text {
                    text: fieldCard.unitText
                    color: root.colGrey
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignBaseline
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: HarmonizedButton
    // =========================================================================
    component HarmonizedButton: Rectangle {
        id: btn
        property string text: ""
        property color baseColor: root.colBlue
        property color textColor: "white"
        property color borderColor: "transparent"
        property bool controlEnabled: true
        signal clicked()

        Layout.preferredWidth: 190
        Layout.preferredHeight: 50
        radius: 6
        opacity: controlEnabled ? 1.0 : 0.4
        color: btnMouse.containsMouse ? Qt.lighter(baseColor, 1.1) : baseColor
        border.color: borderColor
        border.width: borderColor === "transparent" ? 0 : 1

        scale: btnMouse.pressed ? 0.98 : 1.0

        Text {
            anchors.centerIn: parent
            text: btn.text
            color: btn.textColor
            font.pixelSize: 16
            font.bold: true
            font.letterSpacing: 0.5
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            enabled: btn.controlEnabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
