pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Rectangle {
    id: root
    implicitWidth: 1366
    implicitHeight: 700
    color: "#18191C"

    signal proposalSelected(int optionIndex, string name)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true

                Text {
                    text: qsTr("NUEVAS PROPUESTAS DE DISEÑO: ACTIVADORES CONNECTION BAR (BG & BEND)")
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 17
                }

                Text {
                    text: qsTr("5 nuevas opciones con paleta pura de alto contraste (sin amarillos discordantes): GRIS, VERDE, ROJO")
                    color: "#94A3B8"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                Layout.preferredHeight: 32
                Layout.preferredWidth: 260
                radius: 6
                color: "#25272C"
                border.color: "#3F4248"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 4
                        color: "#2563EB"
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("5 NUEVAS OPCIONES")
                            color: "white"
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // Table Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Text {
                text: qsTr("CONCEPTO / ESTILO")
                color: "#64748B"
                font.bold: true
                font.pixelSize: 11
                Layout.preferredWidth: 230
            }
            Text {
                text: qsTr("ESTADO GRIS (DESCONECTADO)")
                color: "#94A3B8"
                font.bold: true
                font.pixelSize: 11
                Layout.preferredWidth: 320
                Layout.fillWidth: true
            }
            Text {
                text: qsTr("ESTADO VERDE (CONECTADO / READY)")
                color: "#4ADE80"
                font.bold: true
                font.pixelSize: 11
                Layout.preferredWidth: 320
                Layout.fillWidth: true
            }
            Text {
                text: qsTr("ESTADO ROJO (ALARMA / FALLA)")
                color: "#F87171"
                font.bold: true
                font.pixelSize: 11
                Layout.preferredWidth: 320
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#2B2D31"
        }

        // ---------------------------------------------------------------------
        // OPCIÓN 1: PRECISION CNC SLOT (Canal Mecanizado CNC con Riel Inferior)
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 230
                spacing: 2
                Text { text: qsTr("1. PRECISION CNC SLOT"); color: "#F1F5F9"; font.bold: true; font.pixelSize: 13 }
                Text { text: qsTr("Base oscura mecanizada con riel inferior luminoso en color de estado y badge oscuro"); color: "#94A3B8"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }

            Opt1Pill { prefix: "BG"; label: "CONNECT"; stateColor: "#6B7280"; isConnected: false; isAlarm: false; Layout.fillWidth: true }
            Opt1Pill { prefix: "BG"; label: "BACK GAUGE"; stateColor: "#22C55E"; isConnected: true; isAlarm: false; Layout.fillWidth: true }
            Opt1Pill { prefix: "BEND"; label: "LS-BEND · ALARM"; stateColor: "#EF4444"; isConnected: true; isAlarm: true; Layout.fillWidth: true }
        }

        // ---------------------------------------------------------------------
        // OPCIÓN 2: DUAL-TONE ARCHITECTURAL (División Tonal 25/75 con Separador)
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 230
                spacing: 2
                Text { text: qsTr("2. DUAL-TONE SPLIT"); color: "#F1F5F9"; font.bold: true; font.pixelSize: 13 }
                Text { text: qsTr("Bloque izquierdo carbón para prefijo + cuerpo derecho 100% saturado en color de estado"); color: "#94A3B8"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }

            Opt2Pill { prefix: "BG"; label: "CONNECT"; stateColor: "#4B5563"; borderColor: "#6B7280"; isConnected: false; isAlarm: false; Layout.fillWidth: true }
            Opt2Pill { prefix: "BG"; label: "BACK GAUGE"; stateColor: "#15803D"; borderColor: "#22C55E"; isConnected: true; isAlarm: false; Layout.fillWidth: true }
            Opt2Pill { prefix: "BEND"; label: "LS-BEND · ALARM"; stateColor: "#B91C1C"; borderColor: "#EF4444"; isConnected: true; isAlarm: true; Layout.fillWidth: true }
        }

        // ---------------------------------------------------------------------
        // OPCIÓN 3: CLEAN FROSTED GLASS (Acrílico Técnico Esmerilado)
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 230
                spacing: 2
                Text { text: qsTr("3. FROSTED GLASS"); color: "#F1F5F9"; font.bold: true; font.pixelSize: 13 }
                Text { text: qsTr("Fondo grafito esmerilado con marco vivo de 1.5px y faro LED en el color de estado"); color: "#94A3B8"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }

            Opt3Pill { prefix: "BG"; label: "CONNECT"; stateColor: "#6B7280"; tintBg: "#1F242C"; isConnected: false; isAlarm: false; Layout.fillWidth: true }
            Opt3Pill { prefix: "BG"; label: "BACK GAUGE"; stateColor: "#22C55E"; tintBg: "#064E3B"; isConnected: true; isAlarm: false; Layout.fillWidth: true }
            Opt3Pill { prefix: "BEND"; label: "LS-BEND · ALARM"; stateColor: "#EF4444"; tintBg: "#450A0A"; isConnected: true; isAlarm: true; Layout.fillWidth: true }
        }

        // ---------------------------------------------------------------------
        // OPCIÓN 4: SOLID MATTE SWITCH PAD (Pulsador Industrial Sólido con Bisel)
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 230
                spacing: 2
                Text { text: qsTr("4. SOLID MATTE PAD"); color: "#F1F5F9"; font.bold: true; font.pixelSize: 13 }
                Text { text: qsTr("Superficie mate sólida de alta presencia con badge embutido y botón circular blanco"); color: "#94A3B8"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }

            Opt4Pill { prefix: "BG"; label: "CONNECT"; stateColor: "#525866"; highlightColor: "#6B7280"; isConnected: false; isAlarm: false; Layout.fillWidth: true }
            Opt4Pill { prefix: "BG"; label: "BACK GAUGE"; stateColor: "#167A00"; highlightColor: "#38A116"; isConnected: true; isAlarm: false; Layout.fillWidth: true }
            Opt4Pill { prefix: "BEND"; label: "LS-BEND · ALARM"; stateColor: "#A82011"; highlightColor: "#DC2626"; isConnected: true; isAlarm: true; Layout.fillWidth: true }
        }

        // ---------------------------------------------------------------------
        // OPCIÓN 5: AERO EDGE RIBBON (Cinta Perimetral Anclada en el Borde)
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 230
                spacing: 2
                Text { text: qsTr("5. AERO EDGE RIBBON"); color: "#F1F5F9"; font.bold: true; font.pixelSize: 13 }
                Text { text: qsTr("Cinta vertical anclada en el borde izquierdo (6px) con chip de estado y botón circular"); color: "#94A3B8"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }

            Opt5Pill { prefix: "BG"; label: "CONNECT"; stateColor: "#9CA3AF"; isConnected: false; isAlarm: false; Layout.fillWidth: true }
            Opt5Pill { prefix: "BG"; label: "BACK GAUGE"; stateColor: "#22C55E"; isConnected: true; isAlarm: false; Layout.fillWidth: true }
            Opt5Pill { prefix: "BEND"; label: "LS-BEND · ALARM"; stateColor: "#EF4444"; isConnected: true; isAlarm: true; Layout.fillWidth: true }
        }

        Item { Layout.fillHeight: true }
    }

    // =========================================================================
    // COMPONENT IMPLEMENTATIONS (PURE HARMONY - ZERO YELLOW)
    // =========================================================================

    // --- OPCIÓN 1: PRECISION CNC SLOT ---
    component Opt1Pill: Rectangle {
        id: opt1
        property string prefix: "BG"
        property string label: ""
        property color stateColor: "#22C55E"
        property bool isConnected: false
        property bool isAlarm: false

        implicitWidth: 310
        implicitHeight: 40
        Layout.preferredWidth: 310
        Layout.preferredHeight: 40
        Layout.fillWidth: true
        radius: 6
        color: "#1E2228"
        border.color: "#333742"
        border.width: 1
        clip: true

        // Colored bottom indicator rail (3px)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            color: opt1.stateColor
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            anchors.bottomMargin: 7
            spacing: 8

            Rectangle {
                Layout.preferredWidth: opt1.prefix === "BG" ? 38 : 54
                Layout.fillHeight: true
                radius: 4
                color: "#111317"
                border.color: "#2C313A"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: opt1.prefix
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            Text {
                text: opt1.label
                color: "#FFFFFF"
                font.bold: true
                font.pixelSize: 13
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                color: "#282C34"
                border.color: "#424854"
                border.width: 1
                opacity: opt1.isConnected ? 1.0 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: opt1.isAlarm ? "!" : "✕"
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }
    }

    // --- OPCIÓN 2: DUAL-TONE ARCHITECTURAL SPLIT ---
    component Opt2Pill: Rectangle {
        id: opt2
        property string prefix: "BG"
        property string label: ""
        property color stateColor: "#15803D"
        property color borderColor: "#22C55E"
        property bool isConnected: false
        property bool isAlarm: false

        implicitWidth: 310
        implicitHeight: 40
        Layout.preferredWidth: 310
        Layout.preferredHeight: 40
        Layout.fillWidth: true
        radius: 6
        color: opt2.stateColor
        border.color: opt2.borderColor
        border.width: 1
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Dark Left Prefix Block
            Rectangle {
                Layout.preferredWidth: opt2.prefix === "BG" ? 44 : 60
                Layout.fillHeight: true
                color: "#111317"

                Text {
                    anchors.centerIn: parent
                    text: opt2.prefix
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 12
                }

                // Vertical hairline divider
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: "#40FFFFFF"
                }
            }

            // Right Body Block
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 10
                Layout.rightMargin: 6
                spacing: 8

                Text {
                    text: opt2.label
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 12
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: "#59000000"
                    border.color: "#40FFFFFF"
                    border.width: 1
                    opacity: opt2.isConnected ? 1.0 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: opt2.isAlarm ? "!" : "✕"
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // --- OPCIÓN 3: CLEAN FROSTED GLASS ---
    component Opt3Pill: Rectangle {
        id: opt3
        property string prefix: "BG"
        property string label: ""
        property color stateColor: "#22C55E"
        property color tintBg: "#064E3B"
        property bool isConnected: false
        property bool isAlarm: false

        implicitWidth: 310
        implicitHeight: 40
        Layout.preferredWidth: 310
        Layout.preferredHeight: 40
        Layout.fillWidth: true
        radius: 7
        color: opt3.tintBg
        border.color: opt3.stateColor
        border.width: 1.5

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 8

            // Radiant Status Beacon Dot (Same Hue as State)
            Rectangle {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                color: opt3.stateColor

                // Subtle beacon glow ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.color: opt3.stateColor
                    border.width: 1
                    opacity: opt3.isConnected ? 0.6 : 0.2
                }
            }

            Text {
                text: opt3.prefix
                color: "#FFFFFF"
                font.bold: true
                font.pixelSize: 13
            }

            Text {
                text: "·"
                color: "#99FFFFFF"
                font.bold: true
                font.pixelSize: 14
            }

            Text {
                text: opt3.label
                color: "#FFFFFF"
                font.bold: true
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 5
                color: "#26FFFFFF"
                border.color: "#40FFFFFF"
                border.width: 1
                opacity: opt3.isConnected ? 1.0 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: opt3.isAlarm ? "!" : "✕"
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }
    }

    // --- OPCIÓN 4: SOLID MATTE SWITCH PAD ---
    component Opt4Pill: Rectangle {
        id: opt4
        property string prefix: "BG"
        property string label: ""
        property color stateColor: "#167A00"
        property color highlightColor: "#38A116"
        property bool isConnected: false
        property bool isAlarm: false

        implicitWidth: 310
        implicitHeight: 40
        Layout.preferredWidth: 310
        Layout.preferredHeight: 40
        Layout.fillWidth: true
        radius: 8
        color: opt4.stateColor
        border.color: opt4.highlightColor
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 8

            // Recessed badge
            Rectangle {
                Layout.preferredWidth: opt4.prefix === "BG" ? 36 : 52
                Layout.fillHeight: true
                radius: 5
                color: "#181A1E"

                Text {
                    anchors.centerIn: parent
                    text: opt4.prefix
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            Text {
                text: opt4.label
                color: "#FFFFFF"
                font.bold: true
                font.pixelSize: 13
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: "#4D000000"
                border.color: "#40FFFFFF"
                border.width: 1
                opacity: opt4.isConnected ? 1.0 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: opt4.isAlarm ? "!" : "✕"
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }
    }

    // --- OPCIÓN 5: AERO EDGE RIBBON ---
    component Opt5Pill: Rectangle {
        id: opt5
        property string prefix: "BG"
        property string label: ""
        property color stateColor: "#22C55E"
        property bool isConnected: false
        property bool isAlarm: false

        implicitWidth: 310
        implicitHeight: 40
        Layout.preferredWidth: 310
        Layout.preferredHeight: 40
        Layout.fillWidth: true
        radius: 6
        color: "#20242C"
        border.color: "#303642"
        border.width: 1
        clip: true

        // Anchored Left Edge Ribbon (6px)
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 6
            color: opt5.stateColor
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 6
            spacing: 8

            Text {
                text: opt5.prefix
                color: "#FFFFFF"
                font.bold: true
                font.pixelSize: 13
            }

            Text {
                text: "│"
                color: "#40FFFFFF"
                font.pixelSize: 12
            }

            Text {
                text: opt5.label
                color: "#FFFFFF"
                font.bold: true
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // State Badge Chip
            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                color: opt5.isConnected ? opt5.stateColor : "#374151"
                opacity: opt5.isConnected ? 1.0 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: opt5.isAlarm ? "!" : (opt5.isConnected ? "✕" : "·")
                    color: "#FFFFFF"
                    font.bold: true
                    font.pixelSize: 11
                }
            }
        }
    }
}
