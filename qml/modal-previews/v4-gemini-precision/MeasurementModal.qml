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
    property real measurementResult: Number.NaN
    readonly property string measurementDisplayString: {
        if (!isFinite(measurementResult)) return "----"
        if (measurementUnit === "MILLIMETER") {
            return (measurementResult * 25.4).toFixed(3)
        }
        return measurementResult.toFixed(4)
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

    property bool tonnageHoldActive: false
    property bool contactProfileActive: false
    property bool closePending: false

    // Action signals
    signal pedalRequested()
    signal autoRequested()
    signal closeRequested()
    signal editShimRequested()
    signal unitChanged(string unit)

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

            Behavior on color { ColorAnimation { duration: 200 } }

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
                                : qsTr("PIECE THICKNESS MEASUREMENT")
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
                                font.pixelSize: 9
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
                            font.pixelSize: 10
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
                            valueText: root.telemetryReady ? root.ramPositionY1.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: root.colBlue
                            badgeText: qsTr("LVDT 1")
                        }

                        TelemetryField {
                            tag: qsTr("Y2 AXIS (RIGHT)")
                            valueText: root.telemetryReady ? root.ramPositionY2.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: root.colBlue
                            badgeText: qsTr("LVDT 2")
                        }

                        TelemetryField {
                            tag: qsTr("Y1 / Y2 MEAN")
                            valueText: root.telemetryReady ? root.ramPositionMean.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: root.colBlue
                            badgeText: qsTr("AVERAGE")
                        }

                        TelemetryField {
                            tag: qsTr("SKEW |Y1 - Y2|")
                            valueText: root.telemetryReady ? root.ramPositionSkew.toFixed(4) : "----"
                            unitText: qsTr("in")
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
                                font.pixelSize: 10
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

                                    Behavior on width {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }

                                Rectangle {
                                    id: y2PosBar
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * (1.0 - root.posBalanceRatio)
                                    radius: 4
                                    color: root.ramPositionSkew <= 0.0010 ? "#5BA2CC" : "#F87171"

                                    Behavior on width {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }

                                Rectangle {
                                    x: Math.max(0, Math.min(parent.width - 2, parent.width * root.posBalanceRatio - 1))
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 2
                                    color: "white"

                                    Behavior on x {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            Text {
                                text: qsTr("%1% Y1 / %2% Y2").arg(root.posBalanceY1Pct).arg(root.posBalanceY2Pct)
                                color: root.ramPositionSkew <= 0.0010 ? root.colBlue : root.colRed
                                font.pixelSize: 10
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
                            font.pixelSize: 10
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

                        TelemetryField {
                            tag: qsTr("TARGET")
                            valueText: root.tonnageHoldTarget.toFixed(3)
                            unitText: qsTr("T")
                            accentColor: root.colBlue
                            badgeText: qsTr("SETPOINT")
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
                                font.pixelSize: 10
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

                                    Behavior on width {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }

                                Rectangle {
                                    id: y2ForceBar
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * (1.0 - root.forceBalanceRatio)
                                    radius: 4
                                    color: "#6DBE20"

                                    Behavior on width {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }

                                Rectangle {
                                    x: Math.max(0, Math.min(parent.width - 2, parent.width * root.forceBalanceRatio - 1))
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 2
                                    color: "white"

                                    Behavior on x {
                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            Text {
                                text: qsTr("%1% Y1 / %2% Y2").arg(root.forceBalanceY1Pct).arg(root.forceBalanceY2Pct)
                                color: Math.abs(root.forceBalanceY1Pct - 50) <= 5 ? root.colGreen : root.colRed
                                font.pixelSize: 10
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

                // CARD 1: REFERENCE DATUM & RECALIBRATE CONTROLS (Height: 114px)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 114
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
                                text: root.operationalMode === "CALIBRATE"
                                    ? qsTr("1. KNOWN PIECE SIZE (SHIM)")
                                    : qsTr("1. CALIBRATED DIE TOP REFERENCE")
                                color: root.colInk
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.4
                            }

                            Item { Layout.fillWidth: true }

                            // Status badge
                            Rectangle {
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
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }

                        // Middle Content: Datum Box (in Measure mode) or Shim Input (in Calibrate mode)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            radius: 5
                            color: "#F8FAFC"
                            border.color: root.operationalMode === "CALIBRATE" ? root.colAmber : root.colDivider
                            border.width: 1

                            // In Measure Mode: Shows Active Die Top
                            RowLayout {
                                visible: root.operationalMode === "MEASURE"
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
                                        ? root.calibratedDieTop.toFixed(4) + " in"
                                        : qsTr("NO DATUM")
                                    color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                            }

                            // In Calibrate Mode: Shows Shim Input Selector
                            RowLayout {
                                visible: root.operationalMode === "CALIBRATE"
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: "⌨"
                                    color: root.colAmber
                                    font.pixelSize: 13
                                }

                                Text {
                                    text: qsTr("SHIM THICKNESS:")
                                    color: root.colCharcoal
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    objectName: "manual-known-piece-thickness"
                                    text: root.shimDisplayString
                                    color: root.colInk
                                    font.pixelSize: 15
                                    font.bold: true
                                }

                                Text {
                                    text: root.shimUnit === "MILLIMETER" ? qsTr("mm") : qsTr("in")
                                    color: root.colAmber
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                enabled: root.operationalMode === "CALIBRATE"
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editShimRequested()
                            }
                        }

                        // Bottom Action Toggle: In-place Recalibrate vs Return to Measurement
                        Rectangle {
                            id: recalibBtn
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 5
                            color: recalibHover.containsMouse
                                ? (root.operationalMode === "CALIBRATE" ? root.colGreenBg : root.colBlueBg)
                                : "#F8FAFC"
                            border.color: recalibHover.containsMouse
                                ? (root.operationalMode === "CALIBRATE" ? root.colGreen : root.colBlue)
                                : root.colGrey
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: root.operationalMode === "CALIBRATE" ? "✓" : "⚙"
                                    color: root.operationalMode === "CALIBRATE" ? root.colGreen : root.colBlue
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Text {
                                    text: root.operationalMode === "CALIBRATE"
                                        ? qsTr("FINISH CALIBRATION & RETURN TO MEASURE")
                                        : qsTr("TOOL CHANGED? RECALIBRATE DIE TOP HERE")
                                    color: root.colCharcoal
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 0.3
                                }
                            }

                            MouseArea {
                                id: recalibHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.operationalMode === "CALIBRATE") {
                                        root.operationalMode = "MEASURE"
                                    } else {
                                        root.operationalMode = "CALIBRATE"
                                    }
                                }
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
                        anchors.margins: 12
                        spacing: 10

                        // Status line (Clean 2-element layout: title + status badge)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: root.operationalMode === "CALIBRATE"
                                    ? qsTr("2. DIE TOP CONTACT ACQUISITION")
                                    : qsTr("2. PIECE MEASUREMENT")
                                color: root.colInk
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 0.5
                            }

                            Item { Layout.fillWidth: true }

                            // Status badge
                            Rectangle {
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
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }

                        // Prominent Measured Result Readout Box (Generous fixed height to ensure no text clipping)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            Layout.minimumHeight: 104
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
                                        text: root.operationalMode === "CALIBRATE"
                                            ? qsTr("CALCULATED DIE TOP REFERENCE")
                                            : qsTr("MEASURED PIECE THICKNESS")
                                        color: root.colGrey
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                    }

                                    Item { Layout.fillWidth: true }

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
                                                    font.pixelSize: 9
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
                                                    font.pixelSize: 9
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
                                        text: root.operationalMode === "CALIBRATE"
                                            ? (root.dieTopCalibrationValid ? root.calibratedDieTop.toFixed(4) + " in" : "----")
                                            : root.measurementDisplayString
                                        color: isFinite(root.measurementResult) ? root.colGreen : root.colCharcoal
                                        font.pixelSize: 30
                                        font.bold: true
                                    }

                                    Text {
                                        visible: root.operationalMode !== "CALIBRATE" && isFinite(root.measurementResult)
                                        text: root.measurementUnit === "MILLIMETER" ? qsTr("mm") : qsTr("in")
                                        color: root.colBlue
                                        font.pixelSize: 14
                                        font.bold: true
                                        Layout.alignment: Qt.AlignBaseline
                                    }
                                }

                                // Bottom Prompt
                                Text {
                                    text: root.operationalMode === "CALIBRATE"
                                        ? (root.dieTopCalibrationValid
                                            ? qsTr("✓ NEW DIE TOP CALIBRATED & LOCKED")
                                            : qsTr("PRESS PEDAL OR AUTO TO QUALIFY DIE TOP"))
                                        : (isFinite(root.measurementResult)
                                            ? qsTr("✓ ACCURATE THICKNESS STORED")
                                            : (root.processActive
                                                ? qsTr("MEASURING CONTACT POSITION...")
                                                : qsTr("PRESS PEDAL OR AUTO TO MEASURE")))
                                    color: isFinite(root.measurementResult) || root.dieTopCalibrationValid
                                        ? root.colGreen
                                        : (root.processActive ? root.colBlue : root.colGrey)
                                    font.pixelSize: 10
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
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("%1 / %2 SAMPLES")
                                        .arg(root.qualifiedSamples)
                                        .arg(root.requiredSamples)
                                    color: root.qualifiedSamples === root.requiredSamples && root.requiredSamples > 0
                                        ? root.colGreen : root.colBlue
                                    font.pixelSize: 10
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
                                    model: root.requiredSamples > 0 ? root.requiredSamples : 10
                                    Rectangle {
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 14
                                        Layout.maximumHeight: 14
                                        radius: 2
                                        color: index < root.qualifiedSamples
                                            ? root.colGreen
                                            : (root.processActive && index === root.qualifiedSamples
                                                ? root.colBlue : "#E2E8F0")
                                        border.color: index < root.qualifiedSamples
                                            ? root.colGreen
                                            : (root.processActive && index === root.qualifiedSamples
                                                ? root.colBlue : "#CBD5E1")
                                        border.width: 1
                                    }
                                }
                            }
                        }

                        // Structured Telemetry Diagnostic Metrics Row (Replaces blank white void)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
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
                                        font.pixelSize: 8
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
                                        font.pixelSize: 8
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
                                        font.pixelSize: 8
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

                        // Detail qualification criteria
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Requires 10 distinct stable telemetry frames over ≥ 2.7 s")
                            color: root.colCharcoal
                            opacity: 0.75
                            font.pixelSize: 9
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
                spacing: 16

                // CLOSE
                HarmonizedButton {
                    text: root.closePending ? qsTr("STOPPING...") : qsTr("CLOSE")
                    baseColor: root.colCardMuted
                    textColor: root.colCharcoal
                    borderColor: root.colGrey
                    onClicked: root.closeRequested()
                }

                // PEDAL
                HarmonizedButton {
                    text: root.tonnageHoldActive ? qsTr("STOP PEDAL") : qsTr("PEDAL")
                    baseColor: root.tonnageHoldActive ? root.colRed : root.colCharcoal
                    textColor: "white"
                    onClicked: root.pedalRequested()
                }

                // AUTO ACTION (Adapts based on operational mode)
                HarmonizedButton {
                    text: root.contactProfileActive
                        ? qsTr("CANCEL AUTO")
                        : (root.operationalMode === "CALIBRATE" ? qsTr("AUTO CALIBRATE") : qsTr("AUTO MEASURE"))
                    baseColor: root.contactProfileActive
                        ? root.colRed
                        : (root.operationalMode === "CALIBRATE" ? root.colGreen : root.colBlue)
                    textColor: "white"
                    onClicked: root.autoRequested()
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

        Layout.fillWidth: true
        Layout.preferredHeight: 58
        radius: 6
        color: root.colCardBg
        border.color: accentColor
        border.width: 1.5

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
                    font.pixelSize: 10
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
                        font.pixelSize: 8
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
        signal clicked()

        Layout.preferredWidth: 200
        Layout.preferredHeight: 50
        radius: 6
        color: btnMouse.containsMouse ? Qt.lighter(baseColor, 1.1) : baseColor
        border.color: borderColor
        border.width: borderColor === "transparent" ? 0 : 1

        scale: btnMouse.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: 80 } }

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
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
