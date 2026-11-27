pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: surface
    property string selection: "RIGHT_PANEL"
    property var appState: null
    // Live canvas mode shows the real RunExecutionCanvas instead of the blank
    // placeholder; dataStore supplies its read-only tooling catalogs.
    property bool liveCanvas: false
    property var dataStore: null
    signal pageRequested(int index)
    // Designer versions can pin a page to an older production view.
    property var pageOverrides: ({})
    readonly property var pages: [
        "RunView.qml", "CreateBendView.qml", "ToolsView.qml",
        pageOverrides[3] || "BackGaugeControlView.qml", "ManualModeView.qml",
        "CadImportView.qml", "SettingsView.qml", "ProgramsView.qml"
    ]
    readonly property bool leftSelected: selection.indexOf("LEFT_") === 0
    readonly property int pageIndex: leftSelected ? Number(selection.substring(5)) : -1

    width: 1366
    height: 768

    LayoutMetrics { id: metrics }

    Rectangle { anchors.fill: parent; color: "#F5F5F5" }

    ActionBarView {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 40
        visible: surface.selection === "ACTION_BAR"
        enabled: false
        appState: surface.appState
    }

    ToolBarView {
        id: designerToolBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 50
        visible: surface.selection === "TOOL_BAR"
        enabled: false
        appState: surface.appState
    }

    ActivatorProposalsView {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: designerToolBar.bottom
        anchors.bottom: parent.bottom
        visible: surface.selection === "TOOL_BAR"
    }

    Item {
        x: 20
        y: 95
        width: metrics.columnLeftWidth
        height: metrics.columnLeftHeight
        visible: surface.leftSelected

        Rectangle {
            width: parent.width
            height: metrics.tabHeaderHeight
            radius: 7
            antialiasing: true
            color: "#2B2C2B"
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 7; color: "#2B2C2B" }
            Row {
                anchors.fill: parent
                Repeater {
                    model: metrics.tabLabels.length
                    Rectangle {
                        required property int index
                        width: metrics.tabWidths[index]
                        height: metrics.tabHeaderHeight
                        color: surface.pageIndex === index ? "#A82011" : "transparent"
                        radius: (index === 0 && surface.pageIndex === 0) ? 7 : 0
                        antialiasing: index === 0 && surface.pageIndex === 0

                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.radius
                            color: parent.color
                            visible: index === 0 && surface.pageIndex === 0
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: parent.radius
                            color: parent.color
                            visible: index === 0 && surface.pageIndex === 0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: metrics.tabLabels[index]
                            color: "white"
                            font.bold: true
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: surface.pageRequested(index)
                        }
                    }
                }
            }
        }

        Rectangle {
            y: metrics.tabHeaderHeight
            width: parent.width
            height: parent.height - y
            color: "#E0E0E0"
            radius: 7
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: metrics.contentTopOverlap; color: "#E0E0E0" }
            Loader {
                id: pageLoader
                anchors.fill: parent
                active: surface.leftSelected && surface.pageIndex >= 0
                    && surface.pageIndex < surface.pages.length
                enabled: false
                source: active ? surface.pages[surface.pageIndex] : ""
                onLoaded: {
                    if (item && item.hasOwnProperty("appState"))
                        item.appState = surface.appState
                    if (item && item.hasOwnProperty("designerBlankCanvas")) {
                        item.designerBlankCanvas = Qt.binding(function() { return !surface.liveCanvas })
                        if (item.hasOwnProperty("dataStore") && surface.dataStore)
                            item.dataStore = surface.dataStore
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: pageLoader.status === Loader.Error
                text: qsTr("Unable to load left panel")
                color: "#A82011"
            }
        }
    }

    // The lab is a visual editor, never a control surface for a machine.
    MouseArea {
        anchors.fill: parent
        visible: surface.selection === "ACTION_BAR" || surface.selection === "TOOL_BAR"
            || surface.leftSelected
        acceptedButtons: Qt.AllButtons
        onClicked: function(mouse) {
            if (surface.leftSelected && mouse.y >= 95 && mouse.y < 125) {
                var offset = mouse.x - 20
                for (var i = 0; i < metrics.tabWidths.length; ++i) {
                    offset -= metrics.tabWidths[i]
                    if (offset < 0) {
                        surface.pageRequested(i)
                        break
                    }
                }
            }
        }
    }
}