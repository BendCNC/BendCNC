pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // Modal metrics: standard 950 × 600 per BendCNC production geometry
    width: 950
    height: 600
    radius: 12
    clip: true
    color: colPaper
    border.color: colOutline
    border.width: 1

    // -------------------------------------------------------------------------
    // BendCNC Design System Tokens (Harmonized with production)
    // -------------------------------------------------------------------------
    readonly property color colRed: "#A82011"
    readonly property color colGreen: "#59A60C"
    readonly property color colBlue: "#2D83B2"
    readonly property color colCharcoal: "#2B2C2B"
    readonly property color colCharcoalRaised: "#3F403F"
    readonly property color colPaper: "#F5F5F5"
    readonly property color colCardBg: "#FFFFFF"
    readonly property color colCardMuted: "#EBEBEB"
    readonly property color colInk: "#232323"
    readonly property color colGrey: "#A8A8A8"
    readonly property color colOutline: "#B8B8B8"
    readonly property color colDivider: "#D3D3D3"

    // Optional header color variation: "RED" (production default) or "BLUE" (operational)
    property string headerColorTheme: "RED" // "RED" | "BLUE"
    readonly property color headerColor: headerColorTheme === "BLUE" ? colBlue : colRed

    // -------------------------------------------------------------------------
    // Operational State
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

    // Process & Telemetry Stability State
    property string measurementStatus: "READY TO CALIBRATE"
    property real measurementResult: Number.NaN
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
        // HEADER BAR (Height: 80px, radius 12 with squared bottom corners)
        // =====================================================================
        Rectangle {
            id: headerRect
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: root.headerColor
            radius: 12

            // Square off bottom corners so only top of dialog is rounded
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 12
                color: parent.color
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 16
                spacing: 12

                // Left icon badge
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 8
                    color: "#26FFFFFF"
                    border.color: "white"
                    border.width: 1.5

                    Text {
                        anchors.centerIn: parent
                        text: "⌖"
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                // Centered titles
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: qsTr("DIE TOP CALIBRATION")
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        text: qsTr("Realtime Y1/Y2 contact measurement")
                        color: "white"
                        opacity: 0.95
                        font.pixelSize: 15
                    }
                }

                // Close "×" button matching CadResultPopup and standard BendCNC modals
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 6
                    color: closeHover.containsMouse ? "#33FFFFFF" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: "white"
                        font.pixelSize: 26
                        font.bold: true
                    }

                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }
        }

        // =====================================================================
        // CONTENT BODY (Height: 440px, Margins: 16px)
        // Harmonious card layout using BendCNC's production palette
        // =====================================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 10

            // -----------------------------------------------------------------
            // ROW 1: 4 REALTIME POSITION FIELDS (Y1, Y2, Mean, Skew Delta)
            // -----------------------------------------------------------------
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 8
                columnSpacing: 8

                HarmonizedFieldCard {
                    title: qsTr("Y1 POSITION")
                    value: root.telemetryReady ? root.ramPositionY1.toFixed(4) : "----"
                    unit: qsTr("in")
                    accent: root.colBlue
                    subBadge: qsTr("LEFT AXIS")
                }

                HarmonizedFieldCard {
                    title: qsTr("Y2 POSITION")
                    value: root.telemetryReady ? root.ramPositionY2.toFixed(4) : "----"
                    unit: qsTr("in")
                    accent: root.colBlue
                    subBadge: qsTr("RIGHT AXIS")
                }

                HarmonizedFieldCard {
                    title: qsTr("Y1 / Y2 MEAN")
                    value: root.telemetryReady ? root.ramPositionMean.toFixed(4) : "----"
                    unit: qsTr("in")
                    accent: root.colBlue
                    subBadge: qsTr("AVERAGE")
                }

                HarmonizedFieldCard {
                    title: qsTr("Y1 - Y2")
                    value: root.telemetryReady ? root.ramPositionSkew.toFixed(4) : "----"
                    unit: qsTr("in")
                    accent: root.ramPositionSkew <= 0.0010 ? root.colGreen : root.colBlue
                    subBadge: root.ramPositionSkew <= 0.0010 ? qsTr("PARALLEL") : qsTr("SKEW")
                }

                // -------------------------------------------------------------
                // ROW 2: 4 REALTIME TONNAGE FIELDS (Y1 Ton, Y2 Ton, Total, Target)
                // -------------------------------------------------------------
                HarmonizedFieldCard {
                    title: qsTr("Y1 TONNAGE")
                    value: root.telemetryReady ? root.ramLoadY1.toFixed(3) : "----"
                    unit: qsTr("T")
                    accent: root.colGreen
                    subBadge: qsTr("CYL 1")
                }

                HarmonizedFieldCard {
                    title: qsTr("Y2 TONNAGE")
                    value: root.telemetryReady ? root.ramLoadY2.toFixed(3) : "----"
                    unit: qsTr("T")
                    accent: root.colGreen
                    subBadge: qsTr("CYL 2")
                }

                HarmonizedFieldCard {
                    title: qsTr("TOTAL APPLIED")
                    value: root.telemetryReady ? root.liveTonnage.toFixed(3) : "----"
                    unit: qsTr("T")
                    accent: root.colGreen
                    subBadge: qsTr("LIVE LOAD")
                }

                HarmonizedFieldCard {
                    title: qsTr("TARGET")
                    value: root.tonnageHoldTarget.toFixed(3)
                    unit: qsTr("T")
                    accent: root.colBlue
                    subBadge: qsTr("SETPOINT")
                }
            }

            // -----------------------------------------------------------------
            // ROW 3: KNOWN PIECE SIZE & CALIBRATED DIE TOP REFERENCE
            // Harmonious, balanced two-panel row
            // -----------------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                spacing: 10

                // Left panel: Known Piece Size Input with segmented IN/MM buttons
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 7
                    color: root.colCardBg
                    border.color: root.colOutline
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            text: qsTr("KNOWN PIECE SIZE")
                            color: root.colCharcoal
                            font.pixelSize: 13
                            font.bold: true
                        }

                        // Interactive thickness field
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 6
                            color: inputTapArea.containsMouse ? "#F0F7FA" : "#FAFAFA"
                            border.color: inputTapArea.containsMouse ? root.colBlue : root.colGrey
                            border.width: inputTapArea.containsMouse ? 2 : 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                Text {
                                    text: "⌨"
                                    color: root.colBlue
                                    font.pixelSize: 15
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.knownPieceDisplayString
                                    color: root.colInk
                                    font.pixelSize: 19
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
                                id: inputTapArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editKnownPieceRequested()
                            }
                        }

                        // IN Button
                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 40
                            radius: 5
                            color: root.knownPieceUnit === "INCH" ? root.colBlue : root.colCardMuted
                            border.color: root.knownPieceUnit === "INCH" ? root.colBlue : root.colGrey

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("IN")
                                color: root.knownPieceUnit === "INCH" ? "white" : root.colCharcoal
                                font.pixelSize: 12
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
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 40
                            radius: 5
                            color: root.knownPieceUnit === "MILLIMETER" ? root.colBlue : root.colCardMuted
                            border.color: root.knownPieceUnit === "MILLIMETER" ? root.colBlue : root.colGrey

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("MM")
                                color: root.knownPieceUnit === "MILLIMETER" ? "white" : root.colCharcoal
                                font.pixelSize: 12
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

                // Right panel: Calibrated Die Top Status Badge
                Rectangle {
                    Layout.preferredWidth: 320
                    Layout.fillHeight: true
                    radius: 7
                    color: root.colCardBg
                    border.color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                    border.width: 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: qsTr("CALIBRATED DIE TOP")
                                color: root.colCharcoal
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Text {
                                text: root.dieTopCalibrationValid ? qsTr("STORED REFERENCE") : qsTr("CALIBRATION NEEDED")
                                color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.dieTopCalibrationValid
                                ? root.calibratedDieTop.toFixed(4) + " in"
                                : qsTr("NOT CALIBRATED")
                            color: root.dieTopCalibrationValid ? root.colGreen : root.colRed
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // ROW 4: STATUS & REALTIME ACQUISITION CARD (Height: 112px)
            // Charcoal #2B2C2B card harmonized with production
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 112
                radius: 8
                color: root.colCharcoal

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: root.measurementStatus
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: isFinite(root.measurementResult)
                            ? root.measurementResult.toFixed(4) + " in"
                            : "----"
                        color: root.colGreen
                        font.pixelSize: 30
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Progress track matching production styling
                    Rectangle {
                        Layout.preferredWidth: 460
                        Layout.preferredHeight: 10
                        Layout.alignment: Qt.AlignHCenter
                        radius: 999
                        color: root.colCharcoalRaised
                        border.color: "#555555"
                        border.width: 1

                        Rectangle {
                            x: 1
                            y: 1
                            height: parent.height - 2
                            radius: 999
                            color: root.colGreen
                            width: root.requiredSamples > 0
                                ? Math.max(8, (parent.width - 2) * (root.qualifiedSamples / root.requiredSamples))
                                : 8
                            visible: root.qualifiedSamples > 0
                        }
                    }

                    Text {
                        text: isFinite(root.appliedLoadMean)
                            ? qsTr("Applied mean %1 T · peak %2 T · %3 samples / %4 s")
                                .arg(root.appliedLoadMean.toFixed(3))
                                .arg(root.appliedLoadPeak.toFixed(3))
                                .arg(root.acceptedSamples)
                                .arg((root.acceptedDurationMs / 1000).toFixed(1))
                            : qsTr("Requires 10 distinct stable telemetry frames over at least 2.7 s")
                        color: "#D5D7DA"
                        font.pixelSize: 12
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        // =====================================================================
        // FOOTER BAR (Height: 80px, white background with rounded bottom corners)
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "white"
            radius: 12

            // Square off top corners so only bottom of dialog is rounded
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

                // PEDAL BUTTON
                HarmonizedButton {
                    text: root.tonnageHoldActive ? qsTr("STOP PEDAL") : qsTr("PEDAL")
                    baseColor: root.tonnageHoldActive ? root.colRed : root.colCharcoal
                    textColor: "white"
                    onClicked: root.pedalRequested()
                }

                // AUTO BUTTON
                HarmonizedButton {
                    text: root.contactProfileActive ? qsTr("CANCEL AUTO") : qsTr("AUTO")
                    baseColor: root.contactProfileActive ? root.colRed : root.colBlue
                    textColor: "white"
                    onClicked: root.autoRequested()
                }

                // CLOSE BUTTON
                HarmonizedButton {
                    text: root.closePending ? qsTr("STOPPING...") : qsTr("CLOSE")
                    baseColor: root.colCardMuted
                    textColor: root.colCharcoal
                    borderColor: root.colGrey
                    onClicked: root.closeRequested()
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: HarmonizedFieldCard
    // 66px card matching BendCNC's RealtimeField geometry and colors
    // =========================================================================
    component HarmonizedFieldCard: Rectangle {
        id: card
        property string title: ""
        property string value: ""
        property string unit: ""
        property color accent: root.colBlue
        property string subBadge: ""

        Layout.fillWidth: true
        Layout.preferredHeight: 66
        radius: 7
        color: root.colCardBg
        border.color: card.accent
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: card.title
                    color: root.colCharcoal
                    font.pixelSize: 11
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: card.subBadge.length > 0
                    text: card.subBadge
                    color: card.subBadge === "PARALLEL" ? root.colGreen : root.colGrey
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            Text {
                text: card.value + (card.unit.length > 0 ? " " + card.unit : "")
                color: card.accent
                font.pixelSize: 18
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: HarmonizedButton
    // 190 × 52 button matching BendCNC's standard modal action buttons
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
        border.color: btn.borderColor.valid ? btn.borderColor : "transparent"
        border.width: btn.borderColor.valid && btn.borderColor !== "transparent" ? 1 : 0

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
