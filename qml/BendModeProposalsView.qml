pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root
    width: 1200
    height: 720

    // Shared mock state for testing mode changes interactively
    property string activeMode: "PROGRAM_BEND_MODE" // "SINGLE_BEND_MODE" | "SINGLE_BEND_REPEAT" | "PROGRAM_BEND_MODE" | "PROGRAM_BEND_LOOP"

    function modeColor(mode) {
        if (mode === "SINGLE_BEND_MODE") return "#10B981"
        if (mode === "SINGLE_BEND_REPEAT") return "#0284C7"
        if (mode === "PROGRAM_BEND_LOOP") return "#8B5CF6"
        return "#EF4444"
    }

    function modeBorderColor(mode) {
        if (mode === "SINGLE_BEND_MODE") return "#059669"
        if (mode === "SINGLE_BEND_REPEAT") return "#0369A1"
        if (mode === "PROGRAM_BEND_LOOP") return "#7C3AED"
        return "#DC2626"
    }

    function modeTitle(mode) {
        if (mode === "SINGLE_BEND_MODE") return qsTr("SINGLE BEND MODE")
        if (mode === "SINGLE_BEND_REPEAT") return qsTr("SINGLE BEND REPEAT")
        if (mode === "PROGRAM_BEND_LOOP") return qsTr("PROGRAM BEND LOOP")
        return qsTr("PROGRAM BEND MODE")
    }

    function modeDetail(mode) {
        if (mode === "SINGLE_BEND_MODE") return qsTr("RUN CURRENT BEND ONCE")
        if (mode === "SINGLE_BEND_REPEAT") return qsTr("REPEAT CURRENT BEND")
        if (mode === "PROGRAM_BEND_LOOP") return qsTr("REPEAT FULL SEQUENCE")
        return qsTr("RUN FULL SEQUENCE ONCE")
    }

    function modeDetailColor(mode) {
        if (mode === "SINGLE_BEND_MODE") return "#A7F3D0"
        if (mode === "SINGLE_BEND_REPEAT") return "#BAE6FD"
        if (mode === "PROGRAM_BEND_LOOP") return "#DDD6FE"
        return "#FCA5A5"
    }

    Rectangle {
        anchors.fill: parent
        color: "#0F1115"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Top Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            ColumnLayout {
                spacing: 2
                Text {
                    text: qsTr("PROGRAM BEND MODE · 4 EXPANSION MENU ITERATIONS")
                    color: "white"
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 0.5
                }
                Text {
                    text: qsTr("Haz clic en cualquier opción dentro de las iteraciones para probar la selección y ver cómo se refleja en el botón inferior.")
                    color: "#94A3B8"
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            // Current Mode Preview Pill
            Rectangle {
                Layout.preferredHeight: 32
                Layout.preferredWidth: 260
                radius: 6
                color: "#181D26"
                border.color: root.modeBorderColor(root.activeMode)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: root.modeColor(root.activeMode)
                    }
                    Text {
                        text: qsTr("ACTIVO: ") + root.modeTitle(root.activeMode)
                        color: "white"
                        font.bold: true
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // 4 Columns: One per Iteration
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // -----------------------------------------------------------------
            // ITERATION 1: Precision Floating Popover
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: "#141720"
                border.color: "#272E3E"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Iteration Header
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 22
                            height: 22
                            radius: 4
                            color: "#1E293B"
                            Text {
                                anchors.centerIn: parent
                                text: "1"
                                color: "#38BDF8"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: qsTr("PRECISION FLOATING DOCK")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                            }
                            Text {
                                text: qsTr("Card flotante con badges de color y check")
                                color: "#64748B"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Iteration 1 Popup Menu
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 258
                        radius: 10
                        color: "#0B0F17"
                        border.color: root.modeBorderColor(root.activeMode)
                        border.width: 1.5

                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 5

                            // Header
                            RowLayout {
                                width: parent.width
                                spacing: 6
                                Rectangle {
                                    width: 4
                                    height: 12
                                    radius: 2
                                    color: root.modeBorderColor(root.activeMode)
                                }
                                Text {
                                    text: qsTr("CYCLE SELECTOR")
                                    color: "#94A3B8"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.letterSpacing: 0.8
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: qsTr("BEND 1/4")
                                    color: "#64748B"
                                    font.bold: true
                                    font.pixelSize: 11
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: "#1E293B"
                            }

                            // Option 1
                            OptionCardV1 {
                                width: parent.width
                                badge: "1"
                                label: qsTr("SINGLE BEND")
                                detail: qsTr("Executes current bend and stops")
                                isSelected: root.activeMode === "SINGLE_BEND_MODE"
                                accent: "#10B981"
                                onClicked: root.activeMode = "SINGLE_BEND_MODE"
                            }

                            // Option 2
                            OptionCardV1 {
                                width: parent.width
                                badge: "1x"
                                label: qsTr("SINGLE REPEAT")
                                detail: qsTr("Continuously repeats active bend")
                                isSelected: root.activeMode === "SINGLE_BEND_REPEAT"
                                accent: "#0284C7"
                                onClicked: root.activeMode = "SINGLE_BEND_REPEAT"
                            }

                            // Option 3
                            OptionCardV1 {
                                width: parent.width
                                badge: "1..N"
                                label: qsTr("PROGRAM ONCE")
                                detail: qsTr("Runs full 1→N sequence once")
                                isSelected: root.activeMode === "PROGRAM_BEND_MODE"
                                accent: "#EF4444"
                                onClicked: root.activeMode = "PROGRAM_BEND_MODE"
                            }

                            // Option 4
                            OptionCardV1 {
                                width: parent.width
                                badge: "LOOP"
                                label: qsTr("PROGRAM LOOP")
                                detail: qsTr("Repeats full sequence continuously")
                                isSelected: root.activeMode === "PROGRAM_BEND_LOOP"
                                accent: "#8B5CF6"
                                onClicked: root.activeMode = "PROGRAM_BEND_LOOP"
                            }
                        }
                    }

                    // Bottom Target Button
                    BendModeButtonView {
                        Layout.fillWidth: true
                        mode: root.activeMode
                        onClicked: {}
                    }
                }
            }

            // -----------------------------------------------------------------
            // ITERATION 2: Integrated Drawer / Sheet (Cajón Segmentado)
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: "#141720"
                border.color: "#272E3E"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Iteration Header
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 22
                            height: 22
                            radius: 4
                            color: "#1E293B"
                            Text {
                                anchors.centerIn: parent
                                text: "2"
                                color: "#10B981"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: qsTr("SEGMENTED DRAWER")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                            }
                            Text {
                                text: qsTr("Acoplado directo, barra lateral y tags de estado")
                                color: "#64748B"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Iteration 2 Popup Drawer (Directly connected to button)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 258
                        radius: 8
                        color: "#0D1117"
                        border.color: root.modeBorderColor(root.activeMode)
                        border.width: 1.5

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Drawer Header
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                color: "#161B22"
                                radius: 8

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 6
                                    Text {
                                        text: qsTr("OPERATION MODE")
                                        color: "#CBD5E1"
                                        font.bold: true
                                        font.pixelSize: 11
                                        font.letterSpacing: 0.6
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        width: 50
                                        height: 16
                                        radius: 3
                                        color: "#21262D"
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("DRAWER")
                                            color: "#8B949E"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            // Drawer Items
                            OptionRowV2 {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                badge: "SINGLE"
                                subBadge: "1 STEP"
                                label: qsTr("SINGLE BEND")
                                detail: qsTr("Executes active bend and halts")
                                isSelected: root.activeMode === "SINGLE_BEND_MODE"
                                accent: "#10B981"
                                onClicked: root.activeMode = "SINGLE_BEND_MODE"
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262D" }

                            OptionRowV2 {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                badge: "REPEAT"
                                subBadge: "CYCLE"
                                label: qsTr("SINGLE REPEAT")
                                detail: qsTr("Repeats active bend continuously")
                                isSelected: root.activeMode === "SINGLE_BEND_REPEAT"
                                accent: "#0284C7"
                                onClicked: root.activeMode = "SINGLE_BEND_REPEAT"
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262D" }

                            OptionRowV2 {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                badge: "PROGRAM"
                                subBadge: "1→N"
                                label: qsTr("PROGRAM ONCE")
                                detail: qsTr("Runs sequence 1..N once")
                                isSelected: root.activeMode === "PROGRAM_BEND_MODE"
                                accent: "#EF4444"
                                onClicked: root.activeMode = "PROGRAM_BEND_MODE"
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#21262D" }

                            OptionRowV2 {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                badge: "LOOP"
                                subBadge: "AUTO"
                                label: qsTr("PROGRAM LOOP")
                                detail: qsTr("Loops entire sequence continuously")
                                isSelected: root.activeMode === "PROGRAM_BEND_LOOP"
                                accent: "#8B5CF6"
                                onClicked: root.activeMode = "PROGRAM_BEND_LOOP"
                            }
                        }
                    }

                    // Bottom Target Button
                    BendModeButtonView {
                        Layout.fillWidth: true
                        mode: root.activeMode
                        onClicked: {}
                    }
                }
            }

            // -----------------------------------------------------------------
            // ITERATION 3: Tactical 2x2 Touch Grid (Malla Táctil Rápida)
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: "#141720"
                border.color: "#272E3E"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Iteration Header
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 22
                            height: 22
                            radius: 4
                            color: "#1E293B"
                            Text {
                                anchors.centerIn: parent
                                text: "3"
                                color: "#F59E0B"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: qsTr("TACTICAL 2x2 TOUCH GRID")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                            }
                            Text {
                                text: qsTr("Malla compacta 2x2, grandes botones para guantes")
                                color: "#64748B"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Iteration 3 2x2 Grid Menu (Shorter height, wider touch pads)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 258
                        radius: 10
                        color: "#0B0F17"
                        border.color: root.modeBorderColor(root.activeMode)
                        border.width: 1.5

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            // Header Bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    width: 4
                                    height: 12
                                    radius: 2
                                    color: root.modeBorderColor(root.activeMode)
                                }
                                Text {
                                    text: qsTr("QUICK TOUCH GRID (2x2)")
                                    color: "#94A3B8"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.letterSpacing: 0.8
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: qsTr("TOUCH OPTIMIZED")
                                    color: "#F59E0B"
                                    font.bold: true
                                    font.pixelSize: 11
                                }
                            }

                            // 2x2 Grid
                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 2
                                rows: 2
                                rowSpacing: 6
                                columnSpacing: 6

                                // Top-Left: Single Bend
                                OptionTileV3 {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    badge: "1"
                                    title: qsTr("SINGLE BEND")
                                    sub: qsTr("Current bend once")
                                    isSelected: root.activeMode === "SINGLE_BEND_MODE"
                                    accent: "#10B981"
                                    onClicked: root.activeMode = "SINGLE_BEND_MODE"
                                }

                                // Top-Right: Single Repeat
                                OptionTileV3 {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    badge: "1x"
                                    title: qsTr("SINGLE REPEAT")
                                    sub: qsTr("Repeat active bend")
                                    isSelected: root.activeMode === "SINGLE_BEND_REPEAT"
                                    accent: "#0284C7"
                                    onClicked: root.activeMode = "SINGLE_BEND_REPEAT"
                                }

                                // Bottom-Left: Program Once
                                OptionTileV3 {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    badge: "1..N"
                                    title: qsTr("PROGRAM ONCE")
                                    sub: qsTr("Full sequence once")
                                    isSelected: root.activeMode === "PROGRAM_BEND_MODE"
                                    accent: "#EF4444"
                                    onClicked: root.activeMode = "PROGRAM_BEND_MODE"
                                }

                                // Bottom-Right: Program Loop
                                OptionTileV3 {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    badge: "LOOP"
                                    title: qsTr("PROGRAM LOOP")
                                    sub: qsTr("Continuous cycles")
                                    isSelected: root.activeMode === "PROGRAM_BEND_LOOP"
                                    accent: "#8B5CF6"
                                    onClicked: root.activeMode = "PROGRAM_BEND_LOOP"
                                }
                            }
                        }
                    }

                    // Bottom Target Button
                    BendModeButtonView {
                        Layout.fillWidth: true
                        mode: root.activeMode
                        onClicked: {}
                    }
                }
            }

            // -----------------------------------------------------------------
            // ITERATION 4: Tactical CNC HUD Flyout (Minimalista Alta Densidad)
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 10
                color: "#141720"
                border.color: "#272E3E"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Iteration Header
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle {
                            width: 22
                            height: 22
                            radius: 4
                            color: "#1E293B"
                            Text {
                                anchors.centerIn: parent
                                text: "4"
                                color: "#A855F7"
                                font.bold: true
                                font.pixelSize: 12
                            }
                        }
                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: qsTr("TACTICAL CNC HUD FLYOUT")
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                            }
                            Text {
                                text: qsTr("Panel técnico minimalista, radio dot y reglas CNC")
                                color: "#64748B"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Iteration 4 HUD Menu
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 258
                        radius: 8
                        color: "#080B11"
                        border.color: root.modeBorderColor(root.activeMode)
                        border.width: 1.5

                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            // HUD Header
                            RowLayout {
                                width: parent.width
                                spacing: 6
                                Text {
                                    text: qsTr("SYS::BEND_SEQUENCE_TARGET")
                                    color: "#64748B"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "Monospace"
                                    Layout.fillWidth: true
                                }
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.modeColor(root.activeMode)
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: "#1F2937"
                            }

                            // Option 1
                            OptionHudV4 {
                                width: parent.width
                                tag: "[ 01 ]"
                                label: qsTr("SINGLE BEND")
                                rule: qsTr("STEP: STOP AT END")
                                isSelected: root.activeMode === "SINGLE_BEND_MODE"
                                accent: "#10B981"
                                onClicked: root.activeMode = "SINGLE_BEND_MODE"
                            }

                            // Option 2
                            OptionHudV4 {
                                width: parent.width
                                tag: "[ 01+ ]"
                                label: qsTr("SINGLE REPEAT")
                                rule: qsTr("REPEAT: CURRENT ONLY")
                                isSelected: root.activeMode === "SINGLE_BEND_REPEAT"
                                accent: "#0284C7"
                                onClicked: root.activeMode = "SINGLE_BEND_REPEAT"
                            }

                            // Option 3
                            OptionHudV4 {
                                width: parent.width
                                tag: "[ 1..N ]"
                                label: qsTr("PROGRAM ONCE")
                                rule: qsTr("SEQ: 1..N BENDS")
                                isSelected: root.activeMode === "PROGRAM_BEND_MODE"
                                accent: "#EF4444"
                                onClicked: root.activeMode = "PROGRAM_BEND_MODE"
                            }

                            // Option 4
                            OptionHudV4 {
                                width: parent.width
                                tag: "[ LOOP ]"
                                label: qsTr("PROGRAM LOOP")
                                rule: qsTr("SEQ: RESTART AUTO")
                                isSelected: root.activeMode === "PROGRAM_BEND_LOOP"
                                accent: "#8B5CF6"
                                onClicked: root.activeMode = "PROGRAM_BEND_LOOP"
                            }
                        }
                    }

                    // Bottom Target Button
                    BendModeButtonView {
                        Layout.fillWidth: true
                        mode: root.activeMode
                        onClicked: {}
                    }
                }
            }
        }
    }

    // =========================================================================
    // COMPONENTS
    // =========================================================================

    // Component: Bottom Target Button matching the live RunView button
    component BendModeButtonView: Rectangle {
        id: btnRoot
        property string mode: "PROGRAM_BEND_MODE"
        signal clicked()

        height: 60
        radius: 8
        color: root.modeColor(mode)
        border.color: root.modeBorderColor(mode)
        border.width: 1.5

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.modeTitle(btnRoot.mode)
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.modeDetail(btnRoot.mode)
                    color: root.modeDetailColor(btnRoot.mode)
                    font.bold: true
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: "#26FFFFFF"

                Text {
                    anchors.centerIn: parent
                    text: "▲"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }
    }

    // Component: OptionCardV1 (Floating Dock Item)
    component OptionCardV1: Rectangle {
        id: cardRoot
        property string badge: "1"
        property string label: ""
        property string detail: ""
        property bool isSelected: false
        property color accent: "#10B981"
        signal clicked()

        height: 50
        radius: 7
        color: isSelected ? "#1E2638" : (cardMouse.containsMouse ? "#141A26" : "transparent")
        border.color: isSelected ? accent : (cardMouse.containsMouse ? "#334155" : "transparent")
        border.width: isSelected ? 1.5 : 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 8

            // Badge
            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 6
                color: cardRoot.isSelected ? cardRoot.accent : "#1E293B"

                Text {
                    anchors.centerIn: parent
                    text: cardRoot.badge
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }
            }

            // Text
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: cardRoot.label
                    color: cardRoot.isSelected ? "white" : "#CBD5E1"
                    font.bold: true
                    font.pixelSize: 11
                }

                Text {
                    text: cardRoot.detail
                    color: cardRoot.isSelected ? "#94A3B8" : "#64748B"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Check circle
            Rectangle {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                radius: 10
                color: cardRoot.isSelected ? cardRoot.accent : "transparent"
                border.color: cardRoot.isSelected ? cardRoot.accent : "#475569"
                border.width: 1.5

                Text {
                    visible: cardRoot.isSelected
                    anchors.centerIn: parent
                    text: "✓"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: cardRoot.clicked()
        }
    }

    // Component: OptionRowV2 (Drawer Row with left bar)
    component OptionRowV2: Rectangle {
        id: rowRoot
        property string badge: ""
        property string subBadge: ""
        property string label: ""
        property string detail: ""
        property bool isSelected: false
        property color accent: "#10B981"
        signal clicked()

        color: isSelected ? "#161E2E" : (rowMouse.containsMouse ? "#121722" : "transparent")

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Left colored indicator bar
            Rectangle {
                Layout.preferredWidth: 4
                Layout.fillHeight: true
                color: rowRoot.isSelected ? rowRoot.accent : "transparent"
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 8

                // Badge Pill
                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 30
                    radius: 4
                    color: rowRoot.isSelected ? Qt.rgba(rowRoot.accent.r, rowRoot.accent.g, rowRoot.accent.b, 0.25) : "#1C2128"
                    border.color: rowRoot.isSelected ? rowRoot.accent : "#30363D"
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: rowRoot.badge
                            color: rowRoot.isSelected ? "white" : "#8B949E"
                            font.bold: true
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: rowRoot.subBadge
                            color: rowRoot.isSelected ? rowRoot.accent : "#484F58"
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }
                }

                // Title & detail
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: rowRoot.label
                        color: rowRoot.isSelected ? "white" : "#C9D1D9"
                        font.bold: true
                        font.pixelSize: 11
                    }
                    Text {
                        text: rowRoot.detail
                        color: rowRoot.isSelected ? "#8B949E" : "#484F58"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // Active status pill
                Rectangle {
                    visible: rowRoot.isSelected
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 18
                    radius: 9
                    color: rowRoot.accent

                    Text {
                        anchors.centerIn: parent
                        text: "ACTIVE"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 11
                    }
                }
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: rowRoot.clicked()
        }
    }

    // Component: OptionTileV3 (2x2 Grid Touch Tile)
    component OptionTileV3: Rectangle {
        id: tileRoot
        property string badge: ""
        property string title: ""
        property string sub: ""
        property bool isSelected: false
        property color accent: "#10B981"
        signal clicked()

        radius: 8
        color: isSelected ? Qt.rgba(tileRoot.accent.r, tileRoot.accent.g, tileRoot.accent.b, 0.22) : (tileMouse.containsMouse ? "#1A2232" : "#131824")
        border.color: isSelected ? tileRoot.accent : (tileMouse.containsMouse ? "#334155" : "#1E293B")
        border.width: isSelected ? 1.5 : 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 18
                    radius: 3
                    color: tileRoot.isSelected ? tileRoot.accent : "#222B3D"

                    Text {
                        anchors.centerIn: parent
                        text: tileRoot.badge
                        color: "white"
                        font.bold: true
                        font.pixelSize: 11
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: tileRoot.isSelected
                    width: 7
                    height: 7
                    radius: 3.5
                    color: tileRoot.accent
                }
            }

            Text {
                text: tileRoot.title
                color: tileRoot.isSelected ? "white" : "#E2E8F0"
                font.bold: true
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: tileRoot.sub
                color: tileRoot.isSelected ? "#94A3B8" : "#64748B"
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: tileRoot.clicked()
        }
    }

    // Component: OptionHudV4 (Tactical Minimalist Item)
    component OptionHudV4: Rectangle {
        id: hudRoot
        property string tag: ""
        property string label: ""
        property string rule: ""
        property bool isSelected: false
        property color accent: "#10B981"
        signal clicked()

        height: 50
        radius: 5
        color: isSelected ? Qt.rgba(hudRoot.accent.r, hudRoot.accent.g, hudRoot.accent.b, 0.15) : (hudMouse.containsMouse ? "#111722" : "transparent")
        border.color: isSelected ? hudRoot.accent : (hudMouse.containsMouse ? "#2A364F" : "#161D2B")
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Text {
                text: hudRoot.tag
                color: hudRoot.isSelected ? hudRoot.accent : "#64748B"
                font.bold: true
                font.family: "Monospace"
                font.pixelSize: 11
                Layout.preferredWidth: 38
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: hudRoot.label
                    color: hudRoot.isSelected ? "white" : "#CBD5E1"
                    font.bold: true
                    font.pixelSize: 11
                }
                Text {
                    text: hudRoot.rule
                    color: hudRoot.isSelected ? hudRoot.accent : "#475569"
                    font.family: "Monospace"
                    font.pixelSize: 11
                }
            }

            // Radio ring
            Rectangle {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                radius: 8
                color: "transparent"
                border.color: hudRoot.isSelected ? hudRoot.accent : "#334155"
                border.width: 1.5

                Rectangle {
                    visible: hudRoot.isSelected
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: hudRoot.accent
                }
            }
        }

        MouseArea {
            id: hudMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: hudRoot.clicked()
        }
    }
}
