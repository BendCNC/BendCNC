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

    // Header color variation: "BLUE" (operational default) or "RED" (production standard)
    property string headerTheme: "BLUE" // "BLUE" | "RED"
    readonly property color headerColor: headerTheme === "RED" ? colRed : colBlue

    // -------------------------------------------------------------------------
    // Operational & Telemetry Properties
    // -------------------------------------------------------------------------
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

    property string knownPieceUnit: "INCH" // "INCH" | "MILLIMETER"
    property real knownPieceThicknessInches: 0.1250
    property real knownPieceThicknessMm: 3.1750
    readonly property string knownPieceDisplayString: knownPieceUnit === "MILLIMETER"
        ? knownPieceThicknessMm.toFixed(3)
        : knownPieceThicknessInches.toFixed(4)

    property bool dieTopCalibrationValid: true
    property real calibratedDieTop: 1.2500

    // Process & Telemetry Stability
    property string measurementStatus: "READY TO CALIBRATE"
    property real measurementResult: Number.NaN
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
    signal editKnownPieceRequested()
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
            color: root.headerColor
            radius: 12

            // Square bottom corners to seamlessly sit on top of the modal paper
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

                // Titles
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: qsTr("DIE TOP CALIBRATION")
                        color: "white"
                        font.pixelSize: 23
                        font.bold: true
                    }

                    Text {
                        text: qsTr("Realtime Y1/Y2 dual-cylinder contact measurement")
                        color: "white"
                        opacity: 0.92
                        font.pixelSize: 14
                    }
                }

                Item { Layout.fillWidth: true }

                // Status chip
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
        // Two-column layout: Left (Telemetry Dynamics) + Right (Protocol & Acquisition)
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
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN (Width: 386px): REFERENCE & CONTACT ACQUISITION
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // CARD 1: REFERENCE SHIM & DIE TOP (Height: 168px)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 168
                    radius: 8
                    color: root.colCardBg
                    border.color: root.colOutline
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: qsTr("1. KNOWN PIECE SIZE")
                                color: root.colInk
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 0.5
                            }

                            Item { Layout.fillWidth: true }

                            // IN / MM Segmented Pill Switch
                            Rectangle {
                                Layout.preferredWidth: 104
                                Layout.preferredHeight: 28
                                radius: 5
                                color: root.colPaper
                                border.color: root.colOutline

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 1

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 4
                                        color: root.knownPieceUnit === "INCH" ? root.colBlue : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("IN")
                                            color: root.knownPieceUnit === "INCH" ? "white" : root.colCharcoal
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.knownPieceUnit = "INCH"
                                                root.unitChanged("INCH")
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 4
                                        color: root.knownPieceUnit === "MILLIMETER" ? root.colBlue : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("MM")
                                            color: root.knownPieceUnit === "MILLIMETER" ? "white" : root.colCharcoal
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.knownPieceUnit = "MILLIMETER"
                                                root.unitChanged("MILLIMETER")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Tactile Thickness Display Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 6
                            color: shimMouse.containsMouse ? root.colBlueBg : "#F8FAFC"
                            border.color: shimMouse.containsMouse ? root.colBlue : root.colGrey
                            border.width: shimMouse.containsMouse ? 2 : 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    text: "⌨"
                                    color: root.colBlue
                                    font.pixelSize: 16
                                }

                                Text {
                                    text: qsTr("THICKNESS:")
                                    color: root.colCharcoal
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.knownPieceDisplayString
                                    color: root.colInk
                                    font.pixelSize: 20
                                    font.bold: true
                                }

                                Text {
                                    text: root.knownPieceUnit === "MILLIMETER" ? qsTr("mm") : qsTr("in")
                                    color: root.colBlue
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: shimMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editKnownPieceRequested()
                            }
                        }

                        // Calibrated Die Top Reference Bar
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 6
                            color: root.dieTopCalibrationValid ? root.colGreenBg : "#FDE8E8"
                            border.color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 7
                                    Layout.preferredHeight: 7
                                    radius: 3.5
                                    color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                                }

                                Text {
                                    text: qsTr("CALIBRATED DIE TOP")
                                    color: root.colCharcoal
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.dieTopCalibrationValid
                                        ? root.calibratedDieTop.toFixed(4) + " in"
                                        : qsTr("NOT CALIBRATED")
                                    color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                // CARD 2: CONTACT ACQUISITION STAGE (Harmonized with white theme)
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
                        spacing: 8

                        // Status line
                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: qsTr("2. CONTACT ACQUISITION")
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

                        // Prominent Measured Result Readout Box
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 88
                            Layout.minimumHeight: 84
                            radius: 6
                            color: "#F8FAFC"
                            border.color: isFinite(root.measurementResult) ? root.colGreen : root.colDivider
                            border.width: isFinite(root.measurementResult) ? 1.5 : 1
                            clip: true

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                spacing: 2

                                Text {
                                    text: qsTr("MEASURED DIE TOP REFERENCE")
                                    color: root.colGrey
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: isFinite(root.measurementResult)
                                        ? root.measurementResult.toFixed(4) + " in"
                                        : "----"
                                    color: isFinite(root.measurementResult) ? root.colGreen : root.colCharcoal
                                    font.pixelSize: 26
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: isFinite(root.measurementResult)
                                        ? qsTr("✓ ACCURATE DATUM STORED")
                                        : (root.processActive
                                            ? qsTr("MEASURING CONTACT POSITION...")
                                            : qsTr("PRESS PEDAL OR AUTO TO COMMENCE"))
                                    color: isFinite(root.measurementResult)
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
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("TELEMETRY STABILITY PROGRESS")
                                    color: root.colCharcoal
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("%1 / %2 SAMPLES")
                                        .arg(root.qualifiedSamples)
                                        .arg(root.requiredSamples)
                                    color: root.qualifiedSamples === root.requiredSamples && root.requiredSamples > 0
                                        ? root.colGreen : root.colBlue
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            // 10-segment track (Fixed sleek 12px height)
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 12
                                Layout.maximumHeight: 12
                                spacing: 3

                                Repeater {
                                    model: root.requiredSamples > 0 ? Math.min(20, root.requiredSamples) : 10
                                    Rectangle {
                                        required property int index
                                        readonly property real doneSegs: root.requiredSamples > 0 ? root.qualifiedSamples * Math.min(20, root.requiredSamples) / root.requiredSamples : 0
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 12
                                        Layout.maximumHeight: 12
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

                        Item { Layout.fillHeight: true }

                        // Detail note
                        Text {
                            Layout.fillWidth: true
                            text: isFinite(root.appliedLoadMean)
                                ? qsTr("Applied mean %1 T · peak %2 T · %3 samples / %4 s")
                                    .arg(root.appliedLoadMean.toFixed(3))
                                    .arg(root.appliedLoadPeak.toFixed(3))
                                    .arg(root.acceptedSamples)
                                    .arg((root.acceptedDurationMs / 1000).toFixed(1))
                                : qsTr("Requires 10 distinct stable telemetry frames over ≥ 2.7 s")
                            color: root.colCharcoal
                            opacity: 0.8
                            font.pixelSize: 10
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

                // AUTO
                HarmonizedButton {
                    text: root.contactProfileActive ? qsTr("CANCEL AUTO") : qsTr("AUTO CALIBRATE")
                    baseColor: root.contactProfileActive ? root.colRed : root.colBlue
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
        color: "#F8FAFC"
        border.color: fieldCard.accentColor
        border.width: 1.5

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: fieldCard.tag
                    color: root.colCharcoal
                    font.pixelSize: 10
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: fieldCard.badgeText.length > 0
                    Layout.preferredHeight: 14
                    Layout.preferredWidth: bText.implicitWidth + 8
                    radius: 3
                    color: fieldCard.badgeBg

                    Text {
                        id: bText
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
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    visible: fieldCard.unitText.length > 0
                    text: fieldCard.unitText
                    color: root.colGrey
                    font.pixelSize: 11
                    font.bold: true
                    Layout.alignment: Qt.AlignBaseline
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: HarmonizedButton
    // =========================================================================
    component HarmonizedButton: Rectangle {
        id: btn
        property string text: ""
        property color baseColor: root.colCharcoal
        property color textColor: "white"
        property color borderColor: "transparent"
        signal clicked()

        Layout.preferredWidth: 190
        Layout.preferredHeight: 52
        radius: 6
        color: btnMouse.pressed ? Qt.darker(btn.baseColor, 1.15)
            : (btnMouse.containsMouse ? Qt.lighter(btn.baseColor, 1.1) : btn.baseColor)
        border.color: btn.borderColor
        border.width: btn.borderColor !== "transparent" ? 1 : 0

        Text {
            anchors.centerIn: parent
            text: btn.text
            color: btn.textColor
            font.pixelSize: 15
            font.bold: true
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
