pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
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
    readonly property color colRedBg: "#FDF2F2"
    readonly property color colGreen: "#1B7A5A"
    readonly property color colGreenBright: "#59A60C"
    readonly property color colGreenBg: "#EBF7E5"
    readonly property color colBlue: "#2D83B2"
    readonly property color colBlueBg: "#EBF4F9"
    readonly property color colCharcoal: "#2B2C2B"
    readonly property color colCharcoalRaised: "#3F403F"
    readonly property color colPaper: "#F5F5F5"
    readonly property color colCardBg: "#FFFFFF"
    readonly property color colCardMuted: "#EAEAEA"
    readonly property color colInk: "#232323"
    readonly property color colGrey: "#767676"
    readonly property color colGreyLight: "#A8A8A8"
    readonly property color colOutline: "#B8B8B8"
    readonly property color colDivider: "#D3D3D3"
    readonly property color colAmber: "#D97706"
    readonly property color colAmberBg: "#FEF3C7"

    // Header color variation: "RED" (standard safety red) or "BLUE"
    property string headerTheme: "RED" // "RED" | "BLUE"
    readonly property color headerColor: headerTheme === "RED" ? colRed : colBlue

    // Wizard phase: 1 = Preparation / Safety Requirements, 2 = Active Bleed Procedure
    property int wizardStep: 2

    // Interactive switch states (simulated or real)
    property bool leftHeld: false
    property bool rightHeld: false

    // Action signals matching original Java actions
    signal continueToBleedRequested()
    signal killHydraulicPowerRequested()
    signal exitProcedureRequested()
    signal completeRequested()
    signal cancelRequested()
    signal leftToggleRequested()
    signal rightToggleRequested()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // =====================================================================
        // HEADER (Height: 80px, radius 12 with squared bottom corners)
        // Title: BLEED HYDRAULICS WIZARD (from Java Popup.BleedHydraulics.Title)
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

                // Warning / Hydraulic Icon Badge
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 22
                    color: "#26FFFFFF"
                    border.color: "white"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: "⚠"
                        color: "white"
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                // Title + Subtitle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        spacing: 8
                        Text {
                            text: qsTr("BLEED HYDRAULICS WIZARD")
                            color: "white"
                            font.pixelSize: 22
                            font.bold: true
                            font.letterSpacing: 0.5
                        }

                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: stepTagText.implicitWidth + 12
                            radius: 4
                            color: "#33FFFFFF"

                            Text {
                                id: stepTagText
                                anchors.centerIn: parent
                                text: root.wizardStep === 1
                                    ? qsTr("STEP 1 OF 2 · PREPARATION")
                                    : qsTr("STEP 2 OF 2 · ACTIVE PURGE")
                                color: "white"
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        text: root.wizardStep === 1
                            ? qsTr("System preparation, fairing removal and mechanical safety checklist")
                            : qsTr("Bleed Hydraulics Mode is Enabled · Manual cylinder air purge protocol")
                        color: "white"
                        opacity: 0.92
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                // Live safety status chip
                Rectangle {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: 160
                    radius: 15
                    color: "#26FFFFFF"
                    border.color: "white"
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: root.wizardStep === 1
                                ? "#FDE047"
                                : ((root.leftHeld || root.rightHeld) ? "#86EFAC" : "#FDE047")
                        }

                        Text {
                            text: root.wizardStep === 1
                                ? qsTr("PREPARATION STAGE")
                                : ((root.leftHeld || root.rightHeld) ? qsTr("PRIMING ACTIVE") : qsTr("PRIMING STANDBY"))
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }

                // Close '×' button
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 6
                    color: closeArea.containsMouse ? "#33FFFFFF" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: "white"
                        font.pixelSize: 26
                        font.bold: true
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelRequested()
                    }
                }
            }
        }

        // =====================================================================
        // CONTENT AREA (Two-column layout, Height: 440px)
        // Left Column: Interactive Palm Controls & Critical Safety Box
        // Right Column: Authentic Java Step Instructions & Navigation
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 14

            // -----------------------------------------------------------------
            // LEFT COLUMN (Width: 460px): CONTROLS & PHYSICAL SAFEGUARDS
            // -----------------------------------------------------------------
            Rectangle {
                Layout.preferredWidth: 460
                Layout.fillHeight: true
                radius: 8
                color: root.colCardBg
                border.color: root.colOutline
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Left Column Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.wizardStep === 2
                                ? qsTr("PALM SWITCH PRIMING STATIONS")
                                : qsTr("PRE-BLEED SAFETY VERIFICATION")
                            color: root.colInk
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.4
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            Layout.preferredHeight: 20
                            Layout.preferredWidth: leftTag.implicitWidth + 12
                            radius: 10
                            color: root.wizardStep === 2 ? root.colBlueBg : root.colAmberBg
                            border.color: root.wizardStep === 2 ? root.colBlue : root.colAmber
                            border.width: 1

                            Text {
                                id: leftTag
                                anchors.centerIn: parent
                                text: root.wizardStep === 2 ? qsTr("INDEPENDENT") : qsTr("MANDATORY")
                                color: root.wizardStep === 2 ? root.colBlue : root.colAmber
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }

                    // Content based on wizard step
                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: root.wizardStep === 1 ? 0 : 1

                        // Step 1 Left View: Safety Inspection & Required Tools
                        ColumnLayout {
                            spacing: 10

                            // Critical Punch & Die Warning Box (Direct from Java step1.md)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 6
                                color: "#FEF2F2"
                                border.color: root.colRed
                                border.width: 1.5

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    RowLayout {
                                        spacing: 8
                                        Text { text: "⛔"; font.pixelSize: 20 }
                                        Text {
                                            text: qsTr("MANDATORY: REMOVE ALL PUNCHES & DIES")
                                            color: root.colRed
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: qsTr("While movement might be slow, the ram is still capable of moving downward under pressure during the bleeding procedure.\n\nFOR YOUR SAFETY, DO NOT PLACE ANY PART OF THE BODY BETWEEN THE RAM AND TABLE OF YOUR MACHINE.")
                                        color: "#7F1D1D"
                                        font.pixelSize: 11
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.2
                                    }
                                }
                            }

                            // Tool & Hardware Checklist
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 110
                                radius: 6
                                color: "#F8FAFC"
                                border.color: root.colDivider
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    Text {
                                        text: qsTr("HARDWARE & TOOLING CHECKLIST")
                                        color: root.colCharcoal
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    RowLayout {
                                        spacing: 8
                                        Text { text: "🔧"; font.pixelSize: 14 }
                                        Text {
                                            text: qsTr("9/16\" open-end wrench required for bleeder screws.")
                                            color: root.colInk
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    RowLayout {
                                        spacing: 8
                                        Text { text: "🛡"; font.pixelSize: 14 }
                                        Text {
                                            text: qsTr("Both Fairing Covers removed to access bleeder hose assembly.")
                                            color: root.colInk
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }

                        // Step 2 Left View: Dual Interactive Palm Switches (Right & Left)
                        ColumnLayout {
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Each palm switch independently operates one hydraulic ram while held. Once motor spins, crack bleeder screw open at least 1/4 turn.")
                                color: root.colCharcoal
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                lineHeight: 1.15
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10

                                // RIGHT HAND RAM (Java step 2 starts with Right Hand Ram!)
                                PalmSwitchCard {
                                    id: rightCard
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    sideLabel: qsTr("RIGHT PALM SWITCH")
                                    cylinderLabel: qsTr("RIGHT HYDRAULIC RAM")
                                    cylinderTag: qsTr("START HERE · RIGHT (Y2)")
                                    isHeld: root.rightHeld
                                    onToggleRequested: root.rightToggleRequested()
                                }

                                // LEFT HAND RAM
                                PalmSwitchCard {
                                    id: leftCard
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    sideLabel: qsTr("LEFT PALM SWITCH")
                                    cylinderLabel: qsTr("LEFT HYDRAULIC RAM")
                                    cylinderTag: qsTr("REPEAT NEXT · LEFT (Y1)")
                                    isHeld: root.leftHeld
                                    onToggleRequested: root.leftToggleRequested()
                                }
                            }

                            // Persistent Safety Box during Step 2
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                radius: 6
                                color: root.colRedBg
                                border.color: root.colRed
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: "⚠"
                                        color: root.colRed
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: qsTr("FOR YOUR SAFETY: DO NOT place any part of the body between the ram and table during the bleeding procedure.")
                                        color: "#991B1B"
                                        font.pixelSize: 10
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.1
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN (Fill remaining ~440px): AUTHENTIC JAVA INSTRUCTIONS
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
                    spacing: 8

                    // Step Phase Switcher Tab Bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 4
                            color: root.wizardStep === 1 ? root.colCharcoal : "#E5E5E5"

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("1. PREPARATION")
                                color: root.wizardStep === 1 ? "white" : root.colInk
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.wizardStep = 1
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 4
                            color: root.wizardStep === 2 ? root.colCharcoal : "#E5E5E5"

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("2. BLEED PROCEDURE")
                                color: root.wizardStep === 2 ? "white" : root.colInk
                                font.pixelSize: 11
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.wizardStep = 2
                            }
                        }
                    }

                    // Instruction Content matching step1.md and step2.md
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: contentCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: contentCol
                            width: parent.width
                            spacing: 8

                            // =================================================
                            // STEP 1 CONTENT (from original step1.md)
                            // =================================================
                            ColumnLayout {
                                visible: root.wizardStep === 1
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("The following procedure can be used to bleed the air out of the hydraulic system. The procedure will permit manual operation of both hydraulic cylinders separately so that the bleeder screws can be cracked open in order to circulate hydraulic fluid back into the reservoir until all air bubbles are removed from the system.")
                                    color: root.colInk
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.25
                                }

                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.colDivider }

                                JavaStepCard {
                                    stepNum: "1"
                                    titleText: qsTr("Remove All Punches & Dies")
                                    bodyText: qsTr("In order to continue, you will need to REMOVE ALL PUNCHES & DIES from your machine. While the movement might be slow, the ram is still capable of moving downward under pressure during the bleeding procedure.")
                                    isWarning: true
                                }

                                JavaStepCard {
                                    stepNum: "2"
                                    titleText: qsTr("Remove Fairing Covers")
                                    bodyText: qsTr("Remove both fairing covers from the left and right hydraulic cylinders and locate the bleeder screw/hose assembly.")
                                }

                                JavaStepCard {
                                    stepNum: "3"
                                    titleText: qsTr("Obtain 9/16\" Wrench")
                                    bodyText: qsTr("Obtain a 9/16\" open-end wrench to loosen and tighten the bleeder screw assembly.")
                                }
                            }

                            // =================================================
                            // STEP 2 CONTENT (from original step2.md)
                            // =================================================
                            ColumnLayout {
                                visible: root.wizardStep === 2
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Bleed Hydraulics Mode is now Enabled. Follow the steps below to Bleed each hydraulic ram separately until both are completed.")
                                    color: root.colInk
                                    font.pixelSize: 12
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.2
                                }

                                // Java Step 2 - Instruction 1 (Right Hand Ram)
                                JavaStepCard {
                                    stepNum: "1"
                                    titleText: qsTr("Right Hand Hydraulic Ram")
                                    bodyText: qsTr("Start with the Right Hand Hydraulic Ram. Press and hold down the Right Hand palm safety switch. Once the Right Hand Servo motor can be heard spinning, with the palm switch still pressed down, unscrew the bleeder screw at least 1/4 turn with the 9/16\" wrench. Hydraulic fluid and air bubbles should now start traveling through the bleeder hose back into the reservoir tank.")
                                }

                                // Java Step 2 - Instruction 2 (Seal Right Hand)
                                JavaStepCard {
                                    stepNum: "2"
                                    titleText: qsTr("Tighten Bleeder & Re-attach Cover")
                                    bodyText: qsTr("Once all air bubbles have stopped flowing, with the palm switch still pressed down, tighten the bleeder screw. Once tightened, the palm switch can now be released. Re-attach the Right Hand Fairing Cover.")
                                }

                                // Java Step 2 - Instruction 3 (Left Hand Ram & Home)
                                JavaStepCard {
                                    stepNum: "3"
                                    titleText: qsTr("Repeat for Left Hand & Home Machine")
                                    bodyText: qsTr("Repeat the above procedure for the Left Hand Hydraulic Ram. After completion, exit this Wizard and Home the machine to continue normal operation.")
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 6
                        }
                    }
                }
            }
        }

        // =====================================================================
        // FOOTER (Height: 74px, Exact buttons from original Java Wizard)
        // Step 1: CONTINUE TO BLEED PROCEDURE / CANCEL
        // Step 2: KILL HYDRAULIC POWER / EXIT BLEED PROCEDURE
        // =====================================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 74
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

                // -------------------------------------------------------------
                // Buttons for STEP 1
                // -------------------------------------------------------------
                HarmonizedButton {
                    visible: root.wizardStep === 1
                    text: qsTr("CANCEL")
                    baseColor: root.colCardMuted
                    textColor: root.colCharcoal
                    borderColor: root.colGrey
                    onClicked: root.cancelRequested()
                }

                HarmonizedButton {
                    visible: root.wizardStep === 1
                    text: qsTr("CONTINUE TO BLEED PROCEDURE")
                    baseColor: root.colRed
                    textColor: "white"
                    onClicked: {
                        root.wizardStep = 2
                        root.continueToBleedRequested()
                    }
                }

                // -------------------------------------------------------------
                // Buttons for STEP 2 (from Java step2.md & i18n properties)
                // -------------------------------------------------------------
                HarmonizedButton {
                    visible: root.wizardStep === 2
                    text: qsTr("KILL HYDRAULIC POWER")
                    baseColor: root.colRed
                    textColor: "white"
                    onClicked: root.killHydraulicPowerRequested()
                }

                HarmonizedButton {
                    visible: root.wizardStep === 2
                    text: qsTr("EXIT BLEED PROCEDURE")
                    baseColor: root.colCharcoal
                    textColor: "white"
                    onClicked: root.exitProcedureRequested()
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
        property bool isHeld: false
        signal toggleRequested()

        radius: 8
        color: isHeld ? root.colGreenBg : "#F8FAFC"
        border.color: isHeld ? root.colGreenBright : root.colOutline
        border.width: isHeld ? 2 : 1

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Text {
                text: card.sideLabel
                color: root.colInk
                font.pixelSize: 11
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle {
                Layout.preferredHeight: 18
                Layout.preferredWidth: tagText.implicitWidth + 10
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
                Layout.preferredWidth: 130
                Layout.preferredHeight: 56
                Layout.alignment: Qt.AlignHCenter
                radius: 28
                color: card.isHeld ? root.colGreenBright : (btnMouse.containsMouse ? "#E2E8F0" : "#CBD5E1")
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
                        font.pixelSize: 18
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: card.isHeld ? qsTr("HELD / ACTIVE") : qsTr("PRESS & HOLD")
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
                Layout.preferredHeight: 26
                radius: 13
                color: card.isHeld ? root.colGreenBright : root.colCharcoalRaised

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: card.isHeld ? "white" : root.colGreyLight
                    }

                    Text {
                        text: card.isHeld ? qsTr("PRIMING · ACTIVE") : qsTr("RELEASED · STOPPED")
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENT: JavaStepCard (Step detail card with exact wording)
    // =========================================================================
    component JavaStepCard: Rectangle {
        id: sc
        property string stepNum: "1"
        property string titleText: ""
        property string bodyText: ""
        property bool isWarning: false

        Layout.fillWidth: true
        Layout.preferredHeight: colDetail.implicitHeight + 16
        radius: 6
        color: sc.isWarning ? "#FFF5F5" : "#F8FAFC"
        border.color: sc.isWarning ? root.colRed : root.colDivider
        border.width: sc.isWarning ? 1.5 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: sc.isWarning ? root.colRed : root.colCharcoal

                Text {
                    anchors.centerIn: parent
                    text: sc.stepNum
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            ColumnLayout {
                id: colDetail
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: sc.titleText
                    color: sc.isWarning ? root.colRed : root.colInk
                    font.pixelSize: 11
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: sc.bodyText
                    color: root.colCharcoal
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
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

        Layout.preferredWidth: 240
        Layout.preferredHeight: 46
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
            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 0.4
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
