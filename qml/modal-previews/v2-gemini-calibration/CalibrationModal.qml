pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // Modal geometry: fixed 950 × 600 per specification
    width: 950
    height: 600
    radius: 12
    clip: true
    color: "#13161A"
    border.color: "#2C3440"
    border.width: 1

    // -------------------------------------------------------------------------
    // Operational & Telemetry State
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

    property string knownPieceUnit: "INCH" // "INCH" | "MILLIMETER"
    property real knownPieceThicknessInches: 0.1250
    property real knownPieceThicknessMm: 3.1750
    readonly property string knownPieceDisplayString: knownPieceUnit === "MILLIMETER"
        ? knownPieceThicknessMm.toFixed(3)
        : knownPieceThicknessInches.toFixed(4)

    property bool dieTopCalibrationValid: true
    property real calibratedDieTop: 1.2500

    // Process & Stability Acquisition State
    property string measurementStatus: "READY TO CALIBRATE"
    property real measurementResult: Number.NaN // NaN when not calibrated
    property int requiredSamples: 10
    property int qualifiedSamples: 0
    property bool processActive: false
    property real appliedLoadMean: Number.NaN
    property real appliedLoadPeak: Number.NaN
    property int acceptedSamples: 0
    property real acceptedDurationMs: 0

    property bool tonnageHoldActive: false     // PEDAL active
    property bool contactProfileActive: false   // AUTO active
    property bool closePending: false

    // Signals for button interactions
    signal pedalRequested()
    signal autoRequested()
    signal closeRequested()
    signal editKnownPieceRequested()
    signal unitChanged(string unit)

    // Palette tokens
    readonly property color colBgDark: "#13161A"
    readonly property color colCardBg: "#1A1E24"
    readonly property color colCardInner: "#14171C"
    readonly property color colCardBorder: "#272E38"
    readonly property color colAccentBlue: "#0EA5E9"
    readonly property color colAccentBlueDim: "#0369A1"
    readonly property color colAccentCyan: "#38BDF8"
    readonly property color colGreen: "#22C55E"
    readonly property color colGreenGlow: "#4ADE80"
    readonly property color colGreenDim: "#14532D"
    readonly property color colAmber: "#F59E0B"
    readonly property color colAmberDim: "#78350F"
    readonly property color colRed: "#EF4444"
    readonly property color colTextPrimary: "#FFFFFF"
    readonly property color colTextSecondary: "#94A3B8"
    readonly property color colTextMuted: "#64748B"

    // Subtle top accent illumination line
    Rectangle {
        id: topGlowBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 3
        z: 10
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#0284C7" }
            GradientStop { position: 0.5; color: "#38BDF8" }
            GradientStop { position: 1.0; color: "#0284C7" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // =====================================================================
        // HEADER BAR (Height: 72px)
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: "#171B21"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#252C36"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 14

                // Precision icon badge
                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 8
                    color: "#0F2942"
                    border.color: "#0284C7"
                    border.width: 1.5

                    Text {
                        anchors.centerIn: parent
                        text: "⌖"
                        color: root.colAccentCyan
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                // Title & subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        spacing: 10
                        Text {
                            text: qsTr("DIE TOP CALIBRATION")
                            color: root.colTextPrimary
                            font.pixelSize: 20
                            font.bold: true
                            font.letterSpacing: 0.5
                        }

                        // Operational badge
                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: 128
                            radius: 4
                            color: "#1E293B"
                            border.color: "#334155"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("PRECISION SETUP")
                                color: "#94A3B8"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.6
                            }
                        }
                    }

                    Text {
                        text: qsTr("Realtime dual-cylinder Y1/Y2 contact measurement and reference datum")
                        color: root.colTextSecondary
                        font.pixelSize: 12
                    }
                }

                // Right telemetry status chips
                RowLayout {
                    spacing: 8

                    Rectangle {
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 122
                        radius: 13
                        color: root.telemetryReady ? "#052E16" : "#450A0A"
                        border.color: root.telemetryReady ? root.colGreen : root.colRed
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                Layout.preferredWidth: 7
                                Layout.preferredHeight: 7
                                radius: 3.5
                                color: root.telemetryReady ? root.colGreenGlow : root.colRed
                            }
                            Text {
                                text: root.telemetryReady ? qsTr("SENSORS LIVE") : qsTr("OFFLINE")
                                color: root.telemetryReady ? root.colGreenGlow : root.colRed
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.4
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: 90
                        radius: 13
                        color: "#1E293B"
                        border.color: "#334155"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: qsTr("950 × 600")
                            color: "#94A3B8"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }
            }
        }

        // =====================================================================
        // MAIN BODY CONTENT (Height: ~454px)
        // Two-column layout: Left (Telemetry Dynamics) + Right (Protocol & Acquisition)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 12

            // -----------------------------------------------------------------
            // LEFT COLUMN: AXIS & FORCE TELEMETRY DASHBOARD (Width: 530px)
            // -----------------------------------------------------------------
            Rectangle {
                Layout.preferredWidth: 530
                Layout.fillHeight: true
                radius: 10
                color: root.colCardBg
                border.color: root.colCardBorder
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // ---- SECTION 1: RAM ENCODER POSITION ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 4
                            Layout.preferredHeight: 14
                            radius: 2
                            color: root.colAccentCyan
                        }
                        Text {
                            text: qsTr("RAM ENCODER POSITION")
                            color: root.colTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.6
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: qsTr("UNIT: INCHES [in]")
                            color: root.colTextMuted
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        // Y1 POSITION
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("Y1 AXIS (LEFT)")
                            valueText: root.telemetryReady ? root.ramPositionY1.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: root.colAccentCyan
                            statusBadge: qsTr("LVDT 1")
                            statusBadgeBg: "#1E293B"
                            statusBadgeColor: "#94A3B8"
                        }

                        // Y2 POSITION
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("Y2 AXIS (RIGHT)")
                            valueText: root.telemetryReady ? root.ramPositionY2.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: root.colAccentCyan
                            statusBadge: qsTr("LVDT 2")
                            statusBadgeBg: "#1E293B"
                            statusBadgeColor: "#94A3B8"
                        }

                        // Y1/Y2 MEAN
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("Y1 / Y2 MEAN")
                            valueText: root.telemetryReady ? root.ramPositionMean.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: "#60A5FA"
                            statusBadge: qsTr("RAM AVERAGE")
                            statusBadgeBg: "#1E293B"
                            statusBadgeColor: "#94A3B8"
                        }

                        // SKEW DELTA |Y1 - Y2|
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("SKEW |Y1 - Y2|")
                            valueText: root.telemetryReady ? root.ramPositionSkew.toFixed(4) : "----"
                            unitText: qsTr("in")
                            accentColor: root.ramPositionSkew <= 0.0010 ? root.colGreenGlow : root.colAmber
                            statusBadge: root.ramPositionSkew <= 0.0010 ? qsTr("PARALLEL") : qsTr("TILT")
                            statusBadgeBg: root.ramPositionSkew <= 0.0010 ? root.colGreenDim : root.colAmberDim
                            statusBadgeColor: root.ramPositionSkew <= 0.0010 ? root.colGreenGlow : root.colAmber
                        }
                    }

                    // Divider between position and force
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: "#272E38"
                    }

                    // ---- SECTION 2: FORCE & TONNAGE DISTRIBUTION ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 4
                            Layout.preferredHeight: 14
                            radius: 2
                            color: root.colGreenGlow
                        }
                        Text {
                            text: qsTr("FORCE & TONNAGE DISTRIBUTION")
                            color: root.colTextPrimary
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.6
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: qsTr("UNIT: US TONS [T]")
                            color: root.colTextMuted
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        // Y1 TONNAGE
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("Y1 TONNAGE")
                            valueText: root.telemetryReady ? root.ramLoadY1.toFixed(3) : "----"
                            unitText: qsTr("T")
                            accentColor: root.colGreenGlow
                            statusBadge: qsTr("CYL 1")
                            statusBadgeBg: "#14532D"
                            statusBadgeColor: root.colGreenGlow
                        }

                        // Y2 TONNAGE
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("Y2 TONNAGE")
                            valueText: root.telemetryReady ? root.ramLoadY2.toFixed(3) : "----"
                            unitText: qsTr("T")
                            accentColor: root.colGreenGlow
                            statusBadge: qsTr("CYL 2")
                            statusBadgeBg: "#14532D"
                            statusBadgeColor: root.colGreenGlow
                        }

                        // TOTAL APPLIED
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("TOTAL APPLIED")
                            valueText: root.telemetryReady ? root.liveTonnage.toFixed(3) : "----"
                            unitText: qsTr("T")
                            accentColor: root.colGreenGlow
                            statusBadge: qsTr("LIVE FORCE")
                            statusBadgeBg: "#14532D"
                            statusBadgeColor: root.colGreenGlow
                        }

                        // TARGET HOLD
                        TelemetryCard {
                            Layout.fillWidth: true
                            tag: qsTr("TARGET")
                            valueText: root.tonnageHoldTarget.toFixed(3)
                            unitText: qsTr("T")
                            accentColor: root.colAccentCyan
                            statusBadge: qsTr("SETPOINT")
                            statusBadgeBg: "#0F2942"
                            statusBadgeColor: root.colAccentCyan
                        }
                    }

                    // Realtime cylinder force balance strip
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: root.colCardInner
                        border.color: "#272E38"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: qsTr("FORCE BALANCE")
                                color: root.colTextMuted
                                font.pixelSize: 10
                                font.bold: true
                            }

                            // Dynamic dual-cylinder balance bar
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: "#232830"
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * 0.5
                                    radius: 4
                                    color: root.colGreen
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * 0.5
                                    radius: 4
                                    color: "#16A34A"
                                }

                                // Center balance marker
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 2
                                    color: "white"
                                }
                            }

                            Text {
                                text: qsTr("50% Y1 / 50% Y2")
                                color: root.colGreenGlow
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN: CALIBRATION PROTOCOL & ACQUISITION (Width: 380px)
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // ==== CARD 1: REFERENCE SHIM SETUP (Height: ~168px) ====
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 168
                    radius: 10
                    color: root.colCardBg
                    border.color: root.colCardBorder
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        // Card header with unit selector
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 4
                                Layout.preferredHeight: 14
                                radius: 2
                                color: root.colAccentBlue
                            }

                            Text {
                                text: qsTr("1. KNOWN PIECE SIZE")
                                color: root.colTextPrimary
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 0.6
                            }

                            Item { Layout.fillWidth: true }

                            // IN / MM Unit Pill Toggle
                            Rectangle {
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 28
                                radius: 6
                                color: root.colCardInner
                                border.color: "#333E4D"

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 2

                                    // IN Button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 5
                                        color: root.knownPieceUnit === "INCH" ? root.colAccentBlueDim : "transparent"
                                        border.color: root.knownPieceUnit === "INCH" ? root.colAccentCyan : "transparent"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("IN")
                                            color: root.knownPieceUnit === "INCH" ? "white" : root.colTextSecondary
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

                                    // MM Button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 5
                                        color: root.knownPieceUnit === "MILLIMETER" ? root.colAccentBlueDim : "transparent"
                                        border.color: root.knownPieceUnit === "MILLIMETER" ? root.colAccentCyan : "transparent"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("MM")
                                            color: root.knownPieceUnit === "MILLIMETER" ? "white" : root.colTextSecondary
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

                        // Tactile Thickness Input Display
                        Rectangle {
                            id: thicknessInputBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 8
                            color: root.colCardInner
                            border.color: inputMouseArea.containsMouse ? root.colAccentCyan : "#334155"
                            border.width: inputMouseArea.containsMouse ? 2 : 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14

                                Text {
                                    text: "⌨"
                                    color: root.colAccentCyan
                                    font.pixelSize: 18
                                }

                                Text {
                                    text: qsTr("THICKNESS:")
                                    color: root.colTextSecondary
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.knownPieceDisplayString
                                    color: root.colTextPrimary
                                    font.pixelSize: 22
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                }

                                Text {
                                    text: root.knownPieceUnit === "MILLIMETER" ? qsTr("mm") : qsTr("in")
                                    color: root.colAccentCyan
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: inputMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editKnownPieceRequested()
                            }
                        }

                        // Calibrated Die Top Reference Status Bar
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 6
                            color: root.colCardInner
                            border.color: root.dieTopCalibrationValid ? "#1E3A2F" : "#451A1A"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: root.dieTopCalibrationValid ? root.colGreenGlow : root.colAmber
                                }

                                Text {
                                    text: qsTr("CALIBRATED DIE TOP")
                                    color: root.colTextSecondary
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.dieTopCalibrationValid
                                        ? root.calibratedDieTop.toFixed(4) + " in"
                                        : qsTr("NOT CALIBRATED")
                                    color: root.dieTopCalibrationValid ? root.colGreenGlow : root.colAmber
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                }
                            }
                        }
                    }
                }

                // ==== CARD 2: CONTACT ACQUISITION & QUALIFICATION (Height: ~260px) ====
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: root.colCardBg
                    border.color: root.colCardBorder
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        // Header with status indicator
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 4
                                Layout.preferredHeight: 14
                                radius: 2
                                color: root.colGreenGlow
                            }

                            Text {
                                text: qsTr("2. CONTACT ACQUISITION")
                                color: root.colTextPrimary
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 0.6
                            }

                            Item { Layout.fillWidth: true }

                            // Live process badge
                            Rectangle {
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: 156
                                radius: 11
                                color: root.processActive ? "#052E16" : "#1E293B"
                                border.color: root.processActive ? root.colGreen : "#334155"

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: root.processActive ? root.colGreenGlow : root.colAccentCyan
                                    }
                                    Text {
                                        text: root.measurementStatus
                                        color: root.processActive ? root.colGreenGlow : root.colAccentCyan
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // Big Result Readout Panel
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: root.colCardInner
                            border.color: isFinite(root.measurementResult) ? root.colGreen : "#262C36"
                            border.width: isFinite(root.measurementResult) ? 1.5 : 1

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: qsTr("MEASURED DIE TOP REFERENCE")
                                    color: root.colTextMuted
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: isFinite(root.measurementResult)
                                        ? root.measurementResult.toFixed(4) + " in"
                                        : "----"
                                    color: isFinite(root.measurementResult) ? root.colGreenGlow : root.colTextPrimary
                                    font.pixelSize: 34
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: isFinite(root.measurementResult)
                                        ? qsTr("✓ ACCURATE DATUM STORED")
                                        : qsTr("PRESS PEDAL OR AUTO TO COMMENCE")
                                    color: isFinite(root.measurementResult) ? root.colGreenGlow : root.colTextSecondary
                                    font.pixelSize: 11
                                    font.bold: true
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Segmented 10-Frame Qualification Progress Bar
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("TELEMETRY STABILITY PROGRESS")
                                    color: root.colTextMuted
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("%1 / %2 SAMPLES")
                                        .arg(root.qualifiedSamples)
                                        .arg(root.requiredSamples)
                                    color: root.qualifiedSamples === root.requiredSamples && root.requiredSamples > 0
                                        ? root.colGreenGlow : root.colAccentCyan
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: "Consolas, monospace"
                                }
                            }

                            // 10-segment discrete LED bar
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 10
                                spacing: 4

                                Repeater {
                                    model: root.requiredSamples > 0 ? root.requiredSamples : 10
                                    Rectangle {
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 3
                                        color: index < root.qualifiedSamples
                                            ? root.colGreenGlow
                                            : (root.processActive && index === root.qualifiedSamples
                                                ? root.colAccentCyan : "#232832")
                                    }
                                }
                            }
                        }

                        // Telemetry stability telemetry details footer note
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: 6
                            color: root.colCardInner
                            border.color: "#272E38"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                Text {
                                    text: "ℹ"
                                    color: root.colAccentCyan
                                    font.pixelSize: 13
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: isFinite(root.appliedLoadMean)
                                        ? qsTr("Applied mean %1 T · peak %2 T · %3 samples / %4 s")
                                            .arg(root.appliedLoadMean.toFixed(3))
                                            .arg(root.appliedLoadPeak.toFixed(3))
                                            .arg(root.acceptedSamples)
                                            .arg((root.acceptedDurationMs / 1000).toFixed(1))
                                        : qsTr("Requires 10 distinct stable telemetry frames over ≥ 2.7 s")
                                    color: isFinite(root.appliedLoadMean) ? root.colTextPrimary : root.colTextSecondary
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // FOOTER ACTION BAR (Height: 74px)
        // High affordance, clear primary vs secondary tactile industrial buttons
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 74
            color: "#16191E"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#272E38"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 16

                // CLOSE BUTTON (Dismiss / Neutral Exit)
                Rectangle {
                    id: closeBtn
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 48
                    radius: 8
                    color: closeBtnMouse.pressed ? "#232832" : (closeBtnMouse.containsMouse ? "#2A313C" : "#1C2026")
                    border.color: closeBtnMouse.containsMouse ? "#64748B" : "#3B4452"
                    border.width: 1.5

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: "✕"
                            color: root.colTextSecondary
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Text {
                            text: root.closePending ? qsTr("STOPPING...") : qsTr("CLOSE")
                            color: root.colTextPrimary
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 0.5
                        }
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }

                Item { Layout.fillWidth: true }

                // PEDAL BUTTON (Manual Operator Assist)
                Rectangle {
                    id: pedalBtn
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 48
                    radius: 8
                    color: root.tonnageHoldActive
                        ? (pedalBtnMouse.pressed ? "#7F1D1D" : "#991B1B")
                        : (pedalBtnMouse.pressed ? "#0F2942" : (pedalBtnMouse.containsMouse ? "#1E3A5F" : "#13273D"))
                    border.color: root.tonnageHoldActive ? root.colRed : root.colAccentBlue
                    border.width: 1.5

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: root.tonnageHoldActive ? "⏹" : "⚡"
                            color: root.tonnageHoldActive ? "white" : root.colAccentCyan
                            font.pixelSize: 15
                        }
                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: root.tonnageHoldActive ? qsTr("STOP PEDAL") : qsTr("PEDAL MODE")
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 0.5
                            }
                            Text {
                                text: root.tonnageHoldActive ? qsTr("Active hold") : qsTr("Manual operator switch")
                                color: root.tonnageHoldActive ? "#FECACA" : "#93C5FD"
                                font.pixelSize: 9
                            }
                        }
                    }

                    MouseArea {
                        id: pedalBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pedalRequested()
                    }
                }

                // AUTO BUTTON (Automated Profile - Primary Call-to-Action)
                Rectangle {
                    id: autoBtn
                    Layout.preferredWidth: 230
                    Layout.preferredHeight: 48
                    radius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: root.contactProfileActive
                                ? (autoBtnMouse.pressed ? "#B91C1C" : "#DC2626")
                                : (autoBtnMouse.pressed ? "#0284C7" : (autoBtnMouse.containsMouse ? "#0284C7" : "#0369A1"))
                        }
                        GradientStop {
                            position: 1.0
                            color: root.contactProfileActive
                                ? (autoBtnMouse.pressed ? "#991B1B" : "#B91C1C")
                                : (autoBtnMouse.pressed ? "#0369A1" : (autoBtnMouse.containsMouse ? "#0EA5E9" : "#0284C7"))
                        }
                    }
                    border.color: root.contactProfileActive ? "#FCA5A5" : "#7DD3FC"
                    border.width: 1.5

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: root.contactProfileActive ? "✖" : "▶"
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: root.contactProfileActive ? qsTr("CANCEL AUTO") : qsTr("AUTO CALIBRATE")
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 0.5
                            }
                            Text {
                                text: root.contactProfileActive ? qsTr("Abort sequence") : qsTr("Automated touch profile")
                                color: "#E0F2FE"
                                font.pixelSize: 9
                            }
                        }
                    }

                    MouseArea {
                        id: autoBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.autoRequested()
                    }
                }
            }
        }
    }

    // =========================================================================
    // REUSABLE SUB-COMPONENT: TelemetryCard
    // High-readability industrial digital readout card
    // =========================================================================
    component TelemetryCard: Rectangle {
        id: cardRoot
        property string tag: ""
        property string valueText: ""
        property string unitText: ""
        property color accentColor: root.colAccentCyan
        property string statusBadge: ""
        property color statusBadgeBg: "#1E293B"
        property color statusBadgeColor: "#94A3B8"

        Layout.fillWidth: true
        Layout.preferredHeight: 62
        radius: 7
        color: root.colCardInner
        border.color: root.colCardBorder
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: cardRoot.tag
                    color: root.colTextSecondary
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0.4
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: cardRoot.statusBadge.length > 0
                    Layout.preferredHeight: 16
                    Layout.preferredWidth: badgeText.implicitWidth + 10
                    radius: 3
                    color: cardRoot.statusBadgeBg

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: cardRoot.statusBadge
                        color: cardRoot.statusBadgeColor
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: cardRoot.valueText
                    color: cardRoot.accentColor
                    font.pixelSize: 20
                    font.bold: true
                    font.family: "Consolas, monospace"
                }

                Text {
                    visible: cardRoot.unitText.length > 0
                    text: cardRoot.unitText
                    color: root.colTextMuted
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignBaseline
                }
            }
        }
    }
}
