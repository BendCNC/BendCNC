pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // Modal dimensions: 950 × 600 per BendCNC Operational Standard
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

    // Header color variation: "BLUE" or "RED" (standard safety red)
    property string headerTheme: "RED" // "RED" | "BLUE"
    readonly property color headerColor: headerTheme === "RED" ? colRed : colBlue

    // Interactive switch states
    property bool leftHeld: false
    property bool rightHeld: false

    // Action signals
    signal completeRequested()
    signal cancelRequested()
    signal leftToggleRequested()
    signal rightToggleRequested()

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

            // Square bottom corners to sit on content
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

                // Title and Subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    RowLayout {
                        spacing: 8
                        Text {
                            text: qsTr("BLEED HYDRAULICS")
                            color: "white"
                            font.pixelSize: 23
                            font.bold: true
                        }

                        // Status pill badge
                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: badgeStatusText.implicitWidth + 12
                            radius: 4
                            color: "#33FFFFFF"

                            Text {
                                id: badgeStatusText
                                anchors.centerIn: parent
                                text: qsTr("MAINTENANCE PROCEDURE")
                                color: "white"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        text: qsTr("Manual cylinder priming and air purge protocol")
                        color: "white"
                        opacity: 0.92
                        font.pixelSize: 13
                    }
                }

                Item { Layout.fillWidth: true }

                // Live safety status chip (right-aligned)
                Rectangle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: 156
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
                            color: (root.leftHeld || root.rightHeld) ? "#86EFAC" : "#FDE047"
                        }
                        Text {
                            text: (root.leftHeld || root.rightHeld) ? qsTr("PRIMING ACTIVE") : qsTr("READY TO PRIME")
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
        // Two-column layout: Left (Interactive Palm Controls) + Right (Step Checklist)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 14

            // -----------------------------------------------------------------
            // LEFT COLUMN (Width: 480px): PALM SWITCH PRIMING STATIONS
            // -----------------------------------------------------------------
            Rectangle {
                Layout.preferredWidth: 480
                Layout.fillHeight: true
                radius: 8
                color: root.colCardBg
                border.color: root.colOutline
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // Card header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: qsTr("HYDRAULIC PRIMING STATIONS")
                            color: root.colInk
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.5
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: 90
                            radius: 10
                            color: root.colBlueBg
                            border.color: root.colBlue
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("INDEPENDENT")
                                color: root.colBlue
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Each palm switch independently primes one logical hydraulic cylinder while held. Release to stop immediately.")
                        color: root.colCharcoal
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        lineHeight: 1.15
                    }

                    // Dual Palm Switch Interactive Cards (Y1 & Y2)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        // Y1 Palm Switch Card
                        PalmSwitchCard {
                            id: y1Card
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            sideLabel: qsTr("LEFT PALM SWITCH")
                            cylinderLabel: qsTr("LOGICAL Y1 CYLINDER")
                            cylinderTag: qsTr("CYLINDER 1 (LEFT)")
                            accentColor: root.colGreen
                            isHeld: root.leftHeld
                            onToggleRequested: root.leftToggleRequested()
                        }

                        // Y2 Palm Switch Card
                        PalmSwitchCard {
                            id: y2Card
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            sideLabel: qsTr("RIGHT PALM SWITCH")
                            cylinderLabel: qsTr("LOGICAL Y2 CYLINDER")
                            cylinderTag: qsTr("CYLINDER 2 (RIGHT)")
                            accentColor: root.colGreen
                            isHeld: root.rightHeld
                            onToggleRequested: root.rightToggleRequested()
                        }
                    }

                    // Safety verification warning strip at bottom of left column
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: 6
                        color: root.colAmberBg
                        border.color: root.colAmber
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "⚠"
                                color: root.colAmber
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Logical Y1/Y2 cylinder sides require supervised physical verification before priming.")
                                color: "#8A5200"
                                font.pixelSize: 10
                                font.bold: true
                                wrapMode: Text.WordWrap
                                lineHeight: 1.1
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN (Fill remaining ~420px): PROCEDURE PROTOCOL & SAFETY
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: root.colCardBg
                border.color: root.colOutline
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Right column header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: qsTr("BLEED PROCEDURE CHECKLIST")
                            color: root.colInk
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.5
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: 84
                            radius: 10
                            color: "#F1F5F9"
                            border.color: root.colGrey
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("4 STEPS")
                                color: root.colCharcoal
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    // Step 1
                    ProcedureStepRow {
                        stepNumber: "1"
                        stepTitle: qsTr("Clear Working Zone")
                        instructionText: qsTr("Remove tooling and keep all body parts completely clear of the ram and lower table bed.")
                        isActive: true
                    }

                    // Step 2
                    ProcedureStepRow {
                        stepNumber: "2"
                        stepTitle: qsTr("Open Cylinder Bleeder")
                        instructionText: qsTr("Connect drain tubing and open the manual bleeder valve for the cylinder being serviced.")
                        isActive: true
                    }

                    // Step 3
                    ProcedureStepRow {
                        stepNumber: "3"
                        stepTitle: qsTr("Hold Palm Switch to Prime")
                        instructionText: qsTr("Hold only the corresponding palm switch until clear, bubble-free hydraulic oil flows; release instantly to stop.")
                        isActive: root.leftHeld || root.rightHeld
                    }

                    // Step 4
                    ProcedureStepRow {
                        stepNumber: "4"
                        stepTitle: qsTr("Seal & Lock Bleeder Valve")
                        instructionText: qsTr("Tighten and securely torque the bleeder valve BEFORE releasing the palm switch to prevent air ingestion.")
                        isActive: true
                    }

                    Item { Layout.fillHeight: true }

                    // Safety standard note
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 5
                        color: "#F8FAFC"
                        border.color: root.colDivider
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6

                            Text {
                                text: "ℹ"
                                color: root.colBlue
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Pump runs in closed-loop limp mode while priming is engaged.")
                                color: root.colCharcoal
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
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
                spacing: 20

                // CANCEL / DISABLE (Red outline / secondary action)
                HarmonizedButton {
                    text: qsTr("CANCEL / DISABLE")
                    baseColor: root.colCardMuted
                    textColor: root.colCharcoal
                    borderColor: root.colGrey
                    onClicked: root.cancelRequested()
                }

                // COMPLETE PROCEDURE (Prominent primary action)
                HarmonizedButton {
                    text: qsTr("COMPLETE PROCEDURE")
                    baseColor: root.colCharcoal
                    textColor: "white"
                    onClicked: root.completeRequested()
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: PalmSwitchCard (Interactive palm priming station)
    // =========================================================================
    component PalmSwitchCard: Rectangle {
        id: card
        property string sideLabel: ""
        property string cylinderLabel: ""
        property string cylinderTag: ""
        property color accentColor: root.colGreen
        property bool isHeld: false
        signal toggleRequested()

        radius: 8
        color: isHeld ? root.colGreenBg : "#F8FAFC"
        border.color: isHeld ? root.colGreen : root.colOutline
        border.width: isHeld ? 2 : 1

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Card title
            Text {
                text: card.sideLabel
                color: root.colInk
                font.pixelSize: 11
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            // Cylinder identification tag
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: tagText.implicitWidth + 12
                Layout.alignment: Qt.AlignHCenter
                radius: 4
                color: card.isHeld ? "#D1FAE5" : "#E2E8F0"

                Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: card.cylinderTag
                    color: card.isHeld ? root.colGreen : root.colCharcoal
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            Item { Layout.fillHeight: true }

            // Large palm switch interactive target
            Rectangle {
                id: palmBtn
                Layout.preferredWidth: 140
                Layout.preferredHeight: 68
                Layout.alignment: Qt.AlignHCenter
                radius: 34
                color: card.isHeld ? root.colGreen : (btnMouse.containsMouse ? "#E2E8F0" : "#CBD5E1")
                border.color: card.isHeld ? "#3F7A07" : root.colGrey
                border.width: 2

                scale: btnMouse.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: 80 } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        text: card.isHeld ? "⚡" : "✋"
                        color: card.isHeld ? "white" : root.colCharcoal
                        font.pixelSize: 22
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: card.isHeld ? qsTr("HOLDING") : qsTr("CLICK TO HOLD")
                        color: card.isHeld ? "white" : root.colCharcoal
                        font.pixelSize: 9
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.toggleRequested()
                }
            }

            Item { Layout.fillHeight: true }

            // State indicator pill
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 15
                color: card.isHeld ? root.colGreen : root.colCharcoalRaised

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: card.isHeld ? "white" : root.colGrey
                    }

                    Text {
                        text: card.isHeld ? qsTr("PRIMING · ACTIVE") : qsTr("STOPPED · SAFE")
                        color: "white"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: ProcedureStepRow (Structured numbered step with status)
    // =========================================================================
    component ProcedureStepRow: Rectangle {
        id: stepRow
        property string stepNumber: "1"
        property string stepTitle: ""
        property string instructionText: ""
        property bool isActive: false

        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 6
        color: isActive ? "#F8FAFC" : "#F1F5F9"
        border.color: isActive ? root.colBlue : root.colDivider
        border.width: isActive ? 1.5 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            // Circular badge for step number
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: stepRow.isActive ? root.colBlue : root.colGrey

                Text {
                    anchors.centerIn: parent
                    text: stepRow.stepNumber
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                }
            }

            // Step text details
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: stepRow.stepTitle
                    color: root.colInk
                    font.pixelSize: 11
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: stepRow.instructionText
                    color: root.colCharcoal
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    lineHeight: 1.1
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
        property color baseColor: root.colBlue
        property color textColor: "white"
        property color borderColor: "transparent"
        signal clicked()

        Layout.preferredWidth: 220
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
            font.pixelSize: 15
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
