import QtQuick
import "modal-previews/v7" as V7

// Production TOOLS tab: renders the v7 designer panel; edits persist through dataStore.
FocusScope {
    id: root
    objectName: "tools-v7-view"
    property var appState: null
    focus: true

    V7.V6ToolsLeftView {
        anchors.fill: parent
        appState: root.appState
        designerInteractive: false
        focus: true
    }
}
