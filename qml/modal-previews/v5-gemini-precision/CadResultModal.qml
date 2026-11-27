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
    // BendCNC Color Palette
    // -------------------------------------------------------------------------
    readonly property color colPaper: "#F5F5F5"
    readonly property color colCardBg: "#FFFFFF"
    readonly property color colInk: "#232323"
    readonly property color colGrey: "#767676"
    readonly property color colOutline: "#B8B8B8"
    readonly property color colDivider: "#CFCFCF"
    readonly property color colEmerald: "#1B7A5A"
    readonly property color colEmeraldBg: "#E8F4DF"
    readonly property color colOrange: "#D97706"
    readonly property color colCharcoal: "#2B2C2B"
    readonly property color colRed: "#A82011"

    property var resultData: ({
        programName: "Battery Plate N1",
        partName: "Battery Plate N1",
        material: "Steel",
        thickness: "0.0600 in",
        bendCount: 4,
        saved: true,
        storageLabel: "SAVED · backup protected",
        rows: [
            { seq: 1, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "0.9494", reference: "EDGE", status: "OK" },
            { seq: 2, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "0.9494", reference: "EDGE", status: "OK" },
            { seq: 3, angle: "45.0", setup: "STD", tooling: "GN88 / 8mm", bg: "1.2500", reference: "EDGE", status: "OK" },
            { seq: 4, angle: "90.0", setup: "STD", tooling: "GN88 / 8mm", bg: "2.1250", reference: "EDGE", status: "OK" }
        ]
    })

    readonly property bool isSaved: resultData && resultData.saved
    readonly property color headerColor: isSaved ? colEmerald : colOrange

    signal closeRequested()
    signal viewInRunRequested()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // =====================================================================
        // HEADER (Exact height 80px, same top bar color: #1B7A5A or #D97706)
        // Preserves the circular check icon, title, subtitle, and close '×' button
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
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 14

                // Round Check Icon
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 22
                    color: "#26FFFFFF"
                    border.color: "white"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: "white"
                        font.pixelSize: 26
                        font.bold: true
                    }
                }

                // Title + Storage Label
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: qsTr("BEND PROGRAM READY")
                        color: "white"
                        font.pixelSize: 21
                        font.bold: true
                        font.letterSpacing: 0.5
                    }

                    Text {
                        text: root.resultData.storageLabel || (root.isSaved ? qsTr("SAVED · backup protected") : qsTr("UNSAVED DRAFT"))
                        color: "white"
                        opacity: 0.92
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                // Close '×' button
                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 6
                    color: closeMouse.containsMouse ? "#33FFFFFF" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: "white"
                        font.pixelSize: 26
                        font.bold: true
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }
        }

        // =====================================================================
        // CONTENT AREA (Strictly preserves original elements & refined layout)
        // 1. Program Name Title
        // 2. The 3 Chips: PART, MATERIAL, SEQUENCE
        // 3. GENERATED OPERATIONS section title
        // 4. Complete Operations Table with headers: SEQ, ANGLE, SETUP, TOOLING, BG/REF, STATUS
        // =====================================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            spacing: 8

            // Program Name
            Text {
                text: root.resultData.programName || qsTr("Imported Program")
                color: root.colInk
                font.pixelSize: 22
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // The 3 Original Metadata Chips (Refined with clean typography and subtle borders)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // PART Chip
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    color: "#EAEAEA"
                    radius: 4
                    border.color: "#CACACA"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 2

                        Text {
                            text: qsTr("PART")
                            color: root.colGrey
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.4
                        }

                        Text {
                            text: root.resultData.partName || "-"
                            color: root.colInk
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                // MATERIAL Chip
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    color: "#EAEAEA"
                    radius: 4
                    border.color: "#CACACA"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 2

                        Text {
                            text: qsTr("MATERIAL")
                            color: root.colGrey
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.4
                        }

                        Text {
                            text: (root.resultData.material || "-") + " · " + (root.resultData.thickness || "-")
                            color: root.colInk
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                // SEQUENCE Chip
                Rectangle {
                    Layout.preferredWidth: 130
                    Layout.preferredHeight: 52
                    color: "#EAEAEA"
                    radius: 4
                    border.color: "#CACACA"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 2

                        Text {
                            text: qsTr("SEQUENCE")
                            color: root.colGrey
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.4
                        }

                        Text {
                            text: String(root.resultData.bendCount || (root.resultData.rows ? root.resultData.rows.length : 0)) + " bends"
                            color: root.colInk
                            font.pixelSize: 13
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // GENERATED OPERATIONS Section Label
            Text {
                text: qsTr("GENERATED OPERATIONS")
                color: "#5E5E5E"
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.5
            }

            // Operations Table Frame (Exact full-width table container)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#ECECEC"
                border.color: "#C7C7C7"
                border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Table Column Headers (Charcoal background, exact original column ratios)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        color: root.colCharcoal

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            HeaderCell { text: qsTr("SEQ"); widthValue: 56 }
                            HeaderCell { text: qsTr("ANGLE"); widthValue: 74 }
                            HeaderCell { text: qsTr("SETUP"); widthValue: 84 }
                            HeaderCell { text: qsTr("TOOLING"); fillValue: true }
                            HeaderCell { text: qsTr("BG / REF"); widthValue: 120 }
                            HeaderCell { text: qsTr("STATUS"); widthValue: 80 }
                        }
                    }

                    // Table Rows
                    ListView {
                        id: operationsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.resultData.rows || []
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: operationsList.width
                            height: 36
                            color: rowItem.index % 2 === 0 ? "#FFFFFF" : "#F2F2F2"

                            RowLayout {
                                anchors.fill: parent
                                spacing: 0

                                // SEQ
                                DataCell {
                                    text: String(rowItem.modelData.seq)
                                    widthValue: 56
                                    bold: true
                                }

                                // ANGLE
                                DataCell {
                                    text: rowItem.modelData.angle + "°"
                                    widthValue: 74
                                    bold: false
                                }

                                // SETUP
                                DataCell {
                                    text: rowItem.modelData.setup
                                    widthValue: 84
                                }

                                // TOOLING
                                DataCell {
                                    text: rowItem.modelData.tooling
                                    fillValue: true
                                }

                                // BG / REF
                                DataCell {
                                    text: rowItem.modelData.bg + " / " + rowItem.modelData.reference
                                    widthValue: 120
                                }

                                // STATUS (OK in Emerald Green)
                                DataCell {
                                    text: rowItem.modelData.status
                                    widthValue: 80
                                    bold: true
                                    accent: rowItem.modelData.status === "OK" ? root.colEmerald : root.colOrange
                                }
                            }

                            // Subtle row separator
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: "#E0E0E0"
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 8
                        }
                    }
                }
            }

            // =================================================================
            // BOTTOM BAR (Exact layout: text on left + CLOSE & VIEW IN RUN buttons)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                spacing: 12

                // Info text (stored in programs.json)
                Text {
                    Layout.fillWidth: true
                    text: root.isSaved
                        ? qsTr("Stored in programs.json with backup protection.")
                        : qsTr("Available in Run until the application closes.")
                    color: root.isSaved ? root.colEmerald : "#9A5B00"
                    font.pixelSize: 12
                    font.bold: true
                }

                // CLOSE button
                Rectangle {
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 42
                    radius: 4
                    color: closeBtnMouse.containsMouse ? Qt.lighter(root.colCharcoal, 1.15) : root.colCharcoal

                    scale: closeBtnMouse.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 60 } }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("CLOSE")
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 0.5
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }

                // VIEW IN RUN button (Red)
                Rectangle {
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 42
                    radius: 4
                    color: runBtnMouse.containsMouse ? Qt.lighter(root.colRed, 1.15) : root.colRed

                    scale: runBtnMouse.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 60 } }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("VIEW IN RUN")
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 0.5
                    }

                    MouseArea {
                        id: runBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewInRunRequested()
                    }
                }
            }
        }
    }

    // =========================================================================
    // SUB-COMPONENTS FOR TABLE
    // =========================================================================
    component HeaderCell: Item {
        id: hc
        property string text: ""
        property real widthValue: 0
        property bool fillValue: false

        Layout.preferredWidth: fillValue ? -1 : widthValue
        Layout.fillWidth: fillValue
        Layout.fillHeight: true

        Text {
            anchors.centerIn: parent
            text: hc.text
            color: "white"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.4
        }
    }

    component DataCell: Rectangle {
        id: dc
        property string text: ""
        property real widthValue: 0
        property bool fillValue: false
        property bool bold: false
        property color accent: root.colInk

        Layout.preferredWidth: fillValue ? -1 : widthValue
        Layout.fillWidth: fillValue
        Layout.fillHeight: true
        color: "transparent"
        border.color: "#DCDCDC"
        border.width: 1

        Text {
            anchors.centerIn: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            text: dc.text
            color: dc.accent
            font.pixelSize: 11
            font.bold: dc.bold
            elide: Text.ElideRight
        }
    }
}
