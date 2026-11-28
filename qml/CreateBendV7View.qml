import QtQuick
import "modal-previews/v7" as V7

// Production CREATE BEND tab: renders the v7 designer panel bound to the live AppState.
FocusScope {
    id: root
    objectName: "create-bend-v7-view"
    property var appState: null
    focus: true

    V7.V7CreateBendLeftView {
        anchors.fill: parent
        appState: root.appState
        focus: true
    }
}
